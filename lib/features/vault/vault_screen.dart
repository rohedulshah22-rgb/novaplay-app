import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/domain/video_file.dart';
import '../player/player_screen.dart';
import 'vault_provider.dart';

class PrivateVaultScreen extends ConsumerWidget {
  const PrivateVaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultProvider);
    final controller = ref.read(vaultProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Private Vault',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (vault.isUnlocked)
            IconButton(
              onPressed: controller.lock,
              icon: const Icon(Icons.lock_open_rounded),
            ),
        ],
      ),
      body: vault.isUnlocked
          ? _UnlockedVault(vault: vault, controller: controller)
          : _LockedVault(vault: vault, onUnlock: controller.unlock),
    );
  }
}

class _LockedVault extends StatelessWidget {
  const _LockedVault({required this.vault, required this.onUnlock});
  final VaultState vault;
  final Future<bool> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NovaColors.violet.withValues(alpha: .13),
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: NovaColors.violet,
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'A quiet place for private videos',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unlock with your fingerprint, face, PIN, or pattern. Vault files are marked .nomedia and kept outside the main scan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NovaColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: vault.isBusy
                      ? null
                      : () async {
                          final ok = await onUnlock();
                          if (context.mounted && !ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  vault.message ?? 'Vault remains locked',
                                ),
                              ),
                            );
                          }
                        },
                  icon: vault.isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  label: const Text('Unlock vault'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnlockedVault extends StatelessWidget {
  const _UnlockedVault({required this.vault, required this.controller});
  final VaultState vault;
  final VaultNotifier controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Only you can see these files',
                style: TextStyle(color: NovaColors.muted),
              ),
            ),
            FilledButton.icon(
              onPressed: vault.isBusy ? null : controller.importVideos,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Import'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (vault.files.isEmpty)
          GlassCard(
            child: Column(
              children: [
                const Icon(
                  Icons.visibility_off_outlined,
                  color: NovaColors.cyan,
                  size: 40,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your vault is empty',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Import a video to move it out of the main NovaPlay library.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NovaColors.muted, fontSize: 12),
                ),
              ],
            ),
          )
        else
          ...vault.files.map(
            (file) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _VaultFileRow(
                file: file,
                onPlay: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(file: _toVideoFile(file)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  VideoFile _toVideoFile(File file) => VideoFile(
    id: file.path,
    path: file.path,
    name: file.path.split(Platform.pathSeparator).last,
    sizeBytes: file.lengthSync(),
    modifiedAt: file.statSync().modified,
  );
}

class _VaultFileRow extends StatelessWidget {
  const _VaultFileRow({required this.file, required this.onPlay});
  final File file;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onPlay,
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: NovaColors.violet),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              file.path.split(Platform.pathSeparator).last,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const Icon(Icons.play_arrow_rounded, color: NovaColors.cyan),
        ],
      ),
    );
  }
}
