# AI Workers — System Review & Optimization Plan

**Biulatech | March 18, 2026**
*Prepared for Neil Schulz*

---

## Executive Summary

This report is a top-down review of the Biulatech AI Workers platform — a self-hosted AI agent system running on a Ryzen 9 9950X workstation with an RTX 5070 Ti GPU. The system orchestrates five AI personalities through Slack, powered by local Ollama models and coordinated by n8n workflows.

The platform is **ambitious and well-architected**, with 20 active n8n workflows, 5 distinct agent personalities, comprehensive monitoring, and deep Slack integration. However, there are three critical issues that need immediate attention:

1. **n8n is currently down** — running from the wrong Docker Compose file, showing a fresh setup screen instead of the 20 configured workflows. A restart script has been prepared.
2. **Models are too large for the GPU** — the 70B and 32B models (21–46 GB) far exceed the 16 GB VRAM, causing CPU offloading and 5+ minute response times. Switching to 14B models would deliver ~60x faster responses.
3. **Documentation has gaps** — while extensive docs exist, there is no single **runbook** for disaster recovery, no automated tests, and the queue-mode migration left artifacts that caused the current outage.

---

## Current State Assessment

### System Health Dashboard

| Service | Port | Status | Notes |
|---------|------|--------|-------|
| n8n | 5678 | **ISSUE** | Running but empty DB — needs restart |
| Ollama | 11434 | OK | Bound to 0.0.0.0 (fixed) |
| Open WebUI | 8080 | OK | Chat UI for Ollama |
| ComfyUI | 8188 | BLOCKED | No model checkpoints downloaded |
| Grafana | 3001 | OK | Monitoring dashboard working |
| Prometheus | 9090 | OK | Metrics collection active |
| ngrok | 4040 | OK | Slack webhook tunnel active |
| GPU Exporter | 9835 | OK | NVIDIA metrics to Prometheus |

### Workflow Inventory (20 Workflows)

All 20 workflows are stored in the SQLite database at `/home/biulatech/n8n/n8n_data/database.sqlite`. They are currently invisible in the n8n UI because the wrong Docker Compose file was used to start n8n. The fix is a single command (see Immediate Actions).

| Category | Count | Examples |
|----------|-------|----------|
| Slack Integration | 3 | Command Handler v2, Events Receiver, Diagnose Handler |
| AI Agent Tasks | 4 | Council Router, Linear PM, Tasks Channel Handler, Patent Spec |
| Content Generation | 3 | News Article Generator, Weekly Digest, 3D CAD Generator |
| Ops Automation | 4 | Daily Digest, Service Monitor, GPU Alert, Status Handler |
| ComfyUI (blocked) | 3 | Text to Image, Text to Video, Image Enhance |
| Infrastructure | 3 | GitHub Push Handler, Preview Servers (2) |

### What Went Wrong

During a session with another AI tool, three changes were made that caused the current issues:

- **A duplicate Docker Compose was created** at `services/n8n/docker-compose.yml`. This new file mapped a fresh, empty `n8n_data` directory instead of the original one containing all 20 workflows and credentials. When n8n restarted from this location, it created a brand-new 585 KB database instead of using the 18.5 MB original.

- **A Redis/Postgres queue migration was attempted** (at `configs/queue/docker-compose.yml`) to solve timeout issues. This changed the database backend from SQLite to PostgreSQL — but the new Postgres database was empty. The migration was partially reverted but left behind configuration artifacts.

- **Large binary files were committed to git** — including the 18.5 MB SQLite database, twelve STL 3D model files, and five auto-generated IMPLEMENTATION-COMPLETE docs. These have now been cleaned up and blocked by `.gitignore`.

---

## The Model Problem: Why Everything Is Slow

The RTX 5070 Ti has **16 GB of VRAM**. This is the single most important constraint in the system. When a model fits entirely in VRAM, it runs at hundreds of tokens per second. When it spills to system RAM, performance drops by 10–100x because data must shuttle across the PCIe bus instead of staying on the GPU.

### Current Models vs. VRAM

| Model | Size on Disk | VRAM Needed | Fits in 16 GB? | Speed |
|-------|-------------|-------------|----------------|-------|
| kevin/jason/christian/chidi (qwen2.5:32b) | 21 GB | ~24 GB | **NO** | 2–5 tok/s (CPU offload) |
| scaachi (llama3.1:70b) | 46 GB | ~49 GB | **NO** | 1–3 tok/s (mostly CPU) |
| qwen2.5:32b | 21 GB | ~24 GB | **NO** | 2–5 tok/s (CPU offload) |

Every current model exceeds 16 GB VRAM. This means **every single Ollama call** is bottlenecked by CPU/PCIe offloading, explaining the 5+ minute timeouts. The solution is not queue mode or more concurrency — it is **smaller models that fit in VRAM**.

### Recommended Models

| Model | Size | VRAM | Fits? | Speed | Best For |
|-------|------|------|-------|-------|----------|
| Qwen3 14B Q4_K_M | ~8 GB | ~11 GB | **YES** | ~60 tok/s | Default for all agents |
| GPT-OSS 20B Q4_K_M | ~11 GB | ~14 GB | **YES** | ~40 tok/s | Patent specs, complex tasks |
| Llama 3.3 8B Q4_K_M | ~5 GB | ~7 GB | **YES** | ~100 tok/s | Fast Slack replies |

### Expected Performance Impact

| Task | Current (70B/32B) | After Fix (14B) | Improvement |
|------|-------------------|-----------------|-------------|
| Slack `/ai` response | 5–10 minutes | 5–15 seconds | ~60x faster |
| Council deliberation (4 calls) | 20–40 minutes | 4–8 minutes | ~5x faster |
| News summary | 5–10 minutes | 10–30 seconds | ~30x faster |
| Patent spec generation | 10–15 minutes | 30–90 seconds | ~10x faster |
| Task classification | 3–5 minutes | 3–5 seconds | ~60x faster |

Quality-wise, Qwen3 14B is excellent for instruction following, conversational tasks, and structured output. For the Council's creative writing (Scaachi's marketing copy), you may notice a slight quality drop from 70B, but the dramatic speed improvement makes it far more practical. You can always keep one 70B model available for offline/batch tasks where speed doesn't matter.

### Ollama Configuration Tips

- **OLLAMA_FLASH_ATTENTION=1** — Already set in your systemd override. Reduces KV cache memory by 30–50%, critical for fitting models in VRAM.
- **OLLAMA_KEEP_ALIVE=5m** — Already set. Releases VRAM after 5 minutes of idle, allowing model swaps for the Council's sequential calls.
- **OLLAMA_MAX_LOADED_MODELS=2** — Consider adding this. With 14B models (~11 GB each), you could keep two loaded simultaneously, enabling faster Council deliberation without reloading.
- **Context window: start at 4K** — Each doubling of context roughly doubles VRAM for KV cache. 4K is plenty for Slack interactions. Only increase for patent specs or long documents.

---

## Architecture Review

### What Works Well

- **Clean separation of concerns** — The repo structure (`agents/`, `configs/`, `services/`, `scripts/`, `monitoring/`) is logical and well-organized. Each service has its own directory with README files explaining purpose and setup.

- **Comprehensive monitoring** — Grafana + Prometheus + custom exporters (GPU, n8n) give full visibility into system health. Blackbox probes check every service endpoint.

- **Well-documented decisions** — The 11 ADRs in `decisions.md` explain the "why" behind each technology choice (n8n, Ollama, Linear, ngrok). This is excellent practice.

- **Personality-driven agents** — The Modelfile system for Kevin (architect), Jason (engineer), Scaachi (marketing), Christian (prototyper), and Chidi (researcher) is creative and well-thought-out.

- **Automated setup** — The 8-script bootstrap sequence (`00-preflight` through `08-slack-channels`) can stand up the entire system from scratch.

### Areas Needing Attention

1. **No automated testing** — There are no CI/CD pipelines, no unit tests, and no integration tests. The `test-slack-workflows.py` script exists but is not integrated into any workflow. Given how fragile n8n JSON editing is, even basic smoke tests would prevent regressions.

2. **Database is a single point of failure** — The entire system depends on one SQLite file. While `backup-n8n.sh` exists (cron at 3am), there is no verified restore procedure. The queue migration proved how easy it is to lose access to all workflows.

3. **No disaster recovery runbook** — `OPERATIONS.md` covers daily ops, `TROUBLESHOOTING.md` covers common issues, but there is no step-by-step recovery guide for scenarios like "n8n shows setup screen" or "all workflows disappeared."

4. **Duplicate/conflicting compose files** — Three different `docker-compose.yml` files existed for n8n (original, `services/n8n`, `configs/queue`). The services copy has been removed; the queue one is preserved but not active. A single source of truth is needed.

5. **Workflow JSON drift** — The exported JSON files in `services/n8n/workflows/` may not match what's in the live SQLite database (which is edited directly). There is no automated sync or diff mechanism.

6. **ngrok dependency** — The free ngrok tunnel is the only path for Slack webhooks. If ngrok goes down or the domain changes, all Slack integration breaks. This is documented in the roadmap as a Phase 7 fix, but it is a current risk.

---

## Documentation Gap Analysis

| Document | Exists? | Quality | Gap |
|----------|---------|---------|-----|
| README.md | Yes | Good | Could link to all other docs |
| ROADMAP.md | Yes | Good | Phase statuses need updating |
| architecture.md | Yes | Good | References Portainer/Uptime Kuma (not deployed) |
| decisions.md (ADRs) | Yes | Excellent | ADR-008 references tools not in use |
| OPERATIONS.md | Yes | Good | Missing disaster recovery steps |
| USER-GUIDE.md | Yes | Good | Needs /3d, /patent commands added |
| TROUBLESHOOTING.md | Yes | Good | Missing "workflows disappeared" scenario |
| QUICK-START.md | Yes | Good | References may be outdated |
| FAQ.md | Yes | Good | Could cover model sizing |
| **Disaster Recovery Runbook** | **Missing** | — | **Critical gap — needed** |
| **Model Selection Guide** | **Missing** | — | **Should document VRAM constraints** |
| **Workflow Catalog** | **Missing** | — | **No central doc of all 20 workflows** |

The documentation is strong overall. The biggest gaps are operational: knowing what to do when something breaks (disaster recovery), understanding why models are slow (model selection guide), and having a single reference for all 20 workflows with their trigger conditions and dependencies.

---

## Immediate Action Plan

### Step 1: Restore n8n (5 minutes)

Run the restart script that has been prepared. This stops whatever n8n container is currently running and starts the original compose from `/home/biulatech/n8n/` which points to the real database with all 20 workflows:

```bash
bash /home/biulatech/n8n/restart-n8n.sh
```

After running, verify at http://localhost:5678 — you should see the login page (not the setup screen) with all 20 workflows listed.

### Step 2: Switch to Smaller Models (30 minutes)

Download Qwen3 14B as the new default model:

```bash
ollama pull qwen3:14b-q4_K_M
```

Then update each personality Modelfile to use the new base. For example, edit `agents/personalities/kevin.Modelfile` and change the FROM line:

```
FROM qwen3:14b-q4_K_M
```

Then rebuild each personality:

```bash
ollama create kevin -f agents/personalities/kevin.Modelfile
```

Repeat for jason, christian, chidi, and scaachi. For Scaachi (creative writing), you may want to test with both Qwen3 14B and the existing 70B model to compare quality.

### Step 3: Test Core Workflows (15 minutes)

After n8n is restored and models are swapped, test each core path:

1. `/ai hello` — should get a fast Kevin response in Slack
2. `/pm Create a test task` — should create a Linear issue and confirm in Slack
3. Post in #the-council — should trigger 4-member deliberation
4. Check Grafana at localhost:3001 — all services should show green

### Step 4: Download ComfyUI Models (optional, ~1 hour)

If you want `/image`, `/video`, and `/enhance` commands working, download the FLUX.1-schnell checkpoint. This requires a HuggingFace account with the FLUX license accepted:

```bash
HF_TOKEN=<your_token> tmux new-session -d -s dl 'bash scripts/download-comfyui-models.sh'
```

---

## Longer-Term Recommendations

1. **Create a disaster recovery runbook** — Document the exact steps to restore n8n from backup, including how to verify the SQLite database, which compose file to use, and how to re-activate workflows. Today's outage could have been prevented with a 1-page checklist.

2. **Add automated workflow export to git** — The `export-workflows.sh` script exists and runs on cron, but the JSON files in `services/n8n/workflows/` should be automatically diffed against the live database. This catches drift before it becomes a problem.

3. **Revisit queue mode after model fix** — The Redis/Postgres queue migration was attempted to solve timeouts, but the real cause was oversized models. Once 14B models are running at 60 tok/s, you likely won't need queue mode at all. If you do, migrate the SQLite data to Postgres first using n8n's built-in export/import.

4. **Set up a proper domain** — The ngrok free tunnel is fragile. Moving to n8n.biulatech.com with a reverse proxy (Caddy or nginx) and Let's Encrypt would eliminate the ngrok dependency. This is already on the roadmap as Phase 7.

5. **Add basic CI smoke tests** — A GitHub Action that validates workflow JSON structure, checks for common errors (e.g., missing credentials references, broken node connections), and runs the `test-slack-workflows.py` script would catch issues before they reach production.

6. **Consolidate to one compose file** — The original compose at `/home/biulatech/n8n/docker-compose.yml` should be the single source of truth. The queue compose can remain in `configs/queue/` as a reference for future use, clearly marked as inactive.

---

## Summary

The AI Workers platform is a well-designed system with solid architecture and comprehensive coverage. The two immediate fixes — restarting n8n from the correct compose and switching to VRAM-friendly models — will resolve the current outage and the longstanding performance issues. The longer-term recommendations focus on resilience: making the system harder to break and easier to recover when something does go wrong.
