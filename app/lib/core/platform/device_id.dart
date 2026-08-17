import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A random, opaque identifier for this install — the `device_id` string
/// verify-scan/get-scan-pack rate-limit and audit against. Deliberately
/// not a hardware identifier (no device_info_plus, no IMEI/serial): the
/// server only needs "same device or not" for rate limiting and the
/// scan_events audit trail, never who owns the phone. Generated once,
/// persisted in secure storage, and reused for the life of the install —
/// reinstalling gets you a new one, same as signing out doesn't rotate it.
class DeviceId {
  DeviceId(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'flc_device_id_v1';

  Future<String> get() async {
    final existing = await _storage.read(key: _key);
    if (existing != null) return existing;

    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final generated = base64Url.encode(bytes).replaceAll('=', '');
    await _storage.write(key: _key, value: generated);
    return generated;
  }
}
