-- Row Level Security. Enabled on every single table, no exceptions — a
-- table with RLS on and no policy denies everything, which is the safe
-- default we rely on. Client-side role checks in the app are for UX only
-- (hiding buttons) and are assumed bypassable; this file is the only real
-- authorisation boundary.
--
-- service_role (used exclusively by Edge Functions, never shipped to any
-- client) bypasses RLS entirely — that is standard Supabase behaviour, not
-- something configured here. Tables below therefore only need SELECT
-- policies for end users/staff/admin; INSERT/UPDATE/DELETE happen through
-- Edge Functions unless a table is explicitly safe for direct client writes
-- (profiles' own safe columns, playback_progress).

-- ============================================================ profiles ===
alter table profiles enable row level security;

create policy profiles_self_read on profiles
  for select using (auth.uid() = id);

create policy profiles_admin_read on profiles
  for select using (is_admin(auth.uid()));

-- Users may update their own row, but privileged columns are excluded by
-- the guard trigger below — RLS alone cannot express "this column is
-- read-only", so we use USING/CHECK for row ownership and a trigger for
-- column-level protection.
create policy profiles_self_update on profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

create policy profiles_admin_update on profiles
  for update using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

-- HARD RULE (briefing §4): membership can only ever be granted server-side
-- by an admin. There is no code path — API, client, deep link, or
-- otherwise — by which a user can set their own member_status. This
-- trigger is what actually enforces it; the RLS policy above only checks
-- row ownership, not which columns changed.
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
    then
      raise exception 'privileged column modification denied';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_guard_privileged_columns
  before update on profiles
  for each row execute function guard_profile_privileged_columns();

-- ============================================================== events ===
alter table events enable row level security;

create policy events_public_read on events
  for select using (status = 'published');

create policy events_staff_read on events
  for select using (is_staff(auth.uid()));

create policy events_admin_write on events
  for all using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

-- ========================================================= ticket_types ===
alter table ticket_types enable row level security;

create policy ticket_types_public_read on ticket_types
  for select using (
    is_active
    and exists (select 1 from events e where e.id = event_id and e.status = 'published')
  );

create policy ticket_types_staff_read on ticket_types
  for select using (is_staff(auth.uid()));

create policy ticket_types_admin_write on ticket_types
  for all using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

-- ================================================================ orders ==
alter table orders enable row level security;

create policy orders_owner_read on orders
  for select using (auth.uid() = user_id);

create policy orders_staff_read on orders
  for select using (is_staff(auth.uid()));

-- No INSERT/UPDATE/DELETE policy at all: orders are created and mutated
-- exclusively by the create-order and stripe-webhook Edge Functions running
-- as service_role (T7/T8 in the threat model).

-- =============================================================== tickets ==
alter table tickets enable row level security;

create policy tickets_owner_read on tickets
  for select using (auth.uid() = user_id);

create policy tickets_staff_read on tickets
  for select using (is_staff(auth.uid()));

-- No INSERT/UPDATE/DELETE policy: tickets are created by stripe-webhook and
-- redeemed by verify-scan, both service_role only. The app never creates a
-- ticket, ever (briefing §9.3 step 5).

-- ==================================================== processed_webhooks ==
alter table processed_webhooks enable row level security;
-- No policies at all: only service_role (bypassing RLS) ever touches this.

-- ==================================================== rate_limit_counters =
alter table rate_limit_counters enable row level security;
-- No policies at all: only service_role touches this.

-- ========================================================= loyalty_ledger =
alter table loyalty_ledger enable row level security;

create policy loyalty_ledger_owner_read on loyalty_ledger
  for select using (auth.uid() = user_id);

create policy loyalty_ledger_staff_read on loyalty_ledger
  for select using (is_staff(auth.uid()));

-- No client writes: award_loyalty_for_ticket / reverse_loyalty_for_refunded_ticket
-- and manual admin adjustments all run through service_role Edge Functions,
-- which additionally write an audit_log row for manual adjustments.

-- ======================================================== loyalty_rewards =
alter table loyalty_rewards enable row level security;

create policy loyalty_rewards_owner_read on loyalty_rewards
  for select using (auth.uid() = user_id);

create policy loyalty_rewards_staff_read on loyalty_rewards
  for select using (is_staff(auth.uid()));

-- ========================================================= loyalty_config =
alter table loyalty_config enable row level security;

create policy loyalty_config_public_read on loyalty_config
  for select using (true);   -- non-sensitive: threshold/rules copy shown pre-sign-in

create policy loyalty_config_admin_write on loyalty_config
  for update using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

-- ================================================= membership_applications =
alter table membership_applications enable row level security;

create policy membership_applications_owner_read on membership_applications
  for select using (auth.uid() = user_id);

create policy membership_applications_admin_all on membership_applications
  for all using (is_admin(auth.uid())) with check (is_admin(auth.uid()));

-- No direct client INSERT policy: applications are created by the
-- membership-apply Edge Function (service_role), which also enforces the
-- 3/hour/user rate limit — see §13.7.

-- ======================================================= podcast_episodes =
alter table podcast_episodes enable row level security;

create policy podcast_episodes_public_read on podcast_episodes
  for select using (true);   -- podcast requires no account, briefing §9.8

-- ======================================================= playback_progress =
alter table playback_progress enable row level security;

create policy playback_progress_owner_all on playback_progress
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ================================================================ articles =
alter table articles enable row level security;

create policy articles_public_read on articles
  for select using (true);   -- news/blog is public, briefing §9.9

-- ============================================================= scan_events =
alter table scan_events enable row level security;

create policy scan_events_staff_read on scan_events
  for select using (is_staff(auth.uid()));

-- No client INSERT policy: written by verify-scan / get-scan-pack sync,
-- service_role only. Already append-only at the table level (see
-- 20260817000006).

-- =============================================================== audit_log =
alter table audit_log enable row level security;

create policy audit_log_admin_read on audit_log
  for select using (is_admin(auth.uid()));

-- No client INSERT policy: every privileged Edge Function writes its own
-- audit_log row as service_role after completing its mutation.
