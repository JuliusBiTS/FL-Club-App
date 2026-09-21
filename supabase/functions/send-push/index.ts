// send-push — staff-triggered push notifications (event announcements,
// FC Recommends, updates for ticket holders, general announcements).
//
// This is the ONLY code that can send a notification. Every call:
//   1. re-verifies the caller is staff or admin in the database (a client-side
//      role check is UX only, briefing §7.3);
//   2. works out who should receive it in Postgres (push_recipient_tokens —
//      honours opt-in, per-topic preferences, membership, ticket ownership);
//   3. is rate-limited, recorded in push_campaigns, and written to audit_log.
//
// `preview: true` only counts the audience — nothing is sent or recorded.
// Needs the FCM_SERVICE_ACCOUNT_JSON secret (docs/PUSH_SETUP.md); without it
// a real send answers 503 with a plain-English message, and preview still works.

import { z } from "npm:zod@3.23.8";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient } from "../_shared/supabase-clients.ts";
import { writeAuditLog } from "../_shared/audit.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getAccessToken, loadServiceAccount, sendToToken, type ServiceAccount } from "../_shared/fcm.ts";

const MAX_RECIPIENTS = 10_000;
const CONCURRENCY = 25;

const bodySchema = z
  .object({
    kind: z.enum(["new_event", "recommendation", "event_update", "announcement"]),
    audience: z.enum(["all", "members", "ticket_holders"]),
    title: z.string().trim().min(1).max(65),
    body: z.string().trim().min(1).max(240),
    event_id: z.string().uuid().optional(),
    preview: z.boolean().default(false),
  })
  .strict()
  .superRefine((v, ctx) => {
    if ((v.audience === "ticket_holders" || v.kind === "event_update") && !v.event_id) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "event_id is required for ticket holders / event updates" });
    }
    if (v.kind === "event_update" && v.audience !== "ticket_holders") {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "event updates only go to ticket holders" });
    }
  });

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
  const userId = userData.user.id;

  const admin = createAdminClient();
  const { data: isStaff } = await admin.rpc("is_staff", { p_uid: userId });
  if (!isStaff) return errorResponse("forbidden — staff role required", 403);

  // The event this is about, if any (also gives us the in-app route to open).
  let route = "/events";
  if (body.event_id) {
    const { data: event } = await admin.from("events").select("id, slug, status").eq("id", body.event_id).maybeSingle();
    if (!event) return errorResponse("event not found", 404);
    if ((body.kind === "new_event" || body.kind === "recommendation") && event.status !== "published") {
      return errorResponse("Publish the event before announcing it — people can't open an event that isn't live.", 409);
    }
    route = `/events/${event.slug}`;
  }

  const { data: recipients, error: recipientsErr } = await admin.rpc("push_recipient_tokens", {
    p_audience: body.audience,
    p_event_id: body.event_id ?? null,
    p_kind: body.kind,
  });
  if (recipientsErr) {
    console.error("push_recipient_tokens failed:", recipientsErr);
    return errorResponse("internal error", 500);
  }
  const tokens = ((recipients ?? []) as Array<{ user_id: string; token: string }>).map((r) => r.token);

  if (body.preview) return jsonResponse({ recipients: tokens.length, preview: true });

  if (tokens.length > MAX_RECIPIENTS) {
    return errorResponse(`That audience is over ${MAX_RECIPIENTS} devices — narrow it down.`, 400);
  }

  // Not set up yet? Say so before spending any of the sending allowance below.
  let serviceAccount: ServiceAccount;
  try {
    serviceAccount = loadServiceAccount();
  } catch (err) {
    console.error("FCM not configured:", err);
    return errorResponse("Push notifications aren't set up on the server yet (see docs/PUSH_SETUP.md).", 503);
  }

  // Rate limits (briefing §13.7 style): a per-person hourly cap, and a daily
  // cap on club-wide broadcasts so the app can't be spammed by accident.
  if (!(await checkRateLimit(admin, `push-user:${userId}`, 10, "1 hour"))) {
    return errorResponse("You've sent a lot of notifications in the last hour — try again a little later.", 429);
  }
  const broadcastKey = body.audience === "ticket_holders" ? `push-event:${body.event_id}` : `push-broadcast:${body.audience}`;
  const broadcastMax = body.audience === "ticket_holders" ? 5 : 3;
  if (!(await checkRateLimit(admin, broadcastKey, broadcastMax, "1 day"))) {
    return errorResponse(
      body.audience === "ticket_holders"
        ? "That's the daily limit of notifications to this event's ticket holders."
        : "That's the daily limit of notifications to everyone. Try again tomorrow.",
      429,
    );
  }

  const { data: campaign, error: campaignErr } = await admin
    .from("push_campaigns")
    .insert({
      event_id: body.event_id ?? null,
      kind: body.kind,
      audience: body.audience,
      title: body.title,
      body: body.body,
      status: "sending",
      recipients: tokens.length,
      created_by: userId,
    })
    .select("id")
    .single();
  if (campaignErr || !campaign) {
    console.error("could not record push campaign:", campaignErr);
    return errorResponse("internal error", 500);
  }

  let delivered = 0;
  let failed = 0;
  const deadTokens: string[] = [];

  try {
    const accessToken = await getAccessToken(serviceAccount);
    const message = { title: body.title, body: body.body, data: { route, campaign_id: campaign.id, kind: body.kind } };

    for (let i = 0; i < tokens.length; i += CONCURRENCY) {
      const batch = tokens.slice(i, i + CONCURRENCY);
      const outcomes = await Promise.all(batch.map((t) => sendToToken(serviceAccount, accessToken, t, message)));
      outcomes.forEach((outcome, idx) => {
        if (outcome === "ok") delivered++;
        else {
          failed++;
          if (outcome === "unregistered") deadTokens.push(batch[idx]);
        }
      });
    }
  } catch (err) {
    console.error("send-push failed mid-way:", err);
    await admin
      .from("push_campaigns")
      .update({ status: "failed", delivered, failed: tokens.length - delivered, error: String(err).slice(0, 500), sent_at: new Date().toISOString() })
      .eq("id", campaign.id);
    return errorResponse("The notification service failed part-way. Check the campaign history.", 502);
  }

  // Forget devices Google says no longer exist (app uninstalled, token rotated).
  if (deadTokens.length > 0) await admin.from("device_tokens").delete().in("token", deadTokens);

  await admin
    .from("push_campaigns")
    .update({
      status: tokens.length === 0 || delivered > 0 ? "sent" : "failed",
      delivered,
      failed,
      sent_at: new Date().toISOString(),
    })
    .eq("id", campaign.id);

  await writeAuditLog(admin, {
    actorId: userId,
    action: "push.send",
    entity: "push_campaign",
    entityId: campaign.id,
    after: { kind: body.kind, audience: body.audience, event_id: body.event_id ?? null, title: body.title, recipients: tokens.length, delivered, failed },
  });

  return jsonResponse({ campaign_id: campaign.id, recipients: tokens.length, delivered, failed });
});
