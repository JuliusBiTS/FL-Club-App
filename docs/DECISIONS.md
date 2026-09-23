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

## Third round of feedback (September 2026)

- **Sign-in's success screen is shown in place, not by navigating to a new
  route.** The previous version used `Navigator.pushReplacement` on top of
  go_router's own declarative Navigator for that route — go_router
  rebuilds/reconciles that Navigator's page stack the moment auth state
  changes (`_ProfileRefreshListenable`, which fires right after a
  sign-in), silently discarding the imperatively-pushed screen underneath
  it. Real bug, not a preference: swapping the same screen's own body in
  place (same pattern as `MembershipInterestScreen`'s `_SubmittedState`)
  sidesteps the conflict entirely rather than working around it.
- **A real bug in the offline event cache**: it only ever upserted, never
  pruned — an event that stopped being "upcoming" server-side (date
  passed, unpublished) had no way to ever leave the cache, so a stale copy
  could sit there indefinitely and mix into the "Upcoming" list. The
  upcoming feed's cache write is now a full replace each refresh
  (`AppDatabase.replaceUpcomingEvents`, transactional delete+insert — the
  same pattern `replaceAllTickets` already used), and the cached read now
  also filters `starts_at >= now` itself as a second line of defence, not
  just the remote query. A single event's own detail-view cache (upsert,
  unaffected) is a separate method precisely so this fix couldn't touch it.
- **The membership card's "always loading" was a real bug**: reading the
  cached card ran outside the `try`/`catch` around the live refresh, so
  any exception there (`flutter_secure_storage` genuinely can throw — a
  reinstall invalidating its keystore entry is a known real-world trigger)
  left `_loading` stuck `true` forever with nothing to ever set it back.
- **FC Highlights lifted-to-top is back** — direct feedback reversed the
  previous round's removal. It coexists with strict chronological order:
  the section itself, and "Coming up" below it, are each still sorted
  soonest-first — only the highlighted events move as a whole group ahead
  of everything else, same as before that removal.
- **A comprehensive dark-mode contrast pass**, beyond last round's brand
  olive fix: `FlcColors.slate` (secondary text, ~55 call sites), `graphite`
  (the perk chip's text — confirmed near-invisible in a screenshot),
  `error` and `success` all measured under the 4.5:1 WCAG AA minimum
  against the dark theme's surface — a single fixed colour can't pass
  contrast against both a near-white and a near-black background at once,
  so each now resolves through a `BuildContext`-aware helper
  (`FlcColors.secondary/secondaryStrong/errorAccent/successAccent`) the
  same way `accent()` already did for brand olive.
- **The filter button always just says "Filter"**, never the active
  filter's own name — showing a long category name there was growing the
  button until the Upcoming/Past segmented control next to it ran out of
  room and its own labels wrapped. The dot is the only "something's
  filtered" signal now.
- **The 5 hand-seeded "placeholder" media_posts rows are gone** (real
  videos from the club's own channel, but static and no longer
  distinguishable from genuinely-synced content once the podcast feed
  actually started syncing for real) — deleted from the database and the
  seed script.
- **A real "Content" admin section**, replacing that placeholder —
  feedback: "how do you edit the media tab? Any way for an admin to do
  changes there?" A "sync now" button each for the podcast feed and
  WordPress (both already auto-sync hourly via pg_cron; this is just for
  "right now, don't wait"), plus manual add/remove for YouTube videos
  (`MediaAdminRepository`, `MediaContentScreen`, shared by the admin
  console and the app's staff area) — deliberately NOT extended to
  podcast_episodes, which stays fully owned by the RSS sync's upsert-by-
  guid; a hand-added row with no guid would sit oddly next to synced ones.
- **Articles fall back to their own first image** when the club hasn't set
  a hero image — `ArticleModel.displayHeroImageUrl`, extracted from
  `content_html` — before falling back further to the logo placeholder.
- **The ticket screen's back button always returns to the tickets
  overview**, never wherever plain back-navigation would otherwise land —
  it's a route outside the shell (like checkout), reachable from more
  than one place, so a plain pop can't be trusted to always have that
  list underneath it.
- **The order confirmation screen now shows real order details** (event,
  ticket type, quantity, total paid — the same `CheckoutArgs` already
  confirmed on the review step, not re-fetched, so it can never disagree
  with what was just agreed to) plus a quiet, smaller echo of the boot
  splash's brand olive and Jost strapline: "Thank you for supporting
  independent journalism" — a nod to that moment rather than a second
  full-screen takeover, since this sits inside an already-busy flow, not
  someone's first impression of the app.
- **A "Sold out" tag**, mirroring "Selling fast"'s existing derived
  design exactly (`events_sold_out()`, same shape as `events_selling_fast()`
  — only event ids ever leave the database) — solid rather than tinted,
  since it's the one ribbon that changes whether someone can act at all.
- **Push notifications are fully built and deployed, waiting only on a
  Firebase project** (`docs/PUSH_SETUP.md` has the complete walkthrough) —
  same category as Stripe and YouTube: an external account only the club
  can create.

## Fourth round (September 2026)

- **The event picture is shown whole, with nothing over it.** The old
  detail page cropped it to a fixed 240px, put the toolbar over its top
  edge and laid a dark gradient on it — hiding parts of posters that have
  their own text. Now: a plain toolbar above, the picture full width at its
  own proportions below, no gradient, no title, no badges on it. (Feed
  cards still crop to 16:9 to keep the list even; the full picture is one
  tap away.)
- **Content warnings** (`events.content_warnings`, up to 5 short free-text
  lines, e.g. "May include distressing footage", "Contains flashing
  images"). Free text rather than a fixed list because what's worth
  warning about varies by event; the editor offers one-tap suggestions.
  Shown as a "Content note" panel on the event page above the description,
  and a small marker on the feed card. Deliberately not copied by "copy
  settings from last event" — they belong to one event.
- **Registration groundwork for the user site**
  (`20260925000003_user_registration.sql`): profiles gain city, country,
  interests, how-heard, privacy version and a database-stamped
  marketing-consent time (users can edit them; the guard trigger still
  only protects the privileged columns). `event_interests` lets a
  signed-in person register interest in an event under RLS, and guests do
  it through `register_event_interest()` (upcoming published events only,
  flood-capped). `event_interest_counts()` exposes counts only. No UI yet —
  the app and a future website will share these same tables.
- **SHEEP CRM link, vendor-neutral first**
  (`20260925000004_crm_members.sql`, `crm-sync` function). SHEEP's API
  details aren't known yet, so the CRM-specific part is one clearly
  marked, unverified `mapSheepRecord` + fetch in the function; everything
  around it is built and works today via a manual import: a `crm_members`
  staging table, `crm_reconcile_preview()` (read-only), and
  `crm_reconcile_apply()` (audited, admin only, a separate deliberate
  step). Safety rules baked in: only a CRM "active" record can activate an
  existing account with the same email; "lapsed/cancelled" lapses; a
  person absent from the CRM is only **flagged** (honorary/lifetime and
  hand-granted members may legitimately not be in it); suspended is never
  overridden; the `crm_member_id` link is added to the profiles guard so
  nobody can point their own account at someone else's CRM record. This
  refines — doesn't replace — the earlier "CSV import with confirm-diff"
  decision: the CSV path still feeds the same staging table.
- **The app now shows its build number** (You tab footer), and the build
  number is bumped per build handed over — after a debugging session where
  every build reported `0.1.0+1` and nobody could tell which one a phone
  was running. Also added a date-order flip button beside Filter.

## Fifth round (September 2026)

- **Users, members, staff (admin console).** One `UsersScreen` in flc_core, shown three ways: Users (everyone), Members (active only), Staff (staff + admins). Reads via the admin RLS policy on `profiles`; every change goes through the `admin_update_user` SQL function, which re-checks admin, refuses removing your own admin access or the last admin, and writes the audit log. Promoting someone = they register first, then an admin finds them under Users and sets Access.
- **Registration.** The app's Register form now collects full name and requires the terms/privacy tick (marketing is a separate optional tick). Details ride as sign-up metadata and are copied into the profile by `handle_new_auth_user`; the database stamps the consent times, the client never does.
- **Manual content.** Content screen can add/remove videos, podcast episodes and blog articles. Hand-added rows are namespaced so the syncs can never touch them (podcast guid `manual:…`, article `wp_post_id` null) and only those are listable/deletable there. Staff-write RLS added on `media_posts`, `podcast_episodes`, `articles` (migration …05). The five original YouTube videos were restored.
- **Account picture.** New Edge Function `profile-photo` (get/set/remove) is the only door to the private `membership-photos` bucket: acts as the caller, only touches `<uid>/…`, checks JPEG/PNG magic bytes, 1.5 MB cap, rate-limited (10/h), audited, short-lived signed URLs only. The phone downsizes/re-encodes (640px) before upload. The same picture appears on the account header and the membership card, and staff see it when scanning.
- **Your details screen** (You → Your details): name, display name, phone, news opt-in. Membership fields stay admin-only (DB trigger).
- **Scanner fixes.** Door and Membership tabs each started their own camera and fought over it; now a single `ScanCamera` owns its controller, releases the camera when hidden, ignores the same code for 4 s (stops re-submits after dismiss/error), and explains a blocked camera. Door lookup can no longer leave the scanner stuck busy. Manual membership-number lookup ignores case/spaces. Verified live end to end: member card → QR → staff `verify-scan` (valid), manual lookup (identified only), bad QR, unknown number, and non-staff refused.

### Fifth round, continued
- **Admin menu cleaned up.** Now: Dashboard, Events, Orders, People, Articles, Media, Notifications, Audit log (staff see Events + Notifications only). Removed the empty placeholders (Attendees, Loyalty, Applications); Users/Members/Staff merged into People (filters cover members, staff, applied). Dashboard and Audit log are real read-only screens.
- **Stories & articles** got a proper manager (list, search, filters, editor page with picture, draft/publish) modelled on Events. Migration …06 adds `articles.status` (draft/published); the public only reads published. Website-synced articles are shown read-only.
- **Button bug:** the theme's filled buttons have infinite minimum width, which squeezed the "Videos" heading in a Row and hid the Add button; Row-placed buttons now set their own minimum size. Outline buttons use the context-aware accent colour (was dark green on dark).
- **Events feed:** the date-order arrow lives inside the Filter pill (one control; on Past it's the only part).
- **Article AI never writes.** `extract-article-details` no longer returns any model-written text. The model only points at passages (verbatim quotes, each verified by substring match against the paste) and classifies Story/Blog; the article body is the original text with the headline/byline/email wrapper cut out by code (never more than 40% removed). The summary line is a verbatim quote from the piece or empty. Model notes are shown to the editor only.
- **Manual availability tag** on events (Automatic / Selling fast / Sold out), `events.availability_tag`; display only, never blocks or allows purchase. Splash strapline is now "Championing independent journalism".
