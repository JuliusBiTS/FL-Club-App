-- Order lifecycle logic lives here, not scattered across Edge Function TS,
-- so the invariants in briefing §9.3 hold under a single Postgres
-- transaction: price/eligibility/stock are always re-read from the
-- database under a row lock, never trusted from the client.

-- ---------------------------------------------------------------------------
-- reserve_order_inventory: steps (a)-(f) of the create-order flow. Locks the
-- event and ticket_type rows, validates everything server-side, computes
-- the total from the DB price, and inserts a 'pending' order that holds
-- stock for p_hold_minutes. Raises a plain-English exception (briefing
-- §16.4 tone) on any validation failure — the Edge Function surfaces that
-- message directly to the client.
-- ---------------------------------------------------------------------------
create or replace function reserve_order_inventory(
  p_user_id uuid,
  p_event_id uuid,
  p_ticket_type_id uuid,
  p_quantity integer,
  p_use_loyalty_reward boolean,
  p_attendee_names text[],
  p_hold_minutes integer default 15
)
returns table (order_id uuid, reference text, total_minor integer, currency text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event       events%rowtype;
  v_ticket_type ticket_types%rowtype;
  v_profile     profiles%rowtype;
  v_issued      integer;
  v_reserved    integer;
  v_remaining   integer;
  v_subtotal    integer;
  v_discount    integer := 0;
  v_total       integer;
  v_reward_id   uuid;
  v_order_id    uuid;
  v_reference   text;
begin
  if p_quantity < 1 then
    raise exception 'Quantity must be at least 1.';
  end if;

  select * into v_event from events where id = p_event_id for update;
  if not found or v_event.status <> 'published' then
    raise exception 'This event is not available for booking.';
  end if;

  select * into v_ticket_type from ticket_types
    where id = p_ticket_type_id and event_id = p_event_id
    for update;
  if not found or not v_ticket_type.is_active then
    raise exception 'That ticket type is not available.';
  end if;

  if v_ticket_type.sales_start_at is not null and now() < v_ticket_type.sales_start_at then
    raise exception 'Ticket sales for this type have not opened yet.';
  end if;
  if v_ticket_type.sales_end_at is not null and now() > v_ticket_type.sales_end_at then
    raise exception 'Ticket sales for this type have closed.';
  end if;

  if p_quantity > v_ticket_type.max_per_order then
    raise exception 'You can buy at most % of this ticket type per order.', v_ticket_type.max_per_order;
  end if;

  select * into v_profile from profiles where id = p_user_id;
  if not found then
    raise exception 'Account not found.';
  end if;

  if v_ticket_type.requires_member and not is_active_member(p_user_id) then
    raise exception 'This ticket type is only available to active members.';
  end if;

  -- Remaining stock = configured quantity - already-issued tickets that
  -- still hold a seat - quantity held by OTHER still-live pending orders.
  -- All of this runs under the ticket_types row lock taken above, so two
  -- concurrent checkouts for the last seat cannot both succeed.
  select count(*) into v_issued
    from tickets
    where ticket_type_id = p_ticket_type_id and status not in ('void', 'cancelled', 'refunded');

  select coalesce(sum(o.quantity), 0) into v_reserved
    from orders o
    where o.ticket_type_id = p_ticket_type_id
      and o.status = 'pending'
      and o.created_at > now() - (p_hold_minutes || ' minutes')::interval;

  v_remaining := v_ticket_type.quantity - v_issued - v_reserved;
  if v_remaining < p_quantity then
    raise exception 'Not enough tickets left of this type.';
  end if;

  v_subtotal := v_ticket_type.price_minor * p_quantity;

  if p_use_loyalty_reward then
    select id into v_reward_id from loyalty_rewards
      where user_id = p_user_id and status = 'available'
      order by earned_at asc
      limit 1
      for update;
    if v_reward_id is null then
      raise exception 'No free ticket is available to use.';
    end if;
    -- Reward covers exactly one unit, at this ticket type's price (§10.2).
    v_discount := least(v_ticket_type.price_minor, v_subtotal);
  end if;

  v_total := v_subtotal - v_discount;

  v_reference := 'FLC-' || to_char(now(), 'YYMM') || '-' || upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 4));

  insert into orders (
    reference, user_id, event_id, ticket_type_id, quantity, attendee_names, status,
    subtotal_minor, discount_minor, total_minor, currency,
    loyalty_reward_id, member_price_applied, buyer_email, buyer_name
  ) values (
    v_reference, p_user_id, p_event_id, p_ticket_type_id, p_quantity, p_attendee_names, 'pending',
    v_subtotal, v_discount, v_total, v_ticket_type.currency,
    v_reward_id, v_ticket_type.requires_member, v_profile.email, v_profile.full_name
  ) returning id into v_order_id;

  if v_reward_id is not null then
    update loyalty_rewards
      set status = 'reserved', reserved_order_id = v_order_id
      where id = v_reward_id;
  end if;

  return query select v_order_id, v_reference, v_total, v_ticket_type.currency;
end;
$$;

-- ---------------------------------------------------------------------------
-- release_order_hold: used when Stripe rejects PaymentIntent creation, when
-- the payment_intent.payment_failed/canceled webhook fires, and by the
-- expire-pending-orders cron job. Idempotent — a no-op if the order has
-- already moved past 'pending'.
-- ---------------------------------------------------------------------------
create or replace function release_order_hold(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id for update;
  if not found or v_order.status <> 'pending' then
    return;
  end if;

  update orders set status = 'failed', cancelled_at = now() where id = p_order_id;

  if v_order.loyalty_reward_id is not null then
    update loyalty_rewards
      set status = 'available', reserved_order_id = null
      where id = v_order.loyalty_reward_id and status = 'reserved';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- find_expired_pending_orders: read-only helper for the expire-pending-
-- orders Edge Function, which needs the Stripe PaymentIntent id to cancel
-- it in Stripe (a Postgres function cannot call Stripe) before calling
-- release_order_hold for each row.
-- ---------------------------------------------------------------------------
create or replace function find_expired_pending_orders(p_hold_minutes integer default 15)
returns table (order_id uuid, stripe_payment_intent_id text)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select id, stripe_payment_intent_id
  from orders
  where status = 'pending'
    and created_at <= now() - (p_hold_minutes || ' minutes')::interval;
$$;

-- ---------------------------------------------------------------------------
-- mark_order_paid: called by stripe-webhook on payment_intent.succeeded,
-- inside the same request that already checked the Stripe signature and
-- the processed_webhooks replay guard. Idempotent on order status so a
-- duplicate call (belt-and-braces beyond the replay guard) is harmless.
-- Creates one tickets row per unit, awards loyalty per ticket, and marks
-- a used reward redeemed. Returns the new ticket ids so the Edge Function
-- can send the confirmation email/push without a second query.
-- ---------------------------------------------------------------------------
create or replace function mark_order_paid(
  p_order_id uuid,
  p_stripe_charge_id text,
  p_payment_method_brand text,
  p_payment_method_last4 text
)
returns setof uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order           orders%rowtype;
  v_ticket_type     ticket_types%rowtype;
  v_i               integer;
  v_attendee_name   text;
  v_code            text;
  v_ticket_id       uuid;
  v_price_per_unit  integer;
begin
  select * into v_order from orders where id = p_order_id for update;
  if not found then
    raise exception 'order % not found', p_order_id;
  end if;

  if v_order.status = 'paid' then
    return query select id from tickets where order_id = p_order_id;
    return;
  end if;

  if v_order.status <> 'pending' then
    raise exception 'order % is in unexpected status %', p_order_id, v_order.status;
  end if;

  select * into v_ticket_type from ticket_types where id = v_order.ticket_type_id;

  update orders set
    status = 'paid',
    paid_at = now(),
    stripe_charge_id = p_stripe_charge_id,
    payment_method_brand = p_payment_method_brand,
    payment_method_last4 = p_payment_method_last4
  where id = p_order_id;

  for v_i in 1..v_order.quantity loop
    -- The reward (if any) discounts exactly one unit — the first — per §10.2.
    v_price_per_unit := v_ticket_type.price_minor;
    if v_order.loyalty_reward_id is not null and v_i = 1 then
      v_price_per_unit := 0;
    end if;

    v_attendee_name := case
      when v_order.attendee_names is not null and array_length(v_order.attendee_names, 1) >= v_i
        then v_order.attendee_names[v_i]
      else v_order.buyer_name
    end;

    v_code := 'FLC-' || upper(substr(encode(gen_random_bytes(5), 'hex'), 1, 8));

    insert into tickets (order_id, event_id, user_id, ticket_type_id, code, attendee_name, price_paid_minor)
    values (p_order_id, v_order.event_id, v_order.user_id, v_order.ticket_type_id, v_code, v_attendee_name, v_price_per_unit)
    returning id into v_ticket_id;

    perform award_loyalty_for_ticket(v_ticket_id, 'purchased');

    return next v_ticket_id;
  end loop;

  if v_order.loyalty_reward_id is not null then
    update loyalty_rewards
      set status = 'redeemed', redeemed_order_id = p_order_id, redeemed_at = now()
      where id = v_order.loyalty_reward_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- refund_order: called by the admin console's refund action after the
-- Stripe-side refund succeeds. Reverses loyalty per ticket via
-- reverse_loyalty_for_refunded_ticket (which already implements the "point
-- survives if a sibling ticket to the same event remains valid" rule).
-- Supports partial refunds by only refunding the tickets passed in.
-- ---------------------------------------------------------------------------
create or replace function refund_order(p_order_id uuid, p_ticket_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ticket_id       uuid;
  v_refunded_count  integer;
  v_total_count     integer;
begin
  foreach v_ticket_id in array p_ticket_ids loop
    update tickets set status = 'refunded' where id = v_ticket_id and status = 'valid';
    perform reverse_loyalty_for_refunded_ticket(v_ticket_id);
  end loop;

  select count(*) filter (where status = 'refunded'), count(*)
    into v_refunded_count, v_total_count
    from tickets where order_id = p_order_id;

  update orders
    set status = case when v_refunded_count >= v_total_count then 'refunded' else 'partially_refunded' end
    where id = p_order_id;
end;
$$;
