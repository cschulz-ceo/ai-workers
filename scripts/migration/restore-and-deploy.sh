#!/bin/bash
# restore-and-deploy.sh - Restore n8n data and deploy queue mode with proper permissions
# Usage: bash scripts/migration/restore-and-deploy.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QUEUE_COMPOSE="/home/biulatech/ai-workers-1/configs/queue/docker-compose.yml"
N8N_DATA_DIR="/home/biulatech/n8n/n8n_data"
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
stop_services() {
    header "Stopping Existing Services"
    docker compose -f "$QUEUE_COMPOSE" down 2>/dev/null || true
    docker compose -f /home/biulatech/ai-workers-1/services/n8n/docker-compose.yml down 2>/dev/null || true
}

# Fix permissions and prepare data
prepare_data() {
    header "Preparing n8n Data Directory"
    
    # Ensure data directory exists and has proper permissions
    if [ ! -d "$N8N_DATA_DIR" ]; then
        error "n8n data directory not found: $N8N_DATA_DIR"
        exit 1
    fi
    
    log "Setting ownership to node user (1000:1000)"
    sudo chown -R 1000:1000 "$N8N_DATA_DIR"
    
    log "Setting permissions to 755"
    sudo chmod -R 755 "$N8N_DATA_DIR"
    
    success "Data directory prepared with proper permissions"
}

# Deploy queue mode
deploy_queue() {
    header "Deploying Queue Mode Infrastructure"
    
    # Create network
    if ! docker network ls | grep -q "n8n-network"; then
        log "Creating Docker network: n8n-network"
        docker network create n8n-network
        success "Docker network created"
    fi
    
    # Deploy services
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

# Verify deployment
verify_deployment() {
    header "Verifying Deployment"
    
    # Check n8n health
    if curl -s "$N8N_URL/healthz" 2>/dev/null | grep -q "ok\|status"; then
        success "n8n health endpoint responding"
    else
        error "n8n health endpoint not responding"
        return 1
    fi
    
    # Check if workflows exist
    if docker exec queue-n8n-1 test -d "/home/node/.n8n/workflows"; then
        success "Workflows directory exists"
    else
        warning "Workflows directory not found - may need manual import"
    fi
    
    # Check if database exists
    if docker exec queue-n8n-1 test -f "/home/node/.n8n/database.sqlite"; then
        success "Database file exists"
    else
        warning "Database file not found - will create new one"
    fi
}

# Show status and next steps
show_status() {
    header "Deployment Status"
    
    echo ""
    log "Docker containers:"
    docker compose -f "$QUEUE_COMPOSE" ps
    
    echo ""
    log "n8n URL: $N8N_URL"
    log "Data directory: $N8N_DATA_DIR"
    
    echo ""
    log "Next steps:"
    echo "1. Access n8n: $N8N_URL"
    echo "2. Check workflows: $N8N_URL/workflows"
    echo "3. Test queue mode: bash scripts/test/test-queue-integration.sh"
    echo "4. Monitor metrics: curl http://localhost:9201/metrics"
}

# Main execution
main() {
    header "n8n Data Restore and Queue Mode Deployment"
    
    stop_services
    prepare_data
    deploy_queue
    wait_for_services
    
    if verify_deployment; then
        show_status
        success "n8n queue mode deployment completed successfully!"
    else
        error "n8n queue mode deployment failed"
        exit 1
    fi
}

main "$@"
