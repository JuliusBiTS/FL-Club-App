import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey, // the ONLY Supabase credential the client ever holds — briefing §7.3
  );

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
