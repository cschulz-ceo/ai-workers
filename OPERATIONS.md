# Operations Guide

This guide is for anyone running, maintaining, or updating the AI Workers environment — no coding background required.

---

## What This System Does

This system runs a set of AI agents that work inside your Slack workspace. They can:

- **Answer questions** — type `/ai <question>` in Slack and an AI responds in the thread
- **Create Linear tasks** — type `/pm <task description>` and it creates a tracked issue in Linear
- **Run AI councils** — mention `@kevin` (or other agents) in `#the-council` for group deliberation
- **Generate images/video** — type `/image <description>` or `/video <description>` in Slack
- **Deliver digests** — automated summaries posted to `#ops-digest` on schedule
- **Alert on GPU heat** — posts to `#ops-alerts` when the GPU runs too hot

---

## The Pieces

| Service | What it does | Local URL |
|---------|-------------|-----------|
| **n8n** | Runs all the automation workflows (the "brain") | http://localhost:5678 |
| **Ollama** | Runs AI models on your GPU | http://localhost:11434 |
| **Open WebUI** | Chat interface for Ollama models | http://localhost:8080 |
| **Grafana** | Monitoring dashboard (GPU, memory, services) | http://localhost:3001 |
| **ComfyUI** | Generates images and video (when running) | http://localhost:8188 |
| **ngrok** | Exposes n8n to the internet so Slack can reach it | Runs inside n8n container |

---

## Daily Operations

### Is everything working?

Open Grafana at **http://localhost:3001** → "AI Workers Hub" dashboard.

Green dots = service is up. If anything is red, see "Restarting Services" below.

You can also test directly in Slack:
- Type `/ai hello` in any channel — you should get a reply within 30 seconds
- Type `/pm test task` — you should get a Linear issue created

---

## Restarting Services

### Restart n8n (most common fix)

```
docker restart n8n-n8n-1
```

Wait about 10 seconds, then try Slack commands again.

### Restart Grafana (if dashboard doesn't load)

```
docker restart grafana
```

### Restart all monitoring (Prometheus + Grafana + exporters)

```
cd /home/biulatech/monitoring
docker compose restart
```

### Restart Ollama (AI models)

```
sudo systemctl restart ollama
```

Check it came back:

```
curl http://localhost:11434/api/tags
```

You should see a list of model names (kevin, jason, etc.).

### Start ComfyUI (image/video generation)

ComfyUI is not started automatically. To start it:

```
cd /home/biulatech/ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188
```

Leave that terminal open while ComfyUI is running. To stop it, press `Ctrl+C`.

---

## Adding or Changing AI Agents

Agents (Kevin, Jason, Scaachi, Christian, Chidi) are Ollama models defined by `Modelfile` files.

**To see current agents:**

```
ollama list
```

**To update an agent's personality/instructions:**

1. Find the Modelfile: `services/ollama/<agent-name>.Modelfile`
2. Edit the `SYSTEM` section — this is the agent's instructions
3. Rebuild the model:

```
ollama create <agent-name> -f services/ollama/<agent-name>.Modelfile
```

No restart needed — Ollama picks it up immediately.

---

## Changing Workflow Automations

Workflows are the automation rules in n8n. You can view and edit them at **http://localhost:5678**.

**To edit a workflow:**
1. Open n8n → click the workflow name
2. Make your changes using the visual editor (drag, click, connect nodes)
3. Click **Save** in the top right
4. If the workflow was already active, it will use the new version immediately

**To activate a workflow** (so it runs automatically):
1. Open the workflow
2. Toggle the switch in the top right from OFF to ON

**To run a workflow manually** (for testing):
1. Open the workflow
2. Click the **Execute Workflow** button (play icon, top right)

---

## Adding a New Slack Token or API Key

All secrets live in one file: `/home/biulatech/n8n/.env`

**To update a value:**

1. Open the file: `nano /home/biulatech/n8n/.env`
2. Find the line with the key you want to change (e.g., `SLACK_BOT_TOKEN=...`)
3. Replace the value after the `=`
4. Save the file (`Ctrl+O`, then `Ctrl+X`)
5. Restart n8n to pick up the new value:

```
docker restart n8n-n8n-1
```

**Key names to know:**

| Key | What it's for |
|-----|--------------|
| `SLACK_BOT_TOKEN` | Slack bot authentication |
| `LINEAR_API_KEY` | Linear project management |
| `NGROK_AUTHTOKEN` | Public URL tunnel to Slack |
| `NGROK_STATIC_DOMAIN` | The fixed domain ngrok uses |

---

## Updating the ngrok URL

If Slack stops receiving events (commands stop working), the ngrok tunnel may have changed.

1. Check the current ngrok URL: look at `NGROK_STATIC_DOMAIN` in `/home/biulatech/n8n/.env`
2. The Slack app's event URL must match: `https://<your-domain>/webhook/slack-events`
3. To update in Slack: go to api.slack.com → your app → **Event Subscriptions** → update the Request URL

With a paid ngrok account and a static domain, this URL should never change.

---

## Monitoring & Alerts

### Grafana Dashboard

Open **http://localhost:3001** → "AI Workers Hub"

What you'll see:
- **GPU section** — utilization %, VRAM used, temperature. Normal: <80°C, <90% utilization
- **System Resources** — CPU and RAM usage
- **Services** — green/red status for each service
- **Workflow Stats** — execution counts from n8n

### GPU is overheating (>85°C)

The GPU alert workflow will post to `#ops-alerts` automatically when this happens.

To reduce GPU load:
- Stop ComfyUI if it's running: press `Ctrl+C` in its terminal
- Check what's using the GPU: `nvidia-smi`

### Checking workflow error logs

In n8n (http://localhost:5678):
1. Click any workflow
2. Click **Executions** (clock icon, left sidebar)
3. Red entries = failed runs — click one to see the error message

---

## Viewing AI Models

To see which AI models are available:

```
ollama list
```

To chat with a model directly (outside of Slack):

```
ollama run kevin
```

Type your message and press Enter. Type `/bye` to exit.

---

## Backup & Restore

### What gets backed up

Backups of the n8n database are stored in `/home/biulatech/backups/n8n/`.

The backup runs automatically. To run it manually:

```
cp /home/biulatech/n8n/n8n_data/database.sqlite /home/biulatech/backups/n8n/database-$(date +%Y%m%d).sqlite
```

### To restore from backup

```
docker stop n8n-n8n-1
cp /home/biulatech/backups/n8n/database-<date>.sqlite /home/biulatech/n8n/n8n_data/database.sqlite
docker start n8n-n8n-1
```

---

## When to Call a Developer

These situations require code-level access:

- A workflow is throwing errors you can't find in n8n's execution logs
- You need to add a completely new Slack command
- The AI models need to be trained differently (model architecture changes)
- ngrok or Slack app credentials need to be reconfigured at the app level
- GPU drivers need updating

For these, share the error from n8n's Executions log and the Grafana screenshot.

---

## Quick Reference

| Problem | First thing to try |
|---------|-------------------|
| Slack commands stopped working | `docker restart n8n-n8n-1` |
| AI responses are slow | Check GPU temp in Grafana — may be throttling |
| No image/video from `/image` | Start ComfyUI (see above) |
| Digests not posting | Check n8n → Weekly News Digest → Executions |
| Dashboard shows red services | `docker ps` to see which container is down, then `docker restart <name>` |
| Ollama not responding | `sudo systemctl restart ollama` |

---

## File Map

```
/home/biulatech/
├── ai-workers-1/          ← All code (this repo)
│   ├── services/
│   │   ├── n8n/workflows/ ← Workflow backup files (JSON)
│   │   └── ollama/        ← Agent personality files (Modelfile)
│   ├── SESSION_CONTEXT.md ← Current system state (for developers)
│   └── OPERATIONS.md      ← This file
├── n8n/
│   ├── .env               ← All secrets and API keys
│   └── n8n_data/          ← n8n database and files
├── monitoring/
│   └── grafana/dashboards/ ← Grafana dashboard definitions
├── ComfyUI/               ← Image/video generation
└── backups/n8n/           ← Database backups
```
