import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'ai_subtitle_preferences.dart';

class AiSubtitleService {
  AiSubtitleService({http.Client? client}) : _client = client ?? http.Client();

  static const _defaultModel = String.fromEnvironment(
    'NOVAPLAY_AI_MODEL',
    defaultValue: 'whisper-1',
  );
  static const _endpoint = String.fromEnvironment(
    'NOVAPLAY_AI_SUBTITLE_ENDPOINT',
  );
  static const _apiKey = String.fromEnvironment('NOVAPLAY_OPENAI_API_KEY');

  final http.Client _client;
  bool get isConfigured => _endpoint.isNotEmpty || _apiKey.isNotEmpty;

  Future<AiSubtitleResult> recognizeAndTranslate({
    required String sourcePath,
    required Duration position,
    required AiSubtitleLanguage language,
  }) async {
    final localCaption = await _readLocalSidecarCaption(sourcePath, position);
    if (localCaption != null) {
      return AiSubtitleResult(caption: localCaption, usedLocalFallback: true);
    }

    if (!isConfigured) {
      return const AiSubtitleResult(requiresCloudRelay: true);
    }
    if (sourcePath.startsWith('content://')) {
      return const AiSubtitleResult(requiresCloudRelay: true);
    }

    final audioFile = await _extractAudioWindow(sourcePath, position);
    if (audioFile == null) return const AiSubtitleResult();

    try {
      final transcript = await _transcribe(audioFile, language);
      if (transcript.trim().isEmpty) return const AiSubtitleResult();
      final translated = await _translate(transcript, language);
      final text = translated.trim().isEmpty
          ? transcript.trim()
          : translated.trim();
      return AiSubtitleResult(
        caption: AiCaption(
          text: text,
          start: position,
          end: position + const Duration(seconds: 6),
        ),
      );
    } finally {
      try {
        await audioFile.delete();
      } catch (_) {}
    }
  }

  Future<File?> _extractAudioWindow(
    String sourcePath,
    Duration position,
  ) async {
    final directory = await getTemporaryDirectory();
    final outputPath = path.join(
      directory.path,
      'novaplay_ai_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final command =
        '-y -ss ${_seconds(position)} -i ${_quote(sourcePath)} '
        '-t 6 -vn -ac 1 -ar 16000 -c:a pcm_s16le ${_quote(outputPath)}';
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    final output = File(outputPath);
    if (!ReturnCode.isSuccess(code) || !await output.exists()) return null;
    return output;
  }

  Future<String> _transcribe(
    File audioFile,
    AiSubtitleLanguage language,
  ) async {
    final uri = _endpoint.isNotEmpty
        ? Uri.parse(_endpoint)
        : Uri.parse('https://api.openai.com/v1/audio/transcriptions');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path))
      ..fields['model'] = _defaultModel
      ..fields['response_format'] = 'json'
      ..fields['target_language'] = language.code;
    if (_apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_apiKey';
    }
    final response = await _client.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiSubtitleException(
        'Speech recognition failed (${response.statusCode}).',
      );
    }
    final json = _decodeObject(body);
    return _readText(json) ?? '';
  }

  Future<String> _translate(
    String transcript,
    AiSubtitleLanguage language,
  ) async {
    if (_endpoint.isNotEmpty) return transcript;
    if (_apiKey.isEmpty || language.code == 'en') return transcript;

    final response = await _client.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': const String.fromEnvironment(
          'NOVAPLAY_TRANSLATION_MODEL',
          defaultValue: 'gpt-4o-mini',
        ),
        'temperature': 0,
        'messages': [
          {
            'role': 'system',
            'content':
                'Translate spoken dialogue into ${language.label}. '
                'Return only the translation, with no explanations.',
          },
          {'role': 'user', 'content': transcript},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiSubtitleException('Translation failed (${response.statusCode}).');
    }
    final json = _decodeObject(response.body);
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
    }
    return transcript;
  }

  Future<AiCaption?> _readLocalSidecarCaption(
    String sourcePath,
    Duration position,
  ) async {
    if (sourcePath.startsWith('content://')) return null;
    final basePath = path.withoutExtension(sourcePath);
    for (final extension in ['.srt', '.vtt']) {
      final file = File('$basePath$extension');
      if (!await file.exists()) continue;
      final caption = await _parseCaptionFile(file, position);
      if (caption != null) return caption;
    }
    return null;
  }

  Future<AiCaption?> _parseCaptionFile(File file, Duration position) async {
    final lines = await file.readAsLines();
    for (var index = 0; index < lines.length; index++) {
      final match = _timestampPattern.firstMatch(lines[index]);
      if (match == null) continue;
      final start = _parseTimestamp(match.group(1)!);
      final end = _parseTimestamp(match.group(2)!);
      if (position < start || position > end) continue;
      final text = <String>[];
      for (var next = index + 1; next < lines.length; next++) {
        final line = lines[next].trim();
        if (line.isEmpty) break;
        if (_timestampPattern.hasMatch(line)) break;
        if (!RegExp(r'^\d+$').hasMatch(line)) text.add(line);
      }
      final value = text.join('\n').replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (value.isEmpty) return null;
      return AiCaption(text: value, start: start, end: end);
    }
    return null;
  }

  static final _timestampPattern = RegExp(
    r'((?:\d{2}:)?\d{2}:\d{2}[,.]\d{3})\s*-->\s*((?:\d{2}:)?\d{2}:\d{2}[,.]\d{3})',
  );

  Duration _parseTimestamp(String value) {
    final parts = value.replaceAll(',', '.').split(':');
    final seconds = double.parse(parts.removeLast());
    final minutes = int.parse(parts.removeLast());
    final hours = parts.isEmpty ? 0 : int.parse(parts.removeLast());
    return Duration(
      milliseconds: ((hours * 3600 + minutes * 60 + seconds) * 1000).round(),
    );
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const AiSubtitleException('AI service returned an invalid response.');
  }

  String? _readText(Map<String, dynamic> json) {
    for (final key in [
      'translated_text',
      'translation',
      'text',
      'transcript',
    ]) {
      final value = json[key];
      if (value is String) return value;
    }
    final segments = json['segments'];
    if (segments is List) {
      return segments
          .whereType<Map>()
          .map((segment) => segment['translated_text'] ?? segment['text'])
          .whereType<String>()
          .join(' ');
    }
    return null;
  }

  String _quote(String value) => '"${value.replaceAll('"', '\\"')}"';
  String _seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(3);

  void dispose() => _client.close();
}

class AiSubtitleResult {
  const AiSubtitleResult({
    this.caption,
    this.requiresCloudRelay = false,
    this.usedLocalFallback = false,
  });

  final AiCaption? caption;
  final bool requiresCloudRelay;
  final bool usedLocalFallback;
}

class AiCaption {
  const AiCaption({required this.text, required this.start, required this.end});

  final String text;
  final Duration start;
  final Duration end;
}

class AiSubtitleException implements Exception {
  const AiSubtitleException(this.message);
  final String message;
  @override
  String toString() => message;
}
