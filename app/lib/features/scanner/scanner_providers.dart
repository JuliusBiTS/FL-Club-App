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

/// How many tickets are sold for an event and how many are already in.
class CheckinCounts {
  const CheckinCounts({required this.sold, required this.checkedIn, required this.live});

  final int sold;
  final int checkedIn;

  /// True when it came from the server (counts every door); false when it was
  /// worked out from this phone's downloaded list because there's no signal.
  final bool live;
}

final checkinCountsProvider = FutureProvider.autoDispose.family<CheckinCounts, String>((ref, eventId) async {
  try {
    final dynamic r = await ref.watch(supabaseClientProvider).rpc('event_checkin_counts', params: <String, dynamic>{'p_event_id': eventId});
    final Map<String, dynamic> m = Map<String, dynamic>.from(r as Map);
    return CheckinCounts(sold: (m['sold'] as num).toInt(), checkedIn: (m['checked_in'] as num).toInt(), live: true);
  } catch (_) {
    final tickets = await ref.watch(appDatabaseProvider).scanPackTicketsFor(eventId);
    final int sold = tickets.where((t) => t.status == 'valid' || t.status == 'redeemed').length;
    final int inside = tickets.where((t) => t.status == 'redeemed').length;
    return CheckinCounts(sold: sold, checkedIn: inside, live: false);
  }
});
