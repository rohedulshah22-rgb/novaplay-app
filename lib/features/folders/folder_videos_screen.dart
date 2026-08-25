import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/domain/natural_sort.dart';
import '../media/domain/video_file.dart';
import 'folder_view_preferences.dart';
import '../media/presentation/video_card.dart';
import '../player/player_screen.dart';

class FolderVideosScreen extends StatefulWidget {
  const FolderVideosScreen({
    super.key,
    required this.folder,
    required this.videos,
  });

  final FolderSummary folder;
  final List<VideoFile> videos;

  @override
  State<FolderVideosScreen> createState() => _FolderVideosScreenState();
}

class _FolderVideosScreenState extends State<FolderVideosScreen> {
  bool isGrid = true;
  String sort = 'Name (A–Z)';
  String duration = 'All';
  String resolution = 'All';

  @override
  void initState() {
    super.initState();
    _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    final preferences = await FolderViewPreferences.load();
    if (!mounted) return;
    setState(() {
      sort = preferences.sort;
      duration = preferences.duration;
      resolution = preferences.resolution;
      isGrid = preferences.isGrid;
    });
  }

  Future<void> _savePreferences() => FolderViewPreferences.save(
    sort: sort,
    duration: duration,
    resolution: resolution,
    isGrid: isGrid,
  );

  List<VideoFile> get visibleVideos {
    final filtered = widget.videos.where((file) {
      final matchesDuration = switch (duration) {
        '< 10 min' =>
          file.duration == Duration.zero || file.duration.inMinutes < 10,
        '10–30 min' =>
          file.duration == Duration.zero ||
              (file.duration.inMinutes >= 10 && file.duration.inMinutes < 30),
        '30+ min' =>
          file.duration == Duration.zero || file.duration.inMinutes >= 30,
        _ => true,
      };
      final matchesResolution =
          resolution == 'All' || file.resolution == resolution;
      return matchesDuration && matchesResolution;
    }).toList();

    filtered.sort((a, b) {
      return switch (sort) {
        'Name (A–Z)' => NaturalSort.compareVideos(a, b),
        'Largest' => b.sizeBytes.compareTo(a.sizeBytes),
        _ => b.modifiedAt.compareTo(a.modifiedAt),
      };
    });
    return filtered;
  }

  void openPlayer(VideoFile file) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(file: file)));
  }

  @override
  Widget build(BuildContext context) {
    final videos = visibleVideos;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.folder_rounded,
                  size: 15,
                  color: NovaColors.cyan,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            Text(
              'Folders  /  ${widget.folder.name}',
              style: const TextStyle(
                color: NovaColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showOptions,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            onPressed: () {
              setState(() => isGrid = !isGrid);
              _savePreferences();
            },
            icon: Icon(
              isGrid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          GlassCard(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: NovaColors.violet.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.folder.icon, color: NovaColors.violet),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.folder.count} videos',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatBytes(widget.folder.sizeBytes)}  •  ${sort == 'Name (A–Z)' ? 'Natural episode order' : sort}',
                        style: const TextStyle(
                          color: NovaColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (videos.isEmpty)
            GlassCard(
              child: Column(
                children: [
                  const Icon(
                    Icons.video_library_outlined,
                    color: NovaColors.cyan,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No videos match these filters',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Try clearing the duration or resolution filter.',
                    style: TextStyle(color: NovaColors.muted, fontSize: 12),
                  ),
                ],
              ),
            )
          else if (isGrid)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: videos.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 20,
                childAspectRatio: .79,
              ),
              itemBuilder: (_, index) => VideoCard(
                file: videos[index],
                compact: true,
                onTap: () => openPlayer(videos[index]),
              ),
            )
          else
            ...videos.map(
              (file) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: VideoCard(file: file, onTap: () => openPlayer(file)),
              ),
            ),
        ],
      ),
    );
  }

  void _showOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Folder view',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Sort by',
                  style: TextStyle(
                    color: NovaColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _choiceRow(['Name (A–Z)', 'Recent', 'Largest'], sort, (value) {
                  setState(() => sort = value);
                  _savePreferences();
                  setModalState(() {});
                }),
                const SizedBox(height: 16),
                const Text(
                  'Duration',
                  style: TextStyle(
                    color: NovaColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _choiceRow(
                  ['All', '< 10 min', '10–30 min', '30+ min'],
                  duration,
                  (value) {
                    setState(() => duration = value);
                    _savePreferences();
                    setModalState(() {});
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Resolution',
                  style: TextStyle(
                    color: NovaColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _choiceRow(['All', '4K', '1080p', '720p'], resolution, (value) {
                  setState(() => resolution = value);
                  _savePreferences();
                  setModalState(() {});
                }),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _choiceRow(
    List<String> values,
    String selected,
    ValueChanged<String> onSelected,
  ) {
    return Wrap(
      spacing: 8,
      children: values
          .map(
            (value) => ChoiceChip(
              label: Text(value),
              selected: selected == value,
              onSelected: (_) => onSelected(value),
            ),
          )
          .toList(),
    );
  }
}
