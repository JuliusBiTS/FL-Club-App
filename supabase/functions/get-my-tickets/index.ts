// get-my-tickets — briefing §9.4. Hands the ticket holder everything needed
// to render every one of their tickets' rotating QR entirely offline from
// then on: display metadata (event/venue/type/status) plus each ticket's
// derived ticket_secret. Never the master_ticket_key itself — a compromised
// device only ever leaks secrets for tickets that holder already owned and
// was always entitled to display.
//
// Mirrors get-member-card's shape: one authenticated call, cache the result
// client-side, no further network access needed to show a valid code.

import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { base64urlEncode, deriveEventScanKey, deriveTicketSecret } from "../_shared/ticket-crypto.ts";

interface TicketRow {
  id: string;
  code: string;
  status: string;
  attendee_name: string | null;
  event_id: string;
  events: {
    id: string;
    slug: string;
    title: string;
    starts_at: string;
    venue_name: string;
    venue_room: string | null;
    venue_address: string;
  } | null;
  ticket_types: { name: string } | null;
  orders: { reference: string } | null;
}

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "GET" && req.method !== "POST") return errorResponse("method not allowed", 405);

  const caller = createCallerClient(req);
  const { data: userData, error: userErr } = await caller.auth.getUser();
  if (userErr || !userData?.user) return errorResponse("unauthenticated", 401);
  const userId = userData.user.id;

  const admin = createAdminClient();
  const { data: tickets, error: ticketsErr } = await admin
    .from("tickets")
    .select(
      "id, code, status, attendee_name, event_id, " +
        "events(id, slug, title, starts_at, venue_name, venue_room, venue_address), " +
        "ticket_types(name), orders(reference)",
    )
    .eq("user_id", userId)
    .order("created_at", { ascending: false });

  if (ticketsErr) {
    console.error("get-my-tickets query failed:", ticketsErr);
    return errorResponse("internal error", 500);
  }

  // MASTER_TICKET_KEY not being set yet is an expected, temporary state
  // during setup (see docs/TICKET_KEYS_SETUP.md) — surface it as a clean
  // error rather than Deno's opaque "Internal Server Error", same
  // reasoning as create-order's guard around STRIPE_SECRET_KEY.
  let masterTicketKey: string;
  try {
    masterTicketKey = requireEnv("MASTER_TICKET_KEY");
  } catch (err) {
    console.error("get-my-tickets: MASTER_TICKET_KEY not set:", err);
    return errorResponse("Ticket signing isn't configured on this server yet.", 503);
  }

  const eventScanKeyCache = new Map<string, Uint8Array>();

  const result = [];
  for (const t of (tickets ?? []) as unknown as TicketRow[]) {
    let eventScanKey = eventScanKeyCache.get(t.event_id);
    if (!eventScanKey) {
      eventScanKey = await deriveEventScanKey(masterTicketKey, t.event_id);
      eventScanKeyCache.set(t.event_id, eventScanKey);
    }
    const ticketSecret = await deriveTicketSecret(eventScanKey, t.id);

    result.push({
      ticket_id: t.id,
      code: t.code,
      status: t.status,
      attendee_name: t.attendee_name,
      order_reference: t.orders?.reference ?? null,
      ticket_type_name: t.ticket_types?.name ?? null,
      event: t.events && {
        id: t.events.id,
        slug: t.events.slug,
        title: t.events.title,
        starts_at: t.events.starts_at,
        venue_name: t.events.venue_name,
        venue_room: t.events.venue_room,
        venue_address: t.events.venue_address,
      },
      // Client regenerates rotating codes locally from this, no further
      // network calls needed until it re-syncs (e.g. next app foreground).
      ticket_secret: base64urlEncode(ticketSecret),
    });
  }

  return jsonResponse({ tickets: result, server_time: new Date().toISOString() });
});
