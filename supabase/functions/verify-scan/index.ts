// verify-scan — the online counterpart to offline door scanning (§13.5) and
// the only path for membership verification (§9.11, §13.4), since
// membership scanning happens "at leisure at a desk" and is not pre-fetched
// as an offline pack. Also used to sync a batch of offline ticket scans on
// reconnect.
//
// Ticket redemption is a single conditional UPDATE keyed on scanned_at, so
// "earliest scanned_at wins" (§13.5 point 6) holds even when two offline
// devices redeemed the same ticket independently and sync arrives out of
// order — whichever UPDATE actually flips the row is authoritative; the
// other is recorded as already_redeemed for the post-event report.

import { z } from "npm:zod@3.23.8";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import {
  currentCounter,
  deriveEventScanKey,
  parseMemberPayload,
  parseTicketPayload,
  sha256Hex,
  verifyMemberSignature,
  verifyTicketSignature,
} from "../_shared/ticket-crypto.ts";

const ticketScanItem = z.object({
  payload: z.string().min(1).max(300),
  scanned_at: z.string().datetime().optional(),
  was_offline: z.boolean().default(false),
});

const bodySchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("ticket"),
    event_id: z.string().uuid(),
    device_id: z.string().min(1).max(200),
    scans: z.array(ticketScanItem).min(1).max(200),
  }),
  z.object({
    kind: z.literal("membership"),
    device_id: z.string().min(1).max(200),
    manual: z.literal(true),
    membership_number: z.string().min(1).max(40),
  }),
  z.object({
    kind: z.literal("membership"),
    device_id: z.string().min(1).max(200),
    manual: z.literal(false).default(false),
    payload: z.string().min(1).max(300),
  }),
]);

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  let body: z.infer<typeof bodySchema>;
  try {
    body = bodySchema.parse(await req.json());
  } catch (err) {
    return errorResponse("invalid request body", 400, err instanceof z.ZodError ? err.issues : String(err));
  }

  const caller = createCallerClient(req);
  const { data: userData, error: userErr } = await caller.auth.getUser();
  if (userErr || !userData?.user) return errorResponse("unauthenticated", 401);
  const staffId = userData.user.id;

  const admin = createAdminClient();

  const { data: isStaff } = await admin.rpc("is_staff", { p_uid: staffId });
  if (!isStaff) return errorResponse("forbidden — staff role required", 403);

  const allowed = await checkRateLimit(admin, `scan:${body.device_id}`, 60, "1 minute");
  if (!allowed) return errorResponse("Too many scans too fast — slow down.", 429);

  if (body.kind === "ticket") {
    let masterTicketKey: string;
    try {
      masterTicketKey = requireEnv("MASTER_TICKET_KEY");
    } catch (err) {
      console.error("verify-scan: MASTER_TICKET_KEY not set:", err);
      return errorResponse("Ticket signing isn't configured on this server yet.", 503);
    }
    const results = [];

    for (const scan of body.scans) {
      const scannedAt = scan.scanned_at ?? new Date().toISOString();
      const rawCodeHash = await sha256Hex(scan.payload);
      const parsed = parseTicketPayload(scan.payload);

      if (!parsed) {
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "invalid_signature", rawCodeHash,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
        }));
        continue;
      }

      const { data: ticket } = await admin
        .from("tickets")
        .select("id, event_id, status, ticket_type_id, attendee_name, redeemed_at, redeemed_by, ticket_types(name)")
        .eq("id", parsed.ticketId)
        .maybeSingle();

      if (!ticket) {
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "not_found", rawCodeHash, ticketId: parsed.ticketId,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
        }));
        continue;
      }

      if (ticket.event_id !== body.event_id) {
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "wrong_event", rawCodeHash, ticketId: ticket.id,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
        }));
        continue;
      }

      const eventScanKey = await deriveEventScanKey(masterTicketKey, ticket.event_id);
      const nowCounter = currentCounter();
      if (Math.abs(parsed.counter - nowCounter) > 1) {
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "expired_code", rawCodeHash, ticketId: ticket.id,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
        }));
        continue;
      }
      const signatureOk = await verifyTicketSignature(eventScanKey, parsed, nowCounter);
      if (!signatureOk) {
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "invalid_signature", rawCodeHash, ticketId: ticket.id,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
        }));
        continue;
      }

      if (ticket.status === "refunded" || ticket.status === "void" || ticket.status === "cancelled") {
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "ticket_refunded", rawCodeHash, ticketId: ticket.id,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
        }));
        continue;
      }

      // Conditional redemption: succeeds if the ticket is still valid, OR
      // if it's already redeemed but THIS scan happened earlier than the
      // recorded redemption (offline conflict resolution, §13.5 point 6).
      const { data: redeemed } = await admin
        .from("tickets")
        .update({
          status: "redeemed",
          redeemed_at: scannedAt,
          redeemed_by: staffId,
          redeemed_device_id: body.device_id,
          redeemed_offline: scan.was_offline,
        })
        .eq("id", ticket.id)
        .or(`status.eq.valid,and(status.eq.redeemed,redeemed_at.gt.${scannedAt})`)
        .select("id")
        .maybeSingle();

      if (redeemed) {
        await admin.rpc("award_loyalty_for_ticket", { p_ticket_id: ticket.id, p_trigger_source: "attended" });
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "valid", rawCodeHash, ticketId: ticket.id,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
          extra: { attendee_name: ticket.attendee_name, ticket_type_name: (ticket as any).ticket_types?.name },
        }));
      } else {
        results.push(await logAndReturn(admin, {
          kind: "ticket", result: "already_redeemed", rawCodeHash, ticketId: ticket.id,
          eventId: body.event_id, staffId, deviceId: body.device_id, scannedAt, wasOffline: scan.was_offline,
          extra: { attendee_name: ticket.attendee_name, redeemed_at: ticket.redeemed_at, redeemed_by: ticket.redeemed_by },
        }));
      }
    }

    return jsonResponse({ results });
  }

  // -------------------------------------------------------------- membership
  let profileId: string | null = null;
  let result: string;

  if (body.manual) {
    const { data: profile } = await admin
      .from("profiles")
      .select("id")
      .eq("membership_number", body.membership_number)
      .maybeSingle();
    profileId = profile?.id ?? null;
    result = profile ? "valid" : "not_found";
  } else {
    let masterMemberKey: string;
    try {
      masterMemberKey = requireEnv("MASTER_MEMBER_KEY");
    } catch (err) {
      console.error("verify-scan: MASTER_MEMBER_KEY not set:", err);
      return errorResponse("Membership signing isn't configured on this server yet.", 503);
    }
    const parsed = parseMemberPayload(body.payload);
    if (!parsed) {
      result = "invalid_signature";
    } else {
      const nowCounter = currentCounter();
      if (Math.abs(parsed.counter - nowCounter) > 1) {
        result = "expired_code";
      } else {
        const ok = await verifyMemberSignature(masterMemberKey, parsed, nowCounter);
        result = ok ? "valid" : "invalid_signature";
        profileId = ok ? parsed.profileId : null;
      }
    }
  }

  let responseExtra: Record<string, unknown> = {};
  if (profileId && result === "valid") {
    const { data: profile } = await admin
      .from("profiles")
      .select("full_name, membership_kind, membership_expires_at, member_status, membership_photo_path")
      .eq("id", profileId)
      .maybeSingle();

    if (!profile || profile.member_status !== "active") {
      result = "member_inactive";
    } else if (profile.membership_expires_at && new Date(profile.membership_expires_at) < new Date()) {
      result = "member_expired";
    } else {
      let photoSignedUrl: string | null = null;
      if (profile.membership_photo_path) {
        const { data: signed } = await admin.storage
          .from("membership-photos")
          .createSignedUrl(profile.membership_photo_path, 900); // 15 min, §13.6
        photoSignedUrl = signed?.signedUrl ?? null;
      }
      responseExtra = {
        full_name: profile.full_name,
        membership_kind: profile.membership_kind,
        valid_to: profile.membership_expires_at,
        photo_signed_url: photoSignedUrl,
      };
    }
  }

  const rawCodeHash = await sha256Hex(body.manual ? body.membership_number : body.payload);
  await admin.from("scan_events").insert({
    kind: "membership",
    result,
    raw_code_hash: rawCodeHash,
    profile_id: profileId,
    staff_id: staffId,
    device_id: body.device_id,
    scanned_at: new Date().toISOString(),
    was_offline: false,
  });

  return jsonResponse({
    result,
    profile_id: profileId,
    authenticated: !body.manual, // false = "Identified, not verified" (§9.11) — the UI MUST show this distinction
    ...responseExtra,
  });
});

async function logAndReturn(
  admin: ReturnType<typeof createAdminClient>,
  args: {
    kind: "ticket";
    result: string;
    rawCodeHash: string;
    ticketId?: string;
    eventId: string;
    staffId: string;
    deviceId: string;
    scannedAt: string;
    wasOffline: boolean;
    extra?: Record<string, unknown>;
  },
) {
  await admin.from("scan_events").insert({
    kind: args.kind,
    result: args.result,
    raw_code_hash: args.rawCodeHash,
    ticket_id: args.ticketId ?? null,
    event_id: args.eventId,
    staff_id: args.staffId,
    device_id: args.deviceId,
    scanned_at: args.scannedAt,
    was_offline: args.wasOffline,
  });
  return { ticket_id: args.ticketId ?? null, result: args.result, ...(args.extra ?? {}) };
}
