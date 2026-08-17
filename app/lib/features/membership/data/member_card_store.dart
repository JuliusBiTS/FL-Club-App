import 'dart:convert';

import 'package:flc_core/flc_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the cached membership card lives on-device — secure storage, one
/// record (a device only ever holds its own signed-in member's card,
/// unlike TicketSecretsStore/EventScanKeyStore which key by id because a
/// device can hold many tickets or scan packs at once). Bundles
/// member_secret with the display fields (including the PIN) in one
/// blob: member_secret is what actually lets this device mint a valid
/// rotating QR, and the PIN is identification-tier-only per the
/// three-tier trust model, so neither is meaningfully more sensitive
/// than the other here — no reason to split them across two stores.
class MemberCardStore {
  MemberCardStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'flc_member_card_v1';

  Future<void> save(MemberCardModel card) {
    return _storage.write(key: _key, value: jsonEncode(card.toCacheJson()));
  }

  Future<MemberCardModel?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    return MemberCardModel.fromCacheJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() => _storage.delete(key: _key);
}
