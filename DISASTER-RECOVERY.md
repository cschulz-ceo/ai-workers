# Disaster Recovery Runbook

Quick-reference checklist for recovering from common failures. Work through each scenario step-by-step.

---

## Scenario 1: n8n Shows "Set up owner account" (Empty Database)

**Symptom:** Navigating to localhost:5678 shows a fresh setup screen instead of the login page. All workflows and credentials are missing.

**Root cause:** n8n was started from the wrong Docker Compose file, pointing to an empty database instead of the real one.

**Recovery steps:**

1. Stop whatever n8n container is running:
   ```bash
   docker ps --filter "ancestor=n8nio/n8n:latest" -q | xargs -r docker stop
   ```

2. Verify the real database exists and has data:
   ```bash
   sqlite3 /home/biulatech/n8n/n8n_data/database.sqlite "SELECT count(*) FROM workflow_entity;"
   # Should return 20 (or however many workflows you have)
   ```

3. Start n8n from the correct compose:
   ```bash
   cd /home/biulatech/n8n && docker compose up -d
   ```
   Or use the restart script: `bash /home/biulatech/n8n/restart-n8n.sh`

4. Verify at localhost:5678 — you should see the login page with all workflows listed.

**Prevention:** The only valid compose file for n8n is `/home/biulatech/n8n/docker-compose.yml`. Never start n8n from any other location.

---

## Scenario 2: n8n Is Up but Workflows Don't Appear

**Symptom:** Login works but the workflow list is empty or missing workflows.

**Possible causes:**
- The `workflow_published_version` table is missing entries (n8n v2.11+ requires this)
- The `workflow_history` table is missing entries

**Recovery steps:**

1. Check what the database has:
   ```bash
   sqlite3 /home/biulatech/n8n/n8n_data/database.sqlite \
     "SELECT id, name, active FROM workflow_entity ORDER BY name;"
   ```

2. If workflows exist in the table but don't show in UI, populate the published version table:
   ```bash
   sqlite3 /home/biulatech/n8n/n8n_data/database.sqlite <<'SQL'
   INSERT OR IGNORE INTO workflow_published_version (workflowId, versionId, nodes, connections, settings, staticData, createdAt, updatedAt)
   SELECT id, '1', nodes, connections, settings, staticData, createdAt, updatedAt
   FROM workflow_entity;
   SQL
   ```

3. Restart n8n: `cd /home/biulatech/n8n && docker compose restart`

---

## Scenario 3: Restoring from Backup

**Backups** are created nightly at 3am by cron (`backup-n8n.sh`) and stored in `/home/biulatech/backups/n8n/`.

**Recovery steps:**

1. Stop n8n:
   ```bash
   cd /home/biulatech/n8n && docker compose down
   ```

2. List available backups:
   ```bash
   ls -lt /home/biulatech/backups/n8n/
   ```

3. Restore the database (replace the timestamp with your backup):
   ```bash
   cp /home/biulatech/backups/n8n/database-YYYYMMDD-HHMMSS.sqlite \
      /home/biulatech/n8n/n8n_data/database.sqlite
   ```

4. Restore the .env if needed:
   ```bash
   cp /home/biulatech/backups/n8n/env-YYYYMMDD-HHMMSS.bak \
      /home/biulatech/n8n/.env
   ```

5. Start n8n:
   ```bash
   cd /home/biulatech/n8n && docker compose up -d
   ```

---

## Scenario 4: Ollama Not Responding / Models Timing Out

**Symptom:** Slack commands hang, n8n workflows fail with "connection refused" or timeout errors.

**Check 1 — Is Ollama running?**
```bash
systemctl status ollama
curl http://localhost:11434/api/tags
```

**Check 2 — Is it bound to 0.0.0.0?** (required for Docker containers to reach it)
```bash
ss -tlnp | grep 11434
# Should show *:11434, not 127.0.0.1:11434
```

If bound to 127.0.0.1, the systemd override is missing:
```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo cp /home/biulatech/ai-workers-1/configs/systemd/ollama.service.d/override.conf \
   /etc/systemd/system/ollama.service.d/
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

**Check 3 — Is the model too large for VRAM?**
```bash
ollama ps  # Shows currently loaded models and VRAM usage
```
If a model shows CPU offloading, it exceeds 16 GB VRAM. Switch to Qwen3 14B (see MODEL-GUIDE.md).

---

## Scenario 5: Slack Webhooks Not Receiving Messages

**Symptom:** Slack slash commands do nothing, no activity in n8n executions.

**Check 1 — Is ngrok running?**
```bash
curl http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'])"
```

**Check 2 — Does the tunnel URL match the n8n webhook URL?**
```bash
grep WEBHOOK_URL /home/biulatech/n8n/.env
```
The URLs must match. If ngrok assigned a new URL, update the .env and restart n8n.

**Check 3 — Is the Slack app pointing to the right URL?**
Go to api.slack.com → your app → Slash Commands. Each command's Request URL must point to the ngrok domain.

---

## Scenario 6: Complete System Recovery (After Reboot or Power Loss)

All services should auto-start via systemd and Docker restart policies. Verify:

```bash
# Check all services
systemctl status ollama
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
curl -s http://localhost:5678/healthz    # n8n
curl -s http://localhost:11434/api/tags  # Ollama
curl -s http://localhost:3001/api/health # Grafana
curl -s http://localhost:4040/api/tunnels # ngrok
```

If any service is down, restart it:
```bash
sudo systemctl restart ollama          # Ollama
cd /home/biulatech/n8n && docker compose up -d  # n8n
cd /home/biulatech/monitoring && docker compose up -d  # Grafana/Prometheus
sudo systemctl restart ngrok           # ngrok tunnel
```

---

## Key File Locations

| What | Path |
|------|------|
| n8n database (source of truth) | `/home/biulatech/n8n/n8n_data/database.sqlite` |
| n8n compose (the only valid one) | `/home/biulatech/n8n/docker-compose.yml` |
| n8n secrets | `/home/biulatech/n8n/.env` |
| n8n restart script | `/home/biulatech/n8n/restart-n8n.sh` |
| Nightly backups | `/home/biulatech/backups/n8n/` |
| Ollama override | `/etc/systemd/system/ollama.service.d/override.conf` |
| Modelfiles | `/home/biulatech/ai-workers-1/agents/personalities/` |
| Monitoring stack | `/home/biulatech/monitoring/docker-compose.yml` |
