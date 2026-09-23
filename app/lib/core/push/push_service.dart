import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../supabase/supabase_providers.dart';

enum PushEnableResult { enabled, denied, signedOut, unavailable, failed }

/// Push notifications (Firebase Cloud Messaging), end to end on the device:
/// ask permission at the point of need, register this phone's token with
/// Supabase, keep it fresh, and turn incoming messages into either a system
/// notification (app closed/backgrounded — FCM does that itself) or a small
/// in-app banner (app open).
///
/// Everything is optional. With no Firebase config in `--dart-define`
/// ([Env.pushConfigured] false) or if Firebase can't start, [isAvailable] is
/// false and every method is a harmless no-op, so the rest of the app never
/// has to care. Nothing here can send a notification — that only happens
/// server-side in the `send-push` Edge Function, by staff.
class PushService {
  PushService(this._client);

  final SupabaseClient _client;

  bool _ready = false;
  bool _attached = false;
  StreamSubscription<String>? _tokenRefresh;

  bool get isAvailable => _ready;

  /// Call once at startup, after Supabase is initialised.
  Future<void> init() async {
    if (kIsWeb || !Env.pushConfigured) return; // web preview: no push
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: Env.firebaseApiKey,
          appId: Env.firebaseAppId,
          messagingSenderId: Env.firebaseMessagingSenderId,
          projectId: Env.firebaseProjectId,
        ),
      );
      _ready = true;
    } catch (error) {
      debugPrint('Push notifications are off: Firebase could not start ($error)');
    }
  }

  /// Wires incoming messages to the UI. [onRoute] opens a screen when a
  /// notification is tapped; [onForeground] shows a banner when one arrives
  /// while the app is open (Android doesn't draw those itself).
  void attach({
    required void Function(String route) onRoute,
    required void Function(String title, String body, String? route) onForeground,
  }) {
    if (!_ready || _attached) return;
    _attached = true;

    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      final RemoteNotification? n = m.notification;
      if (n != null) onForeground(n.title ?? '', n.body ?? '', _routeOf(m));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
      final String? route = _routeOf(m);
      if (route != null) onRoute(route);
    });
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? m) {
      final String? route = m == null ? null : _routeOf(m);
      if (route != null) onRoute(route);
    });
  }

  /// Only in-app paths are ever followed — never an arbitrary URL from a payload.
  String? _routeOf(RemoteMessage m) {
    final Object? route = m.data['route'];
    return route is String && route.startsWith('/') ? route : null;
  }

  Future<PushEnableResult> enable() async {
    if (!_ready) return PushEnableResult.unavailable;
    final User? user = _client.auth.currentUser;
    if (user == null) return PushEnableResult.signedOut;

    try {
      final NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return PushEnableResult.denied;

      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return PushEnableResult.failed;

      await _register(token);
      await _client.from('profiles').update(<String, dynamic>{'push_opt_in': true}).eq('id', user.id);
      _tokenRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(_register);
      return PushEnableResult.enabled;
    } catch (error) {
      debugPrint('Could not enable push: $error');
      return PushEnableResult.failed;
    }
  }

  Future<void> disable() async {
    final User? user = _client.auth.currentUser;
    if (user != null) {
      await _client.from('profiles').update(<String, dynamic>{'push_opt_in': false}).eq('id', user.id);
    }
    await forgetThisDevice();
  }

  /// Removes this phone's token from the signed-in account. Call BEFORE
  /// signing out, so the next person to use the phone doesn't receive the
  /// previous person's notifications.
  Future<void> forgetThisDevice() async {
    if (!_ready) return;
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null && _client.auth.currentUser != null) {
        await _client.rpc('unregister_device_token', params: <String, dynamic>{'p_token': token});
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('Could not forget this device: $error');
    }
  }

  /// After sign-in: if this account already opted in, attach this phone to it
  /// (covers signing in as a different person on the same device).
  Future<void> syncOnSignIn() async {
    if (!_ready) return;
    final User? user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final Map<String, dynamic>? row = await _client.from('profiles').select('push_opt_in').eq('id', user.id).maybeSingle();
      if (row?['push_opt_in'] != true) return;
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _register(token);
      _tokenRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(_register);
    } catch (error) {
      debugPrint('Could not sync push token: $error');
    }
  }

  Future<void> _register(String token) async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    await _client.rpc('register_device_token', params: <String, dynamic>{
      'p_token': token,
      'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'p_app_version': info.version,
    });
  }
}

/// Overridden in main.dart with the initialised instance; this default keeps
/// tests and previews working (push simply isn't available).
final Provider<PushService> pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(supabaseClientProvider));
});
