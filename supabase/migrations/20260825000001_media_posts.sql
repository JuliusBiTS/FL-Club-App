-- Media tab (briefing feedback, 2026-08-24): a synced feed of the club's
-- own YouTube uploads/livestreams, watchable in-app. Modelled directly on
-- podcast_episodes (same "requires no account, synced by an Edge Function"
-- shape) — see docs/OPEN_QUESTIONS.md for why this ships YouTube-only for
-- now (Instagram needs Meta app review before any API access exists).
create table media_posts (
  id             uuid primary key default gen_random_uuid(),
  source         text not null default 'youtube' check (source in ('youtube')),
  external_id    text not null,       -- YouTube video ID, the sync key
  title          text not null,
  description    text,
  thumbnail_url  text,
  published_at   timestamptz not null,
  is_live        boolean not null default false,
  synced_at      timestamptz not null default now(),
  unique (source, external_id)
);

create index media_posts_published_idx on media_posts (published_at desc);

alter table media_posts enable row level security;

create policy media_posts_public_read on media_posts
  for select using (true);   -- public marketing content, no account needed
