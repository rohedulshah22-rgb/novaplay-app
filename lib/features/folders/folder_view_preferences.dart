import 'package:shared_preferences/shared_preferences.dart';

class FolderViewPreferences {
  const FolderViewPreferences._();

  static const _sortKey = 'novaplay.folder.sort.v1';
  static const _durationKey = 'novaplay.folder.duration.v1';
  static const _resolutionKey = 'novaplay.folder.resolution.v1';
  static const _gridKey = 'novaplay.folder.grid.v1';

  static Future<FolderViewPreferenceValues> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FolderViewPreferenceValues(
      sort: prefs.getString(_sortKey) ?? 'Name (A–Z)',
      duration: prefs.getString(_durationKey) ?? 'All',
      resolution: prefs.getString(_resolutionKey) ?? 'All',
      isGrid: prefs.getBool(_gridKey) ?? true,
    );
  }

  static Future<void> save({
    String? sort,
    String? duration,
    String? resolution,
    bool? isGrid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (sort != null) await prefs.setString(_sortKey, sort);
    if (duration != null) await prefs.setString(_durationKey, duration);
    if (resolution != null) await prefs.setString(_resolutionKey, resolution);
    if (isGrid != null) await prefs.setBool(_gridKey, isGrid);
  }
}

class FolderViewPreferenceValues {
  const FolderViewPreferenceValues({
    required this.sort,
    required this.duration,
    required this.resolution,
    required this.isGrid,
  });

  final String sort;
  final String duration;
  final String resolution;
  final bool isGrid;
}
