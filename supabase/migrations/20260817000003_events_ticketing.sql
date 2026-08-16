-- Events and the ticket types sold against them. Pricing is per event and
-- decided by the club, event by event — there is deliberately no fixed
-- price list anywhere in this schema. Every price the app shows MUST come
-- from ticket_types.price_minor, read live. No client-side price constants.

create type event_status as enum ('draft', 'published', 'cancelled', 'postponed', 'archived');
create type audience_kind as enum ('public', 'member', 'concession', 'student', 'press', 'guest_of_speaker');

create table events (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text unique not null,
  title                 text not null,
  subtitle              text,
  summary               text,                      -- 1–2 sentences for cards
  description_html      text,                       -- sanitised HTML for the detail page

  category              text,                       -- 'Panel', 'Screening', 'Book Night', 'Quiz', 'Workshop'
  tags                  text[] not null default '{}',

  starts_at             timestamptz not null,
  ends_at               timestamptz,
  doors_at              timestamptz,
  timezone              text not null default 'Europe/London',

  venue_name            text not null default 'The Frontline Club',
  venue_room            text,                       -- 'The Forum', 'Clubroom'
  venue_address         text not null default '13 Norfolk Place, London W2 1QJ',
  venue_lat             numeric(9,6),
  venue_lng             numeric(9,6),
  is_online             boolean not null default false,
  livestream_url        text,

  hero_image_path       text,
  gallery               jsonb not null default '[]'::jsonb,
  speakers              jsonb not null default '[]'::jsonb,   -- [{name, role, bio, photo_path}]

  status                event_status not null default 'draft',

  capacity_total        integer not null,
  capacity_app          integer not null default 0,  -- allocation sellable in the app
  capacity_eventbrite   integer not null default 0,   -- allocation held on Eventbrite
  eventbrite_event_id   text,
  eventbrite_url        text,
  eventbrite_sold       integer not null default 0,    -- refreshed by eventbrite-sync
  eventbrite_synced_at  timestamptz,

  is_filmed             boolean not null default true, -- drives the filming consent notice
  members_only          boolean not null default false,

  wp_post_id            bigint,
  published_at          timestamptz,

  created_by            uuid references profiles(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint capacity_split_valid
    check (capacity_app + capacity_eventbrite <= capacity_total),
  constraint capacity_non_negative
    check (capacity_total >= 0 and capacity_app >= 0 and capacity_eventbrite >= 0)
);

create index events_status_starts_idx on events (status, starts_at);
create index events_published_upcoming_idx on events (starts_at) where status = 'published';
create index events_eventbrite_id_idx on events (eventbrite_event_id) where eventbrite_event_id is not null;

create trigger events_set_updated_at
  before update on events
  for each row execute function set_updated_at();

create table ticket_types (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid not null references events(id) on delete cascade,

  name              text not null,               -- 'Standard', 'Member', 'Concession', 'Student'
  description       text,
  audience          audience_kind not null default 'public',

  price_minor       integer not null check (price_minor >= 0),  -- pence; 0 = free
  currency          char(3) not null default 'GBP',

  quantity          integer not null check (quantity >= 0),      -- carved out of events.capacity_app
  max_per_order     integer not null default 4 check (max_per_order > 0),

  requires_member   boolean not null default false,
  requires_proof    boolean not null default false,               -- ID checked at door

  sales_start_at    timestamptz,
  sales_end_at      timestamptz,

  sort_order        integer not null default 0,
  is_active         boolean not null default true,

  created_at        timestamptz not null default now()
);

comment on table ticket_types is
  'The admin can add/rename/remove/reorder these freely per event. The three-row default template (Standard/Member/Concession) offered on event creation is a UI convenience, not a schema constraint.';

create index ticket_types_event_idx on ticket_types (event_id) where is_active;
