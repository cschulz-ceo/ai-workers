# n8n Workflows

Version-controlled exports of all n8n workflows. These JSON files are the canonical
source of truth — import them into n8n to restore or replicate the automation stack.

## Workflow Index

| Filename | Description | Trigger |
|----------|-------------|---------|
| `github-push-handler.json` | GitHub push → format commit → #ops-updates | Webhook: `/webhook/github-push` |
| `linear-ai-project-manager.json` | /pm → Ollama classify → Linear issue → Slack confirm | Webhook: `/webhook/slack-command` (pm route) |
| `ops-daily-digest.json` | System health + Kevin quote → #ops-digest | Schedule: weekdays 9am ET |
| `ops-service-monitor.json` | Health checks → #ops-alerts | Schedule: every 5 min |
| `slack-command-handler-v2.json` | Routes /ai /image /video /enhance /news /pm | Webhook: `/webhook/slack-command` |
| `slack-diagnose-handler.json` | /ai-diagnose → 5 health checks → report | Webhook: `/webhook/ai-diagnose` |
| `slack-events-receiver.json` | app_mention events → personality → thread reply | Webhook: `/webhook/slack-events` |
| `slack-status-handler.json` | /ai-status → health check → #ops-status | Webhook: `/webhook/ai-status` |
| `tasks-channel-handler.json` | #tasks-* messages → Linear issue creation | Webhook: `/webhook/slack-events` (filtered) |
| `the-council-counsel-router.json` | #the-council → sequential 4-member deliberation | Webhook: `/webhook/slack-events` (filtered) |
| `weekly-news-digest.json` | 3 RSS feeds → Ollama → Slack #ops-digest | Schedule: Monday 8am |

### Inactive (awaiting ComfyUI models)

| Filename | Description | Blocker |
|----------|-------------|---------|
| `comfyui-text-to-image.json` | /image prompt → ComfyUI → #studio-canvas | No checkpoint in `~/ComfyUI/models/checkpoints/` |
| `comfyui-text-to-video.json` | /video prompt → ComfyUI → #studio-reels | Same |
| `comfyui-image-enhance.json` | /enhance url → ComfyUI → #studio-canvas | Same |
| `news-article-generator.json` | /news topic → RSS + Ollama → Slack | Needs activation + webhook path verify |

## Export / Import

**Export all** (requires n8n API key — see `/home/biulatech/n8n/.env`):
```bash
bash scripts/maintenance/export-workflows.sh
```

**Export one** (n8n UI): Workflow → ⋮ → Download

**Import**: n8n UI → Workflows → Import from file

**Auto-export cron** (daily at 2am):
```bash
(crontab -l; echo "0 2 * * * /home/biulatech/ai-workers-1/scripts/maintenance/export-workflows.sh >> /var/log/n8n-export.log 2>&1") | crontab -
```
