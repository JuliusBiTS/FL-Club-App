// get-scan-pack — briefing §13.5. Hands a staff device everything it needs
// to verify tickets for one event fully offline: the derived
// event_scan_key (never the master key itself, so a compromised scanner
// only ever compromises one event) and the current ticket list.

import { z } from "npm:zod@3.23.8";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { deriveEventScanKey, base64urlEncode } from "../_shared/ticket-crypto.ts";

const bodySchema = z.object({ event_id: z.string().uuid() }).strict();

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

  const { data: event, error: eventErr } = await admin
    .from("events")
    .select("id, starts_at, ends_at, status")
    .eq("id", body.event_id)
    .maybeSingle();
  if (eventErr || !event) return errorResponse("event not found", 404);

  // Staff can scan any event at any time — no "too early" or "too late"
  // window (feedback: tickets must be scannable whenever, even for an event
  // far in the future). The pack is just this event's ticket list plus its
  // scan key, and it's re-downloaded whenever staff pick the event.
  const now = Date.now();
  const startsAt = new Date(event.starts_at).getTime();
  const endsAt = event.ends_at ? new Date(event.ends_at).getTime() : startsAt + 3 * 3600_000;
  const sixHoursMs = 6 * 3600_000;

  let masterTicketKey: string;
  try {
    masterTicketKey = requireEnv("MASTER_TICKET_KEY");
  } catch (err) {
    console.error("get-scan-pack: MASTER_TICKET_KEY not set:", err);
    return errorResponse("Ticket signing isn't configured on this server yet.", 503);
  }
  const eventScanKey = await deriveEventScanKey(masterTicketKey, event.id);

  const { data: tickets, error: ticketsErr } = await admin
    .from("tickets")
    .select("id, code, attendee_name, status, ticket_types(name)")
    .eq("event_id", event.id);
  if (ticketsErr) {
    console.error("get-scan-pack ticket query failed:", ticketsErr);
    return errorResponse("internal error", 500);
  }

  // Good for at least a day, or until six hours after the event ends.
  const expiresAt = new Date(Math.max(endsAt + sixHoursMs, now + 24 * 3600_000)).toISOString();

  return jsonResponse({
    event_id: event.id,
    event_scan_key: base64urlEncode(eventScanKey),
    tickets: (tickets ?? []).map((t) => ({
      ticket_id: t.id,
      code: t.code,
      attendee_name: t.attendee_name,
      ticket_type_name: (t as any).ticket_types?.name ?? null,
      status: t.status,
    })),
    expires_at: expiresAt,
    server_time: new Date().toISOString(),
  });
});
