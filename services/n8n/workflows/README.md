# n8n Workflows

Version-controlled exports of all n8n workflows. These JSON files are the canonical source of truth for the automation stack.

## Active Workflows (13)

| Filename | Description | Trigger |
|----------|-------------|---------|
| `counsel-router.json` | #the-council → sequential 4-member deliberation | Webhook: `/webhook/the-council` |
| `github-push-handler.json` | GitHub push → format commit → #ops-updates | Webhook: `/webhook/github-push` |
| `linear-ai-project-manager.json` | /pm → Ollama classify → Linear issue → Slack confirm | Webhook: `/webhook/slack-command` (pm route) |
| `news-article-generator.json` | /news topic → RSS + Ollama → #ops-intel | Webhook: `/webhook/news-search` |
| `ops-daily-digest.json` | System health + Kevin quote → #ops-digest | Schedule: weekdays 9am ET |
| `ops-gpu-alert.json` | GPU alert webhook → format → #ops-alerts | Webhook: `/webhook/gpu-alert` |
| `ops-service-monitor.json` | Health checks → #ops-alerts | Schedule: every 5 min |
| `slack-command-handler.json` | Routes /ai /image /video /enhance /news /pm | Webhook: `/webhook/slack-command` |
| `slack-diagnose-handler.json` | /ai-diagnose → 5 health checks → report | Webhook: `/webhook/ai-diagnose` |
| `slack-events-receiver.json` | app_mention + #the-council → route → reply | Webhook: `/webhook/slack-events` |
| `slack-status-handler.json` | /ai-status → health check → #ops-status | Webhook: `/webhook/ai-status` |
| `tasks-channel-handler.json` | #tasks-* messages → Linear issue + agent loop | Webhook: `/webhook/slack-events` (filtered) |
| `weekly-news-digest.json` | 3 RSS feeds → Ollama → #ops-digest | Schedule: Monday 8am |

## Inactive (3) — Awaiting ComfyUI model download

| Filename | Description | Blocker |
|----------|-------------|---------|
| `comfyui-image-enhance.json` | /enhance url → ComfyUI → #studio-canvas | No checkpoint in `~/ComfyUI/models/checkpoints/` |
| `comfyui-text-to-image.json` | /image prompt → ComfyUI → #studio-canvas | Same |
| `comfyui-text-to-video.json` | /video prompt → ComfyUI → #studio-reels | Same |

## Export / Import

**Export all** (requires n8n API key in `/home/biulatech/n8n/.env`):
```bash
bash /home/biulatech/ai-workers-1/scripts/maintenance/export-workflows.sh
```

**Export one** (n8n UI): Workflow → ⋮ → Download

**Import**: n8n UI → Workflows → Import from file

**Auto-export cron** (daily at 2am):
```bash
(crontab -l; echo "0 2 * * * /home/biulatech/ai-workers-1/scripts/maintenance/export-workflows.sh >> /var/log/n8n-export.log 2>&1") | crontab -
```
