-- Membership applications, synced content (podcast/news), and the two
-- append-only security tables. If an auditor can't trust scan_events or
-- audit_log, the log is decoration — so both REVOKE UPDATE/DELETE from
-- every role including service_role, enforced by a trigger that raises.

create type application_status as enum ('submitted', 'in_review', 'approved', 'rejected', 'withdrawn');

create table membership_applications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references profiles(id) on delete set null,
  email          text not null,
  full_name      text,
  occupation     text,
  message        text,
  source         text not null default 'app',
  status         application_status not null default 'submitted',
  submitted_at   timestamptz not null default now(),
  decided_at     timestamptz,
  decided_by     uuid references profiles(id),
  admin_notes    text
);

create index membership_applications_status_idx on membership_applications (status, submitted_at desc);

create table podcast_episodes (
  id                 uuid primary key default gen_random_uuid(),
  guid               text unique not null,      -- RSS <guid>, the sync key
  title              text not null,
  description_html   text,
  audio_url          text not null,
  duration_seconds   integer,
  image_url          text,
  episode_number     integer,
  season             integer,
  published_at       timestamptz not null,
  explicit           boolean not null default false,
  synced_at          timestamptz not null default now()
);

create index podcast_episodes_published_idx on podcast_episodes (published_at desc);

create table playback_progress (
  user_id           uuid not null references profiles(id) on delete cascade,
  episode_id        uuid not null references podcast_episodes(id) on delete cascade,
  position_seconds  integer not null default 0,
  completed         boolean not null default false,
  updated_at        timestamptz not null default now(),
  primary key (user_id, episode_id)
);

create trigger playback_progress_set_updated_at
  before update on playback_progress
  for each row execute function set_updated_at();

create table articles (   -- news / blog, synced one-way from WordPress
  id               uuid primary key default gen_random_uuid(),
  wp_post_id       bigint unique,
  slug             text unique not null,
  title            text not null,
  excerpt          text,
  content_html     text,
  hero_image_url   text,
  author_name      text,
  categories       text[] not null default '{}',
  canonical_url    text not null,
  published_at     timestamptz not null,
  synced_at        timestamptz not null default now()
);

create index articles_published_idx on articles (published_at desc);

create type scan_kind as enum ('ticket', 'membership');
create type scan_result as enum (
  'valid', 'invalid_signature', 'expired_code', 'already_redeemed', 'not_found',
  'wrong_event', 'ticket_refunded', 'member_inactive', 'member_expired', 'replay_detected'
);

create table scan_events (   -- security audit trail, append-only
  id              uuid primary key default gen_random_uuid(),
  kind            scan_kind not null,
  result          scan_result not null,
  raw_code_hash   text not null,      -- sha256 of the scanned payload — NEVER the payload itself
  ticket_id       uuid references tickets(id),
  profile_id      uuid references profiles(id),
  event_id        uuid references events(id),
  staff_id        uuid references profiles(id),
  device_id       text,
  scanned_at      timestamptz not null,
  synced_at       timestamptz not null default now(),
  was_offline     boolean not null default false
);

create index scan_events_event_idx on scan_events (event_id, scanned_at);
create index scan_events_ticket_idx on scan_events (ticket_id) where ticket_id is not null;

create table audit_log (   -- every privileged mutation
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references profiles(id),
  action      text not null,          -- 'membership.activate', 'order.refund', 'role.grant'
  entity      text not null,
  entity_id   uuid,
  before      jsonb,
  after       jsonb,
  ip          inet,
  user_agent  text,
  created_at  timestamptz not null default now()
);

create index audit_log_entity_idx on audit_log (entity, entity_id);
create index audit_log_actor_idx on audit_log (actor_id, created_at desc);

create or replace function forbid_update_or_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'append-only table: % on % is not permitted', tg_op, tg_table_name;
end;
$$;

create trigger scan_events_append_only
  before update or delete on scan_events
  for each row execute function forbid_update_or_delete();

create trigger audit_log_append_only
  before update or delete on audit_log
  for each row execute function forbid_update_or_delete();

revoke update, delete on scan_events from anon, authenticated, service_role;
revoke update, delete on audit_log from anon, authenticated, service_role;
