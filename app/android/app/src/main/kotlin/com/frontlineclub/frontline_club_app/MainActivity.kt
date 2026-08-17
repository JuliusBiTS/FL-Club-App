package com.frontlineclub.frontline_club_app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FLAG_SECURE for ticket/membership QR screens (briefing §9.4/§9.6) — no
// Flutter plugin for this in the pubspec, so it's a small MethodChannel
// rather than pulling in a dependency for two calls. Blocks screenshots,
// screen recording and (on supported OEM skins) window mirroring to a
// second display while a code that could be photographed off a stolen or
// borrowed device is on screen.
private const val SECURE_SCREEN_CHANNEL = "flc/secure_screen"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
