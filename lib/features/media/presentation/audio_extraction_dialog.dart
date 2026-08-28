import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/audio_extraction_service.dart';
import '../domain/video_file.dart';

Future<void> showAudioExtractionDialog(
  BuildContext context,
  VideoFile file,
) async {
  final service = const AudioExtractionService();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var started = false;
      var progress = 0.0;
      var complete = false;
      String? output;
      String? error;

      Future<void> runExtraction(
        void Function(void Function()) setDialogState,
      ) async {
        try {
          output = await service.extractToMusic(
            sourcePath: file.path,
            sourceName: file.name,
            duration: file.duration,
            onProgress: (value) {
              if (dialogContext.mounted) {
                setDialogState(() => progress = value);
              }
            },
          );
          if (dialogContext.mounted) {
            setDialogState(() {
              complete = output != null;
              error = output == null
                  ? 'No audio stream could be extracted.'
                  : null;
              progress = 1.0;
            });
          }
        } catch (_) {
          if (dialogContext.mounted) {
            setDialogState(() {
              error = 'Audio extraction failed. Playback was not affected.';
              complete = false;
            });
          }
        }
      }

      return StatefulBuilder(
        builder: (context, setDialogState) {
          if (!started) {
            started = true;
            unawaited(runExtraction(setDialogState));
          }
          return AlertDialog(
            title: const Text('Extract Audio'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete
                      ? 'Saved to Music/NovaPlay'
                      : error ?? 'Converting ${file.name}…',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                if (!complete && error == null) ...[
                  LinearProgressIndicator(
                    value: file.duration > Duration.zero ? progress : null,
                    color: NovaColors.cyan,
                  ),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).round()}%'),
                ] else if (complete)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: NovaColors.cyan,
                    size: 32,
                  ),
              ],
            ),
            actions: [
              if (complete || error != null)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
            ],
          );
        },
      );
    },
  );
}
