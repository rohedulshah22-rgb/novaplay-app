import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/presentation/video_card.dart';
import '../player/player_screen.dart';
import 'private_vault_service.dart';

class PrivateVaultScreen extends StatefulWidget {
  const PrivateVaultScreen({super.key});

  @override
  State<PrivateVaultScreen> createState() => _PrivateVaultScreenState();
}

class _PrivateVaultScreenState extends State<PrivateVaultScreen>
    with WidgetsBindingObserver {
  bool unlocked = false;
  bool loading = true;
  bool configured = false;
  bool biometricAvailable = false;
  bool biometricEnabled = true;
  List<PrivateVaultEntry> items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      setState(() => unlocked = false);
      vaultSession.unlocked = false;
    }
  }

  Future<void> _load() async {
    final service = privateVaultService;
    final values = await Future.wait([
      service.isConfigured(),
      service.biometricAvailable(),
      service.biometricEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      configured = values[0] as bool;
      biometricAvailable = values[1] as bool;
      biometricEnabled = values[2] as bool;
      loading = false;
    });
    if (vaultSession.unlocked && configured) {
      await _loadItems();
    }
  }

  Future<void> _loadItems() async {
    final values = await privateVaultService.entries();
    if (mounted) setState(() => items = values);
  }

  Future<void> _unlock() async {
    if (!configured) {
      final pin = await _showPinSetup();
      if (pin == null) return;
      await privateVaultService.setPin(pin);
      configured = true;
    }

    var success = false;
    if (biometricAvailable && biometricEnabled) {
      success = await privateVaultService.authenticateBiometric();
    }
    if (!success) {
      final pin = await _showPinEntry();
      success = pin != null && await privateVaultService.verifyPin(pin);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect PIN')),
        );
      }
    }
    if (!success || !mounted) return;
    vaultSession.unlocked = true;
    setState(() => unlocked = true);
    await _loadItems();
  }

  Future<void> _play(PrivateVaultEntry entry) async {
    if (!unlocked) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(file: entry.toVideoFile())),
    );
    if (mounted) await _loadItems();
  }

  Future<void> _restore(PrivateVaultEntry entry) async {
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore video?'),
        content: Text('Restore “${entry.name}” to its original folder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (shouldRestore != true) return;
    try {
      await privateVaultService.restore(entry);
      await _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video restored to the public library')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore video: $error')),
        );
      }
    }
  }

  Future<void> _vaultSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password_rounded),
              title: const Text('Change PIN'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final pin = await _showPinSetup(title: 'Change Private Vault PIN');
                if (pin != null) await privateVaultService.setPin(pin);
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Use biometrics'),
              subtitle: const Text('Fingerprint or face unlock when available'),
              value: biometricEnabled && biometricAvailable,
              onChanged: biometricAvailable
                  ? (value) async {
                      await privateVaultService.setBiometricEnabled(value);
                      if (mounted) setState(() => biometricEnabled = value);
                    }
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              title: const Text('Reset Vault', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Permanently deletes vault copies; does not restore them'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Reset Private Vault?'),
                    content: const Text('This permanently deletes every video currently in the vault.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reset vault')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await privateVaultService.resetVault();
                  if (mounted) {
                    setState(() {
                      configured = false;
                      unlocked = false;
                      items = const [];
                    });
                    vaultSession.unlocked = false;
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: NovaColors.cyan));
    }
    if (!unlocked) {
      return _LockedVault(
        configured: configured,
        biometricAvailable: biometricAvailable,
        onUnlock: _unlock,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Vault', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _vaultSettings, icon: const Icon(Icons.settings_outlined)),
          IconButton(
            tooltip: 'Lock vault',
            onPressed: () {
              vaultSession.unlocked = false;
              setState(() => unlocked = false);
            },
            icon: const Icon(Icons.lock_outline_rounded),
          ),
        ],
      ),
      body: items.isEmpty
          ? const _EmptyVault()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final entry = items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VideoCard(
                    file: entry.toVideoFile(),
                    onTap: () => _play(entry),
                    onMore: () => _entryActions(entry),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _entryActions(PrivateVaultEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NovaColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded, color: NovaColors.cyan),
              title: const Text('Play Video'),
              onTap: () { Navigator.pop(sheetContext); _play(entry); },
            ),
            ListTile(
              leading: const Icon(Icons.lock_open_rounded),
              title: const Text('Unhide / Restore Video'),
              onTap: () { Navigator.pop(sheetContext); _restore(entry); },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showPinSetup({String title = 'Set up Private Vault'}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create a 4-digit PIN. Keep it safe; it is required if biometrics are unavailable.'),
            const SizedBox(height: 16),
            TextField(controller: first, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, autofocus: true, decoration: const InputDecoration(labelText: 'New PIN')),
            TextField(controller: second, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Confirm PIN')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (RegExp(r'^\d{4}$').hasMatch(first.text) && first.text == second.text) {
                Navigator.pop(dialogContext, first.text);
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<String?> _showPinEntry() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlock Private Vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '4-digit PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Unlock')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _LockedVault extends StatelessWidget {
  const _LockedVault({required this.configured, required this.biometricAvailable, required this.onUnlock});
  final bool configured;
  final bool biometricAvailable;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(configured ? Icons.lock_rounded : Icons.shield_rounded, size: 64, color: NovaColors.violet),
            const SizedBox(height: 18),
            Text(configured ? 'Private Vault is locked' : 'Set up your Private Vault', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(configured ? 'Your videos are stored in NovaPlay’s app-private storage.' : 'Protect sensitive videos with a 4-digit PIN and optional biometrics.', style: const TextStyle(color: NovaColors.muted), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onUnlock, icon: Icon(configured && biometricAvailable ? Icons.fingerprint_rounded : Icons.lock_open_rounded), label: Text(configured ? 'Unlock Vault' : 'Create PIN')),
          ],
        ),
      ),
    ),
  );
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.video_library_outlined, size: 54, color: NovaColors.muted),
          SizedBox(height: 14),
          Text('Your Private Vault is empty', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          SizedBox(height: 7),
          Text('Use a video’s menu and choose “Move to Private Folder”.', style: TextStyle(color: NovaColors.muted), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
EOF
