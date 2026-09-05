import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class MediaPreferences {
  static const _favoritesKey = 'novaplay.media.favorites.v1';
  static const _playlistsKey = 'novaplay.media.playlists.v1';
  static const _excludedFoldersKey = 'novaplay.media.excluded-folders.v1';
  static const _hideShortClipsKey = 'novaplay.media.hide-short-clips.v1';
  static const _equalizerKey = 'novaplay.audio.equalizer.v1';
  static const _bassBoostKey = 'novaplay.audio.bass-boost.v1';

  const MediaPreferences();

  Future<Set<String>> favorites() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_favoritesKey) ?? const <String>[]).toSet();
  }

  Future<bool> isFavorite(String id) async => (await favorites()).contains(id);

  Future<bool> toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_favoritesKey) ?? const <String>[]).toSet();
    final next = ids.contains(id);
    if (next) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    await prefs.setStringList(_favoritesKey, ids.toList()..sort());
    return !next;
  }

  Future<Map<String, List<String>>> playlists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null) return <String, List<String>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(
            key.toString(),
            value is List ? value.map((item) => item.toString()).toList() : <String>[],
          ),
        );
      }
    } catch (_) {}
    return <String, List<String>>{};
  }

  Future<void> savePlaylists(Map<String, List<String>> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistsKey, jsonEncode(playlists));
  }

  Future<void> createPlaylist(String name) async {
    final current = await playlists();
    current.putIfAbsent(name, () => <String>[]);
    await savePlaylists(current);
  }

  Future<void> addToPlaylist(String name, String id) async {
    final current = await playlists();
    final items = current.putIfAbsent(name, () => <String>[]);
    if (!items.contains(id)) items.add(id);
    await savePlaylists(current);
  }

  Future<Set<String>> excludedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_excludedFoldersKey) ?? const <String>[]).toSet();
  }

  Future<void> setExcludedFolders(Set<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_excludedFoldersKey, folders.toList()..sort());
  }

  Future<bool> hideShortClips() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideShortClipsKey) ?? false;
  }

  Future<void> setHideShortClips(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideShortClipsKey, value);
  }

  Future<List<double>> equalizerBands() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_equalizerKey)?.map(double.parse).toList() ??
        List<double>.filled(5, 0);
  }

  Future<void> setEqualizerBands(List<double> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_equalizerKey, values.map((value) => value.toString()).toList());
  }

  Future<bool> bassBoost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_bassBoostKey) ?? false;
  }

  Future<void> setBassBoost(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bassBoostKey, value);
  }
}

const mediaPreferences = MediaPreferences();

String mediaFolderFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash <= 0 ? 'Music' : normalized.substring(0, slash).split('/').last;
}

String mediaStemFromPath(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

bool isExcludedFolder(String path, Set<String> excluded) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return excluded.any((folder) {
    final value = folder.toLowerCase().trim();
    return value.isNotEmpty && (normalized.contains('/$value/') || normalized.endsWith('/$value'));
  });
}

String lrcPathFor(String audioPath) {
  final normalized = audioPath.replaceAll('\\', '/');
  final dot = normalized.lastIndexOf('.');
  return '${dot <= 0 ? normalized : normalized.substring(0, dot)}.lrc';
}
class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration at;
  final String text;
}

List<LyricLine> parseLrc(String content) {
  final lines = <LyricLine>[];
  final pattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)');
  for (final line in content.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final millis = int.parse((match.group(3) ?? '0').padRight(3, '0'));
    lines.add(
      LyricLine(
        Duration(
          minutes: int.parse(match.group(1)!),
          seconds: int.parse(match.group(2)!),
          milliseconds: millis,
        ),
        match.group(4)!.trim(),
      ),
    );
  }
  return lines..sort((a, b) => a.at.compareTo(b.at));
}

String? findEmbeddedLyrics(String? raw) {
  if (raw == null || !raw.contains('[')) return null;
  return raw;
}
