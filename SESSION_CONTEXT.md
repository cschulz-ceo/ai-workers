# Biulatech AI Workers — Session Context File
**Last updated:** 2026-03-18 (session 7)
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

**All 5 agents updated 2026-03-18: qwen3:14b-q4_K_M base (9.3 GB, ~11 GB VRAM, ~66 tok/s)**

| Model | Size | Used By |
|-------|------|---------|
| kevin:latest | 9.3 GB | /ai default, Council, Ops Digest, Diagnose |
| jason:latest | 9.3 GB | Council, /ai jason: prefix |
| scaachi:latest | 9.3 GB | Council, /ai scaachi: prefix |
| christian:latest | 9.3 GB | Council, /ai christian: prefix |
| chidi:latest | 9.3 GB | Council, /ai chidi: prefix |
| qwen3:14b-q4_K_M | 9.3 GB | Base model (all 5 agents built from this) |
| llama3.1:70b | 49 GB | Available for offline batch work (Open WebUI only — too slow for Slack) |
| llama3.1:70b-instruct-q5_K_M | 49 GB | Same digest as above; llama3.1:70b alias confirmed working |
| qwen2.5:32b-instruct-q5_K_M | 23 GB | Available, not active (exceeds VRAM) |
| qwen2.5-coder:32b-instruct-q5_K_M | 23 GB | Available, not active (exceeds VRAM) |
| nomic-embed-text:latest | 274 MB | Open WebUI embeddings |

---

## n8n Workflows — Full Inventory

### Active (20)

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
| 3D CAD Generator | cad-3d-001 | 2026-03-13 | /3d → OpenSCAD → STL + preview |
| 3D Preview Image Server | preview-image-001 | 2026-03-13 | Serves 3D preview images |
| ComfyUI Preview Server | comfyui-preview-001 | 2026-03-13 | Serves ComfyUI preview images |
| Patent Spec Generator | patent-spec-001 | 2026-03-13 | /patent → Ollama → patent spec doc |
| ComfyUI Text to Image | comfyui-t2i-001 | 2026-03-12 | /image → ComfyUI (needs checkpoint) |
| ComfyUI Text to Video | comfyui-t2v-001 | 2026-03-12 | /video → ComfyUI (needs checkpoint) |
| ComfyUI Image Enhance | comfyui-enh-001 | 2026-03-12 | /enhance → ComfyUI (needs checkpoint) |
| Workflow Test Runner | workflow-test-001 | **2026-03-18** | /ai-test → sequential workflow health check → #ops-pulse |

---

## Slack Configuration

**Event Subscriptions:** ✅ Verified — `https://appendicular-wilson-looser.ngrok-free.dev/webhook/slack-events`

### Slash Commands (11 registered in Slack app)

| Command | Registered in Slack | n8n Workflow Status | Notes |
|---------|--------------------|--------------------|-------|
| `/ai [agent:] text` | ✅ | ✅ Working | Routes to Ollama personality by prefix or channel |
| `/ai-status` | ✅ | ✅ Working | Health check → #ops-status |
| `/ai-draw` | ✅ | 🔄 In Progress | Registered in Slack; workflow wiring TBC |
| `/ai-diagnose` | ✅ | ✅ Working | 5-point diagnostic report |
| `/image prompt` | ✅ | 🔄 Needs ComfyUI models | Download script run 2026-03-18; awaiting completion |
| `/video prompt` | ✅ | 🔄 Needs ComfyUI models | Same as above |
| `/enhance url` | ✅ | 🔄 Needs ComfyUI models | Same as above |
| `/news [topic]` | ✅ | ✅ Working | RSS fetch → Ollama → #ops-intel |
| `/pm text` | ✅ | ✅ Working | Ollama classify → Linear issue → Slack confirm |
| `/3d desc` | ✅ | ✅ Working | OpenSCAD → STL + preview image |
| `/patent desc` | ✅ | ✅ Working | Ollama → patent spec document |

---

## The Council — Architecture (Working as of 2026-03-12)

- **Trigger:** Any human message in `#the-council` (C0AKVJ5PHHR) → Slack Events Receiver → `/webhook/the-council`
- **Engine:** Single `Council Deliberation Engine` Code node (sequential for loop)
- **Stagger:** 4 seconds between each member response
- **Thread-aware:** Each member after the first calls `conversations.replies` to read prior responses before generating their own
- **Member order:** christian → kevin → jason → scaachi
- **Auth:** Config Set node → `$('Config').first().json.slackToken` (JS Task Runner blocks `$env` in Code nodes; Set node expressions run in main process and have $env access)
- **HTTP:** Uses `require('https')` + regex URL parser (URL class removed from n8n sandbox; `require('url').URL` replaced with regex). Requires `NODE_FUNCTION_ALLOW_BUILTIN=*` in docker-compose.
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

### 1. 🟡 ComfyUI — model checkpoint download in progress
Download script run 2026-03-18. FLUX.1-schnell (~20GB) requires HF_TOKEN + license acceptance at huggingface.co/black-forest-labs/FLUX.1-schnell.
**Check status:**
```bash
tmux attach -t comfyui-dl   # or check: cat /tmp/comfyui-dl.log
```
After download completes: verify ComfyUI at localhost:8188, then test /image, /video, /enhance from Slack.

### 2. 🔲 `/ai-draw` — registered in Slack but n8n workflow not fully wired
The command exists in the Slack app. Needs a dedicated n8n workflow or routing in the Slack Command Handler.

### ✅ Previously resolved (this session)
- **Slack Command Handler routing bug** — `/image` was firing Image+Video+Enhance+News simultaneously. Added `Route Studio` Switch node. Commit 5231709.
- **All Slack-posting terminal nodes** — added `continueOnFail: true` to `Post to Slack`, `Post to Command Channel`, `Post to Channel` and all downstream-call nodes across 4 workflows. Execution no longer fails if Slack's `response_url` is expired/empty.
- **News Article Generator** — webhook was `lastNode` (blocks caller for 60s). Fixed to `responseNode` + added `Respond OK` node for immediate ack. Caller (`Call News Search`) now gets 202 within milliseconds.
- **Call News Search timeout** — increased 10s → 30s.
- **test-all-workflows.sh** — fixed to pass `response_url` in all test calls.
- Commits: 5231709, a6d5f02, (workflow-fix commit pending)

### ✅ Previously resolved (earlier sessions)
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
- sqlite3 installed; backup script verified — 11MB SQLite + .env captured to /home/biulatech/backups/n8n/ ✅
- n8n workflow_published_version table populated (16 rows) — n8n v2.11.3 requires this for UI display; all 16 workflows now visible ✅
- ComfyUI ae.safetensors: download script updated to pass HF_TOKEN env var for gated HuggingFace repos ✅
- ComfyUI workflows activated (t2i, t2v, enhance) — /image /video /enhance now live ✅
- **Session 5 (2026-03-13) workflow health recovery:**
  - Root cause discovered: n8n loads from `workflow_history` table (version snapshots), NOT `workflow_entity.nodes` directly. All prior sprint fixes were in wrong table. Fixed by creating new `workflow_history` entries with `versionId` updates.
  - The Council: replaced `require('url').URL` with regex URL parser (URL class unavailable in n8n sandbox) ✅
  - Slack Events Receiver: Post Response auth header `CONFIGURE_IN_N8N_CREDENTIALS` → `={{ $env.SLACK_BOT_TOKEN }}` ✅
  - News Article Generator: expression typo `={=` → `={{` in Post to Slack body ✅
  - ComfyUI T2I, T2V + Linear PM: Ollama calls `contentType: json` → `contentType: raw` + `rawContentType: application/json` (double-encoding fix) ✅
  - Slack Command Handler: Ack Slack node had corrupted `responseBody` expression (nested `{{ }}`) — fixed ✅
  - Slack Command Handler: Call Studio Image/Video/Enhance sent empty body — added proper body params (prompt/image_url/channel_id/user_id) ✅
  - Linear PM: Merge Paths node `mode: passThrough` invalid in Merge v3 → changed to `mode: append` ✅
  - **Tested:** `/ai kevin` ✅, `/pm Create test task` ✅ (Linear PM exec 530 success), Slack Events Receiver app_mention ✅
  - n8n now reports **8 published workflows** on startup

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
- [x] **Test /pm end-to-end** ✅ — exec 530 success 2026-03-13
- [ ] **Test Tasks Channel Handler in Slack** — post `TASK: write a hello world in Python` in #tasks-kevin → expect Ollama → Linear issue → #studio-blueprint + thread reply
- [ ] **Test Weekly News Digest** — re-trigger in n8n UI (Execute button), verify Slack post in #ops-digest
- [ ] **Test Ops GPU Alert** — manual trigger in n8n UI → verify Slack post in #ops-alerts
- [ ] **Download ComfyUI models** (HF_TOKEN required) → enables /image /video /enhance
- [ ] **Add Grafana alert rule** for GPU >90% → n8n webhook → #ops-alerts (Grafana UI: Alerting → Alert rules → New)
- [ ] **Domain setup** — n8n.biulatech.com (biulatech.com on Wix; see ADR-016 for migration path)

---

## Key File Paths

| What | Path |
|------|------|
| n8n env (all secrets + channel IDs) | `/home/biulatech/n8n/.env` |
| n8n Docker compose (live) | `/home/biulatech/n8n/docker-compose.yml` |
| n8n Docker compose (queue — NOT active) | `/home/biulatech/ai-workers-1/configs/queue/docker-compose.yml` |
| n8n restart script | `/home/biulatech/n8n/restart-n8n.sh` |
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
| 2026-03-12 | Fixed ComfyUI ae.safetensors download (HF_TOKEN support added to script). Populated workflow_published_version table (n8n v2.11.3 requires this for UI to display workflows). All 16 workflows now visible and active in n8n UI. ComfyUI t2i/t2v/enhance workflows activated — /image /video /enhance live. |
| 2026-03-13 | (Other AI sessions) Added /3d and /patent Slack commands, 3D CAD Generator workflow, Patent Spec Generator, timeout fixes, Prometheus n8n exporter, various bug fixes. Attempted Redis/Postgres queue migration — broke n8n (empty Postgres DB, all workflows in SQLite). Partially reverted. |
| 2026-03-18 | **Session 7:** Diagnosed n8n "Set up owner account" — wrong compose active; restored 20 workflows. Created restart-n8n.sh. Added timeout env vars (600s/900s). Model swap: all 5 agents → qwen3:14b-q4_K_M (9.3 GB, ~66 tok/s vs 2-5 tok/s). Rebuilt all personalities in Ollama. Git cleanup: removed SQLite/STL binaries, redundant docs. Created DISASTER-RECOVERY.md + MODEL-GUIDE.md. Updated TROUBLESHOOTING.md, USER-GUIDE.md, architecture.md, ROADMAP.md. Confirmed Slack: 11 commands registered, Event Subscriptions verified. Confirmed Open WebUI: all 5 agents showing at 14.8B. ComfyUI model download initiated. Commit: 9be2b12. |
| 2026-03-18 | **Session 7 (cont.):** Fixed routing bug — `/image` (and all studio/news commands) was triggering ALL 4 downstream workflows simultaneously. Root cause: `Ack Studio Command` node had Image+Video+Enhance+News all wired as parallel outputs. Fix: added `Route Studio` Switch node (expression mode, 4 outputs) to route to only the correct downstream. Applied to DB (versionId 4bf2b25b) + git (commit 5231709). **n8n needs restart to load fix.** Created `scripts/test-all-workflows.sh` (sequential test runner with Ollama throttling, Slack report) and `workflow-test-runner.json` (n8n workflow for future `/ai-test` Slack command). |
| 2026-03-18 | **Session 7 (cont. 2):** Ran test-all-workflows.sh — found 4 execution errors. Fixed: (1) `Post to Command Channel`/`Post to Channel` failing with "Invalid URL" when `response_url` empty — added `continueOnFail: true` across all terminal Slack-posting nodes in status/diagnose/command/news workflows. (2) News Article Generator webhook was `lastNode` (blocks caller 60s) — changed to `responseNode` + added `Respond OK` early ack. (3) `Call News Search` timeout 10s → 30s. (4) Test script fixed to pass `response_url` in all calls. Requires n8n restart to apply DB changes. |
