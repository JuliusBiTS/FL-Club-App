-- Loyalty: buy 10 qualifying tickets, get 1 free. One point per EVENT per
-- PERSON, not per ticket — buying four tickets to one panel earns one
-- point. Balance is never a stored integer; it is always derived from the
-- append-only ledger so a bug can be fixed by appending a compensating
-- entry rather than mutating history. This matters because points convert
-- into money.

create type loyalty_reason as enum (
  'purchase', 'refund_reversal', 'reward_granted', 'reward_redeemed',
  'manual_adjustment', 'migration'
);
create type reward_status as enum ('available', 'reserved', 'redeemed', 'expired', 'revoked');

create table loyalty_ledger (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  delta        integer not null,              -- +1 per qualifying ticket, -threshold when a reward is granted
  reason       loyalty_reason not null,
  ticket_id    uuid references tickets(id),
  event_id     uuid references events(id),
  note         text,
  created_by   uuid references profiles(id),   -- null for system-generated entries
  created_at   timestamptz not null default now()
);

-- Enforces "one point per event per person" at the database, not in
-- application code. If loyalty_config.max_points_per_event is ever set to
-- 0 (uncapped), this index MUST be dropped in the same migration that
-- changes the config default — document it as a paired change so the two
-- cannot drift apart.
create unique index loyalty_one_point_per_event_per_user
  on loyalty_ledger (user_id, event_id)
  where reason = 'purchase';

create index loyalty_ledger_user_idx on loyalty_ledger (user_id, created_at desc);
create unique index loyalty_one_entry_per_ticket
  on loyalty_ledger (ticket_id, reason) where ticket_id is not null;

create table loyalty_rewards (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references profiles(id) on delete cascade,
  status              reward_status not null default 'available',
  earned_at           timestamptz not null default now(),
  expires_at          timestamptz,                -- null = never; keep null at launch, see docs/DECISIONS.md
  reserved_order_id   uuid references orders(id),
  redeemed_order_id   uuid references orders(id),
  redeemed_at         timestamptz
);

create index loyalty_rewards_user_status_idx on loyalty_rewards (user_id, status);

create table loyalty_config (
  id                       integer primary key default 1 check (id = 1),   -- singleton row
  threshold                integer not null default 10,
  count_mode               text not null default 'purchased'
                             check (count_mode in ('purchased', 'attended')),
  min_price_minor          integer not null default 1,     -- free tickets never earn points
  member_tickets_count     boolean not null default true,
  max_points_per_event     integer not null default 1,      -- 0 = uncapped; see the paired-index note above
  reward_expiry_months     integer,                          -- null = never expires
  updated_at               timestamptz not null default now()
);

insert into loyalty_config (id) values (1);

create trigger loyalty_config_set_updated_at
  before update on loyalty_config
  for each row execute function set_updated_at();

create view loyalty_balances as
  select user_id, coalesce(sum(delta), 0) as balance
  from loyalty_ledger
  group by user_id;

comment on view loyalty_balances is
  'The only place a loyalty balance is computed. Never cache this into a stored column.';

-- ---------------------------------------------------------------------------
-- award_loyalty_for_ticket: called unconditionally by BOTH the stripe-webhook
-- (trigger_source='purchased') and the scan verification handler
-- (trigger_source='attended'). No-ops unless trigger_source matches
-- loyalty_config.count_mode, so exactly one of the two paths is ever live at
-- a time, and switching the mode later does not touch already-awarded
-- points (old points keep whatever reason/ticket they were earned under).
-- ---------------------------------------------------------------------------
create or replace function award_loyalty_for_ticket(p_ticket_id uuid, p_trigger_source text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ticket  tickets%rowtype;
  v_config  loyalty_config%rowtype;
  v_balance integer;
begin
  select * into v_ticket from tickets where id = p_ticket_id for update;
  if not found then
    return;
  end if;

  select * into v_config from loyalty_config where id = 1;

  if p_trigger_source is distinct from v_config.count_mode then
    return;
  end if;

  -- Qualification rules (briefing §10.1)
  if v_ticket.status in ('refunded', 'void', 'cancelled') then
    return;
  end if;
  if not v_ticket.counts_toward_loyalty then
    return;
  end if;
  if v_ticket.price_paid_minor < v_config.min_price_minor then
    return;
  end if;

  begin
    insert into loyalty_ledger (user_id, delta, reason, ticket_id, event_id)
    values (v_ticket.user_id, 1, 'purchase', v_ticket.id, v_ticket.event_id);
  exception when unique_violation then
    -- Already has a point for this event (another ticket in the same or a
    -- prior order). Silent no-op by design — see §10.1, never surface this
    -- as an error.
    return;
  end;

  select balance into v_balance from loyalty_balances where user_id = v_ticket.user_id;

  if v_balance >= v_config.threshold then
    insert into loyalty_ledger (user_id, delta, reason, note)
    values (v_ticket.user_id, -v_config.threshold, 'reward_granted', 'auto-granted on crossing threshold');

    insert into loyalty_rewards (user_id, status, expires_at)
    values (
      v_ticket.user_id,
      'available',
      case when v_config.reward_expiry_months is null then null
           else now() + (v_config.reward_expiry_months || ' months')::interval end
    );
    -- Caller (stripe-webhook / scan handler) is responsible for the push notification.
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- reverse_loyalty_for_refunded_ticket: called by the admin-console refund
-- action. Removes the point ONLY if no other qualifying ticket for the same
-- event remains — a refund of one ticket out of four to the same event must
-- not remove the point (§10.1/§10.4). Never claws back an already-redeemed
-- reward; only revokes one that is still 'available'.
-- ---------------------------------------------------------------------------
create or replace function reverse_loyalty_for_refunded_ticket(p_ticket_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ticket                   tickets%rowtype;
  v_config                   loyalty_config%rowtype;
  v_had_point                boolean;
  v_other_qualifying_remains boolean;
  v_reward_id                uuid;
  v_balance                  integer;
begin
  select * into v_ticket from tickets where id = p_ticket_id for update;
  if not found then
    return;
  end if;

  select * into v_config from loyalty_config where id = 1;

  select exists (
    select 1 from loyalty_ledger where ticket_id = p_ticket_id and reason = 'purchase'
  ) into v_had_point;

  if not v_had_point then
    return; -- this ticket never earned a point, nothing to reverse
  end if;

  select exists (
    select 1 from tickets t
    where t.event_id = v_ticket.event_id
      and t.user_id = v_ticket.user_id
      and t.id <> v_ticket.id
      and t.status = 'valid'
      and t.counts_toward_loyalty
      and t.price_paid_minor >= v_config.min_price_minor
  ) into v_other_qualifying_remains;

  if v_other_qualifying_remains then
    return; -- point survives on a sibling ticket to the same event
  end if;

  insert into loyalty_ledger (user_id, delta, reason, ticket_id, event_id, note)
  values (v_ticket.user_id, -1, 'refund_reversal', v_ticket.id, v_ticket.event_id,
          'reversed: no qualifying ticket remains for this event');

  select balance into v_balance from loyalty_balances where user_id = v_ticket.user_id;

  if v_balance < v_config.threshold then
    select id into v_reward_id from loyalty_rewards
    where user_id = v_ticket.user_id and status = 'available'
    order by earned_at desc limit 1;

    if v_reward_id is not null then
      update loyalty_rewards set status = 'revoked' where id = v_reward_id;
      -- Caller notifies the user. An already-redeemed reward is deliberately
      -- left untouched — write it off, do not claw back a used benefit.
    end if;
  end if;
end;
$$;
