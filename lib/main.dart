import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'features/ads/admob_service.dart';
import 'features/music/music_audio_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: NovaPlayApp()));
  unawaited(_initializeServices());
}

Future<void> _initializeServices() async {
  await Future.wait<void>([
    initNovaAudioService(),
    NovaAdMob.instance.initialize(),
  ]);
}
