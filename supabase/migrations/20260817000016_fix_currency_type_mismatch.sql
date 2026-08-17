-- Fix: also found live. reserve_order_inventory's RETURN QUERY failed with
-- "structure of query does not match function result type" — ticket_types.currency
-- is char(3) (bpchar) but the function declares its `currency` output
-- column as text, and Postgres does not implicitly match those for
-- RETURN QUERY the way it does for a plain SELECT. Cast it explicitly.
-- Redefines the whole function (not just the search_path fixed in
-- 20260817000015) because CREATE OR REPLACE doesn't reliably retain a
-- prior ALTER FUNCTION ... SET unless restated — so this restates it too,
-- making this migration self-contained.
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
set search_path = public, extensions, pg_temp
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

  return query select v_order_id, v_reference, v_total, v_ticket_type.currency::text;
end;
$$;
