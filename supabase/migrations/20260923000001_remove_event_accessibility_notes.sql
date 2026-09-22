-- Accessibility notes (added in 20260921000001) are removed: the club can't
-- reliably offer this today, and there's no plan in place to build the
-- checks (a verified step-free route, real captioning, staff briefed on it)
-- that would make the promise true. Better to have no field than one nobody
-- can vouch for. See docs/DECISIONS.md.

alter table events drop column if exists accessibility_notes;
