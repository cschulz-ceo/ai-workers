#!/bin/bash
# verify-implementation.sh — Verify documentation and model optimization implementation
# Checks that all files were created and configurations are applied correctly
# Usage: bash scripts/verify-implementation.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "  ${GREEN}✅${RESET} $1"; }
fail() { echo -e "  ${RED}❌${RESET} $1"; }
warn() { echo -e "  ${YELLOW}⚠️${RESET} $1"; }
info() { echo -e "  ${CYAN}ℹ️${RESET} $1"; }

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Verify Implementation: Documentation & Models       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

TOTAL_CHECKS=0
PASSED_CHECKS=0

check() {
  local description="$1"
  local test_command="$2"
  
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  
  if eval "$test_command"; then
    pass "$description"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    fail "$description"
  fi
}

echo -e "\n${BOLD}📚 Documentation Files${RESET}"

check "USER-GUIDE.md exists" "[[ -f '/home/biulatech/ai-workers-1/USER-GUIDE.md' ]]"
check "QUICK-START.md exists" "[[ -f '/home/biulatech/ai-workers-1/QUICK-START.md' ]]"
check "TROUBLESHOOTING.md exists" "[[ -f '/home/biulatech/ai-workers-1/TROUBLESHOOTING.md' ]]"
check "FAQ.md exists" "[[ -f '/home/biulatech/ai-workers-1/FAQ.md' ]]"
check "IMPLEMENTATION-SUMMARY.md exists" "[[ -f '/home/biulatech/ai-workers-1/IMPLEMENTATION-SUMMARY.md' ]]"

echo -e "\n${BOLD}🔧 Scripts Created${RESET}"

check "download-optimized-models.sh exists and executable" "[[ -x '/home/biulatech/ai-workers-1/scripts/download-optimized-models.sh' ]]"
check "apply-ollama-config.sh exists and executable" "[[ -x '/home/biulatech/ai-workers-1/scripts/apply-ollama-config.sh' ]]"
check "verify-implementation.sh exists and executable" "[[ -x '/home/biulatech/ai-workers-1/scripts/verify-implementation.sh' ]]"

echo -e "\n${BOLD}📄 Updated Files${RESET}"

check "README.md updated with user-friendly content" "grep -q 'Your AI-powered team' '/home/biulatech/ai-workers-1/README.md'"
check "Agent Modelfiles updated" "grep -q 'deepseek-coder-v2-lite' '/home/biulatech/ai-workers-1/agents/personalities/jason.Modelfile'"
check "Ollama config updated" "grep -q 'OLLAMA_REQUEST_TIMEOUT=600s' '/home/biulatech/ai-workers-1/configs/systemd/ollama.service.d/override.conf'"

echo -e "\n${BOLD}🤖 Agent Model Updates${RESET}"

check "Jason Modelfile updated to deepseek-coder-v2-lite" "grep -q 'FROM deepseek-coder-v2-lite:16b-q5_K_M' '/home/biulatech/ai-workers-1/agents/personalities/jason.Modelfile'"
check "Scaachi Modelfile updated to llama3.1:8b" "grep -q 'FROM llama3.1:8b-q4_K_M' '/home/biulatech/ai-workers-1/agents/personalities/scaachi.Modelfile'"
check "Christian Modelfile updated to qwen2.5:14b" "grep -q 'FROM qwen2.5:14b-q5_K_M' '/home/biulatech/ai-workers-1/agents/personalities/christian.Modelfile'"
check "Chidi Modelfile updated to mistral-small" "grep -q 'FROM mistral-small:22b-iq2_m' '/home/biulatech/ai-workers-1/agents/personalities/chidi.Modelfile'"
check "Kevin Modelfile maintains qwen2.5:32b" "grep -q 'FROM qwen2.5:32b' '/home/biulatech/ai-workers-1/agents/personalities/kevin.Modelfile'"

echo -e "\n${BOLD}⚙️ System Configuration${RESET}"

if command -v ollama &>/dev/null; then
  check "Ollama command available" "true"
  
  if systemctl is-active --quiet ollama 2>/dev/null; then
    check "Ollama service running" "true"
    
    if ollama list &>/dev/null; then
      check "Ollama responding to commands" "true"
      
      # Check if timeout config is applied
      if systemctl show ollama -p Environment 2>/dev/null | grep -q "OLLAMA_REQUEST_TIMEOUT=600s"; then
        check "Ollama timeout configuration applied" "true"
      else
        warn "Ollama timeout configuration may not be applied yet (run apply-ollama-config.sh)"
      fi
    else
      warn "Ollama installed but not responding (may need restart)"
    fi
  else
    warn "Ollama service not running (start with: sudo systemctl start ollama)"
  fi
else
  warn "Ollama not installed or not in PATH"
fi

echo -e "\n${BOLD}📊 Implementation Summary${RESET}"

if [[ $PASSED_CHECKS -eq $TOTAL_CHECKS ]]; then
  echo -e "\n${GREEN}${BOLD}🎉 All checks passed! Implementation is complete.${RESET}"
  echo -e "\n${BOLD}Next steps:${RESET}"
  echo "1. Apply Ollama configuration:"
  echo "   sudo bash /home/biulatech/ai-workers-1/scripts/apply-ollama-config.sh"
  echo ""
  echo "2. Download optimized models:"
  echo "   bash /home/biulatech/ai-workers-1/scripts/download-optimized-models.sh"
  echo ""
  echo "3. Test the system:"
  echo "   /ai kevin: Hello, can you introduce yourself?"
  echo ""
  echo "4. Read the new documentation:"
  echo "   - User Guide: /home/biulatech/ai-workers-1/USER-GUIDE.md"
  echo "   - Quick Start: /home/biulatech/ai-workers-1/QUICK-START.md"
else
  echo -e "\n${YELLOW}${BOLD}⚠️  Some checks failed. Review the issues above.${RESET}"
  echo -e "\n${BOLD}Common fixes:${RESET}"
  echo "- Apply Ollama config: sudo bash scripts/apply-ollama-config.sh"
  echo "- Start Ollama: sudo systemctl start ollama"
  echo "- Check file permissions: chmod +x scripts/*.sh"
fi

echo -e "\n${CYAN}Results: $PASSED_CHECKS/$TOTAL_CHECKS checks passed${RESET}"
echo -e "\n${BOLD}📚 Documentation available at:${RESET}"
echo "- USER-GUIDE.md - Meet your AI team"
echo "- QUICK-START.md - 15-minute setup"
echo "- TROUBLESHOOTING.md - Solve common issues"
echo "- FAQ.md - Frequently asked questions"
echo "- IMPLEMENTATION-SUMMARY.md - Complete overview"
