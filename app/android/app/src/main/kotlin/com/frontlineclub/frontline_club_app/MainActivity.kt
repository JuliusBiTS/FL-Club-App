package com.frontlineclub.frontline_club_app

import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FLAG_SECURE + forced max brightness for ticket/membership QR screens
// (briefing §9.4/§9.6) — no Flutter plugin for either in the pubspec, so
// it's a small MethodChannel rather than pulling in a dependency for four
// calls. FLAG_SECURE blocks screenshots, screen recording and (on
// supported OEM skins) window mirroring to a second display while a code
// that could be photographed off a stolen or borrowed device is on
// screen. Max brightness is so the barcode/QR actually scans reliably
// under a dim bar or door light — screenBrightness=-1 (BRIGHTNESS_OVERRIDE_NONE)
// restores whatever the system/user setting was.
private const val SECURE_SCREEN_CHANNEL = "flc/secure_screen"

// audio_service (M8, briefing §9.8) requires the launch Activity to extend
// its own AudioServiceActivity rather than plain FlutterActivity — it binds
// the Activity's FlutterEngine to the background playback service that
// drives lock screen/notification controls. Without this, AudioService.init
// throws "wrong Activity class" at startup and podcast playback can't work.
class MainActivity : AudioServiceActivity() {
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
                    "setMaxBrightness" -> {
                        val params = window.attributes
                        params.screenBrightness = 1.0f
                        window.attributes = params
                        result.success(null)
                    }
                    "restoreBrightness" -> {
                        val params = window.attributes
                        params.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        window.attributes = params
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
