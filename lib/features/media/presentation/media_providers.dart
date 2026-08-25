import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/media_repository.dart';
import '../domain/video_file.dart';

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepository(),
);
final appTabProvider = NotifierProvider<AppTabController, int>(
  AppTabController.new,
);

class AppTabController extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

final mediaLibraryProvider =
    NotifierProvider<MediaLibraryNotifier, MediaLibraryState>(
      MediaLibraryNotifier.new,
    );

class MediaLibraryState {
  const MediaLibraryState({
    this.files = const [],
    this.isScanning = false,
    this.hasPermission = true,
    this.errorMessage,
    this.query = '',
    this.durationFilter = 'All',
    this.resolutionFilter = 'All',
  });
  final List<VideoFile> files;
  final bool isScanning;
  final bool hasPermission;
  final String? errorMessage;
  final String query;
  final String durationFilter;
  final String resolutionFilter;

  List<VideoFile> get filteredFiles {
    final normalized = query.trim().toLowerCase();
    return files.where((file) {
      final matchesQuery =
          normalized.isEmpty ||
          file.name.toLowerCase().contains(normalized) ||
          file.folderName.toLowerCase().contains(normalized);
      final matchesResolution =
          resolutionFilter == 'All' || file.resolution == resolutionFilter;
      final matchesDuration = switch (durationFilter) {
        '< 10 min' =>
          file.duration == Duration.zero || file.duration.inMinutes < 10,
        '10–30 min' =>
          file.duration == Duration.zero ||
              (file.duration.inMinutes >= 10 && file.duration.inMinutes < 30),
        '30+ min' =>
          file.duration == Duration.zero || file.duration.inMinutes >= 30,
        _ => true,
      };
      return matchesQuery && matchesResolution && matchesDuration;
    }).toList();
  }

  List<VideoFile> get recentlyPlayed =>
      files.where((file) => file.progress > Duration.zero).take(8).toList();
  List<FolderSummary> folders(MediaRepository repository) =>
      repository.foldersFor(files);

  MediaLibraryState copyWith({
    List<VideoFile>? files,
    bool? isScanning,
    bool? hasPermission,
    String? errorMessage,
    bool clearError = false,
    String? query,
    String? durationFilter,
    String? resolutionFilter,
  }) => MediaLibraryState(
    files: files ?? this.files,
    isScanning: isScanning ?? this.isScanning,
    hasPermission: hasPermission ?? this.hasPermission,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    query: query ?? this.query,
    durationFilter: durationFilter ?? this.durationFilter,
    resolutionFilter: resolutionFilter ?? this.resolutionFilter,
  );
}

class MediaLibraryNotifier extends Notifier<MediaLibraryState> {
  late final MediaRepository repository;

  @override
  MediaLibraryState build() {
    repository = ref.read(mediaRepositoryProvider);
    Future.microtask(load);
    return const MediaLibraryState();
  }

  Future<void> load({bool force = false}) async {
    state = state.copyWith(isScanning: true, clearError: true);
    try {
      final hasPermission = await repository.requestVideoAccess();
      if (!hasPermission) {
        state = state.copyWith(hasPermission: false, isScanning: false);
        return;
      }
      final files = await repository.scan(force: force);
      state = state.copyWith(
        files: files,
        hasPermission: true,
        isScanning: false,
      );
    } catch (_) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Could not scan local storage',
      );
    }
  }

  void setQuery(String value) => state = state.copyWith(query: value);
  void setDurationFilter(String value) =>
      state = state.copyWith(durationFilter: value);
  void setResolutionFilter(String value) =>
      state = state.copyWith(resolutionFilter: value);

  Future<void> saveProgress(VideoFile file, Duration progress) async {
    final files = state.files
        .map(
          (item) =>
              item.id == file.id ? item.copyWith(progress: progress) : item,
        )
        .toList();
    state = state.copyWith(files: files);
    await repository.saveProgress(file.id, progress);
  }
}
