import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';

class CaptureService {
  const CaptureService();

  Future<bool> saveSnapshot(Player player, {required String sourceName}) async {
    final Uint8List? bytes = await player.screenshot(format: 'image/png');
    if (bytes == null || bytes.isEmpty) return false;
    final name = '${_baseName(sourceName)}_${_stamp()}.png';
    final result = await SaverGallery.saveImage(
      bytes,
      quality: 100,
      fileName: name,
      albumPath: 'NovaPlay/Snapshots',
      skipIfExists: false,
    );
    return result.isSuccess;
  }

  Future<bool> exportGif({
    required String sourcePath,
    required Duration start,
  }) async {
    final directory = await getTemporaryDirectory();
    final outputPath = path.join(
      directory.path,
      '${_baseName(sourcePath)}_${_stamp()}.gif',
    );
    final command =
        '-y -ss ${_seconds(start)} -i ${_quote(sourcePath)} -t 5 -vf "fps=12,scale=480:-1:flags=lanczos" -loop 0 ${_quote(outputPath)}';
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) return false;
    final result = await SaverGallery.saveFile(
      filePath: outputPath,
      fileName: path.basename(outputPath),
      albumPath: 'NovaPlay/GIFs',
      skipIfExists: false,
    );
    return result.isSuccess;
  }

  String _quote(String value) => '"${value.replaceAll('"', '\\"')}"';
  String _seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(3);
  String _baseName(String value) => path
      .basenameWithoutExtension(value)
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  String _stamp() => DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '')
      .substring(0, 14);
}
