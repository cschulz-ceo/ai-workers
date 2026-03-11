# ai-workers

Autonomous AI agent environment running on local hardware, orchestrated by n8n, with reporting via Slack. Agents handle task execution, code generation, image generation, content creation, and self-management — all on-premise with no public exposure.

## Hardware Target

| Component | Spec |
|-----------|------|
| CPU | AMD Ryzen 9 9950X |
| GPU | NVIDIA GeForce RTX 5070 Ti |
| RAM | 64 GB DDR5 |
| Disk | 2 TB NVMe |
| OS | Pop!_OS (NVIDIA driver stack, CUDA enabled) |

## Architecture Overview

```
[User / External Input]
        │
        ▼
 ┌─────────────┐     ┌──────────────┐
 │  Open WebUI │────▶│    Ollama    │  ◀── GPU (CUDA)
 └─────────────┘     │  (AI Core)   │
                     └──────┬───────┘
                            │
                     ┌──────▼───────┐
                     │     n8n      │  ◀── Webhooks / Triggers
                     │(Orchestrator)│
                     └──┬───────────┘
           ┌────────────┼────────────────┐
           ▼            ▼                ▼
       [Slack]       [Linear]      [MCP Servers]
     (Reporting)   (Tracking)    (Git, Slack, etc.)

 ┌─────────────────────────────────────────────┐
 │              Monitoring Layer                │
 │   Portainer │ Netdata │ Uptime Kuma          │
 │           └──── alerts ──▶ n8n ──▶ Slack    │
 └─────────────────────────────────────────────┘

 ┌─────────────────────────────────────────────┐
 │               Network Layer                  │
 │   All services bind 0.0.0.0 (LAN only)      │
 │   WireGuard VPN for remote access           │
 └─────────────────────────────────────────────┘
```

See [`docs/architecture.md`](docs/architecture.md) for the full component diagram and data flow documentation.

## Agent Personalities

| Name | Domain | Base Model |
|------|--------|------------|
| Kevin | Diagrams & Architecture | llama3.1 |
| Jason | Code & Scalability | llama3.1 |
| Scaachi | Marketing & Content | llama3.1 |
| Christian | Rapid Prototyping | llama3.1 |
| Chidi | Feasibility Analysis | llama3.1 |

## Service Ports (LAN)

| Service | Port |
|---------|------|
| Ollama | 11434 |
| n8n | 5678 |
| Open WebUI | 8080 |
| ComfyUI | 8188 |
| Portainer | 9000 |
| Netdata | 19999 |
| Uptime Kuma | 3001 |
| Linear | cloud |

## Repository Structure

See [`docs/structure.md`](docs/structure.md) for full folder layout and reasoning.

## Key Documents

- [`decisions.md`](decisions.md) — Architectural decision log (vision preservation)
- [`docs/architecture.md`](docs/architecture.md) — Full system architecture & diagrams
- [`docs/structure.md`](docs/structure.md) — Folder structure rationale

## Principles

- **Local-first**: No public exposure; all services LAN-bound
- **Free/open-source**: No paid SaaS dependencies except Slack (existing)
- **Persistent**: All services managed as systemd units
- **Modular**: Each service is independently configurable and replaceable
- **Repeatable**: Scripts are idempotent; configs are version-controlled
- **Autonomous**: Agents self-report via n8n → Slack; bypass free-tier bot limits
