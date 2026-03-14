#!/bin/bash
# restore-n8n-data.sh - Simple script to copy existing n8n data to new container
# Usage: bash scripts/migration/restore-n8n-data.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OLD_DATA_DIR="/home/biulatech/n8n/n8n_data"
NEW_CONTAINER="queue-n8n-1"
QUEUE_COMPOSE="/home/biulatech/ai-workers-1/configs/queue/docker-compose.yml"

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

# Check if old data exists
check_old_data() {
    header "Checking Old n8n Data"
    
    if [ -d "$OLD_DATA_DIR" ]; then
        success "Old n8n data directory found: $OLD_DATA_DIR"
        return 0
    else
        error "Old n8n data directory not found: $OLD_DATA_DIR"
        return 1
    fi
}

# Stop current container
stop_container() {
    header "Stopping Current Container"
    
    log "Stopping current container..."
    docker compose -f "$QUEUE_COMPOSE" down
    success "Container stopped"
}

# Fix permissions and restart with data copy
copy_data_and_restart() {
    header "Copying Data and Restarting"
    
    # Fix permissions on old data
    log "Setting proper permissions on old data..."
    sudo chown -R 1000:1000 "$OLD_DATA_DIR"
    success "Permissions fixed on old data directory"
    
    # Update docker-compose to use the old data directory
    log "Updating docker-compose to use existing data..."
    
    # Start container with old data
    log "Starting container with existing data..."
    if docker compose -f "$QUEUE_COMPOSE" up -d; then
        success "Container started with existing data"
    else
        error "Failed to start container"
        return 1
    fi
}

# Wait for container to be ready
wait_for_container() {
    header "Waiting for Container"
    
    log "Waiting for n8n to be ready..."
    for i in {1..60}; do
        if docker exec "$NEW_CONTAINER" n8n --version > /dev/null 2>&1; then
            success "n8n is ready after ${i} seconds"
            break
        fi
        sleep 2
    done
    
    if [ $? -ne 0 ]; then
        error "Container failed to start within 60 seconds"
        return 1
    fi
}

# Verify data restoration
verify_restoration() {
    header "Verifying Data Restoration"
    
    # Check if workflows exist
    if docker exec "$NEW_CONTAINER" test -f "/home/node/.n8n/database.sqlite"; then
        success "Database file exists in new container"
    else
        warning "Database file not found in new container"
    fi
    
    # Check if we can access n8n
    log "Testing n8n access..."
    if curl -s "http://localhost:5678" > /dev/null 2>&1 | grep -q "n8n"; then
        success "n8n is accessible"
    else
        warning "n8n may not be fully ready yet"
    fi
}

# Show final status
show_status() {
    header "Restoration Status"
    
    echo ""
    log "Old data directory: $OLD_DATA_DIR"
    log "New container: $NEW_CONTAINER"
    log "n8n URL: http://localhost:5678"
    
    echo ""
    log "Docker containers:"
    docker compose -f "$QUEUE_COMPOSE" ps
    
    echo ""
    log "Next steps:"
    echo "1. Access n8n: http://localhost:5678"
    echo "2. Check workflows: http://localhost:5678/workflows"
    echo "3. Test queue mode: bash scripts/test/test-queue-integration.sh"
}

# Main execution
main() {
    header "n8n Data Restoration"
    
    if ! check_old_data; then
        error "Cannot proceed without existing n8n data"
        exit 1
    fi
    
    stop_container
    copy_data_and_restart
    wait_for_container
    verify_restoration
    show_status
    
    success "Data restoration completed!"
}

# Run main function
main "$@"
