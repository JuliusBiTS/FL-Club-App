// simulate-test-payment — lets the whole ticketing flow (order → paid →
// tickets issued → confirmation) be exercised before the club has
// connected a real Stripe account. Feedback: "put a placeholder payment
// feature so the whole ticketing process can go through and be tested."
//
// Safety: this can ONLY ever run while STRIPE_SECRET_KEY is unset on this
// project. The moment the club connects a real Stripe account, this
// function refuses every request — it can never become a free-ticket path
// once payments are actually live. See docs/DECISIONS.md.

import { z } from "npm:zod@3.23.8";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient } from "../_shared/supabase-clients.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { writeAuditLog } from "../_shared/audit.ts";

const bodySchema = z.object({ order_id: z.string().uuid() }).strict();

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse("method not allowed", 405);

  // The one guard that matters most here: refuse outright once real
  // Stripe is configured, regardless of anything else in this request.
  if (Deno.env.get("STRIPE_SECRET_KEY")) {
    return errorResponse("Test payments are disabled now that a real Stripe account is connected.", 403);
  }

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

  const allowed = await checkRateLimit(admin, `simulate-test-payment:${userId}`, 20, "1 hour");
  if (!allowed) return errorResponse("Too many requests — please wait a moment and try again.", 429);

  // Ownership check: mark_order_paid trusts whatever order_id it's given
  // (it's normally only ever called from stripe-webhook, after Stripe's
  // own signature has already proven who paid) — since this endpoint is
  // reachable by any signed-in user, it must verify the order is actually
  // theirs before touching it, or anyone could "pay" anyone else's order.
  const { data: order, error: orderErr } = await admin
    .from("orders")
    .select("id, user_id, status")
    .eq("id", body.order_id)
    .maybeSingle();

  if (orderErr || !order) return errorResponse("Order not found.", 404);
  if (order.user_id !== userId) return errorResponse("Order not found.", 404); // same message: don't reveal it exists
  if (order.status !== "pending") return errorResponse(`Order is ${order.status}, not pending.`, 409);

  const { data: ticketIds, error: markPaidErr } = await admin.rpc("mark_order_paid", {
    p_order_id: body.order_id,
    p_stripe_charge_id: `test_${body.order_id}`,
    p_payment_method_brand: "test_mode",
    p_payment_method_last4: "0000",
  });

  if (markPaidErr) {
    console.error("simulate-test-payment: mark_order_paid failed:", markPaidErr);
    return errorResponse("Something went wrong completing the test payment.", 500);
  }

  await writeAuditLog(admin, {
    actorId: userId,
    action: "order.test_payment",
    entity: "orders",
    entityId: body.order_id,
    after: { source: "simulate-test-payment", ticket_count: (ticketIds as string[])?.length ?? 0 },
  });

  return jsonResponse({ order_id: body.order_id, status: "paid", ticket_ids: ticketIds });
});
