#!/usr/bin/env bash
# =============================================================================
# 02-port-audit.sh
# Audits all ports required by the ai-workers service stack.
# Reports what is currently listening on each port and whether there are
# conflicts with non-ai-workers processes.
#
# Does NOT modify the system. Safe to run at any time.
# Output: Colored terminal report + JSON at /tmp/port-audit.json
# Usage:  bash scripts/setup/02-port-audit.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS="${GREEN}[PASS]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
FAIL="${RED}[FAIL]${RESET}"
INFO="${CYAN}[INFO]${RESET}"

REPORT_FILE="/tmp/port-audit.json"
CONFLICTS=()
AVAILABLE=()
IN_USE_EXPECTED=()

header() { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }
pass()   { echo -e "  ${PASS} $1"; }
warn()   { echo -e "  ${WARN} $1"; }
fail()   { echo -e "  ${FAIL} $1"; CONFLICTS+=("$1"); }
info()   { echo -e "  ${INFO} $1"; }

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ai-workers  ·  Port Conflict Audit                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Port Definitions ──────────────────────────────────────────────────────────
# Format: PORT|SERVICE|EXPECTED_PROCESS_HINT|PROTOCOL|NOTES
declare -a PORT_DEFS=(
    "11434|Ollama|ollama|TCP|AI inference API; must be LAN-accessible"
    "5678|n8n|n8n/docker|TCP|Automation hub; webhook receiver"
    "8080|Open WebUI|docker|TCP|User chat interface to Ollama"
    "3000|Open WebUI (current)|docker|TCP|Current port mapping in docker-compose (conflicts with some tools)"
    "8188|ComfyUI|python/comfyui|TCP|Image generation API"
    "9000|Portainer|docker|TCP|Container management GUI"
    "19999|Netdata|netdata|TCP|System metrics dashboard"
    "3001|Uptime Kuma|docker|TCP|Service uptime monitor"
    "80|Plane HTTP|docker|TCP|Project management (HTTP)"
    "443|Plane HTTPS|docker|TCP|Project management (HTTPS)"
    "51820|WireGuard|wireguard|UDP|VPN ingress — must be open on router if remote access needed"
)

# ── Check function ─────────────────────────────────────────────────────────────
check_port() {
    local port="$1"
    local service="$2"
    local expected_hint="$3"
    local proto="$4"
    local notes="$5"

    local listening=false
    local process_info=""

    if [[ "$proto" == "TCP" ]]; then
        if ss -tlnp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
            listening=true
            process_info=$(ss -tlnp 2>/dev/null | grep -E ":${port}[[:space:]]" | \
                grep -oP 'users:\(\("([^"]+)"' | head -1 | sed 's/users:(("//' | tr -d '"' || echo "unknown")
        fi
    elif [[ "$proto" == "UDP" ]]; then
        if ss -ulnp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
            listening=true
            process_info=$(ss -ulnp 2>/dev/null | grep -E ":${port}[[:space:]]" | \
                grep -oP 'users:\(\("([^"]+)"' | head -1 | sed 's/users:(("//' | tr -d '"' || echo "unknown")
        fi
    fi

    echo -e "\n  ${BOLD}Port ${port}${RESET} · ${service} (${proto})"
    echo -e "  ${INFO} ${notes}"

    if $listening; then
        # Determine if the process is expected or a conflict
        local is_conflict=false
        for hint_word in $(echo "$expected_hint" | tr '/' ' '); do
            if [[ -z "$process_info" || "$process_info" == "unknown" ]] ; then
                # Can't determine process, assume expected if port is right
                break
            fi
            if ! echo "$process_info" | grep -qi "$hint_word" 2>/dev/null; then
                is_conflict=true
            else
                is_conflict=false
                break
            fi
        done

        if $is_conflict && [[ -n "$process_info" ]]; then
            fail "Port ${port} is in use by an UNEXPECTED process: '${process_info}'"
            info "Expected: ${expected_hint}"
            info "Action: Stop the conflicting process or change its port before starting ${service}"
        else
            pass "Port ${port} is LISTENING — process: '${process_info:-expected}'"
            IN_USE_EXPECTED+=("$port:$service")
        fi
    else
        pass "Port ${port} is AVAILABLE (not currently in use)"
        AVAILABLE+=("$port:$service")
    fi
}

# ── Run checks ────────────────────────────────────────────────────────────────
header "Service Port Status"

for def in "${PORT_DEFS[@]}"; do
    IFS='|' read -r port service hint proto notes <<< "$def"
    check_port "$port" "$service" "$hint" "$proto" "$notes"
done

# ── Additional conflict checks ────────────────────────────────────────────────
header "Additional Conflict Detection"

# Port 3000 vs 8080: open-webui maps 3000:8080 in current compose
# If both 3000 and 8080 are listening, check if they're the same container
if ss -tlnp 2>/dev/null | grep -qE ":3000[[:space:]]" && ss -tlnp 2>/dev/null | grep -qE ":8080[[:space:]]"; then
    warn "Both port 3000 and 8080 are in use. If open-webui is on 3000 AND something else is on 8080, update compose mapping."
fi

# Check for common conflicting services
CONFLICT_CHECKS=(
    "apache2|80|Apache web server conflicts with Plane on port 80"
    "nginx|80|Nginx conflicts with Plane on port 80 (unless used as reverse proxy)"
    "postgres|5432|PostgreSQL on default port (may conflict with Plane's internal DB)"
    "mysql|3306|MySQL running (informational — not directly conflicting)"
    "redis|6379|Redis running (informational — Plane uses its own Redis)"
    "grafana|3000|Grafana on 3000 conflicts with Open WebUI current mapping"
    "jupyter|8888|Jupyter on 8888 (informational)"
)

for check in "${CONFLICT_CHECKS[@]}"; do
    IFS='|' read -r svc_name svc_port warning_msg <<< "$check"
    if pgrep -x "$svc_name" &>/dev/null 2>&1 || systemctl is-active "$svc_name" &>/dev/null 2>&1; then
        warn "${warning_msg}"
    fi
done

# ── LAN Bind Check ────────────────────────────────────────────────────────────
header "LAN Accessibility Check"

info "Checking which services bind to all interfaces (0.0.0.0) vs localhost only"

BOUND_ALL=$(ss -tlnp 2>/dev/null | grep "0.0.0.0" | awk '{print $4}' | sort -u)
BOUND_LOCAL=$(ss -tlnp 2>/dev/null | grep "127.0.0.1" | awk '{print $4}' | sort -u)

if [[ -n "$BOUND_ALL" ]]; then
    info "Services bound to ALL interfaces (LAN-accessible):"
    echo "$BOUND_ALL" | while read -r addr; do
        info "  → ${addr}"
    done
fi

if [[ -n "$BOUND_LOCAL" ]]; then
    info "Services bound to LOCALHOST only (not LAN-accessible):"
    echo "$BOUND_LOCAL" | while read -r addr; do
        PORT=$(echo "$addr" | cut -d: -f2)
        # Flag ai-workers services that should be LAN-accessible
        case "$PORT" in
            11434|5678|8080|3000|8188)
                warn "Port ${PORT} is bound to localhost — not LAN-accessible. Check service bind config."
                ;;
            *)
                info "  → ${addr}"
                ;;
        esac
    done
fi

# ── Firewall check ────────────────────────────────────────────────────────────
header "Firewall Status"

if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    info "UFW status: ${UFW_STATUS}"

    if echo "$UFW_STATUS" | grep -qi "active"; then
        warn "UFW firewall is active. LAN access to services may be blocked."
        info "For LAN-only access, allow from your LAN subnet:"
        info "  sudo ufw allow from 192.168.0.0/24 to any port 11434  # Ollama"
        info "  sudo ufw allow from 192.168.0.0/24 to any port 5678   # n8n"
        info "  sudo ufw allow from 192.168.0.0/24 to any port 8080   # Open WebUI"
        info "  (Adjust subnet to match your LAN)"
        info "  Or disable for home lab: sudo ufw disable"

        ufw status numbered 2>/dev/null | grep -v "^Status" | head -20 | while read -r line; do
            info "  $line"
        done
    else
        pass "UFW is inactive — no firewall blocking LAN access"
    fi
else
    info "UFW not found — checking iptables..."
    if iptables -L INPUT -n 2>/dev/null | grep -q "DROP\|REJECT"; then
        warn "iptables has DROP/REJECT rules. Verify LAN traffic is permitted."
    else
        pass "No restrictive iptables rules detected"
    fi
fi

# ── WireGuard VPN Port ────────────────────────────────────────────────────────
header "WireGuard VPN Readiness"

WG_PORT=51820
if ss -ulnp 2>/dev/null | grep -q ":${WG_PORT}"; then
    pass "WireGuard is listening on UDP ${WG_PORT}"
elif command -v wg &>/dev/null; then
    info "WireGuard tools installed but not currently listening on UDP ${WG_PORT}."
    info "Start: sudo wg-quick up wg0"
    info "Enable on boot: sudo systemctl enable --now wg-quick@wg0"
else
    warn "WireGuard not installed. Install: sudo apt install wireguard"
fi

LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')
info "Detected LAN IP: ${LAN_IP}"
info "Router must port-forward UDP ${WG_PORT} → ${LAN_IP} for remote VPN access."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Port Audit Summary ══${RESET}"
echo ""
echo -e "  Available (not in use): ${#AVAILABLE[@]} port(s)"
echo -e "  In use (expected):      ${#IN_USE_EXPECTED[@]} port(s)"
echo -e "  Conflicts:              ${#CONFLICTS[@]} port(s)"
echo ""

if [[ "${#CONFLICTS[@]}" -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}Conflicts to resolve:${RESET}"
    for c in "${CONFLICTS[@]}"; do
        echo -e "    ${RED}✗${RESET} ${c}"
    done
fi

# JSON output
cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "lan_ip": "${LAN_IP:-unknown}",
  "conflicts": $(printf '%s\n' "${CONFLICTS[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
  "available_ports": $(printf '%s\n' "${AVAILABLE[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
  "in_use_expected": $(printf '%s\n' "${IN_USE_EXPECTED[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
}
EOF

echo ""
echo -e "  ${INFO} Report saved to: ${BOLD}${REPORT_FILE}${RESET}"
echo ""
exit "${#CONFLICTS[@]}"
