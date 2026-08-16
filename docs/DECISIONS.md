# Decisions already made

Don't relitigate these — they were settled with the client before build started.

- **Flutter**, single codebase, Android first, iOS from the same source.
- **Supabase** on the free tier, EU/UK region, RLS enabled on every table with no exceptions.
- **Stripe** direct for all payments — not Eventbrite, not WooCommerce, not in-app purchase. Tickets and membership are physical goods/services consumed outside the app, so store commission does not apply (Apple Guideline 3.1.3(e), Google Play physical-goods policy). Note this in store reviewer notes.
- **Staff scanner lives inside the same consumer app**, gated by role — no second app.
- **Membership is never sold in-app.** Interest flow only: in-app form + prefilled `mailto:` → club reviews → club collects the £365/yr fee outside the app → admin activates `member_status` manually. This keeps the app clean of digital-goods store-commission questions and lets the club keep vetting applicants.
- **Ticket prices vary per event** and are always read from `ticket_types.price_minor` in the database — never hard-coded, no client-side price arithmetic beyond `price × quantity`. Only the £5 member rate is a standing convention (pre-filled on event creation, still editable).
- **Members pay £5 per ticket, always a real Stripe transaction.** The free-reservation-with-no-show-charge model described in the club's Terms of Sale is explicitly out of scope for v1 — do not build it speculatively. `ticket_types.price_minor = 0` already supports it if the club asks later.
- **Loyalty: 1 point per event per person, not per ticket.** Buying 4 tickets to one panel earns 1 point. Enforced by a partial unique index (`loyalty_one_point_per_event_per_user`), not application code. Member £5 tickets count toward loyalty. Threshold is 10 tickets → 1 free ticket. Launches on `count_mode = 'purchased'`, with `'attended'` (scan-based) mode fully built and config-switchable by a single admin toggle — switching must not retroactively remove already-earned points.
- **Loyalty rewards are spendable on any event and ticket type the user is already eligible for**, including members-only events and the £5 member rate — no extra restriction layered on top.
- **Membership sync with SHEEP CRM is CSV import with a confirm-diff**, not an API integration. SHEEP is explicitly not a v1 dependency — the admin console's manual activate/suspend/renew alone is sufficient to run the app.
- **Events are authored once, in the new admin console.** The WordPress site renders from a read-only, cached Supabase endpoint via a small custom plugin (`[frontline_events]` shortcode). The backend is the single source of truth for events, not WordPress.
- **Eventbrite runs in parallel** with a fixed capacity split per event (`capacity_app` + `capacity_eventbrite` ≤ `capacity_total`), synced read-only every 5 minutes. Direction of truth is Eventbrite → app only; we never write to Eventbrite. Migration to 100% app happens via an admin-console allocation slider, event by event — no code changes needed to complete it.
- **The podcast comes from the existing public RSS feed**, not the Spotify SDK — free, no auth, no branding constraints.
- **English (en-GB) only** at launch, but every string is externalised via ARB files from day one so other languages are a drop-in later.
- **Free/cheap by default** (target £0–25/month at this scale — see cost table below), **but security is never the thing that gets cut.** If a cost decision and a security decision conflict, security wins and gets flagged.
- **No paid third-party SDK, managed service, or per-seat tool** without flagging it first. `mobile_scanner` + `barcode_widget` cover scanning/barcodes for free.

## Cost stack (target £0–25/month)

| Item | Cost |
|---|---|
| Supabase | Free tier to start; Pro (~$25/mo) only once storage or the 7-day inactivity pause becomes a problem |
| Stripe | No monthly fee, ~1.5% + 20p per UK card transaction — apply for the nonprofit rate |
| Firebase Cloud Messaging | Free, unlimited |
| Admin console hosting | Free (Cloudflare Pages / Netlify) |
| Error monitoring | Sentry free tier (5k errors/mo) |
| Analytics | PostHog free tier or Firebase Analytics — privacy-first, opt-in only |
| Google Play Developer account | $25 one-time |
| Apple Developer Program | $99/yr, likely £0 — apply for the nonprofit fee waiver early, it takes weeks |
| Podcast hosting | £0, we consume the existing RSS feed |

## Threat model summary

See the HMAC ticket/membership signing scheme documented at the top of `supabase/migrations/` and in `supabase/functions/_shared/`. Three assurance tiers on the membership card, and the UI must always distinguish them:

1. **Identification** — Code128 barcode + membership number + 4-digit PIN. Convenience only (bar tab, reception). Never sufficient for a member discount.
2. **Authentication** — 30-second rotating HMAC-signed QR, verified by the scanner. Required for the member ticket price / member-only entry.
3. **Verification of person** — staff compares the on-screen member photo to the person in front of them.

The member discount requires tier 2 **and** tier 3. A barcode and PIN are a username, not a password.
