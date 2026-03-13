#!/bin/bash
# apply-ollama-config.sh — Apply Ollama timeout and performance fixes
# Updates systemd configuration and restarts Ollama with optimized settings
# Usage: bash scripts/apply-ollama-config.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log() {
  echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} $*"
}

success() {
  echo -e "${GREEN}[SUCCESS]${RESET} $*"
}

warning() {
  echo -e "${YELLOW}[WARNING]${RESET} $*"
}

error() {
  echo -e "${RED}[ERROR]${RESET} $*"
}

# ─── Main Functions ───────────────────────────────────────────────────────────────
check_sudo() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo: sudo bash $0"
    exit 1
  fi
}

backup_current_config() {
  local override_dir="/etc/systemd/system/ollama.service.d"
  local override_file="$override_dir/override.conf"
  
  if [[ -f "$override_file" ]]; then
    local backup_file="$override_file.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$override_file" "$backup_file"
    success "Backed up current config to $backup_file"
  else
    log "No existing override.conf found"
  fi
}

apply_systemd_config() {
  local repo_config="/home/biulatech/ai-workers-1/configs/systemd/ollama.service.d/override.conf"
  local system_config="/etc/systemd/system/ollama.service.d/override.conf"
  local system_dir="/etc/systemd/system/ollama.service.d"
  
  log "Applying Ollama systemd configuration..."
  
  # Create directory if it doesn't exist
  mkdir -p "$system_dir"
  
  # Copy optimized configuration
  if [[ -f "$repo_config" ]]; then
    cp "$repo_config" "$system_config"
    success "Applied optimized Ollama configuration"
  else
    error "Configuration file not found: $repo_config"
    exit 1
  fi
}

reload_systemd() {
  log "Reloading systemd daemon..."
  systemctl daemon-reload
  success "Systemd daemon reloaded"
}

restart_ollama() {
  log "Restarting Ollama service..."
  
  # Check if Ollama is running
  if systemctl is-active --quiet ollama; then
    systemctl restart ollama
    success "Ollama service restarted"
  else
    systemctl start ollama
    success "Ollama service started"
  fi
  
  # Enable Ollama to start on boot
  systemctl enable ollama
  success "Ollama service enabled for auto-start"
}

verify_configuration() {
  log "Verifying Ollama configuration..."
  
  # Wait a moment for service to start
  sleep 3
  
  # Check service status
  if systemctl is-active --quiet ollama; then
    success "Ollama service is running"
  else
    error "Ollama service failed to start"
    return 1
  fi
  
  # Check if configuration is applied
  local env_vars=$(systemctl show ollama -p Environment | tr ' ' '\n' | grep -E "(OLLAMA_REQUEST_TIMEOUT|OLLAMA_LOAD_TIMEOUT)" || true)
  
  if [[ -n "$env_vars" ]]; then
    success "Timeout configuration applied:"
    echo "$env_vars" | while read -r line; do
      echo "  $line"
    done
  else
    warning "Timeout variables not found in service environment"
  fi
  
  # Check if Ollama is listening on correct port
  if ss -tlnp | grep -q ":11434"; then
    success "Ollama is listening on port 11434"
  else
    warning "Ollama may not be listening on expected port"
  fi
}

show_next_steps() {
  log ""
  log "🎯 Next Steps:"
  log "1. Download optimized models:"
  echo "   bash /home/biulatech/ai-workers-1/scripts/download-optimized-models.sh"
  log ""
  log "2. Test the configuration:"
  echo "   curl http://localhost:11434/api/tags"
  log ""
  log "3. Test agent responses:"
  echo "   /ai kevin: Hello, can you introduce yourself?"
  log ""
  log "4. Monitor performance:"
  echo "   /ai-status"
  log ""
  log "📚 For help:"
  echo "   - User Guide: /home/biulatech/ai-workers-1/USER-GUIDE.md"
  echo "   - Troubleshooting: /home/biulatech/ai-workers-1/TROUBLESHOOTING.md"
  echo "   - FAQ: /home/biulatech/ai-workers-1/FAQ.md"
}

# ─── Main Execution ───────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}${CYAN}"
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║     Apply Ollama Configuration & Timeout Fixes           ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
  
  log "Starting Ollama configuration update..."
  
  check_sudo
  backup_current_config
  apply_systemd_config
  reload_systemd
  restart_ollama
  
  if verify_configuration; then
    echo ""
    success "✅ Ollama configuration updated successfully!"
    show_next_steps
  else
    error "❌ Configuration update failed. Check logs with:"
    echo "   journalctl -u ollama -n 50"
    exit 1
  fi
}

# ─── Script Entry Point ───────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
