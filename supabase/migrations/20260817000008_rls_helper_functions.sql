-- Helper functions used throughout RLS policies. SECURITY DEFINER with an
-- explicitly pinned search_path — an unpinned search_path on a security
-- definer function is a classic privilege-escalation hole (a malicious
-- session could shadow a table/function earlier in an unpinned path).

create or replace function is_admin(p_uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from profiles where id = p_uid and role = 'admin' and deleted_at is null
  );
$$;

create or replace function is_staff(p_uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from profiles
    where id = p_uid and role in ('staff', 'admin') and deleted_at is null
  );
$$;

create or replace function is_active_member(p_uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from profiles
    where id = p_uid
      and member_status = 'active'
      and deleted_at is null
      and (membership_expires_at is null or membership_expires_at > now())
  );
$$;

comment on function is_admin(uuid) is 'Used in RLS policies and privileged Edge Function checks. Never trust a client-supplied role claim instead of this.';
comment on function is_staff(uuid) is 'True for staff AND admin (roles are additive, briefing §4).';
comment on function is_active_member(uuid) is 'Re-checks expiry live — a lapsed membership stops counting immediately, no separate cron needed for this check.';
