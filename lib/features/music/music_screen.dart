import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nova_widgets.dart';
import 'music_audio_service.dart';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen>
    with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  late final TabController _tabs;
  List<SongModel> songs = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final allowed = await musicQuery.checkAndRequest();
      if (!allowed) {
        setState(() {
          loading = false;
          error = 'Allow audio access to build your Music library.';
        });
        return;
      }
      final result = await musicQuery.querySongs();
      if (!mounted) return;
      setState(() {
        songs = result;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not scan local audio files.';
      });
    }
  }

  List<SongModel> get visibleSongs {
    final query = _search.text.trim().toLowerCase();
    return songs
        .where((song) {
          if (query.isEmpty) return true;
          return musicTitle(song).toLowerCase().contains(query) ||
              musicArtist(song).toLowerCase().contains(query) ||
              musicAlbum(song).toLowerCase().contains(query) ||
              musicFolder(song).toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _play(SongModel song) async {
    final list = visibleSongs;
    final index = list.indexWhere((item) => item.id == song.id);
    await audioHandler.loadSongs(list, initialIndex: index < 0 ? 0 : index);
    await audioHandler.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Music',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear_rounded),
                          ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'All Songs'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Folders'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? _MusicEmpty(message: error!, onRetry: _refresh)
          : TabBarView(
              controller: _tabs,
              children: [
                _SongList(songs: visibleSongs, onTap: _play),
                _GroupedSongs(
                  songs: visibleSongs,
                  groupBy: musicAlbum,
                  onTap: _play,
                ),
                _GroupedSongs(
                  songs: visibleSongs,
                  groupBy: musicArtist,
                  onTap: _play,
                ),
                _GroupedSongs(
                  songs: visibleSongs,
                  groupBy: musicFolder,
                  onTap: _play,
                ),
              ],
            ),
    );
  }
}

class _SongList extends StatelessWidget {
  const _SongList({required this.songs, required this.onTap});
  final List<SongModel> songs;
  final Future<void> Function(SongModel) onTap;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const _MusicEmpty(message: 'No local songs found.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) => _SongTile(song: songs[index], onTap: onTap),
    );
  }
}

class _GroupedSongs extends StatelessWidget {
  const _GroupedSongs({
    required this.songs,
    required this.groupBy,
    required this.onTap,
  });
  final List<SongModel> songs;
  final String Function(SongModel) groupBy;
  final Future<void> Function(SongModel) onTap;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SongModel>>{};
    for (final song in songs) {
      groups.putIfAbsent(groupBy(song), () => []).add(song);
    }
    if (groups.isEmpty) {
      return const _MusicEmpty(message: 'Nothing to show yet.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      children: groups.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${entry.value.length} song${entry.value.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: NovaColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    ...entry.value
                        .take(8)
                        .map(
                          (song) => _SongTile(
                            song: song,
                            onTap: onTap,
                            compact: true,
                          ),
                        ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.onTap,
    this.compact = false,
  });
  final SongModel song;
  final Future<void> Function(SongModel) onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 0 : 8,
        vertical: compact ? 0 : 2,
      ),
      leading: QueryArtworkWidget(
        id: song.id,
        type: ArtworkType.AUDIO,
        artworkWidth: compact ? 42 : 52,
        artworkHeight: compact ? 42 : 52,
        artworkFit: BoxFit.cover,
        nullArtworkWidget: _Artwork(size: compact ? 42 : 52),
      ),
      title: Text(
        musicTitle(song),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${musicArtist(song)}  •  ${musicAlbum(song)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatMusicDuration(song.duration),
        style: const TextStyle(color: NovaColors.muted, fontSize: 11),
      ),
      onTap: () => onTap(song),
    );
  }
}

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();
        return Material(
          color: NovaColors.surface,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MusicPlayerScreen()),
            ),
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  _Artwork(size: 44, mediaItem: item),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          item.artist ?? 'Unknown artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NovaColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: audioHandler.player.playingStream,
                    initialData: audioHandler.player.playing,
                    builder: (_, playing) => IconButton(
                      onPressed: () => playing.data == true
                          ? audioHandler.pause()
                          : audioHandler.play(),
                      icon: Icon(
                        playing.data == true
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: NovaColors.cyan,
                        size: 34,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: audioHandler.skipToNext,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MusicPlayerScreen extends StatelessWidget {
  const MusicPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Now Playing',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: StreamBuilder<MediaItem?>(
        stream: audioHandler.mediaItem,
        builder: (context, snapshot) {
          final item = snapshot.data;
          if (item == null) {
            return const _MusicEmpty(
              message: 'Choose a song to start listening.',
            );
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                children: [
                  Expanded(
                    child: Center(child: _Artwork(size: 280, mediaItem: item)),
                  ),
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${item.artist ?? 'Unknown artist'}  •  ${item.album ?? 'Unknown album'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: NovaColors.muted),
                  ),
                  const SizedBox(height: 24),
                  StreamBuilder<Duration>(
                    stream: audioHandler.player.positionStream,
                    builder: (_, position) => StreamBuilder<Duration?>(
                      stream: audioHandler.player.durationStream,
                      builder: (_, duration) {
                        final max =
                            duration.data?.inMilliseconds.toDouble() ?? 1;
                        final value =
                            (position.data?.inMilliseconds.toDouble() ?? 0)
                                .clamp(0, max)
                                .toDouble();
                        return Column(
                          children: [
                            Slider(
                              value: value,
                              max: max == 0 ? 1 : max,
                              onChanged: (value) => audioHandler.seek(
                                Duration(milliseconds: value.round()),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatMusicDuration(
                                    position.data?.inMilliseconds,
                                  ),
                                  style: const TextStyle(
                                    color: NovaColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  formatMusicDuration(
                                    duration.data?.inMilliseconds,
                                  ),
                                  style: const TextStyle(
                                    color: NovaColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      StreamBuilder<bool>(
                        stream: audioHandler.player.shuffleModeEnabledStream,
                        initialData: false,
                        builder: (_, value) => IconButton(
                          onPressed: () => audioHandler.setShuffleMode(
                            value.data == true
                                ? AudioServiceShuffleMode.all
                                : AudioServiceShuffleMode.none,
                          ),
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: value.data == true
                                ? NovaColors.cyan
                                : NovaColors.muted,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: audioHandler.skipToPrevious,
                        icon: const Icon(Icons.skip_previous_rounded, size: 38),
                      ),
                      StreamBuilder<bool>(
                        stream: audioHandler.player.playingStream,
                        initialData: audioHandler.player.playing,
                        builder: (_, playing) => IconButton(
                          onPressed: () => playing.data == true
                              ? audioHandler.pause()
                              : audioHandler.play(),
                          icon: Icon(
                            playing.data == true
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            color: NovaColors.cyan,
                            size: 68,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: audioHandler.skipToNext,
                        icon: const Icon(Icons.skip_next_rounded, size: 38),
                      ),
                      StreamBuilder<LoopMode>(
                        stream: audioHandler.player.loopModeStream,
                        initialData: LoopMode.off,
                        builder: (_, mode) => IconButton(
                          onPressed: () => audioHandler.setLoopMode(
                            mode.data == LoopMode.off
                                ? LoopMode.all
                                : mode.data == LoopMode.all
                                ? LoopMode.one
                                : LoopMode.off,
                          ),
                          icon: Icon(
                            Icons.repeat_rounded,
                            color: mode.data == LoopMode.off
                                ? NovaColors.muted
                                : NovaColors.cyan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({this.size = 48, this.mediaItem});
  final double size;
  final MediaItem? mediaItem;

  @override
  Widget build(BuildContext context) {
    final id = mediaItem?.extras?['songId'];
    if (id is int) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size > 100 ? 24 : 12),
        child: QueryArtworkWidget(
          id: id,
          type: ArtworkType.AUDIO,
          artworkWidth: size,
          artworkHeight: size,
          artworkFit: BoxFit.cover,
          nullArtworkWidget: _ArtworkPlaceholder(size: size),
        ),
      );
    }
    return _ArtworkPlaceholder(size: size);
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size > 100 ? 24 : 12),
      gradient: const LinearGradient(
        colors: [NovaColors.cyan, NovaColors.violet],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Icon(
      Icons.music_note_rounded,
      size: size * .42,
      color: NovaColors.black,
    ),
  );
}

class _MusicEmpty extends StatelessWidget {
  const _MusicEmpty({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.library_music_outlined,
            size: 56,
            color: NovaColors.cyan,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: NovaColors.muted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
