import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/data/media_repository.dart';
import '../media/data/audio_extraction_service.dart';
import '../media/domain/playback_history.dart';
import '../media/domain/video_file.dart';
import '../media/presentation/media_providers.dart';
import 'ai_subtitle_preferences.dart';
import 'ai_subtitle_service.dart';
import 'language_names.dart';
import 'capture_service.dart';
import 'cast_service.dart';
import 'precision_scrubber.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.file, this.queue});
  final VideoFile file;
  final List<VideoFile>? queue;
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
  StreamSubscription<bool>? _completionSubscription;
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
  final FlutterTts _dubbingTts = FlutterTts();
  Timer? _subtitleTimer;
  bool aiDubbingEnabled = false;
  String? _lastDubbedCaption;
  double? _dubbingRestorationVolume;
  Duration? _dubbingCueEnd;
  bool _dubbingSpeechActive = false;
  Completer<void>? _dubbingSpeechCompleter;
  int _dubbingRequestId = 0;
  Timer? _resumeSaveTimer;
  Timer? _diagnosticSubtitleTimer;
  bool aiSubtitlesEnabled = false;
  String aiSubtitleLanguage = 'English';
  double aiSubtitleFontScale = 1.0;
  AiCaption? _activeCaption;
  bool _subtitleRequestInFlight = false;
  String? _embeddedSubtitleText;
  String? _lastSubtitleCueText;
  SubtitleTrack _selectedNativeSubtitleTrack = SubtitleTrack.no();
  bool _hasReceivedSubtitleCue = false;
  int _seekIndicatorSeconds = 0;
  int _seekIndicatorDirection = 1;
  int _seekIndicatorNonce = 0;
  bool _seekIndicatorVisible = false;
  Duration? _queuedSeekPosition;
  Future<void> _seekQueue = Future<void>.value();
  final resumeRepository = const MediaRepository();
  bool _resumeRestored = false;
  late final List<VideoFile> _queue;
  late int _queueIndex;
  bool _queueTransitioning = false;
  bool _playerDisposed = false;
  Timer? _queueIndicatorTimer;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  bool _sleepUntilVideoEnd = false;
  final NovaCastController _castController = NovaCastController();
  bool _castBusy = false;
  bool _castConnected = false;
  final audioExtractionService = const AudioExtractionService();
  String? _queueIndicatorLabel;
  int _queueIndicatorDirection = 1;

  VideoFile get _currentFile => _queue[_queueIndex];

  @override
  void initState() {
    super.initState();
    _queue = _resolveQueue();
    _queueIndex = _queue.indexWhere((item) => item.id == widget.file.id);
    if (_queueIndex < 0) _queueIndex = 0;
    player = Player(configuration: const PlayerConfiguration(pitch: true));
    controller = VideoController(player);
    _pipChannel.setMethodCallHandler(_handlePipCall);
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
        _lastSubtitleCueText = null;
        if (aiSubtitlesEnabled) setState(() => _activeCaption = null);
        return;
      }
      if (text == _lastSubtitleCueText) return;
      _lastSubtitleCueText = text;
      _hasReceivedSubtitleCue = true;
      _diagnosticSubtitleTimer?.cancel();
      if (aiSubtitlesEnabled || aiDubbingEnabled) {
        // Do not render the source cue here: AI CC must show only the
        // translated result, never a source-language flash.
        _requestSubtitle();
      }
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      if (!playing) _saveResumePosition();
      unawaited(_updatePipState(playing));
    });
    _completionSubscription = player.stream.completed.listen((completed) {
      if (!completed) return;
      _handleVideoCompletedForSleepTimer();
      _playQueueOffset(1, automatic: true);
    });
    _resumeSaveTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _saveResumePosition(),
    );
    _armControlsTimer();
  }

  List<VideoFile> _resolveQueue() {
    final supplied = widget.queue;
    final source = supplied == null || supplied.isEmpty
        ? ref
              .read(mediaLibraryProvider)
              .files
              .where((item) => item.folderName == widget.file.folderName)
              .toList()
        : supplied.toList();
    final byId = <String, VideoFile>{for (final item in source) item.id: item};
    byId[widget.file.id] = widget.file;
    return byId.values.toList();
  }

  Future<void> _openMediaAndRestoreResume() async {
    final playlist = Playlist(
      _queue.map((item) => Media(item.path)).toList(growable: false),
      index: _queueIndex,
    );
    await player.open(playlist, play: true);
    await player.setPlaylistMode(PlaylistMode.none);
    _selectedNativeSubtitleTrack = SubtitleTrack.no();
    await player.setSubtitleTrack(_selectedNativeSubtitleTrack);
    if (!mounted) return;
    // Native subtitles stay off until the user selects a track. Once selected,
    // AI CC hides only native drawing while retaining MediaKit cue delivery.
    await _restoreResumeForCurrent(showFeedback: true);
  }

  Future<void> _restoreResumeForCurrent({required bool showFeedback}) async {
    _resumeRestored = false;
    final history = await resumeRepository.readPlaybackHistory();
    final entry = history[_currentFile.id];
    final resume = entry?.position ?? _currentFile.progress;
    final duration = await _waitForMediaDuration();
    final effectiveDuration = duration > Duration.zero
        ? duration
        : entry?.totalDuration ?? _currentFile.duration;
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
    if (!mounted || !showFeedback) return;
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

  void _resetCurrentItemSubtitleState() {
    _selectedNativeSubtitleTrack = SubtitleTrack.auto();
    _embeddedSubtitleText = null;
    _lastSubtitleCueText = null;
    _hasReceivedSubtitleCue = false;
    _activeCaption = null;
    _subtitleRequestInFlight = false;
    _dubbingRequestId++;
    _lastDubbedCaption = null;
    _dubbingSpeechActive = false;
    _dubbingSpeechCompleter = null;
    _dubbingCueEnd = null;
    unawaited(_dubbingTts.stop());
    unawaited(_restoreDubbingVolume());
  }

  Future<void> _playQueueOffset(int offset, {bool automatic = false}) async {
    if (_queueTransitioning) return;
    _armControlsTimer();
    final nextIndex = _queueIndex + offset;
    if (nextIndex < 0 || nextIndex >= _queue.length) {
      if (!automatic) {
        _showHud(
          offset > 0 ? 'End of folder' : 'Beginning of folder',
          Icons.info_outline_rounded,
        );
      }
      return;
    }
    _queueTransitioning = true;
    try {
      await _saveResumePosition();
      final direction = offset > 0 ? 1 : -1;
      _showQueueIndicator(direction);
      _queueIndex = nextIndex;
      _resetCurrentItemSubtitleState();
      if (mounted) setState(() {});
      await player.jump(nextIndex);
      _selectedNativeSubtitleTrack = player.state.track.subtitle;
      await _restoreResumeForCurrent(showFeedback: false);
    } finally {
      _queueTransitioning = false;
    }
  }

  void _showQueueIndicator(int direction) {
    final targetIndex = _queueIndex + direction;
    if (targetIndex < 0 || targetIndex >= _queue.length) return;
    final title = _queue[targetIndex].name;
    _queueIndicatorTimer?.cancel();
    setState(() {
      _queueIndicatorDirection = direction;
      _queueIndicatorLabel = '${direction > 0 ? 'Next' : 'Previous'}: $title';
    });
    _queueIndicatorTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _queueIndicatorLabel = null);
    });
  }

  String _formatSleepRemaining(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (mounted) {
      setState(() {
        _sleepRemaining = null;
        _sleepUntilVideoEnd = false;
      });
    }
  }

  void _setSleepTimer(Duration? duration, {bool untilVideoEnd = false}) {
    _sleepTimer?.cancel();
    setState(() {
      _sleepRemaining = duration;
      _sleepUntilVideoEnd = untilVideoEnd;
    });
    if (duration == null || untilVideoEnd) return;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remaining = _sleepRemaining;
      if (!mounted || remaining == null) return;
      if (remaining <= const Duration(seconds: 1)) {
        _sleepTimer?.cancel();
        _sleepTimer = null;
        await player.pause();
        if (!mounted) return;
        setState(() => _sleepRemaining = null);
        _showHud('Sleep timer paused playback', Icons.bedtime_rounded);
        return;
      }
      setState(() => _sleepRemaining = remaining - const Duration(seconds: 1));
    });
  }

  void _handleVideoCompletedForSleepTimer() {
    if (!_sleepUntilVideoEnd) return;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    setState(() {
      _sleepUntilVideoEnd = false;
      _sleepRemaining = null;
    });
  }

  Future<void> _showSleepTimerSheet(
    BuildContext context, {
    VoidCallback? onChanged,
  }) async {
    final choices = <MapEntry<String, Duration?>>[
      const MapEntry('15 minutes', Duration(minutes: 15)),
      const MapEntry('30 minutes', Duration(minutes: 30)),
      const MapEntry('45 minutes', Duration(minutes: 45)),
      const MapEntry('60 minutes', Duration(minutes: 60)),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sleep timer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                _sleepUntilVideoEnd
                    ? 'Active: End of current video'
                    : _sleepRemaining == null
                    ? 'No timer active'
                    : 'Active: ${_formatSleepRemaining(_sleepRemaining!)} remaining',
                style: const TextStyle(color: NovaColors.muted),
              ),
              const SizedBox(height: 14),
              ...choices.map(
                (choice) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.timer_outlined,
                    color: NovaColors.cyan,
                  ),
                  title: Text(choice.key),
                  onTap: () {
                    _setSleepTimer(choice.value);
                    onChanged?.call();
                    Navigator.pop(sheetContext);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.movie_outlined,
                  color: NovaColors.violet,
                ),
                title: const Text('End of current video'),
                onTap: () {
                  _setSleepTimer(null, untilVideoEnd: true);
                  onChanged?.call();
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('Custom duration'),
                onTap: () async {
                  final minutes = await _customSleepMinutes(sheetContext);
                  if (minutes != null && mounted) {
                    _setSleepTimer(Duration(minutes: minutes));
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  }
                },
              ),
              if (_sleepRemaining != null || _sleepUntilVideoEnd)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _cancelSleepTimer();
                      onChanged?.call();
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.timer_off_outlined),
                    label: const Text('Cancel Timer'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _customSleepMinutes(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Custom duration'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Minutes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.trim()),
            ),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value != null && value > 0 ? value : null;
  }

  Future<void> _stopAndClose() async {
    await _saveResumePosition(updateLibrary: false);
    _resumeRestored = false;
    await player.stop();
    await _releasePlayerResources();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _releasePlayerResources() async {
    if (_playerDisposed) return;
    _playerDisposed = true;
    try {
      await player.pause();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
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
        : _currentFile.duration;
    if (updateLibrary && mounted) {
      await ref
          .read(mediaLibraryProvider.notifier)
          .saveProgress(_currentFile, position, totalDuration: totalDuration);
    } else {
      await resumeRepository.savePlaybackPosition(
        id: _currentFile.id,
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
      aiDubbingEnabled = values.aiDubbingEnabled;
      aiSubtitleLanguage = values.language;
      aiSubtitleFontScale = values.fontScale;
    });
    if (aiDubbingEnabled) unawaited(_configureDubbingTts());
    if (aiSubtitlesEnabled || aiDubbingEnabled) {
      _startSubtitleLoop();
      if (aiSubtitlesEnabled) _scheduleDiagnosticSubtitle();
    }
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
      if (!enabled) _activeCaption = null;
    });
    if (enabled) {
      // Keep the selected native track active so MediaKit continues emitting
      // live cues, but hide only its renderer through the Video widget above.
      _lastSubtitleCueText = null;
      _hasReceivedSubtitleCue = false;
    }
    await AiSubtitlePreferences.save(enabled: enabled);
    if (!mounted) return;
    if (enabled) {
      _startSubtitleLoop();
      _scheduleDiagnosticSubtitle();
      _showHud('AI CC on', Icons.closed_caption_rounded);
    } else {
      if (!aiDubbingEnabled) _stopSubtitleLoop();
      _diagnosticSubtitleTimer?.cancel();
      await player.setSubtitleTrack(_selectedNativeSubtitleTrack);
      if (!mounted) return;
      _showHud('AI CC off', Icons.closed_caption_disabled_rounded);
    }
  }

  void _scheduleDiagnosticSubtitle() {
    _diagnosticSubtitleTimer?.cancel();
    if (!aiSubtitlesEnabled || aiSubtitleLanguage != 'Bengali') return;
    _diagnosticSubtitleTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || !aiSubtitlesEnabled || _hasReceivedSubtitleCue) return;
      final position = player.state.position;
      setState(
        () => _activeCaption = const AiCaption(
          text: 'AI Subtitle Active (বাংলা)',
          start: Duration.zero,
          end: Duration(seconds: 3),
        ),
      );
      Timer(const Duration(seconds: 3), () {
        if (!mounted || _hasReceivedSubtitleCue) return;
        final current = player.state.position;
        if (current >= position) setState(() => _activeCaption = null);
      });
    });
  }

  Future<void> _setAiSubtitleLanguage(String language) async {
    _lastDubbedCaption = null;
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
    if ((!aiSubtitlesEnabled && !aiDubbingEnabled) ||
        _subtitleRequestInFlight) {
      return;
    }
    _subtitleRequestInFlight = true;
    try {
      final result = await aiSubtitleService.recognizeAndTranslate(
        sourcePath: _currentFile.path,
        position: player.state.position,
        language: _selectedSubtitleLanguage,
        sourceText: _embeddedSubtitleText,
      );
      if (!mounted || (!aiSubtitlesEnabled && !aiDubbingEnabled)) return;
      if (result.caption != null) {
        final caption = result.caption!;
        if (aiSubtitlesEnabled) setState(() => _activeCaption = caption);
        if (aiDubbingEnabled) unawaited(_speakDubbingCaption(caption));
      }
    } on AiSubtitleException {
      // Direct cue translation is best-effort; keep playback unobstructed.
    } catch (_) {
      // Direct cue translation is best-effort; keep playback unobstructed.
    } finally {
      _subtitleRequestInFlight = false;
    }
  }

  Future<void> _configureDubbingTts() async {
    try {
      await _dubbingTts.awaitSpeakCompletion(true);
      await _dubbingTts.setLanguage(_selectedSubtitleLanguage.code);
      await _dubbingTts.setVolume(1.0);
    } catch (_) {
      // The device TTS engine may not expose every selected language.
    }
  }

  String _sanitizeDubbingText(String input) {
    final withoutAnnotations = input
        .replaceAll(RegExp(r'(\[[^\]]*\]|\([^)]*\)|\{[^}]*\})'), ' ')
        .replaceAll(RegExp(r'[♪♫]+'), ' ');
    return withoutAnnotations.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _finishNearCompleteDubbingSpeech() async {
    if (!_dubbingSpeechActive || _dubbingCueEnd == null) return;
    final remaining = _dubbingCueEnd! - player.state.position;
    if (remaining < Duration.zero ||
        remaining > const Duration(milliseconds: 300)) {
      return;
    }
    final completer = _dubbingSpeechCompleter;
    if (completer == null) return;
    try {
      await completer.future.timeout(const Duration(milliseconds: 300));
    } on TimeoutException {
      // Do not delay the next cue indefinitely if the engine stalls.
    }
  }

  Future<void> _speakDubbingCaption(AiCaption caption) async {
    if (!aiDubbingEnabled) return;
    final text = _sanitizeDubbingText(caption.text);
    if (text.isEmpty) return;
    if (text == _lastDubbedCaption) return;
    final cueDuration = caption.end - caption.start;
    final durationSeconds = cueDuration.inMilliseconds / 1000;
    if (durationSeconds <= 0) return;
    _lastDubbedCaption = text;
    final requestId = ++_dubbingRequestId;
    await _finishNearCompleteDubbingSpeech();
    try {
      await _dubbingTts.stop();
      if (!aiDubbingEnabled || requestId != _dubbingRequestId) return;
      final wordCount = RegExp(r'\S+').allMatches(text).length;
      final estimatedTimeNeeded = (wordCount == 0 ? 1 : wordCount) * .35;
      final targetRate = (estimatedTimeNeeded / durationSeconds)
          .clamp(.9, 1.65)
          .toDouble();
      await _dubbingTts.setSpeechRate(targetRate);
      try {
        await _dubbingTts.setLanguage(_selectedSubtitleLanguage.code);
      } catch (_) {}
      _dubbingRestorationVolume ??= player.state.volume;
      await player.setVolume((_dubbingRestorationVolume! * .25).clamp(0, 100));
      final speechCompleter = Completer<void>();
      _dubbingSpeechCompleter = speechCompleter;
      _dubbingSpeechActive = true;
      _dubbingCueEnd = caption.end;
      try {
        await _dubbingTts.speak(text);
      } finally {
        if (!speechCompleter.isCompleted) speechCompleter.complete();
      }
    } catch (_) {
      // TTS is experimental and must never interrupt video playback.
    } finally {
      if (requestId == _dubbingRequestId) {
        _dubbingSpeechActive = false;
        _dubbingSpeechCompleter = null;
        _dubbingCueEnd = null;
        await _restoreDubbingVolume();
      }
    }
  }

  Future<void> _restoreDubbingVolume() async {
    final volume = _dubbingRestorationVolume;
    _dubbingRestorationVolume = null;
    if (volume == null || _playerDisposed) return;
    try {
      await player.setVolume(volume);
    } catch (_) {}
  }

  Future<void> _setAiDubbingEnabled(bool enabled) async {
    if (!mounted) return;
    if (!enabled) {
      _dubbingRequestId++;
      _lastDubbedCaption = null;
      try {
        await _dubbingTts.stop();
      } catch (_) {}
      await _restoreDubbingVolume();
    }
    setState(() => aiDubbingEnabled = enabled);
    await AiSubtitlePreferences.save(aiDubbingEnabled: enabled);
    if (enabled) {
      await _configureDubbingTts();
      if (!aiSubtitlesEnabled) _startSubtitleLoop();
      _showHud('AI dubbing on', Icons.record_voice_over_rounded);
    } else if (!aiSubtitlesEnabled) {
      _stopSubtitleLoop();
    }
  }

  Future<bool> _confirmAiDubbingEnable(BuildContext dialogContext) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Feature Under Creation'),
        content: const Text(
          'এই ফিচারটি বর্তমানে আন্ডার ক্রিয়েশন প্রসেসিং '
          '(Under Creation / Testing) রয়েছে। ডায়লগের স্বাভাবিক গতি বা '
          'ভয়েসের টোন কিছুটা রোবোটিক হতে পারে। আপনি কি এটি চালু করতে চান?\n\n'
          'This feature is currently under creation/processing. Voice timing '
          'and tone may vary. Do you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel / বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable Anyway / চালু করুন'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _handleAiDubbingToggle({
    required BuildContext dialogContext,
    required bool value,
    required ValueChanged<bool> updateSheet,
  }) async {
    if (!value) {
      updateSheet(false);
      await _setAiDubbingEnabled(false);
      return;
    }
    // Deliberately keep the switch off while the confirmation dialog is open.
    updateSheet(false);
    final confirmed = await _confirmAiDubbingEnable(dialogContext);
    if (!confirmed || !mounted) return;
    updateSheet(true);
    await _setAiDubbingEnabled(true);
  }

  void _showAiSubtitleSettings() {
    var enabled = aiSubtitlesEnabled;
    var dubbingEnabled = aiDubbingEnabled;
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: dubbingEnabled,
              title: const Text('AI Voice Dubbing (Beta)'),
              subtitle: const Text(
                'Offline TTS with subtitle-timed audio ducking',
              ),
              secondary: Icon(
                dubbingEnabled
                    ? Icons.record_voice_over_rounded
                    : Icons.voice_over_off_rounded,
                color: dubbingEnabled ? NovaColors.violet : Colors.white54,
              ),
              onChanged: (value) => _handleAiDubbingToggle(
                dialogContext: context,
                value: value,
                updateSheet: (next) =>
                    setSheetState(() => dubbingEnabled = next),
              ),
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
    _swipeDirection = null;
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
    _diagnosticSubtitleTimer?.cancel();
    _dubbingRequestId++;
    unawaited(_dubbingTts.stop());
    if (_dubbingRestorationVolume != null) {
      unawaited(_restoreDubbingVolume());
    }
    _sensorSubscription?.cancel();
    _embeddedSubtitleSubscription?.cancel();
    _playingSubscription?.cancel();
    _completionSubscription?.cancel();
    _pipChannel.setMethodCallHandler(null);
    _queueIndicatorTimer?.cancel();
    _sleepTimer?.cancel();
    unawaited(_castController.disconnect());
    _saveResumePosition(updateLibrary: false);
    aiSubtitleService.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(_releasePlayerResources());
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
      final swipeThreshold = size.width * .16;
      if (dx.abs() >= swipeThreshold) {
        _swipeDirection = dx < 0 ? 1 : -1;
        _seekPreview = null;
      } else {
        final current = player.state.position;
        final delta = Duration(milliseconds: (dx / size.width * 90000).round());
        setState(() => _seekPreview = current + delta);
      }
    } else if (start.dx < size.width / 2) {
      _updateBrightness(_startBrightness - dy / size.height);
    } else {
      _updateVolume(_startVolume - dy / size.height);
    }
  }

  Future<void> _finishGesture() async {
    final swipeDirection = _swipeDirection;
    _swipeDirection = null;
    if (swipeDirection != null) {
      await _playQueueOffset(swipeDirection);
      _gestureStart = null;
      _seekPreview = null;
      return;
    }
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

  int? _swipeDirection;

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
      sourceName: _currentFile.name,
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
      sourcePath: _currentFile.path,
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
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        visible: !aiSubtitlesEnabled,
                      ),
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
              if (_queueIndicatorLabel != null)
                Positioned(
                  top: size.height * .22,
                  left: _queueIndicatorDirection > 0 ? null : 20,
                  right: _queueIndicatorDirection > 0 ? 20 : null,
                  child: _QueueNavigationIndicator(
                    key: ValueKey(_queueIndicatorLabel),
                    label: _queueIndicatorLabel!,
                    direction: _queueIndicatorDirection,
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
                    left: 12,
                    right: 12,
                    bottom: 24,
                    child: SafeArea(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        reverseDuration: const Duration(milliseconds: 140),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _AiCaptionPill(
                          key: ValueKey(caption.text),
                          text: caption.text,
                          fontScale: aiSubtitleFontScale,
                        ),
                      ),
                    ),
                  );
                },
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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (orientation == Orientation.landscape &&
                              systemTime.isNotEmpty)
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
                          _ControlsOverlay(
                            file: _currentFile,
                            player: player,
                            onBack: () => Navigator.pop(context),
                            onPrevious: () => _playQueueOffset(-1),
                            onStop: _stopAndClose,
                            onNext: () => _playQueueOffset(1),
                            onLock: () => setState(() {
                              locked = true;
                              controlsVisible = false;
                            }),
                            onMore: _showOptions,
                            onPip: _enterPip,
                            onCast: _showCastSheet,
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
                        ],
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

  Future<void> _showCastSheet() async {
    var devicesFuture = _castController.discover();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final connected = _castConnected && _castController.isConnected;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    connected ? 'Casting to TV' : 'Cast to TV',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (connected) ...[
                    Text(
                      _castController.session!.device.name,
                      style: const TextStyle(color: NovaColors.muted),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () => _castController.seek(Duration.zero),
                          icon: const Icon(Icons.replay_10_rounded),
                        ),
                        IconButton(
                          onPressed: () async {
                            await _castController.play();
                            setSheetState(() {});
                          },
                          icon: const Icon(
                            Icons.play_arrow_rounded,
                            color: NovaColors.cyan,
                            size: 32,
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            await _castController.pause();
                            setSheetState(() {});
                          },
                          icon: const Icon(
                            Icons.pause_rounded,
                            color: NovaColors.cyan,
                            size: 32,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              _castController.seek(player.state.position),
                          icon: const Icon(Icons.forward_10_rounded),
                        ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.volume_up_outlined),
                      title: const Text('TV volume'),
                      trailing: SizedBox(
                        width: 170,
                        child: Slider(
                          value: .75,
                          onChanged: (value) =>
                              _castController.setVolume(value),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _castController.disconnect();
                          if (mounted) setState(() => _castConnected = false);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.cast_connected_rounded),
                        label: const Text('Disconnect'),
                      ),
                    ),
                  ] else ...[
                    FutureBuilder<List<CastDevice>>(
                      future: devicesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: NovaColors.cyan,
                              ),
                            ),
                          );
                        }
                        final devices = snapshot.data ?? const <CastDevice>[];
                        if (devices.isEmpty) {
                          return Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  'No Chromecast or DLNA devices found on this Wi-Fi network.',
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: () => setSheetState(
                                  () => devicesFuture = _castController
                                      .discover(),
                                ),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Scan again'),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: devices
                              .map(
                                (device) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    device.protocol == CastProtocol.chromecast
                                        ? Icons.cast
                                        : Icons.tv_rounded,
                                    color: NovaColors.cyan,
                                  ),
                                  title: Text(device.name),
                                  subtitle: Text(
                                    device.protocol == CastProtocol.chromecast
                                        ? 'Chromecast'
                                        : 'DLNA / Smart TV',
                                  ),
                                  onTap: () async {
                                    setSheetState(() => _castBusy = true);
                                    try {
                                      await _castController.connectAndLoad(
                                        device,
                                        _currentFile,
                                      );
                                      await player.pause();
                                      if (mounted) {
                                        setState(() => _castConnected = true);
                                        _showHud(
                                          'Casting to ${device.name}',
                                          Icons.cast_connected_rounded,
                                        );
                                      }
                                      if (sheetContext.mounted) {
                                        Navigator.pop(sheetContext);
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        _showHud(
                                          'Unable to connect to TV',
                                          Icons.cast_outlined,
                                        );
                                      }
                                    } finally {
                                      if (sheetContext.mounted) {
                                        setSheetState(() => _castBusy = false);
                                      }
                                    }
                                  },
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    if (_castBusy)
                      const LinearProgressIndicator(color: NovaColors.cyan),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handlePipCall(MethodCall call) async {
    if (call.method != 'pipAction' || call.arguments != 'play_pause') {
      return;
    }
    await player.playOrPause();
    await _updatePipState(player.state.playing);
  }

  Future<void> _updatePipState(bool playing) async {
    final width = player.state.width;
    final height = player.state.height;
    try {
      await _pipChannel.invokeMethod('setPipState', {
        'enabled': true,
        'playing': playing,
        if (width != null && height != null && width > 0 && height > 0)
          'width': width,
        if (width != null && height != null && width > 0 && height > 0)
          'height': height,
      });
    } on PlatformException {
      // PiP is optional; playback must remain unaffected if unavailable.
    }
  }

  Future<void> _enterPip() async {
    try {
      await _updatePipState(player.state.playing);
      await _pipChannel.invokeMethod('enterPip', {
        'width': player.state.width ?? 16,
        'height': player.state.height ?? 9,
      });
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
      builder: (_) {
        var dubbingEnabled = aiDubbingEnabled;
        return StatefulBuilder(
          builder: (context, setSheetState) => _PlayerOptions(
            player: player,
            aiDubbingEnabled: dubbingEnabled,
            sleepTimerLabel: _sleepUntilVideoEnd
                ? 'End of current video'
                : _sleepRemaining == null
                ? 'Off'
                : '${_formatSleepRemaining(_sleepRemaining!)} remaining',
            onSleepTimer: () => _showSleepTimerSheet(
              context,
              onChanged: () => setSheetState(() {}),
            ),
            onSubtitle: _showEmbeddedSubtitleTracks,
            onAiDubbingChanged: (value) => _handleAiDubbingToggle(
              dialogContext: context,
              value: value,
              updateSheet: (next) => setSheetState(() => dubbingEnabled = next),
            ),
          ),
        );
      },
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
              _selectedNativeSubtitleTrack = SubtitleTrack.no();
              _embeddedSubtitleText = null;
              _lastSubtitleCueText = null;
              _hasReceivedSubtitleCue = false;
              _activeCaption = null;
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
                _selectedNativeSubtitleTrack = entry.value;
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

  String _subtitleTrackLabel(SubtitleTrack track) =>
      trackLanguageLabel(title: track.title, language: track.language);

  Future<void> _pickSubtitle() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (file?.path == null) return;
    final externalTrack = SubtitleTrack.uri(
      file!.path!,
      title: file.name,
      language: 'und',
    );
    _selectedNativeSubtitleTrack = externalTrack;
    await player.setSubtitleTrack(externalTrack);
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
    required this.onPrevious,
    required this.onStop,
    required this.onNext,
    required this.onLock,
    required this.onMore,
    required this.onPip,
    required this.onCast,
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
  final VoidCallback onPrevious;
  final VoidCallback onStop;
  final VoidCallback onNext;
  final VoidCallback onLock;
  final VoidCallback onMore;
  final VoidCallback onPip;
  final VoidCallback onCast;
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
                    tooltip: 'Cast to TV',
                    onPressed: onCast,
                    icon: const Icon(Icons.cast_rounded),
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
                builder: (context, snapshot) {
                  final playing = snapshot.data == true;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Previous video',
                        onPressed: () {
                          onPrevious();
                          onInteract();
                        },
                        iconSize: 38,
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Stop and close player',
                        onPressed: () {
                          onStop();
                          onInteract();
                        },
                        iconSize: 38,
                        icon: const Icon(
                          Icons.stop_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: playing ? 'Pause' : 'Play',
                        onPressed: () {
                          player.playOrPause();
                          onInteract();
                        },
                        iconSize: 64,
                        icon: Icon(
                          playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next video',
                        onPressed: () {
                          onNext();
                          onInteract();
                        },
                        iconSize: 38,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  );
                },
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

class _QueueNavigationIndicator extends StatelessWidget {
  const _QueueNavigationIndicator({
    super.key,
    required this.label,
    required this.direction,
  });

  final String label;
  final int direction;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: direction > 0 ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: NovaColors.cyan.withValues(alpha: .6)),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 2),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                direction > 0
                    ? Icons.skip_next_rounded
                    : Icons.skip_previous_rounded,
                color: NovaColors.cyan,
                size: 20,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiCaptionPill extends StatelessWidget {
  const _AiCaptionPill({
    super.key,
    required this.text,
    required this.fontScale,
  });

  final String text;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18 * fontScale,
                height: 1.18,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(offset: Offset(-1.4, 0), color: Colors.black),
                  Shadow(offset: Offset(1.4, 0), color: Colors.black),
                  Shadow(offset: Offset(0, -1.4), color: Colors.black),
                  Shadow(offset: Offset(0, 1.4), color: Colors.black),
                ],
              ),
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
  const _PlayerOptions({
    required this.player,
    required this.onSubtitle,
    required this.aiDubbingEnabled,
    required this.onAiDubbingChanged,
    required this.sleepTimerLabel,
    required this.onSleepTimer,
  });
  final Player player;
  final VoidCallback onSubtitle;
  final bool aiDubbingEnabled;
  final ValueChanged<bool> onAiDubbingChanged;
  final String sleepTimerLabel;
  final VoidCallback onSleepTimer;
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
      SwitchListTile.adaptive(
        dense: landscape,
        contentPadding: EdgeInsets.zero,
        value: aiDubbingEnabled,
        title: const Text('AI Voice Dubbing (Beta)'),
        subtitle: const Text('Offline TTS with subtitle-timed ducking'),
        secondary: Icon(
          aiDubbingEnabled
              ? Icons.record_voice_over_rounded
              : Icons.voice_over_off_rounded,
          color: aiDubbingEnabled ? NovaColors.violet : Colors.white54,
        ),
        onChanged: onAiDubbingChanged,
      ),
      ListTile(
        dense: landscape,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.bedtime_outlined, color: NovaColors.cyan),
        title: const Text('Sleep timer'),
        subtitle: Text(sleepTimerLabel),
        onTap: onSleepTimer,
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
            ...tracks.asMap().entries.map(
              (entry) => ListTile(
                title: Text(
                  trackLanguageLabel(
                    title: entry.value.title,
                    language: entry.value.language,
                  ),
                ),
                subtitle: Text(
                  entry.value.codec == null
                      ? 'Embedded audio track ${entry.key + 1}'
                      : 'Embedded · ${entry.value.codec}',
                ),
                leading: const Icon(Icons.audiotrack),
                onTap: () {
                  player.setAudioTrack(entry.value);
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
