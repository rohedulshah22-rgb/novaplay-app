class PlaybackHistoryEntry {
  const PlaybackHistoryEntry({
    required this.videoId,
    required this.position,
    required this.totalDuration,
    required this.lastPlayedAt,
    this.finished = false,
  });

  final String videoId;
  final Duration position;
  final Duration totalDuration;
  final DateTime lastPlayedAt;
  final bool finished;

  bool get hasResumePoint => !finished && position > const Duration(seconds: 5);

  double get completion => totalDuration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / totalDuration.inMilliseconds).clamp(0, 1);

  Map<String, dynamic> toJson() => {
    'positionMs': position.inMilliseconds,
    'totalDurationMs': totalDuration.inMilliseconds,
    'lastPlayedAtMs': lastPlayedAt.millisecondsSinceEpoch,
    'finished': finished,
  };

  factory PlaybackHistoryEntry.fromJson(
    String videoId,
    Map<String, dynamic> json,
  ) => PlaybackHistoryEntry(
    videoId: videoId,
    position: Duration(
      milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
    ),
    totalDuration: Duration(
      milliseconds: (json['totalDurationMs'] as num?)?.toInt() ?? 0,
    ),
    lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['lastPlayedAtMs'] as num?)?.toInt() ?? 0,
    ),
    finished: json['finished'] == true,
  );
}

String formatResumeTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${value.inMinutes}:$seconds';
}
