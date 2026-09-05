import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import '../media/data/media_preferences.dart';
import '../vault/private_vault_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool autoplay = true;
  bool rememberPosition = true;
  bool backgroundAudio = true;
  bool keepAwake = true;
  bool haptics = true;
  bool hideShortClips = false;
  Set<String> excludedFolders = <String>{};

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    final folders = await mediaPreferences.excludedFolders();
    final short = await mediaPreferences.hideShortClips();
    if (mounted) {
      setState(() {
        excludedFolders = folders;
        hideShortClips = short;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Text(
            'Playback',
            style: TextStyle(
              color: NovaColors.cyan,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.play_arrow_rounded,
                  title: 'Autoplay videos',
                  subtitle: 'Start immediately when opening a file',
                  value: autoplay,
                  onChanged: (value) => setState(() => autoplay = value),
                ),
                _SettingTile(
                  icon: Icons.bookmark_outline_rounded,
                  title: 'Remember position',
                  subtitle: 'Resume from your last watched moment',
                  value: rememberPosition,
                  onChanged: (value) =>
                      setState(() => rememberPosition = value),
                ),
                _SettingTile(
                  icon: Icons.headphones_outlined,
                  title: 'Background audio',
                  subtitle: 'Keep audio playing when you leave the player',
                  value: backgroundAudio,
                  onChanged: (value) => setState(() => backgroundAudio = value),
                ),
                _SettingTile(
                  icon: Icons.screen_lock_portrait_outlined,
                  title: 'Keep screen awake',
                  subtitle: 'Prevent sleep while watching',
                  value: keepAwake,
                  onChanged: (value) => setState(() => keepAwake = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            'Experience',
            style: TextStyle(
              color: NovaColors.violet,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.vibration_rounded,
                  title: 'Gesture haptics',
                  subtitle: 'Subtle feedback for player actions',
                  value: haptics,
                  onChanged: (value) => setState(() => haptics = value),
                ),
                _ActionTile(
                  icon: Icons.folder_off_outlined,
                  title: 'Hide clutter folders',
                  subtitle: excludedFolders.isEmpty ? 'No folders excluded' : excludedFolders.join(', '),
                  onTap: _editExcludedFolders,
                ),
                _SettingTile(
                  icon: Icons.filter_alt_outlined,
                  title: 'Hide short clips',
                  subtitle: 'Exclude videos and audio shorter than 30 seconds',
                  value: hideShortClips,
                  onChanged: (value) async {
                    setState(() => hideShortClips = value);
                    await mediaPreferences.setHideShortClips(value);
                  },
                ),
                _ActionTile(
                  icon: Icons.folder_copy_outlined,
                  title: 'Manage indexed folders',
                  onTap: () => _toast(context, 'Use folder cards on the Videos tab to add folders'),
                ),
                _ActionTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Private Vault',
                  subtitle: 'Fingerprint, face, PIN, or pattern protected',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivateVaultScreen(),
                    ),
                  ),
                ),
                _ActionTile(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Clear resume history',
                  onTap: () => _toast(context, 'Resume history cleared'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          GlassCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [NovaColors.cyan, NovaColors.violet],
                    ),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: NovaColors.black,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NovaPlay',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Version 1.0.0  •  Built for offline-first watching',
                        style: TextStyle(color: NovaColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editExcludedFolders() async {
    final controller = TextEditingController(text: excludedFolders.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hide folders'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'WhatsApp, Cache, ShortClips'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    final folders = result.split(',').map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    await mediaPreferences.setExcludedFolders(folders);
    if (mounted) setState(() => excludedFolders = folders);
  }

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: NovaColors.cyan),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: NovaColors.muted, fontSize: 11),
    ),
    trailing: Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: NovaColors.cyan,
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: NovaColors.violet),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            style: const TextStyle(color: NovaColors.muted, fontSize: 11),
          ),
    trailing: const Icon(Icons.chevron_right_rounded, color: NovaColors.muted),
  );
}
