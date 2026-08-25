import 'video_file.dart';

class NaturalSort {
  const NaturalSort._();

  static int compareVideos(VideoFile left, VideoFile right) =>
      compareStrings(left.name, right.name);

  static int compareStrings(String left, String right) {
    final leftKey = _episodeKey(left);
    final rightKey = _episodeKey(right);
    if (leftKey != null && rightKey != null) {
      for (
        var index = 0;
        index < leftKey.length && index < rightKey.length;
        index++
      ) {
        final difference = leftKey[index].compareTo(rightKey[index]);
        if (difference != 0) return difference;
      }
      if (leftKey.length != rightKey.length) {
        return leftKey.length.compareTo(rightKey.length);
      }
    }

    final leftTokens = _tokens(left.toLowerCase());
    final rightTokens = _tokens(right.toLowerCase());
    for (
      var index = 0;
      index < leftTokens.length && index < rightTokens.length;
      index++
    ) {
      final a = leftTokens[index];
      final b = rightTokens[index];
      if (a is int && b is int) {
        final difference = a.compareTo(b);
        if (difference != 0) return difference;
      } else {
        final difference = a.toString().compareTo(b.toString());
        if (difference != 0) return difference;
      }
    }
    return leftTokens.length.compareTo(rightTokens.length);
  }

  static List<int>? _episodeKey(String value) {
    final seasonEpisode = RegExp(
      r'[sS](\d{1,3})[^0-9]?[eE](\d{1,4})',
    ).firstMatch(value);
    if (seasonEpisode != null) {
      return [
        int.parse(seasonEpisode.group(1)!),
        int.parse(seasonEpisode.group(2)!),
      ];
    }
    final episode = RegExp(
      r'(?:episode|ep|e)[\s._-]*(\d{1,5})',
      caseSensitive: false,
    ).firstMatch(value);
    if (episode != null) return [0, int.parse(episode.group(1)!)];
    return null;
  }

  static List<Object> _tokens(String value) {
    final tokens = <Object>[];
    final pattern = RegExp(r'\d+|\D+');
    for (final match in pattern.allMatches(value)) {
      final token = match.group(0)!;
      tokens.add(RegExp(r'^\d+$').hasMatch(token) ? int.parse(token) : token);
    }
    return tokens;
  }
}
