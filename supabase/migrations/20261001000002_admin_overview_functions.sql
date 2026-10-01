-- Read-only numbers for the admin console and the door scanner. All of them are
-- security-definer functions that check the caller's role themselves, so the
-- raw tables stay locked down; none of them changes any data.

-- Per-event sales overview (admins only — it contains revenue).
create or replace function event_sales_overview(p_event_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v jsonb;
begin
  if not is_admin(auth.uid()) then
    raise exception 'Admins only.';
  end if;

  select jsonb_build_object(
    'event', (
      select jsonb_build_object(
        'title', e.title, 'starts_at', e.starts_at, 'status', e.status,
        'capacity_total', e.capacity_total, 'capacity_app', e.capacity_app, 'eventbrite_sold', e.eventbrite_sold)
      from events e where e.id = p_event_id
    ),
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', tt.id, 'name', tt.name, 'price_minor', tt.price_minor, 'quantity', tt.quantity,
               'sold', s.sold, 'revenue_minor', s.revenue) order by tt.sort_order, tt.name)
      from ticket_types tt
      left join lateral (
        select count(*) filter (where t.status in ('valid', 'redeemed')) as sold,
               coalesce(sum(t.price_paid_minor) filter (where t.status in ('valid', 'redeemed')), 0) as revenue
        from tickets t where t.ticket_type_id = tt.id
      ) s on true
      where tt.event_id = p_event_id
    ), '[]'::jsonb),
    'totals', (
      select jsonb_build_object(
        'sold', count(*) filter (where status in ('valid', 'redeemed')),
        'checked_in', count(*) filter (where status = 'redeemed'),
        'refunded', count(*) filter (where status = 'refunded'),
        'revenue_minor', coalesce(sum(price_paid_minor) filter (where status in ('valid', 'redeemed')), 0))
      from tickets where event_id = p_event_id
    ),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', d.day, 'tickets', d.n, 'revenue_minor', d.rev) order by d.day)
      from (
        select (t.created_at at time zone 'Europe/London')::date as day, count(*) as n, coalesce(sum(t.price_paid_minor), 0) as rev
        from tickets t
        where t.event_id = p_event_id and t.status in ('valid', 'redeemed')
        group by 1
      ) d
    ), '[]'::jsonb)
  ) into v;

  return v;
end;
$$;

-- Live door count (staff): how many tickets are sold and how many are in.
create or replace function event_checkin_counts(p_event_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
begin
  if not is_staff(auth.uid()) then
    raise exception 'Staff only.';
  end if;
  return (
    select jsonb_build_object(
      'sold', count(*) filter (where status in ('valid', 'redeemed')),
      'checked_in', count(*) filter (where status = 'redeemed'))
    from tickets where event_id = p_event_id
  );
end;
$$;

-- Who is on an event's waiting list (staff). Signed-in people show their
-- account name and email; guests show the email they typed.
create or replace function event_interest_list(p_event_id uuid)
returns table (created_at timestamptz, full_name text, email text, signed_in boolean, notified_at timestamptz)
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
begin
  if not is_staff(auth.uid()) then
    raise exception 'Staff only.';
  end if;
  return query
    select i.created_at, coalesce(p.full_name, i.full_name), coalesce(p.email, i.email), i.user_id is not null, i.notified_at
    from event_interests i
    left join profiles p on p.id = i.user_id
    where i.event_id = p_event_id
    order by i.created_at;
end;
$$;

-- Admin dashboard: sales over the last 30 days, monthly revenue, new members per
-- month, and how full the next few events are.
create or replace function dashboard_overview()
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
begin
  if not is_admin(auth.uid()) then
    raise exception 'Admins only.';
  end if;

  return jsonb_build_object(
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', d.day, 'tickets', d.n, 'revenue_minor', d.rev) order by d.day)
      from (
        select (t.created_at at time zone 'Europe/London')::date as day, count(*) as n, coalesce(sum(t.price_paid_minor), 0) as rev
        from tickets t
        where t.status in ('valid', 'redeemed') and t.created_at >= now() - interval '30 days'
        group by 1
      ) d
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object('month', m.month, 'tickets', m.n, 'revenue_minor', m.rev) order by m.month)
      from (
        select to_char(date_trunc('month', t.created_at at time zone 'Europe/London'), 'YYYY-MM') as month,
               count(*) as n, coalesce(sum(t.price_paid_minor), 0) as rev
        from tickets t
        where t.status in ('valid', 'redeemed') and t.created_at >= date_trunc('month', now()) - interval '11 months'
        group by 1
      ) m
    ), '[]'::jsonb),
    'members_monthly', coalesce((
      select jsonb_agg(jsonb_build_object('month', m.month, 'new_members', m.n) order by m.month)
      from (
        select to_char(date_trunc('month', p.membership_started_at), 'YYYY-MM') as month, count(*) as n
        from profiles p
        where p.deleted_at is null and p.membership_started_at is not null
          and p.membership_started_at >= date_trunc('month', now()) - interval '11 months'
        group by 1
      ) m
    ), '[]'::jsonb),
    'upcoming', coalesce((
      select jsonb_agg(jsonb_build_object('title', u.title, 'starts_at', u.starts_at, 'sold', u.sold, 'capacity', u.capacity) order by u.starts_at)
      from (
        select e.title, e.starts_at, e.capacity_total as capacity,
               (select count(*) from tickets t where t.event_id = e.id and t.status in ('valid', 'redeemed')) + e.eventbrite_sold as sold
        from events e
        where e.status = 'published' and e.starts_at > now()
        order by e.starts_at
        limit 8
      ) u
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function event_sales_overview(uuid) to authenticated;
grant execute on function event_checkin_counts(uuid) to authenticated;
grant execute on function event_interest_list(uuid) to authenticated;
grant execute on function dashboard_overview() to authenticated;
