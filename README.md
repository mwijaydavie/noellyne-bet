# Noellyne Bet

Live football streaming + AI daily picks. Flutter viewer and admin apps, Supabase backend, Cloudflare/Vercel delivery.

Built on the MIT-licensed [NCA football-stream-app](https://github.com/nyeinchanaung75299-eng/football-stream-app) engine, re-skinned and extended.

## Design

Warm editorial glassmorphism — alabaster canvas, terracotta ambient glow, frosted glass cards, matte obsidian actions. Full spec: [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md).

- Live interactive preview: `node preview/server.mjs` → open the printed URL (Lobby · Daily Picks · Match Theatre, light + dark).
- Flutter tokens: `user_app/lib/app_theme.dart`
- Shared UI kit: `user_app/lib/design/noellyne_ui.dart`
- Font: Plus Jakarta Sans (bundled, OFL)

## Apps

| Path | What it is |
|---|---|
| `user_app/` | Viewer app (`football_viewer` 10.0.0) — Live, Daily Picks, Channels, Match Theatre |
| `admin_app/` | Admin dashboard (`football_admin` 3.0.0) — matches, streams, fixtures, channels, health |
| `supabase/` | Schema, migrations, Edge Functions |
| `cloudflare/`, `vercel/` | Protected gateway + network fallbacks |
| `preview/` | Static design preview (no Flutter SDK needed) |
| `docs/` | Integration docs — start with [`docs/N8N_DAILY_PICKS.md`](docs/N8N_DAILY_PICKS.md) |

## Daily Picks (n8n)

The Daily Bets feed renders structured JSON from the n8n pipeline as filterable cards with odds, confidence, AI reasoning and a one-tap deep-link into the live player. Contract and wiring: [`docs/N8N_DAILY_PICKS.md`](docs/N8N_DAILY_PICKS.md).

## Run

```bash
cd user_app && flutter pub get && flutter run          # viewer
cd admin_app && flutter pub get && flutter run         # admin
node preview/server.mjs                                # design preview
```

## Roadmap

See [`PLAN.md`](PLAN.md) — 7 phases from identity and viewer UX through performance, loyalty features, admin, and release.
