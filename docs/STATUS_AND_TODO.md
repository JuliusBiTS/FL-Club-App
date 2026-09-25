# What's still unfinished (audit, 25 Sep 2026)

Legend: **Placeholder** = visible in the app but doesn't do the real thing. **Needs setup** = code is done, waiting on an account/key/decision. **Needs testing** = built, never proven on real devices/real money.

## Placeholder in the app (visible to users)
| Where | State | What's needed |
|---|---|---|
| You → **Payment methods** | Shows "Coming in M3." | Remove, or build saved-cards once real Stripe is live |
| You → **Help** | "Coming later." | Write help/FAQ content + contact link |
| You → **Legal** (T&Cs, privacy notice) | "Coming later." Register form says you agree to terms that can't be read | **Highest priority** — need real T&C / privacy text from the club (and a data-protection contact); link both from Register and Legal |
| **Google sign-in** button | Button exists, provider not configured | Google Cloud OAuth client + Supabase Google provider + Android SHA-1 (+ iOS client ID). Or remove the button until then |
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
