-- User registration data + "register interest" — first stepping stone for
-- the user site (the same tables serve the app and a future website: both
-- sign in through Supabase Auth and read/write the same rows under RLS).
--
-- 1. profiles (which already had phone, terms_accepted_at and
--    privacy_accepted_at) gets the further personal details a registered person can save about
--    themselves, plus recorded consent. Users can edit these freely: the
--    guard trigger (20260817000009) protects only the privileged columns,
--    so anything added here is self-editable by default.
-- 2. event_interests lets a signed-in person (or, via a function, a guest
--    with an email) say "I'm interested" in an event — before tickets are
--    on sale, for a sold-out event, or just to be kept posted.

-- ---------------------------------------------------------------- profiles

alter table profiles
  add column city                 text,
  add column country              text,
  add column interests            text[] not null default '{}',   -- topics/regions they follow, free text chips
  add column how_heard            text,
  add column privacy_version      text,                           -- which policy text they accepted
  add column marketing_consent_at timestamptz,                    -- when marketing_opt_in was last switched on
  add column registration_source  text check (registration_source in ('app', 'web', 'staff')),
  add column profile_completed_at timestamptz;

alter table profiles
  add constraint profiles_phone_len     check (phone is null or char_length(phone) <= 30),
  add constraint profiles_city_len      check (city is null or char_length(city) <= 100),
  add constraint profiles_country_len   check (country is null or char_length(country) <= 100),
  add constraint profiles_how_heard_len check (how_heard is null or char_length(how_heard) <= 200),
  add constraint profiles_interests_max check (coalesce(array_length(interests, 1), 0) <= 20);

-- Keep marketing_consent_at honest: stamped by the database whenever the
-- opt-in flips on, cleared when it flips off, so the record can't be
-- forgotten by (or forged from) a client.
create or replace function stamp_marketing_consent()
returns trigger
language plpgsql
as $$
begin
  if new.marketing_opt_in is distinct from old.marketing_opt_in then
    new.marketing_consent_at := case when new.marketing_opt_in then now() else null end;
  end if;
  return new;
end;
$$;

create trigger profiles_stamp_marketing_consent
  before update on profiles
  for each row execute function stamp_marketing_consent();

-- ---------------------------------------------------------- event_interests

create table event_interests (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references events(id) on delete cascade,
  user_id     uuid references profiles(id) on delete cascade,   -- null for a guest
  email       text,                                             -- required for a guest
  full_name   text,
  note        text,
  created_at  timestamptz not null default now(),
  notified_at timestamptz,                                      -- set when we've told them (tickets on sale, etc.)
  constraint event_interests_who check (user_id is not null or email is not null),
  constraint event_interests_email_len check (email is null or (char_length(email) <= 254 and email like '%_@_%.__%')),
  constraint event_interests_name_len check (full_name is null or char_length(full_name) <= 200),
  constraint event_interests_note_len check (note is null or char_length(note) <= 500)
);

-- One row per person per event, whether they signed in or gave an email.
create unique index event_interests_one_per_user  on event_interests (event_id, user_id) where user_id is not null;
create unique index event_interests_one_per_email on event_interests (event_id, lower(email)) where email is not null;
create index event_interests_event_idx on event_interests (event_id, created_at desc);

alter table event_interests enable row level security;

create policy event_interests_own_read on event_interests
  for select using (auth.uid() = user_id);

create policy event_interests_own_insert on event_interests
  for insert with check (auth.uid() = user_id);

create policy event_interests_own_delete on event_interests
  for delete using (auth.uid() = user_id);

create policy event_interests_staff_read on event_interests
  for select using (is_staff(auth.uid()));

-- Guests have no session, so they go through this function instead of the
-- table: published, upcoming events only, and a crude flood cap so a script
-- can't fill an event's list (the unique index already stops repeats of the
-- same address).
create or replace function register_event_interest(p_event_id uuid, p_email text, p_name text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recent integer;
begin
  if not exists (
    select 1 from events where id = p_event_id and status = 'published' and starts_at > now()
  ) then
    raise exception 'That event isn''t open for registering interest.';
  end if;

  select count(*) into v_recent
  from event_interests
  where event_id = p_event_id and user_id is null and created_at > now() - interval '1 hour';
  if v_recent >= 100 then
    raise exception 'Lots of people are registering right now — please try again in a little while.';
  end if;

  insert into event_interests (event_id, email, full_name)
  values (p_event_id, lower(trim(p_email)), nullif(trim(p_name), ''))
  on conflict do nothing;   -- already registered: quietly succeed
end;
$$;

grant execute on function register_event_interest(uuid, text, text) to anon, authenticated;

-- How many people are interested — ids and counts only, so the app can show
-- "N interested" without exposing anyone's details.
create or replace function event_interest_counts()
returns table (event_id uuid, interested integer)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select ei.event_id, count(*)::integer
  from event_interests ei
  join events e on e.id = ei.event_id
  where e.status = 'published' and e.starts_at > now()
  group by ei.event_id;
$$;

grant execute on function event_interest_counts() to anon, authenticated;
