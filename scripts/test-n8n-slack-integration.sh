#!/bin/bash
# test-n8n-slack-integration.sh — Comprehensive Slack integration test script
# Tests all AI agent commands and workflows after timeout fixes
# Usage: bash scripts/test-n8n-slack-integration.sh [option]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Configuration
N8N_URL="http://localhost:5678"
SLACK_WEBHOOK_URL="http://localhost:5678/webhook/slack-command"
TEST_CHANNEL="#test-ai-workers"  # Change to your test channel

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

log() {
  echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} $*"
}

success() {
  echo -e "${GREEN}✅ $*${RESET}"
}

warning() {
  echo -e "${YELLOW}⚠️  $*${RESET}"
}

error() {
  echo -e "${RED}❌ $*${RESET}"
}

header() {
  echo -e "${BOLD}${BLUE}=== $1 ===${RESET}"
}

# Test functions
test_n8n_health() {
  log "Testing n8n service health..."
  if curl -s "$N8N_URL/healthz" | grep -q '"status":"ok"'; then
    success "n8n service is healthy"
  else
    error "n8n service is not responding"
    return 1
  fi
}

test_timeout_configuration() {
  log "Testing timeout configuration..."
  local response=$(curl -s -X POST "$N8N_URL/webhook/test-timeout" \
    -H "Content-Type: application/json" \
    -d '{"test": "timeout_check", "duration": 300}' \
    --max-time 120 2>/dev/null)
  
  if echo "$response" | grep -q "600000"; then
    success "Timeout configuration set to 600 seconds"
  else
    error "Timeout configuration not properly set"
    return 1
  fi
}

test_agent_response() {
  local agent=$1
  local test_prompt=$2
  log "Testing $agent agent response..."
  
  # Test with 30-second timeout (should fail with old config)
  local response_30s=$(timeout 30s curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text": "/ai '$agent': '$test_prompt'", "channel": "'$TEST_CHANNEL'"}' \
    --max-time 35 2>/dev/null || echo "TIMEOUT")
  
  # Test with 300-second timeout (should work with new config)
  local response_300s=$(timeout 300s curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text": "/ai '$agent': '$test_prompt'", "channel": "'$TEST_CHANNEL'"}' \
    --max-time 310 2>/dev/null || echo "TIMEOUT")
  
  # Evaluate results
  if [[ "$response_30s" == "TIMEOUT" ]]; then
    if [[ "$response_300s" != "TIMEOUT" ]]; then
      success "$agent agent now responds within 30 seconds"
      PASSED_TESTS=$((PASSED_TESTS + 1))
    else
      error "$agent agent still times out at 30 seconds"
      FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  else
    if [[ "$response_300s" != "TIMEOUT" ]]; then
      success "$agent agent responds within 300 seconds with new timeout"
      PASSED_TESTS=$((PASSED_TESTS + 1))
    else
      error "$agent agent still times out at 300 seconds"
      FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  fi
  
  TOTAL_TESTS=$((TOTAL_TESTS + 2))
}

test_workflow_timeouts() {
  log "Testing workflow timeout handling..."
  
  # Test news digest workflow (should complete in <300s with new config)
  local start_time=$(date +%s)
  curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text": "/news test", "channel": "'$TEST_CHANNEL'"}' \
    --max-time 120 2>/dev/null
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  if [[ $duration -lt 300 ]]; then
    success "News digest completed in ${duration}s (under new 300s limit)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    error "News digest took ${duration}s (exceeds 300s limit)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_long_ai_request() {
  log "Testing long AI request handling..."
  
  # This simulates a request that should take 45-60 seconds
  local response=$(timeout 120s curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text": "/ai kevin: '"'"'Explain in detail the architectural principles behind microservices design, including service discovery, load balancing, and data consistency. Provide specific examples and best practices.'"'"'", "channel": "'$TEST_CHANNEL'"}' \
    --max-time 180 2>/dev/null || echo "TIMEOUT")
  
  if [[ "$response" != "TIMEOUT" ]]; then
    success "Long AI request completed successfully"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    error "Long AI request timed out (unexpected)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_news_workflow() {
  log "Testing news aggregation workflow..."
  local response=$(curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text": "/news", "channel": "'$TEST_CHANNEL'"}' \
    --max-time 120 2>/dev/null)
  
  if echo "$response" | grep -q "completed in"; then
    success "News workflow completed successfully"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    error "News workflow failed"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

test_image_workflow() {
  log "Testing image generation workflow..."
  local response=$(curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text": "/image test prompt", "channel": "'$TEST_CHANNEL'"}' \
    --max-time 120 2>/dev/null)
  
  if echo "$response" | grep -q "studio_image"; then
    success "Image workflow routed correctly"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    error "Image workflow failed"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

# Main test suite
run_tests() {
  header "N8N Slack Integration Test Suite"
  header "Testing n8n Service Health"
  test_n8n_health || return 1
  
  header "Testing Timeout Configuration"
  test_timeout_configuration || return 1
  
  header "Testing Agent Response Times"
  test_agent_response "kevin" "What is your role?"
  test_agent_response "jason" "Write a simple hello world function"
  test_agent_response "scaachi" "Create a short marketing tagline"
  test_agent_response "christian" "Describe a basic business model"
  test_agent_response "chidi" "Research benefits of microservices"
  
  header "Testing Workflow Timeouts"
  test_workflow_timeouts || return 1
  
  header "Testing Long AI Requests"
  test_long_ai_request || return 1
  
  header "Testing Specific Workflows"
  test_news_workflow
  test_image_workflow
  
  # Summary
  echo ""
  header "Test Results Summary"
  echo -e "${CYAN}Total Tests:${RESET} $((TOTAL_TESTS))"
  echo -e "${GREEN}Passed:${RESET} $PASSED_TESTS"
  echo -e "${RED}Failed:${RESET} $FAILED_TESTS"
  echo ""
  if [[ $PASSED_TESTS -eq $((TOTAL_TESTS - FAILED_TESTS)) ]]; then
    echo -e "\n${GREEN}🎉 All tests passed!${RESET}"
    return 0
  else
    echo -e "\n${RED}⚠️  Some tests failed. Check logs above.${RESET}"
    return 1
  fi
}

# Help and usage
show_help() {
  echo -e "${BOLD}${CYAN}N8N Slack Integration Test Script${RESET}"
  echo ""
  echo -e "${YELLOW}Usage:${RESET} bash $0 [option]"
  echo ""
  echo -e "${CYAN}Options:${RESET}"
  echo "  health          Test n8n service health"
  echo "  timeout         Test timeout configuration"
  echo "  agents          Test individual agent responses"
  echo "  workflows       Test workflow timeout handling"
  echo "  long            Test long AI request handling"
  echo "  all             Run complete test suite"
  echo ""
  echo -e "${YELLOW}Environment Variables:${RESET}"
  echo "  TEST_CHANNEL     Slack channel for tests (default: #test-ai-workers)"
  echo "  N8N_URL         n8n instance URL (default: http://localhost:5678)"
  echo ""
  echo -e "${YELLOW}Examples:${RESET}"
  echo "  $0 health                    # Test n8n health"
  echo "  $0 agents --agent kevin       # Test specific agent"
  echo "  $0 all                       # Run complete test suite"
  echo ""
  echo -e "${CYAN}Note:${RESET} Make sure n8n is running and Slack integration is configured."
}

# Parse command line arguments
case "${1:-}" in
  "health")
    test_n8n_health
    ;;
  "timeout")
    test_timeout_configuration
    ;;
  "agents")
    if [[ -n "${2:-}" ]]; then
      error "Agent name required for agents test"
      show_help
      exit 1
    fi
    test_agent_response "$2" "${3:-}"
    ;;
  "workflows")
    test_workflow_timeouts
    ;;
  "long")
    test_long_ai_request
    ;;
  "all")
    run_tests
    ;;
  *)
    echo -e "${RED}Error: Unknown option '$1'${RESET}"
    show_help
    exit 1
    ;;
esac
