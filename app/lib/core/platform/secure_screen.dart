import 'dart:io';

import 'package:flutter/services.dart';

/// Wraps the FLAG_SECURE MethodChannel set up in MainActivity.kt. No-op on
/// platforms other than Android (iOS has no screenshot-blocking API — see
/// briefing §9.4's note that this is Android-first).
class SecureScreen {
  static const _channel = MethodChannel('flc/secure_screen');

  static Future<void> enable() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('enable');
  }

  static Future<void> disable() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('disable');
  }
}
