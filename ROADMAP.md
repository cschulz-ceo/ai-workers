# ai-workers Deployment Roadmap

> Last updated: 2026-03-18
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
| Slash commands registered | ✅ | All 11: /ai, /ai-status, /ai-draw, /ai-diagnose, /image, /video, /enhance, /news, /pm, /3d, /patent |
| n8n events receiver workflow | ✅ | Code+Switch routing, app_mention → Ollama → thread reply |
| n8n command handler workflow (ack) | ✅ | /webhook/slack-command, 3s ack working |
| Slack Event Subscriptions | ✅ | **Verified** — `appendicular-wilson-looser.ngrok-free.dev/webhook/slack-events` |
| Slack credentials in n8n | ✅ | Header Auth credential configured |

### ✅ Manual steps complete (as of 2026-03-18)
- Event Subscriptions: On, URL verified, bot events `message.channels` + `app_mention` saved
- All 11 slash commands confirmed in Slack app → Slash Commands

### Manual step: Add Slack credentials in n8n
1. n8n → Credentials → Add Credential → search "Header Auth"
2. Name: `Slack Bot Token`
   - Name: `Authorization`
   - Value: `Bearer $SLACK_BOT_TOKEN` (get value from `/home/biulatech/n8n/.env`)
3. Add another → "Generic Credential"
4. Name: `Slack Signing Secret`
   - Value: `$SLACK_SIGNING_SECRET` (get value from `/home/biulatech/n8n/.env`)

---

## Phase 2 — Slack ↔ Ollama Integration 🔄
Wire slash commands and mentions to actual AI personality responses.

| Item | Status | Notes |
|------|--------|-------|
| `/ai` → Ollama API call | ✅ | Async: ack → Ollama → response_url |
| Personality routing by channel | ✅ | #counsel-kevin → kevin:latest |
| Personality routing by text prefix | ✅ | `/ai kevin: <text>` → kevin |
| Response posted back to Slack | ✅ | Via response_url or chat.postMessage |
| App mention handler | ✅ | @ai-workers in channel → route to personality → thread reply |
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

## Phase 3 — Slash Command Workflows ✅ / 🔄
Dedicated handlers for each slash command beyond `/ai`.

| Command | Workflow | What it does |
|---------|----------|-------------|
| `/ai-status` | slack-status-handler | ✅ Checks Ollama, n8n; posts to cmd channel + #ops-status |
| `/ai-diagnose` | slack-diagnose-handler | ✅ 5 health checks; posts full report |
| `/news [topic]` | news-article-generator | ✅ RSS fetch → Ollama summary → Slack |
| `/pm [task]` | linear-ai-project-manager | ✅ Ollama classify → Linear issue → Slack confirm |
| `/3d [desc]` | 3d-cad-generator | ✅ OpenSCAD → STL + preview image |
| `/patent [desc]` | patent-spec-generator | ✅ Ollama → patent spec document |
| `/image [prompt]` | comfyui-text-to-image | 🔄 ComfyUI models downloading |
| `/video [prompt]` | comfyui-text-to-video | 🔄 ComfyUI models downloading |
| `/enhance [url]` | comfyui-image-enhance | 🔄 ComfyUI models downloading |

### `/ai-status` implementation plan
1. Webhook → ack immediately
2. HTTP Request to Ollama: `GET host.docker.internal:11434/api/tags`
3. HTTP Request to n8n own health: `GET localhost:5678/healthz`
4. Bash via Execute Command: `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits`
5. Compose status message → post to `#ops-status` via Slack API

---

## Phase 4 — Ops Automation ✅ / 🔄
Proactive monitoring, alerts, and digests without human triggering.

| Item | Status | Notes |
|------|--------|-------|
| Hourly status post → #ops-status | 🔲 | n8n Schedule trigger (future) |
| Daily digest → #ops-digest | ✅ | Weekdays 9am ET — system health + Kevin quote |
| GPU overload alert → #ops-alerts | ✅ | ops-gpu-alert workflow active |
| Service-down alert → #ops-alerts | ✅ | ops-service-monitor workflow active |
| Commit notifications → #ops-updates | ✅ | github-push-handler workflow active |
| Grafana + Prometheus monitoring | ✅ | Dashboards, blackbox probes, GPU exporter |
| Weekly news digest | ✅ | Every Monday 8am → 3 RSS feeds → Ollama → Slack |

### GitHub webhook for #ops-updates
1. GitHub repo → Settings → Webhooks → Add webhook
2. Payload URL: `https://appendicular-wilson-looser.ngrok-free.dev/webhook/github-push`
3. Content type: `application/json`
4. Events: Pushes
5. n8n workflow: receives push → formats commit summary → posts to #ops-updates

---

## Phase 5 — Task Management Integration ✅ / 🔄
`#tasks-*` channels become structured agent task queues.

| Item | Status | Notes |
|------|--------|-------|
| Linear integration | ✅ | Task/project management via cloud API |
| #tasks-* → Linear issue creation | ✅ | n8n linear-ai-project-manager workflow |
| Agent processes task → updates issue | 🔲 | |
| Completion → post to #gen-* | 🔲 | Result artifact posted to appropriate gen channel |

### Task message format (in #tasks-kevin)
```
TASK: Design the database schema for the user auth service
CONTEXT: We're using PostgreSQL, need to support OAuth and email/password
PRIORITY: high
```
→ n8n creates Linear issue, assigns to Kevin, calls Ollama, posts result + closes issue

---

## Phase 6 — Generative Output Feeds 🔲
Auto-populate `#studio-*` channels with agent outputs.

| Channel | Source | Trigger |
|---------|--------|---------|
| #studio-canvas | ComfyUI | /image command |
| #studio-reels | ComfyUI | /video command |
| #studio-blueprint | Kevin | Architecture task completion |
| #studio-forge | Jason | Code task completion |
| #studio-quill | Scaachi | Content task completion |

---

## Phase 7 — Domain & Production Hardening ⏳
Move from ngrok free tier to proper domain.

| Item | Status | Notes |
|------|--------|-------|
| n8n.biulatech.com CNAME in Wix DNS | ⏳ | Wix: Manage Domain → DNS Records |
| Cloudflare proxy for n8n subdomain | ⏳ | See ADR-016 |
| n8n behind reverse proxy (caddy/nginx) | ⏳ | TLS termination |
| n8n auth enabled | ⏳ | N8N_BASIC_AUTH_ACTIVE=true |
| Automated backups (n8n_data, .env) | ⏳ | Cron → rclone → cloud |
| Monitoring: Grafana + Prometheus | ✅ | Service health, GPU, CPU, RAM — already deployed |

---

## Configuration Status

### In Slack (api.slack.com/apps → ai-workers):
- [x] ✅ Event Subscriptions: On, URL verified, `message.channels` + `app_mention` bot events saved
- [x] ✅ All 11 slash commands registered: /ai, /ai-status, /ai-draw, /ai-diagnose, /image, /video, /enhance, /news, /pm, /3d, /patent

### In n8n (localhost:5678):
- [x] ✅ Slack Bot Token Header Auth credential configured
- [x] ✅ Slack Signing Secret credential configured
- [x] ✅ Slack Command Handler active at `/webhook/slack-command`
- [x] ✅ Slack Events Receiver active at `/webhook/slack-events`

### In Open WebUI (localhost:8080):
- [x] ✅ All 5 personalities at 14.8B (Qwen3 14B) confirmed in model picker (2026-03-18)
- [x] ✅ nomic-embed-text available for embeddings
- [ ] Set a default model (kevin or chidi recommended)

### In Wix (manage.wix.com) — optional, future prep:
- [ ] Go to Manage Domain → DNS Records
- [ ] Note whether you can add a CNAME record for `n8n` subdomain
  (This is the migration path to n8n.biulatech.com — no rush, just note the UI)

---

## Session Progress Log

| Date | Completed |
|------|-----------|
| 2026-03-11 | Infrastructure, ngrok, personalities, Slack channels, slash commands, /ai → Ollama working, /ai-status working, dual-channel ops posting |
| 2026-03-11 | Fixed events receiver IF node bug (Code+Switch routing), @ai-workers mentions now route to correct personality and reply in thread, /ai-diagnose workflow built, ops-daily-digest workflow built |
| 2026-03-12 | Council deliberation engine (sequential, thread-aware), Grafana dashboard, Weekly News Digest, Linear AI PM, /pm command, systemd overrides (Ollama, ngrok, GPU exporter) |
| 2026-03-13 | /3d and /patent commands, 3D CAD Generator, Patent Spec Generator, timeout fixes, Prometheus n8n exporter |
| 2026-03-18 | Model swap: all 5 agents → Qwen3 14B Q4_K_M (9.3 GB, ~66 tok/s vs 2-5 tok/s). n8n restored from wrong compose; restart-n8n.sh created. Git cleanup (removed SQLite/STL binaries, redundant docs). Created DISASTER-RECOVERY.md + MODEL-GUIDE.md. Updated TROUBLESHOOTING.md, USER-GUIDE.md, architecture.md, ROADMAP.md, SESSION_CONTEXT.md. Confirmed: all 11 Slack commands registered, Event Subscriptions verified, Open WebUI showing all 5 agents at 14.8B. ComfyUI model download initiated. |
