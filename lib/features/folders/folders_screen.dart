import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/data/media_repository.dart';
import '../media/domain/video_file.dart';
import '../media/presentation/media_providers.dart';
import 'folder_videos_screen.dart';

class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  late Future<List<StorageVolumeInfo>> _volumes;

  @override
  void initState() {
    super.initState();
    _volumes = ref.read(mediaRepositoryProvider).storageVolumes();
  }

  Future<void> _refreshStorages() async {
    setState(
      () => _volumes = ref.read(mediaRepositoryProvider).storageVolumes(),
    );
    await ref.read(mediaLibraryProvider.notifier).load(force: true);
    await _volumes;
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(mediaLibraryProvider);
    final media = ref.read(mediaLibraryProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Folders',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Pick a folder',
            onPressed: media.pickCustomDirectory,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: 'Refresh storage and media',
            onPressed: _refreshStorages,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: NovaColors.cyan,
        onRefresh: _refreshStorages,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            const Text(
              'Storages',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Browse videos by device storage location.',
              style: TextStyle(color: NovaColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<StorageVolumeInfo>>(
              future: _volumes,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final volumes = snapshot.data ?? const <StorageVolumeInfo>[];
                final internal = volumes
                    .where((volume) => !volume.isRemovable)
                    .toList();
                final removable = volumes
                    .where((volume) => volume.isRemovable)
                    .toList();
                if (internal.isEmpty && removable.isEmpty) {
                  return GlassCard(
                    child: const Text(
                      'Storage locations are unavailable. Refresh or pick a folder manually.',
                      style: TextStyle(color: NovaColors.muted),
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth > 620 ? 2 : 1;
                    final cards = <Widget>[
                      ...internal.map(
                        (volume) => _StorageCard(
                          title: 'Internal Memory',
                          path: volume.rootPath,
                          icon: Icons.phone_android_rounded,
                          videos: _filesUnder(library.files, volume.rootPath),
                        ),
                      ),
                      ...removable.map(
                        (volume) => _StorageCard(
                          title: 'SD Card',
                          path: volume.rootPath,
                          icon: Icons.sd_storage_rounded,
                          videos: _filesUnder(library.files, volume.rootPath),
                        ),
                      ),
                    ];
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns == 1 ? 2.5 : 1.45,
                      children: cards,
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'All Folders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (library.isScanning)
              const LinearProgressIndicator(color: NovaColors.cyan)
            else if (library.files.isEmpty)
              GlassCard(
                onTap: media.pickCustomDirectory,
                child: const Row(
                  children: [
                    Icon(Icons.folder_open_outlined, color: NovaColors.cyan),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No videos found. Pick a folder to scan media.',
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
              )
            else
              ...library.folders(ref.read(mediaRepositoryProvider)).map((
                folder,
              ) {
                final videos = library.files
                    .where((file) => file.folderName == folder.name)
                    .toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FolderCard(folder: folder, videos: videos),
                );
              }),
          ],
        ),
      ),
    );
  }
}

List<VideoFile> _filesUnder(List<VideoFile> files, String root) {
  final normalizedRoot = _normalizePath(root);
  return files
      .where((file) {
        final path = _normalizePath(file.path);
        return path.startsWith('$normalizedRoot/');
      })
      .toList(growable: false);
}

String _normalizePath(String value) => p.normalize(value.replaceAll('\\', '/'));

class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.title,
    required this.path,
    required this.icon,
    required this.videos,
  });

  final String title;
  final String path;
  final IconData icon;
  final List<VideoFile> videos;

  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _StorageFoldersScreen(title: title, rootPath: path, files: videos),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: NovaColors.cyan.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: NovaColors.cyan, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${videos.length} videos',
                style: const TextStyle(color: NovaColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NovaColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: NovaColors.muted),
      ],
    ),
  );
}

class _StorageFoldersScreen extends StatelessWidget {
  const _StorageFoldersScreen({
    required this.title,
    required this.rootPath,
    required this.files,
  });

  final String title;
  final String rootPath;
  final List<VideoFile> files;

  @override
  Widget build(BuildContext context) {
    final folders = const MediaRepository().foldersFor(files);
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: files.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.video_library_outlined,
                      size: 50,
                      color: NovaColors.cyan,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No indexed videos in this storage',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rootPath,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: NovaColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              itemCount: folders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final folder = folders[index];
                final videos = files
                    .where((file) => file.folderName == folder.name)
                    .toList(growable: false);
                return _FolderCard(folder: folder, videos: videos);
              },
            ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.folder, required this.videos});

  final FolderSummary folder;
  final List<VideoFile> videos;

  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderVideosScreen(folder: folder, videos: videos),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: NovaColors.violet.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(folder.icon, color: NovaColors.violet),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                folder.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                '${videos.length} videos  •  ${formatBytes(folder.sizeBytes)}',
                style: const TextStyle(color: NovaColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                folder.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NovaColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: NovaColors.muted),
      ],
    ),
  );
}
