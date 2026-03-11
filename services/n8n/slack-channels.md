# Slack Channel Architecture

## Design Rationale

Channels are organized into four categories using prefixes for sidebar grouping. Slack sorts channels alphabetically, so prefixes create natural visual buckets without needing paid workspace features.

```
counsel → #the-council (unified council chat — mention any member by name)
tasks-*      → Direct task assignment per agent
gen-*        → Generative output streams (images, video, content)
ops-*        → Operational: reports, alerts, system status, logs
```

---

## Channel Directory

### Category 1 — `counsel-*` (Personality Chat)
Each personality has a dedicated channel for open-ended conversation and ad-hoc requests. You chat here; the agent responds in-thread via n8n.

| Channel | Personality | Domain |
|---------|------------|--------|
| `#the-council` (mention Kevin) | Kevin | Architecture, system design, diagramming |
| `#the-council` (mention Jason) | Jason | Code, refactoring, scalability, DevOps |
| `#the-council` (mention Scaachi) | Scaachi | Marketing, content writing, copywriting |
| `#the-council` (mention Christian) | Christian | Rapid prototyping, POCs, quick builds |
| `#the-council` (mention Chidi) | Chidi | Feasibility, ethics, trade-off analysis |

**How it works:** Post a message in `#the-council`. Mention a council member by name (e.g. 'Kevin, what do you think?') to get their response. Ask an open question and 1-2 members will respond organically. Post to a `#tasks-*` channel with `tasks-*` prefix to route work to a specific agent.

---

### Category 2 — `tasks-*` (Direct Task Assignment)
Structured task channels where you assign specific, trackable work. n8n creates a Linear issue for every task posted here and tracks completion.

| Channel | Agent | Typical Tasks |
|---------|-------|---------------|
| `#tasks-kevin` | Kevin | "Draw a Mermaid diagram of X", "Update architecture doc" |
| `#tasks-jason` | Jason | "Refactor Y module", "Write unit tests for Z", "Review PR" |
| `#tasks-scaachi` | Scaachi | "Write a blog post about X", "Draft changelog for v1.2" |
| `#tasks-christian` | Christian | "Build a prototype for X in Python", "Quick proof of concept" |
| `#tasks-chidi` | Chidi | "Assess feasibility of X", "Review this decision for risks" |

**How it works:** Post task → n8n creates Linear issue → assigns to agent → agent completes and replies with output + Linear issue link.

---

### Category 3 — `gen-*` (Generative Output Streams)
Automated output channels. n8n posts results here; agents don't converse in these channels — they're output feeds.

| Channel | Trigger | Output |
|---------|---------|--------|
| `#studio-canvas` | ComfyUI completion | Generated images with prompt, seed, workflow used |
| `#studio-reels` | Video workflow completion | Video clips, previews, render metadata |
| `#studio-blueprint` | Kevin task completion | Diagrams, Mermaid renders, architecture docs |
| `#studio-forge` | Jason task completion | Code diffs, PR summaries, refactor outputs |
| `#studio-quill` | Scaachi task completion | Written content, marketing copy, changelogs |

---

### Category 4 — `ops-*` (Operational / System)
System-facing channels. Mostly automated; low human interaction.

| Channel | Source | Purpose |
|---------|--------|---------|
| `#ops-alerts` | Netdata + Portainer + Uptime Kuma → n8n | Critical/warning alerts: container crashes, GPU overload, service downtime |
| `#ops-intel` | n8n scheduled workflow | Daily consolidated summary: tasks completed, agents used, system health |
| `#ops-pulse` | n8n on Git push | New commits, deployments, config changes, version bumps |
| `#ops-digest` | n8n scheduled workflow | Weekly digest: agent activity summary, top outputs, pending tasks |
| `#ops-logbook` | n8n on workflow completion | Verbose workflow execution logs (lower priority, high volume) |
| `#ops-board` | n8n scheduled workflow | Hourly service status ping (Ollama, n8n, Docker, GPU util) |

---

## n8n Workflow → Channel Routing Map

| n8n Workflow | Posts To | Trigger |
|-------------|----------|---------|
| `slack-counsel-router` | `#the-council` (reply in thread) | Mention any member by name |
| `slack-agent-report` | `#tasks-*` (reply in thread) | Task completion |
| `slack-monitoring-alert` | `#ops-alerts` | Netdata/Portainer/Uptime Kuma webhook |
| _(future)_ daily-report | `#ops-intel` | Cron: daily 8am |
| _(future)_ weekly-digest | `#ops-digest` | Cron: Monday 9am |
| _(future)_ git-push-notify | `#ops-pulse` | GitHub webhook |
| _(future)_ comfyui-complete | `#studio-canvas` | ComfyUI output webhook |
| _(future)_ status-ping | `#ops-board` | Cron: hourly |

---

## Environment Variables (add to ~/n8n/.env)

```bash
# Slack channel IDs — fill in after channels are created
# Get ID: right-click channel → Copy link → ID is the last segment
SLACK_CHANNEL_THE_COUNCIL=C0AKVJ5PHHR
# (counsel channels merged into #the-council)



SLACK_CHANNEL_TASKS_KEVIN=
SLACK_CHANNEL_TASKS_JASON=
SLACK_CHANNEL_TASKS_SCAACHI=
SLACK_CHANNEL_TASKS_CHRISTIAN=
SLACK_CHANNEL_TASKS_CHIDI=
SLACK_CHANNEL_GEN_IMAGES=
SLACK_CHANNEL_GEN_VIDEO=
SLACK_CHANNEL_GEN_ARCHITECTURE=
SLACK_CHANNEL_GEN_CODE=
SLACK_CHANNEL_GEN_CONTENT=
SLACK_CHANNEL_OPS_ALERTS=
SLACK_CHANNEL_OPS_REPORTS=
SLACK_CHANNEL_OPS_UPDATES=
SLACK_CHANNEL_OPS_DIGEST=
SLACK_CHANNEL_OPS_LOGS=
SLACK_CHANNEL_OPS_STATUS=
```

---

## Creation Checklist

- [ ] `#counsel-kevin`
- [ ] `#counsel-jason`
- [ ] `#counsel-scaachi`
- [ ] `#counsel-christian`
- [ ] `#counsel-chidi`
- [ ] `#tasks-kevin`
- [ ] `#tasks-jason`
- [ ] `#tasks-scaachi`
- [ ] `#tasks-christian`
- [ ] `#tasks-chidi`
- [ ] `#studio-canvas`
- [ ] `#studio-reels`
- [ ] `#studio-blueprint`
- [ ] `#studio-forge`
- [ ] `#studio-quill`
- [ ] `#ops-alerts`
- [ ] `#ops-intel`
- [ ] `#ops-pulse`
- [ ] `#ops-digest`
- [ ] `#ops-logbook`
- [ ] `#ops-board`
- [ ] Invite `ai-workers` bot to all channels
- [ ] Copy channel IDs into `~/n8n/.env`
- [ ] Restart n8n after updating .env
