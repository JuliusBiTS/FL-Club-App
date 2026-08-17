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

  /// Forces screen brightness to max regardless of the system/user
  /// setting — briefing §9.6, so a barcode or QR held up to a scanner
  /// actually reads under dim bar/door lighting. Always pair with
  /// [restoreBrightness] on the same screen's dispose, same as [enable]
  /// pairs with [disable].
  static Future<void> setMaxBrightness() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('setMaxBrightness');
  }

  static Future<void> restoreBrightness() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('restoreBrightness');
  }
}
