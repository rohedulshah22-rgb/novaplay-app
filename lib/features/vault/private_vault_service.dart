import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/domain/video_file.dart';

class PrivateVaultEntry {
  const PrivateVaultEntry({
    required this.id,
    required this.name,
    required this.vaultPath,
    required this.originalPath,
    required this.originalUri,
    required this.originalRelativePath,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String id;
  final String name;
  final String vaultPath;
  final String? originalPath;
  final String? originalUri;
  final String? originalRelativePath;
  final int sizeBytes;
  final DateTime modifiedAt;

  VideoFile toVideoFile() => VideoFile(
    id: 'vault:$id',
    path: vaultPath,
    name: name,
    sizeBytes: sizeBytes,
    modifiedAt: modifiedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'vaultPath': vaultPath,
    'originalPath': originalPath,
    'originalUri': originalUri,
    'originalRelativePath': originalRelativePath,
    'sizeBytes': sizeBytes,
    'modifiedAt': modifiedAt.toIso8601String(),
  };

  factory PrivateVaultEntry.fromJson(Map<String, dynamic> json) =>
      PrivateVaultEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        vaultPath: json['vaultPath'] as String,
        originalPath: json['originalPath'] as String?,
        originalUri: json['originalUri'] as String?,
        originalRelativePath: json['originalRelativePath'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        modifiedAt:
            DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class PrivateVaultService {
  PrivateVaultService._();
  static final instance = PrivateVaultService._();

  static const _pinKey = 'novaplay.vault.pin.v1';
  static const _entriesKey = 'novaplay.vault.entries.v1';
  static const _biometricKey = 'novaplay.vault.biometric.v1';
  static const _mediaChannel = MethodChannel('com.novaplay/media');
  static const _secureStorage = FlutterSecureStorage();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isConfigured() async =>
      (await _secureStorage.read(key: _pinKey))?.isNotEmpty == true;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const FormatException('PIN must contain exactly four digits');
    }
    await _secureStorage.write(key: _pinKey, value: pin);
  }

  Future<bool> verifyPin(String pin) async =>
      pin == await _secureStorage.read(key: _pinKey);

  Future<bool> biometricAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> biometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? true;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock your NovaPlay Private Vault',
      );
    } catch (_) {
      return false;
    }
  }

  Future<List<PrivateVaultEntry>> entries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_entriesKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                PrivateVaultEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((entry) => File(entry.vaultPath).existsSync())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveEntries(List<PrivateVaultEntry> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _entriesKey,
      jsonEncode(value.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<PrivateVaultEntry> moveToVault(VideoFile file) async {
    final current = await entries();
    if (current.any((entry) => entry.id == file.id)) {
      return current.firstWhere((entry) => entry.id == file.id);
    }

    final result = await _mediaChannel
        .invokeMethod<Map<dynamic, dynamic>>('moveToVault', {
          'sourcePath': file.path,
          'contentUri': file.contentUri,
          'relativePath': file.relativePath,
          'displayName': file.name,
        });
    final map = Map<String, dynamic>.from(result ?? const {});
    final entry = PrivateVaultEntry(
      id: file.id,
      name: file.name,
      vaultPath: map['vaultPath'] as String? ?? '',
      originalPath: file.path,
      originalUri: file.contentUri,
      originalRelativePath: file.relativePath,
      sizeBytes: file.sizeBytes,
      modifiedAt: file.modifiedAt,
    );
    if (entry.vaultPath.isEmpty) {
      throw StateError('The vault file could not be created');
    }
    await _saveEntries([...current, entry]);
    return entry;
  }

  Future<void> restore(PrivateVaultEntry entry) async {
    await _mediaChannel.invokeMethod<void>('restoreFromVault', {
      'vaultPath': entry.vaultPath,
      'originalPath': entry.originalPath,
      'displayName': entry.name,
      'contentUri': entry.originalUri,
      'relativePath': entry.originalRelativePath,
    });
    await _saveEntries(
      (await entries())
          .where((item) => item.id != entry.id)
          .toList(growable: false),
    );
  }

  Future<void> deletePermanently(PrivateVaultEntry entry) async {
    final file = File(entry.vaultPath);
    if (await file.exists()) await file.delete();
    await _saveEntries(
      (await entries())
          .where((item) => item.id != entry.id)
          .toList(growable: false),
    );
  }

  Future<void> resetVault() async {
    for (final entry in await entries()) {
      final file = File(entry.vaultPath);
      if (await file.exists()) await file.delete();
    }
    await _saveEntries(const []);
    await _secureStorage.delete(key: _pinKey);
  }

  Future<Directory> fallbackVaultDirectory() async {
    final root = await getApplicationSupportDirectory();
    final vault = Directory(p.join(root.path, 'private_vault'));
    await vault.create(recursive: true);
    return vault;
  }
}

final privateVaultService = PrivateVaultService.instance;

class VaultSession {
  VaultSession._();
  static final instance = VaultSession._();
  bool unlocked = false;
}

final vaultSession = VaultSession.instance;

String vaultDisplayName(String name) => p.basename(name);
