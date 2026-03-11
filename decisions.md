# Architectural Decision Log

This file preserves the reasoning behind key design choices in the ai-workers environment. Each entry captures context, the decision made, and the rationale — so future agents and contributors understand *why*, not just *what*.

---

## ADR-001: n8n as Central Orchestration Hub

**Date**: 2026-03-11
**Status**: Accepted

**Context**
Multiple AI agents need to coordinate task execution, trigger external services, and report results. A dedicated orchestration layer is required that can handle webhooks, conditional logic, retries, and multi-step workflows without custom code per integration.

**Decision**
Use n8n (self-hosted) as the single orchestration hub connecting all services.

**Rationale**
- Free, self-hostable, no per-execution pricing at local scale
- Visual workflow editor reduces friction for building/debugging pipelines
- Native integrations for Slack, HTTP, Git, and custom webhooks
- Enables Slack reporting without requiring a dedicated Slack bot (bypasses free-tier bot limits by using webhook-based posting)
- systemd-compatible for persistent operation

---

## ADR-002: Ollama for Local LLM Inference

**Date**: 2026-03-11
**Status**: Accepted

**Context**
AI agents require an LLM backend that runs entirely on local hardware, supports GPU acceleration, and can serve multiple named personalities simultaneously.

**Decision**
Use Ollama with llama3.1 as the base model, with per-personality Modelfiles defining system prompts and parameter tuning.

**Rationale**
- Runs entirely local — no API costs, no data egress
- Native CUDA support leverages RTX 5070 Ti for fast inference
- Modelfile system allows distinct personalities without separate model weights
- REST API on port 11434 integrates cleanly with n8n and Open WebUI

---

## ADR-003: Slack as Reporting Endpoint (via n8n Webhooks)

**Date**: 2026-03-11
**Status**: Accepted

**Context**
Agents need to report task completions, errors, and system events. Slack is the preferred interface, but direct bot usage is constrained by free-tier limits.

**Decision**
Route all Slack messages through n8n using Incoming Webhooks rather than a bot token.

**Rationale**
- Incoming Webhooks are free, unlimited, and require no bot user
- n8n acts as a message broker — agents post to n8n, n8n formats and forwards to Slack
- Decouples agent output format from Slack's API requirements
- Allows message batching, deduplication, and rate-limit management at the n8n layer

---

## ADR-004: systemd for Service Persistence

**Date**: 2026-03-11
**Status**: Accepted

**Context**
All services must survive reboots and be manageable via standard Linux tooling without Docker Compose orchestration at the top level.

**Decision**
Each service is defined as a systemd unit file stored in `configs/systemd/`.

**Rationale**
- Native to Pop!_OS — no additional runtime dependency
- `systemctl enable` provides automatic start on boot
- `journalctl` provides unified log access across all services
- Allows mixed deployment: some services run in Docker (Portainer, Plane, Uptime Kuma), others run natively (Ollama, n8n), all wrapped in systemd

---

## ADR-005: WireGuard for Remote Access

**Date**: 2026-03-11
**Status**: Accepted

**Context**
All services are LAN-bound with no public exposure. Remote access to the environment (e.g., from mobile or off-site) must be secure without opening ports to the internet.

**Decision**
Use WireGuard VPN for remote access. Keys and config stored in `configs/network/` (excluded from version control via .gitignore).

**Rationale**
- WireGuard is lightweight, kernel-native on modern Linux, and significantly faster than OpenVPN
- No inbound ports required beyond the single WireGuard UDP port
- Private keys never committed to Git (gitignored); only example configs are tracked
- Integrates with systemd via `wg-quick@` service unit

---

## ADR-006: MCP Servers for Agent Tool Access

**Date**: 2026-03-11
**Status**: Accepted

**Context**
Agents need to interact with external tools (Git pushes, Slack posts, file reads) in a structured, permissioned way rather than via raw shell commands.

**Decision**
Use Model Context Protocol (MCP) servers as the interface layer between agents and external tools.

**Rationale**
- MCP provides a standardized agent-tool interface that is model-agnostic
- Local MCP servers can be scoped with fine-grained permissions per agent
- Decouples tool implementation from agent logic — tools can be swapped without changing agent prompts
- Compatible with n8n for workflow-triggered tool calls

---

## ADR-007: Git + GitHub for Version Control and AI Self-Management

**Date**: 2026-03-11
**Status**: Accepted

**Context**
Scripts, configs, agent definitions, and workflow exports must be versioned. Agents (particularly Jason) should be able to commit changes autonomously via MCP.

**Decision**
Use Git locally with GitHub as the remote. Repository is private. AI commits are routed through the GitHub MCP server.

**Rationale**
- Private GitHub repo provides off-device backup and collaboration capability
- MCP-mediated commits mean agents never have direct shell access to `git push` — changes go through a controlled interface
- `decisions.md` (this file) is tracked in Git, preserving architectural intent across agent sessions

---

## ADR-008: Portainer + Netdata + Uptime Kuma as Monitoring Stack

**Date**: 2026-03-11
**Status**: Accepted

**Context**
The environment runs a mix of Docker containers and native services. Visibility into container health, system resources, and service uptime is required, with alerting routed to Slack.

**Decision**
Use Portainer (container GUI), Netdata (system metrics), and Uptime Kuma (service ping/uptime) as complementary monitoring tools, all alerting via n8n to Slack.

**Rationale**
- Each tool covers a distinct monitoring dimension without overlap
- All three are free and self-hosted
- Uptime Kuma provides a single status dashboard with links to all service UIs
- Netdata captures GPU metrics (via NVIDIA plugin) which is critical for inference monitoring
- Alerts flow through n8n, keeping Slack notification logic centralized

---

## ADR-009: Plane for Project and Task Management

**Date**: 2026-03-11
**Status**: Accepted

**Context**
Agents need a structured system to track tasks, epics, and issues — both human-assigned and autonomously generated. GitHub Issues alone are insufficient for project-level tracking.

**Decision**
Self-host Plane (open-source project management) via Docker stack, integrated with n8n via API.

**Rationale**
- Plane is free, self-hosted, and provides GitHub-like issue tracking with roadmap/epic support
- n8n can create/update Plane issues programmatically when agents complete or discover tasks
- Keeps task management entirely on-premise alongside other services

---

## ADR-010: ngrok for Slack Webhook Tunnel

**Status:** Accepted

**Context:**
n8n runs locally and must receive inbound HTTP requests from Slack (slash commands, events, interactive payloads). Cloudflare Tunnel was the original choice but requires either a registered domain or a payment method on file even for zero-cost plans — neither of which was available at bootstrap time.

**Decision:**
Use ngrok (free tier) to expose n8n's webhook endpoint publicly.

**Rationale:**
- Free tier includes one static subdomain (e.g., `abc.ngrok-free.app`) that persists across restarts — required for stable Slack app configuration
- No domain required, no payment required
- CLI install with no system dependencies
- Built-in web inspector at `localhost:4040` for debugging webhook payloads
- Runs as a systemd user service (auto-start on login, no sudo needed)
- If biulatech.com is added to Cloudflare in future, migration to Cloudflare Tunnel is straightforward

**Trade-offs:**
- Free tier limits: 1 static domain, 40 connections/minute — sufficient for this workload
- ngrok account required (free); authtoken stored in `~/n8n/.env` (gitignored)
- Cloudflare Tunnel remains the long-term preference once a domain is registered

## Future Decisions (Pending)

- [ ] ADR-011: Secrets management strategy (e.g., local Vault vs. env files)
- [ ] ADR-012: Model selection strategy beyond llama3.1 (quantization, specialization)
- [ ] ADR-013: ComfyUI workflow versioning approach
- [ ] ADR-014: Agent skill packaging format
- [ ] ADR-015: Migrate tunnel to Cloudflare (when biulatech.com is added to Cloudflare)
