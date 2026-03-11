#!/usr/bin/env bash
# =============================================================================
# 08-slack-create-channels.sh
# Creates all ai-workers Slack channels via the Slack Web API.
# Requires a Slack Bot Token with the `channels:manage` scope.
#
# Channel structure:
#   counsel-*   → AI personality conversation (5 channels)
#   tasks-*     → Direct agent task assignment (5 channels)
#   gen-*       → Generative output feeds (5 channels)
#   ops-*       → Operational/system channels (6 channels)
#
# Usage:
#   bash scripts/setup/08-slack-create-channels.sh <SLACK_BOT_TOKEN>
#
#   Or set env var first:
#   export SLACK_BOT_TOKEN=xoxb-...
#   bash scripts/setup/08-slack-create-channels.sh
#
# Get a bot token: see services/n8n/slack-app-setup.md (Part 3)
# Required scope:  channels:manage (or admin for private channels)
# =============================================================================

set -euo pipefail

CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'

pass()  { echo -e "  ${GREEN}[DONE]${RESET} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
info()  { echo -e "  ${CYAN}[INFO]${RESET} $1"; }
skip()  { echo -e "  ${CYAN}[SKIP]${RESET} $1 (already exists)"; }
header(){ echo -e "\n${BOLD}${CYAN}── $1 ──${RESET}"; }

# ── Token ────────────────────────────────────────────────────────────────────
TOKEN="${1:-${SLACK_BOT_TOKEN:-}}"

if [[ -z "$TOKEN" ]]; then
    echo -e "${RED}Error: No Slack Bot Token provided.${RESET}"
    echo ""
    echo "Usage:"
    echo "  bash $0 xoxb-your-token-here"
    echo "  OR"
    echo "  export SLACK_BOT_TOKEN=xoxb-... && bash $0"
    echo ""
    echo "Get a token by following: services/n8n/slack-app-setup.md (Part 3)"
    echo "Required scope: channels:manage"
    exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ai-workers  ·  Slack Channel Creation                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Check required tools ──────────────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
    fail "curl is required. Install: sudo apt install curl"; exit 1
fi
if ! command -v python3 &>/dev/null; then
    fail "python3 is required for JSON parsing."; exit 1
fi

# ── Slack API helpers ─────────────────────────────────────────────────────────
SLACK_API="https://slack.com/api"
CREATED_CHANNELS=()
SKIPPED_CHANNELS=()
FAILED_CHANNELS=()
CHANNEL_ID_MAP=()   # "name:id" pairs for .env output

create_channel() {
    local name="$1"
    local description="$2"
    local is_private="${3:-false}"

    local response
    response=$(curl -s -X POST "${SLACK_API}/conversations.create" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"${name}\",\"is_private\":${is_private}}" 2>/dev/null)

    local ok
    ok=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ok','false'))" 2>/dev/null || echo "false")
    local error_msg
    error_msg=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null || echo "")
    local channel_id
    channel_id=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('channel',{}).get('id',''))" 2>/dev/null || echo "")

    if [[ "$ok" == "True" || "$ok" == "true" ]]; then
        pass "#${name} (${channel_id})"
        CREATED_CHANNELS+=("$name")
        CHANNEL_ID_MAP+=("${name}:${channel_id}")

        # Set channel description/topic via purpose
        if [[ -n "$description" && -n "$channel_id" ]]; then
            curl -s -X POST "${SLACK_API}/conversations.setPurpose" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{\"channel\":\"${channel_id}\",\"purpose\":\"${description}\"}" \
                > /dev/null 2>&1 || true
        fi
    elif [[ "$error_msg" == "name_taken" ]]; then
        # Channel exists — get its ID for the env file
        local existing_id
        existing_id=$(curl -s "${SLACK_API}/conversations.list?exclude_archived=true&limit=200" \
            -H "Authorization: Bearer ${TOKEN}" 2>/dev/null \
            | python3 -c "
import json,sys
d=json.load(sys.stdin)
channels=d.get('channels',[])
for c in channels:
    if c.get('name')=='${name}':
        print(c.get('id',''))
        break
" 2>/dev/null || echo "")
        skip "#${name}${existing_id:+ (${existing_id})}"
        SKIPPED_CHANNELS+=("$name")
        [[ -n "$existing_id" ]] && CHANNEL_ID_MAP+=("${name}:${existing_id}")
    else
        fail "#${name} — ${error_msg:-unknown error}"
        FAILED_CHANNELS+=("$name")
    fi
}

# ── Verify token ──────────────────────────────────────────────────────────────
header "Verifying Token"
AUTH_TEST=$(curl -s "${SLACK_API}/auth.test" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
AUTH_OK=$(echo "$AUTH_TEST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ok','false'))" 2>/dev/null || echo "false")
WORKSPACE=$(echo "$AUTH_TEST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('team','unknown'))" 2>/dev/null || echo "unknown")
USER_NAME=$(echo "$AUTH_TEST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('user','unknown'))" 2>/dev/null || echo "unknown")

if [[ "$AUTH_OK" != "True" && "$AUTH_OK" != "true" ]]; then
    AUTH_ERR=$(echo "$AUTH_TEST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error',''))" 2>/dev/null || echo "unknown")
    fail "Token authentication failed: ${AUTH_ERR}"
    echo "  Check token and ensure channels:manage scope is granted."
    exit 1
fi
pass "Authenticated as ${USER_NAME} on workspace: ${WORKSPACE}"

# ── counsel-* channels ────────────────────────────────────────────────────────
header "counsel-* (AI Personality Conversation)"

create_channel "counsel-kevin"    "Chat with Kevin — Architecture, system design, and diagrams"
create_channel "counsel-jason"    "Chat with Jason — Code, refactoring, DevOps, and scalability"
create_channel "counsel-scaachi"  "Chat with Scaachi — Marketing, content writing, and copywriting"
create_channel "counsel-christian" "Chat with Christian — Rapid prototyping and quick POCs"
create_channel "counsel-chidi"    "Chat with Chidi — Feasibility analysis, ethics, and trade-offs"

# ── tasks-* channels ──────────────────────────────────────────────────────────
header "tasks-* (Direct Agent Task Assignment)"

create_channel "tasks-kevin"      "Assign structured tasks to Kevin. n8n creates a Linear issue per task."
create_channel "tasks-jason"      "Assign structured tasks to Jason. n8n creates a Linear issue per task."
create_channel "tasks-scaachi"    "Assign structured tasks to Scaachi. n8n creates a Linear issue per task."
create_channel "tasks-christian"  "Assign structured tasks to Christian. n8n creates a Linear issue per task."
create_channel "tasks-chidi"      "Assign structured tasks to Chidi. n8n creates a Linear issue per task."

# ── gen-* channels ────────────────────────────────────────────────────────────
header "gen-* (Generative Output Feeds)"

create_channel "gen-images"       "ComfyUI image generation output. Automated — n8n posts results here."
create_channel "gen-video"        "Video generation output. Automated — n8n posts renders here."
create_channel "gen-architecture" "Kevin's diagrams, Mermaid renders, and architecture documents."
create_channel "gen-code"         "Jason's code outputs, PR summaries, refactor diffs."
create_channel "gen-content"      "Scaachi's written content, marketing copy, and changelogs."

# ── ops-* channels ────────────────────────────────────────────────────────────
header "ops-* (Operational / System)"

create_channel "ops-alerts"       "CRITICAL: Container crashes, GPU overload, service downtime. Netdata + Portainer + Uptime Kuma."
create_channel "ops-reports"      "Daily consolidated summary: tasks completed, agents used, system health."
create_channel "ops-updates"      "New commits, deployments, config changes, version bumps from GitHub."
create_channel "ops-digest"       "Weekly digest: agent activity summary, top outputs, pending tasks."
create_channel "ops-logs"         "Verbose n8n workflow execution logs. High volume — mute if needed."
create_channel "ops-status"       "Hourly service status: Ollama, n8n, Docker, GPU utilization."

# ── Update .env with channel IDs ──────────────────────────────────────────────
header "Updating n8n .env with Channel IDs"

N8N_ENV="$HOME/n8n/.env"
if [[ -f "$N8N_ENV" ]]; then
    # Build the ID section to append
    {
        echo ""
        echo "# Slack Channel IDs — populated by 08-slack-create-channels.sh on $(date)"
    } >> "$N8N_ENV"

    for entry in "${CHANNEL_ID_MAP[@]:-}"; do
        channel_name="${entry%%:*}"
        channel_id="${entry##*:}"
        env_key="SLACK_CHANNEL_$(echo "$channel_name" | tr '[:lower:]-' '[:upper:]_')"
        # Only add if not already present
        if ! grep -q "^${env_key}=" "$N8N_ENV" 2>/dev/null; then
            echo "${env_key}=${channel_id}" >> "$N8N_ENV"
        fi
    done
    pass "Channel IDs written to ${N8N_ENV}"
    info "Restart n8n to pick up new env vars: cd ~/n8n && docker compose restart"
else
    warn "~/n8n/.env not found — channel IDs not saved."
    info "Run 05-remediate-nosudo.sh first to create the .env file."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Summary ══${RESET}"
echo ""
echo -e "  Created:  ${GREEN}${#CREATED_CHANNELS[@]}${RESET} channel(s)"
echo -e "  Skipped:  ${CYAN}${#SKIPPED_CHANNELS[@]}${RESET} (already existed)"
echo -e "  Failed:   ${RED}${#FAILED_CHANNELS[@]}${RESET}"
echo ""

if [[ "${#FAILED_CHANNELS[@]}" -gt 0 ]]; then
    warn "Failed channels: ${FAILED_CHANNELS[*]}"
    info "Common causes: missing channels:manage scope, or token is a user token"
    info "Verify scopes: https://api.slack.com/apps → Your App → OAuth & Permissions"
fi

echo -e "  ${BOLD}Next step: Invite ai-workers bot to all channels${RESET}"
echo "  In Slack: open each channel → Members → Add apps → ai-workers"
echo "  Or run:   /invite @ai-workers  in each channel"
echo ""
