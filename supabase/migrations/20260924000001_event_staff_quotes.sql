-- A personal quote from a staff member on why an event is worth attending —
-- Waterstones-style ("a bookseller's pick"), shown as a speech bubble on the
-- event page. Deliberately independent of `highlight`: a producer can add a
-- quote to any event regardless of which ribbon (or no ribbon) is chosen,
-- rather than this being tied to exactly one of the three highlight values.

alter table events
  add column pick_by_name      text,
  add column pick_by_photo_url text,
  add column pick_quote        text;

alter table events
  add constraint events_pick_quote_len check (pick_quote is null or char_length(pick_quote) <= 280);

comment on column events.pick_quote is
  'A short personal recommendation from a named staff member, e.g. "One of my favourite panels this year." — null means no quote bubble is shown, regardless of highlight.';
