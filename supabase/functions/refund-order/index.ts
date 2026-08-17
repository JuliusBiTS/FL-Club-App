// refund-order — called from the admin console only. Refunds via Stripe
// first (source of truth for the money), then reconciles local state
// (ticket status, loyalty reversal per §10.4) and writes the audit trail.
// Supports partial refunds by accepting a specific list of ticket ids.

import { z } from "npm:zod@3.23.8";
import Stripe from "npm:stripe@16.9.0";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { writeAuditLog } from "../_shared/audit.ts";

const bodySchema = z
  .object({
    order_id: z.string().uuid(),
    ticket_ids: z.array(z.string().uuid()).min(1).optional(), // omit = refund the whole order
    reason: z.string().min(1).max(500),
  })
  .strict();

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
  const adminUserId = userData.user.id;

  const admin = createAdminClient();
  const { data: isAdmin } = await admin.rpc("is_admin", { p_uid: adminUserId });
  if (!isAdmin) return errorResponse("forbidden — admin role required", 403);

  const { data: order, error: orderErr } = await admin
    .from("orders")
    .select("id, status, stripe_payment_intent_id, quantity")
    .eq("id", body.order_id)
    .maybeSingle();
  if (orderErr || !order) return errorResponse("order not found", 404);
  if (order.status !== "paid" && order.status !== "partially_refunded") {
    return errorResponse(`Order is ${order.status}, not refundable.`, 409);
  }
  if (!order.stripe_payment_intent_id) return errorResponse("Order has no payment on record.", 409);

  let ticketIds = body.ticket_ids;
  if (!ticketIds) {
    const { data: allTickets } = await admin
      .from("tickets")
      .select("id, price_paid_minor")
      .eq("order_id", order.id)
      .eq("status", "valid");
    ticketIds = (allTickets ?? []).map((t) => t.id);
  }
  if (ticketIds.length === 0) return errorResponse("Nothing left to refund on this order.", 409);

  const { data: refundTickets } = await admin
    .from("tickets")
    .select("id, price_paid_minor")
    .in("id", ticketIds)
    .eq("order_id", order.id)
    .eq("status", "valid");
  const refundAmountMinor = (refundTickets ?? []).reduce((sum, t) => sum + t.price_paid_minor, 0);

  const stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"), { apiVersion: "2024-06-20" });
  let refund: Stripe.Refund;
  try {
    refund = await stripe.refunds.create({
      payment_intent: order.stripe_payment_intent_id,
      amount: refundAmountMinor > 0 ? refundAmountMinor : undefined, // undefined = full remaining amount
    });
  } catch (err) {
    console.error("Stripe refund failed:", err);
    return errorResponse("Stripe refund failed. No local state has changed.", 502);
  }

  const { error: reconcileErr } = await admin.rpc("refund_order", {
    p_order_id: order.id,
    p_ticket_ids: ticketIds,
  });
  if (reconcileErr) {
    // The money has already moved — this is now a support/ops situation,
    // not something to hide behind a generic error.
    console.error("CRITICAL: Stripe refund succeeded but refund_order() failed:", reconcileErr, "order:", order.id, "stripe_refund:", refund.id);
    return errorResponse("Refund processed with Stripe but local records failed to update — this needs manual reconciliation.", 500);
  }

  await writeAuditLog(admin, {
    actorId: adminUserId,
    action: "order.refund",
    entity: "orders",
    entityId: order.id,
    after: { stripe_refund_id: refund.id, ticket_ids: ticketIds, reason: body.reason, amount_minor: refundAmountMinor },
  });

  return jsonResponse({ refunded: true, stripe_refund_id: refund.id, ticket_ids: ticketIds });
});
