import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';

class PrecisionScrubber extends StatefulWidget {
  const PrecisionScrubber({
    super.key,
    required this.sourcePath,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.onInteraction,
  });
  final String sourcePath;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onInteraction;

  @override
  State<PrecisionScrubber> createState() => _PrecisionScrubberState();
}

class _PrecisionScrubberState extends State<PrecisionScrubber> {
  bool dragging = false;
  late double previewMilliseconds;
  late List<Future<Uint8List?>> thumbnails;

  @override
  void initState() {
    super.initState();
    previewMilliseconds = widget.position.inMilliseconds.toDouble();
    thumbnails = _buildThumbnails();
  }

  @override
  void didUpdateWidget(covariant PrecisionScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!dragging && oldWidget.sourcePath != widget.sourcePath) {
      thumbnails = _buildThumbnails();
    }
    if (!dragging) {
      previewMilliseconds = widget.position.inMilliseconds.toDouble();
    }
  }

  List<Future<Uint8List?>> _buildThumbnails() {
    final length = widget.duration.inMilliseconds;
    if (length <= 0) return const [];
    return List.generate(9, (index) {
      final time = (length * index / 8).round();
      return VideoThumbnail.thumbnailData(
        video: widget.sourcePath,
        imageFormat: ImageFormat.JPEG,
        timeMs: time,
        maxWidth: 150,
        quality: 55,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.duration.inMilliseconds <= 0
        ? 1.0
        : widget.duration.inMilliseconds.toDouble();
    return Column(
      children: [
        if (dragging && thumbnails.isNotEmpty)
          _ThumbnailStrip(
            thumbnails: thumbnails,
            selected: (previewMilliseconds / max).clamp(0, 1),
          ),
        Row(
          children: [
            Text(
              formatDuration(
                Duration(milliseconds: previewMilliseconds.round()),
              ),
              style: const TextStyle(fontSize: 11),
            ),
            Expanded(
              child: Slider(
                value: previewMilliseconds.clamp(0, max),
                max: max,
                onChangeStart: (_) {
                  setState(() => dragging = true);
                  widget.onInteraction?.call();
                },
                onChanged: (value) {
                  setState(() => previewMilliseconds = value);
                  widget.onInteraction?.call();
                },
                onChangeEnd: (value) {
                  final next = Duration(milliseconds: value.round());
                  widget.onSeek(next);
                  setState(() => dragging = false);
                  widget.onInteraction?.call();
                },
              ),
            ),
            Text(
              formatDuration(widget.duration),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({required this.thumbnails, required this.selected});
  final List<Future<Uint8List?>> thumbnails;
  final double selected;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: thumbnails.length,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (_, index) => FutureBuilder<Uint8List?>(
        future: thumbnails[index],
        builder: (_, snapshot) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: (index / (thumbnails.length - 1) - selected).abs() < .08
                  ? NovaColors.cyan
                  : Colors.transparent,
              width: 2,
            ),
            image: snapshot.data == null
                ? null
                : DecorationImage(
                    image: MemoryImage(snapshot.data!),
                    fit: BoxFit.cover,
                  ),
          ),
          child: snapshot.data == null
              ? const ColoredBox(
                  color: NovaColors.surfaceElevated,
                  child: Icon(
                    Icons.movie_outlined,
                    size: 18,
                    color: NovaColors.muted,
                  ),
                )
              : null,
        ),
      ),
    ),
  );
}
