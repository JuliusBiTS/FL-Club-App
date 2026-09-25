import 'package:flc_core/flc_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/local_db/app_database_provider.dart';
import '../../core/platform/device_id.dart';
import '../../core/supabase/supabase_providers.dart';
import 'data/door_scan_repository.dart';
import 'data/event_scan_key_store.dart';
import 'data/membership_scan_repository.dart';
import 'data/scan_pack_repository.dart';

final Provider<EventScanKeyStore> eventScanKeyStoreProvider = Provider<EventScanKeyStore>((ref) {
  return EventScanKeyStore(const FlutterSecureStorage());
});

final Provider<DeviceId> deviceIdProvider = Provider<DeviceId>((ref) {
  return DeviceId(const FlutterSecureStorage());
});

final Provider<ScanPackRepository> scanPackRepositoryProvider = Provider<ScanPackRepository>((ref) {
  return ScanPackRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(eventScanKeyStoreProvider),
  );
});

final Provider<DoorScanRepository> doorScanRepositoryProvider = Provider<DoorScanRepository>((ref) {
  return DoorScanRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(eventScanKeyStoreProvider),
  );
});

final Provider<MembershipScanRepository> membershipScanRepositoryProvider = Provider<MembershipScanRepository>((ref) {
  return MembershipScanRepository(ref.watch(supabaseClientProvider));
});

/// Events staff can scan for: everything published from two days ago onwards.
/// The public feed hides an event the moment it starts, which is exactly when
/// the door is busiest — so the scanner has its own list. Any future event is
/// included too (tickets can be scanned whenever).
final scannerEventsProvider = FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final since = DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String();
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('events')
      .select()
      .eq('status', 'published')
      .gte('starts_at', since)
      .order('starts_at')
      .limit(120);
  return rows.map(EventModel.fromJson).toList();
});
