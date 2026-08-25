import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/video_file.dart';

class PermissionSnapshot {
  const PermissionSnapshot({
    required this.api,
    required this.granted,
    required this.full,
    required this.partial,
    required this.needsSettings,
  });

  final int api;
  final bool granted;
  final bool full;
  final bool partial;
  final bool needsSettings;

  bool get isAndroid13OrNewer => api >= 33;
  bool get isAndroid14OrNewer => api >= 34;

  factory PermissionSnapshot.fromMap(Map<dynamic, dynamic>? map) =>
      PermissionSnapshot(
        api: (map?['api'] as num?)?.toInt() ?? 0,
        granted: map?['granted'] == true,
        full: map?['full'] == true,
        partial: map?['partial'] == true,
        needsSettings: map?['needsSettings'] == true,
      );
}

class MediaRepository {
  const MediaRepository();

  static const _mediaChannel = MethodChannel('com.novaplay/media');
  static const _progressKey = 'novaplay.media.progress.v2';
  static const _customDirectoriesKey = 'novaplay.media.custom-directories.v1';

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
    'm2ts',
    'ogv',
  };

  Future<PermissionSnapshot> permissionState() async {
    if (!Platform.isAndroid) {
      return const PermissionSnapshot(
        api: 0,
        granted: true,
        full: true,
        partial: false,
        needsSettings: false,
      );
    }
    try {
      final map = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getPermissionState',
      );
      return PermissionSnapshot.fromMap(map);
    } on PlatformException {
      return const PermissionSnapshot(
        api: 0,
        granted: false,
        full: false,
        partial: false,
        needsSettings: false,
      );
    }
  }

  Future<PermissionSnapshot> requestVideoAccess() async {
    if (!Platform.isAndroid) return permissionState();
    try {
      final map = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>(
        'requestMediaPermission',
      );
      return PermissionSnapshot.fromMap(map);
    } on PlatformException {
      return permissionState();
    }
  }

  Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;
    await _mediaChannel.invokeMethod<void>('openAppSettings');
  }

  Future<List<VideoFile>> scan({bool force = false}) async {
    final permission = await permissionState();
    if (!permission.granted) return const [];

    final mediaStoreRows = Platform.isAndroid
        ? await _queryMediaStore()
        : const <Map<String, dynamic>>[];
    final customDirectories = await _readCustomDirectories();
    final customRows = await _scanCustomDirectories(customDirectories);
    final progress = await _readProgress();
    final merged = <String, VideoFile>{};

    for (final row in mediaStoreRows) {
      final video = _videoFromMediaStore(row, progress);
      if (video != null) merged[video.id] = video;
    }
    for (final video in customRows) {
      merged[video.id] = video.copyWith(
        progress: progress[video.id] ?? video.progress,
      );
    }

    final result = merged.values.toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return result.take(5000).toList(growable: false);
  }

  Future<List<VideoFile>> scanCustomDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return const [];
    await _addCustomDirectory(directoryPath);
    return _scanCustomDirectories([directoryPath]);
  }

  Future<List<Map<String, dynamic>>> _queryMediaStore() async {
    try {
      final rows = await _mediaChannel.invokeMethod<List<dynamic>>(
        'queryVideos',
      );
      return rows
              ?.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false) ??
          const [];
    } on PlatformException {
      return const [];
    }
  }

  VideoFile? _videoFromMediaStore(
    Map<String, dynamic> row,
    Map<String, Duration> progress,
  ) {
    final id = row['id'] as String?;
    final name = row['name'] as String?;
    if (id == null || name == null || !_isVideo(name)) return null;
    final uri = row['uri'] as String?;
    final filePath = row['path'] as String? ?? uri ?? id;
    final modifiedMs = (row['modifiedAtMs'] as num?)?.toInt() ?? 0;
    return VideoFile(
      id: id,
      path: filePath,
      name: name,
      sizeBytes: (row['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedAt: modifiedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(modifiedMs)
          : DateTime.fromMillisecondsSinceEpoch(0),
      duration: Duration(
        milliseconds: (row['durationMs'] as num?)?.toInt() ?? 0,
      ),
      width: (row['width'] as num?)?.toInt() ?? 0,
      height: (row['height'] as num?)?.toInt() ?? 0,
      progress: progress[id] ?? Duration.zero,
      contentUri: uri,
      relativePath: row['relativePath'] as String?,
      mimeType: row['mimeType'] as String? ?? 'video/*',
    );
  }

  Future<List<VideoFile>> _scanCustomDirectories(
    List<String> directories,
  ) async {
    final files = <VideoFile>[];
    final seen = <String>{};
    for (final path in directories) {
      final root = Directory(path);
      if (!await root.exists()) continue;
      try {
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
                name: pBasename(entity.path),
                sizeBytes: stat.size,
                modifiedAt: stat.modified,
              ),
            );
          } on FileSystemException {
            // A removable volume can change while it is being queried.
          }
        }
      } on FileSystemException {
        // The selected directory may be temporarily unavailable.
      }
    }
    return files;
  }

  Future<List<String>> _readCustomDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_customDirectoriesKey) ?? const [];
  }

  Future<void> _addCustomDirectory(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final current = {...?prefs.getStringList(_customDirectoriesKey)}
      ..add(value);
    await prefs.setStringList(_customDirectoriesKey, current.toList());
  }

  Future<Map<String, Duration>> _readProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (key, value) =>
            MapEntry(key, Duration(milliseconds: (value as num).toInt())),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> saveProgress(String id, Duration progress) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readProgress();
    current[id] = progress;
    await prefs.setString(
      _progressKey,
      jsonEncode(
        current.map((key, value) => MapEntry(key, value.inMilliseconds)),
      ),
    );
  }

  List<FolderSummary> foldersFor(List<VideoFile> files) {
    return files
        .groupListsBy((file) => file.folderName)
        .entries
        .map((entry) {
          final first = entry.value.first;
          final path = first.relativePath ?? first.path;
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

  String pBasename(String value) {
    final normalized = value.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
