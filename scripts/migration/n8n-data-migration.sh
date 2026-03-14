#!/bin/bash
# n8n-data-migration.sh - Proper n8n data backup and restore using CLI commands
# Usage: bash scripts/migration/n8n-data-migration.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OLD_CONTAINER="queue-n8n-1"  # Current running container
NEW_CONTAINER="queue-n8n-1"  # Will restart the same container with new config
BACKUP_DIR="/tmp/n8n-backup-$(date +%Y%m%d_%H%M%S)"
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

# Check if old container is running
check_old_container() {
    header "Checking Old Container"
    
    if docker ps | grep -q "$OLD_CONTAINER"; then
        success "Old container running: $OLD_CONTAINER"
        return 0
    else
        error "Old container not found: $OLD_CONTAINER"
        return 1
    fi
}

# Export data from old container
export_data() {
    header "Exporting Data from Old Container"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    log "Exporting workflows..."
    if docker exec "$OLD_CONTAINER" n8n export:workflow --all --output="$BACKUP_DIR/workflows.json"; then
        success "Workflows exported to $BACKUP_DIR/workflows.json"
    else
        error "Failed to export workflows"
        return 1
    fi
    
    log "Exporting credentials..."
    if docker exec "$OLD_CONTAINER" n8n export:credentials --all --output="$BACKUP_DIR/credentials.json"; then
        success "Credentials exported to $BACKUP_DIR/credentials.json"
    else
        error "Failed to export credentials"
        return 1
    fi
    
    # Show what we got
    log "Export summary:"
    ls -la "$BACKUP_DIR/"
    
    success "Data export completed"
}

# Stop old container and prepare for redeploy
stop_old_container() {
    header "Stopping Container for Redeploy"
    
    if docker ps | grep -q "$OLD_CONTAINER"; then
        log "Stopping $OLD_CONTAINER for redeploy..."
        docker compose -f "$QUEUE_COMPOSE" down
        success "Container stopped for redeploy"
    else
        warning "Container not running"
    fi
}

# Start new container (redeploy with updated config)
start_new_container() {
    header "Starting Container with Queue Mode"
    
    log "Starting queue mode services..."
    if docker compose -f "$QUEUE_COMPOSE" up -d; then
        success "Queue mode services started"
    else
        error "Failed to start queue mode services"
        return 1
    fi
}

# Wait for new container to be ready
wait_for_new_container() {
    header "Waiting for New Container"
    
    log "Waiting for new n8n to be ready..."
    for i in {1..60}; do
        if docker exec "$NEW_CONTAINER" n8n --version > /dev/null 2>&1; then
            success "New n8n is ready after ${i} seconds"
            break
        fi
        sleep 2
    done
    
    if [ $? -ne 0 ]; then
        error "New container failed to start within 60 seconds"
        return 1
    fi
}

# Import data to new container
import_data() {
    header "Importing Data to New Container"
    
    # Check if backup files exist
    if [ ! -f "$BACKUP_DIR/workflows.json" ]; then
        error "Workflows backup not found: $BACKUP_DIR/workflows.json"
        return 1
    fi
    
    if [ ! -f "$BACKUP_DIR/credentials.json" ]; then
        error "Credentials backup not found: $BACKUP_DIR/credentials.json"
        return 1
    fi
    
    log "Importing workflows..."
    if docker exec "$NEW_CONTAINER" n8n import:workflow --file="$BACKUP_DIR/workflows.json"; then
        success "Workflows imported successfully"
    else
        error "Failed to import workflows"
        return 1
    fi
    
    log "Importing credentials..."
    if docker exec "$NEW_CONTAINER" n8n import:credentials --file="$BACKUP_DIR/credentials.json"; then
        success "Credentials imported successfully"
    else
        error "Failed to import credentials"
        return 1
    fi
    
    success "Data import completed"
}

# Verify migration
verify_migration() {
    header "Verifying Migration"
    
    # Check if workflows exist in new container
    if docker exec "$NEW_CONTAINER" test -d "/home/node/.n8n/workflows"; then
        success "Workflows directory exists in new container"
    else
        warning "Workflows directory not found in new container"
    fi
    
    # Check if we can access n8n
    log "Testing n8n access..."
    if curl -s "http://localhost:5678" > /dev/null 2>&1 | grep -q "n8n"; then
        success "n8n is accessible"
    else
        warning "n8n may not be fully ready yet"
    fi
}

# Cleanup
cleanup() {
    header "Cleanup"
    
    log "Cleaning up temporary files..."
    rm -rf "$BACKUP_DIR"
    
    success "Cleanup completed"
}

# Show final status
show_status() {
    header "Migration Status"
    
    echo ""
    log "Old container: $OLD_CONTAINER"
    log "New container: $NEW_CONTAINER"
    log "Backup directory: $BACKUP_DIR"
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
    header "n8n Data Migration (CLI-based)"
    
    if ! check_old_container; then
        error "Cannot proceed without running container"
        exit 1
    fi
    
    if export_data; then
        stop_old_container
        start_new_container
        wait_for_new_container
        
        if import_data; then
            verify_migration
            show_status
            success "Migration completed successfully!"
        else
            error "Import failed"
            exit 1
        fi
    else
        error "Export failed"
        exit 1
    fi
    
    cleanup
}

# Run main function
main "$@"
