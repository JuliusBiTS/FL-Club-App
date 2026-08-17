-- Account deletion — briefing §9.10. The delete-account Edge Function does
-- the immediate anonymisation + GoTrue soft-delete; this migration only
-- adds what a Postgres function does better than the Edge Function could:
-- finding accounts whose 30-day grace window has passed, so
-- purge-deleted-accounts can hard-delete them. auth.users is queried here
-- (not from the Edge Function's JS client, which only sees the public
-- schema by default) via a security definer function.

create or replace function find_accounts_pending_purge(p_grace_days integer default 30)
returns table (user_id uuid)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select id from auth.users
  where deleted_at is not null
    and deleted_at < now() - (p_grace_days || ' days')::interval;
$$;

select cron.schedule(
  'purge-deleted-accounts',
  '0 5 * * *',   -- once daily; deletions are not time-sensitive to the minute
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/purge-deleted-accounts',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'Content-Type', 'application/json'
               ),
    body    := '{}'::jsonb
  );
  $$
);
