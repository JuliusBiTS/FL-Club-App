-- Event management: staff-editable events, promotion fields (FC Recommends /
-- special offers / perks), scheduled publishing, an audit trail for every
-- event change, and the tables behind push notifications.
--
-- Permission model (agreed with the club):
--   * staff  — create events, edit content, upload images, publish, and send
--              push notifications. While an event is still a DRAFT they can
--              also set ticket prices and capacity, so they can build a
--              complete event on their own.
--   * admin  — everything, plus: change price/capacity on a PUBLISHED event,
--              cancel an event, delete an event.
-- Those rules live here, in Postgres, not just in the UI — the console and
-- the app only ever hide buttons (briefing §7.3: client role checks are UX).

-- ===========================================================================
-- 1. New event fields
-- ===========================================================================

create type event_highlight as enum ('none', 'fc_recommends', 'staff_pick', 'special_offer');

alter table events
  add column description_md     text,                                    -- source the editor works on; description_html is generated from it
  add column links              jsonb not null default '[]'::jsonb,       -- [{label, url, kind}] — books, films, articles, donate…
  add column highlight          event_highlight not null default 'none',
  add column perks              text[] not null default '{}',             -- short labels, e.g. 'Free drink with your ticket'
  add column loyalty_eligible   boolean not null default true,            -- false = tickets to this event never earn a loyalty point
  add column accessibility_notes text,
  add column publish_at         timestamptz;                              -- draft + publish_at = scheduled

alter table events
  add constraint events_links_is_array    check (jsonb_typeof(links) = 'array'),
  add constraint events_speakers_is_array check (jsonb_typeof(speakers) = 'array'),
  add constraint events_gallery_is_array  check (jsonb_typeof(gallery) = 'array'),
  add constraint events_perks_max_four    check (cardinality(perks) <= 4);

comment on column events.speakers is '[{name, role, bio, photo_url}] — photo_url is a full public URL from the event-images bucket.';
comment on column events.gallery  is '["https://…", …] — full public URLs from the event-images bucket.';
comment on column events.hero_image_path is 'Full public URL (event-images bucket). Named _path for historical reasons; the app and WordPress plugin both treat it as a URL.';
comment on column events.loyalty_eligible is 'Enforced by tickets_apply_event_loyalty_flag below: a ticket for an ineligible event is created with counts_toward_loyalty = false.';

create index events_highlight_idx on events (highlight) where highlight <> 'none' and status = 'published';
create index events_scheduled_idx on events (publish_at) where status = 'draft' and publish_at is not null;

-- ===========================================================================
-- 2. Club-wide defaults (so no price is hard-coded in app code)
-- ===========================================================================

create table club_settings (
  id                       integer primary key default 1 check (id = 1),
  default_ticket_template  jsonb not null,
  updated_at               timestamptz not null default now()
);

insert into club_settings (id, default_ticket_template) values (
  1,
  '[
    {"name": "Standard",   "audience": "public",      "price_minor": 1500, "requires_member": false},
    {"name": "Member",     "audience": "member",      "price_minor": 500,  "requires_member": true},
    {"name": "Concession", "audience": "concession",  "price_minor": 800,  "requires_member": false, "requires_proof": true}
  ]'::jsonb
);

create trigger club_settings_set_updated_at
  before update on club_settings
  for each row execute function set_updated_at();

alter table club_settings enable row level security;

create policy club_settings_staff_read on club_settings
  for select using (is_staff(auth.uid()));

create policy club_settings_admin_write on club_settings
  for all using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

-- ===========================================================================
-- 3. Permissions: staff can write events, with guard rails
-- ===========================================================================

drop policy events_admin_write on events;

create policy events_admin_all on events
  for all using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

create policy events_staff_insert on events
  for insert with check (is_staff(auth.uid()));

create policy events_staff_update on events
  for update using (is_staff(auth.uid())) with check (is_staff(auth.uid()));
-- deliberately no staff DELETE policy

drop policy ticket_types_admin_write on ticket_types;

create policy ticket_types_admin_all on ticket_types
  for all using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

-- Staff may add ticket types only while the event is still a draft…
create policy ticket_types_staff_insert on ticket_types
  for insert with check (
    is_staff(auth.uid())
    and exists (select 1 from events e where e.id = event_id and e.status = 'draft')
  );

create policy ticket_types_staff_update on ticket_types
  for update using (is_staff(auth.uid())) with check (is_staff(auth.uid()));

-- …and remove them only while the event is a draft (a used ticket type is
-- protected anyway: orders/tickets reference it, so the delete would fail).
create policy ticket_types_staff_delete on ticket_types
  for delete using (
    is_staff(auth.uid())
    and exists (select 1 from events e where e.id = event_id and e.status = 'draft')
  );

-- Staff may upload/replace event images (delete stays admin-only).
create policy event_images_staff_insert on storage.objects
  for insert with check (bucket_id = 'event-images' and is_staff(auth.uid()));

create policy event_images_staff_update on storage.objects
  for update using (bucket_id = 'event-images' and is_staff(auth.uid()));

-- Callers that are not a signed-in end user (service_role, the SQL editor,
-- pg_cron) are trusted: they either are the platform or already ran their
-- own checks in an Edge Function.
create or replace function is_trusted_db_caller()
returns boolean
language sql
stable
as $$
  select auth.role() = 'service_role' or auth.uid() is null;
$$;

-- ---------------------------------------------------------------------------
-- events: guard rails for non-admins, publish timestamp, created_by
-- ---------------------------------------------------------------------------
create or replace function guard_event_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_issued integer;
begin
  -- NB: OLD is unassigned in an INSERT trigger and PL/pgSQL does not
  -- guarantee `or` short-circuiting, so OLD is only ever touched inside an
  -- explicit `tg_op = 'UPDATE'` block.

  -- Stamp the moment an event goes live, for everyone.
  if new.status = 'published' then
    if tg_op = 'INSERT' then
      new.published_at := coalesce(new.published_at, now());
    elsif old.status is distinct from 'published' then
      new.published_at := coalesce(new.published_at, now());
    end if;
  end if;

  if tg_op = 'INSERT' and new.created_by is null then
    new.created_by := auth.uid();
  end if;

  -- Nobody may shrink capacity below tickets already sold. Only checked
  -- when capacity_total is actually being changed, so the 5-minute Eventbrite
  -- sync (which may legitimately report a sell-out) is never blocked.
  if tg_op = 'UPDATE' then
    if new.capacity_total is distinct from old.capacity_total then
      select count(*) into v_issued from tickets
        where event_id = new.id and status not in ('void', 'cancelled', 'refunded');
      if new.capacity_total < v_issued + new.eventbrite_sold then
        raise exception 'Capacity can''t be lower than the % tickets already sold.', v_issued + new.eventbrite_sold;
      end if;
    end if;
  end if;

  if is_trusted_db_caller() or is_admin(auth.uid()) then
    return new;
  end if;

  -- ---- staff (non-admin) rules from here on ----
  if tg_op = 'INSERT' then
    if new.status = 'cancelled' then
      raise exception 'Only an admin can cancel an event.';
    end if;
  else
    if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
      raise exception 'Only an admin can cancel an event.';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if old.status = 'cancelled' then
      raise exception 'Only an admin can change a cancelled event.';
    end if;

    if old.status = 'published' and (
         new.capacity_total      is distinct from old.capacity_total
      or new.capacity_app        is distinct from old.capacity_app
      or new.capacity_eventbrite is distinct from old.capacity_eventbrite
    ) then
      raise exception 'Capacity on a published event can only be changed by an admin.';
    end if;
  end if;

  return new;
end;
$$;

create trigger events_guard_changes
  before insert or update on events
  for each row execute function guard_event_changes();

-- Deleting an event that has orders would fail with a confusing foreign-key
-- error — say what to do instead.
create or replace function guard_event_delete()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if exists (select 1 from orders where event_id = old.id) then
    raise exception 'This event has orders, so it can''t be deleted. Cancel it instead.';
  end if;
  return old;
end;
$$;

create trigger events_guard_delete
  before delete on events
  for each row execute function guard_event_delete();

-- ---------------------------------------------------------------------------
-- ticket_types: price/quantity locked to admins once the event is published;
-- quantity can never drop below tickets already issued.
-- ---------------------------------------------------------------------------
create or replace function guard_ticket_type_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status event_status;
  v_issued integer;
begin
  if tg_op = 'UPDATE' then
    select count(*) into v_issued from tickets
      where ticket_type_id = new.id and status not in ('void', 'cancelled', 'refunded');
    if new.quantity < v_issued then
      raise exception 'Only % of this ticket type can be sold, but % are already issued.', new.quantity, v_issued;
    end if;
  end if;

  if is_trusted_db_caller() or is_admin(auth.uid()) then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    select status into v_status from events where id = new.event_id;
    if v_status <> 'draft' and (
         new.price_minor is distinct from old.price_minor
      or new.quantity   is distinct from old.quantity
      or new.currency   is distinct from old.currency
    ) then
      raise exception 'Price and quantity on a published event can only be changed by an admin.';
    end if;
  end if;

  return new;
end;
$$;

create trigger ticket_types_guard_changes
  before insert or update on ticket_types
  for each row execute function guard_ticket_type_changes();

-- ---------------------------------------------------------------------------
-- Loyalty: an event marked loyalty_eligible = false never awards points.
-- Done as a trigger on ticket creation so mark_order_paid() needn't change.
-- ---------------------------------------------------------------------------
create or replace function tickets_apply_event_loyalty_flag()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not coalesce((select loyalty_eligible from events where id = new.event_id), true) then
    new.counts_toward_loyalty := false;
  end if;
  return new;
end;
$$;

create trigger tickets_event_loyalty_flag
  before insert on tickets
  for each row execute function tickets_apply_event_loyalty_flag();

-- ===========================================================================
-- 4. Audit trail for event changes (append-only audit_log, written by a
--    trigger so it cannot be skipped by a client).
-- ===========================================================================

create or replace function audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_entity  text   := tg_argv[0];
  v_ignore  text[] := string_to_array(coalesce(tg_argv[1], ''), ',');
  v_id      uuid;
  v_before  jsonb;
  v_after   jsonb;
begin
  if tg_op = 'INSERT' then
    v_id := new.id;
    v_after := to_jsonb(new);
  elsif tg_op = 'DELETE' then
    v_id := old.id;
    v_before := to_jsonb(old);
  else
    v_id := new.id;
    -- Record only the columns that actually changed, and ignore machine-
    -- written noise (updated_at, the 5-minute Eventbrite sync counters).
    select coalesce(jsonb_object_agg(n.key, o.value), '{}'::jsonb),
           coalesce(jsonb_object_agg(n.key, n.value), '{}'::jsonb)
      into v_before, v_after
      from jsonb_each(to_jsonb(new)) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
      where n.value is distinct from o.value
        and n.key <> all (v_ignore);
    if v_after = '{}'::jsonb then
      return new;
    end if;
  end if;

  insert into audit_log (actor_id, action, entity, entity_id, before, after)
  values (auth.uid(), v_entity || '.' || lower(tg_op), v_entity, v_id, v_before, v_after);

  -- (NEW is unassigned on DELETE, so don't coalesce(new, old).)
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger events_audit
  after insert or update or delete on events
  for each row execute function audit_row_change('event', 'updated_at,eventbrite_sold,eventbrite_synced_at');

create trigger ticket_types_audit
  after insert or update or delete on ticket_types
  for each row execute function audit_row_change('ticket_type', 'updated_at');

-- ===========================================================================
-- 5. Scheduled publishing (plain SQL — no Edge Function or Vault secret needed)
-- ===========================================================================

select cron.schedule(
  'publish-scheduled-events',
  '* * * * *',
  $$
  update events
     set status = 'published'
   where status = 'draft'
     and publish_at is not null
     and publish_at <= now();
  $$
);

-- ===========================================================================
-- 6. "Selling fast": derived, never stored. Exposes only event ids, not counts.
-- ===========================================================================

create or replace function events_selling_fast()
returns setof uuid
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select e.id
  from events e
  cross join lateral (
    select count(*)::integer as issued
    from tickets t
    where t.event_id = e.id and t.status not in ('void', 'cancelled', 'refunded')
  ) s
  where e.status = 'published'
    and e.starts_at > now()
    and e.capacity_total > 0
    and (s.issued + e.eventbrite_sold) >= e.capacity_total * 0.75   -- 75% or more sold…
    and (s.issued + e.eventbrite_sold) <  e.capacity_total;         -- …and not sold out
$$;

grant execute on function events_selling_fast() to anon, authenticated;

-- ===========================================================================
-- 7. Push notifications
-- ===========================================================================

create type push_kind     as enum ('new_event', 'recommendation', 'event_update', 'announcement');
create type push_audience as enum ('all', 'members', 'ticket_holders');

create table device_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  token         text not null unique,
  platform      text not null check (platform in ('android', 'ios', 'web')),
  app_version   text,
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);

create index device_tokens_user_idx on device_tokens (user_id);

alter table device_tokens enable row level security;

create policy device_tokens_owner_read on device_tokens
  for select using (auth.uid() = user_id);
-- No client INSERT/UPDATE/DELETE: a token can move between accounts on a
-- shared phone, which an owner-only policy can't express — use the RPCs below.

create or replace function register_device_token(p_token text, p_platform text, p_app_version text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to turn on notifications.';
  end if;
  insert into device_tokens (user_id, token, platform, app_version)
  values (auth.uid(), p_token, p_platform, p_app_version)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        app_version = excluded.app_version,
        last_seen_at = now();
end;
$$;

create or replace function unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from device_tokens where token = p_token and user_id = auth.uid();
$$;

grant execute on function register_device_token(text, text, text) to authenticated;
grant execute on function unregister_device_token(text) to authenticated;

create table notification_preferences (
  user_id          uuid primary key references profiles(id) on delete cascade,
  new_events       boolean not null default true,    -- "a new event has been announced"
  recommendations  boolean not null default true,    -- FC Recommends / special offers / announcements
  loyalty          boolean not null default true,    -- "you've earned a free ticket"
  updated_at       timestamptz not null default now()
);

create trigger notification_preferences_set_updated_at
  before update on notification_preferences
  for each row execute function set_updated_at();

alter table notification_preferences enable row level security;

create policy notification_preferences_owner on notification_preferences
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Changes to an event you hold a ticket for (cancelled, moved…) are
-- transactional and are not switchable — only push_opt_in itself stops them.

create table push_campaigns (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid references events(id) on delete set null,
  kind        push_kind not null,
  audience    push_audience not null,
  title       text not null check (char_length(title) between 1 and 65),
  body        text not null check (char_length(body) between 1 and 240),
  status      text not null default 'sending' check (status in ('sending', 'sent', 'failed')),
  recipients  integer not null default 0,
  delivered   integer not null default 0,
  failed      integer not null default 0,
  error       text,
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);

create index push_campaigns_created_idx on push_campaigns (created_at desc);
create index push_campaigns_event_idx on push_campaigns (event_id);

alter table push_campaigns enable row level security;

create policy push_campaigns_staff_read on push_campaigns
  for select using (is_staff(auth.uid()));
-- Written only by the send-push Edge Function (service_role).

-- Who should receive a campaign. Service-role only: it joins tokens to
-- profiles, so it must never be callable from a client.
create or replace function push_recipient_tokens(p_audience push_audience, p_event_id uuid, p_kind push_kind)
returns table (user_id uuid, token text)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select distinct d.user_id, d.token
  from device_tokens d
  join profiles p on p.id = d.user_id and p.deleted_at is null and p.push_opt_in
  left join notification_preferences np on np.user_id = p.id
  where
    (p_audience <> 'members' or (
        p.member_status = 'active'
        and (p.membership_expires_at is null or p.membership_expires_at > now())
    ))
    and (p_audience <> 'ticket_holders' or exists (
        select 1 from tickets t
        where t.event_id = p_event_id and t.user_id = p.id and t.status = 'valid'
    ))
    and case p_kind
          when 'new_event'      then coalesce(np.new_events, true)
          when 'recommendation' then coalesce(np.recommendations, true)
          when 'announcement'   then coalesce(np.recommendations, true)
          else true                                                     -- event_update: transactional
        end;
$$;

revoke all on function push_recipient_tokens(push_audience, uuid, push_kind) from public, anon, authenticated;
grant execute on function push_recipient_tokens(push_audience, uuid, push_kind) to service_role;
