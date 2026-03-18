# System Architecture

## Overview

The ai-workers environment is an autonomous AI agent platform running entirely on local hardware. Agents receive tasks, process them using local LLM inference, and report results to Slack through n8n — with no public internet exposure.

---

## Full System Diagram

```
╔══════════════════════════════════════════════════════════════════════════╗
║                         HARDWARE LAYER                                   ║
║   Ryzen 9 9950X CPU  │  RTX 5070 Ti GPU (CUDA)  │  64GB DDR5  │  2TB NVMe║
╚══════════════════════════════════════════════════════════════════════════╝
                                    │
╔══════════════════════════════════════════════════════════════════════════╗
║                           OS LAYER                                       ║
║              Pop!_OS  ──  NVIDIA Drivers  ──  CUDA Toolkit               ║
╚══════════════════════════════════════════════════════════════════════════╝
                                    │
         ┌──────────────────────────┼───────────────────────────┐
         │                          │                           │
         ▼                          ▼                           ▼

┌─────────────────┐      ┌──────────────────┐      ┌───────────────────┐
│   ENTRY POINTS  │      │    AI CORE       │      │  IMAGE GENERATION │
│                 │      │                  │      │                   │
│  Open WebUI     │─────▶│  Ollama          │      │  ComfyUI          │
│  :8080          │      │  :11434          │      │  :8188            │
│                 │      │                  │      │                   │
│  ┌───────────┐  │      │  Personalities:  │      │  ┌─────────────┐  │
│  │ Chat UI   │  │      │  ┌────────────┐  │      │  │ PyTorch     │  │
│  │ Web Search│  │      │  │ Kevin      │  │      │  │ CUDA        │  │
│  │ ComfyUI   │  │      │  │ Jason      │  │      │  └─────────────┘  │
│  │ connector │  │      │  │ Scaachi    │  │      │                   │
│  └───────────┘  │      │  │ Christian  │  │      │  Input: prompts   │
│                 │      │  │ Chidi      │  │      │  from WebUI/n8n   │
└────────┬────────┘      │  └────────────┘  │      └────────┬──────────┘
         │               │                  │               │
         │               │  Base: llama3.1  │               │
         │               └────────┬─────────┘               │
         │                        │                          │
         └────────────────────────┼──────────────────────────┘
                                  │
                                  ▼
╔═════════════════════════════════════════════════════════════════════════╗
║                     n8n  —  ORCHESTRATION HUB  :5678                    ║
║                                                                          ║
║   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                  ║
║   │ Task Chain   │  │ Self-Healing │  │ MCP Trigger  │                  ║
║   │ Workflows    │  │ Workflows    │  │ Workflows    │                  ║
║   └──────────────┘  └──────────────┘  └──────────────┘                  ║
║                                                                          ║
║   Inputs:  Ollama outputs │ Webhooks │ Monitoring alerts │ Schedules    ║
║   Outputs: Slack posts │ Linear issues │ MCP calls │ HTTP triggers       ║
╚══════════════════╤══════════════════════════╤══════════════════════════╝
                   │                          │
        ┌──────────┼──────────────────────────┼──────────────┐
        │          │                          │              │
        ▼          ▼                          ▼              ▼

┌──────────────┐  ┌──────────────────┐  ┌──────────┐  ┌────────────────┐
│    SLACK     │  │     LINEAR       │  │  GIT /   │  │  MCP SERVERS   │
│  (Reporting) │  │  (Task Tracking) │  │  GITHUB  │  │  (Agent Tools) │
│              │  │                  │  │          │  │                │
│ Via Incoming │  │  Docker stack    │  │  CLI +   │  │ ┌────────────┐ │
│ Webhooks     │  │  :80 / :443      │  │  gh CLI  │  │ │ GitHub MCP │ │
│ (no bot)     │  │                  │  │          │  │ │ Slack MCP  │ │
│              │  │  n8n API writes  │  │  Agent   │  │ │ File MCP   │ │
│ Achievements │  │  issues on task  │  │  commits │  │ └────────────┘ │
│ Errors       │  │  completion      │  │  via MCP │  │                │
│ Alerts       │  └──────────────────┘  └──────────┘  └────────────────┘
└──────────────┘

╔═════════════════════════════════════════════════════════════════════════╗
║                       MONITORING LAYER                                   ║
║                                                                          ║
║  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────────┐    ║
║  │   Grafana       │  │   Prometheus     │  │  Blackbox Exporter  │    ║
║  │   :3001         │  │    :9090         │  │    :9115            │    ║
║  │                 │  │                  │  │                     │    ║
║  │ Dashboards +    │  │ Metrics store:   │  │ HTTP probes:        │    ║
║  │ Alerting        │  │ CPU/RAM/Disk/GPU │  │ All service URLs    │    ║
║  │ AI Workers Hub  │  │ 30-day retention │  │ n8n/Ollama/ComfyUI  │    ║
║  └────────┬────────┘  └────────┬─────────┘  └──────────┬──────────┘    ║
║           └───────────────────┬┘                        │               ║
║                               └─────────────────────────┘               ║
║                                           │                              ║
║                                    alerts ▼                              ║
║                              ┌─────────────────┐                        ║
║                              │  n8n (webhook)  │──▶ Slack               ║
║                              └─────────────────┘                        ║
╚═════════════════════════════════════════════════════════════════════════╝

╔═════════════════════════════════════════════════════════════════════════╗
║                        NETWORK / SECURITY LAYER                          ║
║                                                                          ║
║   ┌─────────────────────────────────────────────────────────────────┐   ║
║   │                         LAN (0.0.0.0)                           │   ║
║   │   All services bind to LAN interface — no public exposure       │   ║
║   └─────────────────────────────────────────────────────────────────┘   ║
║                                                                          ║
║   ┌─────────────────────────────────────────────────────────────────┐   ║
║   │                     WireGuard VPN                               │   ║
║   │   Remote device ──(encrypted tunnel)──▶ LAN services           │   ║
║   │   Single UDP port inbound; kernel-native on Pop!_OS             │   ║
║   └─────────────────────────────────────────────────────────────────┘   ║
╚═════════════════════════════════════════════════════════════════════════╝

╔═════════════════════════════════════════════════════════════════════════╗
║                       PERSISTENCE LAYER                                  ║
║                                                                          ║
║   systemd units for: ollama │ n8n │ wireguard │ netdata                  ║
║   Docker (systemd-managed): portainer │ uptime-kuma             ║
║   Git repo (this): all configs, scripts, decisions, workflows           ║
╚═════════════════════════════════════════════════════════════════════════╝
```

---

## Data Flow Descriptions

### Task Execution Flow
```
User/Agent Input
    │
    ▼
Open WebUI (chat) ──or── n8n webhook
    │
    ▼
Ollama (personality selected → LLM processes task)
    │
    ▼
n8n (receives output, chains next workflow steps)
    │
    ├──▶ Slack (report result)
    ├──▶ Linear (create/update issue)
    └──▶ MCP Server (if tool use needed: Git commit, file write, etc.)
```

### Monitoring Alert Flow
```
Service/System Event
    │
    ├── Blackbox exporter detects service down (HTTP probe)
    ├── Prometheus threshold exceeded (CPU/GPU/RAM via node-exporter + gpu-exporter)
    └── Grafana alert rule fires
    │
    ▼
n8n webhook trigger
    │
    ▼
Message formatted + posted to Slack #alerts channel
```

### Agent Self-Build Flow (Autonomy Loop)
```
n8n schedules task ──▶ Ollama (Jason personality)
    │
    ▼
Jason generates code/config
    │
    ▼
MCP (GitHub server) stages and commits to ai-workers repo
    │
    ▼
n8n posts commit summary to Slack
    │
    ▼
Linear issue marked complete
```

---

## Component Details

### Ollama — AI Core
- **Port**: 11434
- **Protocol**: REST (HTTP)
- **GPU**: Yes — CUDA via RTX 5070 Ti
- **Personalities**: Defined as Modelfiles in `agents/personalities/`
- **Consumers**: Open WebUI, n8n (via HTTP node), MCP servers

### n8n — Orchestration Hub
- **Port**: 5678
- **Protocol**: HTTP / WebSocket
- **Persistence**: Workflow JSONs exported to `workflows/`
- **Key integrations**: Ollama, Slack, Linear, GitHub, ComfyUI, monitoring webhooks

### Open WebUI — User Interface
- **Port**: 8080
- **Features**: Chat with all personalities, ComfyUI image pipeline, web search
- **Auth**: Local user accounts (no external auth required)

### ComfyUI — Image Generation
- **Port**: 8188
- **Backend**: PyTorch + CUDA (shares GPU with Ollama — schedule non-concurrent)
- **Integration**: Triggered from Open WebUI or n8n workflows

### WireGuard — Remote Access
- **Protocol**: UDP (single port)
- **Keys**: Stored locally, gitignored. Example configs only in repo.
- **systemd**: Managed via `wg-quick@wg0.service`

### Linear — Project Management
- **Port**: 80 / 443
- **Deployment**: Cloud SaaS — no self-hosting required
- **Integration**: n8n writes issues via Linear GraphQL API (`linear-ai-project-manager` workflow)

### Grafana — Dashboards & Alerting
- **Port**: 3001
- **Dashboard**: `ai-workers-hub` — service uptime, CPU, RAM, disk, GPU metrics
- **Data sources**: Prometheus, JSON API
- **Anonymous access**: Enabled (Viewer role)

### Prometheus — Metrics Collection
- **Port**: 9090
- **Retention**: 30 days
- **Scrape jobs**: node-exporter, blackbox-http, gpu-exporter (:9835), n8n-exporter (:9201)

### Blackbox Exporter — Service Probes
- **Port**: 9115
- **Probes**: HTTP health checks for n8n, Ollama, Open WebUI, ComfyUI, ngrok, Grafana

---

## Dependency Build Order

1. Hardware / OS / CUDA drivers (prerequisite — manual)
2. Ollama (AI foundation — everything depends on this)
3. n8n (orchestration — must exist before workflows can run)
4. Open WebUI + ComfyUI (interfaces — depend on Ollama)
5. Slack integration (configure n8n Incoming Webhook)
6. Git + GitHub (version control — configure after n8n is live)
7. WireGuard (network access — independent, can be done anytime)
8. Linear (project management — cloud API, requires LINEAR_API_KEY in .env)
9. Monitoring stack (Grafana, Prometheus, Blackbox Exporter — depends on services being live)
10. MCP servers + Skills (autonomy layer — built on top of everything else)
