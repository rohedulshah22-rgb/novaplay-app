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
  String? output;
  Object? failure;
  final stopwatch = Stopwatch()..start();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var started = false;
      var progress = 0.0;
      var elapsedSeconds = 0;
      Timer? elapsedTimer;

      Future<void> runExtraction(
        void Function(void Function()) setDialogState,
      ) async {
        elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (dialogContext.mounted) {
            setDialogState(() => elapsedSeconds = stopwatch.elapsed.inSeconds);
          }
        });
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
          if (output == null) failure = StateError('No audio stream was extracted.');
        } catch (error) {
          failure = error;
        } finally {
          elapsedTimer?.cancel();
          stopwatch.stop();
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
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
                Text('Converting ${file.name}…',
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: file.duration > Duration.zero ? progress : null,
                  color: NovaColors.cyan,
                ),
                const SizedBox(height: 8),
                Text(file.duration > Duration.zero
                    ? '${(progress * 100).round()}% · ${elapsedSeconds}s elapsed'
                    : 'Working… ${elapsedSeconds}s elapsed'),
              ],
            ),
          );
        },
      );
    },
  );

  if (!context.mounted) return;
  if (failure == null && output != null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('MP3 saved to Music/NovaPlay')),
      );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(failure == null
          ? 'Audio Extracted Successfully'
          : 'Audio Extraction Failed'),
      content: Text(failure == null
          ? 'Saved to Music/NovaPlay${output == null ? '' : '\n$output'}'
          : failure.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
