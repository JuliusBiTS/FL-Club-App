-- events_sold_out(): the sold-out counterpart to events_selling_fast()
-- (20260921000001) — same shape, same reasoning (derived, never stored,
-- exposes only event ids). Feedback: "add a sold out banner or tag for
-- events that are sold out."

create or replace function events_sold_out()
returns setof uuid
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select e.id
  from events e
  cross join lateral (
    select count(*)::integer as issued
    from tickets t
    where t.event_id = e.id and t.status not in ('void', 'cancelled', 'refunded')
  ) s
  where e.status = 'published'
    and e.starts_at > now()
    and e.capacity_total > 0
    and (s.issued + e.eventbrite_sold) >= e.capacity_total;
$$;

grant execute on function events_sold_out() to anon, authenticated;
