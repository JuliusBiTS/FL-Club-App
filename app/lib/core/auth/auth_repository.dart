import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';

/// Wraps Supabase auth so screens never call `Supabase.instance.client.auth`
/// directly — briefing §7.3's "no Supabase calls inside widgets" rule
/// applies to auth the same as everything else.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// The extra details ride along as sign-up metadata and are copied into
  /// the person's profile by the database (handle_new_auth_user), so they're
  /// saved even when email confirmation means there's no session yet.
  /// Consent timestamps are stamped by the database, never sent from here.
  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
    String? fullName,
    bool acceptedTerms = false,
    bool marketingOptIn = false,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: <String, dynamic>{
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
        'accepted_terms': acceptedTerms,
        'marketing_opt_in': marketingOptIn,
        'registration_source': 'app',
      },
    );
  }

  Future<AuthResponse> signInWithPassword({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Requires a Google OAuth client configured in the Supabase dashboard
  /// (Authentication > Providers > Google) and, for Android, the SHA-1
  /// fingerprint registered with Google Cloud Console — neither of which
  /// exists yet in this scaffold. See docs/OPEN_QUESTIONS.md.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() => _client.auth.signOut();

  bool get isSignedIn => _client.auth.currentUser != null;
}

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
