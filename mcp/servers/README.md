# MCP Servers

Each subdirectory defines one MCP server — a controlled interface between agents and an external tool.

## Servers
- `github/` — Git operations (commit, push, PR creation)
- `slack/` — Slack message posting (via Incoming Webhook)
- `filesystem/` — Scoped file read/write for agents

## Adding a New Server
1. Create `mcp/servers/<name>/`
2. Add `config.json` with server definition
3. Add `README.md` documenting permissions and usage
4. Reference in relevant agent personality or n8n workflow
