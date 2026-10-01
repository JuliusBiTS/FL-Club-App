-- Saved events, per-event "notify me", reminders, and "a place opened up" alerts
-- for people on a sold-out event's waiting list.
--
-- Saved is the superset: turning the bell on saves the event too; un-saving
-- removes the row (and so the reminders). One row per person per event.

create table event_favourites (
  user_id    uuid not null references profiles(id) on delete cascade,
  event_id   uuid not null references events(id) on delete cascade,
  notify     boolean not null default false,   -- "remind me" (a day before and an hour before)
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

create index event_favourites_notify_idx on event_favourites (event_id) where notify;

alter table event_favourites enable row level security;

create policy event_favourites_own_read   on event_favourites for select using (auth.uid() = user_id);
create policy event_favourites_own_insert on event_favourites for insert with check (auth.uid() = user_id);
create policy event_favourites_own_update on event_favourites for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy event_favourites_own_delete on event_favourites for delete using (auth.uid() = user_id);

-- Which reminders have gone out, so a retried/overlapping run never double-sends.
create table event_reminders_sent (
  event_id uuid not null references events(id) on delete cascade,
  user_id  uuid not null references profiles(id) on delete cascade,
  kind     text not null check (kind in ('day_before', 'hour_before')),
  sent_at  timestamptz not null default now(),
  primary key (event_id, user_id, kind)
);

alter table event_reminders_sent enable row level security;   -- service role only: no policies


-- Who should get which reminder right now. Windows are deliberately a little
-- wide (the job runs every 15 minutes and the table above de-duplicates), so a
-- missed run doesn't lose a reminder. Honours the global push switch only —
-- turning the bell on for an event is itself the explicit opt-in.
create or replace function event_reminder_targets(p_kind text)
returns table (user_id uuid, token text, event_id uuid, slug text, title text, starts_at timestamptz, has_ticket boolean)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select distinct f.user_id, d.token, e.id, e.slug, e.title, e.starts_at,
         exists (select 1 from tickets t where t.event_id = e.id and t.user_id = f.user_id and t.status in ('valid', 'redeemed'))
  from event_favourites f
  join events e on e.id = f.event_id and e.status = 'published'
  join profiles p on p.id = f.user_id and p.deleted_at is null and p.push_opt_in
  join device_tokens d on d.user_id = f.user_id
  where f.notify
    and not exists (select 1 from event_reminders_sent s where s.event_id = e.id and s.user_id = f.user_id and s.kind = p_kind)
    and case p_kind
          when 'day_before'  then e.starts_at between now() + interval '22 hours' and now() + interval '26 hours'
          when 'hour_before' then e.starts_at between now() + interval '30 minutes' and now() + interval '90 minutes'
          else false
        end;
$$;

-- Signed-in waiting-list people whose event now has room again.
create or replace function waitlist_alert_targets()
returns table (user_id uuid, token text, event_id uuid, slug text, title text)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select distinct i.user_id, d.token, e.id, e.slug, e.title
  from event_interests i
  join events e on e.id = i.event_id and e.status = 'published' and e.starts_at > now()
  join profiles p on p.id = i.user_id and p.deleted_at is null and p.push_opt_in
  join device_tokens d on d.user_id = i.user_id
  where i.user_id is not null
    and i.notified_at is null
    and e.id not in (select events_sold_out())
    and exists (select 1 from ticket_types t where t.event_id = e.id and t.quantity > 0);
$$;

revoke all on function event_reminder_targets(text) from public, anon, authenticated;
revoke all on function waitlist_alert_targets() from public, anon, authenticated;
grant execute on function event_reminder_targets(text) to service_role;
grant execute on function waitlist_alert_targets() to service_role;

-- Every 15 minutes. Needs the two Vault secrets described in
-- 20260817000011_scheduled_jobs.sql (project_url, service_role_key).
select cron.schedule(
  'send-event-reminders',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-event-reminders',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'Content-Type', 'application/json'
               ),
    body    := '{}'::jsonb
  );
  $$
);
