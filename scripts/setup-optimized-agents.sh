#!/bin/bash
# setup-optimized-agents.sh — Create optimized AI agents from available models
# Uses existing models to create optimized agent personalities
# Usage: bash scripts/setup-optimized-agents.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
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

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Setup Optimized AI Agents                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

log "Setting up optimized AI agents from available models..."

# Check if Ollama is running
if ! systemctl is-active --quiet ollama; then
  error "Ollama is not running. Start with: sudo systemctl start ollama"
  exit 1
fi

# Agent configurations
declare -A AGENTS=(
  ["kevin"]="qwen2.5:32b-instruct-q5_K_M|Systems Architect"
  ["jason"]="qwen2.5-coder:32b-instruct-q5_K_M|Full-Stack Engineer"
  ["scaachi"]="llama3.1:70b-instruct-q5_K_M|Marketing Lead"
  ["christian"]="qwen2.5:32b-instruct-q5_K_M|Rapid Prototyper"
  ["chidi"]="qwen2.5:32b-instruct-q5_K_M|Feasibility Researcher"
)

create_agent() {
  local agent_name=$1
  local model_info="${AGENTS[$agent_name]}"
  local base_model=$(echo "$model_info" | cut -d'|' -f1)
  local description=$(echo "$model_info" | cut -d'|' -f2)
  local modelfile_path="/home/biulatech/ai-workers-1/agents/personalities/${agent_name}.Modelfile"
  
  log "Setting up $agent_name ($description)..."
  
  # Check if base model exists
  if ! ollama list | grep -q "$base_model"; then
    error "Base model $base_model not found. Available models:"
    ollama list
    return 1
  fi
  
  # Check if Modelfile exists
  if [[ ! -f "$modelfile_path" ]]; then
    error "Modelfile not found: $modelfile_path"
    return 1
  fi
  
  # Create/update agent model
  log "  Creating $agent_name from $base_model..."
  
  # Backup existing agent if it exists
  if ollama list | grep -q "$agent_name:"; then
    log "  Removing existing $agent_name model..."
    ollama rm "$agent_name" 2>/dev/null || true
  fi
  
  # Create agent from Modelfile
  if ollama create "$agent_name" -f "$modelfile_path"; then
    success "  ✅ $agent_name created successfully"
    
    # Show model size
    local model_info=$(ollama show "$agent_name" 2>/dev/null | head -5 || echo "Info not available")
    log "  Model info: $model_info"
  else
    error "  ❌ Failed to create $agent_name"
    return 1
  fi
}

# Create all agents
log ""
log "Creating optimized agents..."

total_agents=${#AGENTS[@]}
current_agent=0

for agent in "${!AGENTS[@]}"; do
  current_agent=$((current_agent + 1))
  echo -ne "\r[$current_agent/$total_agents] Processing $agent..."
  
  if create_agent "$agent"; then
    echo -ne " ✅"
  else
    echo -ne " ❌"
  fi
done

echo ""

# Verify agents were created
log ""
log "Verifying agents..."

echo ""
echo -e "${BOLD}Available Agents:${RESET}"
for agent in "${!AGENTS[@]}"; do
  if ollama list | grep -q "$agent:"; then
    model_info=$(ollama show "$agent" 2>/dev/null | grep "Model" | head -1 || echo "Size unknown")
    success "$agent: $model_info"
  else
    error "$agent: Not found"
  fi
done

# Apply Ollama configuration
log ""
log "Applying Ollama timeout configuration..."

if [[ -f "/home/biulatech/ai-workers-1/configs/systemd/ollama.service.d/override.conf" ]]; then
  if sudo cp "/home/biulatech/ai-workers-1/configs/systemd/ollama.service.d/override.conf" "/etc/systemd/system/ollama.service.d/override.conf"; then
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    
    # Wait for Ollama to restart
    sleep 5
    
    if systemctl is-active --quiet ollama; then
      success "Ollama configuration applied and service restarted"
    else
      error "Ollama failed to restart after configuration"
    fi
  else
    error "Failed to copy Ollama configuration"
  fi
else
  error "Ollama configuration file not found"
fi

# Test one agent
log ""
log "Testing agent functionality..."

if ollama list | grep -q "kevin:"; then
  log "  Testing kevin agent..."
  if timeout 30 ollama run kevin "Hello, introduce yourself briefly." 2>/dev/null | grep -q .; then
    success "  ✅ Agent test passed"
  else
    warning "  ⚠️  Agent test may have failed - try manual testing"
  fi
else
  warning "  ⚠️  kevin agent not found for testing"
fi

# Show next steps
log ""
success "🎉 Agent setup complete!"
log ""
log "🎯 Next steps:"
log "1. Test your agents in Slack:"
echo "   /ai kevin: Hello, can you introduce yourself?"
echo "   /ai jason: Write a simple Python function"
log ""
log "2. Check system status:"
echo "   /ai-status"
log ""
log "3. For issues:"
echo "   /ai-diagnose"
log ""
log "📚 Documentation available:"
echo "   - USER-GUIDE.md: Meet your AI team"
echo "   - QUICK-START.md: Setup guide"
echo "   - TROUBLESHOOTING.md: Solve issues"
