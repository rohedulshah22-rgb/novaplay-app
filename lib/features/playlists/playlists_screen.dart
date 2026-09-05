import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../media/data/media_preferences.dart';
import '../../core/widgets/nova_widgets.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  Map<String, List<String>> customPlaylists = {};

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final value = await mediaPreferences.playlists();
    if (mounted) setState(() => customPlaylists = value);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = [
      (
        'Watch later',
        'Your saved queue',
        Icons.bookmark_border_rounded,
        NovaColors.cyan,
      ),
      (
        'Favorites',
        'Videos you never skip',
        Icons.favorite_border_rounded,
        NovaColors.violet,
      ),
      (
        'Recently added',
        'Fresh from your folders',
        Icons.auto_awesome_motion_outlined,
        NovaColors.green,
      ),
    ];
    final custom = customPlaylists.keys.map(
      (name) => (name, '${customPlaylists[name]!.length} saved items', Icons.playlist_play_rounded, NovaColors.cyan),
    );
    final allPlaylists = [...playlists, ...custom];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Playlists',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: () => _newPlaylist(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Text(
            'Curate your offline queue',
            style: TextStyle(color: NovaColors.muted),
          ),
          const SizedBox(height: 20),
          ...allPlaylists.map(
            (playlist) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${playlist.$1} is empty')),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: playlist.$4.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(playlist.$3, color: playlist.$4),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.$1,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            playlist.$2,
                            style: const TextStyle(
                              color: NovaColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: NovaColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          GlassCard(
            child: Column(
              children: [
                const Icon(
                  Icons.playlist_add_rounded,
                  color: NovaColors.cyan,
                  size: 34,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Make it yours',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Create focused queues for commutes, flights, or late-night watching.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NovaColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => _newPlaylist(context),
                  child: const Text('Create playlist'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _newPlaylist(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              if (controller.text.trim().isNotEmpty) {
                await mediaPreferences.createPlaylist(controller.text.trim());
                await _loadPlaylists();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created ${controller.text.trim()}')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
