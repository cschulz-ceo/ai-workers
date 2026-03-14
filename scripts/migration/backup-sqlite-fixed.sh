#!/bin/bash
# backup-sqlite.sh - Backup current n8n SQLite data before migration
# Usage: bash scripts/migration/backup-sqlite-fixed.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration - Fixed for actual container name and path
BACKUP_DIR="/home/biulatech/backups/n8n-$(date +%Y%m%d_%H%M%S)"
N8N_CONTAINER="n8n-n8n-1"
N8N_DATA_PATH="/home/node/.n8n"

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

# Create backup directory
log "Creating backup directory..."
mkdir -p "$BACKUP_DIR"

# Check if n8n container is running
if ! docker ps | grep -q "$N8N_CONTAINER"; then
    error "n8n container is not running. Please start n8n first."
    exit 1
fi

# Backup SQLite database
log "Backing up SQLite database..."
if docker exec "$N8N_CONTAINER" test -f "$N8N_DATA_PATH/database.sqlite"; then
    docker exec "$N8N_CONTAINER" sqlite3 "$N8N_DATA_PATH/database.sqlite" ".backup" > "$BACKUP_DIR/n8n_database_backup.sql"
    success "SQLite database backed up to $BACKUP_DIR/n8n_database_backup.sql"
else
    error "SQLite database not found at $N8N_DATA_PATH/database.sqlite"
    exit 1
fi

# Backup workflows directory
log "Backing up workflows..."
if docker exec "$N8N_CONTAINER" test -d "$N8N_DATA_PATH/workflows"; then
    docker exec "$N8N_CONTAINER" tar -czf -C "$N8N_DATA_PATH" workflows/ | tar -xzf - -C "$BACKUP_DIR"
    success "Workflows backed up to $BACKUP_DIR/workflows/"
else
    warning "Workflows directory not found"
fi

# Backup configuration files
log "Backing up configuration files..."
mkdir -p "$BACKUP_DIR/configs"

# Copy current environment file
if [ -f "/home/biulatech/ai-workers-1/services/n8n/.env" ]; then
    cp "/home/biulatech/ai-workers-1/services/n8n/.env" "$BACKUP_DIR/configs/.env"
    success "Environment file backed up"
fi

# Copy current docker-compose.yml
if [ -f "/home/biulatech/ai-workers-1/services/n8n/docker-compose.yml" ]; then
    cp "/home/biulatech/ai-workers-1/services/n8n/docker-compose.yml" "$BACKUP_DIR/configs/docker-compose.yml"
    success "Docker compose file backed up"
fi

# Get backup size
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

# Summary
log "Backup completed successfully!"
log "Backup location: $BACKUP_DIR"
log "Backup size: $BACKUP_SIZE"
log "Files backed up:"
ls -la "$BACKUP_DIR"

echo ""
success "Ready for queue mode migration!"
echo "Next steps:"
echo "1. Review backup at: $BACKUP_DIR"
echo "2. Deploy queue mode: docker-compose -f configs/queue/docker-compose.yml up -d"
echo "3. Test new setup: bash scripts/test/test-queue-integration.sh"
