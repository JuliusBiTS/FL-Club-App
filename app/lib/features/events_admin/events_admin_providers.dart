import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';

/// The staff event editor's data access (shared with the admin console via
/// flc_core). What staff may actually do is decided by Postgres, not here.
final Provider<EventAdminRepository> eventAdminRepositoryProvider = Provider<EventAdminRepository>((ref) {
  return EventAdminRepository(ref.watch(supabaseClientProvider));
});
