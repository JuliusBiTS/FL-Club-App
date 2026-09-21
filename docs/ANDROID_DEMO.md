# Putting the app on an Android phone

Two ways: **install an APK** (a file you copy to the phone — no cable, no laptop needed
afterwards) or **run it live from the laptop** over USB while you edit. The APK is best
for showing people.

## Before either: load the database (once)

The app shows whatever is in the Supabase database, so run these in the Supabase
dashboard → **SQL Editor** (see [EVENT_MANAGEMENT.md](EVENT_MANAGEMENT.md)):

1. `supabase/migrations/20260921000001_event_management.sql`
2. `supabase/seed_demo_events.sql` (11 made-up events)

## A. Build and install an APK

Build (from the `app/` folder; needs `app/dart_defines.json` with your Supabase URL and anon key):

```cmd
flutter build apk --release --dart-define-from-file=dart_defines.json
```

The file appears at `app/build/app/outputs/flutter-apk/app-release.apk` (about 100 MB).

Get it onto the phone by any of:

- **OneDrive** — the project lives inside OneDrive, so open the OneDrive app on the phone and download the file.
- **USB cable** — copy the file into the phone's Downloads folder.
- **Email / Google Drive / WhatsApp to yourself.**

On the phone: open the file → Android asks to allow installs from that app (Files, Chrome,
OneDrive…) — allow it → **Install**. If **Play Protect** says the app is unverified, choose
**Install anyway**: this is your own build, signed with a debug key, and not for the Play Store.

## B. Run live from the laptop (USB)

1. Phone: **Settings → About phone → tap Build number 7 times**, then
   **Settings → System → Developer options → USB debugging** on.
2. Plug in the cable; accept **Allow USB debugging?** on the phone.
3. Check it is seen: `flutter devices`
4. From `app/`: `flutter run --release --dart-define-from-file=dart_defines.json`

## What works in the demo build

Works: browsing events (ribbons, FC Recommends, speakers, links), filters, sign-in with the
demo accounts, the membership card, the staff tools (**You → Staff**), creating and editing events.

Not yet: **payments** (Stripe isn't connected — checkout says so), and **push notifications**
(no Firebase project yet — [PUSH_SETUP.md](PUSH_SETUP.md)).

Demo accounts (password `FrontlineDemo2026!`): `demo.member@…`, `demo.staff@…`, `demo.admin@frontlineclub.dev`.

## Notes on the build (why three Android files were changed)

`flutter build apk --release` runs stricter checks than the debug builds used day to day, and
three things stopped it. All fixed in `app/android/`:

- **Stripe and R8 (the release shrinker)** — `flutter_stripe` refers to a Stripe class that
  isn't shipped, so R8 stopped. `app/android/app/proguard-rules.pro` tells it that's fine.
- **Older plugins built for Android 34** — `file_picker` and `device_info_plus` are compiled against
  an older Android than the rest now requires; `app/android/build.gradle.kts` lifts any plugin
  below 36 to 36.
- **Lint and `play-services-tapandpay`** — Stripe's push-provisioning module depends on a Google
  library that isn't on any public repository, so Android's pre-release lint check can never
  finish; it's switched off for release builds (`app/android/app/build.gradle.kts`).

**Slow or flaky internet** can time out while Gradle downloads its (large) build tools —
"Read timed out" / "No route to host". Just run the build again; finished downloads are kept. To be more
patient in one go (PowerShell): `$env:GRADLE_OPTS="-Dorg.gradle.internal.http.socketTimeout=300000"`.
