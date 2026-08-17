// expire-pending-orders — briefing §9.3. Runs every 5 minutes via pg_cron
// (migration 20260817000011). A pending order holds its stock for 15
// minutes; without this job, abandoned checkouts would silently sell out
// an event.

import Stripe from "npm:stripe@16.9.0";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, requireEnv } from "../_shared/supabase-clients.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  const admin = createAdminClient();
  const stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"), { apiVersion: "2024-06-20" });

  const { data: expired, error } = await admin.rpc("find_expired_pending_orders", { p_hold_minutes: 15 });
  if (error) {
    console.error("find_expired_pending_orders failed:", error);
    return errorResponse("internal error", 500);
  }

  let released = 0;
  for (const row of (expired ?? []) as Array<{ order_id: string; stripe_payment_intent_id: string | null }>) {
    if (row.stripe_payment_intent_id) {
      try {
        await stripe.paymentIntents.cancel(row.stripe_payment_intent_id);
      } catch (err) {
        // A PaymentIntent that already succeeded/canceled on Stripe's side
        // throws here too — expected in some races. Log anything else but
        // keep going: an abandoned checkout must never keep holding a seat.
        console.warn(`Could not cancel PaymentIntent ${row.stripe_payment_intent_id}:`, err);
      }
    }

    const { error: releaseErr } = await admin.rpc("release_order_hold", { p_order_id: row.order_id });
    if (releaseErr) {
      console.error(`release_order_hold failed for order ${row.order_id}:`, releaseErr);
      continue;
    }
    released++;
  }

  return jsonResponse({ released });
});
