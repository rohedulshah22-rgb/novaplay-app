import 'dart:async';

import 'package:dart_cast/dart_cast.dart';

import '../media/domain/video_file.dart';

class NovaCastController {
  NovaCastController()
    : _service = CastService(
        discoveryProviders: [
          ChromecastDiscoveryProvider(),
          DlnaDiscoveryProvider(),
        ],
        sessionFactory: (device) => switch (device.protocol) {
          CastProtocol.chromecast => ChromecastSession(device: device),
          CastProtocol.dlna => DlnaSession.fromDevice(device),
          CastProtocol.airplay => throw UnsupportedError(
            'AirPlay is not enabled in NovaPlay',
          ),
        },
      );

  final CastService _service;
  StreamSubscription<List<CastDevice>>? _discoverySubscription;
  CastSession? _session;

  CastSession? get session => _session;
  bool get isConnected => _session != null;

  Future<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _discoverySubscription?.cancel();
    final completer = Completer<List<CastDevice>>();
    _discoverySubscription = _service
        .startDiscovery(
          protocols: {CastProtocol.chromecast, CastProtocol.dlna},
          timeout: timeout,
        )
        .listen((devices) {
          if (!completer.isCompleted) completer.complete(devices);
        });
    try {
      return await completer.future.timeout(
        timeout + const Duration(seconds: 2),
      );
    } on TimeoutException {
      return const [];
    }
  }

  Future<void> connectAndLoad(CastDevice device, VideoFile file) async {
    final session = await _service.connect(device);
    _session = session;
    final type = switch (file.extension.toLowerCase()) {
      'mkv' => CastMediaType.mkv,
      'ts' || 'm2ts' => CastMediaType.mpegTs,
      _ => CastMediaType.mp4,
    };
    await session.loadMedia(
      CastMedia.file(
        filePath: file.path,
        type: type,
        title: file.name,
        duration: file.duration > Duration.zero ? file.duration : null,
        startPosition: file.progress > Duration.zero ? file.progress : null,
      ),
    );
  }

  Future<void> play() => _session?.play() ?? Future.value();
  Future<void> pause() => _session?.pause() ?? Future.value();
  Future<void> stop() => _session?.stop() ?? Future.value();
  Future<void> seek(Duration position) =>
      _session?.seek(position) ?? Future.value();
  Future<void> setVolume(double volume) =>
      _session?.setVolume(volume.clamp(0.0, 1.0).toDouble()) ?? Future.value();

  Future<void> disconnect() async {
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    await _service.dispose();
    _session = null;
  }
}
