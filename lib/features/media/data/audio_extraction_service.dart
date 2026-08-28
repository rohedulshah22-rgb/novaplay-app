import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class AudioExtractionService {
  const AudioExtractionService();

  static const _mediaChannel = MethodChannel('com.novaplay/media');

  Future<String?> extractToMusic({
    required String sourcePath,
    required String sourceName,
    Duration? duration,
    void Function(double)? onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final safeName = _baseName(sourceName);
    final outputPath = path.join(directory.path, '${safeName}_${_stamp()}.mp3');
    final durationSeconds = duration == null || duration <= Duration.zero
        ? null
        : duration.inMilliseconds / 1000;
    final command = [
      '-y',
      '-i',
      _quote(sourcePath),
      '-map',
      '0:a:0?',
      '-vn',
      '-c:a',
      'libmp3lame',
      '-q:a',
      '2',
      _quote(outputPath),
    ].join(' ');

    final complete = Completer<String?>();
    await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (!ReturnCode.isSuccess(returnCode)) {
          if (!complete.isCompleted) complete.complete(null);
          return;
        }
        try {
          final published = await _mediaChannel.invokeMethod<String>(
            'publishAudio',
            {'tempPath': outputPath, 'displayName': '$safeName.mp3'},
          );
          if (!complete.isCompleted) complete.complete(published);
        } on PlatformException {
          if (!complete.isCompleted) complete.complete(null);
        }
      },
      null,
      (statistics) {
        if (durationSeconds == null || durationSeconds <= 0) return;
        final progress = (statistics.getTime() / 1000 / durationSeconds)
            .clamp(0.0, 0.99)
            .toDouble();
        onProgress?.call(progress);
      },
    );
    return complete.future;
  }

  String _quote(String value) => '"${value.replaceAll('"', '\\"')}"';

  String _baseName(String value) => path
      .basenameWithoutExtension(value)
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String _stamp() => DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '')
      .substring(0, 14);
}
