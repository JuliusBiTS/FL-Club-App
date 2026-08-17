// Ticket & membership-card code signing — briefing §13.3 / §13.4.
//
// event_scan_key(E)  = HKDF-SHA256(ikm=master_ticket_key, salt=event_id, info="flc-ticket-scan-v1", len=32)
// ticket_secret(T)   = HMAC-SHA256(event_scan_key(E), ticket_id)
// counter            = floor(unix_seconds / 30)
// sig                = first 10 bytes of HMAC-SHA256(ticket_secret(T), ticket_id + ":" + counter), base64url
// payload            = "FLC1|T|" + base64url(ticket_uuid_bytes) + "|" + base36(counter) + "|" + sig
//
// member_scan_key(period) = HKDF-SHA256(ikm=master_member_key, salt=YYYY-MM, info="flc-member-scan-v1", len=32)
// member_secret(U)        = HMAC-SHA256(member_scan_key(period), profile_id)
// payload                  = "FLC1|M|" + base64url(profile_uuid_bytes) + "|" + base36(counter) + "|" + sig
//
// A ±1 counter window (±90s) tolerates clock drift and slow scans.
//
// This module is the source of truth. It MUST be mirrored byte-for-byte in
// the Flutter app (packages/flc_core/lib/src/crypto/ticket_crypto.dart) so
// a ticket holder's device can regenerate codes with zero network calls,
// and a staff scanner can verify offline from a downloaded event_scan_key.
// If you change anything here, change it there too, in the same commit.

const encoder = new TextEncoder();

// ---------------------------------------------------------------- encoding --

export function base64urlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64urlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base36(n: number): string {
  return n.toString(36);
}

function uuidToBytes(uuid: string): Uint8Array {
  const hex = uuid.replace(/-/g, "");
  if (hex.length !== 32) throw new Error(`not a uuid: ${uuid}`);
  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  return bytes;
}

function bytesToUuid(bytes: Uint8Array): string {
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function base64Decode(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ------------------------------------------------------------------ crypto --

async function hmacSha256(keyBytes: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, message);
  return new Uint8Array(sig);
}

async function hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: string, lengthBytes: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt, info: encoder.encode(info) },
    key,
    lengthBytes * 8,
  );
  return new Uint8Array(bits);
}

export function currentCounter(nowMs: number = Date.now()): number {
  return Math.floor(nowMs / 1000 / 30);
}

// -------------------------------------------------------------- ticket QR --

export async function deriveEventScanKey(masterTicketKeyB64: string, eventId: string): Promise<Uint8Array> {
  return hkdfSha256(base64Decode(masterTicketKeyB64), encoder.encode(eventId), "flc-ticket-scan-v1", 32);
}

export async function deriveTicketSecret(eventScanKey: Uint8Array, ticketId: string): Promise<Uint8Array> {
  return hmacSha256(eventScanKey, encoder.encode(ticketId));
}

export async function signTicketPayload(ticketSecret: Uint8Array, ticketId: string, counter: number): Promise<string> {
  const message = encoder.encode(`${ticketId}:${counter}`);
  const full = await hmacSha256(ticketSecret, message);
  const sig = base64urlEncode(full.slice(0, 10));
  return `FLC1|T|${base64urlEncode(uuidToBytes(ticketId))}|${base36(counter)}|${sig}`;
}

export interface ParsedTicketPayload {
  ticketId: string;
  counter: number;
  sig: string;
}

export function parseTicketPayload(payload: string): ParsedTicketPayload | null {
  const parts = payload.split("|");
  if (parts.length !== 5 || parts[0] !== "FLC1" || parts[1] !== "T") return null;
  try {
    const idBytes = base64urlDecode(parts[2]);
    if (idBytes.length !== 16) return null;
    const counter = parseInt(parts[3], 36);
    if (!Number.isFinite(counter)) return null;
    return { ticketId: bytesToUuid(idBytes), counter, sig: parts[4] };
  } catch {
    return null;
  }
}

/** Verifies against counter-1, counter, counter+1 (±90s tolerance). Does NOT
 *  check redemption state — that's the caller's job (single source of truth
 *  for "already used" is the tickets table, not this function). */
export async function verifyTicketSignature(
  eventScanKey: Uint8Array,
  parsed: ParsedTicketPayload,
  nowCounter: number = currentCounter(),
): Promise<boolean> {
  if (Math.abs(parsed.counter - nowCounter) > 1) return false;
  const secret = await deriveTicketSecret(eventScanKey, parsed.ticketId);
  const expected = await signTicketPayload(secret, parsed.ticketId, parsed.counter);
  const expectedSig = expected.split("|")[4];
  return constantTimeEqual(expectedSig, parsed.sig);
}

// ---------------------------------------------------------- membership QR --

/** salt is the current UTC period as "YYYY-MM" — a suspended member's card
 *  stops verifying within a month even on an offline scanner, per §13.4. */
export function currentMemberPeriod(now: Date = new Date()): string {
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, "0");
  return `${y}-${m}`;
}

export async function deriveMemberScanKey(masterMemberKeyB64: string, period: string): Promise<Uint8Array> {
  return hkdfSha256(base64Decode(masterMemberKeyB64), encoder.encode(period), "flc-member-scan-v1", 32);
}

export async function deriveMemberSecret(memberScanKey: Uint8Array, profileId: string): Promise<Uint8Array> {
  return hmacSha256(memberScanKey, encoder.encode(profileId));
}

export async function signMemberPayload(memberSecret: Uint8Array, profileId: string, counter: number): Promise<string> {
  const message = encoder.encode(`${profileId}:${counter}`);
  const full = await hmacSha256(memberSecret, message);
  const sig = base64urlEncode(full.slice(0, 10));
  return `FLC1|M|${base64urlEncode(uuidToBytes(profileId))}|${base36(counter)}|${sig}`;
}

export interface ParsedMemberPayload {
  profileId: string;
  counter: number;
  sig: string;
}

export function parseMemberPayload(payload: string): ParsedMemberPayload | null {
  const parts = payload.split("|");
  if (parts.length !== 5 || parts[0] !== "FLC1" || parts[1] !== "M") return null;
  try {
    const idBytes = base64urlDecode(parts[2]);
    if (idBytes.length !== 16) return null;
    const counter = parseInt(parts[3], 36);
    if (!Number.isFinite(counter)) return null;
    return { profileId: bytesToUuid(idBytes), counter, sig: parts[4] };
  } catch {
    return null;
  }
}

export async function verifyMemberSignature(
  masterMemberKeyB64: string,
  parsed: ParsedMemberPayload,
  nowCounter: number = currentCounter(),
): Promise<boolean> {
  if (Math.abs(parsed.counter - nowCounter) > 1) return false;
  // Try the current period key; membership scans happen "at leisure at a
  // desk" (§13.4) so we also accept the previous period to cover a scan
  // landing exactly on a month boundary.
  const now = new Date();
  const periods = [currentMemberPeriod(now), currentMemberPeriod(new Date(now.getTime() - 24 * 3600 * 1000))];
  for (const period of periods) {
    const scanKey = await deriveMemberScanKey(masterMemberKeyB64, period);
    const secret = await deriveMemberSecret(scanKey, parsed.profileId);
    const expected = await signMemberPayload(secret, parsed.profileId, parsed.counter);
    const expectedSig = expected.split("|")[4];
    if (constantTimeEqual(expectedSig, parsed.sig)) return true;
  }
  return false;
}

// ------------------------------------------------------------------ misc --

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
