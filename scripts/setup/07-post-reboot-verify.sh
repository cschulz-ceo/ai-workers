#!/usr/bin/env bash
# =============================================================================
# 07-post-reboot-verify.sh
# Post-reboot / post-remediation verification for the ai-workers environment.
# Run this after: a reboot, driver update, or service changes to confirm
# everything is in the expected running state.
#
# Checks all services, GPU, Docker, and LAN accessibility.
# Does NOT modify the system. Safe to run at any time.
# Usage: bash scripts/setup/07-post-reboot-verify.sh
# =============================================================================

set -euo pipefail

CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'

PASS="${GREEN}[PASS]${RESET}"; FAIL="${RED}[FAIL]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"; INFO="${CYAN}[INFO]${RESET}"

ISSUES=(); WARNINGS=()
pass()  { echo -e "  ${PASS} $1"; }
fail()  { echo -e "  ${FAIL} $1"; ISSUES+=("$1"); }
warn()  { echo -e "  ${WARN} $1"; WARNINGS+=("$1"); }
info()  { echo -e "  ${INFO} $1"; }
header(){ echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║    ai-workers  ·  Post-Reboot Verification                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  LAN IP: ${LAN_IP}"
echo ""

# ── NVIDIA ────────────────────────────────────────────────────────────────────
header "NVIDIA GPU"

if ls /dev/nvidia0 &>/dev/null 2>&1; then
    pass "/dev/nvidia0 device file exists"
    if nvidia-smi &>/dev/null 2>&1; then
        GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
        UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader 2>/dev/null | head -1)
        pass "nvidia-smi communicating ✓"
        info "GPU:    ${GPU}"
        info "Driver: ${DRIVER}"
        info "VRAM:   ${VRAM}"
        info "Util:   ${UTIL}"
    else
        fail "nvidia-smi failed despite /dev/nvidia0 existing"
    fi
else
    fail "/dev/nvidia0 missing — run: sudo nvidia-modprobe -u -c 0"
    info "If that fails: sudo reboot"
fi

# ── Docker ────────────────────────────────────────────────────────────────────
header "Docker"

if docker info &>/dev/null 2>&1; then
    pass "Docker daemon running"
    # NVIDIA runtime
    if docker info 2>/dev/null | grep -qi "nvidia"; then
        pass "NVIDIA Container Toolkit active in Docker"
    else
        fail "NVIDIA Container Toolkit not in Docker. Run: sudo bash ~/ai-workers/scripts/setup/06-remediate-sudo.sh"
    fi
else
    fail "Docker daemon not running. Run: sudo systemctl start docker"
fi

# ── Services ──────────────────────────────────────────────────────────────────
header "Container Services"

check_container() {
    local name="$1"; local port="$2"; local dir="$3"
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -qi "$(basename $dir)"; then
        pass "${name} container running"
    elif ss -tlnp 2>/dev/null | grep -q ":${port}"; then
        pass "${name} port ${port} is listening"
    else
        warn "${name} not running. Start: cd ${dir} && docker compose up -d"
    fi
}

check_container "n8n"         5678 "$HOME/n8n"
check_container "Open WebUI"  8080 "$HOME/open-webui"

# Ollama (native, not Docker)
if ss -tlnp 2>/dev/null | grep -q ":11434"; then
    pass "Ollama running (port 11434)"
else
    fail "Ollama not running. Start: systemctl start ollama  OR  ollama serve"
fi

# cloudflared (if set up)
if systemctl --user is-active cloudflared-n8n &>/dev/null 2>&1; then
    pass "cloudflared tunnel service active"
elif pgrep -x cloudflared &>/dev/null 2>&1; then
    pass "cloudflared running (process)"
else
    warn "cloudflared not running. Slack inbound webhooks won't work."
    info "Start: systemctl --user start cloudflared-n8n"
    info "Setup: bash ~/ai-workers/scripts/setup/04-slack-tunnel-setup.sh"
fi

# ── HTTP Reachability ─────────────────────────────────────────────────────────
header "HTTP Endpoint Reachability"

check_http() {
    local name="$1"; local url="$2"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "301" || "$code" == "401" ]]; then
        pass "${name}: ${url} — HTTP ${code} ✓"
    elif [[ "$code" == "000" ]]; then
        fail "${name}: ${url} — no response (service down?)"
    else
        warn "${name}: ${url} — HTTP ${code}"
    fi
}

check_http "Ollama"     "http://localhost:11434"
check_http "n8n"        "http://localhost:5678"
check_http "Open WebUI" "http://localhost:8080"
check_http "n8n (LAN)"  "http://${LAN_IP}:5678"

# ── GPU in Docker test ────────────────────────────────────────────────────────
header "GPU in Docker (quick test)"

if docker info &>/dev/null 2>&1 && ls /dev/nvidia0 &>/dev/null 2>&1; then
    info "Running GPU test container..."
    if docker run --rm --gpus all \
        -e NVIDIA_VISIBLE_DEVICES=all \
        nvidia/cuda:12.0.0-base-ubuntu22.04 \
        nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -q "."; then
        GPU_IN_DOCKER=$(docker run --rm --gpus all \
            nvidia/cuda:12.0.0-base-ubuntu22.04 \
            nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        pass "GPU accessible in Docker: ${GPU_IN_DOCKER} ✓"
    else
        fail "GPU not accessible inside Docker. Check NVIDIA Container Toolkit."
        info "Fix: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
    fi
else
    warn "Skipping Docker GPU test (Docker not running or no GPU device)"
fi

# ── Ollama model check ────────────────────────────────────────────────────────
header "Ollama Models"

if ollama list &>/dev/null 2>&1; then
    MODEL_LIST=$(ollama list 2>/dev/null | tail -n +2)
    if [[ -n "$MODEL_LIST" ]]; then
        pass "Installed models:"
        echo "$MODEL_LIST" | while read -r line; do info "  $line"; done
    else
        warn "No models installed. Run: ollama pull llama3.1"
    fi

    # Check for personality models
    for personality in kevin jason scaachi christian chidi; do
        if ollama list 2>/dev/null | grep -qi "$personality"; then
            pass "Personality model '${personality}' ready"
        else
            info "Personality '${personality}' not yet created (Modelfile in agents/personalities/)"
        fi
    done
else
    warn "Cannot query Ollama models (ollama not running?)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Summary ══${RESET}"
echo ""

FAIL_COUNT=${#ISSUES[@]}
WARN_COUNT=${#WARNINGS[@]}

if [[ "$FAIL_COUNT" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All checks passed — environment is fully operational ✓${RESET}"
    echo ""
    echo -e "  ${BOLD}Ready to:${RESET}"
    echo "    • Open n8n:        http://${LAN_IP}:5678"
    echo "    • Open WebUI:      http://${LAN_IP}:8080"
    echo "    • Set up Slack:    see services/n8n/slack-app-setup.md"
    echo "    • Set up tunnel:   bash scripts/setup/04-slack-tunnel-setup.sh"
else
    [[ "$FAIL_COUNT" -gt 0 ]] && echo -e "  ${RED}${BOLD}${FAIL_COUNT} failure(s):${RESET}" && \
        for i in "${ISSUES[@]}"; do echo -e "    ${RED}✗${RESET} ${i}"; done && echo ""
    [[ "$WARN_COUNT" -gt 0 ]] && echo -e "  ${YELLOW}${BOLD}${WARN_COUNT} warning(s):${RESET}" && \
        for w in "${WARNINGS[@]}"; do echo -e "    ${YELLOW}△${RESET} ${w}"; done
fi
echo ""
