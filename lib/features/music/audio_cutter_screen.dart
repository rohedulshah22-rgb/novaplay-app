import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/theme/app_theme.dart';
import 'audio_cutter_service.dart';
import 'music_audio_service.dart';

class AudioCutterScreen extends StatefulWidget {
  const AudioCutterScreen({required this.song, super.key});

  final SongModel song;

  @override
  State<AudioCutterScreen> createState() => _AudioCutterScreenState();
}

class _AudioCutterScreenState extends State<AudioCutterScreen> {
  final _previewPlayer = AudioPlayer();
  StreamSubscription<Duration>? _positionSubscription;
  Duration _duration = Duration.zero;
  Duration _start = Duration.zero;
  Duration _end = const Duration(seconds: 30);
  Duration _position = Duration.zero;
  bool _loading = true;
  bool _working = false;
  bool _previewing = false;
  AudioCutResult? _result;

  @override
  void initState() {
    super.initState();
    _preparePreview();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _preparePreview() async {
    try {
      final duration = await _previewPlayer.setFilePath(widget.song.data) ?? Duration.zero;
      if (!mounted) return;
      final defaultEnd = duration.inMilliseconds < const Duration(seconds: 30).inMilliseconds
          ? duration
          : const Duration(seconds: 30);
      setState(() {
        _duration = duration;
        _end = defaultEnd;
        _loading = false;
      });
      _positionSubscription = _previewPlayer.positionStream.listen((position) {
        if (!mounted) return;
        if (_previewing && position >= _end) {
          _previewPlayer.pause();
          _previewPlayer.seek(_start);
          setState(() => _previewing = false);
        }
        setState(() => _position = position);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      await _previewPlayer.pause();
      if (mounted) setState(() => _previewing = false);
      return;
    }
    await _previewPlayer.seek(_start);
    await _previewPlayer.play();
    if (mounted) setState(() => _previewing = true);
  }

  Future<void> _trim() async {
    if (_end <= _start || _duration == Duration.zero) return;
    setState(() {
      _working = true;
      _result = null;
    });
    try {
      final result = await audioCutterService.trim(
        inputPath: widget.song.data,
        start: _start,
        end: _end,
        outputName: '${musicTitle(widget.song)}_clip.mp3',
      );
      if (mounted) {
        setState(() => _result = result);
        _message('Trimmed clip is ready.');
      }
    } catch (error) {
      if (mounted) _message('Could not trim audio: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _runAction(String label, Future<void> Function(AudioCutResult) action) async {
    final result = _result;
    if (result == null) {
      await _trim();
      if (!mounted || _result == null) return;
    }
    try {
      await action(_result!);
      if (mounted) _message('$label completed.');
    } catch (error) {
      if (mounted) _message('$label failed: $error');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
    final startMs = _start.inMilliseconds.toDouble().clamp(0, maxMs).toDouble();
    final endMs = _end.inMilliseconds.toDouble().clamp(startMs, maxMs).toDouble();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Cutter', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Song details',
            onPressed: () => _showDetails(context),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                children: [
                  Row(
                    children: [
                      QueryArtworkWidget(
                        id: widget.song.id,
                        type: ArtworkType.AUDIO,
                        artworkWidth: 72,
                        artworkHeight: 72,
                        artworkFit: BoxFit.cover,
                        nullArtworkWidget: _Artwork(size: 72),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(musicTitle(widget.song), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text('${musicArtist(widget.song)} • ${musicAlbum(widget.song)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NovaColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Container(
                    height: 136,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: NovaColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: NovaColors.outline)),
                    child: CustomPaint(painter: _WaveformPainter(start: startMs / maxMs, end: endMs / maxMs)),
                  ),
                  const SizedBox(height: 10),
                  RangeSlider(
                    values: RangeValues(startMs, endMs),
                    min: 0,
                    max: maxMs,
                    divisions: _duration.inMilliseconds.clamp(1, 1000000),
                    labels: RangeLabels(_format(_start), _format(_end)),
                    onChanged: (values) => setState(() {
                      _start = Duration(milliseconds: values.start.round());
                      _end = Duration(milliseconds: values.end.round());
                      _result = null;
                    }),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _TimeLabel(label: 'START', value: _format(_start)),
                      _TimeLabel(label: 'LENGTH', value: _format(_end - _start)),
                      _TimeLabel(label: 'END', value: _format(_end)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _working ? null : _togglePreview,
                    icon: Icon(_previewing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    label: Text(_previewing ? 'Pause preview' : 'Preview selected segment'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _trim,
                    icon: _working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.content_cut_rounded),
                    label: Text(_working ? 'Trimming…' : 'Trim audio'),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 24),
                    const Text('Use this clip', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    const SizedBox(height: 8),
                    _ActionTile(icon: Icons.save_alt_rounded, title: 'Save to Music/NovaPlay', onTap: () => _runAction('Save', (result) async { await audioCutterService.saveToMusic(result, title: '${musicTitle(widget.song)}_clip'); })),
                    _ActionTile(icon: Icons.phone_android_rounded, title: 'Set as Phone Ringtone', onTap: () => _runAction('Ringtone', audioCutterService.setAsRingtone)),
                    _ActionTile(icon: Icons.notifications_active_outlined, title: 'Set as Notification Tone', onTap: () => _runAction('Notification tone', audioCutterService.setAsNotification)),
                    _ActionTile(icon: Icons.alarm_rounded, title: 'Set as Alarm Tone', onTap: () => _runAction('Alarm tone', audioCutterService.setAsAlarm)),
                    _ActionTile(icon: Icons.share_rounded, title: 'Share audio clip', onTap: () => _runAction('Share', (result) async { await audioCutterService.share(result, title: musicTitle(widget.song)); })),
                  ],
                ],
              ),
            ),
    );
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = value.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '${value.inHours > 0 ? '${value.inHours}:' : ''}$minutes:$seconds.$millis';
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Song Details'),
        content: Text('Title: ${musicTitle(widget.song)}\nArtist: ${musicArtist(widget.song)}\nAlbum: ${musicAlbum(widget.song)}\nDuration: ${formatMusicDuration(widget.song.duration)}\nPath: ${widget.song.data}'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: NovaColors.muted, fontSize: 10, fontWeight: FontWeight.w800)), Text(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))]);
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon, color: NovaColors.cyan), title: Text(title), onTap: onTap);
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: const LinearGradient(colors: [NovaColors.cyan, NovaColors.violet])), child: Icon(Icons.music_note_rounded, size: size * .42, color: NovaColors.black));
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.start, required this.end});
  final double start;
  final double end;
  @override
  void paint(Canvas canvas, Size size) {
    final bars = Paint()..strokeWidth = 3..strokeCap = StrokeCap.round;
    final selected = Paint()..color = NovaColors.cyan..strokeWidth = 3..strokeCap = StrokeCap.round;
    for (var index = 0; index < 64; index++) {
      final x = index / 63 * size.width;
      final height = size.height * (0.18 + ((index * 37) % 71) / 100);
      final isSelected = index / 63 >= start && index / 63 <= end;
      canvas.drawLine(Offset(x, (size.height - height) / 2), Offset(x, (size.height + height) / 2), isSelected ? selected : (bars..color = NovaColors.muted.withValues(alpha: .4)));
    }
    final marker = Paint()..color = NovaColors.violet..strokeWidth = 2;
    canvas.drawLine(Offset(size.width * start, 0), Offset(size.width * start, size.height), marker);
    canvas.drawLine(Offset(size.width * end, 0), Offset(size.width * end, size.height), marker);
  }
  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => oldDelegate.start != start || oldDelegate.end != end;
}
