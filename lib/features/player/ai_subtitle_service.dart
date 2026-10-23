import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_audio_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_audio_flutter/return_code.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
  static const _translationEndpoint = String.fromEnvironment(
    'NOVAPLAY_TRANSLATION_ENDPOINT',
  );
  static const _subtitleSearchEndpoint = String.fromEnvironment(
    'NOVAPLAY_SUBTITLE_SEARCH_ENDPOINT',
  );
  static const _apiKey = String.fromEnvironment('NOVAPLAY_OPENAI_API_KEY');
  static const _translationModel = String.fromEnvironment(
    'NOVAPLAY_TRANSLATION_MODEL',
    defaultValue: 'gpt-4o-mini',
  );

  final http.Client _client;
  final Map<String, File?> _embeddedSubtitleFiles = {};
  final Set<String> _embeddedExtractionAttempts = {};
  final Map<String, File?> _episodeSubtitleFiles = {};

  bool get isConfigured => _endpoint.isNotEmpty || _apiKey.isNotEmpty;

  Future<AiSubtitleResult> recognizeBitmapCue({
    required Uint8List pngBytes,
    required Duration start,
    required Duration end,
    required AiSubtitleLanguage language,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      path.join(
        directory.path,
        'novaplay_pgs_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
      ),
    );
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      await file.writeAsBytes(pngBytes, flush: true);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      final sourceText = recognized.text.trim();
      if (sourceText.isEmpty) {
        return const AiSubtitleResult(
          statusMessage: 'No readable text was found in the PGS subtitle.',
        );
      }
      final translated = await _translateSafely(sourceText, language);
      return AiSubtitleResult(
        caption: AiCaption(
          text: translated.trim().isEmpty ? sourceText : translated.trim(),
          start: start,
          end: end,
        ),
        usedLocalFallback: true,
      );
    } catch (error) {
      return AiSubtitleResult(
        statusMessage: 'On-device PGS OCR failed: $error',
      );
    } finally {
      await recognizer.close();
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<AiSubtitleResult> recognizeAndTranslate({
    required String sourcePath,
    required Duration position,
    required AiSubtitleLanguage language,
    String? sourceText,
    int audioTrackIndex = 0,
    int? subtitleTrackIndex,
  }) async {
    final directText = sourceText?.trim();
    if (directText != null && directText.isNotEmpty) {
      return _captionForSourceText(
        directText,
        start: position,
        end: position + const Duration(seconds: 6),
        language: language,
      );
    }

    final localCaption = await _readLocalSidecarCaption(sourcePath, position);
    if (localCaption != null) {
      return _captionForSourceCaption(localCaption, language);
    }

    final embeddedCaption = subtitleTrackIndex == null
        ? null
        : await _readEmbeddedCaption(
            sourcePath,
            position,
            subtitleTrackIndex: subtitleTrackIndex,
          );
    if (embeddedCaption != null) {
      return _captionForSourceCaption(embeddedCaption, language);
    }

    final episodeCaption = await _readEpisodeSubtitleCaption(
      sourcePath,
      position,
    );
    if (episodeCaption != null) {
      return _captionForSourceCaption(episodeCaption, language);
    }

    if (!isConfigured) {
      return const AiSubtitleResult(
        statusMessage:
            'No caption found. Configure a speech endpoint or episode subtitle relay for AI CC.',
      );
    }
    if (sourcePath.startsWith('content://')) {
      return const AiSubtitleResult(
        statusMessage:
            'Speech recognition cannot read this protected media source.',
      );
    }

    final audioFile = await _extractAudioWindow(
      sourcePath,
      position,
      audioTrackIndex: audioTrackIndex,
    );
    if (audioFile == null) {
      return const AiSubtitleResult(
        statusMessage: 'Could not extract audio for speech recognition.',
      );
    }

    try {
      final transcript = await _transcribe(audioFile, language);
      if (transcript.trim().isEmpty) {
        return const AiSubtitleResult(
          statusMessage: 'No speech was detected in this audio segment.',
        );
      }
      final translated = await _translate(transcript, language);
      final text = translated.trim().isEmpty
          ? transcript.trim()
          : translated.trim();
      return AiSubtitleResult(
        caption: AiCaption(
          text: text,
          start: position,
          end: position + const Duration(seconds: 4),
        ),
      );
    } finally {
      try {
        await audioFile.delete();
      } catch (_) {}
    }
  }

  Future<AiSubtitleResult> _captionForSourceCaption(
    AiCaption caption,
    AiSubtitleLanguage language,
  ) async {
    final translated = await _translateSafely(caption.text, language);
    return AiSubtitleResult(
      caption: AiCaption(
        text: translated,
        start: caption.start,
        end: caption.end,
      ),
      usedLocalFallback: true,
    );
  }

  Future<AiSubtitleResult> _captionForSourceText(
    String text, {
    required Duration start,
    required Duration end,
    required AiSubtitleLanguage language,
  }) async {
    final translated = await _translateSafely(text, language);
    return AiSubtitleResult(
      caption: AiCaption(text: translated, start: start, end: end),
      usedLocalFallback: true,
    );
  }

  Future<String> _translateSafely(
    String source,
    AiSubtitleLanguage language,
  ) async {
    try {
      return await _translateText(source, language);
    } catch (_) {
      return source;
    }
  }

  Future<File?> _extractAudioWindow(
    String sourcePath,
    Duration position, {
    required int audioTrackIndex,
  }) async {
    final directory = await getTemporaryDirectory();
    final outputPath = path.join(
      directory.path,
      'novaplay_ai_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final command =
        '-y -ss ${_seconds(position)} -i ${_quote(sourcePath)} '
        '-map 0:a:$audioTrackIndex -t 4 -vn -ac 1 -ar 16000 '
        '-f wav -c:a pcm_s16le ${_quote(outputPath)}';
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

  Future<String> _translate(String transcript, AiSubtitleLanguage language) {
    return _translateText(transcript, language);
  }

  Future<String> _translateText(
    String transcript,
    AiSubtitleLanguage language,
  ) async {
    if (language.code == 'en' || transcript.trim().isEmpty) return transcript;

    if (_translationEndpoint.isNotEmpty) {
      final response = await _client.post(
        Uri.parse(_translationEndpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': transcript,
          'target_language': language.code,
          'target_language_name': language.label,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final value = _readText(_decodeObject(response.body));
        if (value != null && value.trim().isNotEmpty) return value;
      }
    }

    if (_apiKey.isNotEmpty) {
      final response = await _client.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _translationModel,
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
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = _decodeObject(response.body);
        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final message = (choices.first as Map)['message'];
          if (message is Map && message['content'] is String) {
            return message['content'] as String;
          }
        }
      }
    }

    // This keyless endpoint provides a practical translation fallback for
    // embedded and sidecar caption text. Audio transcription still requires a
    // configured speech-recognition relay or provider key.
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': language.code,
      'dt': 't',
      'q': transcript,
    });
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiSubtitleException(
        'Caption translation failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List && decoded.isNotEmpty && decoded.first is List) {
      final chunks = (decoded.first as List)
          .whereType<List>()
          .map(
            (chunk) => chunk.isNotEmpty && chunk.first is String
                ? chunk.first as String
                : '',
          )
          .where((chunk) => chunk.isNotEmpty)
          .join();
      if (chunks.isNotEmpty) return chunks;
    }
    return transcript;
  }

  Future<AiCaption?> _readLocalSidecarCaption(
    String sourcePath,
    Duration position,
  ) async {
    if (sourcePath.startsWith('content://')) return null;
    final basePath = path.withoutExtension(sourcePath);
    for (final extension in [
      '.en.srt', '.eng.srt', '.english.srt', '.srt',
      '.en.vtt', '.eng.vtt', '.english.vtt', '.vtt',
      '.ass', '.ssa',
    ]) {
      final file = File('$basePath$extension');
      if (!await file.exists()) continue;
      final caption = await _parseCaptionFile(file, position);
      if (caption != null) return caption;
    }
    return null;
  }


  Future<AiCaption?> _readEpisodeSubtitleCaption(
    String sourcePath,
    Duration position,
  ) async {
    if (_subtitleSearchEndpoint.isEmpty) return null;
    final file = await _fetchEpisodeSubtitle(sourcePath);
    return file == null ? null : _parseCaptionFile(file, position);
  }

  Future<File?> _fetchEpisodeSubtitle(String sourcePath) async {
    if (_episodeSubtitleFiles.containsKey(sourcePath)) {
      return _episodeSubtitleFiles[sourcePath];
    }
    final filename = path.basename(Uri.parse(sourcePath).path);
    final title = path.basenameWithoutExtension(filename).trim();
    final episodeMatch = RegExp(
      r'(?:s\s*0*(\d{1,2})\s*e\s*0*(\d{1,3})|season\s*0*(\d+)\s*episode\s*0*(\d+)|0*(\d{1,2})x0*(\d{1,3})|episode\s*0*(\d+))',
      caseSensitive: false,
    ).firstMatch(title);
    if (episodeMatch == null) {
      _episodeSubtitleFiles[sourcePath] = null;
      return null;
    }
    final seasonNumber = episodeMatch.group(1) ??
        episodeMatch.group(3) ??
        episodeMatch.group(5);
    final episodeNumber = episodeMatch.group(2) ??
        episodeMatch.group(4) ??
        episodeMatch.group(6) ??
        episodeMatch.group(7);
    if (episodeNumber == null) {
      _episodeSubtitleFiles[sourcePath] = null;
      return null;
    }
    final endpoint = Uri.parse(_subtitleSearchEndpoint).replace(
      queryParameters: {
        'query': title,
        'filename': filename,
        'episode': episodeMatch.group(0)!,
        if (seasonNumber != null) 'season_number': seasonNumber,
        'episode_number': episodeNumber,
        'language': 'en',
      },
    );
    final response = await _client.get(endpoint).timeout(
      const Duration(seconds: 12),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiSubtitleException(
        'Episode subtitle search failed (${response.statusCode}).',
      );
    }
    var subtitleText = response.body;
    if (!subtitleText.contains('-->')) {
      final decoded = _decodeObject(subtitleText);
      subtitleText = _readText(decoded) ?? '';
      if (subtitleText.isEmpty && decoded['url'] is String) {
        final download = await _client.get(Uri.parse(decoded['url'] as String))
            .timeout(const Duration(seconds: 12));
        if (download.statusCode >= 200 && download.statusCode < 300) {
          subtitleText = download.body;
        }
      }
    }
    if (!subtitleText.contains('-->')) {
      _episodeSubtitleFiles[sourcePath] = null;
      return null;
    }
    final directory = await getTemporaryDirectory();
    final output = File(
      path.join(
        directory.path,
        'novaplay_episode_${sourcePath.hashCode.abs()}.srt',
      ),
    );
    await output.writeAsString(subtitleText, flush: true);
    _episodeSubtitleFiles[sourcePath] = output;
    return output;
  }

  Future<AiCaption?> _readEmbeddedCaption(
    String sourcePath,
    Duration position, {
    required int subtitleTrackIndex,
  }) async {
    if (sourcePath.startsWith('content://')) return null;
    final file = await _extractEmbeddedSubtitleFile(
      sourcePath,
      subtitleTrackIndex,
    );
    if (file == null) return null;
    return _parseCaptionFile(file, position);
  }

  Future<List<AiCaption>> extractEmbeddedTextCues({
    required String sourcePath,
    required int subtitleTrackIndex,
  }) async {
    if (sourcePath.startsWith('content://')) return const [];
    final file = await _extractEmbeddedSubtitleFile(
      sourcePath,
      subtitleTrackIndex,
    );
    return file == null ? const [] : _parseAllCaptionFile(file);
  }

  Future<File?> findAutomaticSubtitleFile(String sourcePath) async {
    if (!sourcePath.startsWith('content://')) {
      final basePath = path.withoutExtension(sourcePath);
      for (final extension in [
        '.en.srt', '.eng.srt', '.english.srt', '.srt',
        '.en.vtt', '.eng.vtt', '.english.vtt', '.vtt',
        '.ass', '.ssa',
      ]) {
        final file = File('$basePath$extension');
        if (await file.exists()) return file;
      }
    }
    return _fetchEpisodeSubtitle(sourcePath);
  }

  Future<File?> _extractEmbeddedSubtitleFile(
    String sourcePath,
    int subtitleTrackIndex,
  ) async {
    final cacheKey = '$sourcePath#$subtitleTrackIndex';
    if (_embeddedSubtitleFiles.containsKey(cacheKey)) {
      return _embeddedSubtitleFiles[cacheKey];
    }
    if (!_embeddedExtractionAttempts.add(cacheKey)) return null;
    final directory = await getTemporaryDirectory();
    final output = File(
      path.join(
        directory.path,
        'novaplay_embedded_${sourcePath.hashCode.abs()}_$subtitleTrackIndex.srt',
      ),
    );
    final command =
        '-y -i ${_quote(sourcePath)} -map 0:s:$subtitleTrackIndex '
        '-c:s srt ${_quote(output.path)}';
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    final file = ReturnCode.isSuccess(code) && await output.exists()
        ? output
        : null;
    _embeddedSubtitleFiles[cacheKey] = file;
    return file;
  }

  Future<List<AiCaption>> _parseAllCaptionFile(File file) async {
    final lines = await file.readAsLines();
    final captions = <AiCaption>[];
    for (var index = 0; index < lines.length; index++) {
      final match = _timestampPattern.firstMatch(lines[index]);
      if (match == null) continue;
      final start = _parseTimestamp(match.group(1)!);
      final end = _parseTimestamp(match.group(2)!);
      final text = <String>[];
      for (var next = index + 1; next < lines.length; next++) {
        final line = lines[next].trim();
        if (line.isEmpty || _timestampPattern.hasMatch(line)) break;
        if (!RegExp(r'^\d+$').hasMatch(line)) text.add(line);
      }
      final value = text
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(r'\N', '\n')
          .trim();
      if (value.isNotEmpty && end > start) {
        captions.add(AiCaption(text: value, start: start, end: end));
      }
    }
    return List<AiCaption>.unmodifiable(captions);
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

  void dispose() {
    for (final file in _embeddedSubtitleFiles.values) {
      if (file != null) {
        file.delete();
      }
    }
    for (final file in _episodeSubtitleFiles.values) {
      if (file != null) file.delete();
    }
    _client.close();
  }
}

class AiSubtitleResult {
  const AiSubtitleResult({
    this.caption,
    this.usedLocalFallback = false,
    this.statusMessage,
  });

  final AiCaption? caption;
  final bool usedLocalFallback;
  final String? statusMessage;
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
