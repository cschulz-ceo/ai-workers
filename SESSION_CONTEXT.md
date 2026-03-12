# Biulatech AI Workers — Session Context File
**Last updated:** 2026-03-12
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
| Ollama | 11434 | **127.0.0.1 ONLY** | ✅ Running | ⚠️ Must change to 0.0.0.0 — see Blockers |
| Open WebUI | 8080 | 0.0.0.0 | ✅ Running | Chat UI for Ollama |
| ComfyUI | 8188 | 0.0.0.0 | ✅ Running | Image/video gen — no model checkpoints yet |
| Grafana | 3001 | 0.0.0.0 | ✅ Running | v12.4.1, monitoring hub |
| Prometheus | 9090 | 0.0.0.0 | ✅ Running | Metrics backend |
| ngrok | 4040 | **127.0.0.1 ONLY** | ✅ Running | ⚠️ Web UI not reachable by Docker containers |

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

### Active (11)

| Workflow | ID | Last Updated | Function |
|----------|----|-------------|----------|
| GitHub Push Handler | ZWma6DaWSwTdvft8 | 2026-03-11 | GitHub webhook → format commit → #ops-updates |
| Linear AI Project Manager | linear-pm-001 | **2026-03-12** | /pm → Ollama classify → Linear issue → Slack confirm |
| Ops Daily Digest | IBYZgfl7Du9jTWp6 | 2026-03-11 | Weekdays 9am → kevin quote → #ops-digest |
| Ops Service Monitor | hKRONxaLSsSfVjO4 | 2026-03-11 | Scheduled health checks → #ops-alerts |
| Slack Command Handler v2 | VqmllB5WdHsKmntj | **2026-03-12** | Routes /ai /image /video /enhance /news /pm |
| Slack Diagnose Handler | QCrmHKpu1KktTK1M | 2026-03-11 | /ai-diagnose → 5 health checks → report |
| Slack Events Receiver | f5rTNCSNGXwKiwvE | 2026-03-11 | app_mention events → personality → thread reply |
| Slack Status Handler | KxnpgKyTLMAd4Ygs | 2026-03-11 | /ai-status → health check → #ops-status |
| Tasks Channel Handler | i1TOhKVyXkLXD01W | 2026-03-11 | #tasks-* messages → Linear issue creation |
| The Council — Unified Counsel Router | counsel-router-001 | **2026-03-12** | #the-council → sequential 4-member deliberation |
| Weekly News Digest | d7350619-528b-... | **2026-03-12** | Every Monday 8am → 3 RSS feeds → Ollama → Slack |

### Inactive (4) — Awaiting ComfyUI models

| Workflow | ID | Blocker |
|----------|----|---------|
| ComfyUI Text to Image | comfyui-t2i-001 | No checkpoint in `/home/biulatech/ComfyUI/models/checkpoints/` |
| ComfyUI Text to Video | comfyui-t2v-001 | Same |
| ComfyUI Image Enhance | comfyui-enh-001 | Same |
| News Article Generator | cf2282e0-c226-... | Not activated; depends on `news-search` webhook path |

---

## Slash Commands

| Command | Status | Blocked By |
|---------|--------|-----------|
| `/ai [agent:] text` | ✅ Working | — |
| `/ai-status` | ✅ Working | — |
| `/ai-diagnose` | ✅ Working | — |
| `/pm text` | ⚠️ Wired | Ollama binding + model name mismatch |
| `/image prompt` | ❌ Broken | ComfyUI no models |
| `/video prompt` | ❌ Broken | ComfyUI no models |
| `/enhance url` | ❌ Broken | ComfyUI no models |
| `/news [topic]` | ❌ Broken | News Article Generator inactive |

---

## The Council — Architecture (Rebuilt 2026-03-12)

- **Trigger:** Any message in `#the-council` (C0AKVJ5PHHR)
- **Engine:** Single `Council Deliberation Engine` Code node (sequential for loop)
- **Stagger:** 4 seconds between each member response
- **Thread-aware:** Each member after the first calls `conversations.replies` to read prior responses before generating their own
- **Member order:** christian → kevin → jason → scaachi
- **Auth:** `$env.SLACK_BOT_TOKEN`
- **Ollama endpoint:** `http://host.docker.internal:11434/api/chat` (blocked until Ollama binding fix)

---

## Grafana Dashboard

- URL: `http://localhost:3001` — login: `admin` / `biulatech`
- Dashboard: `ai-workers-hub` (UID: `biulatech-ai-hub`)
- File: `/home/biulatech/monitoring/grafana/dashboards/ai-workers-hub.json`
- Panels: n8n ✅, Ollama ⬇️ (binding), Open WebUI ✅, ComfyUI ✅, ngrok ⬇️ (binding)
- Live: CPU%, RAM, Disk, Uptime, Service Uptime timeseries, Quick Links

---

## Critical Blockers (User Action Required)

### 1. 🔴 Ollama binding — blocks Weekly News Digest, Linear PM, Council
**Fix (Pop!_OS — systemd drop-in override):**
```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo cp configs/systemd/ollama.service.d/override.conf /etc/systemd/system/ollama.service.d/
sudo systemctl daemon-reload && sudo systemctl restart ollama
ss -tlnp | grep 11434  # Must show 0.0.0.0:11434
```
The override.conf sets `OLLAMA_HOST=0.0.0.0`. See ADR-011 in decisions.md for why we use a drop-in (Ollama upgrades overwrite the base unit).
After this, Weekly News Digest and /pm will work; Grafana Ollama probe will go green.

### 2. 🟠 Linear PM model name mismatch
**Problem:** Workflow calls `llama3.1:70b` but Ollama has `llama3.1:70b-instruct-q5_K_M`.
**Fix (quickest — create alias):**
```bash
ollama cp llama3.1:70b-instruct-q5_K_M llama3.1:70b
```

### 3. 🟡 ngrok web UI binding — affects Grafana probe only
Config already updated at `~/.config/ngrok/ngrok.yml` with `web_addr: "0.0.0.0:4040"`.
**Fix:** Restart ngrok (kill + relaunch, or use ngrok dashboard).

### 4. 🟡 ComfyUI — no model checkpoints
**Fix:** Download a Stable Diffusion or FLUX checkpoint to `/home/biulatech/ComfyUI/models/checkpoints/`, then activate the 3 ComfyUI n8n workflows.

### 5. 🟡 n8n API key (Grafana integration)
Key was added to database, needs n8n restart to take effect.
**Fix:** `cd ~/n8n && docker compose restart`

---

## Roadmap Status

| Phase | Name | Status |
|-------|------|--------|
| 0 | Foundation | ✅ Complete |
| 1 | Slack Integration | ✅ Complete |
| 2 | Slack ↔ Ollama | ✅ Complete |
| 3 | Slash Commands | 🔄 Partial (/image /video broken) |
| 4 | Ops Automation | 🔄 Partial (GPU alerts missing) |
| 5 | Task Management | 🔄 Partial (agent→issue update loop missing) |
| 6 | Generative Output Feeds | ❌ Blocked (ComfyUI no models) |
| 7 | Domain Hardening | ⏳ Future |

---

## Pending Work

- [ ] **Fix Ollama binding** → enables Council, Weekly Digest, /pm, Linear PM
- [ ] **Fix Linear PM model name** → `ollama cp llama3.1:70b-instruct-q5_K_M llama3.1:70b`
- [ ] **Download ComfyUI checkpoint** → enables /image /video /enhance
- [ ] **Activate ComfyUI n8n workflows** (3 workflows: t2i, t2v, enhance)
- [ ] **Test /pm end-to-end** after Ollama fix
- [ ] **Test Weekly News Digest** after Ollama fix (re-run Execute workflow in n8n)
- [ ] **Agent → Linear update loop** — agent completes task → updates Linear issue → posts to #studio-blueprint / #studio-forge / #studio-quill
- [ ] **GPU utilization alerts** → #ops-alerts (threshold: >90% for 5 min)
- [ ] **Export n8n workflows to git** — `ai-workers-1/workflows/` has old stubs; export current workflows
- [ ] **Domain setup** — n8n.biulatech.com (biulatech.com on Wix; see ADR-015 for migration path)
- [ ] **Automated backups** — n8n_data SQLite + .env → cloud storage
- [ ] **Streaming responses** — chunk long Ollama outputs into multiple Slack messages
- [ ] **Clean up ai-workers-1** — duplicate repo at `/home/biulatech/ai-workers-1`

---

## Key File Paths

| What | Path |
|------|------|
| n8n env (all secrets + channel IDs) | `/home/biulatech/n8n/.env` |
| n8n Docker compose | `/home/biulatech/n8n/docker-compose.yml` |
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
