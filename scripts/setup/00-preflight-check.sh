#!/usr/bin/env bash
# =============================================================================
# 00-preflight-check.sh
# Hardware and OS compatibility check for the ai-workers environment.
#
# Checks: CPU, RAM, Disk, GPU, NVIDIA driver, CUDA, OS version, kernel.
# Does NOT modify the system. Safe to run at any time.
#
# Output: Colored terminal report + JSON summary at /tmp/preflight-report.json
# Usage:  bash scripts/setup/00-preflight-check.sh
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS="${GREEN}[PASS]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
FAIL="${RED}[FAIL]${RESET}"
INFO="${CYAN}[INFO]${RESET}"

REPORT_FILE="/tmp/preflight-report.json"
ISSUES=()
WARNINGS=()

# ── Helpers ───────────────────────────────────────────────────────────────────
header() { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }
pass()   { echo -e "  ${PASS} $1"; }
warn()   { echo -e "  ${WARN} $1"; WARNINGS+=("$1"); }
fail()   { echo -e "  ${FAIL} $1"; ISSUES+=("$1"); }
info()   { echo -e "  ${INFO} $1"; }

# ── Start ─────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ai-workers  ·  Preflight Compatibility Check       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  Target hardware: Ryzen 9 9950X · RTX 5070 Ti · 64GB DDR5"
echo "  Target OS:       Pop!_OS 24.04 LTS"
echo ""

# ── OS ────────────────────────────────────────────────────────────────────────
header "Operating System"

OS_ID=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VERSION=$(grep "^VERSION_ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)

info "Detected: ${OS_NAME} ${OS_VERSION} (kernel ${KERNEL})"

if [[ "$OS_ID" == "pop" && "$OS_VERSION" == "24.04" ]]; then
    pass "Pop!_OS 24.04 LTS — target OS confirmed"
elif [[ "$OS_ID" == "pop" ]]; then
    warn "Pop!_OS detected but version is ${OS_VERSION}, expected 24.04"
elif [[ "$OS_ID" =~ ^(ubuntu|debian)$ ]]; then
    warn "Ubuntu/Debian base detected (${OS_NAME} ${OS_VERSION}) — scripts assume Pop!_OS but may work"
else
    fail "Unexpected OS: ${OS_NAME} ${OS_VERSION}. Scripts are designed for Pop!_OS 24.04."
fi

# Kernel version check (Pop!_OS ships custom kernels; 6.x required for RTX 5070 Ti)
KERNEL_MAJOR=$(echo "$KERNEL" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL" | cut -d. -f2)
if [[ "$KERNEL_MAJOR" -ge 6 && "$KERNEL_MINOR" -ge 8 ]]; then
    pass "Kernel ${KERNEL} — 6.8+ confirmed (RTX 5070 Ti support available)"
elif [[ "$KERNEL_MAJOR" -ge 6 ]]; then
    warn "Kernel ${KERNEL} — 6.x but < 6.8. RTX 5070 Ti may need a newer kernel."
else
    fail "Kernel ${KERNEL} is too old. RTX 5070 Ti (Blackwell) requires kernel 6.8+."
fi

# ── CPU ───────────────────────────────────────────────────────────────────────
header "CPU"

CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
CPU_THREADS=$(grep -c "^processor" /proc/cpuinfo)

info "Model:   ${CPU_MODEL}"
info "Cores:   ${CPU_CORES} physical / ${CPU_THREADS} logical"

if echo "$CPU_MODEL" | grep -qi "9950X"; then
    pass "Ryzen 9 9950X confirmed"
elif echo "$CPU_MODEL" | grep -qi "Ryzen 9"; then
    warn "Ryzen 9 detected but not 9950X (${CPU_MODEL}). Scripts optimized for 9950X."
elif echo "$CPU_MODEL" | grep -qi "Ryzen"; then
    warn "AMD Ryzen detected (${CPU_MODEL}) but not Ryzen 9 series. Performance may vary."
else
    warn "Non-target CPU detected: ${CPU_MODEL}. Scripts should still work."
fi

if [[ "$CPU_CORES" -ge 16 ]]; then
    pass "${CPU_CORES} cores — sufficient for concurrent AI workloads"
elif [[ "$CPU_CORES" -ge 8 ]]; then
    warn "${CPU_CORES} cores — may bottleneck concurrent multi-agent tasks"
else
    fail "${CPU_CORES} cores — insufficient for target multi-agent workloads"
fi

# ── RAM ───────────────────────────────────────────────────────────────────────
header "Memory"

TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
AVAIL_RAM_GB=$(( AVAIL_RAM_KB / 1024 / 1024 ))

info "Total RAM:     ~${TOTAL_RAM_GB} GB"
info "Available RAM: ~${AVAIL_RAM_GB} GB"

if [[ "$TOTAL_RAM_GB" -ge 60 ]]; then
    pass "${TOTAL_RAM_GB} GB RAM — meets 64 GB target"
elif [[ "$TOTAL_RAM_GB" -ge 32 ]]; then
    warn "${TOTAL_RAM_GB} GB RAM — functional but below 64 GB target. Large models may page to swap."
else
    fail "${TOTAL_RAM_GB} GB RAM — below minimum for comfortable multi-agent operation."
fi

if [[ "$AVAIL_RAM_GB" -lt 8 ]]; then
    warn "Only ~${AVAIL_RAM_GB} GB RAM currently available. Other processes consuming memory."
fi

# Check for ZRAM swap
if grep -q "zram" /proc/swaps 2>/dev/null; then
    ZRAM_SIZE=$(grep zram /proc/swaps | awk '{print $3}' | head -1)
    ZRAM_GB=$(( ${ZRAM_SIZE:-0} / 1024 / 1024 ))
    pass "ZRAM swap active (~${ZRAM_GB} GB) — reduces OOM risk during large model loads"
fi

# ── Disk ──────────────────────────────────────────────────────────────────────
header "Disk"

# Primary NVMe
ROOT_DISK=$(df / | tail -1)
ROOT_USED=$(echo "$ROOT_DISK" | awk '{print $3}')
ROOT_AVAIL=$(echo "$ROOT_DISK" | awk '{print $4}')
ROOT_AVAIL_GB=$(( ROOT_AVAIL / 1024 / 1024 ))
ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')

info "Root filesystem: ${ROOT_DEVICE}"
info "Available on /: ~${ROOT_AVAIL_GB} GB"

if [[ "$ROOT_AVAIL_GB" -ge 200 ]]; then
    pass "${ROOT_AVAIL_GB} GB free on root — ample for models and containers"
elif [[ "$ROOT_AVAIL_GB" -ge 50 ]]; then
    warn "${ROOT_AVAIL_GB} GB free on root — may fill quickly with AI models (llama3.1 = ~5GB, SDXL = ~7GB)"
else
    fail "${ROOT_AVAIL_GB} GB free on root — critically low. Models will fail to download."
fi

# Check NVMe devices
NVME_COUNT=$(ls /dev/nvme*n1 2>/dev/null | wc -l)
if [[ "$NVME_COUNT" -ge 2 ]]; then
    pass "${NVME_COUNT} NVMe devices detected"
    # Show each
    for dev in $(ls /dev/nvme*n1 2>/dev/null); do
        SIZE=$(lsblk -dn -o SIZE "$dev" 2>/dev/null)
        MOUNT=$(lsblk -dn -o MOUNTPOINT "$dev" 2>/dev/null | xargs)
        info "  ${dev}: ${SIZE} ${MOUNT:+(mounted: $MOUNT)}"
    done
elif [[ "$NVME_COUNT" -eq 1 ]]; then
    warn "Only 1 NVMe device detected. Target is 2TB; ensure storage is sufficient."
else
    fail "No NVMe devices detected. System uses spinning disk or unusual layout."
fi

# Check /mnt/shared if present
if mountpoint -q /mnt/shared 2>/dev/null; then
    SHARED_AVAIL=$(df /mnt/shared | tail -1 | awk '{print $4}')
    SHARED_AVAIL_GB=$(( SHARED_AVAIL / 1024 / 1024 ))
    info "Shared mount /mnt/shared: ~${SHARED_AVAIL_GB} GB available"
fi

# ── GPU ───────────────────────────────────────────────────────────────────────
header "GPU & NVIDIA Stack"

# PCI detection
if lspci 2>/dev/null | grep -qi "nvidia"; then
    GPU_INFO=$(lspci 2>/dev/null | grep -i "nvidia" | grep -i "VGA\|3D\|Display" | head -1)
    pass "NVIDIA GPU detected via PCI: ${GPU_INFO}"
else
    fail "No NVIDIA GPU found via lspci. GPU acceleration will not be available."
fi

# nvidia-smi (driver communication)
if nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
    GPU_COMPUTE=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
    pass "nvidia-smi communicating — Driver: ${GPU_DRIVER}"
    info "GPU:    ${GPU_NAME}"
    info "VRAM:   ${GPU_VRAM}"
    info "Compute capability: ${GPU_COMPUTE}"

    # Driver version check (RTX 5070 Ti / Blackwell requires 570+)
    DRIVER_MAJOR=$(echo "$GPU_DRIVER" | cut -d. -f1)
    if [[ "$DRIVER_MAJOR" -ge 570 ]]; then
        pass "Driver ${GPU_DRIVER} — supports RTX 5070 Ti (Blackwell, compute 12.0)"
    elif [[ "$DRIVER_MAJOR" -ge 550 ]]; then
        warn "Driver ${GPU_DRIVER} — RTX 5070 Ti requires 570+. CUDA may not fully enumerate GPU."
    else
        fail "Driver ${GPU_DRIVER} is too old for RTX 5070 Ti. Minimum: 570. Install: sudo apt install nvidia-driver-570"
    fi
else
    fail "nvidia-smi FAILED — driver is not loaded or not communicating with GPU."
    info "RTX 5070 Ti (Blackwell, 2c05) requires driver 570+."
    info "Fix: sudo apt update && sudo apt install nvidia-driver-570 --no-install-recommends"
    info "     Then reboot and re-run this script."
fi

# CUDA toolkit
if command -v nvcc &>/dev/null; then
    CUDA_VER=$(nvcc --version 2>/dev/null | grep "release" | sed 's/.*release //' | cut -d, -f1)
    CUDA_MAJOR=$(echo "$CUDA_VER" | cut -d. -f1)
    CUDA_MINOR=$(echo "$CUDA_VER" | cut -d. -f2)
    info "CUDA toolkit: ${CUDA_VER}"

    # RTX 5070 Ti uses compute 12.0; CUDA 12.x required, 12.4+ recommended
    if [[ "$CUDA_MAJOR" -ge 12 && "$CUDA_MINOR" -ge 4 ]]; then
        pass "CUDA ${CUDA_VER} — fully compatible with RTX 5070 Ti"
    elif [[ "$CUDA_MAJOR" -ge 12 ]]; then
        warn "CUDA ${CUDA_VER} — 12.x present but 12.4+ recommended for RTX 5070 Ti (Blackwell) features"
        info "Upgrade: sudo apt install cuda-toolkit-12-6"
    else
        fail "CUDA ${CUDA_VER} is too old for RTX 5070 Ti. Requires CUDA 12.x."
    fi
else
    warn "nvcc not in PATH. CUDA toolkit may not be installed or not on PATH."
    info "Install: sudo apt install cuda-toolkit-12-6"
fi

# Check if NVIDIA kernel module is loaded
if lsmod 2>/dev/null | grep -q "^nvidia "; then
    pass "NVIDIA kernel module (nvidia) is loaded"
else
    fail "NVIDIA kernel module is NOT loaded. Run: sudo modprobe nvidia"
    info "If modprobe fails, the driver is not installed or not compatible with current kernel."
fi

# ── Virtualization / Container Runtime ────────────────────────────────────────
header "Container Runtime"

if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
    info "Docker binary: ${DOCKER_VER}"

    if docker info &>/dev/null 2>&1; then
        pass "Docker daemon is running"
        # Check for NVIDIA container toolkit
        if docker info 2>/dev/null | grep -qi "nvidia"; then
            pass "NVIDIA Container Toolkit detected in Docker"
        else
            warn "NVIDIA Container Toolkit not visible in Docker. GPU passthrough to containers won't work."
            info "Install: sudo apt install nvidia-container-toolkit && sudo systemctl restart docker"
        fi
    else
        fail "Docker daemon is NOT running. All container-based services (n8n, open-webui, plane) are down."
        info "Fix: sudo systemctl enable --now docker"
        info "     Or check: sudo systemctl status docker"
    fi

    if docker compose version &>/dev/null 2>&1; then
        DC_VER=$(docker compose version 2>/dev/null | awk '{print $NF}')
        pass "Docker Compose v2: ${DC_VER}"
    else
        fail "Docker Compose v2 not found. Required for n8n, open-webui, plane stacks."
        info "Install: sudo apt install docker-compose-plugin"
    fi
else
    fail "Docker not found. Required for n8n, open-webui, portainer, plane, uptime-kuma."
    info "Install: curl -fsSL https://get.docker.com | sh"
fi

# ── Language Runtimes ─────────────────────────────────────────────────────────
header "Language Runtimes"

# Node.js (n8n native needs 18+)
if command -v node &>/dev/null; then
    NODE_VER=$(node --version 2>/dev/null)
    NODE_MAJOR=$(echo "$NODE_VER" | tr -d 'v' | cut -d. -f1)
    info "Node.js: ${NODE_VER}"
    if [[ "$NODE_MAJOR" -ge 20 ]]; then
        pass "Node.js ${NODE_VER} — optimal for n8n"
    elif [[ "$NODE_MAJOR" -ge 18 ]]; then
        pass "Node.js ${NODE_VER} — meets n8n minimum (18 LTS)"
    else
        fail "Node.js ${NODE_VER} is too old for n8n. Requires 18+."
        info "Upgrade: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install nodejs"
    fi
else
    warn "Node.js not found. Required for native n8n install (not needed if running n8n via Docker)."
fi

# Python (ComfyUI, scripts)
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>/dev/null | awk '{print $2}')
    PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
    info "Python: ${PY_VER}"
    if [[ "$PY_MAJOR" -eq 3 && "$PY_MINOR" -ge 11 ]]; then
        pass "Python ${PY_VER} — compatible with PyTorch/CUDA and ComfyUI"
    elif [[ "$PY_MAJOR" -eq 3 && "$PY_MINOR" -ge 10 ]]; then
        warn "Python ${PY_VER} — functional but 3.11+ preferred for ComfyUI and recent PyTorch"
    else
        fail "Python ${PY_VER} — too old. ComfyUI and PyTorch require 3.10+."
    fi
else
    fail "python3 not found. Required for ComfyUI."
fi

# pip
if command -v pip3 &>/dev/null; then
    pass "pip3 available"
else
    warn "pip3 not found. Install: sudo apt install python3-pip"
fi

# ── Core Service Binaries ─────────────────────────────────────────────────────
header "Core Service Binaries"

# Ollama
if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>/dev/null | awk '{print $NF}')
    pass "Ollama: ${OLLAMA_VER}"
    if ss -tlnp 2>/dev/null | grep -q ":11434"; then
        pass "Ollama is running (port 11434 listening)"
    else
        warn "Ollama binary present but port 11434 is not listening. Start: ollama serve"
    fi
else
    warn "Ollama not found. Install: curl -fsSL https://ollama.com/install.sh | sh"
fi

# Git
if command -v git &>/dev/null; then
    GIT_VER=$(git --version 2>/dev/null | awk '{print $3}')
    pass "git: ${GIT_VER}"
else
    fail "git not found. Install: sudo apt install git"
fi

# WireGuard
if command -v wg &>/dev/null; then
    WG_VER=$(wg --version 2>/dev/null | head -1)
    pass "WireGuard tools: ${WG_VER}"
else
    warn "WireGuard tools (wg) not found. Install: sudo apt install wireguard"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Summary ══${RESET}"
echo ""

FAIL_COUNT=${#ISSUES[@]}
WARN_COUNT=${#WARNINGS[@]}

if [[ "$FAIL_COUNT" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All checks passed. Environment is ready.${RESET}"
else
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}${BOLD}${FAIL_COUNT} critical issue(s) found:${RESET}"
        for issue in "${ISSUES[@]}"; do
            echo -e "    ${RED}✗${RESET} $issue"
        done
        echo ""
    fi
    if [[ "$WARN_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}${WARN_COUNT} warning(s):${RESET}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "    ${YELLOW}△${RESET} $warning"
        done
    fi
fi

# ── JSON Report ───────────────────────────────────────────────────────────────
cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "os": "${OS_NAME} ${OS_VERSION}",
  "kernel": "${KERNEL}",
  "cpu": "${CPU_MODEL}",
  "cpu_cores": ${CPU_CORES},
  "ram_gb": ${TOTAL_RAM_GB},
  "critical_issues": $(printf '%s\n' "${ISSUES[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
  "warnings": $(printf '%s\n' "${WARNINGS[@]:-}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
  "pass": $([[ "$FAIL_COUNT" -eq 0 ]] && echo "true" || echo "false")
}
EOF

echo ""
echo -e "  ${INFO} Full report written to: ${BOLD}${REPORT_FILE}${RESET}"
echo ""

# Exit with failure code if critical issues found
exit "$FAIL_COUNT"
