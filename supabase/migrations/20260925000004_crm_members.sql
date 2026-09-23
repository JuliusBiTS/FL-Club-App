-- Membership source-of-truth link (SHEEP CRM, or any CRM/CSV export).
--
-- The club keeps its real member list in SHEEP. The app must only treat
-- someone as a member if that list says so. This migration adds the
-- vendor-neutral half:
--
--   crm_members       staging copy of the CRM's member records (written only
--                     by the crm-sync Edge Function / service role)
--   crm_sync_runs     one row per sync attempt, for the admin console
--   crm_reconcile_preview()   what WOULD change — read-only, admin only
--   crm_reconcile_apply()     makes those changes, audited, admin only
--
-- Design rules (see docs/DECISIONS.md, membership decisions stay in force):
--   * Nothing here lets a user grant themselves membership — the profiles
--     guard trigger still blocks it, and the crm_* link columns are added to
--     that guard below.
--   * Applying is always a separate, deliberate step after previewing.
--   * A CRM that says "lapsed" lapses someone; a person who is simply absent
--     from the CRM is only FLAGGED, never changed — honorary/lifetime and
--     hand-granted members may legitimately not be in it.
--   * Suspended stays suspended (that's an admin decision, not the CRM's).

-- --------------------------------------------------------- profile linkage

alter table profiles
  add column crm_member_id text unique,
  add column crm_synced_at timestamptz;

create or replace function guard_profile_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.role() <> 'service_role' and not is_admin(auth.uid()) then
    if new.role                    is distinct from old.role
      or new.member_status         is distinct from old.member_status
      or new.membership_kind       is distinct from old.membership_kind
      or new.membership_number     is distinct from old.membership_number
      or new.membership_pin        is distinct from old.membership_pin
      or new.membership_expires_at is distinct from old.membership_expires_at
      or new.membership_started_at is distinct from old.membership_started_at
      or new.membership_photo_path is distinct from old.membership_photo_path
      or new.membership_notes      is distinct from old.membership_notes
      or new.crm_member_id         is distinct from old.crm_member_id
      or new.crm_synced_at         is distinct from old.crm_synced_at
    then
      raise exception 'privileged column modification denied';
    end if;
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------ staging table

create table crm_members (
  id                uuid primary key default gen_random_uuid(),
  source            text not null default 'sheep',
  external_id       text not null,                 -- the CRM's own id for this member
  email             text,
  full_name         text,
  status            text not null check (status in ('active', 'lapsed', 'cancelled', 'unknown')),
  membership_kind   text,                          -- 'full' | 'honorary' | 'lifetime' when it maps cleanly
  membership_number text,
  started_at        timestamptz,
  expires_at        timestamptz,
  raw               jsonb,                         -- the CRM's record as received, for debugging mappings
  synced_at         timestamptz not null default now(),
  unique (source, external_id)
);

create index crm_members_email_idx on crm_members (lower(email));

alter table crm_members enable row level security;
create policy crm_members_admin_read on crm_members for select using (is_admin(auth.uid()));
-- No insert/update/delete policies: only the service role (Edge Function) writes.

create table crm_sync_runs (
  id          uuid primary key default gen_random_uuid(),
  source      text not null default 'sheep',
  trigger     text not null check (trigger in ('manual', 'scheduled', 'import')),
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  fetched     integer,
  status      text not null default 'running' check (status in ('running', 'ok', 'failed')),
  error       text,
  applied     boolean not null default false,
  summary     jsonb,
  created_by  uuid references profiles(id)
);

alter table crm_sync_runs enable row level security;
create policy crm_sync_runs_admin_read on crm_sync_runs for select using (is_admin(auth.uid()));

-- ---------------------------------------------------------- reconciliation

-- One row per profile-or-CRM-record that needs a decision. `action`:
--   activate       CRM says active, profile isn't (and isn't suspended)
--   lapse          CRM says lapsed/cancelled, profile is active
--   update_expiry  both active, expiry dates differ
--   link           matched by email, not yet linked to a CRM id (no status change)
--   not_in_crm     profile is active but the CRM has no record — FLAG ONLY
--   unmatched_crm  CRM member with no app account yet — informational
--   none           already in agreement
create or replace function crm_reconcile_preview()
returns table (
  action        text,
  profile_id    uuid,
  crm_id        uuid,
  email         text,
  profile_status text,
  crm_status    text,
  profile_expires_at timestamptz,
  crm_expires_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
begin
  if auth.role() <> 'service_role' and not is_admin(auth.uid()) then
    raise exception 'Admins only.';
  end if;

  return query
  with matched as (
    select p.id as pid, p.email as pemail, p.member_status::text as pstatus, p.membership_expires_at as pexp,
           p.crm_member_id as plink, c.id as cid, c.status as cstatus, c.expires_at as cexp, c.external_id as cext
    from profiles p
    join crm_members c
      on (p.crm_member_id is not null and p.crm_member_id = c.external_id)
      or (p.crm_member_id is null and c.email is not null and lower(p.email) = lower(c.email))
  )
  select
    case
      when m.pstatus = 'suspended' then 'none'
      when m.cstatus = 'active' and m.pstatus <> 'active' then 'activate'
      when m.cstatus in ('lapsed', 'cancelled') and m.pstatus = 'active' then 'lapse'
      when m.cstatus = 'active' and m.pstatus = 'active' and m.pexp is distinct from m.cexp and m.cexp is not null then 'update_expiry'
      when m.plink is null then 'link'
      else 'none'
    end,
    m.pid, m.cid, m.pemail, m.pstatus, m.cstatus, m.pexp, m.cexp
  from matched m

  union all
  -- Active in the app but nowhere in the CRM: flag, never auto-change.
  select 'not_in_crm', p.id, null::uuid, p.email, p.member_status::text, null::text, p.membership_expires_at, null::timestamptz
  from profiles p
  where p.member_status = 'active'
    and not exists (
      select 1 from crm_members c
      where (p.crm_member_id is not null and p.crm_member_id = c.external_id)
         or (c.email is not null and lower(p.email) = lower(c.email))
    )

  union all
  -- In the CRM with no app account yet.
  select 'unmatched_crm', null::uuid, c.id, c.email, null::text, c.status, null::timestamptz, c.expires_at
  from crm_members c
  where not exists (
    select 1 from profiles p
    where (p.crm_member_id is not null and p.crm_member_id = c.external_id)
       or (c.email is not null and lower(p.email) = lower(c.email))
  );
end;
$$;

-- Applies the four state-changing actions above (never not_in_crm /
-- unmatched_crm / none). Returns how many profiles changed. Every change is
-- written to audit_log with before/after.
create or replace function crm_reconcile_apply()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_changed integer := 0;
  v_actor uuid := auth.uid();   -- null when run by the service role
begin
  if auth.role() <> 'service_role' and not is_admin(auth.uid()) then
    raise exception 'Admins only.';
  end if;

  for r in select * from crm_reconcile_preview() where action in ('activate', 'lapse', 'update_expiry', 'link') loop
    declare
      v_before jsonb;
      v_c crm_members%rowtype;
    begin
      select * into v_c from crm_members where id = r.crm_id;
      select jsonb_build_object('member_status', member_status, 'membership_expires_at', membership_expires_at,
                                'crm_member_id', crm_member_id)
        into v_before from profiles where id = r.profile_id;

      update profiles set
        crm_member_id = v_c.external_id,
        crm_synced_at = now(),
        member_status = case r.action
                          when 'activate' then 'active'::member_status
                          when 'lapse'    then 'lapsed'::member_status
                          else member_status
                        end,
        membership_expires_at = case when r.action in ('activate', 'update_expiry') then v_c.expires_at
                                     else membership_expires_at end,
        membership_started_at = case when r.action = 'activate' then coalesce(membership_started_at, v_c.started_at)
                                     else membership_started_at end,
        membership_number = coalesce(membership_number, v_c.membership_number),
        membership_kind = case
                            when r.action = 'activate' and membership_kind is null
                                 and v_c.membership_kind in ('full', 'honorary', 'lifetime')
                              then v_c.membership_kind::membership_kind
                            else membership_kind
                          end
      where id = r.profile_id;

      insert into audit_log (actor_id, action, entity, entity_id, before, after)
      values (v_actor, 'membership.crm_' || r.action, 'profiles', r.profile_id, v_before,
              jsonb_build_object('crm_status', r.crm_status, 'crm_expires_at', r.crm_expires_at, 'source', v_c.source));
      v_changed := v_changed + 1;
    end;
  end loop;

  return v_changed;
end;
$$;

grant execute on function crm_reconcile_preview() to authenticated;
grant execute on function crm_reconcile_apply() to authenticated;
