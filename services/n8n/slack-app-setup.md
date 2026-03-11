# Slack App Setup for n8n Integration

This document walks through creating and configuring the Slack App that connects your local n8n to Slack. The integration enables three channels of communication:

| Direction | Mechanism | Purpose |
|-----------|-----------|---------|
| n8n → Slack | Incoming Webhook | Agent reports, alerts, task completions |
| Slack → n8n | Slash Commands | Trigger n8n workflows from Slack |
| Slack → n8n | Event Subscriptions | React to messages, reactions, mentions |

> **Prerequisites**: Complete `scripts/setup/04-slack-tunnel-setup.sh` first and have your tunnel URL ready (e.g., `https://n8n.yourdomain.com`).

---

## Part 1: Create the Slack App

### 1.1 Create the App

1. Go to **https://api.slack.com/apps**
2. Click **Create New App**
3. Choose **From scratch**
4. App Name: `ai-workers`
5. Pick your Slack workspace
6. Click **Create App**

---

## Part 2: Incoming Webhooks (n8n → Slack)

This allows n8n to post messages to Slack channels without a bot token or rate limits.

### 2.1 Enable Incoming Webhooks

1. In your app settings, go to **Features → Incoming Webhooks**
2. Toggle **Activate Incoming Webhooks** to **On**
3. Scroll down and click **Add New Webhook to Workspace**
4. Select the channel to post to (e.g., `#ai-workers` or `#general`)
5. Click **Allow**
6. Copy the **Webhook URL** — it looks like:
   ```
   https://hooks.slack.com/services/T.../B.../...
   ```

### 2.2 Add to n8n as a Credential

1. Open n8n at `http://YOUR-LAN-IP:5678`
2. Go to **Credentials → Add Credential**
3. Search for **Slack**
4. Choose **Slack API** or **Incoming Webhook**
5. Paste the Webhook URL
6. Save as `Slack Incoming Webhook`

### 2.3 Test It

In n8n, create a simple workflow:
- Trigger: **Manual Trigger**
- Node: **HTTP Request**
  - Method: `POST`
  - URL: your webhook URL
  - Body (JSON): `{"text": "Hello from n8n!"}`

Run it — you should see the message in Slack.

---

## Part 3: Bot Token (Slack → n8n, Reading Messages)

A Bot Token allows n8n to read messages, react to events, and post as a named bot.

### 3.1 Add OAuth Scopes

1. Go to **Features → OAuth & Permissions**
2. Under **Bot Token Scopes**, add:
   - `chat:write` — post messages as the bot
   - `channels:read` — list channels
   - `channels:history` — read channel message history
   - `users:read` — look up user info
   - `commands` — receive slash commands
   - `reactions:write` — add emoji reactions (optional)
   - `files:write` — upload files/images (for ComfyUI output)

### 3.2 Install App to Workspace

1. Go to **Settings → Install App**
2. Click **Install to Workspace**
3. Authorize
4. Copy the **Bot User OAuth Token** — starts with `xoxb-`

### 3.3 Add Bot Token to n8n

1. In n8n, go to **Credentials → Add Credential**
2. Search **Slack**
3. Select **Slack API**
4. Paste the `xoxb-...` token
5. Save as `Slack Bot Token`

---

## Part 4: Slash Commands (Slack → n8n workflows)

Slash commands let you type `/ai-status` or `/run-agent Jason` in Slack and trigger an n8n workflow.

### 4.1 Create a Slash Command

1. Go to **Features → Slash Commands**
2. Click **Create New Command**
3. Configure:
   - **Command**: `/ai` (or `/agent`, your choice)
   - **Request URL**: `https://YOUR-TUNNEL-URL/webhook/slack-command`
     *(replace with your actual cloudflared tunnel URL)*
   - **Short Description**: `Trigger AI agent tasks`
   - **Usage Hint**: `[task description]`
4. Click **Save**

Repeat for any additional commands:

| Command | Webhook Path | Purpose |
|---------|-------------|---------|
| `/ai` | `/webhook/slack-command` | General agent task |
| `/ai-status` | `/webhook/slack-status` | Report system status |
| `/ai-draw` | `/webhook/slack-draw` | Trigger ComfyUI image gen |
| `/ai-diagnose` | `/webhook/slack-diagnose` | Run environment checks |

### 4.2 n8n Webhook Endpoint Setup

In n8n, for each slash command:
1. Create a new workflow
2. Add a **Webhook** trigger node
   - HTTP Method: `POST`
   - Path: `slack-command` (matches URL above)
   - Authentication: None (Slack signs requests — see Part 5 for verification)
3. Add processing nodes (parse `text` field from Slack payload, route to Ollama, etc.)
4. Activate the workflow

Slack sends a POST body like:
```
command=/ai&text=summarize+today&user_name=neil&channel_name=general&response_url=https://hooks.slack.com/...
```

Use the `response_url` to post a delayed reply (for tasks that take >3 seconds).

---

## Part 5: Event Subscriptions (React to Slack messages)

This allows n8n to receive events when messages are posted, reactions added, etc.

### 5.1 Enable Event Subscriptions

1. Go to **Features → Event Subscriptions**
2. Toggle **Enable Events** to **On**
3. **Request URL**: `https://YOUR-TUNNEL-URL/webhook/slack-events`
4. Slack will immediately send a challenge request to verify — **n8n must be running** with a workflow at that path that echoes back the `challenge` field
5. Once verified, add **Subscribe to Bot Events**:
   - `message.channels` — messages in channels the bot is in
   - `app_mention` — when someone @mentions your bot

### 5.2 n8n Challenge Response Workflow

Create this workflow BEFORE adding the Event Subscription URL:

1. **Webhook** node: Path = `slack-events`, Method = POST
2. **IF** node: Check if `body.type == "url_verification"`
3. **Respond to Webhook** node (true branch): Return `{"challenge": "{{$json.body.challenge}}"}`
4. Continue workflow for actual events (false branch)

---

## Part 6: Signing Secret (Request Verification)

Slack signs all outbound requests with your app's signing secret. Verify in n8n to prevent spoofed requests.

### 6.1 Get the Signing Secret

1. Go to **Settings → Basic Information**
2. Under **App Credentials**, copy the **Signing Secret**

### 6.2 Add to n8n Credential

Store the signing secret as an n8n credential or environment variable:
```
N8N_SLACK_SIGNING_SECRET=your_signing_secret
```

In slash command / event webhook workflows, add a **Function** node to verify:
```javascript
const crypto = require('crypto');
const signingSecret = $env.N8N_SLACK_SIGNING_SECRET;
const timestamp = $input.first().headers['x-slack-request-timestamp'];
const signature = $input.first().headers['x-slack-signature'];
const body = $input.first().rawBody;

const sigBasestring = `v0:${timestamp}:${body}`;
const mySignature = 'v0=' + crypto.createHmac('sha256', signingSecret)
    .update(sigBasestring).digest('hex');

if (mySignature !== signature) {
    throw new Error('Invalid Slack signature');
}
return $input.all();
```

---

## Part 7: Manifest (Quick Setup Alternative)

If you prefer, install the app using a manifest instead of the manual steps above.

Save as `slack-app-manifest.yaml` (see `services/n8n/slack-app-manifest.yaml`):

```yaml
display_information:
  name: ai-workers
  description: Autonomous AI agent interface
  background_color: "#1a1a2e"
features:
  bot_user:
    display_name: ai-workers
    always_online: true
  slash_commands:
    - command: /ai
      url: https://YOUR-TUNNEL-URL/webhook/slack-command
      description: Trigger AI agent tasks
      usage_hint: "[task description]"
oauth_config:
  scopes:
    bot:
      - chat:write
      - channels:read
      - channels:history
      - users:read
      - commands
      - reactions:write
      - files:write
settings:
  event_subscriptions:
    request_url: https://YOUR-TUNNEL-URL/webhook/slack-events
    bot_events:
      - message.channels
      - app_mention
  interactivity:
    is_enabled: true
    request_url: https://YOUR-TUNNEL-URL/webhook/slack-interactive
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
```

Go to https://api.slack.com/apps → **Create New App → From a manifest** → paste.

---

## Summary Checklist

- [ ] Slack App created
- [ ] Incoming Webhook URL copied → added to n8n credentials
- [ ] Bot Token (`xoxb-...`) copied → added to n8n credentials
- [ ] Signing Secret copied → added to n8n env / credentials
- [ ] Slash command `/ai` created → pointing to tunnel URL
- [ ] Event subscriptions enabled → pointing to tunnel URL
- [ ] n8n `url_verification` workflow active before enabling events
- [ ] n8n `WEBHOOK_URL` updated to tunnel URL in `~/n8n/docker-compose.yml`
- [ ] n8n restarted after WEBHOOK_URL change
- [ ] Test: send `/ai hello` in Slack → verify n8n receives it
- [ ] Test: n8n workflow posts to Slack → verify message appears
