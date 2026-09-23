-- Hand-written articles and stories can be saved as drafts. Everything that
-- already exists (including everything the WordPress sync brings in) stays
-- published; the sync never sets this column, so it keeps defaulting to that.
alter table articles
  add column status text not null default 'published' check (status in ('draft', 'published'));

-- The public still reads articles freely, but only published ones; staff also
-- see drafts (for the admin console and the app's staff area).
drop policy if exists articles_public_read on articles;
create policy articles_public_read on articles
  for select using (status = 'published' or is_staff(auth.uid()));
