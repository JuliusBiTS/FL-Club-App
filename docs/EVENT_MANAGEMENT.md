# Event management

How the club creates, edits, promotes and announces events — in the **admin
console** (a web page, best at a desk) and in the **mobile app** (for staff, on
the go). Both use the *same* editor, so an event looks and behaves the same
wherever it was made.

## Turning it on (one-off, per Supabase project)

1. **Apply the migration.** From the `supabase/` folder:
   ```bash
   supabase db push
   ```
   This adds the new event fields, the staff permissions, the audit trail and the
   notification tables (`supabase/migrations/20260921000001_event_management.sql`).
   Migrations run in a transaction: if anything is wrong, nothing is changed.
2. **(Optional) Load the demo events** so there is something to show. In the
   Supabase dashboard open **SQL Editor**, paste the whole of
   `supabase/seed_demo_events.sql` and run it. It creates 11 made-up events (every
   format, ribbons, perks, a "selling fast" one, a scheduled one, a draft and a
   past one). Safe to run again. Remove them later with the line at the top of that file.
3. **Deploy the notification function** (only needed for push, see
   [PUSH_SETUP.md](PUSH_SETUP.md)):
   ```bash
   supabase functions deploy send-push
   ```

## Who can do what

The rules are enforced in the database, not just by hiding buttons.

| | Staff | Admin |
|---|---|---|
| Create events, edit anything on them, upload pictures | yes | yes |
| Publish, unpublish (if nothing sold), postpone, archive, duplicate | yes | yes |
| Set price and capacity **while the event is a draft** | yes | yes |
| Change price / capacity **once the event is live** | no | yes |
| Add a ticket type to a live event | no | yes |
| Cancel an event (with optional refund of every order) | no | yes |
| Delete an event (only if it has no orders) | no | yes |
| Send push notifications | yes | yes |
| See the change history of an event | no | yes |
| Orders, members, loyalty, audit log, everything else in the console | no | yes |

Capacity can never be lowered below tickets already sold, and a ticket type that
has sold tickets can be taken off sale but not deleted — for everyone.

## Creating an event

Open **Events → New event** (console) or **You → Manage events** / the pencil icon
on the Events tab (app, staff only).

The editor is one page of sections. On a wide screen a **live preview** of the
event card and a **"Before you publish" checklist** sit on the right; on a phone
tap the eye icon.

- **The basics** — title, subtitle, a short summary (this is what appears on the
  card), category and tags.
- **When & where** — start, end and doors time, room, address, and whether it is
  online. **All times are London time**, whatever time zone you are in.
- **Pictures** — the main picture (16:9) and a gallery. With no picture the app
  shows the olive category artwork, so nothing looks broken.
- **About this event** — the description, with bold / italic / heading / list / link
  buttons and a **Preview** button. The filming notice goes here too.
- **Speakers** — name, role, bio, photo, in the order they should appear.
- **Links** — buttons on the event page, e.g. *Buy the book*, *Watch the trailer*, *Donate*.
- **Tickets & capacity** — total seats, how many are sold in the app and how many
  are held for Eventbrite, and the ticket types (Standard / Member / Concession, or
  your own). **"Use the club's standard tickets"** fills in the three usual rows
  from the club's defaults (stored in the database in `club_settings`, so prices are
  never hard-coded in the app).
- **Membership & loyalty** — *Members only*, and *Counts towards loyalty*, with a live
  summary of how it reads to people. Switch loyalty **off** for private, partner or
  fundraising events.
- **Promotion** — see below.
- **Notifications** — appears once the event is saved.

**Save draft** keeps it private. **Publish** makes it live. If you set *Publish
automatically at* the button becomes **Schedule** and the database publishes it
at that time (checked every minute).

### Membership and loyalty, in plain terms

- A **member ticket** is just a ticket type marked *Members only*. Non-members can't
  buy it — the server checks this at purchase, not just the app.
- **Loyalty** is one point per person per event (however many tickets), and free
  tickets never earn a point. That is unchanged; the new switch simply lets an
  event opt out.

## Promoting an event

- **Highlight**: *FC Highlights* (also lifts the event into its own section at the
  top of the app's Events tab), *Staff pick*, or *Special offer*.
- **Perks**: up to four short labels, e.g. *Free drink with your ticket*, *Signed
  copies available*. Suggestions are one tap.
- **Selling fast** appears automatically once 75% of seats are sold (app + Eventbrite)
  and disappears when the event sells out. Nothing to switch on or off.

## Changing an event after it's live

Anything can be edited. The editor protects the things that affect buyers:

| You change… | What happens |
|---|---|
| Typos, description, pictures, speakers, links | Live straight away |
| Date, time or venue | After saving it asks whether to **notify ticket holders** |
| Capacity | Can't go below tickets sold; admin only when live |
| Price or quantity | Only affects future sales; admin only when live |
| A ticket type with sales | Can be taken off sale, not removed |
| **Postpone** | Marked Postponed, can't be booked; offers to notify ticket holders |
| **Cancel** (admin) | Marked Cancelled; optionally refunds every paid order through Stripe (which also reverses loyalty points); offers to notify ticket holders |
| **Duplicate** | New draft, one week later, no sales carried over — for recurring formats |

Every change to an event or its ticket types is recorded automatically (who, when,
what changed) in the audit log; admins can read it under **⋮ → Change history**.

## Notifications about events

Inside an event, **Notifications** lets staff write a message and choose who gets it:
everyone who has notifications on, members only, or that event's ticket holders. **Check
who'll get it** shows the audience size first; **Send** always asks to confirm because a
sent notification can't be recalled. There are daily limits so it can't be spammed by accident.

**Notifications** in the console (and **You → Send a notification** in the app) is for
general announcements that aren't about one event, plus a list of everything sent recently.

Setup is in [PUSH_SETUP.md](PUSH_SETUP.md).

## Known limits

- Descriptions use simple formatting marks (`**bold**`, `*italic*`, `- ` lists); the
  **Preview** button shows the result.
- The "Watch live" button appears on the event page from 15 minutes before an online event
  starts. For a *paid* stream, leave the link empty and send it to ticket holders yourself.
- Scheduled *notifications* aren't built yet (only scheduled *publishing*).
- Editing an event here does not change it on Eventbrite; the sync only pulls sold counts.
- The brand fonts (Source Serif 4 and Inter, SIL Open Font License) are bundled in `app/assets/fonts` and `admin/assets/fonts`;
  the licence texts sit beside them.
