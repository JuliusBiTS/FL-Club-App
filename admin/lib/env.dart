/// Same pattern as app/lib/core/env.dart — passed via --dart-define, never
/// hard-coded. The admin console additionally needs an admin-scoped
/// session (checked via profiles.role = 'admin' through RLS after
/// sign-in), not a different key.
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
