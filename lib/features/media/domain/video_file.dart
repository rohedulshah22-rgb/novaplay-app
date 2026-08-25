import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class VideoFile {
  const VideoFile({
    required this.id,
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
    this.progress = Duration.zero,
    this.lastPlayedAt,
    this.thumbnailPath,
    this.contentUri,
    this.relativePath,
    this.mimeType = 'video/*',
  });

  final String id;
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
  final Duration duration;
  final int width;
  final int height;
  final Duration progress;
  final DateTime? lastPlayedAt;
  final String? thumbnailPath;
  final String? contentUri;
  final String? relativePath;
  final String mimeType;

  String get extension => p.extension(name).replaceFirst('.', '').toUpperCase();
  String get resolution {
    if (height >= 2160) return '4K';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height > 0) return '${height}p';
    return 'HD';
  }

  String get folderName {
    final indexedPath = relativePath;
    if (indexedPath != null && indexedPath.isNotEmpty) {
      final normalized = indexedPath
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'/$'), '');
      final segments = normalized
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.length >= 2) return segments[segments.length - 2];
      if (segments.isNotEmpty) return segments.first;
    }
    return p.basename(p.dirname(path));
  }

  double get completion => duration.inMilliseconds == 0
      ? 0
      : (progress.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  VideoFile copyWith({
    Duration? progress,
    DateTime? lastPlayedAt,
    String? thumbnailPath,
    Duration? duration,
    int? width,
    int? height,
  }) => VideoFile(
    id: id,
    path: path,
    name: name,
    sizeBytes: sizeBytes,
    modifiedAt: modifiedAt,
    duration: duration ?? this.duration,
    width: width ?? this.width,
    height: height ?? this.height,
    progress: progress ?? this.progress,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    contentUri: contentUri,
    relativePath: relativePath,
    mimeType: mimeType,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'sizeBytes': sizeBytes,
    'modifiedAt': modifiedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'width': width,
    'height': height,
    'progressMs': progress.inMilliseconds,
    'lastPlayedAtMs': lastPlayedAt?.millisecondsSinceEpoch,
    'thumbnailPath': thumbnailPath,
    'contentUri': contentUri,
    'relativePath': relativePath,
    'mimeType': mimeType,
  };

  factory VideoFile.fromJson(Map<String, dynamic> json) => VideoFile(
    id: json['id'] as String,
    path: json['path'] as String,
    name: json['name'] as String,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    duration: Duration(
      milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
    ),
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
    progress: Duration(
      milliseconds: (json['progressMs'] as num?)?.toInt() ?? 0,
    ),
    lastPlayedAt: (json['lastPlayedAtMs'] as num?) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (json['lastPlayedAtMs'] as num).toInt(),
          ),
    thumbnailPath: json['thumbnailPath'] as String?,
    contentUri: json['contentUri'] as String?,
    relativePath: json['relativePath'] as String?,
    mimeType: json['mimeType'] as String? ?? 'video/*',
  );
}

class FolderSummary {
  const FolderSummary({
    required this.name,
    required this.path,
    required this.count,
    required this.sizeBytes,
    required this.icon,
  });
  final String name;
  final String path;
  final int count;
  final int sizeBytes;
  final IconData icon;
}
