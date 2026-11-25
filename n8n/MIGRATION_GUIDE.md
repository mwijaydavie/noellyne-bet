# Noellyne & Altraware n8n Production Backup & Disaster-Recovery Guide

**Authors:** David Erick Mwijage & Clemence W. N'gunda — **Altraware Technology Ltd**  
**Production Host:** `https://mwijay.duckdns.org` (AWS EC2 `i-0cc1e65a07b17d1d5`, `eu-north-1`)  
**Dedicated Noellyne Supabase:** `tahigoqhuyxedhmeqhnp` (`https://tahigoqhuyxedhmeqhnp.supabase.co`)  
**Firebase Project:** `altraware-automations` (`noellyne.app`)

All workflow files in this directory are **100% sanitized** via `scripts/sanitize_n8n_backup.py` (zero API keys, JWTs, bot tokens, or private keys committed to Git).

---

## Backed-Up Production Workflows

| File | Live Workflow ID | Schedule / Trigger | Purpose |
|---|---|---|---|
| `hermes-sports-ai.json` | `reZre7G6tPP2aSwj` | `07:30, 09:00, 14:00, 19:00 EAT` + Telegram | Football (22 leagues incl. CAF CL/Confed for Simba/Yanga/Azam) + NBA Sniper Quant Engine, Supabase `daily_picks` publisher, live `stream_id` matcher, FCM push (`noellyne_picks`). |
| `hermes-settlement.json` | `xsQuUV3Vfc6Z1TQJ` | `01:30 & 08:45 EAT` | Supabase-first autonomous grader across 30+ leagues (incl. CAF CL/Confed, Championship, Argentina), canonical `tags` preservation, Telegram summary + FCM win alerts (`noellyne_results`). |
| `noellyne-fixtures-sync.json` | `PSZrsfnn2dyTLdLA` | Every 15 minutes | Syncs 31 Football leagues (incl. CAF CL, CAF Confed, RSA/Kenya/Uganda, UCL/UEL/UECL, midweek leagues) + NBA into Supabase `public.fixtures` with midnight-safe stale deactivation. |
| `noellyne-ai-chat-api.json` | `mKAODz9f6rZyLCT7` | Webhook `/webhook/noellyne-ai-chat` | In-app Noellyne AI v3.1: persistent Postgres daily quotas (3/10/VIP), anti-cache-clear hardware fingerprint, Cloud User AI Memory (`user_ai_memory`), Altraware identity & interactive action chips. |
| `hermes-weekly-report.json` | `WNiHHMe0MfaTeIOT` | Sunday `19:00 EAT` | Weekly Football vs NBA ROI summary delivered to Telegram. |
| `altraware-linkedin-studio.json` | `QzZ8x4zGpZec8PXa` | Telegram `@linkinmwijay_bot` + Drive | LinkedIn Images & Native MP4 Videos (`feedshare-video`) studio with Gemini 2.5 Flash Vision. |

---

## 60-Second Disaster Recovery (How to Restore on a Fresh n8n Instance)

1. **Import JSON:** In n8n UI → **Workflows → Import from File** → pick any `.json` from `n8n/`.
2. **Re-attach Credentials** (each placeholder `<CONFIGURE_IN_N8N>` shows the exact credential name):
   - `Noellyne Supabase` (`Header Auth`: `apikey` / `Authorization: Bearer <sb_secret_...>` for `tahigoqhuyxedhmeqhnp`)
   - `Google Service Account account` (`Google API` for Firebase FCM HTTP v1, `Set up for use in HTTP Request node = ON`, scope `https://www.googleapis.com/auth/firebase.messaging`)
   - Telegram Bot credentials (`@Mxtech_bot` / `@linkinmwijay_bot`)
   - Groq / Gemini / OpenRouter API keys (configured in n8n Credentials or env vars)
   - LinkedIn OAuth2 & Google Drive OAuth2 (for `altraware-linkedin-studio.json`)
3. **Publish / Activate** the workflow and run 1 manual test execution.
4. **Update App Webhook (if domain changed):** Update `public.app_config` (`key = 'ai_chat_webhook'`) in Supabase — all installed Noellyne APKs pick up the new URL automatically without rebuilding!

---

## How to Refresh Backups Safely

Whenever you export a workflow JSON from n8n, always run it through the sanitizer before committing:

```bash
python scripts/sanitize_n8n_backup.py exported-raw.json n8n/hermes-sports-ai.json
```

The script automatically strips credential IDs and fails closed if any API key, JWT, private key, or bot token pattern is detected.
