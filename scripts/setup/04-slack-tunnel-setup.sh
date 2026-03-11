#!/usr/bin/env bash
# =============================================================================
# 04-slack-tunnel-setup.sh
# Sets up a Cloudflare Tunnel (cloudflared) to expose n8n's webhook endpoint
# to the public internet — enabling Slack to send events, slash commands, and
# interactive payloads to your local n8n instance.
#
# Architecture:
#   Slack → cloudflared tunnel → local n8n :5678
#   n8n → Slack Incoming Webhook (no tunnel needed, outbound only)
#
# What this script does:
#   1. Downloads and installs cloudflared (no sudo needed — user-local install)
#   2. Creates a persistent named tunnel (stays stable across restarts)
#   3. Generates tunnel config with n8n as the backend service
#   4. Creates a systemd user service for auto-start
#   5. Writes the tunnel URL to ~/ai-workers/configs/network/tunnel-url.txt
#   6. Prints instructions to update n8n WEBHOOK_URL
#
# Prerequisites:
#   - n8n must be running (docker compose up in ~/n8n/)
#   - A Cloudflare account (free tier at cloudflare.com)
#   - After running, follow prompts to authenticate with Cloudflare
#
# Usage: bash scripts/setup/04-slack-tunnel-setup.sh
# =============================================================================

set -euo pipefail

CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'

info()  { echo -e "  ${CYAN}[INFO]${RESET} $1"; }
pass()  { echo -e "  ${GREEN}[PASS]${RESET} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
step()  { echo -e "\n${BOLD}${CYAN}── $1 ──${RESET}"; }

TUNNEL_NAME="ai-workers-n8n"
N8N_PORT=5678
CLOUDFLARED_BIN="$HOME/.local/bin/cloudflared"
TUNNEL_CONFIG_DIR="$HOME/.cloudflared"
TUNNEL_URL_FILE="$HOME/ai-workers/configs/network/tunnel-url.txt"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ai-workers  ·  Cloudflare Tunnel Setup for n8n        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: Check prerequisites ───────────────────────────────────────────────
step "1. Prerequisites"

# Check n8n is reachable
if curl -s --max-time 3 "http://localhost:${N8N_PORT}/healthz" &>/dev/null; then
    pass "n8n is responding on port ${N8N_PORT}"
elif ss -tlnp 2>/dev/null | grep -q ":${N8N_PORT}"; then
    pass "Port ${N8N_PORT} is listening (n8n may still be starting)"
else
    warn "n8n does not appear to be running on port ${N8N_PORT}."
    warn "The tunnel will be created but won't route traffic until n8n starts."
    info "Start n8n: cd ~/n8n && docker compose up -d"
fi

# ── Step 2: Install cloudflared ───────────────────────────────────────────────
step "2. Installing cloudflared"

mkdir -p "$HOME/.local/bin"

if [[ -f "$CLOUDFLARED_BIN" ]]; then
    CURRENT_VER=$("$CLOUDFLARED_BIN" --version 2>/dev/null | awk '{print $3}' || echo "unknown")
    pass "cloudflared already installed (${CURRENT_VER})"
    info "To update: re-run this script or download from https://github.com/cloudflare/cloudflared/releases"
else
    info "Downloading cloudflared for linux/amd64..."
    LATEST_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    if curl -fsSL --progress-bar "$LATEST_URL" -o "$CLOUDFLARED_BIN"; then
        chmod +x "$CLOUDFLARED_BIN"
        VER=$("$CLOUDFLARED_BIN" --version 2>/dev/null | awk '{print $3}' || echo "installed")
        pass "cloudflared installed: ${CLOUDFLARED_BIN} (${VER})"
    else
        fail "Failed to download cloudflared. Check internet connection."
        exit 1
    fi
fi

# Ensure ~/.local/bin is on PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    warn "~/.local/bin is not in your PATH."
    info "Add to ~/.bashrc or ~/.profile:"
    info '  export PATH="$HOME/.local/bin:$PATH"'
fi

# ── Step 3: Authenticate with Cloudflare ──────────────────────────────────────
step "3. Cloudflare Authentication"

CERT_FILE="$TUNNEL_CONFIG_DIR/cert.pem"
if [[ -f "$CERT_FILE" ]]; then
    pass "Cloudflare credentials found at ${CERT_FILE}"
else
    echo ""
    echo -e "  ${BOLD}You need to authenticate cloudflared with your Cloudflare account.${RESET}"
    echo ""
    echo "  This will open a browser window to authorize the tunnel."
    echo "  If running headlessly, copy the URL shown and open it on another device."
    echo ""
    read -rp "  Press ENTER to start authentication (or Ctrl+C to cancel)..." _

    "$CLOUDFLARED_BIN" tunnel login

    if [[ -f "$CERT_FILE" ]]; then
        pass "Authentication successful. Credentials saved."
    else
        fail "Authentication failed or was cancelled. Re-run this script to try again."
        exit 1
    fi
fi

# ── Step 4: Create the tunnel ─────────────────────────────────────────────────
step "4. Creating Named Tunnel: ${TUNNEL_NAME}"

# Check if tunnel already exists
if "$CLOUDFLARED_BIN" tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
    pass "Tunnel '${TUNNEL_NAME}' already exists"
    TUNNEL_ID=$("$CLOUDFLARED_BIN" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    info "Tunnel ID: ${TUNNEL_ID}"
else
    info "Creating tunnel '${TUNNEL_NAME}'..."
    "$CLOUDFLARED_BIN" tunnel create "$TUNNEL_NAME" 2>&1
    TUNNEL_ID=$("$CLOUDFLARED_BIN" tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    if [[ -n "$TUNNEL_ID" ]]; then
        pass "Tunnel created. ID: ${TUNNEL_ID}"
    else
        fail "Tunnel creation failed."
        exit 1
    fi
fi

# ── Step 5: Write tunnel config ───────────────────────────────────────────────
step "5. Writing Tunnel Config"

TUNNEL_CRED_FILE="$TUNNEL_CONFIG_DIR/${TUNNEL_ID}.json"
TUNNEL_CONFIG_FILE="$TUNNEL_CONFIG_DIR/config.yml"

if [[ ! -f "$TUNNEL_CRED_FILE" ]]; then
    fail "Tunnel credential file not found: ${TUNNEL_CRED_FILE}"
    info "Try re-running: cloudflared tunnel create ${TUNNEL_NAME}"
    exit 1
fi

cat > "$TUNNEL_CONFIG_FILE" << EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${TUNNEL_CRED_FILE}

ingress:
  # n8n webhook endpoint — receives Slack events, slash commands, payloads
  - hostname: ${TUNNEL_NAME}.${TUNNEL_ID:0:8}.workers.dev
    service: http://localhost:${N8N_PORT}

  # Catch-all (required by cloudflared)
  - service: http_status:404
EOF

pass "Tunnel config written to ${TUNNEL_CONFIG_FILE}"

# ── Step 6: Get the tunnel URL ────────────────────────────────────────────────
step "6. Tunnel URL"

# Named tunnels use the pattern: <name>.cfargotunnel.com or custom domain
# For quick-tunnel (no account), use: cloudflared tunnel --url http://localhost:5678
# Named tunnels need a DNS record. Offer both approaches.

echo ""
echo -e "  ${BOLD}Two tunnel options:${RESET}"
echo ""
echo -e "  ${BOLD}Option A: Named tunnel (persistent URL, recommended)${RESET}"
echo "  Requires adding a CNAME DNS record in your Cloudflare dashboard."
echo "  Your tunnel ID: ${TUNNEL_ID}"
echo ""
echo "  To create the DNS route:"
echo "    $CLOUDFLARED_BIN tunnel route dns ${TUNNEL_NAME} n8n.yourdomain.com"
echo "  Then your n8n will be at: https://n8n.yourdomain.com"
echo ""
echo -e "  ${BOLD}Option B: Quick tunnel (temporary URL, good for testing)${RESET}"
echo "  No account or DNS needed — URL changes on each restart."
echo "  Start with: $CLOUDFLARED_BIN tunnel --url http://localhost:${N8N_PORT}"
echo "  The URL will be printed in the output."
echo ""
info "For Slack integration, a persistent URL (Option A or a static quick-tunnel) is strongly recommended."

# ── Step 7: Systemd user service ──────────────────────────────────────────────
step "7. Creating systemd User Service"

mkdir -p "$SYSTEMD_USER_DIR"

cat > "${SYSTEMD_USER_DIR}/cloudflared-n8n.service" << EOF
[Unit]
Description=Cloudflare Tunnel for n8n (ai-workers)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${CLOUDFLARED_BIN} tunnel --config ${TUNNEL_CONFIG_FILE} run ${TUNNEL_NAME}
Restart=on-failure
RestartSec=5s
# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

pass "Systemd user service created: ${SYSTEMD_USER_DIR}/cloudflared-n8n.service"
info "Enable and start:"
info "  systemctl --user daemon-reload"
info "  systemctl --user enable --now cloudflared-n8n"
info "  systemctl --user status cloudflared-n8n"
info "  journalctl --user -u cloudflared-n8n -f"

# Enable lingering so user services start at boot (not just on login)
if loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
    pass "User lingering already enabled (service will start at boot)"
else
    info "Enable user service boot persistence:"
    info "  loginctl enable-linger ${USER}"
fi

# ── Step 8: Update n8n docker-compose ─────────────────────────────────────────
step "8. n8n WEBHOOK_URL Update Required"

N8N_COMPOSE="$HOME/n8n/docker-compose.yml"
echo ""
echo -e "  ${BOLD}${YELLOW}ACTION REQUIRED:${RESET}"
echo "  After the tunnel is running and you have your public URL, update:"
echo ""
echo "    File: ${N8N_COMPOSE}"
echo ""
echo "    Change:  - WEBHOOK_URL=http://localhost:5678/"
echo "    To:      - WEBHOOK_URL=https://YOUR-TUNNEL-URL/"
echo ""
echo "  Then restart n8n:"
echo "    cd ~/n8n && docker compose down && docker compose up -d"
echo ""

# Save placeholder URL file
mkdir -p "$(dirname "$TUNNEL_URL_FILE")"
cat > "$TUNNEL_URL_FILE" << EOF
# Cloudflare Tunnel URL for n8n
# Update this file after tunnel is running and URL is confirmed.
# This file is gitignored (no secrets, but avoids committing env-specific URLs).
#
# Tunnel Name: ${TUNNEL_NAME}
# Tunnel ID:   ${TUNNEL_ID}
#
# WEBHOOK_URL (update in ~/n8n/docker-compose.yml):
WEBHOOK_URL=https://REPLACE-WITH-YOUR-TUNNEL-URL/
EOF

pass "Tunnel URL placeholder written to: ${TUNNEL_URL_FILE}"

# ── Next steps summary ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Next Steps ══${RESET}"
echo ""
echo "  1. Enable tunnel service:"
echo "     systemctl --user daemon-reload"
echo "     systemctl --user enable --now cloudflared-n8n"
echo ""
echo "  2. Get your tunnel URL:"
echo "     Option A: cloudflared tunnel route dns ${TUNNEL_NAME} n8n.yourdomain.com"
echo "     Option B: cloudflared tunnel --url http://localhost:${N8N_PORT}  (temporary)"
echo ""
echo "  3. Update ~/n8n/docker-compose.yml WEBHOOK_URL → your tunnel URL"
echo "     Then: cd ~/n8n && docker compose down && docker compose up -d"
echo ""
echo "  4. Create your Slack App:"
echo "     See: services/n8n/slack-app-setup.md"
echo ""
echo "  5. Test with: curl https://YOUR-TUNNEL-URL/healthz"
echo ""
