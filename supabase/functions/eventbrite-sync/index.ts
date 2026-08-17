// eventbrite-sync — briefing §11.2. Direction of truth is Eventbrite -> app,
// read-only. We NEVER write to Eventbrite — attempting bidirectional sync
// between two systems that both own inventory is a reliable source of
// double-selling; the fixed capacity_app/capacity_eventbrite split avoids
// the problem entirely. Runs every 5 minutes via pg_cron.

import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, requireEnv } from "../_shared/supabase-clients.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  const admin = createAdminClient();
  const token = requireEnv("EVENTBRITE_API_TOKEN");

  const { data: events, error } = await admin
    .from("events")
    .select("id, eventbrite_event_id")
    .eq("status", "published")
    .not("eventbrite_event_id", "is", null);

  if (error) {
    console.error("eventbrite-sync: failed to load events", error);
    return errorResponse("internal error", 500);
  }

  let synced = 0;
  const failed: string[] = [];

  for (const event of events ?? []) {
    try {
      const sold = await fetchEventbriteSoldCount(event.eventbrite_event_id as string, token);
      const { error: updateErr } = await admin
        .from("events")
        .update({ eventbrite_sold: sold, eventbrite_synced_at: new Date().toISOString() })
        .eq("id", event.id);
      if (updateErr) throw updateErr;
      synced++;
    } catch (err) {
      // A single event's sync failure must not block the rest, and must
      // not touch eventbrite_synced_at — the app is required to treat a
      // sync older than 30 minutes as stale and fall back to app-only
      // availability (§11.2), which happens automatically by simply not
      // updating the timestamp here.
      console.error(`eventbrite-sync failed for event ${event.id}:`, err);
      failed.push(String(event.id));
    }
  }

  return jsonResponse({ synced, failed });
});

async function fetchEventbriteSoldCount(eventbriteEventId: string, token: string): Promise<number> {
  const res = await fetch(`https://www.eventbriteapi.com/v3/events/${eventbriteEventId}/ticket_classes/`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    throw new Error(`Eventbrite API error ${res.status}: ${await res.text()}`);
  }
  const body = await res.json();
  const classes = (body.ticket_classes ?? []) as Array<{ quantity_sold?: number }>;
  return classes.reduce((sum, tc) => sum + (tc.quantity_sold ?? 0), 0);
}
