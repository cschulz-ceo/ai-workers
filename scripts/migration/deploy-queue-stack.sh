#!/bin/bash
# deploy-queue-stack.sh - Deploy n8n queue mode infrastructure
# Usage: bash scripts/migration/deploy-queue-stack.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QUEUE_COMPOSE="/home/biulatech/ai-workers-1/configs/queue/docker-compose.yml"
BACKUP_DIR="/home/biulatech/backups"
N8N_URL="http://localhost:5678"
REDIS_HOST="localhost"
REDIS_PORT="6379"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"

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

# Check prerequisites
check_prerequisites() {
    header "Checking Prerequisites"
    
    # Check Docker
    if ! command -v docker; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi
    success "Docker: $(docker --version)"
    
    # Check Docker Compose
    if ! docker compose version > /dev/null 2>&1; then
        error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    success "Docker Compose: $(docker compose version)"
    
    # Check configuration files
    if [ ! -f "$QUEUE_COMPOSE" ]; then
        error "Queue compose file not found: $QUEUE_COMPOSE"
        exit 1
    fi
    success "Queue compose file: $QUEUE_COMPOSE"
}

# Stop existing services
stop_existing_services() {
    header "Stopping Existing Services"
    
    # Stop current n8n
    if docker ps | grep -q "n8n"; then
        log "Stopping current n8n service..."
        docker compose -f /home/biulatech/ai-workers-1/services/n8n/docker-compose.yml down
        success "Existing n8n service stopped"
    else
        warning "No existing n8n service found"
    fi
    
    # Remove any existing queue services
    if docker ps | grep -q "n8n-redis"; then
        log "Stopping existing Redis service..."
        docker stop n8n-redis
        success "Existing Redis service stopped"
    fi
    
    if docker ps | grep -q "n8n-postgres"; then
        log "Stopping existing PostgreSQL service..."
        docker stop n8n-postgres
        success "Existing PostgreSQL service stopped"
    fi
}

# Deploy new infrastructure
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

# Wait for services to be ready
wait_for_services() {
    header "Waiting for Services to Start"
    
    log "Waiting for Redis to be ready..."
    local redis_ready=false
    for i in {1..30}; do
        if docker exec n8n-redis redis-cli ping > /dev/null 2>&1; then
            redis_ready=true
            success "Redis is ready after ${i} seconds"
            break
        fi
        sleep 1
    done
    
    if [ "$redis_ready" = false ]; then
        error "Redis failed to start within 30 seconds"
        docker logs n8n-redis --tail 20
        exit 1
    fi
    
    log "Waiting for PostgreSQL to be ready..."
    local postgres_ready=false
    for i in {1..30}; do
        if docker exec n8n-postgres pg_isready -U n8n > /dev/null 2>&1; then
            postgres_ready=true
            success "PostgreSQL is ready after ${i} seconds"
            break
        fi
        sleep 1
    done
    
    if [ "$postgres_ready" = false ]; then
        error "PostgreSQL failed to start within 30 seconds"
        docker logs n8n-postgres --tail 20
        exit 1
    fi
    
    log "Waiting for n8n to be ready..."
    local n8n_ready=false
    for i in {1..60}; do
        if curl -s "$N8N_URL/healthz" | grep -q "ok"; then
            n8n_ready=true
            success "n8n is ready after ${i} seconds"
            break
        fi
        sleep 1
    done
    
    if [ "$n8n_ready" = false ]; then
        error "n8n failed to start within 60 seconds"
        docker logs n8n --tail 20
        exit 1
    fi
}

# Verify deployment
verify_deployment() {
    header "Verifying Deployment"
    
    # Check Redis connectivity
    log "Testing Redis connectivity..."
    if docker exec n8n-redis redis-cli ping > /dev/null 2>&1; then
        success "Redis connectivity: OK"
    else
        error "Redis connectivity: FAILED"
        return 1
    fi
    
    # Check PostgreSQL connectivity
    log "Testing PostgreSQL connectivity..."
    if PGPASSWORD=${POSTGRES_PASSWORD} docker exec n8n-postgres psql -U n8n -d n8n_queue -c "SELECT 1;" > /dev/null 2>&1; then
        success "PostgreSQL connectivity: OK"
    else
        error "PostgreSQL connectivity: FAILED"
        return 1
    fi
    
    # Check n8n queue mode
    log "Testing n8n queue mode..."
    local execution_mode=$(curl -s "$N8N_URL/healthz" | jq -r '.execution_mode // "main"')
    if [ "$execution_mode" = "queue" ]; then
        success "n8n queue mode: ACTIVE"
    else
        error "n8n queue mode: NOT ACTIVE (mode: $execution_mode)"
        return 1
    fi
    
    # Check worker count
    log "Checking worker configuration..."
    local worker_count=$(curl -s "$N8N_URL/healthz" | jq -r '.concurrency_limit // 1')
    if [ "$worker_count" -ge 4 ]; then
        success "Workers configured: $worker_count (expected: 4+)"
    else
        warning "Workers configured: $worker_count (expected: 4+)"
    fi
}

# Show service status
show_service_status() {
    header "Service Status"
    
    echo ""
    log "Docker containers:"
    docker compose -f "$QUEUE_COMPOSE" ps
    
    echo ""
    log "Resource usage:"
    docker stats --no-stream n8n-redis n8n-postgres n8n 2>/dev/null || true
    
    echo ""
    log "Network information:"
    docker network ls | grep "n8n-network"
}

# Cleanup function
cleanup() {
    header "Cleanup"
    log "Removing any orphaned containers..."
    docker container prune -f
    success "Cleanup completed"
}

# Main execution
main() {
    header "n8n Queue Mode Deployment"
    
    check_prerequisites
    stop_existing_services
    deploy_queue_stack
    wait_for_services
    
    if verify_deployment; then
        show_service_status
        success "Queue mode deployment completed successfully!"
        echo ""
        log "Next steps:"
        echo "1. Test the setup: bash scripts/test/test-queue-integration.sh"
        echo "2. Monitor performance: curl http://localhost:5678/metrics"
        echo "3. View dashboard: http://localhost:3000 (Grafana)"
    else
        error "Queue mode deployment failed. Check logs above."
        exit 1
    fi
}

# Handle cleanup on script exit
trap cleanup EXIT

# Run main function
main "$@"
