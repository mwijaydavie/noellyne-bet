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
