import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';

/// The signed-in user's own profile — null for guests. Drives the bottom
/// nav's Scan tab visibility, the membership card handle vs. "Become a
/// member" handle, and member-price surfacing on event cards (briefing
/// §9.0/§9.1/§9.6). This is a UX convenience only: every privileged
/// decision is re-checked server-side regardless (§7.3).
final FutureProvider<ProfileModel?> currentProfileProvider = FutureProvider<ProfileModel?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final client = ref.watch(supabaseClientProvider);
  final row = await client.from('profiles').select().eq('id', user.id).maybeSingle();
  if (row == null) return null;
  return ProfileModel.fromJson(row);
});
