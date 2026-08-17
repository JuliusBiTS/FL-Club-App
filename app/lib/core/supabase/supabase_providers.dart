import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The single Supabase client for the whole app. Repositories depend on
/// this — never on `Supabase.instance.client` directly — so tests can
/// override it with a fake. See briefing §7.3: "No Supabase calls inside
/// widgets, ever."
final Provider<SupabaseClient> supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Streams the current auth state so the router (redirect logic) and any
/// widget can react to sign-in/out without polling.
final StreamProvider<AuthState> authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

final Provider<User?> currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user ?? ref.watch(supabaseClientProvider).auth.currentUser;
});
