import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/video_file.dart';

class MediaRepository {
  static const _cacheKey = 'novaplay.media.cache.v1';
  static const supportedExtensions = {
    'mp4',
    'mkv',
    'avi',
    'webm',
    'mov',
    'flv',
    'ts',
    'm4v',
    '3gp',
    'mpeg',
    'mpg',
  };

  Future<bool> requestVideoAccess() async {
    if (!Platform.isAndroid) return true;
    final status =
        await (Platform.version.contains('Android')
                ? Permission.videos
                : Permission.storage)
            .request();
    if (status.isGranted || status.isLimited) return true;
    final fallback = await Permission.storage.request();
    return fallback.isGranted || fallback.isLimited;
  }

  Future<List<VideoFile>> scan({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    final cachedFiles = cached == null
        ? <VideoFile>[]
        : (jsonDecode(cached) as List)
              .map((item) => VideoFile.fromJson(item as Map<String, dynamic>))
              .toList();
    if (!force && cachedFiles.isNotEmpty) return cachedFiles;

    final roots = <Directory>[
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Movies'),
      Directory('/storage/emulated/0/DCIM'),
      Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Video'),
      Directory('/storage/emulated/0'),
    ];
    final seen = <String>{};
    final files = <VideoFile>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            !_isVideo(entity.path) ||
            !seen.add(entity.path)) {
          continue;
        }
        try {
          final stat = await entity.stat();
          files.add(
            VideoFile(
              id: entity.path,
              path: entity.path,
              name: entity.path.split(Platform.pathSeparator).last,
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
            ),
          );
        } on FileSystemException {
          // Files can disappear while MediaStore is updating; skip them safely.
        }
      }
      if (files.length > 3000) break;
    }
    files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    final result = files.take(3000).toList();
    await _save(result);
    return result;
  }

  Future<void> saveProgress(String id, Duration progress) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    final current = (jsonDecode(raw) as List)
        .map((item) => VideoFile.fromJson(item as Map<String, dynamic>))
        .toList();
    final updated = current
        .map((file) => file.id == id ? file.copyWith(progress: progress) : file)
        .toList();
    await _save(updated, prefs: prefs);
  }

  List<FolderSummary> foldersFor(List<VideoFile> files) {
    return files
        .groupListsBy((file) => file.folderName)
        .entries
        .map((entry) {
          final path = entry.value.first.path.substring(
            0,
            entry.value.first.path.lastIndexOf(Platform.pathSeparator),
          );
          final icon = switch (entry.key.toLowerCase()) {
            'download' || 'downloads' => Icons.download_outlined,
            'movies' => Icons.movie_outlined,
            'whatsapp video' => Icons.chat_bubble_outline,
            'dcim' || 'camera' => Icons.photo_camera_outlined,
            _ => Icons.folder_outlined,
          };
          return FolderSummary(
            name: entry.key,
            path: path,
            count: entry.value.length,
            sizeBytes: entry.value.fold<int>(
              0,
              (total, file) => total + file.sizeBytes,
            ),
            icon: icon,
          );
        })
        .sorted((a, b) => b.count.compareTo(a.count));
  }

  bool _isVideo(String path) =>
      supportedExtensions.contains(path.split('.').last.toLowerCase());

  Future<void> _save(List<VideoFile> files, {SharedPreferences? prefs}) async {
    final target = prefs ?? await SharedPreferences.getInstance();
    await target.setString(
      _cacheKey,
      jsonEncode(files.map((file) => file.toJson()).toList()),
    );
  }
}
