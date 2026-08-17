# Frontline Club Events (WordPress plugin)

Read-only. Renders events from the Supabase backend into the existing
theme — see briefing §12.2. The website is never a second source of truth
for events; it only renders from the app's admin console.

## Install

1. Copy `frontline-events.php` into `wp-content/plugins/frontline-events/`
   (or zip it and upload via Plugins → Add New → Upload).
2. Add to `wp-config.php` (not to this file — keep secrets out of version
   control):
   ```php
   define('FLC_SUPABASE_URL', 'https://<project-ref>.supabase.co');
   define('FLC_SUPABASE_ANON_KEY', '<anon-key>');
   ```
   The anon key is safe here — RLS restricts it to `status = 'published'`
   events only (`supabase/migrations/20260817000009_rls_policies.sql`).
3. Activate the plugin. This flushes rewrite rules automatically so
   `/events/<slug>/` starts resolving immediately.
4. Add `[frontline_events]` to any page/post, or use the "Frontline Club
   Events" block in the editor. Optional `limit` attribute (default 6).

## What it does

- Fetches published events directly from PostgREST (`/rest/v1/events`),
  cached in a WordPress transient for 5 minutes.
- Registers `/events/<slug>/` as a virtual page rendering that event, with
  JSON-LD `Event` structured data for SEO / Google event listings.
- Never writes back to Supabase. Never touches WooCommerce.

## Fallback if custom plugins are refused

If the club's web maintainer won't allow a custom plugin
([CONFIRM] — see `docs/OPEN_QUESTIONS.md`), the fallback is a JS embed
pulling from the same PostgREST endpoint client-side, dropped into a
generic HTML/embed block. Worse for SEO (no server-rendered JSON-LD), but
needs no plugin install.
