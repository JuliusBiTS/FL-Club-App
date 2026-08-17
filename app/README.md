# Frontline Club app

Mobile app — see the root [README](../README.md) for the full monorepo picture.

## First-time setup

`android/` is already generated and committed (verified: `flutter build apk
--debug` succeeds — see Troubleshooting below for what that took on
Windows). `ios/` is not yet generated — that needs a Mac; from this
directory run `flutter create --org com.frontlineclub --project-name
frontline_club_app --platforms ios .` there when M10 starts.

```bash
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

## Troubleshooting: Android build fails with "Inconsistent JVM Target Compatibility"

Some plugins (`stripe_android`, `sentry_flutter` as of the versions pinned
in `pubspec.yaml`) don't consistently pin their own Kotlin/Java compiler
targets, so they inherit whatever JDK the Gradle daemon happens to default
to. On a machine with a very new JDK on `PATH` (e.g. JDK 25) that produces
exactly this error. `android/build.gradle.kts` already forces every
subproject to target JVM 17 — that's committed and should be enough on its
own. If it still fails on your machine:

1. Stop any running Gradle daemon: `cd android && ./gradlew --stop`
2. Pin a JDK 17+ LTS release (21 is what this was verified against) for
   Gradle specifically, in your **user-level** `~/.gradle/gradle.properties`
   (not this repo — that file is machine-specific and never committed):
   ```
   org.gradle.java.home=C:/Program Files/Java/jdk-21.0.11
   ```
3. Retry `flutter build apk --debug`.
