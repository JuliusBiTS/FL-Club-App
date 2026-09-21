# Switching on push notifications

The code is finished and deployed with the app; what's missing is a **Firebase
project** (Google's free notification service) to send through. Until then the
app runs normally with notifications simply switched off — nothing breaks.

Cost: Firebase Cloud Messaging is free with no limits (see `docs/DECISIONS.md`).

You need to do steps 1–3 yourself, in your own Google account; they can't be
automated.

## 1. Create the Firebase project

1. Go to <https://console.firebase.google.com> and sign in with the Google account
   that should own it (use the club's, or yours — same reasoning as Supabase: it
   should be an account you can keep).
2. **Add project** → name it e.g. *Frontline Club App* → you can turn off Google Analytics.
3. In the project, click the **Android** icon to **add an Android app**:
   - **Package name:** `com.frontlineclub.frontline_club_app`
   - Nickname: anything. Skip the SHA-1 for now.
   - **You do not need to download `google-services.json`** — this app takes the four
     values below from `dart_defines.json` instead, so no build files change.
4. Open **Project settings ⚙️ → General → Your apps → the Android app** and copy:

   | Firebase shows | Goes in `app/dart_defines.json` as |
   |---|---|
   | Web API Key (Project settings → General) | `FIREBASE_API_KEY` |
   | App ID (`1:123…:android:abc…`) | `FIREBASE_APP_ID` |
   | Project number (a.k.a. Sender ID) | `FIREBASE_MESSAGING_SENDER_ID` |
   | Project ID | `FIREBASE_PROJECT_ID` |

   These four are identifiers, not secrets — but keep them in the git-ignored
   `dart_defines.json` like the Supabase key.

## 2. Give the server permission to send

1. Firebase **Project settings ⚙️ → Service accounts → Generate new private key**.
   A `.json` file downloads. **This one is a secret** — never commit it, never paste it
   into chat, never put it in the app.
2. Store it as an Edge Function secret (from the `supabase/` folder; on Windows PowerShell
   the simplest way is to read the file into the command):
   ```powershell
   supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(Get-Content -Raw C:\path\to\the-key.json)"
   ```
   Then delete the downloaded file, or keep it in a password manager.
3. Deploy the function:
   ```bash
   supabase functions deploy send-push
   ```

## 3. Rebuild the app with the four values

```bash
cd app
flutter run --dart-define-from-file=dart_defines.json
```

In the app: **You → Notifications** → switch **Notifications** on → allow the phone's
permission prompt. (The prompt only appears when someone flips that switch, never at launch.)

## 4. Try it

1. Sign in as a staff or admin account on the phone, turn notifications on.
2. In the admin console open **Notifications**, write an announcement, press
   **Check who'll get it** — it should say 1 device — then **Send notification**.
3. Lock the phone first to see the real thing; with the app open you get an in-app banner.
   Tapping a notification about an event opens that event.

## How it works (for whoever maintains it)

- Each phone registers its Firebase token against the signed-in account
  (`register_device_token`, table `device_tokens`) only after the person switches
  notifications on. Signing out removes the token first, so the next person on that
  phone doesn't get the previous person's messages.
- Staff send from the editor or **Notifications** screen → the `send-push` Edge Function
  → which re-checks the caller is staff, works out the audience in Postgres
  (`push_recipient_tokens`: honours opt-in, each person's topic choices, membership and
  ticket ownership), rate-limits, sends through Firebase, deletes dead tokens, records the
  campaign (`push_campaigns`) and writes the audit log.
- People choose topics under **You → Notifications** (new events; recommendations & offers;
  loyalty rewards). Messages about an event you hold a ticket for (cancelled, moved) are
  always sent while notifications are on.
- Only in-app routes in a notification are ever followed (`/events/<slug>`).

## Not done yet

- **iOS**: needs a Mac, an Apple Developer account and an APNs key uploaded in Firebase. The
  Dart code is platform-neutral, but iOS hasn't been generated for this project yet.
- **Scheduled notifications** (send tomorrow at 9am), **event reminders**, and the "you've
  earned a free ticket" push (the loyalty SQL leaves a note that the caller should send it).
