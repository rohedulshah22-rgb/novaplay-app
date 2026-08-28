import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'features/ads/admob_service.dart';
import 'features/music/music_audio_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initNovaAudioService();
  await NovaAdMob.instance.initialize();
  runApp(const ProviderScope(child: NovaPlayApp()));
}
