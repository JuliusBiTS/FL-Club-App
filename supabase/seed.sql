-- Local/dev demo data. Never run this against production. Gives you:
--   * four demo accounts (plain user / active member / staff / admin) —
--     the same accounts §14.2 requires in App Store / Play reviewer notes
--     and for screenshots, so real member data never appears in a
--     submission.
--   * two published demo events with a realistic ticket-type spread.
--
-- Password for every demo account: FrontlineDemo2026!

do $$
declare
  v_user_id   uuid := '00000000-0000-0000-0000-000000000101';
  v_member_id uuid := '00000000-0000-0000-0000-000000000102';
  v_staff_id  uuid := '00000000-0000-0000-0000-000000000103';
  v_admin_id  uuid := '00000000-0000-0000-0000-000000000104';
  v_password  text := crypt('FrontlineDemo2026!', gen_salt('bf'));
begin
  -- The four empty-string columns below aren't optional cosmetics: GoTrue
  -- scans them into non-nullable Go strings on every sign-in, and a manual
  -- insert (bypassing the Admin API, which always sets these) leaves them
  -- NULL by default. That fails sign-in for exactly these demo accounts
  -- with an opaque "Database error querying schema" — found the hard way
  -- testing a demo build.
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) values
    ('00000000-0000-0000-0000-000000000000', v_user_id,   'authenticated', 'authenticated', 'demo.user@frontlineclub.dev',   v_password, now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', v_member_id, 'authenticated', 'authenticated', 'demo.member@frontlineclub.dev', v_password, now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', v_staff_id,  'authenticated', 'authenticated', 'demo.staff@frontlineclub.dev',  v_password, now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', v_admin_id,  'authenticated', 'authenticated', 'demo.admin@frontlineclub.dev',  v_password, now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '')
  on conflict (id) do nothing;

  insert into auth.identities (
    id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values
    (gen_random_uuid(), v_user_id::text,   v_user_id,   jsonb_build_object('sub', v_user_id::text,   'email', 'demo.user@frontlineclub.dev'),   'email', now(), now(), now()),
    (gen_random_uuid(), v_member_id::text, v_member_id, jsonb_build_object('sub', v_member_id::text, 'email', 'demo.member@frontlineclub.dev'), 'email', now(), now(), now()),
    (gen_random_uuid(), v_staff_id::text,  v_staff_id,  jsonb_build_object('sub', v_staff_id::text,  'email', 'demo.staff@frontlineclub.dev'),  'email', now(), now(), now()),
    (gen_random_uuid(), v_admin_id::text,  v_admin_id,  jsonb_build_object('sub', v_admin_id::text,  'email', 'demo.admin@frontlineclub.dev'),  'email', now(), now(), now())
  on conflict (provider, provider_id) do nothing;

  insert into profiles (
    id, email, full_name, display_name, role, member_status, membership_kind,
    membership_number, membership_pin, membership_started_at, membership_expires_at,
    terms_accepted_at, privacy_accepted_at
  ) values
    (v_user_id,   'demo.user@frontlineclub.dev',   'Demo User',    'Demo User',    'user',  'none',   null,   null,          null,   null,                     null,                     now(), now()),
    (v_member_id, 'demo.member@frontlineclub.dev', 'Demo Member',  'Demo Member',  'user',  'active', 'full', 'FLC-00102',   '4821', now() - interval '1 year', now() + interval '6 months', now(), now()),
    (v_staff_id,  'demo.staff@frontlineclub.dev',  'Demo Staff',   'Demo Staff',   'staff', 'none',   null,   null,          null,   null,                     null,                     now(), now()),
    (v_admin_id,  'demo.admin@frontlineclub.dev',  'Demo Admin',   'Demo Admin',   'admin', 'active', 'full', 'FLC-00104',   '1357', now() - interval '2 years', null,                     now(), now())
  on conflict (id) do nothing;
end $$;

-- Demo events -----------------------------------------------------------

insert into events (
  id, slug, title, subtitle, summary, description_html, category, tags,
  starts_at, ends_at, doors_at, venue_room, hero_image_path, is_filmed, members_only,
  status, capacity_total, capacity_app, capacity_eventbrite, published_at, created_by
) values (
  '10000000-0000-0000-0000-000000000001',
  'reporting-from-the-front-line',
  'Reporting from the Front Line: A Conversation',
  'Twenty years of conflict journalism, on the record',
  'Three correspondents on what changed, and what never does, about covering war.',
  '<p>A panel discussion with correspondents who have covered conflict across three decades, moderated by a Frontline Club trustee.</p>',
  'Panel',
  array['panel', 'conflict-reporting'],
  now() + interval '24 days' + interval '19 hours',
  now() + interval '24 days' + interval '20 hours 30 minutes',
  now() + interval '24 days' + interval '18 hours 30 minutes',
  'The Forum', 'https://picsum.photos/seed/flc-panel-conflict/900/500', true, false,
  'published', 120, 100, 20, now(), '00000000-0000-0000-0000-000000000104'
) on conflict (id) do nothing;

insert into ticket_types (event_id, name, description, audience, price_minor, quantity, requires_member, requires_proof, sort_order) values
  ('10000000-0000-0000-0000-000000000001', 'Standard',   null, 'public',      1500, 70, false, false, 0),
  ('10000000-0000-0000-0000-000000000001', 'Member',     'The club''s standing member rate.', 'member', 500, 20, true, false, 1),
  ('10000000-0000-0000-0000-000000000001', 'Concession', 'Students and over-65s. Photo ID checked at the door.', 'concession', 800, 10, false, true, 2)
on conflict do nothing;

insert into events (
  id, slug, title, subtitle, summary, description_html, category, tags,
  starts_at, ends_at, doors_at, venue_room, hero_image_path, is_filmed, members_only,
  status, capacity_total, capacity_app, capacity_eventbrite, published_at, created_by
) values (
  '10000000-0000-0000-0000-000000000002',
  'documentary-screening-under-fire',
  'Documentary Screening: Under Fire',
  'Followed by a Q&A with the director',
  'A feature documentary on press freedom, screened for members ahead of general release.',
  '<p>Members-only preview screening. The director joins for a Q&A immediately after.</p>',
  'Screening',
  array['screening', 'members-only'],
  now() + interval '10 days' + interval '19 hours',
  now() + interval '10 days' + interval '21 hours',
  now() + interval '10 days' + interval '18 hours 30 minutes',
  'The Forum', 'https://picsum.photos/seed/flc-screening-underfire/900/500', true, true,
  'published', 80, 80, 0, now(), '00000000-0000-0000-0000-000000000104'
) on conflict (id) do nothing;

insert into ticket_types (event_id, name, description, audience, price_minor, quantity, requires_member, requires_proof, sort_order) values
  ('10000000-0000-0000-0000-000000000002', 'Member', 'Members-only screening.', 'member', 500, 80, true, false, 0)
on conflict do nothing;

-- Media posts --------------------------------------------------------------
-- Real uploads from the club's own channel, youtube.com/@FrontlineClubLondon
-- (channel id UC_RRSAK5BsitIw0tV2dg9gw). Hand-seeded until a YouTube sync
-- exists; more can be added (and removed) by staff under Content in the admin
-- console or You > Manage media in the app. They were briefly removed and
-- then restored at the club's request.
insert into media_posts (source, external_id, title, description, thumbnail_url, published_at, is_live) values
  ('youtube', 'qXZzQYP60-M', 'Lebanon on the Edge', 'Panel discussion, recorded at the club.', 'https://img.youtube.com/vi/qXZzQYP60-M/hqdefault.jpg', '2026-06-03T07:52:03Z', false),
  ('youtube', 'Syw0GDQV6lw', 'AI Targeting and Palantir: Who Decides Who Lives or Dies?', 'Panel discussion, recorded at the club.', 'https://img.youtube.com/vi/Syw0GDQV6lw/hqdefault.jpg', '2026-05-15T09:33:10Z', false),
  ('youtube', 'MGIrcA2cNFU', 'The Gulf at a Turning Point', 'Panel discussion, recorded at the club.', 'https://img.youtube.com/vi/MGIrcA2cNFU/hqdefault.jpg', '2026-05-07T10:14:41Z', false),
  ('youtube', 'oq293zudVck', 'The Power of Humanising Conflict', 'Panel discussion, recorded at the club.', 'https://img.youtube.com/vi/oq293zudVck/hqdefault.jpg', '2026-04-30T13:33:53Z', false),
  ('youtube', 'oFsSB07TJLQ', 'Why the US War Machine Will Lose in Iran', 'Panel discussion featuring Jeremy Corbyn, recorded at the club.', 'https://img.youtube.com/vi/oFsSB07TJLQ/hqdefault.jpg', '2026-04-01T08:07:02Z', false)
on conflict (source, external_id) do nothing;
