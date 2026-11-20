# Noellyne Bet — Football Stream App: Perfection Plan

> **Source repo:** [nyeinchanaung75299-eng/football-stream-app](https://github.com/nyeinchanaung75299-eng/football-stream-app)
> **This repo:** `noellyne-bet` — source code copied in, customization workspace
> **Status:** Sprint 1 in progress — decisions locked (below), design system applied, design preview live.

## Decisions locked (2026-11-20)

| Question | Decision |
|---|---|
| Brand | **Noellyne Bet** — warm terracotta glass aesthetic (see §1.1). No more neon green. |
| Focus | **Viewer app first**, Admin second. |
| Platforms | **Android + Web** (iOS later). |
| Language | **English only** for now (Swahili later if wanted). |
| Monetization | **Undecided** — perfect the product first. |
| Code home | Copied into this repo ✅ (original kept as reference). |
| Backend | Reuse existing Supabase/Cloudflare setup for now; fresh project when ready to launch. |

### 1.1 Design direction (locked)

Restraint, surface depth, aggressive contrast control. Four layers, not flat color:

| Layer / Token | Value | Role |
|---|---|---|
| Canvas Base | `#FAF7F5` Warm Alabaster | Screen background (replaces harsh white) |
| Ambient Mesh Glow | `#F4A28C` → `#E88267` Terracotta/Coral | Blurred orbs (60–90px) behind content; glass picks up warmth |
| Glass Surface | `rgba(255,255,255,0.72)` + `1px rgba(255,255,255,0.65)` | Primary cards |
| Elevated Inner | `#FFFFFF` @ 0.95 | Nested rows, chips, active inputs (Z-depth) |
| Obsidian Ink | `#1D1918` Warm Charcoal | Primary CTAs, active chips, headlines |
| Muted Metadata | `#736A66` Warm Slate | Timestamps, subtitles, inactive icons |
| Geometry | Outer `24–28px` radii, nested rows smaller | Strict hierarchy |

Dark mode mirrors it: deep warm charcoal canvas `#141110`, terracotta primary CTAs, warm-gray metadata `#A89C96`.

Applied in `user_app/lib/app_theme.dart` (`NoellyneColors`, `AppTheme`, `NoellyneBackground` widget). Live visual preview: `preview/` (run `node preview/server.mjs`, open the preview URL).

---

## 1. What the app is today (audit summary)

A mature, production Flutter suite — not a starter toy. 982 commits, 73 branches, CI passing.

| Part | What it is | Version |
|---|---|---|
| **Viewer app** (`user_app/`) | User-facing football streaming app. 7 tabs: Live, Live 2, Soco, YYZB, ColaTV, Fawa, Channels. HLS/DASH playback via media_kit, web player via Shaka, iOS player page. | 9.8.12 |
| **Admin app** (`admin_app/`) | Dashboard to upload matches, manage stream links, import fixtures (Soco), channels, EPG, highlights, system health, Telegram bots. 30+ screens. | 2.5.23 |
| **Backend** (`supabase/`) | Postgres + RLS + 40+ migrations + Edge Functions (`soco-links`, `source-match-list`, `public-feed-lines`, `viewer-network-api`, Telegram bots…). | — |
| **Delivery** (`cloudflare/`, `vercel/`) | Cloudflare Workers (public API, viewer proxy, network backup) + Vercel fallback for restricted networks. | — |

**Current look:** Material 3, green accent (`#22D67B`), light + dark mode, `PremiumMatchCard` cards, custom bottom nav with 7 tabs.

**Strengths to keep:** protected stream gateway (raw URLs never exposed), multi-source fallback, realtime updates, channel logos/EPG, update service, analytics (PostHog), extensive tests.

**Weaknesses / opportunities:** huge files (`home_page.dart` 1,699 lines, `soco_import_page.dart` 2,455 lines), 7 tabs is crowded, no favorites/history, no Swahili, no monetization layer, no onboarding, generic branding ("NCA"), no web landing/marketing page.

---

## 2. Vision

Turn this solid engine into a **beautiful, fast, loved football streaming product** under the **Noellyne** brand — the kind of app fans open every match day and never delete.

**North-star goals:**
1. **Instant delight** — first screen looks premium in <1s, WATCH tap → video in <3s.
2. **Loyalty** — favorites, history, reminders, personalized home.
3. **Trust** — stable playback, honest status, works on weak networks.
4. **Growth** — shareable links, SEO web version, monetization-ready.
5. **Craft** — consistent design system, buttery animations, zero jank.

---

## 3. The plan — 7 phases

### Phase 0 — Setup & fork strategy (foundation)
- [ ] Decide: fork code into this repo (copy `user_app/`, `admin_app/`, `supabase/`, etc.) vs. work on a fork of the original. **Recommendation:** copy into `noellyne-bet` so we own it fully, keep original as reference.
- [ ] Remove/rename NCA branding references, Supabase keys → env/dart-define, fresh project setup docs.
- [ ] Get both apps building locally (Flutter) + web preview running.
- [ ] Set up CI (analyze + test + APK/web build) on this repo.

### Phase 1 — Noellyne identity & design system
- [ ] **Brand:** name, logo, icon, splash, color palette (keep green energy or go new?), typography (display + body), dark-first design.
- [ ] **Design tokens:** colors, spacing, radius, shadows, motion curves — one `app_theme.dart` both apps share.
- [ ] **Components:** buttons, chips, cards, nav, dialogs, snackbars, empty/loading/error states — pixel-perfect, consistent.
- [ ] **App icon + launcher + web favicon** generated from new logo.

### Phase 2 — Viewer UX perfection (the money phase)
- [ ] **Home redesign:** hero featured live match, smart sections (Live now / Upcoming / Leagues), skeleton loading, pull-to-refresh, live score badges.
- [ ] **Match cards v2:** team crests, league chip, kickoff countdown, LIVE pulse, stream-count, quality hints, smooth entrance animations.
- [ ] **Navigation:** simplify 7 tabs → 4–5 (e.g. Live, Matches, Channels, More) with a "Sources" sheet; bottom nav + top app bar polish.
- [ ] **Player experience:** faster startup, quality selector, server rail, PiP, fullscreen, resume, auto-fallback with friendly messaging ("Server busy — trying next…").
- [ ] **Search & filters:** search teams/leagues, filter by league/time, sort options.
- [ ] **Onboarding:** 3-screen first-run (what it is, how to watch, allow notifications) + empty states that teach.
- [ ] **Micro-interactions:** haptics, shared-element transitions, shimmer, success/error toasts.

### Phase 3 — Performance & reliability
- [ ] Split giant files (`home_page.dart`, `soco_import_page.dart`) into widgets/controllers.
- [ ] Image/logo caching, list virtualization, debounce, in-flight coalescing (extend existing patterns).
- [ ] Startup budget: first frame <1s, feed <1.5s; add perf marks + PostHog tracking.
- [ ] Offline/weak-network mode: cached matches, retry with backoff, diagnostics page upgrade.
- [ ] Crash/ANR monitoring, error boundaries, graceful Supabase-outage mode.

### Phase 4 — Loyalty & new features
- [ ] **Favorites:** favorite teams/leagues, personalized "My Teams" row.
- [ ] **History & continue watching.**
- [ ] **Match reminders:** notify 15 min before kickoff (local + push-ready).
- [ ] **Live scores:** real-time score/minute on cards (extend existing score sync).
- [ ] **Highlights tab** (data already exists in Supabase).
- [ ] **Language:** English + **Swahili (Kiswahili)** toggle — big win for TZ audience.
- [ ] **Share:** share match link (`?match=` deep link already supported — make it beautiful).
- [ ] **Settings:** theme (light/dark/auto), data-saver, quality preference, about.

### Phase 5 — Admin perfection
- [ ] Dashboard redesign: KPIs (live now, streams health, users), quick actions.
- [ ] Stream health board: one-glance green/red per line, bulk retry/disable.
- [ ] Faster match creation (templates, duplicate, bulk import).
- [ ] Channel/EPG management polish, audit log.
- [ ] Mobile-responsive admin web (it already runs as web).

### Phase 6 — Growth & monetization (optional, decide later)
- [ ] Web landing page (SEO: "Watch live football — Noellyne") + PWA install.
- [ ] Ads (AdMob) with premium remove-ads tier.
- [ ] Premium/VIP: priority servers, 4K, no ads — via RevenueCat or manual entitlements.
- [ ] Referral + Telegram/WhatsApp channel integration (bots already exist).
- [ ] Analytics dashboards: retention, playback success, funnel.

### Phase 7 — Release & polish
- [ ] Versioning, changelog, in-app update flow test.
- [ ] Store assets (screenshots, feature graphic, descriptions EN/SW).
- [ ] Beta rollout plan, feedback loop, crash-free target ≥99.5%.

---

## 4. Tech decisions (proposed)

| Area | Decision |
|---|---|
| Framework | Keep Flutter (both apps) — no rewrite. |
| State | Keep existing controllers; extract where files are huge. |
| Theming | Single shared design-token file, dark-first. |
| Backend | Keep Supabase + Cloudflare/Vercel delivery; new project, same schema. |
| i18n | `flutter_localizations` + ARB files (EN/SW). |
| Testing | Keep `flutter test` gates; add widget/golden tests for new UI. |
| Release | GitHub Actions → APK + web deploy; signed updates as today. |

---

## 5. Suggested order of work (first 3 sprints)

1. **Sprint 1 — Foundation:** fork code in, rebrand to Noellyne, new theme + icon, apps building, web preview live.
2. **Sprint 2 — Viewer wow:** home redesign, cards v2, nav simplification, player polish, search.
3. **Sprint 3 — Loyalty:** favorites, history, reminders, Swahili, share, settings.

Each sprint ends with a working preview you can tap through on your phone.

---

## 6. Open questions — need your answers before we build

1. **Brand:** Should the app be called **Noellyne** (or "Noellyne Bet")? Any logo/colors you love? Or keep green?
2. **Focus:** Viewer app first, Admin too, or both together?
3. **Platforms:** Android only, or also Web + iOS from day one?
4. **Audience language:** English only, or English + Swahili?
5. **Monetization:** Free forever, ads, premium/VIP, betting-related features — or undecided?
6. **Code home:** Copy everything into this `noellyne-bet` repo (recommended), or keep working in the original repo?
7. **Backend:** Reuse the existing Supabase project, or create a fresh one for Noellyne?

---

## 7. Progress log

### Sprint 1 — Foundation & identity ✅ (in progress)

- [x] Source copied into this repo (`user_app/`, `admin_app/`, `supabase/`, `cloudflare/`, `vercel/`).
- [x] `DESIGN_SYSTEM.md` written — warm editorial glassmorphism, locked tokens, GPU + motion rules.
- [x] Flutter theme rebuilt (`user_app/lib/app_theme.dart`): `NoellyneColors`, `NoellyneMotion`, `NoellyneBackground`, dark twin (`#141212` + `#D96B52` glow), full-pill controls.
- [x] **Plus Jakarta Sans** bundled (5 weights, OFL) in both apps + `pubspec.yaml` wiring.
- [x] Shared UI kit `user_app/lib/design/noellyne_ui.dart`: `GlassCard` (fake glass, list-safe), `GlassBlur` (dock/sheets only), `PillButton`, `FilterPill`, `LivePill`, `TabularText`, `PressableScale` (140ms/.96), `RevealIn`, `FloatingDock` + detached AI button.
- [x] Rebrand: titles → "Noellyne Bet" / "Noellyne Bet Admin"; versions → Viewer 10.0.0, Admin 3.0.0.
- [x] **Daily Picks (n8n)** feature: model + repository + feed screen + `daily_picks` migration & RLS.
- [x] `docs/N8N_DAILY_PICKS.md` — JSON contract + n8n wiring (direct Supabase or Edge Function).
- [x] Interactive design preview `preview/` — Lobby, Daily Picks, Match Theatre; light/dark.

### Next (Sprint 2 — Lobby & player)

- [ ] Home lobby rebuild using the new kit (hero banker slip, filter rail, stream cards v2).
- [ ] Bottom nav → `FloatingDock` (Live / Picks / Channels / More) + AI button routing to Daily Picks.
- [ ] Match Theatre: obsidian player + draggable pick sheet (replace `ios_player_page` chrome).
- [ ] Wire `DailyPicksPage.onWatchMatch` to the existing playback route by `stream_id`.
- [ ] Admin: Daily Picks moderation screen; n8n `ingest-daily-picks` Edge Function.

### Deferred / decided against

- ~~Neon green palette~~ → replaced by terracotta glass.
- ~~7 flat tabs~~ → 4 dock destinations + AI button.

---

*Plan v2 — 2026-11-20. Sprint 1 code complete; awaiting design sign-off on the preview to start the lobby rebuild.*
