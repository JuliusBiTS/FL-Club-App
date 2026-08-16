-- Rate limiting backing store for Edge Functions (§13.7). Free — no
-- external rate-limiting service needed at this scale. Each Edge Function
-- calls check_rate_limit() with its own key/limit/window before doing
-- anything expensive or privileged.

create table rate_limit_counters (
  key           text primary key,     -- e.g. 'create-order:<user_id>', 'password-reset:<email>'
  window_start  timestamptz not null default now(),
  count         integer not null default 0
);

-- Atomic check-and-increment: a single INSERT ... ON CONFLICT DO UPDATE
-- avoids the read-then-write race a SELECT + UPDATE pair would have under
-- concurrent requests for the same key.
create or replace function check_rate_limit(p_key text, p_max integer, p_window interval)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row rate_limit_counters%rowtype;
begin
  insert into rate_limit_counters (key, window_start, count)
  values (p_key, now(), 1)
  on conflict (key) do update
    set count        = case when rate_limit_counters.window_start < now() - p_window
                             then 1
                             else rate_limit_counters.count + 1 end,
        window_start  = case when rate_limit_counters.window_start < now() - p_window
                              then now()
                              else rate_limit_counters.window_start end
  returning * into v_row;

  return v_row.count <= p_max;
end;
$$;

comment on function check_rate_limit(text, integer, interval) is
  'Returns true if the call is within limit (and counts it), false if it should be rejected. Callers: create-order 10/min/user, membership-apply 3/hour/user, password reset 5/hour/email, scan verification 60/min/device.';

-- Prevent unbounded growth — stale counters are safe to discard.
select cron.schedule(
  'rate-limit-counters-cleanup',
  '0 4 * * *',
  $$ delete from rate_limit_counters where window_start < now() - interval '2 days' $$
);
