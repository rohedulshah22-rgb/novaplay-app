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
    this.thumbnailPath,
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
  final String? thumbnailPath;

  String get extension => p.extension(name).replaceFirst('.', '').toUpperCase();
  String get resolution {
    if (height >= 2160) return '4K';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height > 0) return '${height}p';
    return 'HD';
  }

  String get folderName => p.basename(p.dirname(path));
  double get completion => duration.inMilliseconds == 0
      ? 0
      : (progress.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  VideoFile copyWith({
    Duration? progress,
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
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
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
    'thumbnailPath': thumbnailPath,
  };

  factory VideoFile.fromJson(Map<String, dynamic> json) => VideoFile(
    id: json['id'] as String,
    path: json['path'] as String,
    name: json['name'] as String,
    sizeBytes: json['sizeBytes'] as int,
    modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    duration: Duration(milliseconds: (json['durationMs'] as int?) ?? 0),
    width: (json['width'] as int?) ?? 0,
    height: (json['height'] as int?) ?? 0,
    progress: Duration(milliseconds: (json['progressMs'] as int?) ?? 0),
    thumbnailPath: json['thumbnailPath'] as String?,
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
