import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/preferences/membership_card_preferences.dart';
import 'core/preferences/theme_mode_preferences.dart';
import 'core/push/push_service.dart';
import 'features/podcast/audio/podcast_audio_handler.dart';
import 'features/podcast/podcast_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey, // the ONLY Supabase credential the client ever holds — briefing §7.3
  );

  // Guarded: the club hasn't connected a Stripe account to this build yet
  // (see docs/STRIPE_SETUP.md). PaymentStep checks the same flag and shows
  // a clear message instead of reaching checkout with no working payment
  // sheet — this guard just stops Stripe's SDK rejecting an empty key at
  // startup before that screen ever runs.
  if (Env.stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = Env.stripePublishableKey;
    await Stripe.instance.applySettings();
  }

  // Push notifications (docs/PUSH_SETUP.md). Optional: with no Firebase config
  // in --dart-define this is a no-op and the app runs exactly as before.
  final PushService pushService = PushService(Supabase.instance.client);
  await pushService.init();

  // Sets up the lock screen/notification media session for podcast
  // playback (briefing §9.8) — must happen before the widget tree exists,
  // since ListenScreen expects podcastAudioHandlerProvider already
  // overridden with a live handler the moment it first builds.
  final PodcastAudioHandler audioHandler = await AudioService.init(
    builder: PodcastAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.frontlineclub.frontline_club_app.audio',
      androidNotificationChannelName: 'Podcast playback',
      androidNotificationOngoing: true,
    ),
  );

  // Backs the "always show as a dot" membership-card preference — a plain
  // non-sensitive UI toggle, so shared_preferences rather than secure
  // storage (which is reserved for tokens/credentials).
  final SharedPreferences sharedPreferences = await SharedPreferences.getInstance();
  final MembershipCardPreferences membershipCardPreferences = MembershipCardPreferences(sharedPreferences);
  final ThemeModePreferences themeModePreferences = ThemeModePreferences(sharedPreferences);

  // Sentry: sendDefaultPii disabled per briefing §15 — crash reports are
  // identified by an opaque user id only, never name/email/content.
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN'); // empty in dev — Sentry no-ops without a DSN
      options.sendDefaultPii = false;
      options.tracesSampleRate = 0.2;
    },
    appRunner: () => runApp(
      ProviderScope(
        overrides: [
          podcastAudioHandlerProvider.overrideWithValue(audioHandler),
          pushServiceProvider.overrideWithValue(pushService),
          membershipCardPreferencesProvider.overrideWithValue(membershipCardPreferences),
          themeModePreferencesProvider.overrideWithValue(themeModePreferences),
        ],
        child: const FrontlineClubApp(),
      ),
    ),
  );
}
