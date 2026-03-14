#!/bin/bash
# setup-queue-env.sh - Setup environment variables for n8n queue mode
# Usage: bash scripts/setup-queue-env.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QUEUE_ENV_FILE="/home/biulatech/ai-workers-1/configs/queue/.env"
EXISTING_ENV_FILE="/home/biulatech/ai-workers-1/services/n8n/.env"

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

# Generate secure passwords
generate_passwords() {
    log "Generating secure passwords..."
    
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
    
    success "Generated Redis password"
    success "Generated PostgreSQL password"
}

# Read existing environment variables
read_existing_env() {
    log "Reading existing environment variables..."
    
    if [ -f "$EXISTING_ENV_FILE" ]; then
        # Source existing environment
        set -a
        source "$EXISTING_ENV_FILE"
        set +a
        
        success "Loaded existing environment variables"
    else
        warning "No existing .env file found"
    fi
}

# Create new environment file
create_queue_env() {
    log "Creating queue mode environment file..."
    
    cat > "$QUEUE_ENV_FILE" << EOF
# n8n Queue Mode Environment Variables
# Generated on $(date)

# Database passwords
REDIS_PASSWORD=${REDIS_PASSWORD}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Core queue mode settings
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=redis
QUEUE_BULL_REDIS_PORT=6379
QUEUE_BULL_REDIS_PASSWORD=\${REDIS_PASSWORD}

# Worker configuration
N8N_CONCURRENCY_LIMIT=4
N8N_MAX_EXECUTION_TIMEOUT=600
N8N_RUNNERS_ENABLED=true

# Database configuration
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n_queue
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}

# Preserve existing configuration
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:5678/}
N8N_BASIC_AUTH_ACTIVE=false
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY:-}
SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN:-}
SLACK_SIGNING_SECRET=${SLACK_SIGNING_SECRET:-}
SLACK_INCOMING_WEBHOOK_URL=${SLACK_INCOMING_WEBHOOK_URL:-}
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
NODE_FUNCTION_ALLOW_BUILTIN=*
NODE_FUNCTION_ALLOW_EXTERNAL=*
EOF

    success "Environment file created: $QUEUE_ENV_FILE"
}

# Show summary
show_summary() {
    echo -e "${BLUE}=== Setup Summary ===${NC}"
    
    echo ""
    log "Environment file: $QUEUE_ENV_FILE"
    log "Redis password: [SET]"
    log "PostgreSQL password: [SET]"
    echo ""
    
    if [ -n "${N8N_ENCRYPTION_KEY:-}" ]; then
        success "N8N encryption key: [PRESERVED]"
    else
        warning "N8N encryption key: [NOT SET]"
    fi
    
    if [ -n "${SLACK_BOT_TOKEN:-}" ]; then
        success "Slack bot token: [PRESERVED]"
    else
        warning "Slack bot token: [NOT SET]"
    fi
    
    echo ""
    log "Next steps:"
    echo "1. Review the environment file: $QUEUE_ENV_FILE"
    echo "2. Deploy queue mode: bash scripts/migration/deploy-queue-stack-fixed.sh"
    echo "3. Test the setup: bash scripts/test/test-queue-integration.sh"
}

# Main execution
main() {
    echo -e "${BLUE}=== Setting up n8n Queue Mode Environment ===${NC}"
    
    generate_passwords
    read_existing_env
    create_queue_env
    show_summary
    
    success "Environment setup completed!"
}

# Run main function
main "$@"
