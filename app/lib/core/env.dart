/// Compile-time configuration, passed via `--dart-define` at build/run
/// time — never hard-coded, never in source control. These are the ONLY
/// two secrets the client ever holds (briefing §7.3): the Supabase anon
/// key (meaningless without RLS, which is the real gate) and Stripe's
/// *publishable* key (safe to ship by design).
///
/// Example:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  static void assertConfigured() {
    assert(
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty,
      'SUPABASE_URL / SUPABASE_ANON_KEY were not passed via --dart-define. '
      'See app/README or the root README "Getting started".',
    );
  }
}
