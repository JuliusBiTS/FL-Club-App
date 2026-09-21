# Mobile App

Ticketing, membership, podcast and news app built with Flutter and Supabase.

## Layout (monorepo)

```
app/                  Flutter mobile app (Android first, iOS from the same code)
admin/                Flutter Web admin console (events, orders, members, staff)
packages/flc_core/    Shared models, theme tokens, repositories used by app + admin
supabase/
  migrations/         Postgres schema + RLS, applied in order
  functions/          Edge Functions (Deno) — the only code that talks to Stripe/Eventbrite/WordPress
  seed.sql            Demo data for local dev
wordpress-plugin/     Shortcode/block that renders from the Supabase API
docs/                 Decisions already made, open questions still blocking work
```

## Stack

Flutter (Riverpod, go_router, freezed) · Supabase (Postgres + Auth + Storage + Edge Functions) · Stripe · Firebase Cloud Messaging · Drift (local cache) · flutter_secure_storage.

## Getting started

### 1. Install the Flutter SDK
https://docs.flutter.dev/get-started/install. Run `flutter doctor` until it's clean (Android toolchain at minimum; Xcode only needed once iOS work starts).

### 2. Create a Supabase project
Free tier is enough to start. Then:
```bash
cd supabase
supabase link --project-ref <your-project-ref>
supabase db push          # applies migrations/
supabase db seed          # optional demo data, see seed.sql
```
Copy `.env.example` → `.env` in `supabase/` and fill in the project URL/anon key/service role key. Never commit `.env`.

### 3. Generate code (once per clone, and after changing a model)
Generated files (`*.g.dart`, `*.freezed.dart`) are git-ignored, so a fresh clone won't compile until you run:
```bash
(cd packages/flc_core && flutter pub get && dart run build_runner build)
(cd app && flutter pub get && dart run build_runner build && flutter gen-l10n)
```

### 4. Run the app
Copy `app/dart_defines.example.json` to `app/dart_defines.json` (git-ignored), fill in your Supabase URL and anon key, then:
```bash
cd app
flutter run --dart-define-from-file=dart_defines.json
```

### 5. Run the admin console
Same idea with `admin/dart_defines.json`:
```bash
cd admin
flutter pub get
flutter run -d chrome --dart-define-from-file=dart_defines.json
```
Sign in as an admin (whole console) or a staff member (Events and Notifications only).

### 6. Event management, demo events and push notifications
- [docs/EVENT_MANAGEMENT.md](docs/EVENT_MANAGEMENT.md) — how staff create and promote events, what staff vs admins can do, and the made-up demo events (`supabase/seed_demo_events.sql`).
- [docs/PUSH_SETUP.md](docs/PUSH_SETUP.md) — switching on push notifications (Firebase).

## The one thing to get right

Security. No forgeable tickets, no forgeable membership cards, no path — client, API, or deep link — by which a user can grant themselves membership. Every privileged mutation goes through Postgres RLS and Edge Functions running as `service_role`; the client only ever holds the Supabase anon key and Stripe's publishable key. See the ticket/membership HMAC scheme in the schema migrations' comments before touching `supabase/functions/`.
