import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Ticket & membership-card code generation — mirrors
/// supabase/functions/_shared/ticket-crypto.ts BYTE FOR BYTE (briefing
/// §13.3/§13.4). If you change one, change the other in the same commit.
///
/// The app only ever GENERATES codes here (from a secret it was handed once
/// over TLS at ticket issue / card sync) — it never verifies anyone else's,
/// that's the scanner's job server-side. This is what lets a ticket
/// holder's device regenerate a rotating QR every 30 seconds, and the
/// membership card render, with zero network calls.

String base64UrlEncodeBytes(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List base64UrlDecodeString(String s) {
  final padded = s.padRight((s.length + 3) ~/ 4 * 4, '=');
  return base64Url.decode(padded);
}

Uint8List uuidToBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) {
    throw FormatException('not a uuid: $uuid');
  }
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String bytesToUuid(Uint8List bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _base36(int n) => n.toRadixString(36);

Uint8List _hmacSha256(Uint8List key, List<int> message) =>
    Uint8List.fromList(Hmac(sha256, key).convert(message).bytes);

/// RFC 5869 HKDF-SHA256. Dart's crypto package has no built-in HKDF, so
/// extract+expand are implemented by hand here — keep this in lock-step
/// with the Web Crypto HKDF call in the TypeScript mirror.
Uint8List hkdfSha256({
  required Uint8List ikm,
  required Uint8List salt,
  required String info,
  required int length,
}) {
  final prk = _hmacSha256(salt, ikm);
  final infoBytes = utf8.encode(info);
  final okm = BytesBuilder();
  var t = Uint8List(0);
  var counter = 1;
  while (okm.length < length) {
    final input = BytesBuilder()
      ..add(t)
      ..add(infoBytes)
      ..addByte(counter);
    t = _hmacSha256(prk, input.toBytes());
    okm.add(t);
    counter++;
  }
  return Uint8List.fromList(okm.toBytes().sublist(0, length));
}

int currentCounter([DateTime? now]) =>
    ((now ?? DateTime.now().toUtc()).millisecondsSinceEpoch / 1000 / 30).floor();

// ---------------------------------------------------------------- tickets --

Uint8List deriveEventScanKey(Uint8List masterTicketKey, String eventId) => hkdfSha256(
      ikm: masterTicketKey,
      salt: Uint8List.fromList(utf8.encode(eventId)),
      info: 'flc-ticket-scan-v1',
      length: 32,
    );

Uint8List deriveTicketSecret(Uint8List eventScanKey, String ticketId) =>
    _hmacSha256(eventScanKey, utf8.encode(ticketId));

String signTicketPayload(Uint8List ticketSecret, String ticketId, int counter) {
  final message = utf8.encode('$ticketId:$counter');
  final full = _hmacSha256(ticketSecret, message);
  final sig = base64UrlEncodeBytes(full.sublist(0, 10));
  return 'FLC1|T|${base64UrlEncodeBytes(uuidToBytes(ticketId))}|${_base36(counter)}|$sig';
}

/// Regenerates the live QR payload for display — call from a 30s timer,
/// entirely offline, using the ticket_secret handed over once at issue.
String currentTicketPayload(Uint8List ticketSecret, String ticketId, {DateTime? now}) =>
    signTicketPayload(ticketSecret, ticketId, currentCounter(now));

// ------------------------------------------------------------ membership --

/// The current UTC period as "YYYY-MM" — matches the server's monthly
/// member_scan_key salt (briefing §13.4).
String currentMemberPeriod([DateTime? now]) {
  final n = now ?? DateTime.now().toUtc();
  final y = n.year.toString().padLeft(4, '0');
  final m = n.month.toString().padLeft(2, '0');
  return '$y-$m';
}

Uint8List deriveMemberScanKey(Uint8List masterMemberKey, String period) => hkdfSha256(
      ikm: masterMemberKey,
      salt: Uint8List.fromList(utf8.encode(period)),
      info: 'flc-member-scan-v1',
      length: 32,
    );

Uint8List deriveMemberSecret(Uint8List memberScanKey, String profileId) =>
    _hmacSha256(memberScanKey, utf8.encode(profileId));

String signMemberPayload(Uint8List memberSecret, String profileId, int counter) {
  final message = utf8.encode('$profileId:$counter');
  final full = _hmacSha256(memberSecret, message);
  final sig = base64UrlEncodeBytes(full.sublist(0, 10));
  return 'FLC1|M|${base64UrlEncodeBytes(uuidToBytes(profileId))}|${_base36(counter)}|$sig';
}

/// member_secret comes from get-member-card, already scoped to the current
/// monthly period — this just re-signs it locally every 30 seconds. The app
/// should re-fetch a fresh member_secret when the local period rolls over
/// (compare against `period` returned alongside it).
String currentMemberPayload(Uint8List memberSecret, String profileId, {DateTime? now}) =>
    signMemberPayload(memberSecret, profileId, currentCounter(now));
