import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
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

  // Sets up the lock screen/notification media session for podcast
  // playback (briefing §9.8) — must happen before the widget tree exists,
  // since PodcastScreen expects podcastAudioHandlerProvider already
  // overridden with a live handler the moment it first builds.
  final PodcastAudioHandler audioHandler = await AudioService.init(
    builder: PodcastAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.frontlineclub.frontline_club_app.audio',
      androidNotificationChannelName: 'Podcast playback',
      androidNotificationOngoing: true,
    ),
  );

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
        overrides: [podcastAudioHandlerProvider.overrideWithValue(audioHandler)],
        child: const FrontlineClubApp(),
      ),
    ),
  );
}
