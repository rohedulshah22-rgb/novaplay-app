import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/nova_widgets.dart';
import '../domain/video_file.dart';
import '../data/thumbnail_cache.dart';

class VideoArtwork extends StatefulWidget {
  const VideoArtwork({
    super.key,
    required this.file,
    this.aspectRatio = 16 / 10,
  });
  final VideoFile file;
  final double aspectRatio;

  @override
  State<VideoArtwork> createState() => _VideoArtworkState();
}

class _VideoArtworkState extends State<VideoArtwork> {
  late Future<String?> thumbnail;

  @override
  void initState() {
    super.initState();
    thumbnail = const ThumbnailCache().get(widget.file);
  }

  @override
  void didUpdateWidget(covariant VideoArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) {
      thumbnail = const ThumbnailCache().get(widget.file);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: thumbnail,
      builder: (context, snapshot) {
        return MediaArtwork(
          imagePath: snapshot.data,
          aspectRatio: widget.aspectRatio,
          icon: Icons.movie_creation_outlined,
          gradient: LinearGradient(
            colors: [
              NovaColors.cyan.withValues(alpha: .2),
              NovaColors.violet.withValues(alpha: .42),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      },
    );
  }
}

class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.file,
    required this.onTap,
    this.compact = false,
    this.onMore,
    this.onFavorite,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });
  final VideoFile file;
  final VoidCallback onTap;
  final bool compact;
  final VoidCallback? onMore;
  final VoidCallback? onFavorite;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress ?? onMore,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 178,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  VideoArtwork(file: file, aspectRatio: 16 / 10),
                  if (selectionMode)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: IgnorePointer(
                        child: Checkbox(
                          value: selected,
                          onChanged: null,
                          side: const BorderSide(color: Colors.white),
                          fillColor: WidgetStatePropertyAll(
                            selected ? NovaColors.cyan : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 10,
                    bottom: 9,
                    child: ResolutionBadge(label: file.resolution),
                  ),
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: _DurationPill(file: file),
                  ),
                  if (onFavorite != null)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: IconButton(
                        onPressed: onFavorite,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.pinkAccent),
                        icon: const Icon(Icons.favorite_border_rounded, size: 18),
                      ),
                    ),
                  if (onMore != null)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: IconButton(
                        onPressed: onMore,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.more_vert_rounded, size: 18),
                      ),
                    ),
                  if (file.completion > 0)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 3,
                      child: LinearProgressIndicator(
                        value: file.completion,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(4),
                        color: NovaColors.cyan,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                file.folderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NovaColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: onLongPress ?? onMore,
      child: GlassCard(
        padding: const EdgeInsets.all(10),
        borderRadius: 18,
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 132,
              child: Stack(
                children: [
                  VideoArtwork(file: file, aspectRatio: 16 / 10),
                  if (selectionMode)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: IgnorePointer(
                        child: Checkbox(
                          value: selected,
                          onChanged: null,
                          side: const BorderSide(color: Colors.white),
                          fillColor: WidgetStatePropertyAll(
                            selected ? NovaColors.cyan : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: ResolutionBadge(label: file.resolution),
                  ),
                  Positioned(
                    right: 7,
                    bottom: 7,
                    child: _DurationPill(file: file),
                  ),
                  if (file.completion > 0)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 2,
                      child: LinearProgressIndicator(
                        value: file.completion,
                        minHeight: 2,
                        color: NovaColors.cyan,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${file.folderName}  •  ${formatBytes(file.sizeBytes)}',
                    style: const TextStyle(
                      color: NovaColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.more_horiz,
                        size: 19,
                        color: NovaColors.muted,
                      ),
                      const Spacer(),
                      if (onFavorite != null)
                        IconButton(
                          onPressed: onFavorite,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.favorite_border_rounded, color: Colors.pinkAccent),
                        ),
                      IconButton(
                        onPressed: onTap,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          color: NovaColors.cyan,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.file});
  final VideoFile file;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        file.duration == Duration.zero
            ? file.extension
            : formatDuration(file.duration),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
