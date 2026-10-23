import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_audio_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_audio_flutter/return_code.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../../../core/tool_notification_service.dart';

class AudioExtractionService {
  const AudioExtractionService();

  static const _mediaChannel = MethodChannel('com.novaplay/media');
  static const _minimumExtractionTimeout = Duration(minutes: 10);
  static const _unknownDurationTimeout = Duration(minutes: 30);

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
    final durationBasedTimeout = duration == null || duration <= Duration.zero
        ? _unknownDurationTimeout
        : duration * 2 + const Duration(minutes: 5);
    final extractionTimeout = durationBasedTimeout < _minimumExtractionTimeout
        ? _minimumExtractionTimeout
        : durationBasedTimeout;
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
    Timer? timeout;
    try {
      timeout = Timer(extractionTimeout, () {
        if (!complete.isCompleted) {
          complete.completeError(
            TimeoutException('Audio extraction timed out', extractionTimeout),
          );
        }
      });
      await FFmpegKit.executeAsync(
        command,
        (session) async {
          if (complete.isCompleted) return;
          try {
            final returnCode = await session.getReturnCode();
            if (complete.isCompleted) return;
            if (!ReturnCode.isSuccess(returnCode)) {
              final output = await session.getOutput() ?? '';
              throw StateError(
                'FFmpeg audio extraction failed (return code $returnCode). ${output.trim()}',
              );
            }
            final file = File(outputPath);
            if (!await file.exists() || await file.length() == 0) {
              throw StateError('FFmpeg did not produce an audio file.');
            }
            final published = await _mediaChannel
                .invokeMethod<String>(
                  'publishAudio',
                  {'tempPath': outputPath, 'displayName': '$safeName.mp3'},
                )
                .timeout(const Duration(seconds: 10));
            if (published == null || published.isEmpty) {
              throw StateError('The published Music/NovaPlay path was empty.');
            }
            if (complete.isCompleted) return;
            await ToolNotificationService.show(
              title: 'Video to MP3 Complete 🎵',
              body: 'Audio generated successfully: $safeName.mp3',
            );
            if (complete.isCompleted) return;
            try {
              onProgress?.call(1.0);
            } catch (_) {}
            if (!complete.isCompleted) complete.complete(published);
          } catch (error, stackTrace) {
            if (!complete.isCompleted) complete.completeError(error, stackTrace);
          }
        },
        null,
        (statistics) {
          if (complete.isCompleted) return;
          if (durationSeconds == null || durationSeconds <= 0) return;
          final progress = (statistics.getTime() / 1000 / durationSeconds)
              .clamp(0.0, 0.99)
              .toDouble();
          try {
            onProgress?.call(progress);
          } catch (_) {}
        },
      );
      return await complete.future;
    } finally {
      timeout?.cancel();
    }
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
