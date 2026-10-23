import 'dart:async';

import 'package:flutter/services.dart';

class ToolNotificationService {
  const ToolNotificationService._();

  static const _channel = MethodChannel('com.novaplay/media');

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<bool>('showToolNotification', {
        'title': title,
        'body': body,
      }).timeout(const Duration(seconds: 2));
    } on PlatformException {
      // Notifications are best-effort and must not turn a successful media
      // operation into a failure.
    } on MissingPluginException {
      // The native handler may be unavailable on non-Android platforms.
    } on TimeoutException {
      // Keep the media operation's completion independent of notification UI.
    }
  }
}
