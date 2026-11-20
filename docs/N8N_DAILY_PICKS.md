# n8n → Noellyne Bet: Daily Picks Pipeline

How your n8n betting workflow feeds the app's **Daily Picks** screen instead of (or alongside) Telegram.

## 1. Why not Telegram-only?

Telegram forces linear markdown text: no filters, no one-tap "watch", no odds/confidence structure. Noellyne Bet renders the **same n8n output** as interactive cards: filter pills (`All Picks`, `Sure 2+`, `BTTS`, `High Odds`), nested stat rows (market, odds, confidence), and a CTA that deep-links into the live player.

## 2. The contract

n8n sends **one JSON object per pick** (or an array — loop and POST each).

```json
{
  "match": "Arsenal vs Chelsea",
  "league": "Premier League",
  "pick": "Arsenal Win & Over 1.5",
  "odds": 1.85,
  "confidence": 84,
  "reasoning": "Arsenal scored 2+ in 7 of 9 home games; Chelsea concede 1.6 away.",
  "stream_id": "8f3c1e2a-...",
  "kickoff_time": "2026-11-20T17:30:00Z",
  "tags": ["sure2+", "over2.5"],
  "slip_code": "NLY-8K2F",
  "status": "published"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `match` | text | ✅ | `"Home vs Away"` — used as the card title |
| `league` | text | — | defaults to `Football` |
| `pick` | text | ✅ | Market + selection, e.g. `"Both Teams To Score"` |
| `odds` | numeric | ✅ | Decimal odds |
| `confidence` | int 0–100 | ✅ | ≥80 renders the ⚡ "Sure" chip |
| `reasoning` | text | — | Keep it **1–2 sentences** (card shows 2 lines) |
| `stream_id` | text | — | `matches.id`; enables **Watch Match Live** |
| `kickoff_time` | ISO-8601 | — | Drives ordering + "today" grouping |
| `tags` | string[] | — | `sure2+`, `btts`, `over2.5`, `high-odds` power the filters |
| `slip_code` | text | — | Shown/copyable in Match Theatre |
| `sport` | text | — | `football` \| `basketball` (drives the card icon) |
| `tier` | text | — | Hermes tier, e.g. `🟢 STRONG` |
| `units` | numeric | — | Recommended stake (1u = 1% bankroll) |
| `edge_pct` | numeric | — | Model edge over implied probability |
| `injury_note` | text | — | NBA Injury Guard note (who is OUT) |
| `status` | text | — | `draft` \| `published` \| `settled` \| `void` |

**Ordering:** published picks are ordered by `kickoff_time` ascending.
**Dedupe:** a unique index on `(match, pick, kickoff_time::date)` means re-running the n8n cron will not duplicate cards.

## 3. Wiring n8n (two options)

### Option A — Direct Supabase write (fastest)

HTTP Request node:

- **Method:** `POST`
- **URL:** `https://<PROJECT>.supabase.co/rest/v1/daily_picks`
- **Headers:**
  - `apikey: <SERVICE_ROLE_KEY>`
  - `Authorization: Bearer <SERVICE_ROLE_KEY>`
  - `Content-Type: application/json`
  - `Prefer: resolution=merge-duplicates,return=minimal`
- **Body:** the JSON above (use n8n expressions to map your AI output).

> Keep the service-role key in n8n credentials only — never in the app.

### Option B — Edge Function with a shared secret (recommended for production)

1. Deploy `supabase/functions/ingest-daily-picks` (secret header `x-noellyne-secret`).
2. n8n POSTs the array to it; the function validates, normalises tags and upserts.

This keeps the service-role key entirely out of n8n.

## 3b. From YOUR Hermes v5.0 workflow (drop-in)

Your existing Telegram workflow is the brain — **don't rewrite it**. Keep the
`Quant Model v3.1 → Format Message → Send Telegram` path exactly as it is and
add one branch that mirrors the same picks into the app.

**File:** [`n8n/noellyne-daily-picks-branch.json`](../n8n/noellyne-daily-picks-branch.json)

### Wiring (4 steps)

1. n8n → **Workflows → Import from File** → pick the JSON above.
2. In your Hermes workflow, drag a connection from **`Quant Model v3.1`** to the
   imported **`Map Hermes → Noellyne`** node (the Telegram chain keeps running —
   one node output can fan out to many branches).
3. In n8n, add an environment variable
   `SUPABASE_SERVICE_ROLE_KEY=<your service role key>`
   (Settings → Variables, or your `.env` / Docker env).
4. Run the schedule once manually — the app's **Daily Picks** tab fills up.

### What the mapping does

| Hermes field (`footballPicks` / `basketballPicks`) | `daily_picks` column |
|---|---|
| `match` ("Arsenal vs Chelsea") | `match` |
| `league` ("⚽ EPL" → emoji stripped) | `league` |
| `market` ("DC 1X", "OVER 2.5 Pts") | `pick` |
| `odds` | `odds` |
| `probPct` (84.3 → 84) | `confidence` |
| `explain` + `injuryNote` | `reasoning` |
| `kickoffISO` | `kickoff_time` |
| `tier` ("🟢 STRONG") | `tier` |
| `units` ("2.50u") | `units` |
| `edgePct` | `edge_pct` |
| `injuryNote` | `injury_note` |
| `sport` | `sport` (football / basketball → ⚽ / 🏀 icon) |
| `match` + `market` (hashed) | `slip_code` (`NLY-XXXXX`, copyable) |
| derived from the pick | `tags` (`sure2+`, `strong`, `over2.5`, `under2.5`, `btts`, `high-odds`) |

`tags` are what power the in-app filter pills, so your `ANCHOR` picks land in
**Sure 2+** automatically and `OVER/UNDER` markets land in the right chip.

### Why this beats Telegram-only

| Telegram post | Noellyne Bet |
|---|---|
| Linear text, scroll to find a pick | Filter pills: Sure 2+ / BTTS / High Odds |
| Odds + confidence buried in prose | Nested stat row, tabular numerals |
| "Watch it on…" → manual search | **Watch Live** deep-links by `stream_id` |
| Re-sharing screenshots | One-tap **Copy slip code** (`NLY-…`) |
| History scroll | Persistent feed ordered by kickoff |

### Idempotency

The unique index on `(match, pick, kickoff_time)` plus
`Prefer: resolution=merge-duplicates` means the 09:00 / 14:00 / 19:00 runs
**update** the same row instead of duplicating the card.

### Linking a stream (optional but powerful)

If you also store the fixture in `matches`, set `stream_id` to that row's id in
the mapping node (e.g. look it up by team names) and the app's **Watch Live**
button jumps straight into the player.

## 4. n8n flow sketch

```
Cron (07:00 EAT)
  └─ Fixtures API (or your existing source)
      └─ AI node → JSON per pick
          └─ Code node: normalise
              · tags from market type
              · clamp confidence 0–100
              · attach stream_id via Supabase match lookup
          └─ HTTP Request → daily_picks
              └─ IF status=published → Telegram (optional mirror)
```

## 5. In-app behaviour

| Situation | Behaviour |
|---|---|
| Supabase OK, picks exist | Live feed, ordered by kickoff |
| Supabase unreachable / empty | Demo picks (disable with `--dart-define=DAILY_PICKS_DEMO=0`) |
| Pick has no `stream_id` | "Watch Live" shows a soft toast, card still readable |
| Filter empty | Friendly empty state → points to "All Picks" |
| Every card | `Copy` copies `slip_code` to clipboard |

## 6. Where it lives

| Piece | Path |
|---|---|
| Screen | `user_app/lib/screens/daily_picks_page.dart` |
| Model + filters | `user_app/lib/models/daily_pick.dart` |
| Repository | `user_app/lib/services/daily_picks_repository.dart` |
| Table + RLS | `supabase/migrations/20261120000000_daily_picks.sql` |
| Design spec | `DESIGN_SYSTEM.md` |

## 7. Next steps

- [ ] Admin app: "Daily Picks" editor (approve/edit before publishing, see `result` history).
- [ ] Settlement job: after matches, mark `result` won/lost → win-rate stats on the feed header.
- [ ] "Today's Banker" = highest-confidence slip, auto-featured in the home hero.
