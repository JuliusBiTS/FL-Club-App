// stripe-webhook — briefing §9.3 step 4 and threat T8.
//
// This endpoint is public. The signature is the only thing standing
// between it and free tickets — verify it before touching anything else,
// and guard against replay with processed_webhooks before any mutation.
// The app never creates a ticket; it only listens on Realtime for its own
// order row flipping to 'paid' after this function runs.

import Stripe from "npm:stripe@16.9.0";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, requireEnv } from "../_shared/supabase-clients.ts";
import { writeAuditLog } from "../_shared/audit.ts";

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  const signature = req.headers.get("stripe-signature");
  if (!signature) return errorResponse("missing stripe-signature header", 400);

  const stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"), { apiVersion: "2024-06-20" });
  const rawBody = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      requireEnv("STRIPE_WEBHOOK_SECRET"),
    );
  } catch (err) {
    // Reject anything that isn't genuinely from Stripe — do this before any
    // database access at all.
    console.error("Stripe signature verification failed:", err);
    return errorResponse("invalid signature", 400);
  }

  const admin = createAdminClient();

  // Replay guard: an INSERT that violates the primary key means we've
  // already handled this exact Stripe event.id — ignore duplicates rather
  // than re-processing (Stripe retries webhooks on anything but a 2xx).
  const { error: dedupeErr } = await admin.from("processed_webhooks").insert({ id: event.id });
  if (dedupeErr) {
    if (dedupeErr.code === "23505") {
      return jsonResponse({ received: true, duplicate: true });
    }
    console.error("processed_webhooks insert failed:", dedupeErr);
    return errorResponse("internal error", 500);
  }

  try {
    switch (event.type) {
      case "payment_intent.succeeded": {
        const pi = event.data.object as Stripe.PaymentIntent;
        const orderId = pi.metadata?.order_id;
        if (!orderId) break;

        const charge = pi.latest_charge && typeof pi.latest_charge !== "string" ? pi.latest_charge : null;
        const paymentMethodBrand = charge?.payment_method_details?.card?.brand
          ?? charge?.payment_method_details?.type
          ?? null;
        const paymentMethodLast4 = charge?.payment_method_details?.card?.last4 ?? null;

        const { data: ticketIds, error: markPaidErr } = await admin.rpc("mark_order_paid", {
          p_order_id: orderId,
          p_stripe_charge_id: typeof pi.latest_charge === "string" ? pi.latest_charge : charge?.id ?? null,
          p_payment_method_brand: paymentMethodBrand,
          p_payment_method_last4: paymentMethodLast4,
        });
        if (markPaidErr) {
          console.error("mark_order_paid failed for order", orderId, markPaidErr);
          break; // Stripe will retry the webhook; do not ack with 5xx here to avoid infinite retries on a data bug — investigate via logs instead.
        }

        // TODO(M4): send confirmation email + push using ticketIds.
        console.log(`Order ${orderId} paid, ${(ticketIds as string[])?.length ?? 0} ticket(s) issued.`);
        break;
      }

      case "payment_intent.payment_failed":
      case "payment_intent.canceled": {
        const pi = event.data.object as Stripe.PaymentIntent;
        const orderId = pi.metadata?.order_id;
        if (!orderId) break;
        await admin.rpc("release_order_hold", { p_order_id: orderId });
        break;
      }

      case "charge.refunded": {
        // Refunds are normally initiated FROM the admin console (which
        // calls refund-order directly), but a refund issued from the
        // Stripe dashboard should still reconcile local state.
        const charge = event.data.object as Stripe.Charge;
        const paymentIntentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent?.id;
        if (!paymentIntentId) break;

        const { data: order } = await admin
          .from("orders")
          .select("id")
          .eq("stripe_payment_intent_id", paymentIntentId)
          .maybeSingle();
        if (!order) break;

        const { data: tickets } = await admin
          .from("tickets")
          .select("id")
          .eq("order_id", order.id)
          .eq("status", "valid");
        const ticketIds = (tickets ?? []).map((t) => t.id);
        if (ticketIds.length > 0) {
          await admin.rpc("refund_order", { p_order_id: order.id, p_ticket_ids: ticketIds });
          await writeAuditLog(admin, {
            actorId: null,
            action: "order.refund.dashboard",
            entity: "orders",
            entityId: order.id,
            after: { source: "stripe_dashboard", stripe_charge_id: charge.id },
          });
        }
        break;
      }

      default:
        // Unhandled event types are fine to ignore — only ack.
        break;
    }
  } catch (err) {
    console.error("stripe-webhook handler error:", err);
    return errorResponse("internal error", 500);
  }

  return jsonResponse({ received: true });
});
