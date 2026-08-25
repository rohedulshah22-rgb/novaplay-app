import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_theme.dart';
import '../media/domain/video_file.dart';
import '../media/presentation/media_providers.dart';

class ReelsScreen extends ConsumerWidget {
  const ReelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(mediaLibraryProvider);
    final reels = library.files
        .where(
          (file) =>
              file.height > file.width || (file.width == 0 && file.height == 0),
        )
        .toList();
    if (reels.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black, body: _EmptyReels());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: reels.length,
        itemBuilder: (context, index) =>
            ReelPage(file: reels[index], isActive: index == 0),
      ),
    );
  }
}

class ReelPage extends StatefulWidget {
  const ReelPage({super.key, required this.file, this.isActive = false});
  final VideoFile file;
  final bool isActive;
  @override
  State<ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<ReelPage> {
  late final Player player;
  late final VideoController controller;
  bool showControls = true;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    player.open(Media(widget.file.path), play: widget.isActive);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => showControls = !showControls),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Video(controller: controller, controls: NoVideoControls),
          ),
          if (showControls)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent, Colors.black87],
                  stops: [0, .46, 1],
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 14),
                    const Text(
                      'REELS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: NovaColors.cyan,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reels are stored locally only'),
                            ),
                          ),
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 8, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.file.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '${widget.file.folderName}  •  ${widget.file.extension}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 15),
                            StreamBuilder<bool>(
                              stream: player.stream.playing,
                              initialData: player.state.playing,
                              builder: (context, snapshot) => FilledButton.icon(
                                onPressed: () => player.playOrPause(),
                                icon: Icon(
                                  snapshot.data == true
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  snapshot.data == true ? 'Pause' : 'Play',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 13, bottom: 18),
                      child: Column(
                        children: [
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.favorite_border_rounded,
                              size: 30,
                            ),
                          ),
                          const Text('Save', style: TextStyle(fontSize: 10)),
                          const SizedBox(height: 12),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.playlist_add_rounded,
                              size: 30,
                            ),
                          ),
                          const Text('Queue', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReels extends StatelessWidget {
  const _EmptyReels();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NovaColors.cyan.withValues(alpha: .12),
            ),
            child: const Icon(
              Icons.swipe_vertical_rounded,
              color: NovaColors.cyan,
              size: 39,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your vertical cinema is empty',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Portrait videos will appear here as a full-screen swipe feed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NovaColors.muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}
