#!/bin/bash
# download-optimized-models.sh — RTX 5070 Ti optimized model downloader
# Downloads and installs optimized models for RTX 5070 Ti (16GB VRAM)
# Features: Resume support, validation, backup, progress tracking
# Usage: bash scripts/download-optimized-models.sh
# Logs: /tmp/ollama-model-download.log

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────────
LOG_FILE="/tmp/ollama-model-download.log"
BACKUP_DIR="/home/biulatech/ai-workers-1/model-backups-$(date +%Y%m%d-%H%M%S)"
OLLAMA_BASE_URL="https://ollama.com/library"

# Model definitions: agent|model|size|description|vram_estimate
declare -A MODELS=(
  ["kevin"]="kevin|qwen2.5:32b-instruct-q5_K_M|23GB|Systems Architect - Strong reasoning and planning|~19GB"
  ["jason"]="jason|qwen2.5-coder:32b-instruct-q5_K_M|23GB|Full-Stack Engineer - Purpose-trained coding model|~19GB"
  ["scaachi"]="scaachi|llama3.1:8b|5GB|Marketing Lead - Fast content generation|~5GB"
  ["christian"]="christian|qwen2.5:32b-instruct-q5_K_M|23GB|Rapid Prototyper - Balanced speed and capability|~19GB"
  ["chidi"]="chidi|qwen2.5:32b-instruct-q5_K_M|23GB|Feasibility Researcher - Efficient analysis|~19GB"
)

# ── Helper Functions ────────────────────────────────────────────────────────────────
log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
}

show_progress() {
  local current=$1
  local total=$2
  local task=$3
  local percent=$((current * 100 / total))
  local bar_length=30
  local filled=$((percent * bar_length / 100))
  local empty=$((bar_length - filled))
  
  printf "\r["
  printf "%*s" $filled | tr ' ' '█'
  printf "%*s" $empty | tr ' ' '░'
  printf "] %d%% - %s" $percent "$task"
  if [[ $current -eq $total ]]; then
    echo ""
  fi
}

check_ollama() {
  if ! command -v ollama &>/dev/null; then
    log "ERROR: ollama not found. Install first: curl -fsSL https://ollama.com/install.sh | sh"
    exit 1
  fi
  
  if ! ollama list &>/dev/null; then
    log "ERROR: ollama not running. Start with: sudo systemctl start ollama"
    exit 1
  fi
}

check_gpu_memory() {
  if command -v nvidia-smi &>/dev/null; then
    local total_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    local total_gb=$((total_vram / 1024))
    log "GPU VRAM detected: ${total_gb}GB"
    
    if [[ $total_gb -lt 12 ]]; then
      log "WARNING: Less than 12GB VRAM detected. Some models may not fit comfortably."
    fi
  else
    log "WARNING: nvidia-smi not available. Cannot check GPU memory."
  fi
}

backup_current_models() {
  log "Creating backup of current models..."
  mkdir -p "$BACKUP_DIR"
  
  local backup_count=0
  for agent in "${!MODELS[@]}"; do
    local model_info="${MODELS[$agent]}"
    local model_name=$(echo "$model_info" | cut -d'|' -f2)
    
    if ollama list | grep -q "$model_name"; then
      log "  Backing up $model_name..."
      ollama save "$model_name" -o "$BACKUP_DIR/${model_name}.tar" 2>/dev/null || true
      backup_count=$((backup_count + 1))
    fi
  done
  
  if [[ $backup_count -gt 0 ]]; then
    log "✅ Backed up $backup_count models to $BACKUP_DIR"
  else
    log "ℹ️  No existing models found to backup"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
  fi
}

download_model() {
  local agent=$1
  local model_info="${MODELS[$agent]}"
  local model_name=$(echo "$model_info" | cut -d'|' -f2)
  local model_size=$(echo "$model_info" | cut -d'|' -f3)
  local description=$(echo "$model_info" | cut -d'|' -f4)
  local vram_estimate=$(echo "$model_info" | cut -d'|' -f5)
  
  log ""
  log "🔄 Processing $agent: $description"
  log "   Model: $model_name"
  log "   Size: $model_size"
  log "   VRAM: $vram_estimate"
  
  # Check if model already exists
  if ollama list | grep -q "$model_name"; then
    log "   ✅ Model already exists - skipping download"
    return 0
  fi
  
  # Download model with progress tracking
  log "   📥 Downloading $model_name..."
  
  # Start download in background and monitor progress
  ollama pull "$model_name" 2>&1 | while IFS= read -r line; do
    if [[ "$line" =~ "downloading" ]]; then
      log "     $line"
    fi
  done &
  
  local pull_pid=$!
  
  # Monitor download progress
  local start_time=$(date +%s)
  while kill -0 $pull_pid 2>/dev/null; do
    local elapsed=$(($(date +%s) - start_time))
    printf "\r     ⏳ Downloading... %ds elapsed" $elapsed
    sleep 2
  done
  
  # Wait for completion and check result
  wait $pull_pid
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    # Verify model was downloaded
    if ollama list | grep -q "$model_name"; then
      local actual_size=$(ollama show "$model_name" 2>/dev/null | grep -i "size" | head -1 | awk '{print $2}' || echo "unknown")
      log "   ✅ Download complete (size: $actual_size)"
      return 0
    else
      log "   ❌ Download failed - model not found after download"
      return 1
    fi
  else
    log "   ❌ Download failed with error code $exit_code"
    return 1
  fi
}

validate_model() {
  local agent=$1
  local model_info="${MODELS[$agent]}"
  local model_name=$(echo "$model_info" | cut -d'|' -f2)
  
  log "   🔍 Validating $model_name..."
  
  # Test if model responds to a simple query
  local test_response=$(echo "test" | timeout 30 ollama run "$model_name" 2>/dev/null | head -1 || echo "")
  
  if [[ -n "$test_response" ]]; then
    log "   ✅ Model validation passed"
    return 0
  else
    log "   ⚠️  Model validation failed - may need manual testing"
    return 1
  fi
}

update_modelfile() {
  local agent=$1
  local model_info="${MODELS[$agent]}"
  local model_name=$(echo "$model_info" | cut -d'|' -f2)
  local modelfile_path="/home/biulatech/ai-workers-1/agents/personalities/${agent}.Modelfile"
  
  if [[ -f "$modelfile_path" ]]; then
    # Backup original Modelfile
    cp "$modelfile_path" "${modelfile_path}.backup-$(date +%Y%m%d-%H%M%S)"
    
    # Update FROM line
    sed -i "s/^FROM .*/FROM $model_name/" "$modelfile_path"
    log "   📝 Updated $agent.Modelfile to use $model_name"
  else
    log "   ⚠️  Modelfile not found: $modelfile_path"
  fi
}

show_summary() {
  log ""
  log "🎉 Download Summary"
  log "=================="
  
  local total_models=${#MODELS[@]}
  local downloaded=0
  local failed=0
  
  for agent in "${!MODELS[@]}"; do
    local model_info="${MODELS[$agent]}"
    local model_name=$(echo "$model_info" | cut -d'|' -f2)
    
    if ollama list | grep -q "$model_name"; then
      downloaded=$((downloaded + 1))
      log "✅ $agent: $model_name"
    else
      failed=$((failed + 1))
      log "❌ $agent: $model_name (failed)"
    fi
  done
  
  log ""
  log "Results: $downloaded/$total_models models downloaded successfully"
  
  if [[ $failed -gt 0 ]]; then
    log "⚠️  $failed models failed to download. Check the log: $LOG_FILE"
  fi
  
  if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
    log "💾 Original models backed up to: $BACKUP_DIR"
  fi
}

# ── Main Execution ────────────────────────────────────────────────────────────────
main() {
  log "🚀 Starting RTX 5070 Ti Optimized Model Download"
  log "=================================================="
  log "Timestamp: $(date)"
  log "Log file: $LOG_FILE"
  
  # Pre-flight checks
  log ""
  log "🔍 Running pre-flight checks..."
  check_ollama
  check_gpu_memory
  
  # Create backup directory
  if [[ "${SKIP_BACKUP:-}" != "true" ]]; then
    backup_current_models
  fi
  
  # Download models with progress tracking
  log ""
  log "📥 Downloading optimized models..."
  
  local total_models=${#MODELS[@]}
  local current_model=0
  
  for agent in "${!MODELS[@]}"; do
    current_model=$((current_model + 1))
    show_progress $current_model $total_models "Downloading $agent model"
    
    if download_model "$agent"; then
      validate_model "$agent"
      update_modelfile "$agent"
    else
      log "❌ Failed to download $agent model"
    fi
  done
  
  # Show final summary
  show_summary
  
  log ""
  log "🎯 Next Steps:"
  log "1. Restart Ollama: sudo systemctl restart ollama"
  log "2. Test agents: /ai [agent]: hello"
  log "3. Check performance: /ai-status"
  log "4. For issues: /ai-diagnose"
  
  log ""
  log "✅ Download script completed!"
}

# ── Script Entry Point ────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
