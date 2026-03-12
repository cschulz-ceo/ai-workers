#!/bin/bash
# export-workflows.sh — Export all active n8n workflows to JSON and commit if changed
# Requires n8n API key in /home/biulatech/n8n/.env as N8N_API_KEY
# Cron: 0 2 * * * /home/biulatech/ai-workers-1/scripts/maintenance/export-workflows.sh >> /var/log/n8n-export.log 2>&1

set -euo pipefail

REPO="/home/biulatech/ai-workers-1"
EXPORT_DIR="$REPO/workflows"
N8N_URL="http://localhost:5678"
N8N_API_KEY=$(grep '^N8N_API_KEY=' /home/biulatech/n8n/.env | cut -d= -f2)

echo "[$(date -Iseconds)] Starting n8n workflow export..."

if [[ -z "$N8N_API_KEY" ]]; then
    echo "[$(date -Iseconds)] ERROR: N8N_API_KEY not found in /home/biulatech/n8n/.env"
    exit 1
fi

# Fetch all workflow IDs and names
workflows=$(curl -sf "$N8N_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin).get('data', [])
for w in data:
    name = w['name'].lower().replace(' ', '-').replace('/', '-').replace('_', '-')
    print(w['id'], name)
")

if [[ -z "$workflows" ]]; then
    echo "[$(date -Iseconds)] WARNING: No workflows returned from n8n API. Is n8n running?"
    exit 1
fi

count=0
while IFS=' ' read -r id name; do
    outfile="$EXPORT_DIR/$name.json"
    curl -sf "$N8N_URL/api/v1/workflows/$id" \
        -H "X-N8N-API-KEY: $N8N_API_KEY" \
        | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2))" \
        > "$outfile"
    echo "[$(date -Iseconds)] Exported: $name.json"
    ((count++))
done <<< "$workflows"

echo "[$(date -Iseconds)] Exported $count workflows."

# Commit if anything changed
cd "$REPO"
if ! git diff --quiet workflows/; then
    git add workflows/
    git commit -m "chore: auto-export n8n workflows $(date +%Y-%m-%d)"
    git push
    echo "[$(date -Iseconds)] Committed and pushed workflow changes."
else
    echo "[$(date -Iseconds)] No workflow changes — nothing to commit."
fi
