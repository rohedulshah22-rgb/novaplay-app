import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/folders/folders_screen.dart';
import 'features/home/home_screen.dart';
import 'features/media/presentation/media_providers.dart';
import 'features/music/music_audio_service.dart';
import 'features/music/music_screen.dart';
import 'features/playlists/playlists_screen.dart';
import 'features/reels/reels_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/vault/private_vault_screen.dart';

class NovaPlayApp extends ConsumerStatefulWidget {
  const NovaPlayApp({super.key});

  @override
  ConsumerState<NovaPlayApp> createState() => _NovaPlayAppState();
}

class _NovaPlayAppState extends ConsumerState<NovaPlayApp>
    with WidgetsBindingObserver {
  static const _playerChannel = MethodChannel('com.novaplay/player');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playerChannel.setMethodCallHandler(_handlePlayerChannel);
  }

  Future<void> _handlePlayerChannel(MethodCall call) async {
    if (call.method != 'notificationTapped' || !mounted) return;
    _openNowPlaying();
  }

  void _openNowPlaying() {
    if (!mounted) return;
    ref.read(appTabProvider.notifier).select(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MusicPlayerScreen()),
      );
    });
  }

  @override
  void dispose() {
    _playerChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(mediaLibraryProvider.notifier).onAppResumed();
      if (audioServiceReady.value && currentAudioHandler.mediaItem.value != null) {
        _openNowPlaying();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NovaPlay',
      debugShowCheckedModeBanner: false,
      theme: buildNovaTheme(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: NovaColors.black,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: child!,
      ),
      home: const NovaShell(),
    );
  }
}

class NovaShell extends ConsumerWidget {
  const NovaShell({super.key});

  static const screens = [
    HomeScreen(),
    MusicScreen(),
    FoldersScreen(),
    ReelsScreen(),
    PlaylistsScreen(),
    SettingsScreen(),
    PrivateVaultScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(appTabProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MusicMiniPlayer(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) =>
                ref.read(appTabProvider.notifier).select(value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle),
                label: 'Videos',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Music',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_open_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'Folders',
              ),
              NavigationDestination(
                icon: Icon(Icons.swipe_vertical_outlined),
                selectedIcon: Icon(Icons.swipe_vertical_rounded),
                label: 'Reels',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_play_next_outlined),
                selectedIcon: Icon(Icons.queue_play_next),
                label: 'Playlists',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Settings',
              ),
              NavigationDestination(
                icon: Icon(Icons.lock_outline_rounded),
                selectedIcon: Icon(Icons.lock_rounded),
                label: 'Vault',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
