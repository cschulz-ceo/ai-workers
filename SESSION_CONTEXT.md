# Biulatech AI Workers — Session Context File
**Last updated:** 2026-03-12 (session 4)
**Purpose:** Context retention across Claude sessions. Update this file at the end of each working session.

---

## System Identity

| Field | Value |
|-------|-------|
| Host | pop-os · LAN IP: 192.168.110.104 |
| Hardware | Ryzen 9 9950X · RTX 5070 Ti · 64 GB DDR5 · 2 TB NVMe |
| OS | Pop!_OS (NVIDIA driver 570+, CUDA enabled) |
| Git Repo | `cschulz-ceo/ai-workers` (private, SSH auth) |
| Local path | `/home/biulatech/ai-workers-1` |
| Slack workspace | Biula Tech (T0AKQL4FZMX) |
| ngrok tunnel | `https://appendicular-wilson-looser.ngrok-free.dev` |
| Linear | Cloud-hosted, API key in `~/n8n/.env` as `LINEAR_API_KEY` |

---

## Service Map & Current Status

| Service | Port | Binding | Status | Notes |
|---------|------|---------|--------|-------|
| n8n | 5678 | 0.0.0.0 | ✅ Running | Workflow orchestrator (Docker on Pop!_OS) |
| Ollama | 11434 | **0.0.0.0** | ✅ Running | systemd override applied — Council, /pm, Digest unblocked |
| Open WebUI | 8080 | 0.0.0.0 | ✅ Running | Chat UI for Ollama |
| ComfyUI | 8188 | 0.0.0.0 | ✅ Running | Image/video gen — no model checkpoints yet |
| Grafana | 3001 | 0.0.0.0 | ✅ Running | v12.4.1, monitoring hub |
| Prometheus | 9090 | 0.0.0.0 | ✅ Running | Metrics backend + GPU exporter on :9835 |
| ngrok | 4040 | **0.0.0.0** | ✅ Running | systemd service, web UI reachable by Docker |
| GPU exporter | 9835 | 0.0.0.0 | ✅ Running | NVIDIA metrics → Prometheus |

**Critical networking note:** n8n runs inside Docker. Docker containers use `host.docker.internal` (resolves to Docker bridge gateway, NOT 127.0.0.1) to reach the Pop!_OS host. Ollama must bind to `0.0.0.0` for this to work.

---

## Ollama Models

| Model | Size | Used By |
|-------|------|---------|
| kevin:latest | 21 GB | /ai default, Council, Ops Digest, Diagnose |
| jason:latest | 21 GB | Council, /ai jason: prefix |
| scaachi:latest | 46 GB | Council, /ai scaachi: prefix |
| christian:latest | 21 GB | Council, /ai christian: prefix |
| chidi:latest | 21 GB | Council, /ai chidi: prefix |
| llama3.1:70b-instruct-q5_K_M | 46 GB | ⚠️ Linear PM uses `llama3.1:70b` (name mismatch — needs alias or fix) |
| qwen2.5:32b-instruct-q5_K_M | 21 GB | Available, not wired |
| qwen2.5-coder:32b-instruct-q5_K_M | 21 GB | Available, not wired |
| nomic-embed-text:latest | ~300 MB | Open WebUI embeddings |

---

## n8n Workflows — Full Inventory

### Active (13)

| Workflow | ID | Last Updated | Function |
|----------|----|-------------|----------|
| GitHub Push Handler | ZWma6DaWSwTdvft8 | 2026-03-11 | GitHub webhook → format commit → #ops-updates |
| Linear AI Project Manager | linear-pm-001 | **2026-03-12** | /pm → Ollama classify → Linear issue → Slack confirm |
| News Article Generator | cf2282e0-c226-... | **2026-03-12** | /news → RSS fetch → Ollama summary → #ops-intel |
| Ops Daily Digest | IBYZgfl7Du9jTWp6 | 2026-03-11 | Weekdays 9am → kevin quote → #ops-digest |
| Ops GPU Alert Handler | (live in n8n) | **2026-03-12** | GPU webhook → format alert → #ops-alerts |
| Ops Service Monitor | hKRONxaLSsSfVjO4 | 2026-03-11 | Scheduled health checks → #ops-alerts |
| Slack Command Handler v2 | VqmllB5WdHsKmntj | **2026-03-12** | Routes /ai /image /video /enhance /news /pm |
| Slack Diagnose Handler | QCrmHKpu1KktTK1M | 2026-03-11 | /ai-diagnose → 5 health checks → report |
| Slack Events Receiver | f5rTNCSNGXwKiwvE | **2026-03-12** | app_mention + #the-council + TASK: → route → reply/council/task-handler |
| Slack Status Handler | KxnpgKyTLMAd4Ygs | 2026-03-11 | /ai-status → health check → #ops-status |
| Tasks Channel Handler | i1TOhKVyXkLXD01W | 2026-03-11 | #tasks-* messages → Linear issue creation |
| The Council — Unified Counsel Router | counsel-router-001 | **2026-03-12** | #the-council → sequential 4-member deliberation ✅ TESTED |
| Weekly News Digest | d7350619-528b-... | **2026-03-12** | Every Monday 8am → 3 RSS feeds → Ollama → Slack |

### Inactive (3) — Awaiting ComfyUI models

| Workflow | ID | Blocker |
|----------|----|---------|
| ComfyUI Text to Image | comfyui-t2i-001 | No checkpoint in `/home/biulatech/ComfyUI/models/checkpoints/` |
| ComfyUI Text to Video | comfyui-t2v-001 | Same |
| ComfyUI Image Enhance | comfyui-enh-001 | Same |

---

## Slash Commands

| Command | Status | Blocked By |
|---------|--------|-----------|
| `/ai [agent:] text` | ✅ Working | — |
| `/ai-status` | ✅ Working | — |
| `/ai-diagnose` | ✅ Working | — |
| `/pm text` | ⚠️ Likely working | Model name mismatch: `llama3.1:70b` vs `llama3.1:70b-instruct-q5_K_M` — create alias to confirm |
| `/image prompt` | ❌ Broken | ComfyUI no models |
| `/video prompt` | ❌ Broken | ComfyUI no models |
| `/enhance url` | ❌ Broken | ComfyUI no models |
| `/news [topic]` | ✅ Working | Fixed 2026-03-12 (responseMode, Post to Slack URL, auth header) |

---

## The Council — Architecture (Working as of 2026-03-12)

- **Trigger:** Any human message in `#the-council` (C0AKVJ5PHHR) → Slack Events Receiver → `/webhook/the-council`
- **Engine:** Single `Council Deliberation Engine` Code node (sequential for loop)
- **Stagger:** 4 seconds between each member response
- **Thread-aware:** Each member after the first calls `conversations.replies` to read prior responses before generating their own
- **Member order:** christian → kevin → jason → scaachi
- **Auth:** Config Set node → `$('Config').first().json.slackToken` (JS Task Runner blocks `$env` in Code nodes; Set node expressions run in main process and have $env access)
- **HTTP:** Uses `require('https')` + `require('url')` based helper (fetch and $helpers not available in task runner sandbox). Requires `NODE_FUNCTION_ALLOW_BUILTIN=*` in docker-compose.
- **Ollama endpoint:** `http://host.docker.internal:11434/api/chat` ✅ Working (Ollama binding fixed)
- **Tested:** 2026-03-12 — Chidi responded to question in #the-council ✅

---

## Grafana Dashboard

- URL: `http://localhost:3001` — login: `admin` / `biulatech`
- Dashboard: `ai-workers-hub` (UID: `biulatech-ai-hub`)
- File: `/home/biulatech/monitoring/grafana/dashboards/ai-workers-hub.json`
- Panels: n8n ✅, Ollama ✅ (fixed), Open WebUI ✅, ComfyUI ✅, ngrok ✅ (fixed), GPU exporter ✅
- Live: CPU%, RAM, Disk, Uptime, Service Uptime timeseries, Quick Links

---

## Current Blockers

### 1. 🟡 ComfyUI — no model checkpoints
**Fix:** Run the existing download script (FLUX.1-schnell, ~20GB, use tmux):
```bash
tmux new-session -d -s comfyui-dl 'bash /home/biulatech/ai-workers-1/scripts/download-comfyui-models.sh 2>&1 | tee /tmp/comfyui-dl.log'
```
After download completes, activate the 3 ComfyUI n8n workflows (t2i, t2v, enhance) in the n8n UI.

### 2. 🟡 n8n workflow credentials
8 workflow JSON exports show `CONFIGURE_IN_N8N_CREDENTIALS` placeholder for Slack bot token.
**Fix:** n8n UI → Credentials → update "Slack Bot Token" with the rotated token from `~/n8n/.env`.

### ✅ Previously resolved
- Ollama binding: `0.0.0.0:11434` — systemd override applied 2026-03-12
- ngrok web UI: `0.0.0.0:4040` — systemd service installed 2026-03-12, config indentation fixed
- GPU exporter: running on `0.0.0.0:9835` — Prometheus scraping
- Slack credentials: rotated + purged from git history 2026-03-12
- n8n API key: activated (n8n restarted 2026-03-12)
- The Council end-to-end: routing fixed (Slack Events Receiver → /webhook/the-council), JS Task Runner sandbox workarounds applied, `NODE_FUNCTION_ALLOW_BUILTIN=*` added — tested 2026-03-12 ✅
- Webhook validation: 10/10 paths returning 200/202 as of 2026-03-12 ✅
- News Article Generator: activated and fixed (responseMode, Post to Slack URL, auth) 2026-03-12 ✅
- All active workflows exported to git: `services/n8n/workflows/` — 2026-03-12 ✅
- docker-compose.yml added to repo: `services/n8n/docker-compose.yml` — 2026-03-12 ✅
- Agent → Linear update loop: wired — TASK: messages in #tasks-* → Events Receiver → /webhook/slack-tasks → full Ollama+Linear+studio pipeline ✅ (2026-03-12)
- jason.Modelfile path corrected: ~/ai-workers → ~/ai-workers-1, re-pushed to Ollama ✅
- llama3.1:70b alias: confirmed present (same digest as full model name) ✅
- Backup cron + export cron: confirmed in crontab (3am backup, 2am export) ✅
- Stale top-level workflows/ stubs retired; canonical location is services/n8n/workflows/ ✅

---

## Roadmap Status

| Phase | Name | Status |
|-------|------|--------|
| 0 | Foundation | ✅ Complete |
| 1 | Slack Integration | ✅ Complete |
| 2 | Slack ↔ Ollama | ✅ Complete |
| 3 | Slash Commands | 🔄 Partial (/image /video /enhance blocked by ComfyUI) |
| 4 | Ops Automation | 🔄 Partial (GPU exporter ✅, Grafana alert rule pending) |
| 5 | Task Management | 🔄 Partial (agent→issue update loop missing) |
| 6 | Generative Output Feeds | ❌ Blocked (ComfyUI no models) |
| 7 | Domain Hardening | ⏳ Future |

---

## Pending Work

- [ ] **Download ComfyUI checkpoint** → enables /image /video /enhance (`scripts/download-comfyui-models.sh`)
- [ ] **Activate ComfyUI n8n workflows** (3 workflows: t2i, t2v, enhance) — after model download
- [ ] **Test /pm end-to-end** — run `/pm Create test issue` in Slack → expect Linear issue + Slack confirm
- [ ] **Test Tasks Channel Handler** — post `TASK: [task]` in #tasks-kevin → expect Ollama → Linear issue → #studio-blueprint + thread reply
- [ ] **Test Weekly News Digest** — re-trigger in n8n UI, verify Slack post in #ops-digest
- [ ] **Install sqlite3** — `sudo apt install sqlite3` → enables full SQLite backup in `backup-n8n.sh`
- [ ] **Add Grafana alert rule** for GPU >90% → n8n webhook → #ops-alerts (Grafana UI only)
- [ ] **Update n8n credentials** — workflows show `CONFIGURE_IN_N8N_CREDENTIALS` for bot token (n8n UI → Credentials)
- [ ] **Download ComfyUI checkpoint** → enables /image /video /enhance (`scripts/download-comfyui-models.sh`)
- [ ] **Activate ComfyUI n8n workflows** (3 workflows: t2i, t2v, enhance) — after model download
- [ ] **Domain setup** — n8n.biulatech.com (biulatech.com on Wix; see ADR-016 for migration path)
- [ ] **Merge worktree branch** → `claude/admiring-yonath` → main

---

## Key File Paths

| What | Path |
|------|------|
| n8n env (all secrets + channel IDs) | `/home/biulatech/n8n/.env` |
| n8n Docker compose (live) | `/home/biulatech/n8n/docker-compose.yml` |
| n8n Docker compose (git) | `/home/biulatech/ai-workers-1/services/n8n/docker-compose.yml` |
| n8n SQLite database (all workflows) | `/home/biulatech/n8n/n8n_data/database.sqlite` |
| Monitoring Docker compose | `/home/biulatech/monitoring/docker-compose.yml` |
| Grafana dashboard JSON | `/home/biulatech/monitoring/grafana/dashboards/ai-workers-hub.json` |
| Prometheus config | `/home/biulatech/monitoring/prometheus/prometheus.yml` |
| ngrok config | `/home/biulatech/.config/ngrok/ngrok.yml` |
| Agent Modelfiles | `/home/biulatech/ai-workers-1/agents/personalities/` |
| Git repo | `/home/biulatech/ai-workers-1/` |
| Decisions log (ADRs) | `/home/biulatech/ai-workers-1/decisions.md` |
| Roadmap | `/home/biulatech/ai-workers-1/ROADMAP.md` |
| This file | `/home/biulatech/ai-workers-1/SESSION_CONTEXT.md` |

---

## Session Log

| Date | Work Done |
|------|-----------|
| 2026-03-11 | Infrastructure, ngrok, personalities, Slack channels, slash commands, /ai → Ollama, /ai-status, dual-channel ops posting, events receiver, /ai-diagnose, daily digest, GitHub push handler, Linear integration (replaced Plane), council router |
| 2026-03-12 | Rebuilt Council deliberation (sequential engine, thread-aware). Set up Grafana dashboard. Activated Weekly News Digest. Activated Linear AI Project Manager. Added /pm to Slack Command Handler. Identified: Ollama 127.0.0.1 binding is the primary blocker. |
| 2026-03-12 | Created systemd units for Ollama override (OLLAMA_HOST=0.0.0.0), ngrok, gpu-exporter. Added GPU Prometheus exporter script, backup-n8n.sh, export-workflows.sh. Fixed Mac→Pop!_OS inaccuracies in docs. Scrubbed credentials from ROADMAP.md. Added ADR-011 (Ollama systemd strategy). Standardized studio-* channel naming. Updated decisions.md. |
| 2026-03-12 | Validated all 10 webhook paths (10/10 passing). Fixed news-article-generator (responseMode, continueOnFail, Post to Slack URL + auth). Added Slack Events Receiver → #the-council routing (Switch Route + Ack Council + Forward to Council nodes). Fixed Council JS Task Runner sandbox issues: Config Set node for $env workaround, replaced $helpers/fetch with require('https') helper, added NODE_FUNCTION_ALLOW_BUILTIN=* to docker-compose. Tested The Council end-to-end — Chidi responded in #the-council ✅. Exported all active workflows + docker-compose to git. |
| 2026-03-12 | Re-evaluated plan against actual repo state. Fixed jason.Modelfile path (~/ai-workers → ~/ai-workers-1), retired stale top-level workflows/ stubs (3 JSON files), added services/n8n/workflows/README.md. Confirmed llama3.1:70b alias + backup/export crons already present. Wired agent→Linear update loop: updated Slack Events Receiver to route TASK: messages in #tasks-* to Tasks Channel Handler (/webhook/slack-tasks) via new Switch[4] → Ack Task → Forward to Tasks nodes. Tasks Channel Handler already had complete Ollama+Linear+studio flow. |
