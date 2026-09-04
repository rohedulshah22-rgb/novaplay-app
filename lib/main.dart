import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'features/ads/admob_service.dart';
import 'features/music/music_audio_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NovaPlayApp()));

  // media_kit performs synchronous native setup. Defer it until Flutter has
  // painted the shell so the dashboard is available instead of holding the
  // launch screen during codec/asset initialization.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    MediaKit.ensureInitialized();
    unawaited(_initializeServices());
  });
}

Future<void> _initializeServices() async {
  await Future.wait<void>([
    initNovaAudioService(),
    NovaAdMob.instance.initialize(),
  ]);
}
