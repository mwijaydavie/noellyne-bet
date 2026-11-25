#!/usr/bin/env python3
"""
Sanitizes exported n8n workflow JSON files for safe GitHub version-control backup.
Author: David Erick Mwijage (Altraware Technology Ltd)

Usage:
  python scripts/sanitize_n8n_backup.py <input.json> <output.json>

Guarantees:
  - Keeps full n8n-importable structure (name, nodes, connections, settings)
  - Replaces internal credential IDs with "<CONFIGURE_IN_N8N>"
  - Scrubs any accidentally embedded API keys, JWTs, Telegram bot tokens,
    Supabase secret keys, Google OAuth secrets, or private keys
  - Fails closed (non-zero exit) if any secret pattern remains after sanitization
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SECRET_PATTERNS: list[tuple[str, re.Pattern[str], str]] = [
    ("PRIVATE_KEY", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"), "<REDACTED_PRIVATE_KEY>"),
    ("GROQ_KEY", re.compile(r"gsk_[A-Za-z0-9_-]{20,}"), "<REDACTED_GROQ_KEY>"),
    ("GOOGLE_API_KEY", re.compile(r"AIza[0-9A-Za-z_-]{30,}"), "<REDACTED_GOOGLE_API_KEY>"),
    ("OPENROUTER_KEY", re.compile(r"sk-or-v1-[A-Za-z0-9]{24,}"), "<REDACTED_OPENROUTER_KEY>"),
    ("OPENAI_KEY", re.compile(r"\bsk-[A-Za-z0-9_-]{24,}\b"), "<REDACTED_API_KEY>"),
    ("SUPABASE_SECRET", re.compile(r"\b(?:sb_secret|sbp)_[A-Za-z0-9_-]{16,}\b"), "<REDACTED_SUPABASE_SECRET>"),
    ("GOOGLE_OAUTH_SECRET", re.compile(r"GOCSPX-[A-Za-z0-9_-]{16,}"), "<REDACTED_GOOGLE_OAUTH_SECRET>"),
    ("TELEGRAM_BOT_TOKEN", re.compile(r"\b\d{8,11}:[A-Za-z0-9_-]{30,}\b"), "<REDACTED_TELEGRAM_BOT_TOKEN>"),
    ("JWT_TOKEN", re.compile(r"eyJhbGciOi[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"), "<REDACTED_JWT>"),
    ("BEARER_LITERAL", re.compile(r"(Bearer\s+)[A-Za-z0-9._-]{28,}"), r"\1<REDACTED_BEARER_TOKEN>"),
    ("GITHUB_PAT", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b"), "<REDACTED_GITHUB_TOKEN>"),
]


def scrub_text(text: str) -> str:
    out = text
    for _, pattern, replacement in SECRET_PATTERNS:
        out = pattern.sub(replacement, out)
    return out


def sanitize_value(val: Any) -> Any:
    if isinstance(val, str):
        return scrub_text(val)
    if isinstance(val, list):
        return [sanitize_value(v) for v in val]
    if isinstance(val, dict):
        cleaned: dict[str, Any] = {}
        for k, v in val.items():
            if k == "credentials" and isinstance(v, dict):
                creds: dict[str, Any] = {}
                for c_type, c_obj in v.items():
                    if isinstance(c_obj, dict):
                        creds[c_type] = {
                            "id": "<CONFIGURE_IN_N8N>",
                            "name": str(c_obj.get("name") or c_type),
                        }
                    else:
                        creds[c_type] = c_obj
                cleaned[k] = creds
            else:
                cleaned[k] = sanitize_value(v)
        return cleaned
    return val


def sanitize_workflow(raw_doc: dict[str, Any]) -> dict[str, Any]:
    wf = raw_doc.get("workflow") if isinstance(raw_doc.get("workflow"), dict) else raw_doc
    keep = {
        "name": wf.get("name", "Untitled Workflow"),
        "description": wf.get("description") or "",
        "active": bool(wf.get("active", False)),
        "nodes": wf.get("nodes") or [],
        "connections": wf.get("connections") or {},
        "settings": wf.get("settings") or {"executionOrder": "v1"},
        "meta": {
            "sourceWorkflowId": wf.get("id", ""),
            "activeVersionId": wf.get("activeVersionId") or wf.get("versionId") or "",
            "backedUpAtUtc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "sanitized": True,
        },
    }
    return sanitize_value(keep)


def audit_clean(serialized: str, label: str) -> None:
    leaks: list[str] = []
    for name, pattern, _ in SECRET_PATTERNS:
        if pattern.search(serialized):
            leaks.append(name)
    if leaks:
        raise SystemExit(f"SECURITY BLOCK ({label}): Secret pattern(s) still present: {', '.join(leaks)}")


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: python scripts/sanitize_n8n_backup.py <input.json> <output.json>", file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    raw = json.loads(src.read_text(encoding="utf-8"))
    sanitized = sanitize_workflow(raw)
    text = json.dumps(sanitized, indent=2, ensure_ascii=False) + "\n"
    audit_clean(text, dst.name)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text, encoding="utf-8")
    print(f"[OK] Backed up & sanitized {dst.name} ({len(sanitized['nodes'])} nodes, {len(text)} bytes, 0 secrets)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
