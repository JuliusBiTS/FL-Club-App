-- Scheduled Edge Function invocations via pg_cron + pg_net.
--
-- SETUP REQUIRED AFTER FIRST DEPLOY (cannot be done from a migration, these
-- are project-specific secrets): in the Supabase SQL editor, run
--
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service_role_key>', 'service_role_key');
--
-- Until those two Vault secrets exist, the jobs below no-op with an error
-- that is harmless (net.http_post fails, cron logs it, nothing else
-- happens) but should be checked in Supabase's cron job log after setup.

create extension if not exists pg_net;

-- A pending order holds its stock for 15 minutes (briefing §9.3). Without
-- this job, abandoned checkouts would silently sell out an event.
select cron.schedule(
  'expire-pending-orders',
  '*/5 * * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/expire-pending-orders',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'Content-Type', 'application/json'
               ),
    body    := '{}'::jsonb
  );
  $$
);

-- Direction of truth is Eventbrite -> app, read-only (briefing §11.2). Never write to Eventbrite.
select cron.schedule(
  'eventbrite-sync',
  '*/5 * * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/eventbrite-sync',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'Content-Type', 'application/json'
               ),
    body    := '{}'::jsonb
  );
  $$
);

select cron.schedule(
  'podcast-sync',
  '17 * * * *',   -- hourly, off the top of the hour to avoid every cron piling up at :00
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/podcast-sync',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'Content-Type', 'application/json'
               ),
    body    := '{}'::jsonb
  );
  $$
);

select cron.schedule(
  'wordpress-sync',
  '32 * * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/wordpress-sync',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'Content-Type', 'application/json'
               ),
    body    := '{}'::jsonb
  );
  $$
);
