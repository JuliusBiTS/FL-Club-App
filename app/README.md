# Frontline Club app

Mobile app — see the root [README](../README.md) for the full monorepo picture.

## First-time setup

This `lib/` and `pubspec.yaml` were hand-written before `flutter create` had
been run in this environment. Before the first `flutter run`:

```bash
# From this directory (app/). Generates android/ and ios/ WITHOUT touching
# pubspec.yaml or lib/ — flutter create only fills in missing platform folders.
flutter create --org com.frontlineclub --project-name frontline_club_app --platforms android,ios .

flutter pub get

# Code generation: freezed models, Drift's AppDatabase, and ARB localization.
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

## Running

Requires the Supabase project's URL/anon key and Stripe's publishable key —
none of these are secrets in the "don't commit" sense (the anon key is
meaningless without RLS, which is the real gate — see
`supabase/migrations/20260817000009_rls_policies.sql`), but they're
per-environment, so they're passed at run time rather than hard-coded:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
```

## Architecture

Feature-first, repository pattern, offline-first reads — see briefing §7.3
(reproduced in `docs/DECISIONS.md` at the repo root) and
`lib/features/events/` for the reference implementation every other
feature should follow:

```
presentation/  (screens, Riverpod controllers)
      -> domain/  (repository interface)
            -> data/  (repository impl, remote data source (Supabase), local data source (Drift))
```

No Supabase calls inside widgets, ever. No client-side price arithmetic
beyond `price × quantity`. Money is always integer minor units with a
currency code, never a double.
