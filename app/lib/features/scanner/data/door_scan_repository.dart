import 'dart:convert';

import 'package:flc_core/flc_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/local_db/app_database.dart';
import 'event_scan_key_store.dart';

/// One scanned QR, verified and (if valid) redeemed — entirely offline,
/// per briefing §13.5: "a door with dead Wi-Fi doesn't stop the door
/// working." Only scans this device actually admits (`result: 'valid'`)
/// get queued for the eventual verify-scan sync — a locally-rejected scan
/// caused no state change, so there's nothing to reconcile. The sync is
/// still what resolves conflicts between two devices that both admitted
/// the same ticket offline (§13.5 point 6); this repository only gives
/// the scanning device an immediate, locally-consistent answer.
class DoorScanRepository {
  DoorScanRepository(this._client, this._db, this._eventScanKeyStore);

  final SupabaseClient _client;
  final AppDatabase _db;
  final EventScanKeyStore _eventScanKeyStore;

  Future<TicketScanResultModel> scan({
    required String eventId,
    required String payload,
  }) async {
    final scannedAt = DateTime.now().toUtc();
    final parsed = parseTicketPayload(payload);
    if (parsed == null) {
      return const TicketScanResultModel(ticketId: '', result: 'invalid_signature');
    }

    final cached = await _db.scanPackTicketById(parsed.ticketId);
    if (cached == null || cached.eventId != eventId) {
      return TicketScanResultModel(ticketId: parsed.ticketId, result: 'not_found');
    }

    final keyBase64 = await _eventScanKeyStore.get(eventId);
    if (keyBase64 == null) {
      // Pack metadata says we have one but the secret's gone missing —
      // shouldn't happen outside manual app-data clearing, but fail
      // closed rather than pretend this scan was verified.
      return TicketScanResultModel(ticketId: parsed.ticketId, result: 'invalid_signature');
    }
    final eventScanKey = base64UrlDecodeString(keyBase64);
    final nowCounter = currentCounter(scannedAt);

    if ((parsed.counter - nowCounter).abs() > 1) {
      return TicketScanResultModel(ticketId: parsed.ticketId, result: 'expired_code');
    }
    if (!verifyTicketSignature(eventScanKey, parsed, nowCounter: nowCounter)) {
      return TicketScanResultModel(ticketId: parsed.ticketId, result: 'invalid_signature');
    }

    final ticketInfo = ScanPackTicketModel.fromCacheJson(jsonDecode(cached.json) as Map<String, dynamic>);
    final attendeeName = ticketInfo.attendeeName;
    final ticketTypeName = ticketInfo.ticketTypeName;

    if (cached.status == 'refunded' || cached.status == 'void' || cached.status == 'cancelled') {
      return TicketScanResultModel(ticketId: parsed.ticketId, result: 'ticket_refunded');
    }
    if (cached.status == 'redeemed') {
      return TicketScanResultModel(
        ticketId: parsed.ticketId,
        result: 'already_redeemed',
        attendeeName: attendeeName,
        ticketTypeName: ticketTypeName,
      );
    }

    await _db.markScanPackTicketStatus(parsed.ticketId, 'redeemed');
    await _db.enqueuePendingScan(
      ticketId: parsed.ticketId,
      eventId: eventId,
      payload: payload,
      scannedAt: scannedAt,
    );

    return TicketScanResultModel(
      ticketId: parsed.ticketId,
      result: 'valid',
      attendeeName: attendeeName,
      ticketTypeName: ticketTypeName,
    );
  }

  /// Flushes every queued offline scan for [eventId] to verify-scan in one
  /// batch call, then drops the ones the server acknowledged. A scan that
  /// fails to sync (network drop mid-batch) simply stays queued for the
  /// next attempt — nothing here assumes the batch either fully succeeds
  /// or fully fails.
  Future<int> syncPending(String eventId, String deviceId) async {
    final pending = await _db.pendingScansFor(eventId);
    if (pending.isEmpty) return 0;

    final response = await _client.functions.invoke(
      'verify-scan',
      body: {
        'kind': 'ticket',
        'event_id': eventId,
        'device_id': deviceId,
        'scans': [
          for (final p in pending)
            {
              'payload': p.payload,
              'scanned_at': p.scannedAt.toIso8601String(),
              'was_offline': p.wasOffline,
            },
        ],
      },
    );

    final data = response.data as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>).cast<Map<String, dynamic>>();

    // Reconcile local status with whatever the server decided was
    // authoritative (it may differ from this device's own guess if
    // another device redeemed the same ticket first — §13.5 point 6).
    for (final r in results) {
      final ticketId = r['ticket_id'] as String;
      final result = r['result'] as String;
      if (result == 'valid' || result == 'already_redeemed') {
        await _db.markScanPackTicketStatus(ticketId, 'redeemed');
      }
    }

    await _db.deletePendingScans([for (final p in pending) p.id]);
    return pending.length;
  }
}
