import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_audio_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_audio_flutter/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'pgs_sup_decoder.dart';

class PgsSubtitleService {
  final Map<String, Future<List<PgsSubtitleCue>>> _cache = {};
  final Map<String, File> _temporaryFiles = {};

  Future<List<PgsSubtitleCue>> load({
    required String videoPath,
    required int subtitleStreamIndex,
  }) {
    final key = '$videoPath#$subtitleStreamIndex';
    return _cache.putIfAbsent(
      key,
      () => _extractAndDecode(videoPath, subtitleStreamIndex, key),
    );
  }

  Future<List<PgsSubtitleCue>> _extractAndDecode(
    String videoPath,
    int subtitleStreamIndex,
    String cacheKey,
  ) async {
    if (videoPath.startsWith('content://')) {
      throw const PgsSubtitleException(
        'This video is available through Android MediaStore only; select a local folder copy to use bitmap fallback.',
      );
    }
    final directory = await getTemporaryDirectory();
    final output = File(
      path.join(
        directory.path,
        'novaplay_pgs_${DateTime.now().microsecondsSinceEpoch}_$subtitleStreamIndex.sup',
      ),
    );
    final command =
        '-y -i ${_quote(videoPath)} -map 0:s:$subtitleStreamIndex '
        '-c:s copy -f sup ${_quote(output.path)}';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode) || !await output.exists()) {
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      throw const PgsSubtitleException(
        'Could not extract the selected PGS subtitle track.',
      );
    }
    final length = await output.length();
    if (length == 0 || length > 128 * 1024 * 1024) {
      await output.delete();
      throw const PgsSubtitleException('The PGS subtitle file is invalid or too large.');
    }
    _temporaryFiles[cacheKey] = output;
    final bytes = await output.readAsBytes();
    final cues = await compute(
      decodePgsSup,
      Uint8List.fromList(bytes),
      debugLabel: 'Decode PGS subtitles',
    );
    if (cues.isEmpty) {
      throw const PgsSubtitleException(
        'No renderable bitmap cues were found in the selected PGS track.',
      );
    }
    return cues;
  }

  String _quote(String value) => '"${value.replaceAll('"', '\\"')}"';

  Future<void> dispose() async {
    for (final file in _temporaryFiles.values) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _temporaryFiles.clear();
    _cache.clear();
  }
}

class PgsSubtitleException implements Exception {
  const PgsSubtitleException(this.message);
  final String message;

  @override
  String toString() => message;
}
