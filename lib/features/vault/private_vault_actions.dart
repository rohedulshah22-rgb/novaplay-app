import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../ads/admob_service.dart';
import '../media/data/media_repository.dart';
import '../media/domain/video_file.dart';
import '../media/presentation/audio_extraction_dialog.dart';
import 'private_vault_service.dart';

Future<void> showVideoActions(
  BuildContext context,
  VideoFile file, {
  VoidCallback? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: NovaColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_rounded, color: NovaColors.violet),
              title: const Text('Move to Private Folder'),
              subtitle: const Text(
                'Hide from Android gallery and NovaPlay lists',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await _confirmMove(context, file.name);
                if (!confirmed || !context.mounted) return;
                try {
                  await privateVaultService.moveToVault(file);
                  onChanged?.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Video moved to Private Vault'),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not secure video: $error')),
                    );
                  }
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: const Text('Delete File'),
              subtitle: const Text(
                'Permanently remove this file from the device',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await _confirmDelete(context, file.name);
                if (!confirmed || !context.mounted) return;
                try {
                  await const MediaRepository().deleteFile(
                    path: file.path,
                    contentUri: file.contentUri,
                  );
                  onChanged?.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File deleted')),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not delete file: $error')),
                    );
                  }
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.audiotrack_rounded,
                color: NovaColors.cyan,
              ),
              title: const Text('Extract Audio / Convert to MP3'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final allowed = await NovaAdMob.instance.requirePremium(
                  context,
                  'Video to MP3 Converter',
                );
                if (allowed && context.mounted) {
                  await showAudioExtractionDialog(context, file);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete File?'),
      content: const Text(
        'Are you sure you want to delete this file from your device?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result == true;
}

Future<bool> _confirmMove(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Move to Private Vault?'),
      content: Text(
        '“$name” will be moved into NovaPlay’s app-private vault and removed from public media lists.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Move video'),
        ),
      ],
    ),
  );
  return result == true;
}
