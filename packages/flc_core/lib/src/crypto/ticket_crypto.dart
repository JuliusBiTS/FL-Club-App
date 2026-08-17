import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Ticket & membership-card code signing — mirrors
/// supabase/functions/_shared/ticket-crypto.ts BYTE FOR BYTE (briefing
/// §13.3/§13.4). If you change one, change the other in the same commit.
///
/// Two roles use this, both inside the same app binary (briefing §9.11 —
/// "Staff scanner lives inside the same app"):
///   - A ticket/card HOLDER only ever GENERATES codes, from a secret handed
///     over TLS once at issue/card-sync — the sign* / current* functions.
///   - STAFF running the door scanner in offline mode VERIFY codes against
///     an event_scan_key downloaded ahead of time via get-scan-pack
///     (§13.5) — the parse*/verify* functions. This is what lets the door
///     work when the venue Wi-Fi fails.
/// Neither role ever needs master_ticket_key/master_member_key on-device;
/// those never leave the server.

// ---------------------------------------------------------------- encoding --

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

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

// ------------------------------------------------------------------ crypto --

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

class ParsedTicketPayload {
  const ParsedTicketPayload({required this.ticketId, required this.counter, required this.sig});
  final String ticketId;
  final int counter;
  final String sig;
}

ParsedTicketPayload? parseTicketPayload(String payload) {
  final parts = payload.split('|');
  if (parts.length != 5 || parts[0] != 'FLC1' || parts[1] != 'T') return null;
  try {
    final idBytes = base64UrlDecodeString(parts[2]);
    if (idBytes.length != 16) return null;
    final counter = int.parse(parts[3], radix: 36);
    return ParsedTicketPayload(ticketId: bytesToUuid(idBytes), counter: counter, sig: parts[4]);
  } catch (_) {
    return null;
  }
}

/// Offline door verification (briefing §13.5) — the staff scanner downloads
/// event_scan_key once via get-scan-pack, then verifies every ticket for
/// that event entirely locally. Accepts counter-1/counter/counter+1 (±90s)
/// to tolerate clock drift and slow scans, same window as the server.
/// Does NOT check redemption state — the scanner's local scan-pack cache
/// (or the tickets table, once synced) is the single source of truth for
/// "already used", not this function.
bool verifyTicketSignature(
  Uint8List eventScanKey,
  ParsedTicketPayload parsed, {
  int? nowCounter,
}) {
  final now = nowCounter ?? currentCounter();
  if ((parsed.counter - now).abs() > 1) return false;
  final secret = deriveTicketSecret(eventScanKey, parsed.ticketId);
  final expected = signTicketPayload(secret, parsed.ticketId, parsed.counter).split('|').last;
  return _constantTimeEquals(expected, parsed.sig);
}

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

class ParsedMemberPayload {
  const ParsedMemberPayload({required this.profileId, required this.counter, required this.sig});
  final String profileId;
  final int counter;
  final String sig;
}

ParsedMemberPayload? parseMemberPayload(String payload) {
  final parts = payload.split('|');
  if (parts.length != 5 || parts[0] != 'FLC1' || parts[1] != 'M') return null;
  try {
    final idBytes = base64UrlDecodeString(parts[2]);
    if (idBytes.length != 16) return null;
    final counter = int.parse(parts[3], radix: 36);
    return ParsedMemberPayload(profileId: bytesToUuid(idBytes), counter: counter, sig: parts[4]);
  } catch (_) {
    return null;
  }
}

/// Membership verification is online-only in v1 (briefing §9.11 — checked
/// "at leisure at a desk", not at a door queue), so this takes the already-
/// derived member_secret for the relevant period rather than a master key —
/// unlike verifyTicketSignature, no offline scan-pack equivalent exists for
/// membership yet. Kept here anyway so a future offline membership mode
/// doesn't have to invent this from scratch.
bool verifyMemberSignature(
  Uint8List memberSecret,
  ParsedMemberPayload parsed, {
  int? nowCounter,
}) {
  final now = nowCounter ?? currentCounter();
  if ((parsed.counter - now).abs() > 1) return false;
  final expected = signMemberPayload(memberSecret, parsed.profileId, parsed.counter).split('|').last;
  return _constantTimeEquals(expected, parsed.sig);
}
