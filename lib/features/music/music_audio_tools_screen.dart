import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../media/data/media_preferences.dart';
import 'music_audio_service.dart';

class MusicAudioToolsScreen extends StatefulWidget {
  const MusicAudioToolsScreen({super.key, required this.mediaItem});
  final MediaItem mediaItem;

  @override
  State<MusicAudioToolsScreen> createState() => _MusicAudioToolsScreenState();
}

class _MusicAudioToolsScreenState extends State<MusicAudioToolsScreen> {
  final labels = const ['60 Hz', '250 Hz', '1 kHz', '4 kHz', '12 kHz'];
  List<double> bands = List<double>.filled(5, 0);
  bool bassBoost = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await mediaPreferences.equalizerBands();
    final boost = await mediaPreferences.bassBoost();
    if (!mounted) return;
    setState(() {
      bands = values.length == 5 ? values : List<double>.filled(5, 0);
      bassBoost = boost;
    });
  }

  Future<void> _preset(String name) async {
    final values = switch (name) {
      'Bass Boost' => [8.0, 6.0, 2.0, -2.0, -3.0],
      'Pop' => [2.0, -1.0, 3.0, 5.0, 3.0],
      'Rock' => [5.0, 2.0, -1.0, 3.0, 5.0],
      'Classical' => [4.0, 2.0, -1.0, 2.0, 4.0],
      'Vocal' => [-2.0, -1.0, 4.0, 6.0, 3.0],
      _ => List<double>.filled(5, 0),
    };
    setState(() => bands = values);
    await currentAudioHandler.setEqualizerBands(values);
    if (name == 'Bass Boost' && !bassBoost) {
      setState(() => bassBoost = true);
      await currentAudioHandler.setBassBoost(true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audio tools')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          widget.mediaItem.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(widget.mediaItem.artist ?? 'Unknown artist', style: const TextStyle(color: NovaColors.muted)),
        const SizedBox(height: 20),
        const Text('Presets', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Flat', 'Bass Boost', 'Pop', 'Rock', 'Classical', 'Vocal']
              .map((name) => ActionChip(label: Text(name), onPressed: () => _preset(name)))
              .toList(),
        ),
        const SizedBox(height: 22),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bass boost'),
          subtitle: const Text('Enhance low frequencies for headphones and speakers'),
          value: bassBoost,
          onChanged: (value) async {
            setState(() => bassBoost = value);
            await currentAudioHandler.setBassBoost(value);
          },
        ),
        const SizedBox(height: 8),
        const Text('5-band equalizer', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ...List.generate(
          bands.length,
          (index) => Row(
            children: [
              SizedBox(width: 54, child: Text(labels[index], style: const TextStyle(fontSize: 11))),
              Expanded(
                child: Slider(
                  min: -12,
                  max: 12,
                  value: bands[index],
                  label: '${bands[index].round()} dB',
                  onChanged: (value) => setState(() => bands[index] = value),
                  onChangeEnd: (_) => currentAudioHandler.setEqualizerBands(bands),
                ),
              ),
              SizedBox(width: 42, child: Text('${bands[index].round()} dB', textAlign: TextAlign.end)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => showSleepTimerSheet(context),
          icon: const Icon(Icons.bedtime_outlined),
          label: const Text('Sleep timer'),
        ),
      ],
    ),
  );
}

Future<void> showSleepTimerSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text('Sleep timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...<MapEntry<String, Duration?>>[
            const MapEntry('Off', null),
            MapEntry('15 minutes', const Duration(minutes: 15)),
            MapEntry('30 minutes', const Duration(minutes: 30)),
            MapEntry('45 minutes', const Duration(minutes: 45)),
            MapEntry('60 minutes', const Duration(minutes: 60)),
          ].map(
            (entry) => ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(entry.key),
              onTap: () async {
                await currentAudioHandler.setSleepTimer(entry.value);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('End of current track'),
            subtitle: const Text('Fade out and pause when this track finishes'),
            onTap: () async {
              await currentAudioHandler.setSleepTimer(null, untilTrackEnd: true);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
        ],
      ),
    ),
  );
}

class SyncedLyricsPanel extends StatefulWidget {
  const SyncedLyricsPanel({super.key, required this.mediaItem});
  final MediaItem mediaItem;

  @override
  State<SyncedLyricsPanel> createState() => _SyncedLyricsPanelState();
}

class _SyncedLyricsPanelState extends State<SyncedLyricsPanel> {
  List<LyricLine> lines = const [];
  String? plainLyrics;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    final file = File(lrcPathFor(widget.mediaItem.id));
    if (await file.exists()) {
      final content = await file.readAsString();
      if (!mounted) return;
      setState(() => lines = parseLrc(content));
      return;
    }
    final embedded = findEmbeddedLyrics(widget.mediaItem.extras?['lyrics'] as String?);
    if (!mounted) return;
    setState(() => plainLyrics = embedded);
  }

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty && plainLyrics == null) {
      return const Text('No local lyrics found. Add an .lrc file next to the audio file.', style: TextStyle(color: NovaColors.muted));
    }
    if (lines.isEmpty) {
      return Text(plainLyrics!, style: const TextStyle(height: 1.6));
    }
    return StreamBuilder<Duration>(
      stream: currentAudioHandler.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        var active = 0;
        for (var index = 0; index < lines.length; index++) {
          if (lines[index].at <= position) active = index;
        }
        return SizedBox(
          height: 150,
          child: ListView.builder(
            itemCount: lines.length,
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                lines[index].text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: index == active ? NovaColors.cyan : NovaColors.muted,
                  fontWeight: index == active ? FontWeight.w900 : FontWeight.w500,
                  fontSize: index == active ? 17 : 14,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
