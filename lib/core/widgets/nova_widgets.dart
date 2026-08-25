import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 22,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: NovaColors.surface.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: NovaColors.border.withValues(alpha: .72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: Material(color: Colors.transparent, child: child),
    );
    return onTap == null
        ? card
        : Semantics(
            button: true,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(borderRadius),
              child: card,
            ),
          );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -.4,
          ),
        ),
        const Spacer(),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              action!,
              style: const TextStyle(
                color: NovaColors.cyan,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class NeonIcon extends StatelessWidget {
  const NeonIcon(
    this.icon, {
    super.key,
    this.color = NovaColors.cyan,
    this.size = 21,
  });
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(icon, color: color, size: size);
}

class ResolutionBadge extends StatelessWidget {
  const ResolutionBadge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NovaColors.cyan.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: NovaColors.cyan,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
          ),
        ),
      ),
    );
  }
}

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    this.bytes,
    this.gradient,
    this.icon = Icons.movie_outlined,
    this.aspectRatio = 16 / 10,
  });
  final Uint8List? bytes;
  final Gradient? gradient;
  final IconData icon;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient:
                      gradient ??
                      const LinearGradient(
                        colors: [Color(0xFF162933), Color(0xFF312557)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -18,
                      top: -25,
                      child: Icon(
                        icon,
                        size: 110,
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    Center(
                      child: Icon(
                        icon,
                        size: 36,
                        color: Colors.white.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} GB'.replaceFirst(
      '0.',
      '.',
    );
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
