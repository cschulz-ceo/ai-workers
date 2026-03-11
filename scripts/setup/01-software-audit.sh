#!/usr/bin/env bash
# =============================================================================
# 01-software-audit.sh
# Deep audit of existing software installs, orphaned files, conflicting
# packages, and Docker state for the ai-workers environment.
#
# Checks: Ollama, n8n, Open WebUI, ComfyUI, Plane, NVIDIA packages,
#         Python envs, Docker daemon/containers/volumes/networks,
#         orphaned compose files, security issues in configs.
#
# Does NOT modify the system. Safe to run at any time.
# Output: Colored terminal report + JSON at /tmp/software-audit.json
# Usage:  bash scripts/setup/01-software-audit.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS="${GREEN}[PASS]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
FAIL="${RED}[FAIL]${RESET}"
INFO="${CYAN}[INFO]${RESET}"
NOTE="${BOLD}[NOTE]${RESET}"

REPORT_FILE="/tmp/software-audit.json"
ISSUES=()
WARNINGS=()
NOTES=()

header() { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }
pass()   { echo -e "  ${PASS} $1"; }
warn()   { echo -e "  ${WARN} $1"; WARNINGS+=("$1"); }
fail()   { echo -e "  ${FAIL} $1"; ISSUES+=("$1"); }
info()   { echo -e "  ${INFO} $1"; }
note()   { echo -e "  ${NOTE} $1"; NOTES+=("$1"); }

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ai-workers  ·  Software Audit & Conflict Check    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Docker Daemon ─────────────────────────────────────────────────────────────
header "Docker Daemon"

DOCKER_RUNNING=false
if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
        DOCKER_RUNNING=true
        pass "Docker daemon is running"

        # NVIDIA container toolkit
        if docker info 2>/dev/null | grep -qi "nvidia"; then
            pass "NVIDIA Container Toolkit active in Docker runtime"
        else
            fail "NVIDIA Container Toolkit NOT active. GPU passthrough to containers is broken."
            info "Fix: sudo apt install nvidia-container-toolkit"
            info "     sudo nvidia-ctk runtime configure --runtime=docker"
            info "     sudo systemctl restart docker"
        fi
    else
        fail "Docker daemon is NOT running. All container services (n8n, open-webui, plane) are down."
        info "Fix: sudo systemctl enable --now docker"
    fi
else
    fail "Docker not installed."
fi

# ── Docker Containers ─────────────────────────────────────────────────────────
header "Docker Containers"

if $DOCKER_RUNNING; then
    CONTAINERS=$(docker ps -a --format "{{.Names}}|{{.Status}}|{{.Image}}" 2>/dev/null)
    if [[ -z "$CONTAINERS" ]]; then
        info "No containers found."
    else
        while IFS='|' read -r name status image; do
            if echo "$status" | grep -qi "^Up"; then
                pass "RUNNING: ${name} (${image})"
            elif echo "$status" | grep -qi "Exited (0)"; then
                info "STOPPED (clean exit): ${name}"
            elif echo "$status" | grep -qi "Exited"; then
                warn "CRASHED: ${name} — Status: ${status}"
            else
                info "${name}: ${status}"
            fi
        done <<< "$CONTAINERS"
    fi

    # Orphaned / dangling images
    DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
    if [[ "$DANGLING" -gt 0 ]]; then
        warn "${DANGLING} dangling Docker image(s) consuming disk space."
        info "Clean up: docker image prune"
    else
        pass "No dangling Docker images"
    fi

    # Unused volumes
    UNUSED_VOL=$(docker volume ls -f "dangling=true" -q 2>/dev/null | wc -l)
    if [[ "$UNUSED_VOL" -gt 0 ]]; then
        warn "${UNUSED_VOL} unused Docker volume(s) found."
        docker volume ls -f "dangling=true" --format "  → {{.Name}}" 2>/dev/null | while read -r line; do info "$line"; done
        info "Review and clean: docker volume prune"
    else
        pass "No unused Docker volumes"
    fi

    # Unused networks
    UNUSED_NET=$(docker network ls --filter "type=custom" --format "{{.Name}}" 2>/dev/null | grep -v "bridge\|host\|none" | wc -l)
    if [[ "$UNUSED_NET" -gt 0 ]]; then
        note "${UNUSED_NET} custom Docker network(s) exist. Review if stale."
        docker network ls --filter "type=custom" --format "  → {{.Name}}" 2>/dev/null | while read -r line; do info "$line"; done
    fi
else
    warn "Skipping container audit — Docker daemon not running."
fi

# ── Docker Compose File Audits ────────────────────────────────────────────────
header "Docker Compose Files & Orphan Detection"

COMPOSE_DIRS=("$HOME/n8n" "$HOME/open-webui" "$HOME/plane-data" "$HOME/backups")

for dir in "${COMPOSE_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        COMPOSE_COUNT=$(find "$dir" -maxdepth 2 -name "docker-compose*.yml" -o -name "compose*.yml" 2>/dev/null | wc -l)
        ACTIVE=$(find "$dir" -maxdepth 2 -name "docker-compose.yml" -o -name "compose.yml" 2>/dev/null | wc -l)
        BAK_COUNT=$(find "$dir" -maxdepth 2 -name "*.bak*" -o -name "*.bak[0-9]*" 2>/dev/null | wc -l)

        if [[ "$COMPOSE_COUNT" -gt 0 ]]; then
            info "Found ${COMPOSE_COUNT} compose file(s) in ${dir}"
            find "$dir" -maxdepth 2 \( -name "docker-compose*.yml" -o -name "compose*.yml" \) 2>/dev/null | while read -r f; do
                FNAME=$(basename "$f")
                if [[ "$FNAME" == "docker-compose.yml" || "$FNAME" == "compose.yml" ]]; then
                    info "  [ACTIVE]  $f"
                else
                    warn "  [ORPHAN]  $f — backup/abandoned compose file. Consider removing."
                fi
            done
        fi
    fi
done

# Global search for orphaned compose backups
GLOBAL_BAKS=$(find "$HOME" -maxdepth 3 \( -name "*.bak" -o -name "*.bak[0-9]*" -o -name "*.bak.*" \) -name "*.yml" 2>/dev/null | wc -l)
if [[ "$GLOBAL_BAKS" -gt 0 ]]; then
    warn "${GLOBAL_BAKS} orphaned .bak compose file(s) found across home directory."
    find "$HOME" -maxdepth 3 \( -name "*.bak" -o -name "*.bak[0-9]*" -o -name "*.bak.*" \) -name "*.yml" 2>/dev/null | while read -r f; do
        info "  → $f"
    done
    info "Safe to delete if services are working: rm <file>"
fi

# ── n8n ───────────────────────────────────────────────────────────────────────
header "n8n"

N8N_DIR="$HOME/n8n"
if [[ -d "$N8N_DIR" ]]; then
    pass "n8n directory found: ${N8N_DIR}"

    if [[ -f "$N8N_DIR/docker-compose.yml" ]]; then
        pass "Active docker-compose.yml present"

        # Security: check for hardcoded secrets in compose file
        if grep -q "N8N_ENCRYPTION_KEY" "$N8N_DIR/docker-compose.yml" 2>/dev/null; then
            KEY_VAL=$(grep "N8N_ENCRYPTION_KEY" "$N8N_DIR/docker-compose.yml" | grep -v "#" | head -1 | cut -d= -f2- | xargs)
            if [[ -n "$KEY_VAL" && "$KEY_VAL" != '${' && "$KEY_VAL" != "CHANGE_ME" ]]; then
                fail "SECURITY: N8N_ENCRYPTION_KEY is hardcoded in docker-compose.yml (not in .env file)"
                info "Move to a .env file: echo 'N8N_ENCRYPTION_KEY=${KEY_VAL}' >> ${N8N_DIR}/.env"
                info "Then in compose: - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}"
            fi
        fi

        # Check WEBHOOK_URL — must not be localhost for Slack inbound to work
        if grep -q "WEBHOOK_URL" "$N8N_DIR/docker-compose.yml" 2>/dev/null; then
            WEBHOOK_VAL=$(grep "WEBHOOK_URL" "$N8N_DIR/docker-compose.yml" | grep -v "#" | head -1 | cut -d= -f2- | xargs)
            if echo "$WEBHOOK_VAL" | grep -qiE "localhost|127\.0\.0\.1"; then
                warn "WEBHOOK_URL is set to localhost (${WEBHOOK_VAL})"
                info "For Slack inbound webhooks, update to your ngrok tunnel URL."
                info "See: scripts/setup/04-slack-tunnel-setup.sh"
            fi
        fi

        # n8n data dir
        if [[ -d "$N8N_DIR/n8n_data" ]]; then
            N8N_DATA_SIZE=$(du -sh "$N8N_DIR/n8n_data" 2>/dev/null | cut -f1)
            pass "n8n_data directory present (${N8N_DATA_SIZE})"
        else
            warn "n8n_data directory not found. First run will create it."
        fi
    fi

    # Check if n8n is also installed natively (conflict risk)
    if command -v n8n &>/dev/null; then
        NATIVE_VER=$(n8n --version 2>/dev/null)
        warn "n8n is also installed natively (${NATIVE_VER}) in addition to Docker. Potential port 5678 conflict."
    fi
    if npm list -g n8n --depth=0 &>/dev/null 2>&1; then
        warn "n8n found in global npm packages. If Docker n8n is primary, remove: npm uninstall -g n8n"
    fi
else
    warn "n8n directory not found at ${N8N_DIR}. Run setup before starting n8n."
fi

# ── Open WebUI ────────────────────────────────────────────────────────────────
header "Open WebUI"

OW_DIR="$HOME/open-webui"
if [[ -d "$OW_DIR" ]]; then
    pass "open-webui directory found: ${OW_DIR}"

    if [[ -f "$OW_DIR/docker-compose.yml" ]]; then
        # Port check: compose maps 3000:8080 but architecture expects 8080
        if grep -q "3000:8080" "$OW_DIR/docker-compose.yml" 2>/dev/null; then
            warn "Open WebUI is mapped to port 3000 (not 8080 as documented in architecture)."
            info "Update docker-compose.yml: '- \"8080:8080\"' to match architecture docs."
        fi

        # Security: hardcoded WEBUI_SECRET_KEY
        if grep -q "WEBUI_SECRET_KEY" "$OW_DIR/docker-compose.yml" 2>/dev/null; then
            SECRET_VAL=$(grep "WEBUI_SECRET_KEY" "$OW_DIR/docker-compose.yml" | grep -v "#" | head -1 | cut -d= -f2- | xargs)
            if [[ -n "$SECRET_VAL" && ${#SECRET_VAL} -gt 5 ]]; then
                fail "SECURITY: WEBUI_SECRET_KEY is hardcoded in docker-compose.yml. Move to .env file."
            fi
        fi
    fi
else
    warn "open-webui directory not found at ${OW_DIR}."
fi

# ── ComfyUI ───────────────────────────────────────────────────────────────────
header "ComfyUI"

COMFY_DIR="$HOME/ComfyUI"
if [[ -d "$COMFY_DIR" ]]; then
    pass "ComfyUI directory found: ${COMFY_DIR}"

    COMFY_SIZE=$(du -sh "$COMFY_DIR" 2>/dev/null | cut -f1)
    info "ComfyUI directory size: ${COMFY_SIZE}"

    # Check for virtual env
    if [[ -d "$COMFY_DIR/venv" ]]; then
        pass "ComfyUI Python venv found"
    elif [[ -d "$COMFY_DIR/.venv" ]]; then
        pass "ComfyUI Python .venv found"
    else
        warn "No venv found in ComfyUI directory. May use system Python (conflict risk)."
        info "Recommended: python3 -m venv ${COMFY_DIR}/venv"
    fi

    # Check for models directory
    if [[ -d "$COMFY_DIR/models" ]]; then
        MODEL_COUNT=$(find "$COMFY_DIR/models" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" 2>/dev/null | wc -l)
        MODELS_SIZE=$(du -sh "$COMFY_DIR/models" 2>/dev/null | cut -f1)
        pass "ComfyUI models directory present (${MODELS_SIZE}, ${MODEL_COUNT} model file(s))"
    else
        info "No models directory yet — will be created on first run."
    fi

    # Custom nodes
    if [[ -d "$COMFY_DIR/custom_nodes" ]]; then
        NODE_COUNT=$(find "$COMFY_DIR/custom_nodes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        info "${NODE_COUNT} custom node package(s) installed"
    fi
else
    warn "ComfyUI directory not found at ${COMFY_DIR}."
fi

# ── Ollama ────────────────────────────────────────────────────────────────────
header "Ollama"

if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>/dev/null | awk '{print $NF}')
    pass "Ollama ${OLLAMA_VER} installed"

    # Check for models
    OLLAMA_MODELS_DIR="${HOME}/.ollama/models"
    if [[ -d "$OLLAMA_MODELS_DIR" ]]; then
        MODEL_SIZE=$(du -sh "$OLLAMA_MODELS_DIR" 2>/dev/null | cut -f1)
        MODEL_COUNT=$(find "$OLLAMA_MODELS_DIR/manifests" -type f 2>/dev/null | wc -l)
        pass "Ollama models directory: ${MODEL_SIZE} (${MODEL_COUNT} manifest(s))"
        ollama list 2>/dev/null | tail -n +2 | while read -r line; do
            info "  Model: $line"
        done
    else
        warn "No Ollama models directory found. Run: ollama pull llama3.1"
    fi

    # Check systemd service
    if systemctl is-enabled ollama &>/dev/null 2>&1; then
        pass "Ollama systemd service is enabled"
        if systemctl is-active ollama &>/dev/null 2>&1; then
            pass "Ollama service is active (running)"
        else
            fail "Ollama service is enabled but NOT active. Start: sudo systemctl start ollama"
        fi
    else
        warn "Ollama is not managed by systemd. It may not survive reboots."
        info "Enable: sudo systemctl enable --now ollama"
    fi
else
    warn "Ollama not found in PATH."
fi

# ── Plane ─────────────────────────────────────────────────────────────────────
header "Plane (Project Management)"

PLANE_DIR="$HOME/plane-data"
if [[ -d "$PLANE_DIR" ]]; then
    PLANE_SIZE=$(du -sh "$PLANE_DIR" 2>/dev/null | cut -f1)
    pass "Plane data directory found: ${PLANE_DIR} (${PLANE_SIZE})"

    PLANE_COMPOSE=$(find "$PLANE_DIR" -maxdepth 2 -name "docker-compose*.yml" 2>/dev/null | head -1)
    if [[ -n "$PLANE_COMPOSE" ]]; then
        pass "Plane compose file: ${PLANE_COMPOSE}"
    else
        warn "No docker-compose.yml found in plane-data. Plane may not be configured."
    fi
else
    info "Plane data directory not yet created at ${PLANE_DIR}."
fi

# ── NVIDIA Package Audit ──────────────────────────────────────────────────────
header "NVIDIA Package Audit"

# Collect all installed NVIDIA packages
NVIDIA_PKGS=$(dpkg -l 2>/dev/null | grep -iE "^ii.*(nvidia|cuda|cudnn|nccl|tensorrt)" | awk '{print $2, $3}')

if [[ -n "$NVIDIA_PKGS" ]]; then
    info "Installed NVIDIA/CUDA packages:"
    echo "$NVIDIA_PKGS" | while read -r pkg ver; do
        info "  ${pkg} (${ver})"
    done

    # Check for multiple CUDA versions (conflict risk)
    CUDA_VERSIONS=$(dpkg -l 2>/dev/null | grep -E "^ii.*cuda-toolkit-[0-9]" | awk '{print $2}' | sed 's/cuda-toolkit-//' | sort -u)
    CUDA_COUNT=$(echo "$CUDA_VERSIONS" | grep -c . || true)
    if [[ "$CUDA_COUNT" -gt 1 ]]; then
        warn "Multiple CUDA toolkit versions installed: $(echo $CUDA_VERSIONS | tr '\n' ' ')"
        info "Multiple CUDA versions can coexist but ensure PyTorch uses the correct one."
        info "Check: python3 -c 'import torch; print(torch.version.cuda)'"
    fi

    # Check for NVIDIA driver packages vs current kernel
    DRIVER_PKGS=$(dpkg -l 2>/dev/null | grep -E "^ii.*nvidia-driver-[0-9]" | awk '{print $2}')
    if [[ -n "$DRIVER_PKGS" ]]; then
        for pkg in $DRIVER_PKGS; do
            VER=$(echo "$pkg" | grep -oE "[0-9]+$")
            if [[ "$VER" -lt 570 ]]; then
                fail "Outdated NVIDIA driver package: ${pkg}. RTX 5070 Ti requires 570+."
                info "Install: sudo apt install nvidia-driver-570 --no-install-recommends"
            else
                pass "NVIDIA driver package: ${pkg} (570+ ✓)"
            fi
        done
    else
        warn "No nvidia-driver-NNN package found via dpkg. Driver may be installed via DKMS or runfile."
    fi
else
    warn "No NVIDIA/CUDA packages found via dpkg. GPU stack may not be installed."
fi

# ── Python Environment Audit ──────────────────────────────────────────────────
header "Python Environment Audit"

# Check for multiple Python installs
PY_VERSIONS=$(ls /usr/bin/python* 2>/dev/null | grep -oE "python[0-9]+\.[0-9]+" | sort -u)
if [[ -n "$PY_VERSIONS" ]]; then
    info "System Python versions: $(echo $PY_VERSIONS | tr '\n' ' ')"
fi

# Check for virtual envs that might conflict
VENVS_FOUND=$(find "$HOME" -maxdepth 4 -name "pyvenv.cfg" 2>/dev/null | head -20)
if [[ -n "$VENVS_FOUND" ]]; then
    VENV_COUNT=$(echo "$VENVS_FOUND" | wc -l)
    info "${VENV_COUNT} Python virtual environment(s) found:"
    echo "$VENVS_FOUND" | while read -r cfg; do
        VENV_DIR=$(dirname "$cfg")
        PY_VER=$(grep "version" "$cfg" 2>/dev/null | head -1 | awk '{print $3}')
        info "  ${VENV_DIR} (Python ${PY_VER})"
    done
fi

# Check PyTorch (critical for ComfyUI)
PY_TORCH_VER=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "")
if [[ -n "$PY_TORCH_VER" ]]; then
    pass "PyTorch ${PY_TORCH_VER} installed in system Python"
    TORCH_CUDA=$(python3 -c "import torch; print(torch.version.cuda)" 2>/dev/null || echo "none")
    if [[ "$TORCH_CUDA" != "none" && -n "$TORCH_CUDA" ]]; then
        pass "PyTorch CUDA version: ${TORCH_CUDA}"
    else
        warn "PyTorch installed but CUDA support not detected. ComfyUI will use CPU only."
        info "Install CUDA PyTorch: pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124"
    fi
else
    info "PyTorch not installed in system Python (expected if ComfyUI uses its own venv)."
fi

# ── Conflicting Services on Target Ports ──────────────────────────────────────
header "Service Conflict Quick-Check"

declare -A PORT_SERVICES=(
    [11434]="Ollama"
    [5678]="n8n"
    [8080]="Open WebUI"
    [3000]="Open WebUI (current mapping)"
    [8188]="ComfyUI"
    [9000]="Portainer"
    [19999]="Netdata"
    [3001]="Uptime Kuma"
)

for port in "${!PORT_SERVICES[@]}"; do
    svc="${PORT_SERVICES[$port]}"
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        PROC=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'users:\(\(".*?"' | head -1 | tr -d '"users:((' || echo "unknown")
        pass "Port ${port} (${svc}) — LISTENING"
    else
        info "Port ${port} (${svc}) — not in use"
    fi
done

# ── Systemd Services ──────────────────────────────────────────────────────────
header "Systemd Service State"

SERVICES_TO_CHECK=("ollama" "docker" "wireguard" "wg-quick@wg0" "netdata" "n8n")

for svc in "${SERVICES_TO_CHECK[@]}"; do
    if systemctl list-units --all --type=service 2>/dev/null | grep -q "${svc}.service"; then
        ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "unknown")
        ACTIVE=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        if [[ "$ACTIVE" == "active" ]]; then
            pass "${svc}: running (${ENABLED})"
        elif [[ "$ENABLED" == "enabled" ]]; then
            warn "${svc}: enabled but not running. Check: sudo systemctl status ${svc}"
        else
            info "${svc}: not configured as systemd service yet"
        fi
    else
        info "${svc}: no systemd unit found"
    fi
done

# ── Secrets Exposure Check ────────────────────────────────────────────────────
header "Secrets Exposure Audit"

COMPOSE_FILES=$(find "$HOME" -maxdepth 4 -name "docker-compose.yml" 2>/dev/null)
SECRET_PATTERNS=("SECRET_KEY" "ENCRYPTION_KEY" "PASSWORD" "API_KEY" "TOKEN" "PASSWD")

while IFS= read -r compose_file; do
    for pattern in "${SECRET_PATTERNS[@]}"; do
        MATCHES=$(grep -n "$pattern" "$compose_file" 2>/dev/null | grep -v "^\s*#" | grep -v '\${' | grep -v "CHANGE_ME" || true)
        if [[ -n "$MATCHES" ]]; then
            fail "Hardcoded secret pattern '${pattern}' in ${compose_file}:"
            echo "$MATCHES" | while read -r match; do
                info "  Line: $match"
            done
            info "  Fix: move to .env file and reference as \${VARIABLE_NAME}"
        fi
    done
done <<< "$COMPOSE_FILES"

# Check if any .env files are accidentally tracked (should not be)
if [[ -d "$HOME/ai-workers" ]]; then
    GIT_TRACKED=$(git -C "$HOME/ai-workers" ls-files 2>/dev/null | grep "\.env$" | head -5 || true)
    if [[ -n "$GIT_TRACKED" ]]; then
        fail "SECURITY: .env file(s) are tracked in git repo: ${GIT_TRACKED}"
        info "Remove: git -C ~/ai-workers rm --cached <file> && git commit"
    else
        pass "No .env files tracked in ai-workers git repo"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Summary ══${RESET}"
echo ""

FAIL_COUNT=${#ISSUES[@]}
WARN_COUNT=${#WARNINGS[@]}

if [[ "$FAIL_COUNT" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All checks passed. Software environment looks clean.${RESET}"
else
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}${BOLD}${FAIL_COUNT} critical issue(s):${RESET}"
        for issue in "${ISSUES[@]}"; do
            echo -e "    ${RED}✗${RESET} ${issue}"
        done
        echo ""
    fi
    if [[ "$WARN_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}${WARN_COUNT} warning(s):${RESET}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "    ${YELLOW}△${RESET} ${warning}"
        done
    fi
fi

# JSON output
cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "docker_running": ${DOCKER_RUNNING},
  "critical_issues": $(printf '%s\n' "${ISSUES[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
  "warnings": $(printf '%s\n' "${WARNINGS[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
  "notes": $(printf '%s\n' "${NOTES[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
}
EOF

echo ""
echo -e "  ${INFO} Report saved to: ${BOLD}${REPORT_FILE}${RESET}"
echo ""
exit "$FAIL_COUNT"
