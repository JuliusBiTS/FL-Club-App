// create-order — briefing §9.3 checkout server flow, steps 1-2.
//
// The client sends only its intent (event, ticket type, quantity). Price,
// eligibility and stock are re-read from the database inside
// reserve_order_inventory() under a row lock — the client's claims about
// price or membership are never trusted (threats T6/T7 in §13.1).

import { z } from "npm:zod@3.23.8";
import Stripe from "npm:stripe@16.9.0";
import { handlePreflight } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createAdminClient, createCallerClient, requireEnv } from "../_shared/supabase-clients.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

const bodySchema = z
  .object({
    event_id: z.string().uuid(),
    ticket_type_id: z.string().uuid(),
    quantity: z.number().int().min(1).max(20),
    use_loyalty_reward: z.boolean().default(false),
    attendee_names: z.array(z.string().min(1).max(200)).max(20).optional(),
  })
  .strict();

const HOLD_MINUTES = 15;

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

  const allowed = await checkRateLimit(admin, `create-order:${userId}`, 10, "1 minute");
  if (!allowed) return errorResponse("Too many requests — please wait a moment and try again.", 429);

  const { data: reservationRows, error: reserveErr } = await admin.rpc("reserve_order_inventory", {
    p_user_id: userId,
    p_event_id: body.event_id,
    p_ticket_type_id: body.ticket_type_id,
    p_quantity: body.quantity,
    p_use_loyalty_reward: body.use_loyalty_reward,
    p_attendee_names: body.attendee_names ?? null,
    p_hold_minutes: HOLD_MINUTES,
  });

  if (reserveErr) {
    // reserve_order_inventory raises a plain-English exception for every
    // validation failure (sold out, sales window closed, not a member,
    // reward unavailable, ...) — surface it directly, per §16.4 tone.
    return errorResponse(reserveErr.message, 409);
  }
  const reservation = (reservationRows as Array<{
    order_id: string;
    reference: string;
    total_minor: number;
    currency: string;
  }>)[0];

  const stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"), { apiVersion: "2024-06-20" });

  let paymentIntent: Stripe.PaymentIntent;
  try {
    paymentIntent = await stripe.paymentIntents.create(
      {
        amount: reservation.total_minor,
        currency: reservation.currency.toLowerCase(),
        metadata: { order_id: reservation.order_id, event_id: body.event_id, user_id: userId },
        automatic_payment_methods: { enabled: true },
      },
      { idempotencyKey: reservation.order_id }, // safe to retry this exact order without double-charging
    );
  } catch (err) {
    // Don't leave stock reserved for 15 minutes for a payment that will
    // never happen — release immediately if Stripe itself rejects us.
    await admin.rpc("release_order_hold", { p_order_id: reservation.order_id });
    console.error("Stripe PaymentIntent creation failed:", err);
    return errorResponse("We couldn't start the payment. No money has been taken.", 502);
  }

  const { error: updateErr } = await admin
    .from("orders")
    .update({ stripe_payment_intent_id: paymentIntent.id })
    .eq("id", reservation.order_id);
  if (updateErr) {
    console.error("Failed to attach payment_intent_id to order:", updateErr);
  }

  return jsonResponse({
    order_id: reservation.order_id,
    reference: reservation.reference,
    client_secret: paymentIntent.client_secret,
    total_minor: reservation.total_minor,
  });
});
