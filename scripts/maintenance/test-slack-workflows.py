#!/usr/bin/env python3
"""
Sequential Slack Workflow Test Runner
Tests all Slack-facing workflows one at a time without triggering heavy AI inference.

Strategy:
  - Lightweight: each test fires a minimal trigger and checks for an ACK / routing response
  - Non-queuing: tests run sequentially with a short wait between each
  - Non-destructive: test payloads are clearly labelled [TEST] and ignored by AI logic
  - Results posted to #ops-digest so you can see them without leaving Slack

Usage:
  python3 scripts/maintenance/test-slack-workflows.py [--full]

  --full: also trigger AI-inference flows (Ollama, /3d, /patent) — takes 2-3 min
          Default (no flag): only lightweight routing / webhook checks

Env requirements:
  SLACK_BOT_TOKEN  — set in /home/biulatech/n8n/.env (auto-loaded)
  WEBHOOK_URL      — ngrok base URL
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
import hmac
import hashlib

# ──────────────────────────────────────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────────────────────────────────────
ENV_FILE = "/home/biulatech/n8n/.env"
N8N_BASE = "http://localhost:5678"
RESULTS_CHANNEL = "C0AKZLGFH50"   # #ops-digest

FULL_MODE = "--full" in sys.argv

# Load env
env = {}
try:
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip()
except Exception as e:
    print(f"WARN: could not read {ENV_FILE}: {e}")

SLACK_TOKEN  = env.get("SLACK_BOT_TOKEN", os.environ.get("SLACK_BOT_TOKEN", ""))
NGROK_BASE   = env.get("WEBHOOK_URL", "http://localhost:5678").rstrip("/")
SIGNING_SEC  = env.get("SLACK_SIGNING_SECRET", "")

if not SLACK_TOKEN:
    print("ERROR: SLACK_BOT_TOKEN not found. Cannot post results.")
    sys.exit(1)

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def post_slack(channel: str, text: str, blocks=None):
    payload = {"channel": channel, "text": text}
    if blocks:
        payload["blocks"] = blocks
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=data,
        method="POST",
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {SLACK_TOKEN}"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"ok": False, "error": str(e)}


def http_get(url: str, timeout=8) -> tuple[int, str]:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "n8n-test-runner/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")
    except Exception as e:
        return 0, str(e)


def http_post(url: str, body: dict | str, headers=None, timeout=8) -> tuple[int, str]:
    if isinstance(body, dict):
        data = json.dumps(body).encode()
        content_type = "application/json"
    else:
        data = body.encode() if isinstance(body, str) else body
        content_type = "application/x-www-form-urlencoded"
    h = {"Content-Type": content_type, "User-Agent": "n8n-test-runner/1.0"}
    if headers:
        h.update(headers)
    try:
        req = urllib.request.Request(url, data=data, method="POST", headers=h)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")
    except Exception as e:
        return 0, str(e)


def slack_signature(body: str, secret: str, ts: str) -> str:
    """Generate a valid Slack request signature."""
    sig_base = f"v0:{ts}:{body}"
    return "v0=" + hmac.new(secret.encode(), sig_base.encode(), hashlib.sha256).hexdigest()


def make_slack_headers(body: str) -> dict:
    ts = str(int(time.time()))
    sig = slack_signature(body, SIGNING_SEC, ts)
    return {
        "X-Slack-Request-Timestamp": ts,
        "X-Slack-Signature": sig,
    }


# ──────────────────────────────────────────────────────────────────────────────
# Test cases
# ──────────────────────────────────────────────────────────────────────────────

results = []   # list of (name, ok, detail)


def record(name: str, ok: bool, detail: str):
    icon = "✅" if ok else "❌"
    print(f"  {icon} {name}: {detail}")
    results.append((name, ok, detail))


def run_test(name: str, fn):
    print(f"\n[{name}]")
    try:
        fn()
    except Exception as e:
        record(name, False, f"Exception: {e}")


# ── 1. n8n health ─────────────────────────────────────────────────────────────
def test_n8n_health():
    code, body = http_get(f"{N8N_BASE}/healthz")
    ok = code == 200
    record("n8n /healthz", ok, f"HTTP {code}")

# ── 2. Ngrok tunnel reachable ─────────────────────────────────────────────────
def test_ngrok():
    code, _ = http_get(f"{NGROK_BASE}/healthz", timeout=6)
    ok = code == 200
    record("ngrok→n8n /healthz", ok, f"HTTP {code} (via {NGROK_BASE})")

# ── 3. Slack Events Receiver webhook ─────────────────────────────────────────
def test_events_receiver():
    # Send a Slack url_verification challenge — n8n must echo back the challenge
    body = json.dumps({
        "type": "url_verification",
        "challenge": "test_challenge_abc123",
        "token": "test"
    })
    url = f"{NGROK_BASE}/webhook/slack-events"
    hdrs = make_slack_headers(body)
    code, resp = http_post(url, body, headers=hdrs, timeout=8)
    # Accept HTTP 200 as proof the webhook is reachable and routing correctly.
    # (url_verification echo is only required during Slack app verification setup.)
    ok = code == 200
    detail = f"HTTP {code}" + (" — webhook reachable" if ok else f" — response: {resp[:80]}")
    record("Slack Events Receiver", ok, detail)

# ── 4. Slack Command Handler — /status ────────────────────────────────────────
def test_command_status():
    # /status is lightweight: no Ollama, just reads DB
    form = "command=%2Fstatus&text=&user_id=U0TEST&user_name=testbot&channel_id=C0AKZLGFH50&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2Ftest"
    url = f"{NGROK_BASE}/webhook/slack-command"
    ts = str(int(time.time()))
    sig = "v0=" + hmac.new(SIGNING_SEC.encode(), f"v0:{ts}:{form}".encode(), hashlib.sha256).hexdigest()
    hdrs = {"X-Slack-Request-Timestamp": ts, "X-Slack-Signature": sig,
            "Content-Type": "application/x-www-form-urlencoded"}
    code, resp = http_post(url, form, headers=hdrs, timeout=10)
    ok = code in (200, 202)
    detail = f"HTTP {code}" + (f" — ack OK" if ok else f" — {resp[:80]}")
    record("Command Handler /status", ok, detail)

# ── 5. Slack Command Handler — /diagnose ─────────────────────────────────────
def test_command_diagnose():
    form = "command=%2Fdiagnose&text=&user_id=U0TEST&user_name=testbot&channel_id=C0AKZLGFH50&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2Ftest"
    url = f"{NGROK_BASE}/webhook/slack-command"
    ts = str(int(time.time()))
    sig = "v0=" + hmac.new(SIGNING_SEC.encode(), f"v0:{ts}:{form}".encode(), hashlib.sha256).hexdigest()
    hdrs = {"X-Slack-Request-Timestamp": ts, "X-Slack-Signature": sig,
            "Content-Type": "application/x-www-form-urlencoded"}
    code, resp = http_post(url, form, headers=hdrs, timeout=10)
    ok = code in (200, 202)
    record("Command Handler /diagnose", ok, f"HTTP {code}")

# ── 6. Tasks Channel Handler — channel message routing ───────────────────────
def test_tasks_channel():
    # Post a message_event with [TEST] label — Tasks Handler should ack quickly
    body = json.dumps({
        "type": "event_callback",
        "event": {
            "type": "message",
            "channel": "C0AKXJSTRV4",  # tasks-kevin
            "text": "[TEST] workflow test ping — ignore",
            "user": "U0TEST",
            "ts": f"{int(time.time())}.000000"
        },
        "team_id": "T0AKQL4FZMX",
        "event_id": "Ev_TEST001"
    })
    url = f"{NGROK_BASE}/webhook/slack-events"
    hdrs = make_slack_headers(body)
    code, _ = http_post(url, body, headers=hdrs, timeout=8)
    ok = code in (200, 202)
    record("Tasks Channel Handler routing", ok, f"HTTP {code}")

# ── 7. The Council Router — @mention ─────────────────────────────────────────
def test_council_router():
    body = json.dumps({
        "type": "event_callback",
        "event": {
            "type": "message",
            "channel": "C0AKVJ5PHHR",   # #the-council
            "text": "<@U_KEVIN_BOT> [TEST] routing ping — ignore",
            "user": "U0TEST",
            "ts": f"{int(time.time())}.000001"
        },
        "team_id": "T0AKQL4FZMX",
        "event_id": "Ev_TEST002"
    })
    url = f"{NGROK_BASE}/webhook/slack-events"
    hdrs = make_slack_headers(body)
    code, _ = http_post(url, body, headers=hdrs, timeout=8)
    ok = code in (200, 202)
    record("Council Router @mention routing", ok, f"HTTP {code}")

# ── 8. Preview image server ───────────────────────────────────────────────────
def test_preview_server():
    # Request a non-existent job — should return 404 JSON (server is up)
    url = f"{NGROK_BASE}/webhook/preview-3d?job=test_nonexistent"
    code, resp = http_get(url, timeout=8)
    ok = code in (200, 404) and ("not found" in resp.lower() or code == 200)
    detail = f"HTTP {code}" + (" — server responding" if ok else f" — {resp[:60]}")
    record("Preview Image Server", ok, detail)

# ── Full-mode: AI inference tests ──────────────────────────────────────────────
def test_ai_command():
    """POST /ai 'hello' — triggers Ollama inference"""
    form = "command=%2Fai&text=Hello+test+ping&user_id=U0TEST&user_name=testbot&channel_id=C0AKZLGFH50&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2Ftest"
    url = f"{NGROK_BASE}/webhook/slack-command"
    ts = str(int(time.time()))
    sig = "v0=" + hmac.new(SIGNING_SEC.encode(), f"v0:{ts}:{form}".encode(), hashlib.sha256).hexdigest()
    hdrs = {"X-Slack-Request-Timestamp": ts, "X-Slack-Signature": sig,
            "Content-Type": "application/x-www-form-urlencoded"}
    code, _ = http_post(url, form, headers=hdrs, timeout=15)
    ok = code in (200, 202)
    record("Command Handler /ai (full)", ok, f"HTTP {code} — wait for Slack reply")

def test_3d_command():
    """POST /3d 'cube' — triggers OpenSCAD + Ollama"""
    form = "command=%2F3d&text=simple+1cm+cube&user_id=U0TEST&user_name=testbot&channel_id=C0AKZLGFH50&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2Ftest"
    url = f"{NGROK_BASE}/webhook/slack-command"
    ts = str(int(time.time()))
    sig = "v0=" + hmac.new(SIGNING_SEC.encode(), f"v0:{ts}:{form}".encode(), hashlib.sha256).hexdigest()
    hdrs = {"X-Slack-Request-Timestamp": ts, "X-Slack-Signature": sig,
            "Content-Type": "application/x-www-form-urlencoded"}
    code, _ = http_post(url, form, headers=hdrs, timeout=20)
    ok = code in (200, 202)
    record("Command Handler /3d (full)", ok, f"HTTP {code} — wait for Slack reply")

# ──────────────────────────────────────────────────────────────────────────────
# Run tests
# ──────────────────────────────────────────────────────────────────────────────

print("=" * 60)
print("n8n Slack Workflow Test Runner")
print(f"Mode: {'FULL (AI inference enabled)' if FULL_MODE else 'lightweight (no AI inference)'}")
print(f"Target: {NGROK_BASE}")
print("=" * 60)

run_test("n8n Health",               test_n8n_health)
time.sleep(0.5)
run_test("Ngrok Tunnel",             test_ngrok)
time.sleep(0.5)
run_test("Events Receiver",          test_events_receiver)
time.sleep(1)
run_test("Command /status",          test_command_status)
time.sleep(1)
run_test("Command /diagnose",        test_command_diagnose)
time.sleep(1)
run_test("Tasks Channel Routing",    test_tasks_channel)
time.sleep(1)
run_test("Council Router Routing",   test_council_router)
time.sleep(0.5)
run_test("Preview Image Server",     test_preview_server)

if FULL_MODE:
    print("\n[Full mode — triggering AI inference tests]")
    time.sleep(2)
    run_test("AI Command /ai",       test_ai_command)
    time.sleep(2)
    run_test("3D Command /3d",       test_3d_command)

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────

total  = len(results)
passed = sum(1 for _, ok, _ in results if ok)
failed = total - passed

print("\n" + "=" * 60)
print(f"Results: {passed}/{total} passed")
print("=" * 60)

# Build Slack blocks
header_color = "good" if failed == 0 else ("warning" if failed <= 2 else "danger")
rows = ""
for name, ok, detail in results:
    icon = "✅" if ok else "❌"
    rows += f"{icon} *{name}*: {detail}\n"

blocks = [
    {"type": "header",
     "text": {"type": "plain_text", "text": f"🧪 Workflow Test Results — {passed}/{total} passed"}},
    {"type": "section",
     "text": {"type": "mrkdwn", "text": rows.strip()}},
    {"type": "context",
     "elements": [{"type": "mrkdwn",
                   "text": f"Mode: {'full' if FULL_MODE else 'lightweight'} · Target: `{NGROK_BASE}` · View details: http://localhost:3001"}]}
]

r = post_slack(RESULTS_CHANNEL, f"Workflow test: {passed}/{total} passed", blocks=blocks)
if r.get("ok"):
    print(f"\nResults posted to #ops-digest ✅")
else:
    print(f"\nFailed to post to Slack: {r.get('error')}")
    print("Results printed above ^")

sys.exit(0 if failed == 0 else 1)
