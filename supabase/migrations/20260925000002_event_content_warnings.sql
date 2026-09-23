-- Content warnings ("might include distressing footage", "flashing imagery",
-- ...) — feedback: an option to add trigger-warning style notices to an
-- event. Free-text short lines chosen per event, not a fixed enum: what's
-- worth warning about varies by event, and staff know best. Shown on the
-- event page above the description; a small "Content note" marker on the
-- feed card.

alter table events
  add column content_warnings text[] not null default '{}';

alter table events
  add constraint events_content_warnings_limits check (
    coalesce(array_length(content_warnings, 1), 0) <= 5
  );

comment on column events.content_warnings is
  'Short warnings shown to attendees before they book, e.g. "May include distressing footage". Max 5, each kept short by the editor.';
