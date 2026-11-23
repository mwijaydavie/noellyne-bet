#!/usr/bin/env python3
"""
Noellyne Bet — Multi-Source Match Fixtures, Live Scores & Odds Collector
Author: David Erick Mwijage

Designed to run on EC2 (cron / systemd timer every 15 minutes) OR on-demand,
writing normalized Football & NBA fixtures directly into Noellyne's own
Supabase (`public.fixtures`) so the app NEVER relies on a single third-party
stream operator for today's match schedule, live scores, or odds.

Environment variables (server-side only — never hardcode secrets):
  NOELLYNE_SUPABASE_URL  (default: https://tahigoqhuyxedhmeqhnp.supabase.co)
  NOELLYNE_SUPABASE_KEY  (required: Supabase service_role / sb_secret_ key)
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any

EAT = timezone(timedelta(hours=3))
SUPABASE_URL = os.environ.get(
    "NOELLYNE_SUPABASE_URL", "https://tahigoqhuyxedhmeqhnp.supabase.co"
).rstrip("/")
SUPABASE_KEY = os.environ.get("NOELLYNE_SUPABASE_KEY", "").strip()

LEAGUES: list[tuple[str, str, str]] = [
    ("soccer", "eng.1", "Premier League"),
    ("soccer", "esp.1", "La Liga"),
    ("soccer", "ita.1", "Serie A"),
    ("soccer", "ger.1", "Bundesliga"),
    ("soccer", "fra.1", "Ligue 1"),
    ("soccer", "uefa.champions", "UEFA Champions League"),
    ("soccer", "uefa.europa", "UEFA Europa League"),
    ("soccer", "ned.1", "Eredivisie"),
    ("soccer", "por.1", "Primeira Liga"),
    ("soccer", "tur.1", "Turkish Super Lig"),
    ("soccer", "bra.1", "Brasileirao"),
    ("soccer", "usa.1", "MLS"),
    ("basketball", "nba", "NBA"),
]


def http_json(
    url: str,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    payload: Any = None,
    timeout: int = 15,
) -> Any:
    hdrs = {"User-Agent": "NoellyneFixturesCollector/1.0"}
    if headers:
        hdrs.update(headers)
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8", errors="replace").strip()
        return json.loads(raw) if raw else {}


def american_to_decimal(val: Any) -> float | None:
    try:
        n = float(val)
    except (TypeError, ValueError):
        return None
    if n == 0:
        return None
    if n > 0:
        return round(1.0 + n / 100.0, 2)
    return round(1.0 + 100.0 / abs(n), 2)


def fetch_espn_fixtures(date_keys: list[str]) -> list[dict[str, Any]]:
    rows_by_id: dict[str, dict[str, Any]] = {}
    now_iso = datetime.now(timezone.utc).isoformat()

    for date_key in date_keys:
        for sport_slug, league_slug, league_name in LEAGUES:
            url = (
                f"https://site.api.espn.com/apis/site/v2/sports/"
                f"{sport_slug}/{league_slug}/scoreboard?dates={date_key}"
            )
            try:
                data = http_json(url, timeout=12)
            except Exception:
                try:
                    data = http_json(url, timeout=15)
                except Exception as exc:
                    print(f"[warn] ESPN {league_slug} {date_key}: {exc}", file=sys.stderr)
                    continue

            sport = "basketball" if sport_slug == "basketball" else "football"
            for ev in data.get("events") or []:
                ev_id = str(ev.get("id") or "").strip()
                comps = ev.get("competitions") or []
                if not ev_id or not comps:
                    continue
                comp = comps[0]
                competitors = comp.get("competitors") or []
                home = next((c for c in competitors if c.get("homeAway") == "home"), None)
                away = next((c for c in competitors if c.get("homeAway") == "away"), None)
                if not home or not away:
                    continue

                h_team = home.get("team") or {}
                a_team = away.get("team") or {}
                home_name = str(h_team.get("displayName") or h_team.get("name") or "").strip()
                away_name = str(a_team.get("displayName") or a_team.get("name") or "").strip()
                if not home_name or not away_name:
                    continue

                kickoff_str = str(ev.get("date") or now_iso)
                stale_cutoff = datetime.now(timezone.utc) - timedelta(hours=4)
                try:
                    kickoff_dt = datetime.fromisoformat(kickoff_str.replace("Z", "+00:00"))
                    is_too_old = kickoff_dt < stale_cutoff
                except ValueError:
                    is_too_old = False

                st_type = (ev.get("status") or {}).get("type") or {}
                state = str(st_type.get("state") or "pre").lower()
                completed = bool(st_type.get("completed")) or state == "post" or is_too_old
                is_live = (not completed) and state == "in"
                status = "finished" if completed else ("live" if is_live else "scheduled")
                clock = str(st_type.get("shortDetail") or st_type.get("detail") or "").strip()

                def parse_score(v: Any) -> int | None:
                    if state == "pre":
                        return None
                    try:
                        return int(str(v).strip())
                    except (TypeError, ValueError):
                        return None

                odds_list = comp.get("odds") or []
                o0 = next((x for x in odds_list if isinstance(x, dict)), None)
                odds_home = None
                odds_draw = None
                odds_away = None
                odds_summary = ""
                if o0:
                    ml_home = (o0.get("homeTeamOdds") or {}).get("moneyLine")
                    ml_away = (o0.get("awayTeamOdds") or {}).get("moneyLine")
                    ml_draw = (o0.get("drawOdds") or {}).get("moneyLine")
                    odds_home = american_to_decimal(ml_home)
                    odds_away = american_to_decimal(ml_away)
                    odds_draw = american_to_decimal(ml_draw)
                    details = str(o0.get("details") or "").strip()
                    ou = o0.get("overUnder")
                    parts = []
                    if odds_home and odds_away:
                        if odds_draw:
                            parts.append(f"1: {odds_home:.2f} · X: {odds_draw:.2f} · 2: {odds_away:.2f}")
                        else:
                            parts.append(f"1: {odds_home:.2f} · 2: {odds_away:.2f}")
                    elif details:
                        parts.append(details)
                    if ou:
                        parts.append(f"O/U {ou}")
                    odds_summary = " | ".join(parts)

                row_id = f"espn-{sport}-{ev_id}"
                rows_by_id[row_id] = {
                    "id": row_id,
                    "event_id": ev_id,
                    "sport": sport,
                    "league": league_name,
                    "home_team": home_name,
                    "away_team": away_name,
                    "home_logo_url": str(h_team.get("logo") or "").strip(),
                    "away_logo_url": str(a_team.get("logo") or "").strip(),
                    "kickoff_at": str(ev.get("date") or now_iso),
                    "status": status,
                    "is_live": is_live,
                    "home_score": parse_score(home.get("score")),
                    "away_score": parse_score(away.get("score")),
                    "clock": clock,
                    "odds_home": odds_home,
                    "odds_draw": odds_draw,
                    "odds_away": odds_away,
                    "odds_summary": odds_summary,
                    "source": "espn-multi",
                    "is_active": not completed,
                    "updated_at": now_iso,
                }

    return list(rows_by_id.values())


def upsert_supabase(rows: list[dict[str, Any]]) -> None:
    if not rows:
        print("No fixtures to upsert.")
        return
    if not SUPABASE_KEY:
        raise SystemExit("NOELLYNE_SUPABASE_KEY env var is required to write to Supabase.")

    url = f"{SUPABASE_URL}/rest/v1/fixtures?on_conflict=id"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    # Chunk in batches of 50 to keep payloads lean
    for i in range(0, len(rows), 50):
        batch = rows[i : i + 50]
        http_json(url, method="POST", headers=headers, payload=batch, timeout=20)
    print(f"Upserted {len(rows)} fixtures into {SUPABASE_URL}/rest/v1/fixtures")

    # Deactivate any stale fixtures older than 4 hours so zombie LIVE rows never survive
    stale_cutoff = (datetime.now(timezone.utc) - timedelta(hours=4)).isoformat()
    import urllib.parse
    patch_url = (
        f"{SUPABASE_URL}/rest/v1/fixtures"
        f"?is_active=eq.true&kickoff_at=lt.{urllib.parse.quote(stale_cutoff, safe='')}"
    )
    http_json(
        patch_url,
        method="PATCH",
        headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Prefer": "return=minimal",
        },
        payload={
            "is_live": False,
            "is_active": False,
            "status": "finished",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
        timeout=15,
    )


def main() -> None:
    now_eat = datetime.now(EAT)
    yesterday_key = (now_eat - timedelta(days=1)).strftime("%Y%m%d")
    today_key = now_eat.strftime("%Y%m%d")
    tomorrow_key = (now_eat + timedelta(days=1)).strftime("%Y%m%d")
    rows = fetch_espn_fixtures([yesterday_key, today_key, tomorrow_key])
    active = sum(1 for r in rows if r["is_active"])
    live = sum(1 for r in rows if r["is_live"])
    print(f"Collected {len(rows)} fixtures ({active} active, {live} live) for {yesterday_key}/{today_key}/{tomorrow_key}")
    if "--dry-run" in sys.argv:
        for r in rows[:10]:
            print(f"  [{r['sport']}] {r['league']} | {r['home_team']} vs {r['away_team']} | {r['kickoff_at']} | {r['odds_summary']}")
        return
    upsert_supabase(rows)


if __name__ == "__main__":
    main()
