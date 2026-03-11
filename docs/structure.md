# Repository Structure

This document explains the folder layout of the `ai-workers` repository and the reasoning behind each directory's placement.

## Layout

```
ai-workers/
├── .github/                    # GitHub-specific configs
│   └── ISSUE_TEMPLATE/         # Standardized issue templates
├── agents/                     # AI agent definitions
│   ├── personalities/          # Per-personality Modelfiles and system prompts
│   └── skills/                 # Reusable skill packages loaded by agents
├── configs/                    # Environment-level configuration
│   ├── systemd/                # systemd unit files for all services
│   └── network/                # WireGuard and network configs (secrets gitignored)
├── docs/                       # Documentation and diagrams
│   ├── architecture.md         # Full system architecture and component diagrams
│   └── structure.md            # This file
├── mcp/                        # Model Context Protocol layer
│   ├── servers/                # MCP server definitions (one subdir per tool)
│   └── configs/                # MCP connection configs per agent
├── monitoring/                 # Monitoring stack configs and alert rules
├── scripts/                    # Operational scripts
│   ├── setup/                  # First-run / installation scripts
│   └── maintenance/            # Ongoing ops (backups, health checks, etc.)
├── services/                   # Per-service configuration
│   ├── ollama/                 # Modelfiles, model pull lists
│   ├── n8n/                    # Workflow exports (.json), env example
│   ├── open-webui/             # Config overrides, env example
│   ├── comfyui/                # Custom nodes list, workflow examples
│   ├── wireguard/              # WireGuard config examples (no real keys)
│   ├── plane/                  # Docker Compose for Plane stack
│   ├── portainer/              # Portainer stack config
│   ├── netdata/                # Netdata config overrides
│   └── uptime-kuma/            # Uptime Kuma backup/config
├── workflows/                  # n8n workflow JSON exports (source of truth)
├── decisions.md                # Architectural decision log (ADRs)
├── README.md                   # Project overview and quickstart
└── .gitignore                  # Excludes secrets, keys, volumes, logs
```

## Rationale

### `services/` — One Subdirectory Per Service
Each service is isolated so its configuration, environment variables, and Docker Compose files can be versioned and deployed independently. This mirrors the "one concern per module" principle and makes it easy to add, remove, or swap a service without touching other directories.

### `agents/personalities/` vs `agents/skills/`
Personalities are Ollama Modelfiles — they define *who* an agent is (system prompt, temperature, stop tokens). Skills are reusable capability packages — they define *what* an agent can do (e.g., a code-gen skill Jason loads, or a diagram skill Kevin uses). Separating them allows skills to be shared across personalities.

### `configs/systemd/`
All systemd unit files live here rather than inside individual service directories, because systemd is an OS-level concern, not a service-level one. A single location makes it easy to deploy all units in one step via a setup script.

### `mcp/` — Separate from `services/`
MCP servers are not traditional services — they're agent-tool bridges. Placing them in `mcp/` rather than `services/` makes the distinction clear: services are user-facing or infrastructure; MCP servers are agent-internal tooling.

### `workflows/`
n8n workflow JSON exports are the canonical, version-controlled source of truth for automation logic. They live at the repo root level (not inside `services/n8n/`) because workflows are a primary artifact of the project — as important as code.

### `docs/`
Keeps all human-readable documentation together. Architecture diagrams and decision logs are the two most critical documents for long-term maintainability, so they get dedicated files rather than being embedded in the README.

### `scripts/setup/` vs `scripts/maintenance/`
Setup scripts are idempotent first-run installers. Maintenance scripts are recurring operational tasks (health checks, backups, log rotation). Separating them prevents accidental re-initialization during routine ops.

### `.github/ISSUE_TEMPLATE/`
Standardized issue templates ensure that tasks created by both humans and AI agents (via n8n → GitHub MCP) follow a consistent format, making Plane/GitHub integration reliable.
