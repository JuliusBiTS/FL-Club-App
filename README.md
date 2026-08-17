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

### 3. Run the app
```bash
cd app
flutter pub get
flutter run
```

### 4. Run the admin console
```bash
cd admin
flutter pub get
flutter run -d chrome
```

## The one thing to get right

Security. No forgeable tickets, no forgeable membership cards, no path — client, API, or deep link — by which a user can grant themselves membership. Every privileged mutation goes through Postgres RLS and Edge Functions running as `service_role`; the client only ever holds the Supabase anon key and Stripe's publishable key. See the ticket/membership HMAC scheme in the schema migrations' comments before touching `supabase/functions/`.
