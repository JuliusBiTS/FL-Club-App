import 'dart:convert';

import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/local_db/app_database.dart';
import 'event_scan_key_store.dart';

/// Friendly text for whatever get-scan-pack/verify-scan's errorResponse
/// sent back ({ error, details }) — falls back to the raw exception for
/// anything that isn't a clean server-side rejection (network failure,
/// timeout, ...).
String scanFunctionErrorMessage(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) return details['error'] as String;
  }
  return 'Something went wrong. Please try again.';
}

/// Downloads and caches an offline scan pack (briefing §13.5) — one
/// network call per event, good until `expires_at` (event end + 6h),
/// after which every scan for that event has to go through verify-scan
/// online instead of local verification.
class ScanPackRepository {
  ScanPackRepository(this._client, this._db, this._eventScanKeyStore);

  final SupabaseClient _client;
  final AppDatabase _db;
  final EventScanKeyStore _eventScanKeyStore;

  Future<ScanPackModel> download(String eventId) async {
    final response = await _client.functions.invoke('get-scan-pack', body: {'event_id': eventId});
    final data = response.data as Map<String, dynamic>;
    final pack = ScanPackModel.fromApiJson(data);

    await _eventScanKeyStore.put(eventId, data['event_scan_key'] as String);
    await _db.saveScanPack(
      eventId,
      pack.expiresAt,
      [for (final t in pack.tickets) (t.ticketId, t.status, _encodeTicket(t))],
    );
    return pack;
  }

  Future<bool> hasPackFor(String eventId) async {
    final pack = await _db.scanPackFor(eventId);
    if (pack == null) return false;
    return pack.expiresAt.isAfter(DateTime.now());
  }

  Future<CachedScanPack?> packMetaFor(String eventId) => _db.scanPackFor(eventId);

  Future<List<ScanPackTicketModel>> cachedTicketsFor(String eventId) async {
    final rows = await _db.scanPackTicketsFor(eventId);
    return rows
        .map((row) => ScanPackTicketModel.fromCacheJson(jsonDecode(row.json) as Map<String, dynamic>))
        .toList();
  }

  Future<String?> eventScanKeyFor(String eventId) => _eventScanKeyStore.get(eventId);

  String _encodeTicket(ScanPackTicketModel t) => jsonEncode(t.toCacheJson());
}
