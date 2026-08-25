import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/presentation/media_providers.dart';
import 'folder_videos_screen.dart';

class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(mediaLibraryProvider);
    final media = ref.read(mediaLibraryProvider.notifier);
    final folders = library.folders(ref.read(mediaRepositoryProvider));
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
            tooltip: 'Refresh media store',
            onPressed: () => media.load(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: NovaColors.cyan,
        onRefresh: () => media.load(force: true),
        child: folders.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * .25),
                  const Center(
                    child: Icon(
                      Icons.folder_open_outlined,
                      color: NovaColors.cyan,
                      size: 54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'No folders indexed yet',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'NovaPlay will group videos from MediaStore after scanning. For USB/SD locations or folders hidden from MediaStore, pick a directory manually.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: NovaColors.muted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: FilledButton.icon(
                      onPressed: media.pickCustomDirectory,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Pick a folder'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                itemCount: folders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final folder = folders[index];
                  return GlassCard(
                    onTap: () {
                      final videos = library.files
                          .where((file) => file.folderName == folder.name)
                          .toList();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FolderVideosScreen(
                            folder: folder,
                            videos: videos,
                          ),
                        ),
                      );
                    },
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${folder.count} videos  •  ${formatBytes(folder.sizeBytes)}',
                                style: const TextStyle(
                                  color: NovaColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                folder.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: NovaColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: NovaColors.muted,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
