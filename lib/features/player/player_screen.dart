import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/domain/video_file.dart';
import 'capture_service.dart';
import 'precision_scrubber.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.file});
  final VideoFile file;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _pipChannel = MethodChannel('com.novaplay/player');
  late final Player player;
  late final VideoController controller;
  Timer? _hideTimer;
  Timer? _statusTimer;
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
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

  @override
  void initState() {
    super.initState();
    player = Player(configuration: const PlayerConfiguration(pitch: true));
    controller = VideoController(player);
    player.open(Media(widget.file.path), play: true);
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
    _armControlsTimer();
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
    _sensorSubscription?.cancel();
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

  Future<void> _doubleTap(TapDownDetails details, Size size) async {
    final delta = details.localPosition.dx < size.width / 2
        ? const Duration(seconds: -10)
        : const Duration(seconds: 10);
    final next = player.state.position + delta;
    await player.seek(
      Duration(
        milliseconds: next.inMilliseconds.clamp(
          0,
          player.state.duration.inMilliseconds,
        ),
      ),
    );
    _showHud(
      '${delta.isNegative ? '−' : '+'}10s',
      delta.isNegative ? Icons.replay_10_rounded : Icons.forward_10_rounded,
    );
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
              else if (controlsVisible)
                Positioned.fill(
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
                    onOrientation: _toggleManualOrientation,
                    onAspectRatio: _cycleAspectRatio,
                    orientationLocked: orientationLocked,
                    landscapeLocked: landscapeLocked,
                    aspectMode: aspectMode,
                    onInteract: _armControlsTimer,
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
      builder: (_) => _PlayerOptions(player: player, onSubtitle: _pickSubtitle),
    );
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
    if (mounted) Navigator.pop(context);
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
  final VoidCallback onOrientation;
  final VoidCallback onAspectRatio;
  final bool orientationLocked;
  final bool landscapeLocked;
  final String aspectMode;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent, Colors.black87],
            stops: [0, .42, 1],
          ),
        ),
        child: SafeArea(
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
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
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
          const SizedBox(height: 18),
          const Text(
            'Speed',
            style: TextStyle(
              color: NovaColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
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
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.audiotrack_rounded,
              color: NovaColors.cyan,
            ),
            title: const Text('Audio track'),
            subtitle: Text(
              '${player.state.tracks.audio.length} embedded tracks found',
            ),
            onTap: () => _showAudioTracks(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.subtitles_outlined,
              color: NovaColors.violet,
            ),
            title: const Text('Subtitles'),
            subtitle: Text(
              '${player.state.tracks.subtitle.length} embedded tracks found',
            ),
            onTap: onSubtitle,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.aspect_ratio_rounded,
              color: NovaColors.green,
            ),
            title: const Text('Aspect ratio'),
            subtitle: const Text('Fit  •  Fill  •  Stretch'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );

  void _showAudioTracks(BuildContext context) {
    final tracks = player.state.tracks.audio;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      builder: (_) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          shrinkWrap: true,
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
