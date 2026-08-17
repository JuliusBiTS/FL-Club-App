# Frontline Club — Mobile App

Ticketing, membership, podcast and news app for [The Frontline Club](https://www.frontlineclub.com) — built to replace Eventbrite fees with direct Stripe checkout and give members a real digital membership card.

Full product/engineering spec: see the original briefing (kept by the project owner) and [`docs/DECISIONS.md`](docs/DECISIONS.md) / [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md) below for the parts that matter day to day.

## Layout (monorepo)

```
app/                  Flutter mobile app (Android first, iOS from the same code)
admin/                Flutter Web admin console (events, orders, members, staff)
packages/flc_core/    Shared models, theme tokens, repositories used by app + admin
supabase/
  migrations/         Postgres schema + RLS, applied in order
  functions/          Edge Functions (Deno) — the only code that talks to Stripe/Eventbrite/WordPress
  seed.sql            Demo data for local dev
wordpress-plugin/     [frontline_events] shortcode/block that renders from the Supabase API
docs/                 Decisions already made, open questions still blocking work
```

## Stack

Flutter (Riverpod, go_router, freezed) · Supabase (Postgres + Auth + Storage + Edge Functions) · Stripe · Firebase Cloud Messaging · Drift (local cache) · flutter_secure_storage.

Nothing here needs a paid tier at the club's scale — see cost notes in `docs/DECISIONS.md`.

## Getting started

### 1. Install the Flutter SDK
See the step-by-step Windows guide the assistant gave at project kickoff, or https://docs.flutter.dev/get-started/install. Run `flutter doctor` until it's clean (Android toolchain at minimum; Xcode only needed once iOS work starts).

### 2. Create a Supabase project
Free tier, **EU or UK region** (cannot be changed later). Then:
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

## Delivery plan

Ten milestones, each demonstrable end to end. See the full breakdown in the briefing §18; short version:

- [x] **M0** Foundations — repo, CI, schema, RLS, design tokens
- [x] **M1** Events, read-only
- [x] **M2** Accounts
- [x] **M3** Payments (Stripe checkout) — built and live-tested end to end; only Stripe credentials remain, see `docs/STRIPE_SETUP.md`
- [x] **M4** Tickets (rotating signed QR wallet) — built and live-tested end to end; only the ticket/membership signing keys remain, see `docs/TICKET_KEYS_SETUP.md`
- [ ] **M5** Scanner (staff door mode, offline)
- [ ] **M6** Membership (the card — see below)
- [ ] **M7** Loyalty
- [ ] **M8** Content (podcast RSS, news, WordPress plugin)
- [ ] **M9** Hardening & launch (Android)
- [ ] **M10** iOS

Ship M0–M5 before demoing to club staff — a demo that can't sell a ticket and scan it at a door doesn't answer the question they care about.

## The one thing to get right

Security. No forgeable tickets, no forgeable membership cards, no path — client, API, or deep link — by which a user can grant themselves membership. Every privileged mutation goes through Postgres RLS and Edge Functions running as `service_role`; the client only ever holds the Supabase anon key and Stripe's publishable key. See the ticket/membership HMAC scheme in the schema migrations' comments before touching `supabase/functions/`.
