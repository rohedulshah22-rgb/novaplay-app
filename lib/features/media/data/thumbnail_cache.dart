import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../domain/video_file.dart';

class ThumbnailCache {
  const ThumbnailCache();

  static const _channel = MethodChannel('com.novaplay/media');

  Future<String?> get(VideoFile file) async {
    final directory = await getTemporaryDirectory();
    final cacheDirectory = Directory(
      p.join(directory.path, 'novaplay-thumbnails'),
    );
    await cacheDirectory.create(recursive: true);
    final key = file.id.hashCode.toUnsigned(32).toRadixString(16);
    final cachedPath = p.join(cacheDirectory.path, '$key.jpg');
    final cached = File(cachedPath);
    if (await cached.exists() && await cached.length() > 0) return cachedPath;

    if (file.contentUri != null && file.contentUri!.startsWith('content://')) {
      try {
        final nativePath = await _channel.invokeMethod<String>(
          'cacheThumbnail',
          {'uri': file.contentUri, 'key': key, 'width': 640, 'height': 360},
        );
        if (nativePath != null && nativePath.isNotEmpty) return nativePath;
      } on PlatformException {
        // Fall through to the file-path thumbnail provider.
      }
    }

    try {
      return await VideoThumbnail.thumbnailFile(
        video: file.path,
        thumbnailPath: cacheDirectory.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 640,
        quality: 72,
      );
    } catch (_) {
      return null;
    }
  }
}
