# Noellyne Bet — Standalone EC2 Python Data Scrapers

**Author:** David Erick Mwijage

Standalone Python collectors that run independently of n8n on your AWS EC2 (`t4g.small`) or any future VPS, feeding fixtures, live scores, and odds directly into Supabase (`public.fixtures`). Zero third-party Python pip dependencies required (pure Python 3 stdlib).

## Quick Test (Dry Run)
```bash
python3 sync_fixtures.py --dry-run
```

## Run Every 15 Minutes on EC2 (Cron)
1. Copy `sync_fixtures.py` to `/opt/noellyne/sync_fixtures.py`.
2. Store your Supabase secret key in `/opt/noellyne/.env` (`chmod 600`):
   ```env
   NOELLYNE_SUPABASE_URL=https://tahigoqhuyxedhmeqhnp.supabase.co
   NOELLYNE_SUPABASE_KEY=sb_secret_...
   ```
3. Add a cron entry (`crontab -e`):
   ```cron
   */15 * * * * set -a; . /opt/noellyne/.env; set +a; /usr/bin/python3 /opt/noellyne/sync_fixtures.py >> /var/log/noellyne-fixtures.log 2>&1
   ```

> Note: An identical 15-minute sync workflow (`Noellyne Fixtures & Live Scores Sync (15m)`) is ALSO active on n8n right now for immediate zero-ops redundancy. You can extend `sync_fixtures.py` with additional bookmaker odds sources (e.g. BetPawa TZ, The Odds API, SofaScore) at any time without touching the Flutter APK!
