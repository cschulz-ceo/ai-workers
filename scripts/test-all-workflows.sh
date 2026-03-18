#!/bin/bash
# =============================================================================
# test-all-workflows.sh
# Tests all n8n workflows and reports results to Slack (#ops-pulse)
#
# Orchestration strategy:
#   - Non-Ollama workflows run first (fast, seconds each)
#   - Ollama-heavy workflows run SEQUENTIALLY with waits between them
#     (prevents queue buildup and timeouts on the 14B model)
#   - ComfyUI workflows run as actual inference calls (SDXL, AnimateDiff, ESRGAN)
#   - Scheduled-only workflows verified as active (not triggered)
#
# Usage:
#   bash scripts/test-all-workflows.sh              # full test suite
#   bash scripts/test-all-workflows.sh --quick      # skip Ollama tests
#   bash scripts/test-all-workflows.sh --dry-run    # connectivity check only
#
# Output: Posts results to Slack #ops-pulse
# =============================================================================

set -uo pipefail   # -e intentionally excluded — we catch failures ourselves

# ── Config ────────────────────────────────────────────────────────────────────
ENV_FILE="/home/biulatech/n8n/.env"
N8N_BASE="http://localhost:5678"
WEBHOOK="$N8N_BASE/webhook"
DB="/home/biulatech/n8n/n8n_data/database.sqlite"
OLLAMA_BASE="http://localhost:11434"
MODE="${1:-}"          # --quick, --dry-run, or empty for full

# ── Load environment ──────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found"; exit 1
fi
set -a
# shellcheck disable=SC1090
source <(grep -E '^[A-Z_]+=[^$[:space:]]' "$ENV_FILE" | sed 's/#[^=]*.*//' | sed 's/[[:space:]]*$//')
set +a

# Target channel for test results (ops-pulse = monitoring feed)
REPORT_CHANNEL="${SLACK_CHANNEL_OPS_PULSE:-}"
# Channel where test workflow outputs will be directed
TEST_CHANNEL="${SLACK_CHANNEL_OPS_PULSE:-}"
# Fake Slack user (Claude/automation)
TEST_USER="U0AKBNLRXMY"
# Async responses from /ai etc. will land at the incoming webhook channel
FAKE_RESPONSE_URL="${SLACK_INCOMING_WEBHOOK_URL:-}"

# ── State tracking ─────────────────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0; WARN=0
declare -a REPORT_LINES=()
START_TIME=$(date +%s)

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*"; }

urlencode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

slack_post() {
  # Post plain text to the report channel
  local text="$1"
  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"${REPORT_CHANNEL}\",\"text\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text")}" \
    > /dev/null 2>&1
}

slack_blocks_post() {
  # Post a blocks payload to the report channel
  local payload="$1"
  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1
}

get_execution_status() {
  # Poll SQLite for latest execution status for a workflow after a given unix timestamp
  local workflow_id="$1"
  local since_ts="$2"
  sqlite3 "$DB" \
    "SELECT status FROM execution_entity
     WHERE workflowId='${workflow_id}'
       AND startedAt > datetime(${since_ts}, 'unixepoch')
     ORDER BY startedAt DESC LIMIT 1;" 2>/dev/null
}

wait_for_completion() {
  # Wait up to timeout_s for an execution to reach success/error/crashed
  local workflow_id="$1"
  local timeout_s="$2"
  local since_ts="$3"
  local elapsed=0
  local poll=3

  while [[ $elapsed -lt $timeout_s ]]; do
    local st
    st=$(get_execution_status "$workflow_id" "$since_ts")
    case "$st" in
      success|error|crashed|waiting)
        echo "$st"; return 0 ;;
    esac
    sleep $poll
    elapsed=$((elapsed + poll))
  done
  echo "timeout"
  return 0
}

mark_pass() {
  local name="$1"; local detail="${2:-}"
  PASS=$((PASS+1))
  REPORT_LINES+=("✅  *${name}*${detail:+  —  ${detail}}")
  log "PASS  $name"
}

mark_fail() {
  local name="$1"; local detail="${2:-}"
  FAIL=$((FAIL+1))
  REPORT_LINES+=("❌  *${name}*${detail:+  —  ${detail}}")
  log "FAIL  $name  ${detail}"
}

mark_skip() {
  local name="$1"; local reason="${2:-}"
  SKIP=$((SKIP+1))
  REPORT_LINES+=("⏭️  *${name}*${reason:+  —  ${reason}}")
  log "SKIP  $name"
}

mark_warn() {
  local name="$1"; local detail="${2:-}"
  WARN=$((WARN+1))
  REPORT_LINES+=("⚠️  *${name}*${detail:+  —  ${detail}}")
  log "WARN  $name  ${detail}"
}

# ── Test functions ─────────────────────────────────────────────────────────────

check_services() {
  log "Checking services..."
  local n8n_ok ollama_ok
  n8n_ok=$(curl -s -o /dev/null -w "%{http_code}" "${N8N_BASE}/healthz")
  ollama_ok=$(curl -s -o /dev/null -w "%{http_code}" "${OLLAMA_BASE}/api/tags")

  if [[ "$n8n_ok" != "200" ]]; then
    echo "ERROR: n8n not healthy (HTTP ${n8n_ok})"; exit 1
  fi
  if [[ "$ollama_ok" != "200" ]]; then
    echo "ERROR: Ollama not reachable (HTTP ${ollama_ok})"; exit 1
  fi
  log "Services OK  (n8n=200  ollama=200)"
}

check_active() {
  # Verify a workflow is active in the DB — no network call needed
  local name="$1"
  local workflow_id="$2"
  local active
  active=$(sqlite3 "$DB" "SELECT active FROM workflow_entity WHERE id='${workflow_id}';" 2>/dev/null)
  if [[ "$active" == "1" ]]; then
    mark_pass "$name" "active"
  else
    mark_fail "$name" "inactive in DB (id=${workflow_id})"
  fi
}

test_fast_webhook() {
  # Test a webhook that doesn't call Ollama — should complete in <30s
  local name="$1"
  local path="$2"
  local form_data="$3"
  local workflow_id="$4"
  local timeout_s="${5:-30}"

  [[ "$MODE" == "--dry-run" ]] && { mark_warn "$name" "dry-run skip"; return; }

  log "Testing webhook: $name"
  local before_ts; before_ts=$(date +%s)

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${WEBHOOK}/${path}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-raw "$form_data" 2>/dev/null)

  if [[ "$http_code" =~ ^(200|202)$ ]]; then
    local status
    status=$(wait_for_completion "$workflow_id" "$timeout_s" "$before_ts")
    case "$status" in
      success)  mark_pass "$name" ;;
      error|crashed) mark_fail "$name" "execution ${status} — check n8n UI" ;;
      timeout)  mark_warn "$name" "no completion in ${timeout_s}s" ;;
      *)        mark_warn "$name" "unexpected status: ${status}" ;;
    esac
  else
    mark_fail "$name" "webhook returned HTTP ${http_code}"
  fi
}

test_slack_command() {
  # Test an Ollama-heavy slash command — run ONLY sequentially
  local name="$1"
  local command="$2"
  local text="$3"
  local timeout_s="${4:-120}"

  if [[ "$MODE" == "--quick" || "$MODE" == "--dry-run" ]]; then
    mark_skip "$name" "${MODE} mode"
    return
  fi

  log "Testing Ollama command: $name  (timeout=${timeout_s}s)"
  local before_ts; before_ts=$(date +%s)

  local enc_response_url
  enc_response_url=$(urlencode "${FAKE_RESPONSE_URL}")

  local form_data="command=$(urlencode "${command}")&text=$(urlencode "${text}")&channel_id=${TEST_CHANNEL}&user_id=${TEST_USER}&user_name=health-check&response_url=${enc_response_url}"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${WEBHOOK}/slack-command" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-raw "$form_data" 2>/dev/null)

  if [[ "$http_code" =~ ^(200|202)$ ]]; then
    # Slack Command Handler v2 is the workflow being tested
    local status
    status=$(wait_for_completion "VqmllB5WdHsKmntj" "$timeout_s" "$before_ts")
    case "$status" in
      success)  mark_pass "$name" ;;
      error|crashed) mark_fail "$name" "execution ${status} — check n8n executions" ;;
      timeout)  mark_warn "$name" "Ollama still processing after ${timeout_s}s — not necessarily failed" ;;
      *)        mark_warn "$name" "unexpected status: ${status}" ;;
    esac
  else
    mark_fail "$name" "webhook returned HTTP ${http_code}"
  fi

  # IMPORTANT: Wait between Ollama calls so the model finishes and frees VRAM
  # before the next workflow tries to acquire it
  if [[ "$MODE" != "--quick" && "$MODE" != "--dry-run" ]]; then
    log "Waiting 8s for Ollama to free up..."
    sleep 8
  fi
}

test_direct_json_webhook() {
  # Test a webhook that expects JSON body
  local name="$1"
  local path="$2"
  local json_body="$3"
  local workflow_id="$4"
  local timeout_s="${5:-120}"

  if [[ "$MODE" == "--quick" || "$MODE" == "--dry-run" ]]; then
    mark_skip "$name" "${MODE} mode"
    return
  fi

  log "Testing: $name"
  local before_ts; before_ts=$(date +%s)

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${WEBHOOK}/${path}" \
    -H "Content-Type: application/json" \
    -d "$json_body" 2>/dev/null)

  if [[ "$http_code" =~ ^(200|202)$ ]]; then
    local status
    status=$(wait_for_completion "$workflow_id" "$timeout_s" "$before_ts")
    case "$status" in
      success)  mark_pass "$name" ;;
      error|crashed) mark_fail "$name" "execution ${status}" ;;
      timeout)  mark_warn "$name" "no completion in ${timeout_s}s" ;;
      *)        mark_warn "$name" "unexpected: ${status}" ;;
    esac
  else
    mark_fail "$name" "HTTP ${http_code}"
  fi

  sleep 8   # Ollama cooldown
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN TEST SUITE
# ══════════════════════════════════════════════════════════════════════════════

log "=== Workflow Health Check | mode: ${MODE:-full} ==="

check_services

# Announce start
slack_post ":test_tube: *Workflow health check starting...* (mode: \`${MODE:-full}\`)"

# ── GROUP 1: Active status check (instant, all 20 workflows) ──────────────────
log "--- Group 1: Active status checks ---"
check_active "Slack Command Handler v2"     "VqmllB5WdHsKmntj"
check_active "Slack Events Receiver"        "f5rTNCSNGXwKiwvE"
check_active "Slack Status Handler"         "KxnpgKyTLMAd4Ygs"
check_active "Slack Diagnose Handler"       "QCrmHKpu1KktTK1M"
check_active "GitHub Push Handler"          "ZWma6DaWSwTdvft8"
check_active "Ops Daily Digest"             "IBYZgfl7Du9jTWp6"
check_active "Weekly News Digest"           "d7350619-528b-481d-bb87-fa245d2734bb"
check_active "Ops Service Monitor"          "hKRONxaLSsSfVjO4"
check_active "Ops GPU Alert"                "ops-gpu-alert-001"
check_active "Tasks Channel Handler"        "i1TOhKVyXkLXD01W"
check_active "The Council Router"           "counsel-router-001"
check_active "Linear AI PM"                 "linear-pm-001"
check_active "News Article Generator"       "cf2282e0-c226-4030-8df4-59ec9fb61a7c"
check_active "3D CAD Generator"             "cad-3d-001"
check_active "Patent Spec Generator"        "patent-spec-001"
check_active "3D Preview Server"            "preview-image-001"
check_active "ComfyUI Preview Server"       "comfyui-preview-001"
check_active "ComfyUI Text to Image"        "comfyui-t2i-001"
check_active "ComfyUI Text to Video"        "comfyui-t2v-001"
check_active "ComfyUI Image Enhance"        "comfyui-enh-001"

# ── GROUP 2: Fast webhooks — no Ollama ────────────────────────────────────────
log "--- Group 2: Fast webhook tests (no Ollama) ---"

ENC_RESP=$(urlencode "${FAKE_RESPONSE_URL}")

test_fast_webhook "/ai-status" \
  "slack-status" \
  "command=%2Fai-status&text=&channel_id=${TEST_CHANNEL}&user_id=${TEST_USER}&user_name=health-check&response_url=${ENC_RESP}" \
  "KxnpgKyTLMAd4Ygs" \
  30

test_fast_webhook "/ai-diagnose" \
  "slack-diagnose" \
  "command=%2Fai-diagnose&text=&channel_id=${TEST_CHANNEL}&user_id=${TEST_USER}&user_name=health-check&response_url=${ENC_RESP}" \
  "QCrmHKpu1KktTK1M" \
  45

# ── GROUP 3: Ollama-heavy tests — SEQUENTIAL (one at a time) ──────────────────
# Each test waits 8s after completion before starting the next to ensure
# Ollama is free and the model stays loaded (OLLAMA_KEEP_ALIVE=5m).
log "--- Group 3: Ollama command tests (sequential) ---"

# /ai — basic Ollama response (~15-20s)
test_slack_command "/ai" \
  "/ai" \
  "health check: respond with exactly: OK" \
  90

# /news — RSS fetch + Ollama summarise (~30-45s)
test_slack_command "/news" \
  "/news" \
  "AI workflow automation" \
  120

# /pm — Ollama classify + Linear issue creation (~30s)
# Creates a real Linear issue — intentionally labelled as a test
test_slack_command "/pm" \
  "/pm" \
  "HEALTH-CHECK-TEST: automated workflow validation — do not action" \
  120

# /3d — Ollama + OpenSCAD render (~45s)
test_slack_command "/3d" \
  "/3d" \
  "simple test cube 5mm sides" \
  150

# /patent — Ollama doc generation (~60s)
test_slack_command "/patent" \
  "/patent" \
  "automated workflow health monitoring system" \
  150

# ── GROUP 4: ComfyUI — models ready, run inference tests ─────────────────────
log "--- Group 4: ComfyUI (models loaded) ---"

# Give Ollama a longer VRAM cooldown before ComfyUI claims the GPU
if [[ "$MODE" != "--quick" && "$MODE" != "--dry-run" ]]; then
  log "Waiting 15s for Ollama VRAM cooldown before ComfyUI tests..."
  sleep 15
fi

# /image — SDXL Base 1.0 text-to-image (~60-120s on RTX 5070 Ti)
test_direct_json_webhook "/image (ComfyUI Text to Image)" \
  "comfyui-image" \
  "{\"prompt\":\"a simple red sphere on a white background\",\"channel_id\":\"${TEST_CHANNEL}\",\"user_id\":\"${TEST_USER}\"}" \
  "comfyui-t2i-001" \
  240

# /video — AnimateDiff text-to-video (~90-180s)
test_direct_json_webhook "/video (ComfyUI Text to Video)" \
  "comfyui-video" \
  "{\"prompt\":\"a slow zoom toward a red sphere, cinematic\",\"channel_id\":\"${TEST_CHANNEL}\",\"user_id\":\"${TEST_USER}\"}" \
  "comfyui-t2v-001" \
  360

# /enhance — Real-ESRGAN 4x upscale (~30-60s)
# Uses a stable 256×256 public test image
test_direct_json_webhook "/enhance (ComfyUI Image Enhance)" \
  "comfyui-enhance" \
  "{\"image_url\":\"https://picsum.photos/256/256\",\"channel_id\":\"${TEST_CHANNEL}\",\"user_id\":\"${TEST_USER}\"}" \
  "comfyui-enh-001" \
  120

# ── GROUP 5: Council — verify active, skip live trigger ──────────────────────
log "--- Group 5: The Council (active check only) ---"
# The Council requires a real Slack thread and cannot be tested
# without sending a message through the full Slack event flow
mark_skip "The Council deliberation" "Requires live Slack event — verify manually in #the-council"

# ══════════════════════════════════════════════════════════════════════════════
# REPORT
# ══════════════════════════════════════════════════════════════════════════════

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))
TOTAL=$((PASS + FAIL + SKIP + WARN))

log ""
log "=== Results: ${PASS} passed  ${FAIL} failed  ${WARN} warnings  ${SKIP} skipped  (${MINS}m${SECS}s) ==="

# Build block list
LINES_TEXT=""
for line in "${REPORT_LINES[@]}"; do
  LINES_TEXT+="${line}\n"
done

if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
  SUMMARY_ICON=":white_check_mark:"
  SUMMARY_TEXT="${PASS}/${TOTAL} workflows healthy"
elif [[ $FAIL -eq 0 ]]; then
  SUMMARY_ICON=":warning:"
  SUMMARY_TEXT="${PASS} passed, ${WARN} warnings — check details"
else
  SUMMARY_ICON=":x:"
  SUMMARY_TEXT="${FAIL} FAILED — ${PASS} passed, ${WARN} warnings"
fi

# Post report to Slack
python3 << PYEOF
import json, urllib.request

token = "${SLACK_BOT_TOKEN}"
channel = "${REPORT_CHANNEL}"
lines = """${LINES_TEXT}""".strip()

blocks = [
    {
        "type": "header",
        "text": {"type": "plain_text", "text": "Workflow Health Report"}
    },
    {
        "type": "section",
        "fields": [
            {"type": "mrkdwn", "text": f"*Mode:* \`${MODE:-full}\`"},
            {"type": "mrkdwn", "text": f"*Duration:* ${MINS}m${SECS}s"},
            {"type": "mrkdwn", "text": f"*Passed:* ${PASS}"},
            {"type": "mrkdwn", "text": f"*Failed:* ${FAIL}"},
            {"type": "mrkdwn", "text": f"*Warnings:* ${WARN}"},
            {"type": "mrkdwn", "text": f"*Skipped:* ${SKIP}"}
        ]
    },
    {"type": "divider"},
    {
        "type": "section",
        "text": {"type": "mrkdwn", "text": lines[:2800] if lines else "_No results_"}
    },
    {"type": "divider"},
    {
        "type": "context",
        "elements": [
            {"type": "mrkdwn", "text": "${SUMMARY_ICON} *${SUMMARY_TEXT}*"}
        ]
    }
]

payload = json.dumps({"channel": channel, "blocks": blocks}).encode()
req = urllib.request.Request(
    "https://slack.com/api/chat.postMessage",
    data=payload,
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
        if result.get("ok"):
            print("Report posted to Slack")
        else:
            print(f"Slack error: {result.get('error')}")
except Exception as e:
    print(f"Failed to post report: {e}")
PYEOF

# Exit with failure if any tests failed
[[ $FAIL -eq 0 ]] || exit 1
