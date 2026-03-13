# Quick Start Guide

**Get your AI Workers team running in 15 minutes.** This guide gets you from zero to a fully functional AI team.

## What You'll Accomplish

✅ Set up your AI Workers environment  
✅ Test all five AI agents  
✅ Send your first task requests  
✅ Verify everything is working  

## What You Need Before Starting

**Hardware Requirements:**
- RTX 5070 Ti GPU (16GB VRAM)
- 64GB RAM (recommended)
- 2TB free disk space

**Software Requirements:**
- Pop!_OS 24.04 LTS (or Ubuntu 24.04)
- NVIDIA drivers 570+ installed
- Docker and Docker Compose
- Internet connection for initial setup

**System Access:**
- Terminal/command line access
- sudo/administrator privileges
- About 30 minutes of uninterrupted time

## Step-by-Step Setup

### Step 1: Verify Your System
```bash
# Run the system check
bash /home/biulatech/ai-workers-1/scripts/setup/00-preflight-check.sh
```

**What you should see:** Green "PASS" messages for hardware, software, and drivers.

**If you see red "FAIL" messages:** Follow the on-screen instructions to fix issues before continuing.

### Step 2: Start Core Services
```bash
# Start Docker services
cd /home/biulatech/n8n
docker compose up -d

# Start Ollama
sudo systemctl start ollama
sudo systemctl enable ollama
```

**What happens:** Docker containers start in the background, Ollama begins loading models.

**Wait time:** 2-3 minutes for services to fully start.

### Step 3: Verify Services Are Running
```bash
# Check service status
bash /home/biulatech/ai-workers-1/scripts/setup/07-post-reboot-verify.sh
```

**What you should see:** All services showing "✅ Running" status.

**If services are missing:** Use the remediation scripts:
```bash
# For issues requiring sudo
sudo bash /home/biulatech/ai-workers-1/scripts/setup/06-remediate-sudo.sh

# For issues not requiring sudo  
bash /home/biulatech/ai-workers-1/scripts/setup/05-remediate-nosudo.sh
```

### Step 4: Download Optimized AI Models
```bash
# Download RTX 5070 Ti optimized models
bash /home/biulatech/ai-workers-1/scripts/download-optimized-models.sh
```

**What happens:** Downloads 5 optimized models (total ~50GB). This can take 20-40 minutes depending on internet speed.

**Progress:** You'll see progress bars and size information for each model.

### Step 5: Set Up Slack Integration
```bash
# Configure Slack tunnel
bash /home/biulatech/ai-workers-1/scripts/setup/04-slack-tunnel-setup.sh
```

**What you need:** Your Slack bot token (from your Slack app settings).

**Result:** Creates secure tunnel so Slack can talk to your local AI team.

### Step 6: Test Your AI Team

#### Test via Web Interface
1. Open your browser
2. Go to `http://localhost:8080`
3. Create an account (first user becomes admin)
4. Try a simple test: "Hello, can you introduce yourself?"

#### Test via Slack
In your Slack workspace, try these commands:

```
/ai kevin: What makes a good system architecture?
/ai jason: Write a simple Python hello world function
/ai scaachi: Write a short intro about AI automation
/ai christian: Design a simple mobile app layout
/ai chidi: Is Python good for web development?
```

**Expected response time:** 15-60 seconds per request.

## What Success Looks Like

### ✅ Web Interface Working
- You can access `http://localhost:8080`
- Chat interface loads and responds
- All 5 agent personalities are available

### ✅ Slack Integration Working  
- `/ai` commands return responses
- Each agent has their distinct personality
- Responses appear in threads

### ✅ System Health Good
- All services show "running" status
- GPU is being utilized (check with `nvidia-smi`)
- No error messages in logs

### ✅ Models Loaded
- Ollama shows 5 models when you run: `ollama list`
- Each model responds within 60 seconds
- No timeout errors

## Common Setup Issues

### Issue: "Docker not running"
**Solution:**
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### Issue: "Ollama connection refused"
**Solution:**
```bash
sudo systemctl restart ollama
# Wait 30 seconds, then test again
```

### Issue: "Slack commands not working"
**Solution:**
1. Check ngrok is running: `ps aux | grep ngrok`
2. Verify tunnel URL: `curl http://localhost:4040/api/tunnels`
3. Update Slack webhook URL if needed

### Issue: "Slow responses or timeouts"
**Solution:**
1. Check GPU usage: `nvidia-smi`
2. Verify models are downloaded: `ollama list`
3. Restart services: `docker compose restart`

### Issue: "Permission denied"
**Solution:**
```bash
# Fix script permissions
chmod +x /home/biulatech/ai-workers-1/scripts/*.sh
```

## Next Steps After Setup

### 🎯 Try Real Tasks
- Ask Kevin to design a system for your project
- Have Jason write some useful code
- Get Scaachi to create marketing content
- Request Christian to prototype an idea
- Ask Chidi to research a technical question

### 📚 Learn More
- Read the [User Guide](USER-GUIDE.md) for detailed agent information
- Check the [Troubleshooting Guide](TROUBLESHOOTING.md) for common issues
- Review the [FAQ](FAQ.md) for frequently asked questions

### 🔧 Customize Your Setup
- Adjust agent personalities in `agents/personalities/`
- Modify system settings in `configs/`
- Add custom workflows in `services/n8n/workflows/`

## Need Help?

### Self-Service
- Check system health: `/ai-diagnose` in Slack
- Review troubleshooting steps in [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Search the [FAQ](FAQ.md) for common questions

### Get Support
If you're still stuck after trying the troubleshooting steps, reach out through your support channels with:
- What you were trying to do
- What error messages you saw
- What you've already tried to fix it

---

**Congratulations!** 🎉 You now have a fully functional AI team ready to help you build, create, and solve problems.
