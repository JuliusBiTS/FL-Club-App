// send-event-reminders — run every 15 minutes by pg_cron (migration
// 20261001000001). Sends, to people who turned the bell on for an event:
//   * a reminder about a day before, and another about an hour before;
// and to signed-in people on a sold-out event's waiting list:
//   * a one-off "a place has opened up".
//
// Only the cron job (service role key) may call this — it is not a staff or
// app-user action. Every send is recorded first-come in event_reminders_sent /
// event_interests.notified_at, so an overlapping or retried run can't send twice.
// Without FCM_SERVICE_ACCOUNT_JSON it does nothing (and says so) rather than
// marking anything as sent.

import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient } from "../_shared/supabase-clients.ts";
import { getAccessToken, loadServiceAccount, sendToToken, type ServiceAccount } from "../_shared/fcm.ts";

const CONCURRENCY = 25;

interface ReminderRow {
  user_id: string;
  token: string;
  event_id: string;
  slug: string;
  title: string;
  starts_at: string;
  has_ticket: boolean;
}

interface WaitlistRow {
  user_id: string;
  token: string;
  event_id: string;
  slug: string;
  title: string;
}

const trunc = (s: string, n: number) => (s.length <= n ? s : s.slice(0, n - 1).trimEnd() + "…");
const londonTime = (iso: string) =>
  new Date(iso).toLocaleTimeString("en-GB", { timeZone: "Europe/London", hour: "2-digit", minute: "2-digit" });

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  // The service role key is the cron job's credential; the anon key (which any
  // app user holds) must not be enough to trigger a run.
  const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!bearer || bearer !== Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) return errorResponse("forbidden", 403);

  let serviceAccount: ServiceAccount;
  try {
    serviceAccount = loadServiceAccount();
  } catch (err) {
    console.error("FCM not configured:", err);
    return jsonResponse({ sent: 0, skipped: "push not configured" });
  }

  const admin = createAdminClient();
  const accessToken = await getAccessToken(serviceAccount);
  const dead: string[] = [];
  let sent = 0;

  const deliver = async (items: Array<{ token: string; title: string; body: string; route: string; kind: string }>) => {
    const ok: string[] = [];
    for (let i = 0; i < items.length; i += CONCURRENCY) {
      const batch = items.slice(i, i + CONCURRENCY);
      const outcomes = await Promise.all(
        batch.map((m) =>
          sendToToken(serviceAccount, accessToken, m.token, { title: m.title, body: m.body, data: { route: m.route, kind: m.kind } })
        ),
      );
      outcomes.forEach((o, idx) => {
        if (o === "ok") {
          sent++;
          ok.push(batch[idx].token);
        } else if (o === "unregistered") dead.push(batch[idx].token);
      });
    }
    return new Set(ok);
  };

  for (const kind of ["day_before", "hour_before"] as const) {
    const { data, error } = await admin.rpc("event_reminder_targets", { p_kind: kind });
    if (error) {
      console.error(`event_reminder_targets(${kind}) failed:`, error);
      continue;
    }
    const rows = (data ?? []) as ReminderRow[];
    const delivered = await deliver(
      rows.map((r) => {
        const when = londonTime(r.starts_at);
        const body = kind === "day_before"
          ? `Tomorrow at ${when}.${r.has_ticket ? " Your ticket is in You → My tickets." : " Tap for details and tickets."}`
          : `Starts at ${when}.${r.has_ticket ? " Have your ticket QR ready." : ""}`.trim();
        return { token: r.token, title: trunc(r.title, 65), body, route: `/events/${r.slug}`, kind: "event_update" };
      }),
    );
    // Mark a person as reminded once any of their devices got it.
    const reminded = new Map<string, ReminderRow>();
    for (const r of rows) if (delivered.has(r.token)) reminded.set(`${r.event_id}:${r.user_id}`, r);
    if (reminded.size > 0) {
      await admin.from("event_reminders_sent").upsert(
        [...reminded.values()].map((r) => ({ event_id: r.event_id, user_id: r.user_id, kind })),
        { onConflict: "event_id,user_id,kind", ignoreDuplicates: true },
      );
    }
  }

  {
    const { data, error } = await admin.rpc("waitlist_alert_targets");
    if (error) console.error("waitlist_alert_targets failed:", error);
    const rows = ((data ?? []) as WaitlistRow[]);
    const delivered = await deliver(
      rows.map((r) => ({
        token: r.token,
        title: trunc(r.title, 65),
        body: "A place has opened up — tap to book before it goes.",
        route: `/events/${r.slug}`,
        kind: "event_update",
      })),
    );
    const done = new Map<string, WaitlistRow>();
    for (const r of rows) if (delivered.has(r.token)) done.set(`${r.event_id}:${r.user_id}`, r);
    for (const r of done.values()) {
      await admin.from("event_interests").update({ notified_at: new Date().toISOString() }).eq("event_id", r.event_id).eq("user_id", r.user_id);
    }
  }

  if (dead.length > 0) await admin.from("device_tokens").delete().in("token", dead);
  return jsonResponse({ sent });
});
