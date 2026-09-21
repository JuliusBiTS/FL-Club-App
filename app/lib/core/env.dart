/// Compile-time configuration, passed via `--dart-define` at build/run
/// time — never hard-coded, never in source control. These are the ONLY
/// secrets the client ever holds (briefing §7.3): the Supabase anon
/// key (meaningless without RLS, which is the real gate), Stripe's
/// *publishable* key (safe to ship by design), and the Firebase client
/// identifiers (public by design — they only say *which* Firebase project
/// to talk to; sending is done server-side with a service account).
///
/// Simplest is a local, git-ignored JSON file:
///   flutter run --dart-define-from-file=dart_defines.json
/// (see dart_defines.example.json). The equivalent one-liner:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  // Firebase Cloud Messaging (push notifications). All four come from the
  // Firebase console → Project settings → Your apps → Android app. Left empty
  // = push notifications are simply off in this build. See docs/PUSH_SETUP.md.
  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get pushConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  static void assertConfigured() {
    assert(
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty,
      'SUPABASE_URL / SUPABASE_ANON_KEY were not passed via --dart-define. '
      'See app/README or the root README "Getting started".',
    );
  }
}
