import 'dart:io';

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
    final directory = await getTemporaryDirectory();
    final name = _safeName(
      outputName ?? 'NovaPlay_Cut_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    final output = File('${directory.path}/$name');
    if (await output.exists()) await output.delete();

    final command = [
      '-y',
      '-ss',
      _seconds(start),
      '-i',
      _quote(inputPath),
      '-t',
      _seconds(end - start),
      '-vn',
      '-c:a',
      'libmp3lame',
      '-q:a',
      '2',
      _quote(output.path),
    ].join(' ');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode) || !await output.exists()) {
      final logs = await session.getOutput();
      throw StateError('Audio trimming failed${logs == null ? '' : ': $logs'}');
    }
    return AudioCutResult(path: output.path, duration: end - start);
  }

  Future<String> saveToMusic(AudioCutResult result, {String? title}) async {
    final displayName = '${_safeName(title ?? 'NovaPlay Audio')}.mp3';
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
        files: [XFile(result.path, mimeType: 'audio/mpeg')],
      ),
    );
  }

  String _seconds(Duration duration) =>
      (duration.inMilliseconds / 1000).toStringAsFixed(3);

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  String _safeName(String value) {
    final withoutExtension = value.replaceFirst(
      RegExp(r'\.mp3$', caseSensitive: false),
      '',
    );
    final cleaned = withoutExtension.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    return cleaned.isEmpty ? 'NovaPlay_Audio' : cleaned;
  }
}

final audioCutterService = AudioCutterService.instance;
