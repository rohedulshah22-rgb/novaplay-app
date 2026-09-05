import 'dart:io';

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import '../media/data/media_preferences.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

class NovaAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  NovaAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed && _sleepAtTrackEnd) {
        _sleepAtTrackEnd = false;
        await _player.setVolume(.15);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _player.pause();
        await _player.setVolume(1);
      }
    });
    _player.sequenceStateStream.listen((sequence) {
      final item = sequence.currentSource?.tag;
      if (item is MediaItem) mediaItem.add(item);
    });
    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index >= 0 && index < items.length) {
        mediaItem.add(items[index]);
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final MethodChannel _effectsChannel = const MethodChannel('com.novaplay/player');
  Timer? _sleepTimer;
  bool _sleepAtTrackEnd = false;
  List<double> _equalizerBands = List<double>.filled(5, 0);
  bool _bassBoost = false;
  AudioPlayer get player => _player;

  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Future<void> loadSongs(List<SongModel> songs, {int initialIndex = 0}) async {
    final items = songs.map(_toMediaItem).toList(growable: false);
    final sources = songs
        .map(
          (song) =>
              AudioSource.uri(Uri.file(song.data), tag: _toMediaItem(song)),
        )
        .toList(growable: false);
    await _player.setAudioSources(
      sources,
      initialIndex: initialIndex
          .clamp(0, sources.isEmpty ? 0 : sources.length - 1)
          .toInt(),
    );
    queue.add(items);
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex.clamp(0, items.length - 1).toInt()]);
    }
    final sessionId = await _player.androidAudioSessionIdStream.first;
    if (sessionId != null) await _applyEffects(sessionId);
  }

  MediaItem _toMediaItem(SongModel song) => MediaItem(
    id: song.data,
    title: song.title.trim().isEmpty ? song.displayName : song.title,
    artist: song.artist == '<unknown>' ? null : song.artist,
    album: song.album == '<unknown>' ? null : song.album,
    duration: Duration(milliseconds: song.duration ?? 0),
    extras: <String, dynamic>{
      'songId': song.id,
      'albumId': song.albumId,
      'artistId': song.artistId,
      'folder': _folderOf(song.data),
    },
  );

  String _folderOf(String path) {
    final separator = path.lastIndexOf('/');
    return separator <= 0
        ? 'Music'
        : path.substring(0, separator).split('/').last;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final mode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      _ => LoopMode.off,
    };
    await _player.setLoopMode(mode);
    await super.setRepeatMode(repeatMode);
  }

  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
      shuffleMode == AudioServiceShuffleMode.all,
    );
    await super.setShuffleMode(shuffleMode);
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: event.updatePosition,
        bufferedPosition: event.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  Future<void> setEqualizerBands(List<double> bands) async {
    _equalizerBands = bands;
    await mediaPreferences.setEqualizerBands(bands);
    final sessionId = await _player.androidAudioSessionIdStream.first;
    if (sessionId != null) await _applyEffects(sessionId);
  }

  Future<void> setBassBoost(bool enabled) async {
    _bassBoost = enabled;
    await mediaPreferences.setBassBoost(enabled);
    final sessionId = await _player.androidAudioSessionIdStream.first;
    if (sessionId != null) await _applyEffects(sessionId);
  }

  Future<void> _applyEffects(int sessionId) async {
    await _effectsChannel.invokeMethod<void>('setAudioEffects', {
      'sessionId': sessionId,
      'bands': _equalizerBands,
      'bassBoost': _bassBoost,
    });
  }

  Future<void> setSleepTimer(Duration? duration, {bool untilTrackEnd = false}) async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAtTrackEnd = untilTrackEnd;
    if (duration == null && !untilTrackEnd) {
      await _player.setVolume(1);
      return;
    }
    if (untilTrackEnd) {
      await _player.setVolume(1);
      return;
    }
    final fade = duration! > const Duration(seconds: 20)
        ? const Duration(seconds: 20)
        : duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final remaining = duration - Duration(seconds: timer.tick);
      if (remaining <= Duration.zero) {
        timer.cancel();
        await _player.pause();
        await _player.setVolume(1);
        return;
      }
      if (remaining <= fade) {
        await _player.setVolume(remaining.inMilliseconds / fade.inMilliseconds);
      }
    });
  }

  Future<void> dispose() {
    _sleepTimer?.cancel();
    return _player.dispose();
  }
}

NovaAudioHandler? audioHandler;
final audioServiceReady = ValueNotifier<bool>(false);
NovaAudioHandler get currentAudioHandler => audioHandler ??= NovaAudioHandler();

Future<void> initNovaAudioService() async {
  final handler = await AudioService.init(
    builder: () => NovaAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.novaplay.novaplay.audio',
      androidNotificationChannelName: 'NovaPlay Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
  audioHandler = handler;
  await currentAudioHandler.configureSession();
  currentAudioHandler._equalizerBands = await mediaPreferences.equalizerBands();
  currentAudioHandler._bassBoost = await mediaPreferences.bassBoost();
  if (Platform.isAndroid) {
    await Permission.notification.request();
  }
  audioServiceReady.value = true;
}

final musicQuery = OnAudioQuery();
String musicTitle(SongModel song) =>
    song.title.trim().isEmpty ? song.displayName : song.title;
String musicArtist(SongModel song) {
  final artist = song.artist;
  return artist == null || artist == '<unknown>' || artist.trim().isEmpty
      ? 'Unknown artist'
      : artist;
}

String musicAlbum(SongModel song) {
  final album = song.album;
  return album == null || album == '<unknown>' || album.trim().isEmpty
      ? 'Unknown album'
      : album;
}

String musicFolder(SongModel song) {
  final path = song.data;
  final separator = path.lastIndexOf('/');
  return separator <= 0
      ? 'Music'
      : path.substring(0, separator).split('/').last;
}

String formatMusicDuration(int? milliseconds) {
  final duration = Duration(milliseconds: milliseconds ?? 0);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
