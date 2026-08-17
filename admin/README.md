# Frontline Club admin console

Flutter Web, deployed free (Cloudflare Pages / Netlify) — see root [README](../README.md).

## First-time setup

```bash
flutter create --org com.frontlineclub --project-name frontline_club_admin --platforms web .
flutter pub get
```

## Running

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Sign in with the seeded demo admin account (`supabase/seed.sql`):
`demo.admin@frontlineclub.dev` / `FrontlineDemo2026!`.

Every section beyond the shell (`lib/shell/admin_shell.dart`) is a
placeholder — see `lib/sections/admin_sections.dart` for what each one
needs to become, in the order the root README's delivery plan builds them.
