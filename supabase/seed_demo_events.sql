-- Demo events for showing the app and admin console off.
--
-- Everything here is INVENTED: made-up titles, made-up speakers, example.com
-- links. Nothing is attributed to a real person or a real Frontline Club event.
-- Every row is tagged 'demo' so it is easy to find and remove.
--
-- HOW TO RUN (after the 20260921000001_event_management migration is applied):
--   Supabase dashboard -> SQL Editor -> paste this whole file -> Run.
-- Safe to run again: it first removes earlier demo events (any that already have
-- orders are left alone) and re-creates them, with dates counted from today.
--
-- HOW TO REMOVE THEM LATER:
--   delete from events where 'demo' = any(tags)
--     and not exists (select 1 from orders o where o.event_id = events.id);
--
-- There are no pictures on purpose: the app shows its olive "category" artwork
-- until you add real photos in the editor.

-- ---------------------------------------------------------------- helpers ---
-- 19:00 London time, N days from today (pass hours/minutes for other times).
create or replace function public._demo_at_london(days integer, h integer, m integer default 0)
returns timestamptz
language sql
as $$
  select ((date_trunc('day', now() at time zone 'Europe/London')
           + make_interval(days => days, hours => h, mins => m)) at time zone 'Europe/London');
$$;

-- Plain paragraphs -> the HTML the app renders (same result as the editor for text without formatting).
create or replace function public._demo_para_html(md text)
returns text
language sql
as $$
  select '<p>' || replace(replace(md, E'\n\n', '</p><p>'), E'\n', '<br>') || '</p>';
$$;

-- ---------------------------------------------------------- clean up first ---
delete from events
 where 'demo' = any(tags)
   and not exists (select 1 from orders o where o.event_id = events.id);

-- ------------------------------------------------------------------ events ---
insert into events (
  id, slug, title, subtitle, summary, description_md, category, tags,
  starts_at, ends_at, doors_at, venue_room, is_online, livestream_url,
  speakers, links, highlight, perks, loyalty_eligible, members_only, is_filmed,
  accessibility_notes, capacity_total, capacity_app, capacity_eventbrite,
  eventbrite_sold, eventbrite_synced_at, status, publish_at
) values

-- 1. FC Recommends panel ------------------------------------------------------
('d0000000-0000-4000-8000-000000000001', 'demo-reporting-from-the-edge-of-the-map',
 'Panel discussion: Reporting from the Edge of the Map',
 'What it takes to cover a story nobody else can reach',
 'Three reporters on working alone, working safely, and getting the story out when the usual routes are closed.',
 E'Freelancers now cover most of the world''s hardest stories, often without a newsroom behind them.\n\nOur panel talks about how they plan a trip, who they rely on locally, what they do when things go wrong, and how they get paid for it.\n\nThis is a demo event: the speakers and details are made up.',
 'Panel discussion', ARRAY['demo', 'Press freedom', 'Freelancers'],
 public._demo_at_london(3, 19), public._demo_at_london(3, 20, 45), public._demo_at_london(3, 18, 30), 'The Forum', false, null,
 '[{"name":"Priya Nair","role":"Freelance war correspondent","bio":"Has reported from eleven conflicts. (Fictional.)"},
   {"name":"Tomas Reyes","role":"Photojournalist","bio":"Documents daily life in places the news has moved on from. (Fictional.)"},
   {"name":"Dr Amira Haddad","role":"Conflict analyst","bio":"Studies how wars are reported. (Fictional.)"},
   {"name":"Elena Voss","role":"Chair","bio":"Journalist and broadcaster. (Fictional.)"}]',
 '[{"label":"Read the reading list","url":"https://example.com/reading-list","kind":"article"}]',
 'fc_recommends', ARRAY['Free drink with your ticket'], true, false, true,
 'Step-free access via the side entrance. Live captions are available on request.',
 120, 100, 20, 0, now(), 'published', null),

-- 2. Book talk with a special offer -----------------------------------------
('d0000000-0000-4000-8000-000000000002', 'demo-the-last-correspondent',
 'Book talk: The Last Correspondent',
 'A novel of fixers, editors and the stories that get cut',
 'Helena Marsh reads from her new novel and talks about the real people behind the byline.',
 E'A debut novel about the local fixers who make foreign reporting possible, and who are rarely named.\n\nHelena Marsh reads from the book and is in conversation with the audience. Copies will be on sale after the talk.\n\nThis is a demo event: the book and author are made up.',
 'Book talk', ARRAY['demo', 'Fiction', 'Books'],
 public._demo_at_london(6, 19), public._demo_at_london(6, 20, 30), public._demo_at_london(6, 18, 30), 'The Forum', false, null,
 '[{"name":"Helena Marsh","role":"Author, The Last Correspondent","bio":"Former newspaper editor turned novelist. (Fictional.)"}]',
 '[{"label":"Buy the book","url":"https://example.com/the-last-correspondent","kind":"book"}]',
 'special_offer', ARRAY['Signed copies available'], true, false, true,
 null, 80, 80, 0, 0, null, 'published', null),

-- 3. Members-only screening --------------------------------------------------
('d0000000-0000-4000-8000-000000000003', 'demo-the-fixers-screening',
 'Screening + Q&A: The Fixers',
 'A documentary about the people who make the story possible',
 'Members-only screening of a new documentary, followed by a conversation with its director.',
 E'The Fixers follows three local producers over one year as they work with visiting journalists.\n\nThe screening is followed by a Q&A with the director and one of the film''s subjects.\n\nThis is a demo event: the film and the people are made up.',
 'Screening + Q&A', ARRAY['demo', 'Film', 'Members'],
 public._demo_at_london(9, 19, 30), public._demo_at_london(9, 22), public._demo_at_london(9, 19), 'The Forum', false, null,
 '[{"name":"Jonas Lindqvist","role":"Director","bio":"Makes documentaries about the business of news. (Fictional.)"},
   {"name":"Farah Qasim","role":"Fixer and producer","bio":"Has worked with reporters from thirty countries. (Fictional.)"}]',
 '[{"label":"Watch the trailer","url":"https://example.com/the-fixers-trailer","kind":"film"}]',
 'staff_pick', ARRAY[]::text[], true, true, true,
 'Captioned screening. Step-free access via the side entrance.',
 80, 80, 0, 0, null, 'published', null),

-- 4. Online talk ---------------------------------------------------------------
('d0000000-0000-4000-8000-000000000004', 'demo-verifying-the-video',
 'Online talk: Verifying the Video',
 'A beginner''s guide to open-source investigation',
 'How to check where a video was filmed, when, and by whom, using free tools. Watch from anywhere.',
 E'A practical hour on the habits that stop you sharing something false.\n\nMarcus shows real (and clearly labelled demo) examples and answers questions from the live chat.\n\nThis is a demo event: the speaker and details are made up.',
 'Online talk', ARRAY['demo', 'Verification', 'Online'],
 public._demo_at_london(12, 18), public._demo_at_london(12, 19), null, null, true, 'https://example.com/live',
 '[{"name":"Marcus Oyelaran","role":"Open-source investigator","bio":"Teaches verification to newsrooms. (Fictional.)"}]',
 '[{"label":"Free verification toolkit","url":"https://example.com/toolkit","kind":"link"}]',
 'none', ARRAY[]::text[], true, false, true,
 'Live captions on the stream.', 300, 300, 0, 0, null, 'published', null),

-- 5. Workshop -------------------------------------------------------------------
('d0000000-0000-4000-8000-000000000005', 'demo-safety-basics-for-freelancers',
 'Workshop: Safety Basics for Freelancers',
 'A practical day on risk, first aid and staying in touch',
 'A small-group training day for freelancers heading to difficult places for the first time.',
 E'A hands-on day covering risk assessment, first aid basics, digital security and check-in routines.\n\nPlaces are limited to keep the groups small. Lunch is included.\n\nThis is a demo event: the trainer and details are made up.',
 'Workshop / training', ARRAY['demo', 'Training', 'Safety'],
 public._demo_at_london(15, 10), public._demo_at_london(15, 16), public._demo_at_london(15, 9, 30), 'The Clubroom', false, null,
 '[{"name":"Ingrid Solberg","role":"Safety trainer","bio":"Ran hostile-environment courses for ten years. (Fictional.)"}]',
 '[]',
 'staff_pick', ARRAY['Lunch included'], false, false, false,
 'Step-free access. Tell us about any dietary needs when you book.',
 24, 24, 0, 0, null, 'published', null),

-- 6. Members' social -------------------------------------------------------
('d0000000-0000-4000-8000-000000000006', 'demo-autumn-quiz-night',
 'Members'' social: Autumn Quiz Night',
 'Teams of six, one very serious trophy',
 'A relaxed evening for members and their guests, with a current-affairs quiz and a free drink.',
 E'Bring a team or join one on the night. Rounds on world news, geography, photography and the wrong end of history.\n\nMembers only.\n\nThis is a demo event.',
 'Members'' social', ARRAY['demo', 'Social', 'Members'],
 public._demo_at_london(18, 19), public._demo_at_london(18, 21, 30), public._demo_at_london(18, 18, 30), 'The Forum', false, null,
 '[]', '[]',
 'none', ARRAY['Free drink with your ticket', 'Prizes for the winning team'], false, true, false,
 null, 80, 80, 0, 0, null, 'published', null),

-- 7. Nearly sold out ("Selling fast" appears on its own) --------------------
('d0000000-0000-4000-8000-000000000007', 'demo-the-age-of-the-algorithm',
 'Panel discussion: The Age of the Algorithm',
 'AI, verification and the future of the newsroom',
 'Editors and investigators on what automated tools mean for reporting, and what they can''t replace.',
 E'From transcription to translation to fake video, AI is already in the newsroom.\n\nOur panel asks what still needs a human, and how to tell the difference.\n\nThis is a demo event: the speakers and details are made up.',
 'Panel discussion', ARRAY['demo', 'AI', 'Newsrooms'],
 public._demo_at_london(2, 19), public._demo_at_london(2, 20, 30), public._demo_at_london(2, 18, 30), 'The Forum', false, null,
 '[{"name":"Marcus Oyelaran","role":"Open-source investigator","bio":"Teaches verification to newsrooms. (Fictional.)"},
   {"name":"Dr Amira Haddad","role":"Conflict analyst","bio":"Studies how wars are reported. (Fictional.)"}]',
 '[]',
 'none', ARRAY[]::text[], true, false, true,
 null, 100, 20, 80, 78, now(), 'published', null),

-- 8. Free exhibition evening --------------------------------------------------
('d0000000-0000-4000-8000-000000000008', 'demo-faces-of-the-frontline',
 'Exhibition: Faces of the Frontline',
 'Photographers in conversation',
 'A free evening among the club''s photographs, with three photographers talking about one picture each.',
 E'Walk the club''s permanent collection with the people who took the pictures.\n\nThree photographers each choose one image and tell the story of how it was made.\n\nThis is a demo event: the photographers are made up.',
 'Exhibition', ARRAY['demo', 'Photography'],
 public._demo_at_london(21, 18, 30), public._demo_at_london(21, 20, 30), public._demo_at_london(21, 18), 'The Club', false, null,
 '[{"name":"Tomas Reyes","role":"Photojournalist","bio":"Documents daily life in places the news has moved on from. (Fictional.)"}]',
 '[]',
 'none', ARRAY['Free welcome drink'], true, false, true,
 'Step-free access throughout.', 60, 60, 0, 0, null, 'published', null),

-- 9. Scheduled: goes live on its own in two days ------------------------------
('d0000000-0000-4000-8000-000000000009', 'demo-frontline-awards-night',
 'Awards and fundraising: Frontline Awards Night',
 'An evening celebrating independent journalism',
 'Dinner, short films and the year''s awards, in support of freelance journalists.',
 E'An evening honouring the year''s best independent reporting, with proceeds supporting freelancers who work in dangerous places.\n\nThis is a demo event, scheduled to go live automatically so you can see scheduling working.',
 'Awards & fundraising', ARRAY['demo', 'Fundraising'],
 public._demo_at_london(40, 19), public._demo_at_london(40, 23), public._demo_at_london(40, 18, 30), 'The Forum', false, null,
 '[]',
 '[{"label":"Donate","url":"https://example.com/donate","kind":"donate"}]',
 'fc_recommends', ARRAY[]::text[], false, false, true,
 null, 150, 150, 0, 0, null, 'draft', now() + interval '2 days'),

-- 10. A plain draft -------------------------------------------------------------
('d0000000-0000-4000-8000-000000000010', 'demo-untitled-documentary-draft',
 'Screening + Q&A: Untitled documentary',
 null,
 'Still being planned.',
 E'Placeholder for an event that has not been confirmed yet.\n\nThis is a demo draft.',
 'Screening + Q&A', ARRAY['demo'],
 public._demo_at_london(30, 19), null, null, 'The Forum', false, null,
 '[]', '[]',
 'none', ARRAY[]::text[], true, false, true,
 null, 80, 80, 0, 0, null, 'draft', null),

-- 11. A past event (shows under "Past" in the manager) ------------------------
('d0000000-0000-4000-8000-000000000011', 'demo-notes-from-the-field',
 'Book talk: Notes from the Field',
 'A reporter''s diaries',
 'A past event, kept so the Past filter has something to show.',
 E'A look back at a demo book evening.\n\nThis is a demo event.',
 'Book talk', ARRAY['demo', 'Books'],
 public._demo_at_london(-12, 19), public._demo_at_london(-12, 20, 30), public._demo_at_london(-12, 18, 30), 'The Forum', false, null,
 '[{"name":"Helena Marsh","role":"Author","bio":"(Fictional.)"}]', '[]',
 'none', ARRAY[]::text[], true, false, true,
 null, 80, 80, 0, 0, null, 'published', null)

on conflict (id) do nothing;

update events
   set description_html = public._demo_para_html(description_md)
 where 'demo' = any(tags) and description_md is not null;

-- ---------------------------------------------------------- ticket types ---
-- price_minor is in pence. Quantities never exceed each event's app capacity.
insert into ticket_types (id, event_id, name, audience, price_minor, quantity, requires_member, requires_proof, sort_order)
values
  -- 1 Reporting from the Edge of the Map (100 in the app)
  ('d1000000-0000-4000-8000-000000000101', 'd0000000-0000-4000-8000-000000000001', 'Standard',   'public',     1500, 60, false, false, 0),
  ('d1000000-0000-4000-8000-000000000102', 'd0000000-0000-4000-8000-000000000001', 'Member',     'member',      500, 30, true,  false, 1),
  ('d1000000-0000-4000-8000-000000000103', 'd0000000-0000-4000-8000-000000000001', 'Concession', 'concession',  800, 10, false, true,  2),
  -- 2 The Last Correspondent (80)
  ('d1000000-0000-4000-8000-000000000201', 'd0000000-0000-4000-8000-000000000002', 'Standard',   'public',     1200, 50, false, false, 0),
  ('d1000000-0000-4000-8000-000000000202', 'd0000000-0000-4000-8000-000000000002', 'Member',     'member',      500, 30, true,  false, 1),
  -- 3 The Fixers, members only (80)
  ('d1000000-0000-4000-8000-000000000301', 'd0000000-0000-4000-8000-000000000003', 'Member',     'member',      500, 80, true,  false, 0),
  -- 4 Verifying the Video, online (300)
  ('d1000000-0000-4000-8000-000000000401', 'd0000000-0000-4000-8000-000000000004', 'Watch online', 'public',    500, 200, false, false, 0),
  ('d1000000-0000-4000-8000-000000000402', 'd0000000-0000-4000-8000-000000000004', 'Member (free)', 'member',     0, 100, true,  false, 1),
  -- 5 Safety Basics workshop (24)
  ('d1000000-0000-4000-8000-000000000501', 'd0000000-0000-4000-8000-000000000005', 'Freelance journalist', 'press', 1000, 12, false, true, 0),
  ('d1000000-0000-4000-8000-000000000502', 'd0000000-0000-4000-8000-000000000005', 'Standard',   'public',     4500, 12, false, false, 1),
  -- 6 Autumn Quiz Night, members only (80)
  ('d1000000-0000-4000-8000-000000000601', 'd0000000-0000-4000-8000-000000000006', 'Member',     'member',      500, 80, true,  false, 0),
  -- 7 The Age of the Algorithm (20 left in the app)
  ('d1000000-0000-4000-8000-000000000701', 'd0000000-0000-4000-8000-000000000007', 'Standard',   'public',     1500, 20, false, false, 0),
  -- 8 Faces of the Frontline, free (60)
  ('d1000000-0000-4000-8000-000000000801', 'd0000000-0000-4000-8000-000000000008', 'Free entry', 'public',        0, 60, false, false, 0),
  -- 9 Awards night (150)
  ('d1000000-0000-4000-8000-000000000901', 'd0000000-0000-4000-8000-000000000009', 'Standard',   'public',     7500, 120, false, false, 0),
  ('d1000000-0000-4000-8000-000000000902', 'd0000000-0000-4000-8000-000000000009', 'Member',     'member',     5000, 30, true,  false, 1),
  -- 10 draft (80)
  ('d1000000-0000-4000-8000-000000001001', 'd0000000-0000-4000-8000-000000000010', 'Standard',   'public',     1500, 50, false, false, 0),
  ('d1000000-0000-4000-8000-000000001002', 'd0000000-0000-4000-8000-000000000010', 'Member',     'member',      500, 30, true,  false, 1),
  -- 11 past (80)
  ('d1000000-0000-4000-8000-000000001101', 'd0000000-0000-4000-8000-000000000011', 'Standard',   'public',     1200, 80, false, false, 0)
on conflict (id) do nothing;

-- The two helper functions above were only needed while inserting.
drop function if exists public._demo_at_london(integer, integer, integer);
drop function if exists public._demo_para_html(text);

-- Quick check: this should list the 11 demo events.
select title, status, starts_at at time zone 'Europe/London' as london_time, highlight
  from events where 'demo' = any(tags) order by starts_at;
