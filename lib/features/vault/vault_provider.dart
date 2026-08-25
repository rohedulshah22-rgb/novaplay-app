import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final vaultProvider = NotifierProvider<VaultNotifier, VaultState>(
  VaultNotifier.new,
);

class VaultState {
  const VaultState({
    this.isUnlocked = false,
    this.isConfigured = false,
    this.files = const [],
    this.isBusy = false,
    this.message,
  });
  final bool isUnlocked;
  final bool isConfigured;
  final List<File> files;
  final bool isBusy;
  final String? message;

  VaultState copyWith({
    bool? isUnlocked,
    bool? isConfigured,
    List<File>? files,
    bool? isBusy,
    String? message,
    bool clearMessage = false,
  }) => VaultState(
    isUnlocked: isUnlocked ?? this.isUnlocked,
    isConfigured: isConfigured ?? this.isConfigured,
    files: files ?? this.files,
    isBusy: isBusy ?? this.isBusy,
    message: clearMessage ? null : (message ?? this.message),
  );
}

class VaultNotifier extends Notifier<VaultState> {
  final _auth = LocalAuthentication();
  Directory? _directory;

  @override
  VaultState build() {
    Future.microtask(_prepare);
    return const VaultState();
  }

  Future<void> _prepare() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'PrivateVault'));
    await directory.create(recursive: true);
    final nomedia = File(path.join(directory.path, '.nomedia'));
    if (!nomedia.existsSync()) await nomedia.create();
    _directory = directory;
    await _refreshFiles();
  }

  Future<bool> unlock() async {
    if (_directory == null) await _prepare();
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        state = state.copyWith(
          isBusy: false,
          message:
              'Set a fingerprint, face, PIN, or pattern in Android settings first.',
        );
        return false;
      }
      final success = await _auth.authenticate(
        localizedReason: 'Unlock your NovaPlay Private Vault',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      state = state.copyWith(
        isUnlocked: success,
        isConfigured: true,
        isBusy: false,
        message: success ? null : 'Vault remains locked',
      );
      if (success) await _refreshFiles();
      return success;
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        message: 'Authentication was unavailable on this device.',
      );
      return false;
    }
  }

  void lock() => state = state.copyWith(isUnlocked: false, files: const []);

  Future<void> importVideos() async {
    if (!state.isUnlocked || _directory == null) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4',
        'mkv',
        'avi',
        'webm',
        'mov',
        'flv',
        'ts',
        'm4v',
      ],
    );
    if (picked.isEmpty) return;
    state = state.copyWith(isBusy: true, clearMessage: true);
    for (final selected in picked) {
      final sourcePath = selected.path;
      if (sourcePath == null) continue;
      final destination = File(
        path.join(_directory!.path, path.basename(sourcePath)),
      );
      await File(sourcePath).copy(destination.path);
      try {
        await File(sourcePath).delete();
      } on FileSystemException {
        // Copy succeeds even when the source provider does not allow deletion.
      }
    }
    await _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    final directory = _directory;
    if (directory == null || !directory.existsSync() || !state.isUnlocked) {
      state = state.copyWith(isBusy: false);
      return;
    }
    final files = await directory
        .list()
        .where(
          (entity) =>
              entity is File && !path.basename(entity.path).startsWith('.'),
        )
        .map((entity) => entity as File)
        .toList();
    state = state.copyWith(files: files, isBusy: false);
  }
}
