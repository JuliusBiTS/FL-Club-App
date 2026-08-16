-- Extensions and generic utilities shared by every later migration.

create extension if not exists pgcrypto;   -- gen_random_uuid(), gen_random_bytes()
create extension if not exists pg_cron;    -- scheduled Edge Function triggers (inventory hold expiry, syncs)

-- Every mutable table gets updated_at maintained here rather than in application code,
-- so it is impossible for a write path to forget it.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function set_updated_at() is
  'Generic BEFORE UPDATE trigger: stamps updated_at = now() on every row change.';
