# What's still unfinished (audit, 25 Sep 2026)

Legend: **Placeholder** = visible in the app but doesn't do the real thing. **Needs setup** = code is done, waiting on an account/key/decision. **Needs testing** = built, never proven on real devices/real money.

## Placeholder in the app (visible to users)
| Where | State | What's needed |
|---|---|---|
| You → **Payment methods** | Muted "Soon" row, no dead tap (1 Oct tidy-up) | Build saved-cards once real Stripe is live |
| You → **Help** | Muted "Soon" row | Write help/FAQ content + contact link |
| You → **Legal** (T&Cs, privacy notice) | Muted "Soon" row. Register form still says you agree to terms that can't be read | **Highest priority** — need real T&C / privacy text from the club (and a data-protection contact); link both from Register and Legal |
| **Google sign-in** | Hidden (1 Oct) rather than a broken button — was calling an unconfigured provider | Bring back once Google Cloud OAuth client + Supabase Google provider + Android SHA-1 (+ iOS client ID) exist. Code still in `AuthRepository.signInWithGoogle` |
| **Tickets** and **QR codes** | Built and tested on the server side, but only with test-mode orders | Test on real phones: buy → ticket shows → QR rotates → staff scans; offline scanning; refunded tickets |
| **Payments** | Test mode (fake payment) unless Stripe keys set | Stripe account + 2 secrets + webhook (docs/STRIPE_SETUP.md); then test real card, refund, failed payment |
| Order **confirmation emails** | Not sent (TODO in stripe-webhook) | Email service (Resend/SendGrid or similar) + templates; also ticket resend from admin |
| **Membership PIN** | Stored plain, returned as-is (TODO to encrypt) | Encrypt at rest before real members |
| App **login emails** (verify email, reset password) | Supabase's built-in sender, email confirmation OFF | Set custom SMTP, branded templates, turn confirmation on, set redirect URLs for password reset deep links |
| App **icon / launcher / store listing** | Flat JPG logo, debug signing key | Vector logo, proper icon, release keystore, Play Store listing, privacy policy URL |
| **Loyalty** | Works, rules fixed | Test end-to-end with real attended tickets |

## Needs setup (blocked on club decisions/accounts)
- **Stripe** (real payments, refunds, nonprofit rate)
- **Eventbrite** API token (sync not running)
- **YouTube** API key (videos are hand-added; no auto-sync/live detection)
- **SHEEP CRM** API docs + sample record (CRM sync is a guess until then; API key set by you in Supabase secrets, never in chat)
- **Firebase push**: tested path needs a real-phone test; iOS needs Apple push key
- **Sentry** DSN (crash reporting currently off)
- **Membership photos**: who takes them, how members upload; approval step? (members can now upload their own via Your details; staff review at the door only)
- **Apple Developer** account / nonprofit waiver for iPhone builds
- Instagram/Meta feed: out of scope until access exists

## Admin console
- **Orders**: no resend-confirmation; refunds untested with real Stripe
- **Dashboard**: basic counts only; **Audit log**: read-only list (no export)
- No **attendee list / CSV export** per event, no **loyalty adjustment** screen (removed empty placeholders; build when needed)
- **Applications** queue is only the "Applied to join" filter under People (no approve/reject-with-notes flow yet)
- Admin password-reset flow untested

## Needs real-device testing (never run on hardware)
- Scanner camera (door + membership) on the latest build
- Account photo upload (camera + gallery), membership card photo
- Push notifications (app on/off, tap to open)
- Checkout end to end, ticket wallet offline, dark/light contrast on device
- Web preview in mobile Safari (camera/audio)
- Event ordering bug: confirm on a fresh install (build number shown in You footer)

## Not started / deferred
- Combined ticket types in one order (e.g. 1 member + 2 standard)
- Interest registration UI in the app (database is ready)
- Accessibility pass (screen reader labels, font scaling), localisation
- Feed cards crop pictures to 16:9
- Automated tests are thin (crypto, event editor, feeds); none for checkout, scanner, user admin

## Code tidy-up pass (1 Oct 2026)
`flutter analyze` is clean with zero issues across `app/`, `packages/flc_core/`, `admin/`; spacing and colour usage were swept for stray hardcoded values outside the theme (none of concern found — the few hardcoded hex colours left, e.g. the membership card and scanner overlay, are deliberate fixed-palette surfaces, not bugs). Fixed: a lingering `flutter analyze` lint in `app.dart`; three dead-end rows (Payment methods, Help, Legal) that popped a snackbar with internal milestone jargon ("Coming in M3") now read as a plain, muted "Soon" row instead; the Google sign-in button (calling an unconfigured OAuth provider) is hidden rather than left to fail silently/confusingly when tapped.

## Potential next features (not started, worth considering)
- **Search** across events/articles/podcast — there's no search bar anywhere in the app yet.
- **Calendar export** — "Add to calendar" on an event/ticket (.ics).
- **Apple/Google Wallet pass** for tickets and the membership card, instead of only the in-app QR.
- **Saved/favourited events**, and a "notify me" per-event toggle instead of only broadcast pushes.
- **Referral or "bring a guest"** flow for members.
- **In-app event interest/waitlist** for a sold-out event (the data model already supports "interest"; no UI yet).
- **Richer loyalty**: visible tiers/rewards catalogue, not just a point count.
- **Staff-side check-in stats**: live attendee count at the door during an event, not just scan-by-scan.
- **Member renewal reminders**: a push/email N days before `membership_expires_at`.
- **Admin bulk actions**: e.g. select several People rows and change status at once; CSV export of attendees/orders.
- **Article/podcast comments or reactions**, if the club wants more community feel.
- **Offline reading**: cache the last few articles/episodes for the Tube.
- **Dark-mode-aware event images**: a subtle scrim so light photos stay legible on dark cards (cosmetic, low priority).
- **Admin dashboard charts** (ticket sales over time, membership growth) instead of plain counts.
- **Multi-language support** — currently en-GB only, deliberately, per the brief.
