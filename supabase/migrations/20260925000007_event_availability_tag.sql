-- A manual "Selling fast" / "Sold out" tag staff can set on an event, for when
-- the automatic count doesn't tell the whole story (e.g. tickets sold outside
-- the app). Display only: it never blocks or allows a purchase.
alter table events
  add column availability_tag text check (availability_tag in ('selling_fast', 'sold_out'));

-- Sold out: the automatic rule, or a manual "sold out" tag.
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
    and (
      e.availability_tag = 'sold_out'
      or (e.availability_tag is null
          and e.capacity_total > 0
          and (s.issued + e.eventbrite_sold) >= e.capacity_total)
    );
$$;

-- Selling fast: the automatic 75% rule, or a manual "selling fast" tag. A manual
-- "sold out" tag always wins over the automatic rule.
create or replace function events_selling_fast()
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
    and (
      e.availability_tag = 'selling_fast'
      or (e.availability_tag is null
          and e.capacity_total > 0
          and (s.issued + e.eventbrite_sold) >= e.capacity_total * 0.75
          and (s.issued + e.eventbrite_sold) <  e.capacity_total)
    );
$$;
