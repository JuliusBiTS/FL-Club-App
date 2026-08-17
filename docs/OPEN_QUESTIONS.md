# Open questions

Do not guess at these — get real answers from the club. Nothing here blocks M0.

## Commercial — resolved, no action needed
Ticket prices vary per event and are always set in the admin console. Member rate is £5.
Loyalty rules are fixed (see `DECISIONS.md`). Free member reservations are explicitly out of scope for v1.

## Technical / access — these block real milestones, chase them early

- [ ] **Stripe** — access to the club's existing account (WooCommerce Stripe is already installed on the site) or authority to create a new one. Apply for the nonprofit rate at the same time. **Does not block M3 anymore** — the whole checkout flow (Edge Functions deployed, Flutter UI built) is done and waiting; see `docs/STRIPE_SETUP.md` for the exact remaining steps once access exists (two secrets + one webhook registration, no code changes).
- [ ] **Eventbrite** — organiser account API token (organiser ID `29840816681`). **Blocks M9.**
- [ ] **WordPress** — staging access + permission to install a small custom plugin (`wordpress-plugin/`). If custom plugins are refused, fall back to an iframe-free JS embed served from Supabase (worse for SEO, no plugin needed). **Blocks M8.**
- [ ] **Podcast RSS** — canonical feed URL from Spotify for Creators (show settings; Apple Podcasts show id `1744425242`). **Blocks M8.**
- [ ] **Membership inbox** — confirm `members@frontlineclub.com` as the destination for the `mailto:` interest flow. One email to the club. **Blocks M6.**
- [ ] **SHEEP CRM API** — unknown whether one exists. Explicitly *not* a dependency (CSV import covers v1). Worth asking at some point, must never delay M6.

## Brand — blocks M0's design tokens

- [ ] Logo in vector (SVG), plus a square club mark for the app icon and membership card. A flat JPG (no transparency) was pulled from the live site for the demo build — fine for a demo, not for shipping (can't recolor/resize cleanly for adaptive icons).
- [x] Primary brand colour — **not red**. Sampled directly from the live site: `#33460C` (dark olive), confirmed independently from the logo background, the nav bar, and the button background, all matching. `packages/flc_core/lib/src/theme/flc_colors.dart`'s `FlcColors.brand` now uses this. Near-black/body grey/background off-white were left as the original placeholders — they're brand-neutral and were never specifically red-derived.
- [ ] Font licensing — do the site's typefaces cover mobile app embedding? If not, `Source Serif 4` + `Inter` are the pre-approved free substitutes already wired into the theme.

## Operational — needed before launch, not before build

- [ ] Who supplies member photographs, and how do existing members get one on file? Likely the single largest non-technical task in the project — plan a capture session at the club plus a member-submitted upload path with admin approval.
- [ ] How many staff need scanner access, and on club-owned or personal devices?
- [ ] What happens today when a member's card is lost or a phone dies at the door? Confirm the guest-list + manual-code fallback (§9.11 of the briefing) actually matches how the door runs.
- [ ] Named data protection contact for ICO registration and the privacy policy.
- [ ] Has the club applied for the Apple Developer Program nonprofit fee waiver yet? Start early, it takes weeks.
