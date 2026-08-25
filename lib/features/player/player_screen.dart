import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/data/media_repository.dart';
import '../media/domain/playback_history.dart';
import '../media/domain/video_file.dart';
import '../media/presentation/media_providers.dart';
import 'ai_subtitle_preferences.dart';
import 'ai_subtitle_service.dart';
import 'capture_service.dart';
import 'precision_scrubber.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.file});
  final VideoFile file;
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _pipChannel = MethodChannel('com.novaplay/player');
  late final Player player;
  late final VideoController controller;
  Timer? _hideTimer;
  Timer? _statusTimer;
  Timer? _seekIndicatorTimer;
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  StreamSubscription<List<String>>? _embeddedSubtitleSubscription;
  StreamSubscription<bool>? _playingSubscription;
  bool controlsVisible = true;
  bool locked = false;
  bool _hudVisible = false;
  String _hudLabel = '';
  IconData _hudIcon = Icons.brightness_6_rounded;
  double _brightness = .55;
  double _volume = .55;
  Offset? _gestureStart;
  Duration? _seekPreview;
  double _startBrightness = .55;
  double _startVolume = .55;
  bool dialogueEnhancer = false;
  bool captureBusy = false;
  bool orientationLocked = false;
  bool landscapeLocked = false;
  String aspectMode = 'Fit';
  double zoom = 1.0;
  double _baseZoom = 1.0;
  int batteryPercent = 0;
  String systemTime = '';
  final captureService = const CaptureService();
  final aiSubtitleService = AiSubtitleService();
  Timer? _subtitleTimer;
  Timer? _resumeSaveTimer;
  bool aiSubtitlesEnabled = false;
  String aiSubtitleLanguage = 'English';
  double aiSubtitleFontScale = 1.0;
  AiCaption? _activeCaption;
  bool _subtitleRequestInFlight = false;
  String? _embeddedSubtitleText;
  int _seekIndicatorSeconds = 0;
  int _seekIndicatorDirection = 1;
  int _seekIndicatorNonce = 0;
  bool _seekIndicatorVisible = false;
  Duration? _queuedSeekPosition;
  Future<void> _seekQueue = Future<void>.value();
  final resumeRepository = const MediaRepository();
  bool _resumeRestored = false;

  @override
  void initState() {
    super.initState();
    player = Player(configuration: const PlayerConfiguration(pitch: true));
    controller = VideoController(player);
    _openMediaAndRestoreResume();
    _loadAiSubtitlePreferences();
    WakelockPlus.enable();
    _enableAutoOrientation();
    _loadSystemLevels();
    _loadDeviceStatus();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _loadDeviceStatus(),
    );
    _sensorSubscription = accelerometerEventStream().listen(
      _onAccelerometerEvent,
    );
    _embeddedSubtitleSubscription = player.stream.subtitle.listen((lines) {
      if (!mounted) return;
      final text = lines.join('\n').trim();
      _embeddedSubtitleText = text.isEmpty ? null : text;
      if (text.isEmpty) {
        setState(() => _activeCaption = null);
        return;
      }
      final position = player.state.position;
      setState(
        () => _activeCaption = AiCaption(
          text: text,
          start: position,
          end: position + const Duration(seconds: 6),
        ),
      );
      if (aiSubtitlesEnabled) _requestSubtitle();
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      if (!playing) _saveResumePosition();
    });
    _resumeSaveTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _saveResumePosition(),
    );
    _armControlsTimer();
  }

  Future<void> _openMediaAndRestoreResume() async {
    await player.open(Media(widget.file.path), play: true);
    if (!mounted) return;
    await player.setSubtitleTrack(SubtitleTrack.no());
    final history = await resumeRepository.readPlaybackHistory();
    final entry = history[widget.file.id];
    final resume = entry?.position ?? widget.file.progress;
    final duration = await _waitForMediaDuration();
    final effectiveDuration = duration > Duration.zero
        ? duration
        : entry?.totalDuration ?? widget.file.duration;
    if (resume <= const Duration(seconds: 5) ||
        (effectiveDuration > Duration.zero &&
            resume.inMilliseconds * 100 >=
                effectiveDuration.inMilliseconds * 95)) {
      _resumeRestored = true;
      return;
    }

    // MediaKit may complete open() before the stream duration is populated.
    // Pause, apply the saved position after readiness, then explicitly resume.
    await player.pause();
    await player.seek(resume);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await player.play();
    _resumeRestored = true;
    if (!mounted) return;
    final label = formatResumeTime(resume);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Resumed from $label'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Restart',
            onPressed: _restartFromBeginning,
          ),
        ),
      );
  }

  Future<Duration> _waitForMediaDuration() async {
    final current = player.state.duration;
    if (current > Duration.zero) return current;
    try {
      return await player.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return player.state.duration;
    } catch (_) {
      return player.state.duration;
    }
  }

  Future<void> _restartFromBeginning() async {
    await player.seek(Duration.zero);
    await _saveResumePosition();
  }

  Future<void> _saveResumePosition({bool updateLibrary = true}) async {
    if (!_resumeRestored) return;
    final duration = player.state.duration;
    final position = player.state.position;
    if (duration <= Duration.zero && position <= Duration.zero) return;
    final totalDuration = duration > Duration.zero
        ? duration
        : widget.file.duration;
    if (updateLibrary && mounted) {
      await ref
          .read(mediaLibraryProvider.notifier)
          .saveProgress(widget.file, position, totalDuration: totalDuration);
    } else {
      await resumeRepository.savePlaybackPosition(
        id: widget.file.id,
        position: position,
        totalDuration: totalDuration,
      );
    }
  }

  Future<void> _loadSystemLevels() async {
    try {
      _brightness = await ScreenBrightness.instance.application;
      _volume = await VolumeController.instance.getVolume();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadDeviceStatus() async {
    try {
      final status = await const MethodChannel(
        'com.novaplay/media',
      ).invokeMethod<Map<dynamic, dynamic>>('getDeviceStatus');
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        batteryPercent =
            (status?['batteryPercent'] as num?)?.toInt() ?? batteryPercent;
        systemTime =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      });
    } on PlatformException {
      if (mounted) {
        final now = DateTime.now();
        setState(
          () => systemTime =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        );
      }
    }
  }

  Future<void> _loadAiSubtitlePreferences() async {
    final values = await AiSubtitlePreferences.load();
    if (!mounted) return;
    setState(() {
      aiSubtitlesEnabled = values.enabled;
      aiSubtitleLanguage = values.language;
      aiSubtitleFontScale = values.fontScale;
    });
    if (aiSubtitlesEnabled) _startSubtitleLoop();
  }

  AiSubtitleLanguage get _selectedSubtitleLanguage =>
      AiSubtitlePreferences.languages.firstWhere(
        (language) => language.label == aiSubtitleLanguage,
        orElse: () => AiSubtitlePreferences.languages.first,
      );

  Future<void> _setAiSubtitlesEnabled(bool enabled) async {
    if (!mounted) return;
    setState(() {
      aiSubtitlesEnabled = enabled;
      if (!enabled) {
        final source = _embeddedSubtitleText;
        _activeCaption = source == null
            ? null
            : AiCaption(
                text: source,
                start: player.state.position,
                end: player.state.position + const Duration(seconds: 6),
              );
      }
    });
    await AiSubtitlePreferences.save(enabled: enabled);
    if (!mounted) return;
    if (enabled) {
      _startSubtitleLoop();
      _showHud('AI CC on', Icons.closed_caption_rounded);
    } else {
      _stopSubtitleLoop();
      _showHud('AI CC off', Icons.closed_caption_disabled_rounded);
    }
  }

  Future<void> _setAiSubtitleLanguage(String language) async {
    setState(() => aiSubtitleLanguage = language);
    await AiSubtitlePreferences.save(language: language);
    if (aiSubtitlesEnabled) _requestSubtitle();
  }

  Future<void> _setAiSubtitleFontScale(double scale) async {
    setState(() => aiSubtitleFontScale = scale);
    await AiSubtitlePreferences.save(fontScale: scale);
  }

  void _startSubtitleLoop() {
    _subtitleTimer?.cancel();
    _subtitleTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _requestSubtitle(),
    );
    _requestSubtitle();
  }

  void _stopSubtitleLoop() {
    _subtitleTimer?.cancel();
    _subtitleTimer = null;
  }

  Future<void> _requestSubtitle() async {
    if (!aiSubtitlesEnabled || _subtitleRequestInFlight) return;
    _subtitleRequestInFlight = true;
    try {
      final result = await aiSubtitleService.recognizeAndTranslate(
        sourcePath: widget.file.path,
        position: player.state.position,
        language: _selectedSubtitleLanguage,
        sourceText: _embeddedSubtitleText,
      );
      if (!mounted || !aiSubtitlesEnabled) return;
      if (result.caption != null) {
        setState(() => _activeCaption = result.caption);
      }
    } on AiSubtitleException {
      // Direct cue translation is best-effort; keep playback unobstructed.
    } catch (_) {
      // Direct cue translation is best-effort; keep playback unobstructed.
    } finally {
      _subtitleRequestInFlight = false;
    }
  }

  void _showAiSubtitleSettings() {
    var enabled = aiSubtitlesEnabled;
    var language = aiSubtitleLanguage;
    var fontScale = aiSubtitleFontScale;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final landscape =
              MediaQuery.orientationOf(context) == Orientation.landscape;
          final controls = <Widget>[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              title: const Text('AI CC'),
              subtitle: const Text('Off by default on fresh installs'),
              secondary: Icon(
                enabled
                    ? Icons.closed_caption_rounded
                    : Icons.closed_caption_disabled_rounded,
                color: enabled ? NovaColors.cyan : Colors.white54,
              ),
              onChanged: (value) {
                setSheetState(() => enabled = value);
                _setAiSubtitlesEnabled(value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Target language'),
              subtitle: Text(language),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showAiLanguagePicker(language, (value) {
                setSheetState(() => language = value);
                _setAiSubtitleLanguage(value);
              }),
            ),
          ];
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Live Subtitles',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Opt in to transcribe short audio windows and translate spoken dialogue.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .68),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (landscape)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: controls
                          .map(
                            (child) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: child,
                              ),
                            ),
                          )
                          .toList(),
                    )
                  else
                    ...controls,
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      const Icon(Icons.format_size_rounded, size: 20),
                      const SizedBox(width: 10),
                      const Text('Caption size'),
                      Expanded(
                        child: Slider(
                          min: .8,
                          max: 1.8,
                          divisions: 5,
                          value: fontScale,
                          label: '${(fontScale * 100).round()}%',
                          onChanged: (value) {
                            setSheetState(() => fontScale = value);
                            _setAiSubtitleFontScale(value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAiLanguagePicker(
    String currentLanguage,
    ValueChanged<String> onSelected,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final height = MediaQuery.sizeOf(context).height;
        final languages = AiSubtitlePreferences.languages;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * .85),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Target language',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: landscape
                      ? GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisExtent: 54,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 4,
                              ),
                          itemCount: languages.length,
                          itemBuilder: (_, index) => _languageTile(
                            languages[index],
                            currentLanguage,
                            onSelected,
                          ),
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: languages.length,
                          itemBuilder: (_, index) => _languageTile(
                            languages[index],
                            currentLanguage,
                            onSelected,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _languageTile(
    AiSubtitleLanguage language,
    String currentLanguage,
    ValueChanged<String> onSelected,
  ) {
    final selected = language.label == currentLanguage;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? NovaColors.cyan : Colors.white54,
      ),
      title: Text(language.label),
      onTap: () {
        onSelected(language.label);
        Navigator.pop(context);
      },
    );
  }

  void _enableAutoOrientation() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  DeviceOrientation? _lastSensorOrientation;
  DateTime _lastOrientationChange = DateTime.fromMillisecondsSinceEpoch(0);

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (orientationLocked) return;
    final now = DateTime.now();
    if (now.difference(_lastOrientationChange) <
        const Duration(milliseconds: 700)) {
      return;
    }
    DeviceOrientation? next;
    if (event.x.abs() > 7 && event.x.abs() > event.y.abs()) {
      next = event.x > 0
          ? DeviceOrientation.landscapeLeft
          : DeviceOrientation.landscapeRight;
    } else if (event.y.abs() > 7 && event.y.abs() > event.x.abs()) {
      next = DeviceOrientation.portraitUp;
    }
    if (next == null || next == _lastSensorOrientation) return;
    _lastSensorOrientation = next;
    _applyOrientation(next);
  }

  Future<void> _applyOrientation(DeviceOrientation orientation) async {
    _lastOrientationChange = DateTime.now();
    final landscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    await SystemChrome.setPreferredOrientations([orientation]);
    await SystemChrome.setEnabledSystemUIMode(
      landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleManualOrientation() async {
    orientationLocked = true;
    landscapeLocked = !landscapeLocked;
    await _applyOrientation(
      landscapeLocked
          ? DeviceOrientation.landscapeLeft
          : DeviceOrientation.portraitUp,
    );
    _showHud(
      landscapeLocked ? 'Landscape locked' : 'Portrait locked',
      Icons.screen_lock_rotation_rounded,
    );
  }

  void _cycleAspectRatio() {
    const modes = ['Fit', 'Fill', '16:9', 'Stretch', 'Original'];
    final next = (modes.indexOf(aspectMode) + 1) % modes.length;
    setState(() => aspectMode = modes[next]);
    _showHud(aspectMode, Icons.aspect_ratio_rounded);
  }

  BoxFit get _videoFit => switch (aspectMode) {
    'Fill' => BoxFit.cover,
    'Stretch' => BoxFit.fill,
    _ => BoxFit.contain,
  };

  double? get _videoAspectRatio => aspectMode == '16:9' ? 16 / 9 : null;

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = zoom;
    _gestureStart = details.localFocalPoint;
    _startBrightness = _brightness;
    _startVolume = _volume;
    _seekPreview = null;
    _hideTimer?.cancel();
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size size) {
    if (details.pointerCount > 1 || (details.scale - 1).abs() > .02) {
      setState(() => zoom = (_baseZoom * details.scale).clamp(.85, 2.4));
      _hideTimer?.cancel();
      return;
    }
    _onPanUpdate(
      DragUpdateDetails(
        globalPosition: details.focalPoint,
        localPosition: details.localFocalPoint,
        delta: details.focalPointDelta,
      ),
      size,
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _finishGesture();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _statusTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _subtitleTimer?.cancel();
    _resumeSaveTimer?.cancel();
    _sensorSubscription?.cancel();
    _embeddedSubtitleSubscription?.cancel();
    _playingSubscription?.cancel();
    _saveResumePosition(updateLibrary: false);
    aiSubtitleService.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    player.pause();
    player.dispose();
    super.dispose();
  }

  void _armControlsTimer() {
    _hideTimer?.cancel();
    if (!locked) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => controlsVisible = false);
      });
    }
  }

  void _toggleControls() {
    if (locked) return;
    _hideTimer?.cancel();
    setState(() => controlsVisible = !controlsVisible);
    if (controlsVisible) _armControlsTimer();
  }

  void _showHud(String label, IconData icon) {
    setState(() {
      _hudVisible = true;
      _hudLabel = label;
      _hudIcon = icon;
    });
    Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  Future<void> _updateBrightness(double value) async {
    _brightness = value.clamp(.02, 1.0);
    await ScreenBrightness.instance.setApplicationScreenBrightness(_brightness);
    _showHud('${(_brightness * 100).round()}%', Icons.brightness_6_rounded);
  }

  Future<void> _updateVolume(double value) async {
    _volume = value.clamp(0, 1.0);
    VolumeController.instance.showSystemUI = false;
    await VolumeController.instance.setVolume(_volume);
    _showHud(
      '${(_volume * 100).round()}%',
      _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
    );
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final start = _gestureStart;
    if (start == null) return;
    final dx = details.localPosition.dx - start.dx;
    final dy = details.localPosition.dy - start.dy;
    if (dx.abs() > dy.abs()) {
      final current = player.state.position;
      final delta = Duration(milliseconds: (dx / size.width * 90000).round());
      setState(() => _seekPreview = current + delta);
    } else if (start.dx < size.width / 2) {
      _updateBrightness(_startBrightness - dy / size.height);
    } else {
      _updateVolume(_startVolume - dy / size.height);
    }
  }

  Future<void> _finishGesture() async {
    if (_seekPreview != null) {
      final duration = player.state.duration;
      final position = _seekPreview!.inMilliseconds.clamp(
        0,
        duration.inMilliseconds,
      );
      await player.seek(Duration(milliseconds: position));
      _showHud(
        _formatSeek(Duration(milliseconds: position)),
        Icons.swap_horiz_rounded,
      );
    }
    _gestureStart = null;
    _seekPreview = null;
    _armControlsTimer();
  }

  String _formatSeek(Duration position) =>
      '${position.isNegative ? '-' : '+'}${formatDuration(position.abs())}';

  Future<void> _toggleDialogueEnhancer() async {
    dialogueEnhancer = !dialogueEnhancer;
    try {
      await (player.platform as dynamic).setProperty(
        'af',
        dialogueEnhancer
            ? 'lavfi=[equalizer=f=100:t=q:w=1:g=-8,equalizer=f=250:t=q:w=1:g=-5,equalizer=f=1400:t=q:w=1:g=5,equalizer=f=3000:t=q:w=1:g=6,acompressor=threshold=0.18:ratio=4:attack=5:release=100]'
            : '',
      );
    } catch (_) {
      dialogueEnhancer = false;
    }
    _showHud(
      dialogueEnhancer ? 'Dialogue enhancer on' : 'Dialogue enhancer off',
      Icons.record_voice_over_rounded,
    );
    if (mounted) setState(() {});
  }

  Future<void> _captureSnapshot() async {
    if (captureBusy) return;
    setState(() => captureBusy = true);
    final saved = await captureService.saveSnapshot(
      player,
      sourceName: widget.file.name,
    );
    if (mounted) {
      setState(() => captureBusy = false);
      _showHud(
        saved ? 'Snapshot saved' : 'Snapshot failed',
        saved ? Icons.photo_camera_rounded : Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _captureGif() async {
    if (captureBusy) return;
    setState(() => captureBusy = true);
    final saved = await captureService.exportGif(
      sourcePath: widget.file.path,
      start: player.state.position,
    );
    if (mounted) {
      setState(() => captureBusy = false);
      _showHud(
        saved ? '5s GIF saved' : 'GIF export failed',
        saved ? Icons.gif_box_rounded : Icons.error_outline_rounded,
      );
    }
  }

  void _doubleTap(TapDownDetails details, Size size) {
    final direction = details.localPosition.dx < size.width / 2 ? -1 : 1;
    final current = _queuedSeekPosition ?? player.state.position;
    final requested = current + Duration(seconds: direction * 10);
    final duration = player.state.duration;
    final target = Duration(
      milliseconds: requested.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    _queuedSeekPosition = target;
    _seekQueue = _seekQueue.catchError((_) {}).then((_) async {
      await player.seek(target);
      if (_queuedSeekPosition == target) _queuedSeekPosition = null;
    });
    _showSeekIndicator(direction: direction);
  }

  void _showSeekIndicator({required int direction}) {
    final sameDirection =
        _seekIndicatorVisible && _seekIndicatorDirection == direction;
    setState(() {
      _seekIndicatorDirection = direction;
      _seekIndicatorSeconds = sameDirection ? _seekIndicatorSeconds + 10 : 10;
      _seekIndicatorNonce++;
      _seekIndicatorVisible = true;
    });
    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _seekIndicatorVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final size = MediaQuery.sizeOf(context);
          return Stack(
            children: [
              Center(
                child: ClipRect(
                  child: Transform.scale(
                    scale: zoom,
                    child: Video(
                      controller: controller,
                      fit: _videoFit,
                      aspectRatio: _videoAspectRatio,
                      controls: NoVideoControls,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                onDoubleTapDown: (details) => _doubleTap(details, size),
                onScaleStart: _onScaleStart,
                onScaleUpdate: (details) => _onScaleUpdate(details, size),
                onScaleEnd: _onScaleEnd,
                child: const SizedBox.expand(),
              ),
              if (_seekPreview != null)
                Center(child: _SeekPreview(position: _seekPreview!)),
              if (_seekIndicatorVisible)
                Positioned(
                  left: _seekIndicatorDirection < 0 ? 28 : null,
                  right: _seekIndicatorDirection > 0 ? 28 : null,
                  top: size.height * .36,
                  child: _SeekIndicator(
                    key: ValueKey(_seekIndicatorNonce),
                    direction: _seekIndicatorDirection,
                    seconds: _seekIndicatorSeconds,
                  ),
                ),
              StreamBuilder<Duration>(
                stream: player.stream.position,
                initialData: player.state.position,
                builder: (context, snapshot) {
                  final caption = _activeCaption;
                  final position = snapshot.data ?? Duration.zero;
                  final visible =
                      caption != null &&
                      position >= caption.start &&
                      position <= caption.end;

                  if (!visible) return const SizedBox.shrink();
                  return Positioned(
                    left: 20,
                    right: 20,
                    bottom: orientation == Orientation.landscape ? 64 : 84,
                    child: SafeArea(
                      child: _AiCaptionPill(
                        text: caption.text,
                        fontScale: aiSubtitleFontScale,
                        language: aiSubtitlesEnabled
                            ? aiSubtitleLanguage
                            : 'Original',
                      ),
                    ),
                  );
                },
              ),
              if (orientation == Orientation.landscape && systemTime.isNotEmpty)
                Positioned(
                  top: 10,
                  right: 16,
                  child: SafeArea(
                    child: _DeviceStatusPill(
                      batteryPercent: batteryPercent,
                      systemTime: systemTime,
                    ),
                  ),
                ),
              if (_hudVisible)
                Center(
                  child: _Hud(icon: _hudIcon, label: _hudLabel),
                ),
              if (locked)
                Positioned(
                  top: 28,
                  right: 20,
                  child: SafeArea(
                    child: IconButton(
                      onPressed: () => setState(() {
                        locked = false;
                        controlsVisible = true;
                        _armControlsTimer();
                      }),
                      icon: const Icon(Icons.lock_rounded, color: Colors.white),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !controlsVisible,
                    child: AnimatedOpacity(
                      opacity: controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _ControlsOverlay(
                        file: widget.file,
                        player: player,
                        onBack: () => Navigator.pop(context),
                        onLock: () => setState(() {
                          locked = true;
                          controlsVisible = false;
                        }),
                        onMore: _showOptions,
                        onPip: _enterPip,
                        onSnapshot: _captureSnapshot,
                        onGif: _captureGif,
                        dialogueEnhancerEnabled: dialogueEnhancer,
                        onDialogueEnhancer: _toggleDialogueEnhancer,
                        aiSubtitlesEnabled: aiSubtitlesEnabled,
                        onAiSubtitles: _showAiSubtitleSettings,
                        onOrientation: _toggleManualOrientation,
                        onAspectRatio: _cycleAspectRatio,
                        orientationLocked: orientationLocked,
                        landscapeLocked: landscapeLocked,
                        aspectMode: aspectMode,
                        onInteract: _armControlsTimer,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _enterPip() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } on PlatformException {
      if (mounted) {
        _showHud('PiP unavailable', Icons.picture_in_picture_alt_outlined);
      }
    }
  }

  void _showOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlayerOptions(
        player: player,
        onSubtitle: _showEmbeddedSubtitleTracks,
      ),
    );
  }

  void _showEmbeddedSubtitleTracks() {
    final tracks = player.state.tracks.subtitle;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final landscape =
            MediaQuery.orientationOf(sheetContext) == Orientation.landscape;
        final trackTiles = <Widget>[
          ListTile(
            dense: landscape,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(
              Icons.subtitles_off_rounded,
              color: NovaColors.cyan,
            ),
            title: const Text('None / Turn Off Subtitles'),
            subtitle: const Text('Hide embedded subtitle output'),
            onTap: () async {
              await player.setSubtitleTrack(SubtitleTrack.no());
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
              _showHud('Subtitles off', Icons.subtitles_off_rounded);
            },
          ),
        ];
        trackTiles.addAll(
          tracks.asMap().entries.map(
            (entry) => ListTile(
              dense: landscape,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(
                Icons.subtitles_rounded,
                color: NovaColors.violet,
              ),
              title: Text(_subtitleTrackLabel(entry.value)),
              subtitle: Text(
                entry.value.codec == null
                    ? 'Embedded track ${entry.key + 1}'
                    : 'Embedded · ${entry.value.codec}',
              ),
              onTap: () async {
                await player.setSubtitleTrack(entry.value);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                _showHud(
                  '${_subtitleTrackLabel(entry.value)} selected',
                  Icons.subtitles_rounded,
                );
              },
            ),
          ),
        );
        if (tracks.isEmpty) {
          trackTiles.add(
            const ListTile(
              dense: true,
              title: Text('No embedded subtitle tracks found.'),
            ),
          );
        }
        trackTiles.add(
          ListTile(
            dense: landscape,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.file_open_rounded),
            title: const Text('Load external subtitle file'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _pickSubtitle();
            },
          ),
        );
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subtitle tracks',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose an embedded language or turn subtitles off. Changes apply immediately.',
                  style: TextStyle(color: NovaColors.muted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: landscape
                      ? GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisExtent: 68,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 4,
                              ),
                          itemCount: trackTiles.length,
                          itemBuilder: (_, index) => trackTiles[index],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: trackTiles.length,
                          itemBuilder: (_, index) => trackTiles[index],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _subtitleTrackLabel(SubtitleTrack track) {
    const names = {
      'ar': 'Arabic',
      'ara': 'Arabic',
      'bn': 'Bengali',
      'ben': 'Bengali',
      'zh': 'Chinese',
      'zho': 'Chinese',
      'de': 'German',
      'deu': 'German',
      'en': 'English',
      'eng': 'English',
      'es': 'Spanish',
      'spa': 'Spanish',
      'fr': 'French',
      'fra': 'French',
      'hi': 'Hindi',
      'hin': 'Hindi',
      'ja': 'Japanese',
      'jpn': 'Japanese',
      'ko': 'Korean',
      'kor': 'Korean',
      'pt': 'Portuguese',
      'por': 'Portuguese',
    };
    final rawLanguage = track.language?.trim();
    final language = rawLanguage == null || rawLanguage.isEmpty
        ? null
        : names[rawLanguage.toLowerCase()] ?? rawLanguage;
    final title = track.title?.trim();
    if (title != null && title.isNotEmpty && language != null) {
      if (title.toLowerCase() == rawLanguage?.toLowerCase()) return language;
      return '$title · $language';
    }
    if (title != null && title.isNotEmpty) return title;
    if (language != null) return language;
    return 'Subtitle track';
  }

  Future<void> _pickSubtitle() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (file?.path == null) return;
    await player.setSubtitleTrack(
      SubtitleTrack.uri(file!.path!, title: file.name, language: 'und'),
    );
    if (mounted) {
      _showHud('External subtitles selected', Icons.subtitles_rounded);
    }
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.file,
    required this.player,
    required this.onBack,
    required this.onLock,
    required this.onMore,
    required this.onPip,
    required this.onSnapshot,
    required this.onGif,
    required this.dialogueEnhancerEnabled,
    required this.onDialogueEnhancer,
    required this.aiSubtitlesEnabled,
    required this.onAiSubtitles,
    required this.onOrientation,
    required this.onAspectRatio,
    required this.orientationLocked,
    required this.landscapeLocked,
    required this.aspectMode,
    required this.onInteract,
  });
  final VideoFile file;
  final Player player;
  final VoidCallback onBack;
  final VoidCallback onLock;
  final VoidCallback onMore;
  final VoidCallback onPip;
  final VoidCallback onSnapshot;
  final VoidCallback onGif;
  final bool dialogueEnhancerEnabled;
  final VoidCallback onDialogueEnhancer;
  final bool aiSubtitlesEnabled;
  final VoidCallback onAiSubtitles;
  final VoidCallback onOrientation;
  final VoidCallback onAspectRatio;
  final bool orientationLocked;
  final bool landscapeLocked;
  final String aspectMode;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent, Colors.black87],
                stops: [0, .42, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: onPip,
                    icon: const Icon(Icons.picture_in_picture_alt_outlined),
                  ),
                  IconButton(
                    onPressed: onMore,
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
              const Spacer(),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (context, snapshot) => IconButton(
                  onPressed: () {
                    player.playOrPause();
                    onInteract();
                  },
                  iconSize: 64,
                  icon: Icon(
                    snapshot.data == true
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              StreamBuilder<Duration>(
                stream: player.stream.position,
                initialData: player.state.position,
                builder: (context, positionSnapshot) => StreamBuilder<Duration>(
                  stream: player.stream.duration,
                  initialData: player.state.duration,
                  builder: (context, durationSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final duration = durationSnapshot.data ?? Duration.zero;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(17, 0, 17, 8),
                      child: PrecisionScrubber(
                        sourcePath: file.path,
                        position: position,
                        duration: duration,
                        onSeek: player.seek,
                        onInteraction: onInteract,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: dialogueEnhancerEnabled
                          ? 'Disable dialogue enhancer'
                          : 'Enable dialogue enhancer',
                      onPressed: onDialogueEnhancer,
                      icon: Icon(
                        Icons.record_voice_over_rounded,
                        color: dialogueEnhancerEnabled
                            ? NovaColors.cyan
                            : Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: aiSubtitlesEnabled
                          ? 'Configure AI live subtitles'
                          : 'Enable AI live subtitles',
                      onPressed: onAiSubtitles,
                      icon: Icon(
                        aiSubtitlesEnabled
                            ? Icons.closed_caption_rounded
                            : Icons.closed_caption_disabled_rounded,
                        color: aiSubtitlesEnabled
                            ? NovaColors.cyan
                            : Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Save high-resolution snapshot',
                      onPressed: onSnapshot,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                    IconButton(
                      tooltip: 'Export 5-second GIF',
                      onPressed: onGif,
                      icon: const Icon(Icons.gif_box_outlined),
                    ),
                    IconButton(
                      tooltip: 'Cycle aspect ratio',
                      onPressed: onAspectRatio,
                      icon: const Icon(Icons.aspect_ratio_rounded),
                    ),
                    const Spacer(),
                    Text(
                      dialogueEnhancerEnabled
                          ? 'Dialogue boost'
                          : 'Swipe for controls',
                      style: TextStyle(
                        color: dialogueEnhancerEnabled
                            ? NovaColors.cyan
                            : Colors.white.withValues(alpha: .7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: orientationLocked
                        ? (landscapeLocked
                              ? 'Switch to portrait'
                              : 'Switch to landscape')
                        : 'Lock orientation',
                    onPressed: onOrientation,
                    icon: Icon(
                      landscapeLocked
                          ? Icons.screen_lock_landscape_rounded
                          : Icons.screen_lock_portrait_rounded,
                      color: orientationLocked ? NovaColors.cyan : Colors.white,
                    ),
                  ),
                  Text(
                    aspectMode,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: onLock,
                    icon: const Icon(Icons.lock_outline_rounded),
                  ),
                  const Spacer(),
                  Text(
                    'Swipe for controls',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onMore,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiCaptionPill extends StatelessWidget {
  const _AiCaptionPill({
    required this.text,
    required this.fontScale,
    required this.language,
  });

  final String text;
  final double fontScale;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: .24)),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 2),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 9, 15, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17 * fontScale,
                    height: 1.22,
                    fontWeight: FontWeight.w800,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'AI CC · $language',
                  style: TextStyle(
                    color: NovaColors.cyan.withValues(alpha: .86),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceStatusPill extends StatelessWidget {
  const _DeviceStatusPill({
    required this.batteryPercent,
    required this.systemTime,
  });
  final int batteryPercent;
  final String systemTime;

  @override
  Widget build(BuildContext context) {
    final batteryIcon = batteryPercent <= 20
        ? Icons.battery_alert_rounded
        : batteryPercent >= 80
        ? Icons.battery_full_rounded
        : Icons.battery_5_bar_rounded;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(batteryIcon, color: NovaColors.cyan, size: 15),
            const SizedBox(width: 4),
            Text(
              '$batteryPercent%',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 9),
            Text(
              systemTime,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .76),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: NovaColors.cyan, size: 28),
        const SizedBox(height: 7),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _SeekIndicator extends StatelessWidget {
  const _SeekIndicator({
    super.key,
    required this.direction,
    required this.seconds,
  });

  final int direction;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final forward = direction > 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .72, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 118,
        height: 118,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: .74),
          border: Border.all(
            color: NovaColors.cyan.withValues(alpha: .72),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 14, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: NovaColors.cyan,
              size: 31,
            ),
            const SizedBox(height: 3),
            Text(
              '${forward ? '+' : '−'}${seconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({required this.position});
  final Duration position;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.swap_horiz_rounded, color: NovaColors.cyan),
        const SizedBox(width: 8),
        Text(
          formatDuration(position),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _PlayerOptions extends StatelessWidget {
  const _PlayerOptions({required this.player, required this.onSubtitle});
  final Player player;
  final VoidCallback onSubtitle;
  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final actions = <Widget>[
      ListTile(
        dense: landscape,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.audiotrack_rounded, color: NovaColors.cyan),
        title: const Text('Audio track'),
        subtitle: Text(
          '${player.state.tracks.audio.length} embedded tracks found',
        ),
        onTap: () => _showAudioTracks(context),
      ),
      ListTile(
        dense: landscape,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.subtitles_outlined, color: NovaColors.violet),
        title: const Text('Subtitles'),
        subtitle: Text(
          '${player.state.tracks.subtitle.length} embedded tracks found',
        ),
        onTap: onSubtitle,
      ),
      ListTile(
        dense: landscape,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.aspect_ratio_rounded,
          color: NovaColors.green,
        ),
        title: const Text('Aspect ratio'),
        subtitle: const Text('Fit  •  Fill  •  Stretch'),
        onTap: () => Navigator.pop(context),
      ),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playback controls',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            const Text(
              'Speed',
              style: TextStyle(
                color: NovaColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 2,
              children: [.25, .5, .75, 1.0, 1.25, 1.5, 2.0, 3.0]
                  .map(
                    (speed) => ActionChip(
                      label: Text('${speed}x'),
                      onPressed: () {
                        player.setRate(speed);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            if (landscape)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 64,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                itemCount: actions.length,
                itemBuilder: (_, index) => actions[index],
              )
            else
              ...actions,
          ],
        ),
      ),
    );
  }

  void _showAudioTracks(BuildContext context) {
    final tracks = player.state.tracks.audio;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Audio tracks',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('Auto'),
              leading: const Icon(Icons.auto_awesome),
              onTap: () {
                player.setAudioTrack(AudioTrack.auto());
                Navigator.pop(context);
              },
            ),
            ...tracks.map(
              (track) => ListTile(
                title: Text(track.title ?? track.language ?? 'Track'),
                leading: const Icon(Icons.audiotrack),
                onTap: () {
                  player.setAudioTrack(track);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
