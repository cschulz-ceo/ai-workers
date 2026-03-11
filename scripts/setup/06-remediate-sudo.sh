#!/usr/bin/env bash
# =============================================================================
# 06-remediate-sudo.sh
# Remediates issues that require root/sudo:
#
#   1. Creates NVIDIA device files (nvidia-modprobe) — no reboot required
#   2. Starts and enables Docker daemon
#   3. Installs NVIDIA Container Toolkit (GPU passthrough to Docker)
#   4. Configures Docker runtime to use NVIDIA
#   5. Verifies GPU is accessible inside Docker
#   6. Starts all ai-workers Docker services (n8n, open-webui)
#
# Run as: sudo bash scripts/setup/06-remediate-sudo.sh
# Safe to re-run (idempotent).
# =============================================================================

set -euo pipefail

# Must be root
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run with sudo: sudo bash $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'

info()  { echo -e "  ${CYAN}[INFO]${RESET} $1"; }
pass()  { echo -e "  ${GREEN}[DONE]${RESET} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
step()  { echo -e "\n${BOLD}${CYAN}── $1 ──${RESET}"; }
skip()  { echo -e "  ${CYAN}[SKIP]${RESET} $1"; }

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ai-workers  ·  Sudo Remediation                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

REBOOT_NEEDED=false
CHANGES_MADE=0

# =============================================================================
# 1. NVIDIA device files
# =============================================================================
step "1. NVIDIA Device Files"

if ls /dev/nvidia0 &>/dev/null 2>&1; then
    pass "/dev/nvidia0 already exists"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null \
        | while read -r line; do pass "  GPU: $line"; done
else
    info "NVIDIA kernel modules loaded but device files missing."
    info "Running nvidia-modprobe to create device nodes..."

    if command -v nvidia-modprobe &>/dev/null; then
        nvidia-modprobe -u -c 0 2>&1 && pass "nvidia-modprobe succeeded"
        sleep 1
        if ls /dev/nvidia0 &>/dev/null 2>&1; then
            pass "/dev/nvidia0 created successfully"
            nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null \
                | while read -r line; do pass "  GPU: $line"; done
            CHANGES_MADE=$((CHANGES_MADE + 1))
        else
            warn "/dev/nvidia0 still missing after modprobe."
            # Try udev trigger as fallback
            info "Trying udevadm trigger as fallback..."
            udevadm trigger --action=add --subsystem-match=drm 2>&1 || true
            udevadm settle 2>&1 || true
            if ls /dev/nvidia0 &>/dev/null 2>&1; then
                pass "/dev/nvidia0 created via udev"
                CHANGES_MADE=$((CHANGES_MADE + 1))
            else
                warn "Device files still missing. A reboot will definitively resolve this."
                warn "Run: sudo reboot"
                warn "Then re-run: bash ~/ai-workers/scripts/setup/07-post-reboot-verify.sh"
                REBOOT_NEEDED=true
            fi
        fi
    else
        warn "nvidia-modprobe not found. Installing..."
        apt-get install -y nvidia-modprobe 2>&1 | tail -3
        nvidia-modprobe -u -c 0 2>&1 || true
        CHANGES_MADE=$((CHANGES_MADE + 1))
    fi
fi

# Check driver version (RTX 5070 Ti needs 570+)
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    DRIVER_MAJOR=$(echo "$DRIVER_VER" | cut -d. -f1)
    if [[ "$DRIVER_MAJOR" -ge 570 ]]; then
        pass "NVIDIA driver ${DRIVER_VER} — 570+ confirmed ✓"
    else
        fail "NVIDIA driver ${DRIVER_VER} is below 570. RTX 5070 Ti needs 570+."
        info "Upgrade: apt-get install -y nvidia-driver-580 --no-install-recommends"
        info "Then reboot."
        REBOOT_NEEDED=true
    fi
fi

# =============================================================================
# 2. Docker daemon
# =============================================================================
step "2. Docker Daemon"

if systemctl is-active docker &>/dev/null 2>&1; then
    skip "Docker daemon is already running"
else
    info "Starting Docker daemon..."
    systemctl start docker 2>&1
    sleep 2
    if systemctl is-active docker &>/dev/null 2>&1; then
        pass "Docker daemon started"
        CHANGES_MADE=$((CHANGES_MADE + 1))
    else
        fail "Docker failed to start. Check: sudo journalctl -u docker -n 50"
        systemctl status docker --no-pager -l 2>&1 | tail -15
        exit 1
    fi
fi

if systemctl is-enabled docker &>/dev/null 2>&1; then
    skip "Docker already enabled on boot"
else
    systemctl enable docker 2>&1
    pass "Docker enabled (starts on boot)"
    CHANGES_MADE=$((CHANGES_MADE + 1))
fi

# Ensure current user is in docker group
if groups "$REAL_USER" 2>/dev/null | grep -q "docker"; then
    skip "${REAL_USER} already in docker group"
else
    usermod -aG docker "$REAL_USER"
    pass "Added ${REAL_USER} to docker group (log out/in or run: newgrp docker)"
    CHANGES_MADE=$((CHANGES_MADE + 1))
    warn "Log out and back in (or run 'newgrp docker') for docker group to take effect."
fi

# =============================================================================
# 3. NVIDIA Container Toolkit
# =============================================================================
step "3. NVIDIA Container Toolkit"

if docker info 2>/dev/null | grep -qi "nvidia"; then
    skip "NVIDIA Container Toolkit already active in Docker"
else
    info "Installing NVIDIA Container Toolkit..."

    # Add NVIDIA container toolkit repo
    if [[ ! -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]]; then
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
            | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
            | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
        apt-get update -qq 2>&1
    fi

    apt-get install -y nvidia-container-toolkit 2>&1 | tail -5

    # Configure Docker runtime
    nvidia-ctk runtime configure --runtime=docker 2>&1
    pass "Docker runtime configured for NVIDIA"
    CHANGES_MADE=$((CHANGES_MADE + 1))

    # Restart Docker to pick up new runtime
    info "Restarting Docker to apply NVIDIA runtime..."
    systemctl restart docker 2>&1
    sleep 3
    pass "Docker restarted"

    # Verify GPU in Docker
    info "Testing GPU access in Docker..."
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi 2>/dev/null | grep -q "NVIDIA"; then
        pass "GPU confirmed accessible inside Docker containers ✓"
    else
        warn "GPU test in Docker inconclusive. May need reboot or toolkit restart."
        info "Manual test: docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi"
    fi
fi

# =============================================================================
# 4. Set NVIDIA persistence mode (prevents smi failures after idle)
# =============================================================================
step "4. NVIDIA Persistence Mode"

if nvidia-smi -pm 1 &>/dev/null 2>&1; then
    pass "NVIDIA persistence mode enabled (prevents sleep-state failures)"
    CHANGES_MADE=$((CHANGES_MADE + 1))

    # Create systemd service to re-enable on every boot
    cat > /etc/systemd/system/nvidia-persistence.service << 'EOF'
[Unit]
Description=Enable NVIDIA Persistence Mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable nvidia-persistence.service 2>&1
    pass "nvidia-persistence.service created and enabled"
else
    warn "Could not set persistence mode (nvidia-smi may not be accessible yet)."
fi

# =============================================================================
# 5. Start ai-workers Docker services
# =============================================================================
step "5. Start Docker Services"

start_service() {
    local name="$1"
    local dir="$2"
    local compose_file="${dir}/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        warn "${name}: docker-compose.yml not found at ${dir}"
        return
    fi

    info "Starting ${name}..."
    # Run as the real user to respect file ownership
    if su -c "cd ${dir} && docker compose up -d 2>&1" "$REAL_USER"; then
        sleep 2
        # Verify container is actually up
        CONTAINER_STATUS=$(su -c "cd ${dir} && docker compose ps --format 'table {{.Status}}' 2>/dev/null | tail -1" "$REAL_USER" || echo "unknown")
        if echo "$CONTAINER_STATUS" | grep -qi "Up\|running"; then
            pass "${name} is running"
            CHANGES_MADE=$((CHANGES_MADE + 1))
        else
            warn "${name} may not have started cleanly. Status: ${CONTAINER_STATUS}"
            info "Check: cd ${dir} && docker compose logs --tail=20"
        fi
    else
        fail "${name} failed to start. Check: cd ${dir} && docker compose logs"
    fi
}

start_service "n8n"          "$REAL_HOME/n8n"
start_service "Open WebUI"   "$REAL_HOME/open-webui"

# =============================================================================
# 6. Verify ports are now listening
# =============================================================================
step "6. Port Verification"

sleep 5  # Give containers time to bind ports
EXPECTED_PORTS=(11434 5678 8080)

for port in "${EXPECTED_PORTS[@]}"; do
    if ss -tlnp 2>/dev/null | grep -q ":${port}"; then
        pass "Port ${port} is now LISTENING ✓"
    else
        warn "Port ${port} not yet listening. Service may still be starting."
    fi
done

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}══ Summary ══${RESET}"
echo ""
pass "${CHANGES_MADE} change(s) applied."
echo ""

if $REBOOT_NEEDED; then
    echo -e "  ${YELLOW}${BOLD}△ A reboot is recommended to fully initialize NVIDIA device files.${RESET}"
    echo "    After reboot, run: bash ~/ai-workers/scripts/setup/07-post-reboot-verify.sh"
    echo ""
else
    echo -e "  ${GREEN}${BOLD}No reboot required. Run the post-reboot verify to confirm all services.${RESET}"
    echo "    bash ~/ai-workers/scripts/setup/07-post-reboot-verify.sh"
fi
echo ""

# LAN access info
LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')
echo -e "  ${BOLD}LAN Access (once services are up):${RESET}"
echo "    Ollama:    http://${LAN_IP}:11434"
echo "    n8n:       http://${LAN_IP}:5678"
echo "    Open WebUI: http://${LAN_IP}:8080"
echo ""
