# Noellyne Bet — UI/UX Design Language

> Locked design brief. Every screen refactor must follow this file.
> Visual proof: `preview/index.html` (live preview) · Flutter tokens: `user_app/lib/app_theme.dart`.

## Aesthetic
**Warm Editorial Glassmorphism** — soft alabaster canvas, diffused coral/terracotta ambient mesh glow, frosted translucent cards, matte obsidian primary actions. Restraint, surface depth, aggressive contrast control. Never neon green, never heavy borders, never cluttered grids.

## Color Tokens

| Token | Light | Dark twin | Role |
|---|---|---|---|
| Background Base | `#FAF7F5` Warm Alabaster | `#141212` | Canvas (never harsh white) |
| Ambient Mesh Orbs | `#F4A28C` 45% → `#E88267` 30%, blur 60–90px | `#D96B52` 18% | Radial glow behind mid-screen |
| Glass Card | `rgba(255,255,255,0.74)` + `1px rgba(255,255,255,0.65)` | `rgba(255,255,255,0.07)` | Primary cards; shadow `0 12px 32px rgba(29,25,24,0.05)` |
| Nested Inner Row | `#FFFFFF` 95%, radius 16px | `#241E1C` | White stat rows, chips, active inputs (Z-depth) |
| Primary CTA & Ink | `#1D1918`, text `#FFFFFF` | `#E88267`, text `#1D1918` | Buttons, active chips, headlines |
| Secondary Text | `#736A66` | `#A89C96` | Timestamps, subtitles, inactive icons |
| Live / Highlight Tint | `#FCE5DC` bg, `#C85A3F` text | — | LIVE pills, kickoff badges |
| Video Player | `#141212` Obsidian | `#141212` | Player container — pitch pops, zero glare |

## Geometry (strict hierarchy)
- Outer cards: **24–28px** radius.
- Inner rows/items: **16px** radius.
- **Every** interactive control — buttons, filter chips, status badges, bottom nav — **full pill (9999px)**.
- Navigation: floating frosted bottom-nav pill (side margins, never edge-stuck) + one **detached circular glowing action button** on the right for Noellyne AI / Daily Picks.

## Typography
- Geometric sans: **Plus Jakarta Sans** (fallback Inter / SF Pro).
- Headline tracking `-0.02em`, generous vertical rhythm.
- **`font-variant-numeric: tabular-nums`** on ALL odds, scores, match clocks, timers — digits must never jitter.

## Performance & Motion (non-negotiable)
- **GPU-safe only:** transforms (`translate3d`, `scale`, `opacity`). 
- **No real backdrop blur inside scrolling list items** — it chokes mid-range Android. Fake glass on cards with semi-transparent gradients + `1px` crisp borders.
- Real blur **only** on: sticky header, floating bottom dock, modal/bottom sheets.
- Micro-interactions: `140ms` scale-down to `0.96`, `cubic-bezier(0.22, 1, 0.36, 1)`.
- Reveals: `expo-out (0.16, 1, 0.3, 1)`, `260–380ms`.

## Screen Map (Streaming + n8n Picks)

### 1. Home Lobby
- Top bar: league selector pill left (`All Leagues ▾`) + profile/VIP badge right.
- Hero glass card: **Featured Live Match** (or "Today's Banker Slip") — teams, AI confidence, combined odds, full-width obsidian pill CTA `Watch Live & View Slip`.
- Quick-filter pills (horizontal): `Live Now`, `EPL`, `UCL`, `Safe 2+`, `Over 2.5`.
- Stream cards: crest left, coral `LIVE 64'` pill, match title, `Stream` pill button.
- Detached bottom-right glowing circle: **Noellyne AI / Daily Slips**.

### 2. Daily Bets Feed (n8n)
- Quick-filter pills: `All Picks`, `Sure 2+`, `BTTS`, `High Odds`.
- Structured glass card per pick:
  - Header: match + short n8n AI reasoning.
  - Nested white rows: **Market & Pick** (e.g. `Arsenal Win & Over 1.5`) + **Odds / Confidence** (e.g. `1.85 • 84%`) with dark circular chevron.
  - Matte-black bottom CTA: `Watch Match Live` → deep-links via `stream_id`.

### 3. Match Theatre & Live Sheet
- Top: seamless Obsidian `#141212` video player.
- Bottom: draggable translucent sheet — n8n pick for this game, live stats, twin pills `Copy Bet Code` / `Share Slip`.

## n8n Integration (planned)
- n8n POSTs structured JSON (`match`, `league`, `pick`, `odds`, `confidence`, `reasoning`, `stream_id`, `kickoff_time`) to Supabase table `daily_picks` (migration: `supabase/migrations/20261120000000_daily_picks.sql`).
- Viewer reads via existing public API pattern; `Watch Match Live` deep-links with `?match=<id>` (already supported).
