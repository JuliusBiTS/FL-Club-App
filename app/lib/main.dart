import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';

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

  // Sentry: sendDefaultPii disabled per briefing §15 — crash reports are
  // identified by an opaque user id only, never name/email/content.
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN'); // empty in dev — Sentry no-ops without a DSN
      options.sendDefaultPii = false;
      options.tracesSampleRate = 0.2;
    },
    appRunner: () => runApp(const ProviderScope(child: FrontlineClubApp())),
  );
}
