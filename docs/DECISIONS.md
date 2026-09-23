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

## Event management (September 2026)

Decided with the club's Head of Digital & Events Producer; built in `supabase/migrations/20260921000001_event_management.sql` and `packages/flc_core/lib/src/events_admin/`. How-to: [EVENT_MANAGEMENT.md](EVENT_MANAGEMENT.md).

- **One editor, two surfaces.** The admin console (web) and the app's staff area use the same editor and list, shared from `flc_core`, so an event is authored identically anywhere.
- **Staff vs admin, enforced in Postgres.** Staff create, edit, publish and send notifications. While an event is a *draft* staff can also set price and capacity; once it is *live*, changing price/capacity, adding ticket types, cancelling and deleting are admin-only. Capacity can never fall below tickets sold; a ticket type with sales can be withdrawn, never deleted.
- **Notifications are available to staff without admin permission**, with rate limits (per person per hour; club-wide broadcasts per day) and an audit record of every send.
- **Highlights are `FC Highlights`, `Staff pick`, `Special offer`, plus up to four free-text perks** (e.g. "Free drink with your ticket"). **"Selling fast" is derived, never stored** (75% or more sold, not sold out), so it can't go stale.
- **Loyalty is switchable per event** (`loyalty_eligible`), applied by a trigger on ticket creation so the order functions are untouched. The scheme's rules (one point per person per event; free tickets never earn) are unchanged.
- **Event times are London time, always.** The editor never reads or writes the device's time zone (`LondonTime`), because staff may not be in London.
- **Descriptions are authored as light markdown** (`description_md`) and the sanitised HTML in `description_html` is generated from it on save — nobody types HTML, and nothing typed can inject markup.
- **Every change to events and ticket types is audited by a database trigger**, not by client code, so it cannot be skipped.
- **Push uses Firebase config from `--dart-define`**, not `google-services.json`, so enabling it needs no build-file changes. It is opt-in per person and asked for at the point of need, never at launch.

## Event auto-fill from pasted text (September 2026)

- **A new paid dependency, flagged per the rule above.** "Paste details to auto-fill"
  (`supabase/functions/extract-event-details/`) calls the Claude API to turn a pasted
  email/press release into a first-draft set of event fields. This is genuinely a paid
  third-party call, unlike everything else added so far — roughly 2-3 US cents per use
  (`claude-opus-5`, ~2,500 input + ~500 output tokens). Setup: [AUTOFILL_SETUP.md](AUTOFILL_SETUP.md).
- **Safe by construction, not by instruction.** Price, capacity, and ticket type are
  simply not fields in the response schema — there is no way for the model to return
  one, however the pasted text is worded.
- **Never overwrites.** Only fills fields that are currently blank on the draft; always
  shows a summary of what it filled, what it left alone, and anything it flagged for a
  human to check (an uncertain date, a guessed category).
- **Model choice belongs to whoever is paying** — defaults to `claude-opus-5` rather than
  a cheaper model, per Anthropic's own guidance not to auto-downgrade for cost.

## Accessibility notes removed (September 2026)

Added in the event-management work above, removed shortly after: the club can't
reliably offer this today, "now or in the future," per direct instruction. Rather
than leave a field nobody can vouch for, it's gone entirely — the column
(`events.accessibility_notes`), the editor field, and the display on the event page.
See `supabase/migrations/20260923000001_remove_event_accessibility_notes.sql`.

## UX polish and bug fixes (September 2026)

A round of feedback after the first hands-on pass with the app: too much text,
poor contrast on the membership handle, and a real bug where it could vanish
for the rest of a session. Fixed in one pass rather than piecemeal, since
several of these touch the same files.

- **Past events are now browsable.** `EventsRemoteDataSource.fetchPastPublished`
  + a dedicated `pastEventsProvider`, surfaced as a `Past` filter chip on the
  events feed (`events_feed_screen.dart`) — a plain reverse-chronological list,
  deliberately with none of the FC-Recommends grouping the upcoming feed has,
  since "what's next" and "what happened" are different questions.
- **The event detail page is quieter.** Practical facts (date, time, venue,
  online/members-only/filmed) now sit in one bordered block instead of a bare
  stack of icon rows; the filming disclaimer is a one-line caption ("Filmed —
  may be shared publicly") instead of a full sentence; the loyalty line moved
  out of the facts block to sit by the Tickets header, where it's relevant.
  Body text got `height: 1.5` — the actual "hard to read" complaint was
  line-height, not font size.
- **Staff picks are a quote, not just a tag** (`StaffPickBubble` in
  `packages/flc_core/lib/src/widgets/`), Waterstones-style: a staff photo,
  name, and a short reason the event is worth attending
  (`events.pick_by_name` / `pick_by_photo_url` / `pick_quote`, ≤280 chars —
  see `supabase/migrations/20260924000001_event_staff_quotes.sql`).
  Deliberately independent of `highlight`/ribbons — any event can carry a
  quote regardless of whether it's also FC Highlights or a special offer.
- **The membership handle's "disappears quite often" bug is fixed at the
  root, not patched.** The old code set a boolean to `false` the first time
  any podcast episode ever played and relied on remembering to set it back —
  unsafe the moment the screen holding that logic lives in a
  `StatefulShellRoute` branch that's never disposed (which the podcast/media
  tab did). Replaced with `MembershipHandleMode` (`full` / `dot` / `hidden`),
  computed fresh every build in `AppShell` from live state — current tab,
  whether audio is loaded, and whether a pushed screen (ticket bar, article,
  scanner) has claimed the strip — so there's nothing to forget to reset.
- **The handle got visible contours** (border + shadow, see
  `_kHandleBorder`/`_kHandleShadow` in `membership_card_handle.dart`) so it
  reads as a control sitting on top of the app rather than blending into the
  brand-olive bars above and below it — plus a minimised "just a dot" mode,
  user-toggleable from the You tab (`alwaysShowDotProvider`, backed by
  `shared_preferences` — a UI preference, not sensitive data).
- **A hardcoded membership card entry lives permanently on the You tab**
  (`_MembershipCardTile` in `account_screen.dart`), independent of the
  drag-handle — one guaranteed way in that never moves or disappears.
- **Podcast and video merged into one "Listen" tab**
  (`features/listen/listen_screen.dart`), filterable by type and, for
  podcasts, by season — two browsing tabs for what's fundamentally one
  content feed was the actual complaint, not that video existed.
- **A splash animation was added** (`features/splash/splash_overlay.dart`):
  the club's logo flips into the strapline "The home of independent
  journalism" over ~2s, then fades into the app. Set in **Jost**
  (SIL OFL, bundled as `assets/fonts/Jost-Variable.ttf`) rather than Futura,
  which is commercially licensed — Jost is a widely-used free geometric
  substitute for the same brand feel. The native Android launch background
  was also changed from white to brand olive, so there's no colour flash
  before the animated splash takes over.

## Post-demo bug fixes (September 2026)

Feedback after the first APK install of the round above.

- **The demo APK's broken login and a "vanished" event were a build mistake,
  not a code bug.** It was built with a plain `flutter build apk --release`
  instead of `--dart-define-from-file=dart_defines.json`
  ([ANDROID_DEMO.md](ANDROID_DEMO.md) already documented the right command —
  this build just didn't follow it). `Env.assertConfigured()`'s check is an
  `assert`, which is stripped in release mode, so it shipped silently with an
  empty Supabase URL: sign-in failed outright, and everything else ran on
  whatever was last cached — including the events feed, which is deliberately
  stale-while-revalidate (see `EventsFeedController`), so a newly-added event
  that arrived after the last successful sync just wasn't in that cache yet.
- **"FC Recommends" renamed to "FC Highlights"** everywhere it's shown.
  Collapsed a duplicated hardcoded copy of the label in `EventBadges` down to
  `EventHighlight.badgeLabel`, the one place the editor's picker already read
  it from — two copies of the same string is exactly how it went stale.
- **Every article now shows a picture**, even with no hero image set —
  `ArticleHeroFallback` (the club's logo on brand olive), matching what
  `EventHeroFallback` already does for events.
- **The merged Podcast+Media tab is labelled "Media"**, not "Listen" — it
  carries video too, and the tab name should say so.

## Second round of feedback (September 2026)

- **Events are always strictly chronological now, even on "All".** The
  previous "lift FC Highlights into its own section at the top" grouping
  is gone — it directly conflicted with a repeated, explicit ask for
  chronological order. A highlight still shows as a ribbon on its card; it
  just no longer reorders the list. Also renamed the "This week" filter to
  "In the next 7 days", which is what it always actually did.
- **One filter button instead of a scrolling chip row.** All/Next 7 days/
  Offers/Members only/category now live in a bottom sheet behind a single
  `Filter` button (with a dot when a non-default filter is active).
  Upcoming vs Past is a separate segmented toggle above it, not one more
  option in that sheet — it's a different query and sort direction, not a
  filter on the same list.
- **The event page's title moved below the hero image**, not layered over
  it — most event photos already have their own text (flyers, posters),
  so stacking a second layer of text on top of that was often unreadable.
  It still appears in the collapsed app bar once scrolled, for context.
- **A hardcoded amount of bottom padding on the event page** now reserves
  space for the floating membership handle's bottom-right corner, so it
  can't end up overlapping whatever content happens to fall there for a
  given event's length.
- **A dedicated success screen after signing in or registering**
  (`AuthSuccessScreen`), instead of silently popping back to whatever
  screen asked for it — checkout's own inline account step is unaffected,
  since finishing checkout is already its own feedback there.
- **"Become a member" now offers a way back to sign-in** for a guest who
  already has an account, and re-fills the form the moment someone signs
  in from that shortcut mid-flow, rather than making them retype an email
  they already have on file.
- **The membership card sheet distinguishes "not a member yet" from a
  broken card.** get-member-card's 403 is an expected, common state (a
  signed-in guest or staff account), not a failure — it now gets its own
  screen with a "Become a member" button instead of a generic red error.
- **Dark mode is switched on** — `FlcTheme.dark()` already existed but was
  never reachable; added a light/dark/system toggle under You → Appearance,
  persisted via `shared_preferences`. Audited every place brand olive was
  used as text or an icon colour (a category label, "Members only", a
  speaker's initials, …) and routed them through the new
  `FlcColors.accent(context)`, which brightens to `brandOnDark` in dark
  mode — dark olive on the dark theme's near-black surface was unreadable
  otherwise. Brand olive as a *background* (the app bar, the bottom nav,
  the membership handle) is unaffected — it's meant to stay the same in
  both themes.
- **A test-payment mode**, so the whole ticketing flow — order, ticket
  issuance, loyalty, confirmation — can be exercised before the club
  connects a real Stripe account. `create-order` returns a `test_mode`
  order (no PaymentIntent) whenever `STRIPE_SECRET_KEY` isn't set; a new
  `simulate-test-payment` function then marks it paid exactly like a real
  webhook would. Safety is structural, not just UI: that function refuses
  every request outright the moment a real `STRIPE_SECRET_KEY` is set, so
  it can never become a free-ticket path once payments go live, and it
  independently verifies the order belongs to the caller before touching
  it. The client shows it as a clearly labelled "Test payment — no Stripe
  account connected" step, never blended in with a real charge.
- **The event editor can copy venue/category/promotion settings from the
  last event** (`EventDraft.applyRecurringSettingsFrom`), and remembers
  everyone who's ever been given a staff pick so a producer can choose
  them from a list instead of retyping a name and re-uploading a photo
  every time (`EventAdminRepository.recentStaffPickPeople`, derived from
  past events rather than a table of its own — it can't go stale). Neither
  ever touches dates, capacity or ticket pricing, which always need a
  fresh look. (Along the way: fields fed by a bulk copy like this need a
  generation-keyed rebuild, not just `touch()`, or a `TextFormField`'s own
  `initialValue` won't visibly update — see `EventEditorController.
  formGeneration`.)
- **The podcast tab is now live** — `PODCAST_RSS_URL` was the only missing
  piece; `podcast-sync` runs hourly via pg_cron and was already fully
  built.
- **YouTube auto-sync and combining ticket types in one order are
  deliberately deferred.** The first needs the club's channel and a
  Google Cloud API key, neither in hand yet. The second means a real
  schema change (today's `orders` row is one ticket type × quantity, not a
  cart) touching order creation, payment, refunds and every screen that
  displays an order — exactly the kind of money-handling change that
  deserves its own focused pass rather than being squeezed in alongside
  everything above.
