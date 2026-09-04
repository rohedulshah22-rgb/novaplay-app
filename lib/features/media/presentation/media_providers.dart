import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/media_repository.dart';
import '../domain/video_file.dart';

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => const MediaRepository(),
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
    this.hasPermission = false,
    this.permission,
    this.errorMessage,
    this.query = '',
    this.durationFilter = 'All',
    this.resolutionFilter = 'All',
  });

  final List<VideoFile> files;
  final bool isScanning;
  final bool hasPermission;
  final PermissionSnapshot? permission;
  final String? errorMessage;
  final String query;
  final String durationFilter;
  final String resolutionFilter;

  bool get needsPermissionSettings => permission?.needsSettings ?? false;
  String get permissionDescription {
    final snapshot = permission;
    if (snapshot == null || snapshot.api == 0) {
      return 'Allow access to build your offline library.';
    }
    if (snapshot.isAndroid14OrNewer) {
      return 'Allow all videos, or choose selected videos for NovaPlay.';
    }
    if (snapshot.isAndroid13OrNewer) {
      return 'Allow NovaPlay to read videos on this device.';
    }
    return 'Allow NovaPlay to read videos from shared storage.';
  }

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
      (files.where((file) => file.progress > Duration.zero).toList()..sort(
            (a, b) => (b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
          ))
          .take(8)
          .toList();

  VideoFile? get resumeLastVideo {
    final items = files.where((file) => file.progress > Duration.zero).toList()
      ..sort(
        (a, b) => (b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ),
      );
    return items.isEmpty ? null : items.first;
  }

  List<FolderSummary> folders(MediaRepository repository) =>
      repository.foldersFor(files);

  MediaLibraryState copyWith({
    List<VideoFile>? files,
    bool? isScanning,
    bool? hasPermission,
    PermissionSnapshot? permission,
    String? errorMessage,
    bool clearError = false,
    String? query,
    String? durationFilter,
    String? resolutionFilter,
  }) => MediaLibraryState(
    files: files ?? this.files,
    isScanning: isScanning ?? this.isScanning,
    hasPermission: hasPermission ?? this.hasPermission,
    permission: permission ?? this.permission,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    query: query ?? this.query,
    durationFilter: durationFilter ?? this.durationFilter,
    resolutionFilter: resolutionFilter ?? this.resolutionFilter,
  );
}

class MediaLibraryNotifier extends Notifier<MediaLibraryState> {
  late final MediaRepository repository;
  bool _hasRequestedPermissionThisSession = false;

  @override
  MediaLibraryState build() {
    repository = ref.read(mediaRepositoryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      load(requestPermission: true);
    });
    return const MediaLibraryState();
  }

  Future<void> load({
    bool force = false,
    bool requestPermission = false,
  }) async {
    state = state.copyWith(isScanning: true, clearError: true);
    try {
      final permission =
          requestPermission && !_hasRequestedPermissionThisSession
          ? await repository.requestVideoAccess()
          : await repository.permissionState();
      _hasRequestedPermissionThisSession =
          _hasRequestedPermissionThisSession || requestPermission;
      if (!permission.granted) {
        state = state.copyWith(
          permission: permission,
          hasPermission: false,
          isScanning: false,
        );
        return;
      }
      final files = await repository.scan(force: force);
      state = state.copyWith(
        files: files,
        permission: permission,
        hasPermission: true,
        isScanning: false,
      );
    } catch (_) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Could not scan the device media library',
      );
    }
  }

  Future<void> onAppResumed() async {
    final permission = await repository.permissionState();
    final changed =
        permission.granted != state.hasPermission ||
        permission.partial != (state.permission?.partial ?? false);
    if (changed || state.files.isEmpty) {
      await load(force: true, requestPermission: false);
    }
  }

  Future<void> requestPermissionFromBanner() async {
    _hasRequestedPermissionThisSession = false;
    await load(force: true, requestPermission: true);
  }

  Future<void> openPermissionSettings() => repository.openAppSettings();

  Future<void> pickCustomDirectory() async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a video folder',
    );
    if (directory == null || directory.isEmpty) return;
    state = state.copyWith(isScanning: true, clearError: true);
    try {
      final selected = await repository.scanCustomDirectory(directory);
      final merged = <String, VideoFile>{
        for (final file in state.files) file.id: file,
        for (final file in selected) file.id: file,
      };
      state = state.copyWith(
        files: merged.values.toList()
          ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt)),
        isScanning: false,
      );
    } catch (_) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Could not read that folder',
      );
    }
  }

  void setQuery(String value) => state = state.copyWith(query: value);
  void setDurationFilter(String value) =>
      state = state.copyWith(durationFilter: value);
  void setResolutionFilter(String value) =>
      state = state.copyWith(resolutionFilter: value);

  Future<void> saveProgress(
    VideoFile file,
    Duration progress, {
    Duration? totalDuration,
  }) async {
    final duration = totalDuration ?? file.duration;
    final finished =
        duration > Duration.zero &&
        progress.inMilliseconds * 100 >= duration.inMilliseconds * 95;
    final savedProgress = finished ? Duration.zero : progress;
    final now = DateTime.now();
    final files = state.files
        .map(
          (item) => item.id == file.id
              ? item.copyWith(progress: savedProgress, lastPlayedAt: now)
              : item,
        )
        .toList();
    state = state.copyWith(files: files);
    await repository.savePlaybackPosition(
      id: file.id,
      position: progress,
      totalDuration: duration,
      lastPlayedAt: now,
    );
  }

  Future<void> clearResumeHistory() async {
    await repository.clearPlaybackHistory();
    state = state.copyWith(
      files: state.files
          .map((file) => file.copyWith(progress: Duration.zero))
          .toList(),
    );
  }
}
