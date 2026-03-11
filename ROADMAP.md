# ai-workers Deployment Roadmap

> Last updated: 2026-03-11
> Status key: ✅ Done · 🔄 In Progress · 🔲 Pending · ⏳ Future

---

## Phase 0 — Foundation ✅
Everything needed to run local AI workers reliably.

| Item | Status | Notes |
|------|--------|-------|
| Pop!_OS workstation setup | ✅ | RTX 5070 Ti, 64GB RAM |
| NVIDIA driver + persistence | ✅ | 06-remediate-sudo.sh |
| Docker running | ✅ | |
| Ollama installed | ✅ | Port 11434 |
| n8n running | ✅ | Port 5678, docker compose |
| Open WebUI running | ✅ | Port 8080 |
| ngrok tunnel | ✅ | appendicular-wilson-looser.ngrok-free.dev |
| GitHub repo (SSH auth) | ✅ | cschulz-ceo/ai-workers (private) |
| 5 personality models built | ✅ | kevin, jason, scaachi, christian, chidi |
| Old models pruned | ✅ | 19 → 9 models |

---

## Phase 1 — Slack Integration ✅ / 🔄
Full Slack ↔ n8n communication layer.

| Item | Status | Notes |
|------|--------|-------|
| Slack app created (manifest) | ✅ | ai-workers app |
| 21 channels created | ✅ | counsel/tasks/gen/ops groups |
| Bot + user invited to all channels | ✅ | |
| Slash commands registered | ✅ | /ai, /ai-status, /ai-draw, /ai-diagnose |
| n8n events receiver workflow | ✅ | /webhook/slack-events, url_verification |
| n8n command handler workflow (ack) | ✅ | /webhook/slack-command, 3s ack working |
| Enable Slack Event Subscriptions | 🔲 | Needs: toggle on in Slack app settings |
| Slack credentials in n8n | 🔲 | Add xoxb- token + signing secret as n8n Credentials |

### Manual step: Enable Event Subscriptions
1. Slack app → Features → Event Subscriptions → toggle On
2. URL: `https://appendicular-wilson-looser.ngrok-free.dev/webhook/slack-events`
3. Verify passes green (events receiver is live)
4. Confirm bot events: `message.channels`, `app_mention`
5. Save Changes

### Manual step: Add Slack credentials in n8n
1. n8n → Credentials → Add Credential → search "Header Auth"
2. Name: `Slack Bot Token`
   - Name: `Authorization`
   - Value: `Bearer REDACTED_SLACK_BOT_TOKEN`
3. Add another → "Generic Credential"
4. Name: `Slack Signing Secret`
   - Value: `REDACTED_SIGNING_SECRET`

---

## Phase 2 — Slack ↔ Ollama Integration 🔄
Wire slash commands and mentions to actual AI personality responses.

| Item | Status | Notes |
|------|--------|-------|
| `/ai` → Ollama API call | 🔲 | Async: ack → Ollama → response_url |
| Personality routing by channel | 🔲 | #counsel-kevin → kevin:latest |
| Personality routing by text prefix | 🔲 | `/ai kevin: <text>` → kevin |
| Response posted back to Slack | 🔲 | Via response_url or chat.postMessage |
| App mention handler | 🔲 | @ai-workers in channel → route to personality |
| Streaming-friendly chunked responses | 🔲 | Future: split long responses |

### How routing will work
```
/ai <text>                     → general (no personality, use kevin as default)
/ai kevin: <text>              → kevin:latest
/ai jason: <text>              → jason:latest
Message in #counsel-kevin      → kevin:latest (via app_mention or message.channels)
Message in #tasks-jason        → jason:latest (structured task flow)
```

### Ollama API endpoint (from inside n8n container)
```
POST http://host.docker.internal:11434/api/chat
{
  "model": "kevin:latest",
  "messages": [{ "role": "user", "content": "<text>" }],
  "stream": false
}
```

---

## Phase 3 — Slash Command Workflows 🔲
Dedicated handlers for each slash command beyond `/ai`.

| Command | Workflow | What it does |
|---------|----------|-------------|
| `/ai-status` | slack-status-handler | Checks Ollama, Docker, GPU, ngrok; posts to #ops-status |
| `/ai-diagnose` | slack-diagnose-handler | Runs health checks; posts full report |
| `/ai-draw` | slack-draw-handler | Routes to ComfyUI (Phase 5); placeholder now |

### `/ai-status` implementation plan
1. Webhook → ack immediately
2. HTTP Request to Ollama: `GET host.docker.internal:11434/api/tags`
3. HTTP Request to n8n own health: `GET localhost:5678/healthz`
4. Bash via Execute Command: `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits`
5. Compose status message → post to `#ops-status` via Slack API

---

## Phase 4 — Ops Automation 🔲
Proactive monitoring, alerts, and digests without human triggering.

| Item | Status | Notes |
|------|--------|-------|
| Hourly status post → #ops-status | 🔲 | n8n Schedule trigger |
| Daily digest → #ops-reports | 🔲 | Summary of executions, agent usage |
| GPU overload alert → #ops-alerts | 🔲 | Threshold: >90% util for 5min |
| Service-down alert → #ops-alerts | 🔲 | Ollama/n8n/Open WebUI down |
| Commit notifications → #ops-updates | 🔲 | GitHub webhook → n8n → Slack |

### GitHub webhook for #ops-updates
1. GitHub repo → Settings → Webhooks → Add webhook
2. Payload URL: `https://appendicular-wilson-looser.ngrok-free.dev/webhook/github-push`
3. Content type: `application/json`
4. Events: Pushes
5. n8n workflow: receives push → formats commit summary → posts to #ops-updates

---

## Phase 5 — Task Management Integration 🔲
`#tasks-*` channels become structured agent task queues.

| Item | Status | Notes |
|------|--------|-------|
| Plane self-hosted setup | 🔲 | Task/project management |
| #tasks-* → Plane issue creation | 🔲 | n8n workflow |
| Agent processes task → updates issue | 🔲 | |
| Completion → post to #gen-* | 🔲 | Result artifact posted to appropriate gen channel |

### Task message format (in #tasks-kevin)
```
TASK: Design the database schema for the user auth service
CONTEXT: We're using PostgreSQL, need to support OAuth and email/password
PRIORITY: high
```
→ n8n creates Plane issue, assigns to Kevin, calls Ollama, posts result + closes issue

---

## Phase 6 — Generative Output Feeds 🔲
Auto-populate `#gen-*` channels with agent outputs.

| Channel | Source | Trigger |
|---------|--------|---------|
| #gen-images | ComfyUI | /ai-draw command |
| #gen-architecture | Kevin | Architecture task completion |
| #gen-code | Jason | Code task completion |
| #gen-content | Scaachi | Content task completion |
| #gen-video | Future | Not yet implemented |

---

## Phase 7 — Domain & Production Hardening ⏳
Move from ngrok free tier to proper domain.

| Item | Status | Notes |
|------|--------|-------|
| n8n.biulatech.com CNAME in Wix DNS | ⏳ | Wix: Manage Domain → DNS Records |
| Cloudflare proxy for n8n subdomain | ⏳ | See ADR-015 |
| n8n behind reverse proxy (caddy/nginx) | ⏳ | TLS termination |
| n8n auth enabled | ⏳ | N8N_BASIC_AUTH_ACTIVE=true |
| Automated backups (n8n_data, .env) | ⏳ | Cron → rclone → cloud |
| Monitoring: Uptime Kuma | ⏳ | Service health dashboard |
| Monitoring: Netdata | ⏳ | GPU/CPU/RAM metrics |

---

## What You Can Configure Right Now (No Code Needed)

### In Slack (api.slack.com/apps → ai-workers):
- [ ] Enable Event Subscriptions (see Phase 1 above)
- [ ] Verify `message.channels` + `app_mention` bot events are saved

### In n8n (localhost:5678):
- [ ] Add Slack Bot Token as Header Auth credential
- [ ] Add Slack Signing Secret as credential
- [ ] Open Slack Command Handler → confirm webhook path is `slack-command`
- [ ] Open Slack Events Receiver → confirm active + path is `slack-events`

### In Open WebUI (localhost:8080):
- [ ] Create an account (first signup = admin)
- [ ] Confirm all 5 personalities appear in the model picker
- [ ] Set a default model (kevin or chidi recommended for general use)
- [ ] Admin → Settings → enable "Chat History" if not already on
- [ ] Admin → Settings → set document embedding model to `nomic-embed-text`

### In Wix (manage.wix.com) — optional, future prep:
- [ ] Go to Manage Domain → DNS Records
- [ ] Note whether you can add a CNAME record for `n8n` subdomain
  (This is the migration path to n8n.biulatech.com — no rush, just note the UI)

---

## Session Progress Log

| Date | Completed |
|------|-----------|
| 2026-03-11 | Infrastructure, ngrok, personalities, Slack channels, slash commands, end-to-end test |
