import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where `event_scan_key` lives on-device — secure storage, never Drift,
/// same reasoning as TicketSecretsStore (M4): it's what lets this device
/// verify a whole event's tickets offline, so it's sensitive in the same
/// way a ticket_secret is. Keyed by event_id since staff may hold packs
/// for more than one event at once (e.g. a multi-room evening).
class EventScanKeyStore {
  EventScanKeyStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'flc_event_scan_keys_v1';

  Future<void> put(String eventId, String eventScanKeyBase64Url) async {
    final map = await _readAll();
    map[eventId] = eventScanKeyBase64Url;
    await _storage.write(key: _key, value: jsonEncode(map));
  }

  Future<String?> get(String eventId) async {
    final map = await _readAll();
    return map[eventId] as String?;
  }

  Future<void> remove(String eventId) async {
    final map = await _readAll();
    map.remove(eventId);
    await _storage.write(key: _key, value: jsonEncode(map));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return <String, dynamic>{};
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
