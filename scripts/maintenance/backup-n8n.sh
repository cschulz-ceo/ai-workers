#!/bin/bash
# backup-n8n.sh — Daily n8n SQLite + .env backup with optional rclone cloud sync
# Cron: 0 3 * * * /home/biulatech/ai-workers-1/scripts/maintenance/backup-n8n.sh >> /var/log/n8n-backup.log 2>&1
#
# Prerequisites:
#   sudo apt install sqlite3
#   Optional: rclone configured with a remote named 'backup'
#             rclone config — add a Backblaze B2 or Google Drive remote named 'backup'

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/home/biulatech/backups/n8n"
N8N_DB="/home/biulatech/n8n/n8n_data/database.sqlite"
N8N_ENV="/home/biulatech/n8n/.env"
KEEP_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "[$(date -Iseconds)] Starting n8n backup..."

# SQLite hot backup — safe while n8n is running (WAL mode is handled correctly)
if command -v sqlite3 &>/dev/null; then
    sqlite3 "$N8N_DB" ".backup '$BACKUP_DIR/n8n-$TIMESTAMP.sqlite'"
    echo "[$(date -Iseconds)] SQLite backup: $BACKUP_DIR/n8n-$TIMESTAMP.sqlite ($(du -sh "$BACKUP_DIR/n8n-$TIMESTAMP.sqlite" | cut -f1))"
else
    echo "[$(date -Iseconds)] WARNING: sqlite3 not found — install with: sudo apt install sqlite3"
fi

# .env backup (secrets — keep permissions tight)
if [[ -f "$N8N_ENV" ]]; then
    cp "$N8N_ENV" "$BACKUP_DIR/n8n-env-$TIMESTAMP.env"
    chmod 600 "$BACKUP_DIR/n8n-env-$TIMESTAMP.env"
    echo "[$(date -Iseconds)] .env backup: $BACKUP_DIR/n8n-env-$TIMESTAMP.env"
fi

# Prune old local backups (keep last KEEP_DAYS days)
find "$BACKUP_DIR" -name "n8n-*.sqlite" -mtime +"$KEEP_DAYS" -delete
find "$BACKUP_DIR" -name "n8n-env-*.env" -mtime +"$KEEP_DAYS" -delete
echo "[$(date -Iseconds)] Pruned backups older than $KEEP_DAYS days"

# Optional: rclone sync to cloud (configure 'backup' remote first)
if command -v rclone &>/dev/null && rclone listremotes 2>/dev/null | grep -q '^backup:'; then
    rclone copy "$BACKUP_DIR" backup:biulatech-ai-workers/n8n/ \
        --include "*.sqlite" --include "*.env" \
        --progress 2>/dev/null || echo "[$(date -Iseconds)] WARNING: rclone sync failed"
    echo "[$(date -Iseconds)] rclone sync complete"
else
    echo "[$(date -Iseconds)] rclone not configured — skipping cloud sync"
fi

echo "[$(date -Iseconds)] Backup complete."
