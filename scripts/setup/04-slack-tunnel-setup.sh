#!/usr/bin/env bash
# =============================================================================
# 04-slack-tunnel-setup.sh
# Sets up an ngrok tunnel to expose n8n's webhook endpoint to the internet,
# enabling Slack to send events, slash commands, and payloads to local n8n.
#
# Architecture:
#   Slack → ngrok tunnel → local n8n :5678
#   n8n → Slack Incoming Webhook (outbound only — no tunnel needed)
#
# What this script does:
#   1. Downloads and installs ngrok (no sudo needed — user-local install)
#   2. Configures authtoken from NGROK_AUTHTOKEN env var or ~/n8n/.env
#   3. Optionally configures a static domain (free account gives you one)
#   4. Creates a systemd user service for auto-start on login
#   5. Writes the tunnel URL to ~/ai-workers/configs/network/tunnel-url.txt
#   6. Prints instructions to update n8n WEBHOOK_URL
#
# Prerequisites:
#   - Free ngrok account at https://dashboard.ngrok.com/signup
#   - Your authtoken from https://dashboard.ngrok.com/get-started/your-authtoken
#   - n8n should be running (docker compose up in ~/n8n/) before starting tunnel
#
# Usage:
#   NGROK_AUTHTOKEN=<your_token> bash scripts/setup/04-slack-tunnel-setup.sh
#   -- or --
#   Add NGROK_AUTHTOKEN=<token> to ~/n8n/.env, then run without env var
#   -- or --
#   bash scripts/setup/04-slack-tunnel-setup.sh   (will prompt for token)
# =============================================================================

set -euo pipefail

CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'

info()  { echo -e "  ${CYAN}[INFO]${RESET} $1"; }
pass()  { echo -e "  ${GREEN}[PASS]${RESET} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
step()  { echo -e "\n${BOLD}${CYAN}── $1 ──${RESET}"; }

N8N_PORT=5678
NGROK_BIN="$HOME/.local/bin/ngrok"
NGROK_CONFIG_DIR="$HOME/.config/ngrok"
TUNNEL_URL_FILE="$HOME/ai-workers/configs/network/tunnel-url.txt"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
N8N_ENV_FILE="$HOME/n8n/.env"

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ai-workers  ·  ngrok Tunnel Setup for n8n          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: Check prerequisites ───────────────────────────────────────────────
step "1. Prerequisites"

if curl -s --max-time 3 "http://localhost:${N8N_PORT}/healthz" &>/dev/null; then
    pass "n8n is responding on port ${N8N_PORT}"
elif ss -tlnp 2>/dev/null | grep -q ":${N8N_PORT}"; then
    pass "Port ${N8N_PORT} is listening (n8n may still be starting)"
else
    warn "n8n does not appear to be running on port ${N8N_PORT}."
    warn "Start n8n first: cd ~/n8n && docker compose up -d"
    warn "Continuing anyway — tunnel will be created but won't route until n8n starts."
fi

# ── Step 2: Install ngrok ─────────────────────────────────────────────────────
step "2. Installing ngrok"

mkdir -p "$HOME/.local/bin"

if [[ -f "$NGROK_BIN" ]]; then
    CURRENT_VER=$("$NGROK_BIN" version 2>/dev/null | head -1 || echo "unknown")
    pass "ngrok already installed: ${CURRENT_VER}"
else
    info "Downloading ngrok for linux/amd64..."
    NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"
    TMP_DIR=$(mktemp -d)
    if curl -fsSL --progress-bar "$NGROK_URL" | tar xz -C "$TMP_DIR"; then
        mv "$TMP_DIR/ngrok" "$NGROK_BIN"
        chmod +x "$NGROK_BIN"
        rm -rf "$TMP_DIR"
        VER=$("$NGROK_BIN" version 2>/dev/null | head -1 || echo "installed")
        pass "ngrok installed: ${NGROK_BIN} (${VER})"
    else
        fail "Failed to download ngrok. Check internet connection."
        fail "Manual install: https://ngrok.com/download"
        exit 1
    fi
fi

# Ensure ~/.local/bin is on PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    warn "~/.local/bin is not in your PATH."
    info "Add to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ── Step 3: Configure authtoken ───────────────────────────────────────────────
step "3. ngrok Authtoken"

# Source authtoken from environment, n8n .env file, or existing ngrok config
AUTHTOKEN="${NGROK_AUTHTOKEN:-}"

if [[ -z "$AUTHTOKEN" ]] && [[ -f "$N8N_ENV_FILE" ]]; then
    AUTHTOKEN=$(grep -E "^NGROK_AUTHTOKEN=" "$N8N_ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi

if [[ -z "$AUTHTOKEN" ]]; then
    # Check if ngrok already has a config with a token
    if "$NGROK_BIN" config check &>/dev/null 2>&1; then
        pass "ngrok config already present — assuming token is configured"
        AUTHTOKEN="already_configured"
    fi
fi

if [[ -z "$AUTHTOKEN" ]]; then
    echo ""
    echo -e "  ${BOLD}No authtoken found. Get yours from:${RESET}"
    echo "  https://dashboard.ngrok.com/get-started/your-authtoken"
    echo ""
    read -rsp "  Paste your ngrok authtoken (input hidden): " AUTHTOKEN
    echo ""
    if [[ -z "$AUTHTOKEN" ]]; then
        fail "No authtoken provided. Re-run with NGROK_AUTHTOKEN=<token> or paste when prompted."
        exit 1
    fi
fi

if [[ "$AUTHTOKEN" != "already_configured" ]]; then
    "$NGROK_BIN" config add-authtoken "$AUTHTOKEN" 2>&1
    pass "ngrok authtoken configured"

    # Save to n8n .env for future runs (if file exists)
    if [[ -f "$N8N_ENV_FILE" ]]; then
        if grep -q "^NGROK_AUTHTOKEN=" "$N8N_ENV_FILE"; then
            sed -i "s|^NGROK_AUTHTOKEN=.*|NGROK_AUTHTOKEN=${AUTHTOKEN}|" "$N8N_ENV_FILE"
        else
            echo "NGROK_AUTHTOKEN=${AUTHTOKEN}" >> "$N8N_ENV_FILE"
        fi
        pass "Authtoken saved to ${N8N_ENV_FILE}"
    fi
fi

# ── Step 4: Static domain (recommended) ──────────────────────────────────────
step "4. Static Domain Configuration"

STATIC_DOMAIN="${NGROK_STATIC_DOMAIN:-}"

if [[ -z "$STATIC_DOMAIN" ]] && [[ -f "$N8N_ENV_FILE" ]]; then
    STATIC_DOMAIN=$(grep -E "^NGROK_STATIC_DOMAIN=" "$N8N_ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi

if [[ -z "$STATIC_DOMAIN" ]]; then
    echo ""
    echo -e "  ${BOLD}Optional: Static domain (free account includes one)${RESET}"
    echo "  Find yours at: https://dashboard.ngrok.com/cloud-edge/domains"
    echo "  It looks like: abc123xyz.ngrok-free.app"
    echo "  (Press ENTER to skip and use a dynamic URL instead)"
    echo ""
    read -rp "  Your static domain (or press ENTER to skip): " STATIC_DOMAIN
fi

if [[ -n "$STATIC_DOMAIN" ]]; then
    pass "Static domain configured: ${STATIC_DOMAIN}"
    TUNNEL_URL="https://${STATIC_DOMAIN}"

    # Save to n8n .env
    if [[ -f "$N8N_ENV_FILE" ]]; then
        if grep -q "^NGROK_STATIC_DOMAIN=" "$N8N_ENV_FILE"; then
            sed -i "s|^NGROK_STATIC_DOMAIN=.*|NGROK_STATIC_DOMAIN=${STATIC_DOMAIN}|" "$N8N_ENV_FILE"
        else
            echo "NGROK_STATIC_DOMAIN=${STATIC_DOMAIN}" >> "$N8N_ENV_FILE"
        fi
        # Also update WEBHOOK_URL
        if grep -q "^WEBHOOK_URL=" "$N8N_ENV_FILE"; then
            sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=${TUNNEL_URL}/|" "$N8N_ENV_FILE"
            pass "WEBHOOK_URL updated in ${N8N_ENV_FILE}"
        fi
    fi

    NGROK_START_ARGS="http --domain=${STATIC_DOMAIN} ${N8N_PORT}"
else
    warn "No static domain set. URL will change on every restart."
    warn "After starting, update WEBHOOK_URL in ~/n8n/.env and restart n8n."
    TUNNEL_URL="https://DYNAMIC-URL-SEE-NGROK-OUTPUT"
    NGROK_START_ARGS="http ${N8N_PORT}"
fi

# ── Step 5: Write systemd user service ────────────────────────────────────────
step "5. Creating systemd User Service"

mkdir -p "$SYSTEMD_USER_DIR"

cat > "${SYSTEMD_USER_DIR}/ngrok-n8n.service" << EOF
[Unit]
Description=ngrok Tunnel for n8n (ai-workers)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${NGROK_BIN} ${NGROK_START_ARGS} --log=stdout
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal
# Environment (ngrok reads token from ~/.config/ngrok/ngrok.yml)
Environment=HOME=${HOME}

[Install]
WantedBy=default.target
EOF

pass "systemd user service created: ${SYSTEMD_USER_DIR}/ngrok-n8n.service"
info "Enable and start:"
info "  systemctl --user daemon-reload"
info "  systemctl --user enable --now ngrok-n8n"
info "  systemctl --user status ngrok-n8n"
info "  journalctl --user -u ngrok-n8n -f"

# Enable lingering so service starts at boot, not just on login
if loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
    pass "User lingering already enabled (service will start at boot)"
else
    info "Enable boot persistence (requires sudo):"
    info "  sudo loginctl enable-linger ${USER}"
fi

# ── Step 6: Write tunnel URL file ─────────────────────────────────────────────
step "6. Tunnel URL File"

mkdir -p "$(dirname "$TUNNEL_URL_FILE")"
cat > "$TUNNEL_URL_FILE" << EOF
# ngrok Tunnel URL for n8n (ai-workers)
# Update WEBHOOK_URL below after tunnel is confirmed running.
# This file is gitignored — do not commit.
#
# Static domain: ${STATIC_DOMAIN:-none configured — dynamic URL}
#
# WEBHOOK_URL (update in ~/n8n/.env):
WEBHOOK_URL=${TUNNEL_URL}/
EOF

pass "Tunnel URL file written to: ${TUNNEL_URL_FILE}"

# ── Step 7: Quick-start option ────────────────────────────────────────────────
step "7. Quick Start (foreground test)"

echo ""
echo -e "  To test the tunnel interactively (Ctrl+C to stop):"
echo ""
if [[ -n "$STATIC_DOMAIN" ]]; then
    echo "    ${NGROK_BIN} http --domain=${STATIC_DOMAIN} ${N8N_PORT}"
else
    echo "    ${NGROK_BIN} http ${N8N_PORT}"
fi
echo ""
echo -e "  ${BOLD}ngrok web inspector (local):${RESET}  http://127.0.0.1:4040"
echo ""

# ── Next steps summary ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Next Steps ══${RESET}"
echo ""
echo "  1. Enable tunnel service:"
echo "     systemctl --user daemon-reload"
echo "     systemctl --user enable --now ngrok-n8n"
echo ""
echo "  2. Confirm tunnel is running:"
echo "     curl http://127.0.0.1:4040/api/tunnels | python3 -m json.tool"
echo ""
if [[ -z "$STATIC_DOMAIN" ]]; then
    echo "  3. Copy the Forwarding URL from ngrok output"
    echo "     Update WEBHOOK_URL in ~/n8n/.env → restart n8n"
    echo "     cd ~/n8n && docker compose down && docker compose up -d"
    echo ""
else
    echo "  3. WEBHOOK_URL already set to: ${TUNNEL_URL}/"
    echo "     Restart n8n to apply: cd ~/n8n && docker compose down && docker compose up -d"
    echo ""
fi
echo "  4. Create your Slack App:"
echo "     See: services/n8n/slack-app-setup.md"
echo ""
echo "  5. Test end-to-end:"
echo "     curl ${TUNNEL_URL}/healthz"
echo ""
