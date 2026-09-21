import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_audio_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_audio_flutter/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ringtone_set_plus/ringtone_set_plus.dart';
import 'package:share_plus/share_plus.dart';

class AudioCutResult {
  const AudioCutResult({required this.path, required this.duration});

  final String path;
  final Duration duration;
}

class AudioCutterService {
  AudioCutterService._();

  static final instance = AudioCutterService._();
  static const _mediaChannel = MethodChannel('com.novaplay/media');

  Future<AudioCutResult> trim({
    required String inputPath,
    required Duration start,
    required Duration end,
    String? outputName,
  }) async {
    if (end <= start) {
      throw ArgumentError('End time must be after start time.');
    }

    final input = File(inputPath);
    if (!await input.exists()) {
      throw StateError('The source audio file no longer exists.');
    }

    final documents = await getApplicationDocumentsDirectory();
    final outputDirectory = Directory(
      '${documents.path}/Music/NovaPlay_Trimmed',
    );
    await outputDirectory.create(recursive: true);

    final requestedName = outputName ??
        'NovaPlay_Cut_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final safeName = _safeName(requestedName);
    final name = safeName.toLowerCase().endsWith('.m4a')
        ? safeName
        : '$safeName.m4a';
    final output = File('${outputDirectory.path}/$name');
    if (await output.exists()) await output.delete();

    final startSeconds = _seconds(start);
    final endSeconds = _seconds(end);

    // Re-encoding is the reliable path for frame-accurate cuts and avoids
    // stream-copy failures on files with unusual timestamps/codecs.
    final reencodeArguments = [
      '-y',
      '-i',
      _quote(input.path),
      '-ss',
      startSeconds,
      '-to',
      endSeconds,
      '-vn',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      _quote(output.path),
    ].join(' ');
    final reencodeResult = await _execute(reencodeArguments, output);
    if (reencodeResult.success) {
      return AudioCutResult(path: output.path, duration: end - start);
    }

    if (await output.exists()) await output.delete();

    // Keep stream copy as a fallback for formats/codecs that the bundled
    // encoder cannot handle, while still returning a useful diagnostic.
    final copyArguments = [
      '-y',
      '-ss',
      startSeconds,
      '-i',
      _quote(input.path),
      '-to',
      _seconds(end - start),
      '-vn',
      '-c',
      'copy',
      _quote(output.path),
    ].join(' ');
    final copyResult = await _execute(copyArguments, output);
    if (!copyResult.success) {
      throw StateError(
        'Audio trimming failed (re-encode ${reencodeResult.returnCode}; '
        'stream copy ${copyResult.returnCode}). '
        '${copyResult.output.isEmpty ? reencodeResult.output : copyResult.output}',
      );
    }

    return AudioCutResult(path: output.path, duration: end - start);
  }

  Future<_FfmpegResult> _execute(String command, File output) async {
    try {
      debugPrint('NovaPlay FFmpeg command: $command');
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final logs = await session.getOutput() ?? '';
      final exists = await output.exists();
      final hasContent = exists && await output.length() > 0;
      final success = ReturnCode.isSuccess(returnCode) && hasContent;
      if (!success) {
        debugPrint(
          'NovaPlay FFmpeg failed. returnCode=$returnCode output=$logs',
        );
      }
      return _FfmpegResult(
        success: success,
        returnCode: returnCode.toString(),
        output: logs.trim(),
      );
    } catch (error, stackTrace) {
      debugPrint('NovaPlay FFmpeg exception: $error\n$stackTrace');
      return _FfmpegResult(
        success: false,
        returnCode: 'exception',
        output: error.toString(),
      );
    }
  }

  Future<String> saveToMusic(AudioCutResult result, {String? title}) async {
    final displayName = '${_safeName(title ?? 'NovaPlay Audio')}.m4a';
    final published = await _mediaChannel.invokeMethod<String>('publishAudio', {
      'tempPath': result.path,
      'displayName': displayName,
    });
    if (published == null || published.isEmpty) {
      throw StateError('Unable to save audio to Music/NovaPlay.');
    }
    return published;
  }

  Future<void> setAsRingtone(AudioCutResult result) async {
    await RingtoneSet.setRingtoneFromFile(File(result.path));
  }

  Future<void> setAsNotification(AudioCutResult result) async {
    await RingtoneSet.setNotificationFromFile(File(result.path));
  }

  Future<void> setAsAlarm(AudioCutResult result) async {
    await RingtoneSet.setAlarmFromFile(File(result.path));
  }

  Future<ShareResult> share(AudioCutResult result, {String? title}) {
    return SharePlus.instance.share(
      ShareParams(
        title: title ?? 'Share NovaPlay audio clip',
        files: [XFile(result.path, mimeType: 'audio/mp4')],
      ),
    );
  }

  String _seconds(Duration duration) =>
      (duration.inMilliseconds / 1000).toStringAsFixed(3);

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  String _safeName(String value) {
    final withoutExtension = value.replaceFirst(
      RegExp(r'\.(mp3|m4a|aac|wav)$', caseSensitive: false),
      '',
    );
    final cleaned = withoutExtension.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    return cleaned.isEmpty ? 'NovaPlay_Audio' : cleaned;
  }
}

class _FfmpegResult {
  const _FfmpegResult({
    required this.success,
    required this.returnCode,
    required this.output,
  });

  final bool success;
  final String returnCode;
  final String output;
}

final audioCutterService = AudioCutterService.instance;
