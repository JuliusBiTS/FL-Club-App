import 'dart:convert';
import 'dart:typed_data';

import 'package:flc_core/flc_core.dart';
import 'package:test/test.dart';

Uint8List _hex(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  final bytes = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

void main() {
  group('hkdfSha256', () {
    // Ground-truth vector computed independently via Node's
    // crypto.hkdfSync('sha256', ...) (OpenSSL-backed), using the exact
    // input shapes this function actually takes (ikm as raw bytes, salt
    // and info as UTF-8 strings) — not adapted from a vector with a
    // different byte layout. This is what gives confidence the algorithm
    // here matches the TypeScript mirror's native Web Crypto HKDF call,
    // since both ultimately implement RFC 5869 HKDF-SHA256.
    test('matches an independently-computed HKDF-SHA256 vector', () {
      final okm = hkdfSha256(
        ikm: _hex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'),
        salt: Uint8List.fromList(utf8.encode('event-id-test-salt')),
        info: 'flc-ticket-scan-v1',
        length: 32,
      );
      expect(okm, _hex('01fb3c15a18626567b2f4a580557c80a2fad735d87371990a50b18f600ef4318'));
    });

    test('different salts produce different keys (event isolation, briefing §13.3)', () {
      final ikm = _hex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
      final keyA = hkdfSha256(ikm: ikm, salt: Uint8List.fromList(utf8.encode('event-a')), info: 'flc-ticket-scan-v1', length: 32);
      final keyB = hkdfSha256(ikm: ikm, salt: Uint8List.fromList(utf8.encode('event-b')), info: 'flc-ticket-scan-v1', length: 32);
      expect(keyA, isNot(equals(keyB)));
    });
  });

  group('ticket payload', () {
    test('sign then parse round-trips exactly', () {
      final secret = Uint8List.fromList(List.generate(32, (i) => i));
      const ticketId = 'a1b2c3d4-e5f6-47a8-89b0-c1d2e3f4a5b6';
      const counter = 123456;

      final payload = signTicketPayload(secret, ticketId, counter);
      expect(payload, startsWith('FLC1|T|'));

      final parsed = parseTicketPayload(payload);
      expect(parsed, isNotNull);
      expect(parsed!.ticketId, ticketId);
      expect(parsed.counter, counter);
    });

    test('rejects malformed payloads', () {
      expect(parseTicketPayload('not-a-payload'), isNull);
      expect(parseTicketPayload('FLC1|M|xxx|1|sig'), isNull); // wrong domain marker
      expect(parseTicketPayload('FLC1|T|' '${base64UrlEncodeBytes(Uint8List(4))}|1|sig'), isNull); // short uuid
    });

    test('matches an independently-computed HMAC signature (crypto.createHmac via Node)', () {
      final secret = Uint8List.fromList(List.generate(32, (i) => i));
      const ticketId = 'a1b2c3d4-e5f6-47a8-89b0-c1d2e3f4a5b6';
      const counter = 123456;

      final payload = signTicketPayload(secret, ticketId, counter);
      final sig = payload.split('|').last;
      expect(sig, 'huOwbh43pAMVXA');
    });

    test('different counters produce different signatures', () {
      final secret = Uint8List.fromList(List.generate(32, (i) => i * 3 % 256));
      const ticketId = 'a1b2c3d4-e5f6-47a8-89b0-c1d2e3f4a5b6';

      final sigA = signTicketPayload(secret, ticketId, 1000).split('|').last;
      final sigB = signTicketPayload(secret, ticketId, 1001).split('|').last;
      expect(sigA, isNot(equals(sigB)));
    });

    test('currentTicketPayload is stable within a 30s window and changes across one', () {
      final secret = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      const ticketId = 'a1b2c3d4-e5f6-47a8-89b0-c1d2e3f4a5b6';

      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 5); // counter N
      final t1 = DateTime.utc(2026, 1, 1, 12, 0, 20); // still counter N (< 30s later)
      final t2 = DateTime.utc(2026, 1, 1, 12, 0, 35); // counter N+1

      final p0 = currentTicketPayload(secret, ticketId, now: t0);
      final p1 = currentTicketPayload(secret, ticketId, now: t1);
      final p2 = currentTicketPayload(secret, ticketId, now: t2);

      expect(p0, p1);
      expect(p0, isNot(equals(p2)));
    });
  });

  group('membership payload', () {
    test('currentMemberPeriod formats as YYYY-MM in UTC', () {
      expect(currentMemberPeriod(DateTime.utc(2026, 3, 7)), '2026-03');
      expect(currentMemberPeriod(DateTime.utc(2026, 11, 30)), '2026-11');
    });

    test('sign then parse round-trips exactly', () {
      final secret = Uint8List.fromList(List.generate(32, (i) => i + 1));
      const profileId = '11111111-2222-3333-4444-555555555555';
      const counter = 987654;

      final payload = signMemberPayload(secret, profileId, counter);
      expect(payload, startsWith('FLC1|M|'));

      final parsed = parseMemberPayload(payload);
      expect(parsed, isNotNull);
      expect(parsed!.profileId, profileId);
      expect(parsed.counter, counter);
    });

    test('a ticket payload is never mistaken for a membership payload and vice versa', () {
      final secret = Uint8List.fromList(List.generate(32, (i) => i));
      const id = 'a1b2c3d4-e5f6-47a8-89b0-c1d2e3f4a5b6';

      final ticketPayload = signTicketPayload(secret, id, 1);
      final memberPayload = signMemberPayload(secret, id, 1);

      expect(parseMemberPayload(ticketPayload), isNull);
      expect(parseTicketPayload(memberPayload), isNull);
    });
  });

  group('base64url helpers', () {
    test('round-trips arbitrary bytes including padding edge cases', () {
      for (final length in [0, 1, 2, 3, 4, 5, 16, 17, 32]) {
        final bytes = Uint8List.fromList(List.generate(length, (i) => (i * 7) % 256));
        final encoded = base64UrlEncodeBytes(bytes);
        expect(encoded.contains('='), isFalse, reason: 'no padding characters expected');
        expect(base64UrlDecodeString(encoded), bytes);
      }
    });
  });

  group('uuid helpers', () {
    test('round-trips a uuid through bytes', () {
      const id = 'a1b2c3d4-e5f6-47a8-89b0-c1d2e3f4a5b6';
      expect(bytesToUuid(uuidToBytes(id)), id);
    });
  });
}
