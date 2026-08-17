-- Orders and tickets. The app never creates a ticket directly — only the
-- stripe-webhook Edge Function does, running as service_role, after Stripe
-- confirms payment. See RLS in 20260817000009: there is no INSERT/UPDATE
-- policy on tickets for any client role at all.

create type order_status as enum
  ('pending', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded');
create type ticket_status as enum ('valid', 'redeemed', 'refunded', 'void', 'cancelled');

create table orders (
  id                        uuid primary key default gen_random_uuid(),
  reference                 text unique not null,   -- 'FLC-2609-4KX7', human-quotable

  user_id                   uuid not null references profiles(id),
  event_id                  uuid not null references events(id),
  ticket_type_id            uuid not null references ticket_types(id),
  quantity                  integer not null check (quantity > 0),
  attendee_names            text[],       -- optional, index-aligned with the tickets created on payment; falls back to buyer_name

  status                    order_status not null default 'pending',

  subtotal_minor            integer not null check (subtotal_minor >= 0),
  discount_minor            integer not null default 0 check (discount_minor >= 0),
  total_minor               integer not null check (total_minor >= 0),
  currency                  char(3) not null default 'GBP',

  stripe_payment_intent_id  text unique,
  stripe_charge_id          text,
  payment_method_brand      text,                    -- 'visa', 'google_pay' — display only
  payment_method_last4      text,

  loyalty_reward_id         uuid,                     -- set if this order redeemed a free ticket
  member_price_applied      boolean not null default false,

  buyer_email               text not null,             -- snapshot at purchase time
  buyer_name                text,

  created_at                timestamptz not null default now(),
  paid_at                   timestamptz,
  cancelled_at              timestamptz,

  constraint total_matches_subtotal_minus_discount
    check (total_minor = subtotal_minor - discount_minor)
);

create index orders_user_idx on orders (user_id, created_at desc);
create index orders_event_idx on orders (event_id, status);
create index orders_pending_expiry_idx on orders (created_at) where status = 'pending';
create index orders_ticket_type_pending_idx on orders (ticket_type_id) where status = 'pending';

create table tickets (
  id                    uuid primary key default gen_random_uuid(),
  order_id              uuid not null references orders(id) on delete cascade,
  event_id              uuid not null references events(id),
  user_id               uuid not null references profiles(id),
  ticket_type_id        uuid not null references ticket_types(id),

  code                  text unique not null,        -- 'FLC-3K9T-22XA', shown under the QR for manual entry
  status                ticket_status not null default 'valid',

  attendee_name         text,                          -- may differ from buyer
  price_paid_minor      integer not null check (price_paid_minor >= 0),
  counts_toward_loyalty boolean not null default true,

  redeemed_at           timestamptz,
  redeemed_by           uuid references profiles(id),
  redeemed_device_id    text,
  redeemed_offline      boolean not null default false,

  created_at            timestamptz not null default now()
);

comment on table tickets is
  'No secret column here on purpose — the per-ticket signing key is derived on demand from master_ticket_key + event_id + ticket_id (HKDF), never stored. See supabase/functions/_shared/ticket-crypto.ts.';

create index tickets_event_status_idx on tickets (event_id, status);
create index tickets_user_idx on tickets (user_id, created_at desc);
create unique index tickets_code_idx on tickets (code);

-- Guards against a fake/replayed Stripe webhook body being processed twice.
-- The webhook handler inserts event.id here before doing any mutation and
-- ignores the call if the insert violates the unique constraint.
create table processed_webhooks (
  id            text primary key,     -- Stripe event.id
  received_at   timestamptz not null default now()
);

comment on table processed_webhooks is
  'Replay guard for stripe-webhook. Rows are never read except by the ON CONFLICT check; safe to prune anything older than ~30 days with a scheduled job once volume matters.';
