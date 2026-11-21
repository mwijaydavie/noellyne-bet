# Noellyne Bet — n8n Disaster Recovery & 5-Minute VPS Migration Guide

**Author:** David Erick Mwijage

All production n8n betting workflows are backed up here in sanitized, import-ready JSON format (**zero API keys, zero tokens, zero secrets**). Because the Flutter app reads its live AI Chat endpoint dynamically from Supabase `public.app_config`, you can migrate your entire n8n backend to a new VPS in **under 5 minutes with ZERO APK rebuild**.

---

## Backed-Up Production Workflows

| File | Workflow | Purpose |
| --- | --- | --- |
| [`hermes-sports-ai.json`](./hermes-sports-ai.json) | **Hermes Sports AI v5.0** | Daily Football & NBA quantitative engine, ESPN Injury Guard, Telegram One-Tap Bot, Supabase `daily_picks` writer + live `stream_id` auto-matcher |
| [`hermes-settlement.json`](./hermes-settlement.json) | **Hermes Settlement v5.0** | Autonomous **Supabase-first** grader (01:30 & 08:45 EAT), ESPN FT score verifier, updates Supabase + optional Google Sheet backup, sends Telegram cards |
| [`hermes-weekly-report.json`](./hermes-weekly-report.json) | **Hermes Weekly Performance Summary** | Every Sunday 20:00 EAT Football vs NBA P&L, ROI, and TZS bankroll summary |
| [`noellyne-ai-chat-api.json`](./noellyne-ai-chat-api.json) | **Noellyne Bet — AI Chat & Intelligence API** | Public `POST /webhook/noellyne-ai-chat` brain with instant 0-cost BetPawa slip split, Groq → Gemini → OpenRouter fallback, per-device rate limiter & cryptographic Supabase JWT VIP Owner Bypass |

---

## 5-Minute Migration Playbook (When Moving to a New VPS)

### Step 1 — Provision Docker + Caddy + n8n on New VPS
Install Docker & Docker Compose, point your domain (or update DuckDNS `mwijay.duckdns.org` to the new IP), and start n8n with automatic HTTPS (Caddy) and the required environment variables in `/opt/n8n/.env`:

```env
N8N_HOST=your-new-domain.example.com
WEBHOOK_URL=https://your-new-domain.example.com/
GENERIC_TIMEZONE=Africa/Dar_es_Salaam
TZ=Africa/Dar_es_Salaam

# LLM Provider Keys (server-side only — never inside Flutter APK)
GROQ_API_KEY=...
GEMINI_API_KEY=...
OPENROUTER_API_KEY=...

# Hermes Quant & Telegram Settings
ALTRAWARE_OWNER_TG_ID=8051901138
HERMES_BANKROLL_TZS=100000
```

### Step 2 — Re-Create the 3 Credentials in n8n
Open `https://<your-domain>/credentials` and create:
1. **`Noellyne Supabase`** (`Header Auth`):
   - Header Name: `apikey` (or configure `Authorization: Bearer <sb_secret_...>` — note Supabase accepts `apikey: <sb_secret_...>` for PostgREST writes)
   - Value: your `tahigoqhuyxedhmeqhnp` secret/service-role key from Supabase Dashboard → Settings → API
2. **`Noellyne BetBot`** (`Telegram API`):
   - Access Token from `@BotFather`
3. **`Google Sheets account`** (`Google Sheets OAuth2 API`, optional backup):
   - Reconnect with your Production Google OAuth app (`faidahq.tz@gmail.com`)

### Step 3 — Import & Activate All 4 JSON Workflows
In n8n UI → **Workflows → Import from File**:
1. Import all 4 JSON files from `n8n/`.
2. Re-bind the 3 credential dropdowns where prompted (names already match).
3. Click **Publish / Activate** on all 4 workflows.
4. Set the Telegram webhook (automatically handled when `Hermes Sports AI v5.0` activates).

### Step 4 — Zero-APK-Rebuild Cutover (If Domain Changed)
If your domain changed from `mwijay.duckdns.org` to a new URL, run **one SQL statement** in Supabase (`tahigoqhuyxedhmeqhnp` → SQL Editor):

```sql
update public.app_config
set value = 'https://your-new-domain.example.com/webhook/noellyne-ai-chat',
    updated_at = now()
where key = 'ai_chat_webhook';
```

Every installed Noellyne Bet APK automatically fetches `app_config` on launch and switches to the new server **without requiring any Play Store / GitHub APK update**.

> Tip: If you keep `mwijay.duckdns.org` and simply update its DuckDNS IP to the new server, even Step 4 is not needed — everything cuts over seamlessly!
