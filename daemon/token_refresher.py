#!/usr/bin/env python3
"""Keep the Claude OAuth access token fresh for the Clawdmeter daemon.

The daemon (`claude_usage_daemon.py`) reads ~/.claude/.credentials.json on every
poll but never refreshes it. On a desktop, Claude Code keeps that file fresh; on
a headless host (e.g. a Dockerized server) nothing does, and the access token
expires in ~8h — after which the daemon gets HTTP 401 and stops updating.

This sidecar fills that gap. It runs next to the daemon, sharing the same token
file via a Docker volume. On first start it seeds the volume from a read-only
copy of your credentials, then it refreshes the access token with the stored
refresh token shortly before each expiry and writes the rotated credentials
back atomically. The daemon picks up the new token on its next poll.

Self-contained: stdlib + httpx only. All endpoints/IDs are env-overridable so
nothing is hard-wired if the upstream OAuth details ever change.
"""

import json
import os
import shutil
import sys
import time
from pathlib import Path

import httpx

# Token store the daemon reads (inside the shared volume).
CREDENTIALS_PATH = Path(
    os.environ.get("CLAUDE_CREDENTIALS_PATH", str(Path.home() / ".claude" / ".credentials.json"))
)
# Read-only seed used once if the store is empty (your copied credentials).
SEED_PATH = Path(os.environ.get("CLAUDE_CREDENTIALS_SEED", "/seed/.credentials.json"))

# Claude Code's public OAuth client + token endpoint. Override via env if these
# ever change. This refreshes YOUR OWN token for YOUR OWN device — same grant
# Claude Code itself performs.
TOKEN_URL = os.environ.get("CLAUDE_OAUTH_TOKEN_URL", "https://console.anthropic.com/v1/oauth/token")
CLIENT_ID = os.environ.get("CLAUDE_OAUTH_CLIENT_ID", "9d1c250a-e61b-44d9-88ed-5944d1962f5e")

CHECK_INTERVAL = int(os.environ.get("REFRESH_CHECK_INTERVAL", "600"))  # poll the store every 10 min
REFRESH_MARGIN = int(os.environ.get("REFRESH_MARGIN", "1800"))         # refresh when <30 min to expiry
REFRESH_ON_START = os.environ.get("REFRESH_ON_START", "true").lower() == "true"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] refresher: {msg}", flush=True)


def load() -> tuple[dict, dict]:
    """Return (whole_doc, oauth_subdict). Supports the flat and the
    {"claudeAiOauth": {...}} credential shapes; writes preserve the shape."""
    doc = json.loads(CREDENTIALS_PATH.read_text())
    if isinstance(doc, dict) and isinstance(doc.get("claudeAiOauth"), dict):
        return doc, doc["claudeAiOauth"]
    return doc, doc


def save(doc: dict) -> None:
    tmp = CREDENTIALS_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(doc, indent=2))
    tmp.replace(CREDENTIALS_PATH)  # atomic
    try:
        os.chmod(CREDENTIALS_PATH, 0o600)
    except OSError:
        pass


def seed_if_needed() -> None:
    if CREDENTIALS_PATH.exists():
        return
    CREDENTIALS_PATH.parent.mkdir(parents=True, exist_ok=True)
    if SEED_PATH.exists():
        shutil.copyfile(SEED_PATH, CREDENTIALS_PATH)
        log(f"seeded token store from {SEED_PATH}")
    else:
        log(f"FATAL: no token at {CREDENTIALS_PATH} and no seed at {SEED_PATH}")
        log("       copy your ~/.claude/.credentials.json into the seed location first.")
        sys.exit(1)


def refresh(oauth: dict) -> bool:
    """Exchange the refresh token for a new access token. Mutates oauth in place.
    Never logs token material."""
    rt = oauth.get("refreshToken")
    if not rt:
        log("no refreshToken in credentials — cannot refresh (re-login on a desktop)")
        return False
    try:
        r = httpx.post(
            TOKEN_URL,
            json={"grant_type": "refresh_token", "refresh_token": rt, "client_id": CLIENT_ID},
            headers={"Content-Type": "application/json"},
            timeout=30,
        )
    except httpx.HTTPError as e:
        log(f"refresh request error: {e}")
        return False
    if r.status_code != 200:
        log(f"refresh failed: HTTP {r.status_code} {r.text[:120]}")
        return False
    d = r.json()
    if not d.get("access_token"):
        log("refresh response missing access_token")
        return False
    oauth["accessToken"] = d["access_token"]
    if d.get("refresh_token"):
        oauth["refreshToken"] = d["refresh_token"]
    if d.get("expires_in"):
        oauth["expiresAt"] = int((time.time() + int(d["expires_in"])) * 1000)
    return True


def seconds_to_expiry(oauth: dict) -> float:
    exp = oauth.get("expiresAt")
    if not exp:
        return -1  # unknown -> treat as needing refresh
    return exp / 1000 - time.time()


def main() -> None:
    seed_if_needed()
    first = True
    while True:
        try:
            doc, oauth = load()
            left = seconds_to_expiry(oauth)
            need = left < REFRESH_MARGIN or (first and REFRESH_ON_START)
            if need:
                why = "startup validation" if (first and REFRESH_ON_START and left >= REFRESH_MARGIN) else f"{int(left)}s to expiry"
                log(f"refreshing ({why})...")
                if refresh(oauth):
                    save(doc)
                    log(f"refreshed OK — next expiry in {int(seconds_to_expiry(oauth) / 60)} min")
            else:
                log(f"token healthy ({int(left / 60)} min left)")
        except Exception as e:  # never let the loop die
            log(f"loop error: {e}")
        first = False
        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
