#!/bin/bash
# deploy-queue-simple.sh - Simple n8n queue mode deployment
# Usage: bash scripts/migration/deploy-queue-simple.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QUEUE_COMPOSE="/home/biulatech/ai-workers-1/configs/queue/docker-compose.yml"
N8N_URL="http://localhost:5678"

log() {
    echo -e "${NC}[$(date +%H:%M:%S)]${NC} $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Stop existing services
stop_existing_services() {
    header "Stopping Existing Services"
    
    # Stop any existing queue services
    docker compose -f "$QUEUE_COMPOSE" down 2>/dev/null || true
    
    # Stop current n8n if running
    if docker ps | grep -q "n8n"; then
        log "Stopping current n8n service..."
        docker compose -f /home/biulatech/ai-workers-1/services/n8n/docker-compose.yml down 2>/dev/null || true
        success "Existing n8n service stopped"
    fi
}

# Deploy queue mode
deploy_queue_stack() {
    header "Deploying Queue Mode Infrastructure"
    
    # Create networks if needed
    if ! docker network ls | grep -q "n8n-network"; then
        log "Creating Docker network: n8n-network"
        docker network create n8n-network
        success "Docker network created"
    fi
    
    # Deploy queue stack
    log "Deploying queue mode services..."
    docker compose -f "$QUEUE_COMPOSE" up -d
    
    if [ $? -eq 0 ]; then
        success "Queue mode services deployed successfully"
    else
        error "Failed to deploy queue mode services"
        exit 1
    fi
}

# Wait for services
wait_for_services() {
    header "Waiting for Services to Start"
    
    log "Waiting for Redis to be ready..."
    for i in {1..30}; do
        if docker exec n8n-redis redis-cli ping > /dev/null 2>&1; then
            success "Redis is ready after ${i} seconds"
            break
        fi
        sleep 1
    done
    
    log "Waiting for PostgreSQL to be ready..."
    for i in {1..30}; do
        if docker exec n8n-postgres pg_isready -U n8n > /dev/null 2>&1; then
            success "PostgreSQL is ready after ${i} seconds"
            break
        fi
        sleep 1
    done
    
    log "Waiting for n8n to be ready..."
    for i in {1..120}; do
        if curl -s "$N8N_URL/healthz" 2>/dev/null | grep -q "ok\|status"; then
            success "n8n is ready after ${i} seconds"
            break
        fi
        sleep 2
    done
}

# Show status
show_status() {
    header "Service Status"
    
    echo ""
    log "Docker containers:"
    docker compose -f "$QUEUE_COMPOSE" ps
    
    echo ""
    log "Testing n8n health endpoint..."
    if curl -s "$N8N_URL/healthz" 2>/dev/null | jq . 2>/dev/null; then
        success "n8n health endpoint responding"
    else
        warning "n8n health endpoint not responding yet"
    fi
    
    echo ""
    log "Next steps:"
    echo "1. Check n8n URL: $N8N_URL"
    echo "2. Verify queue mode is active"
    echo "3. Test with: bash scripts/test/test-queue-integration.sh"
}

# Main execution
main() {
    header "n8n Queue Mode Deployment (Simple)"
    
    stop_existing_services
    deploy_queue_stack
    wait_for_services
    show_status
    
    success "Queue mode deployment completed!"
}

main "$@"
