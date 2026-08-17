import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where ticket_secret ever lives on-device — never in Drift (see
/// CachedTickets' doc comment in app_database.dart) and never anywhere
/// this app logs or serialises alongside other data. It's a single JSON
/// blob under one key rather than one key per ticket: [replaceAll] then
/// overwrites the whole set in one write on every refresh, which is
/// simpler than reconciling stale per-ticket keys for refunded/voided
/// tickets that dropped out of the latest get-my-tickets response.
class TicketSecretsStore {
  TicketSecretsStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'flc_ticket_secrets_v1';

  Future<void> replaceAll(Map<String, String> ticketIdToSecret) {
    return _storage.write(key: _key, value: jsonEncode(ticketIdToSecret));
  }

  Future<String?> secretFor(String ticketId) async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map[ticketId] as String?;
  }
}
