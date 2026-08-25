import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/domain/video_file.dart';
import '../media/presentation/media_providers.dart';
import '../media/presentation/video_card.dart';
import '../player/player_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final searchController = TextEditingController();
  bool isGrid = true;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void openPlayer(VideoFile file) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(file: file)));
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(mediaLibraryProvider);
    final media = ref.read(mediaLibraryProvider.notifier);
    final resume = library.recentlyPlayed;
    final folders = library
        .folders(ref.read(mediaRepositoryProvider))
        .take(4)
        .toList();
    final files = library.filteredFiles;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: NovaColors.cyan,
          backgroundColor: NovaColors.surfaceElevated,
          onRefresh: () => media.load(force: true),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _Header(
                      onSettings: () =>
                          ref.read(appTabProvider.notifier).select(4),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      'Your offline cinema',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                          ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Everything you downloaded. One calm place to watch.',
                      style: TextStyle(color: NovaColors.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: searchController,
                      onChanged: media.setQuery,
                      decoration: InputDecoration(
                        hintText: 'Search videos, folders…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          onPressed: _showFilters,
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    if (resume.isNotEmpty) ...[
                      SectionTitle(
                        title: 'Resume watching',
                        action: 'See all',
                        onAction: () => _scrollToLibrary(),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 206,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: resume.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (_, index) => _ResumeCard(
                            file: resume[index],
                            onTap: () => openPlayer(resume[index]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                    SectionTitle(
                      title: 'Smart folders',
                      action: 'Manage',
                      onAction: () =>
                          ref.read(appTabProvider.notifier).select(1),
                    ),
                    const SizedBox(height: 14),
                    if (folders.isEmpty)
                      const _EmptyFolders()
                    else
                      SizedBox(
                        height: 112,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: folders.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 11),
                          itemBuilder: (_, index) => _FolderCard(
                            folder: folders[index],
                            onTap: () => _showFolder(folders[index]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        const Expanded(
                          child: SectionTitle(title: 'All videos'),
                        ),
                        IconButton(
                          onPressed: () => setState(() => isGrid = !isGrid),
                          icon: Icon(
                            isGrid
                                ? Icons.view_agenda_outlined
                                : Icons.grid_view_rounded,
                            color: NovaColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!library.hasPermission)
                      const _PermissionCard()
                    else if (library.isScanning && library.files.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 42),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: NovaColors.cyan,
                          ),
                        ),
                      )
                    else if (library.errorMessage != null)
                      _ErrorCard(
                        message: library.errorMessage!,
                        onRetry: () => media.load(force: true),
                      )
                    else if (files.isEmpty)
                      _EmptyLibrary(onRefresh: () => media.load(force: true))
                    else if (isGrid)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: files.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 20,
                              childAspectRatio: .79,
                            ),
                        itemBuilder: (_, index) => VideoCard(
                          file: files[index],
                          compact: true,
                          onTap: () => openPlayer(files[index]),
                        ),
                      )
                    else
                      ...files.map(
                        (file) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: VideoCard(
                            file: file,
                            onTap: () => openPlayer(file),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToLibrary() {}

  void _showFilters() {
    final library = ref.read(mediaLibraryProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter your library',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              const Text(
                'Duration',
                style: TextStyle(
                  color: NovaColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: ['All', '< 10 min', '10–30 min', '30+ min']
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value),
                        selected: library.durationFilter == value,
                        onSelected: (_) {
                          ref
                              .read(mediaLibraryProvider.notifier)
                              .setDurationFilter(value);
                          setModalState(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              const Text(
                'Resolution',
                style: TextStyle(
                  color: NovaColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: ['All', '4K', '1080p', '720p']
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value),
                        selected: library.resolutionFilter == value,
                        onSelected: (_) {
                          ref
                              .read(mediaLibraryProvider.notifier)
                              .setResolutionFilter(value);
                          setModalState(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Apply filters'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFolder(FolderSummary folder) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Opening ${folder.name}')));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [NovaColors.cyan, NovaColors.violet],
          ),
        ),
        child: const Icon(
          Icons.bolt_rounded,
          color: NovaColors.black,
          size: 25,
        ),
      ),
      const SizedBox(width: 11),
      const Text(
        'NovaPlay',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 20,
          letterSpacing: -.8,
        ),
      ),
      const Spacer(),
      IconButton(
        onPressed: onSettings,
        icon: const Icon(Icons.tune_rounded, color: NovaColors.muted),
      ),
    ],
  );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.file, required this.onTap});
  final VideoFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                VideoArtwork(file: file, aspectRatio: 16 / 10),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: ResolutionBadge(label: file.resolution),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .74),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Text(
                        file.extension,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: file.completion,
                minHeight: 4,
                backgroundColor: NovaColors.border,
                color: NovaColors.cyan,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${(file.completion * 100).round()}% watched',
              style: const TextStyle(color: NovaColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.folder, required this.onTap});
  final FolderSummary folder;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NovaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NovaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(folder.icon, color: NovaColors.violet, size: 23),
          const Spacer(),
          Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            '${folder.count} videos  •  ${formatBytes(folder.sizeBytes)}',
            style: const TextStyle(color: NovaColors.muted, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders();
  @override
  Widget build(BuildContext context) => Container(
    height: 112,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: NovaColors.surfaceElevated,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: NovaColors.border),
    ),
    child: const Text(
      'Folders will appear after your first scan.',
      style: TextStyle(color: NovaColors.muted, fontSize: 12),
    ),
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onRefresh});
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      children: [
        const Icon(
          Icons.video_library_outlined,
          color: NovaColors.cyan,
          size: 42,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your library is ready when you are',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Drop videos into Downloads or Movies, then rescan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: NovaColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Scan again'),
        ),
      ],
    ),
  );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard();
  @override
  Widget build(BuildContext context) => GlassCard(
    child: const Row(
      children: [
        Icon(Icons.lock_outline_rounded, color: NovaColors.yellow),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'NovaPlay needs video access to build your offline library.',
            style: TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => GlassCard(
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: NovaColors.yellow),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
