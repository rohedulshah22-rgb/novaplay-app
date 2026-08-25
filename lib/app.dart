import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'features/folders/folders_screen.dart';
import 'features/home/home_screen.dart';
import 'features/playlists/playlists_screen.dart';
import 'features/reels/reels_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/media/presentation/media_providers.dart';

class NovaPlayApp extends StatelessWidget {
  const NovaPlayApp({super.key});

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
    FoldersScreen(),
    ReelsScreen(),
    PlaylistsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(appTabProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: NavigationBar(
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
        ],
      ),
    );
  }
}
