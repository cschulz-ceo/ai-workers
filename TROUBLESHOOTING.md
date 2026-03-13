# Troubleshooting Guide

**Solve common AI Workers problems quickly.** This guide helps you diagnose and fix issues without needing technical support.

## Quick Diagnostics

### Run System Health Check
```bash
# Comprehensive system diagnosis
/ai-diagnose
```
This command checks all services and reports issues in Slack.

### Check Service Status
```bash
# Quick service check
bash /home/biulatech/ai-workers-1/scripts/setup/07-post-reboot-verify.sh
```

### Monitor GPU Usage
```bash
# Check if GPU is being used
nvidia-smi
```

---

## Agent Not Responding

### Symptoms
- Slack commands show no response
- Web interface says "loading" or "error"
- Requests time out after 5 minutes

### Causes & Solutions

#### Cause 1: Ollama Service Down
**Check:**
```bash
systemctl status ollama
```

**Fix:**
```bash
sudo systemctl restart ollama
sudo systemctl enable ollama
```

#### Cause 2: Models Not Downloaded
**Check:**
```bash
ollama list
```

**Fix:**
```bash
# Download optimized models
bash /home/biulatech/ai-workers-1/scripts/download-optimized-models.sh
```

#### Cause 3: GPU Not Available
**Check:**
```bash
nvidia-smi
# Look for "No devices" or errors
```

**Fix:**
```bash
# Reload NVIDIA drivers
sudo modprobe nvidia
sudo systemctl restart ollama
```

#### Cause 4: Docker Services Down
**Check:**
```bash
cd /home/biulatech/n8n
docker compose ps
```

**Fix:**
```bash
cd /home/biulatech/n8n
docker compose restart
```

#### Cause 5: Network Issues
**Check:**
```bash
# Test Ollama directly
curl http://localhost:11434/api/tags

# Test n8n directly
curl http://localhost:5678/healthz
```

**Fix:**
```bash
# Restart networking services
sudo systemctl restart docker
sudo systemctl restart ollama
```

---

## Slow Response Times

### Symptoms
- Agents take 2+ minutes to respond
- Simple questions take a long time
- Intermittent slow performance

### Causes & Solutions

#### Cause 1: Large Models in Memory
**Check:**
```bash
# Monitor GPU memory usage
watch -n 1 nvidia-smi
```

**Fix:**
```bash
# Restart Ollama to clear memory
sudo systemctl restart ollama

# Use smaller models for testing
/ai jason: Write a simple hello world function
```

#### Cause 2: System Resources Low
**Check:**
```bash
# Check RAM usage
free -h

# Check CPU usage
top
```

**Fix:**
```bash
# Close unnecessary applications
# Restart services to clear memory
sudo systemctl restart ollama
cd /home/biulatech/n8n && docker compose restart
```

#### Cause 3: Multiple Concurrent Requests
**Check:**
```bash
# Check for multiple Ollama processes
ps aux | grep ollama
```

**Fix:**
```bash
# Wait for current requests to finish
# Or restart Ollama to clear queue
sudo systemctl restart ollama
```

---

## Connection Issues

### Slack Commands Not Working

#### Symptoms
- `/ai` commands show "not found" or no response
- Slack app mentions don't trigger responses
- Webhook errors in logs

#### Causes & Solutions

**Cause 1: ngrok Tunnel Down**
**Check:**
```bash
ps aux | grep ngrok
curl http://localhost:4040/api/tunnels
```

**Fix:**
```bash
# Restart ngrok
systemctl --user restart ngrok
systemctl --user enable ngrok
```

**Cause 2: Slack App Configuration**
**Check:**
- Slack app features → Event Subscriptions → Enabled
- Webhook URL matches ngrok tunnel
- Bot permissions include required scopes

**Fix:**
1. Update Slack webhook URL to current ngrok URL
2. Re-enable Event Subscriptions
3. Verify bot is invited to channels

**Cause 3: n8n Webhooks Not Receiving**
**Check:**
```bash
# Test n8n webhook endpoint
curl -X POST http://localhost:5678/webhook/slack-events \
  -H "Content-Type: application/json" \
  -d '{"test": "message"}'
```

**Fix:**
```bash
# Restart n8n
cd /home/biulatech/n8n
docker compose restart
```

### Web Interface Not Working

#### Symptoms
- `http://localhost:8080` shows connection refused
- Login page not loading
- Chat interface shows errors

#### Causes & Solutions

**Cause 1: Open WebUI Service Down**
**Check:**
```bash
cd /home/biulatech/open-webui
docker compose ps
```

**Fix:**
```bash
cd /home/biulatech/open-webui
docker compose restart
```

**Cause 2: Port Conflicts**
**Check:**
```bash
# Check if port 8080 is in use
ss -tlnp | grep :8080
```

**Fix:**
```bash
# Kill process using port 8080
sudo kill -9 [PID]
# Restart Open WebUI
cd /home/biulatech/open-webui && docker compose restart
```

**Cause 3: Ollama Connection Issues**
**Check:**
```bash
# Test Ollama from Open WebUI container
docker exec -it open-webui curl http://host.docker.internal:11434/api/tags
```

**Fix:**
```bash
# Ensure Ollama binds to 0.0.0.0
sudo systemctl restart ollama
```

---

## Model Problems

### Model Download Failures

#### Symptoms
- Download script shows errors
- Models appear corrupted
- `ollama list` shows unexpected sizes

#### Solutions

**Fix 1: Resume Download**
```bash
# Re-run download script (has resume support)
bash /home/biulatech/ai-workers-1/scripts/download-optimized-models.sh
```

**Fix 2: Manual Model Removal**
```bash
# Remove corrupted model
ollama rm model-name

# Re-download
ollama pull model-name
```

**Fix 3: Clear Ollama Cache**
```bash
# Stop Ollama
sudo systemctl stop ollama

# Clear cache (optional - removes all models)
sudo rm -rf /usr/share/ollama/.ollama/models/*

# Restart and re-download
sudo systemctl start ollama
bash /home/biulatech/ai-workers-1/scripts/download-optimized-models.sh
```

### Model Performance Issues

#### Symptoms
- Specific agent always slow
- Model gives poor quality responses
- Model uses excessive VRAM

#### Solutions

**Fix 1: Check Model Configuration**
```bash
# Review agent Modelfile
cat /home/biulatech/ai-workers-1/agents/personalities/[agent].Modelfile
```

**Fix 2: Recreate Agent Model**
```bash
# Remove and recreate agent model
ollama rm agent-name
# Edit Modelfile if needed
ollama create agent-name -f /home/biulatech/ai-workers-1/agents/personalities/[agent].Modelfile
```

**Fix 3: Use Different Quantization**
```bash
# Try different model version
ollama pull model-name:q4_K_M  # Smaller, faster
# or
ollama pull model-name:q5_K_M  # Better quality
```

---

## System Resource Issues

### Out of Memory Errors

#### Symptoms
- System becomes unresponsive
- Services crash randomly
- "Out of memory" errors in logs

#### Solutions

**Fix 1: Check Memory Usage**
```bash
# Monitor memory usage
free -h
ps aux --sort=-%mem | head -10
```

**Fix 2: Optimize Model Usage**
```bash
# Use smaller models
# Restart services to clear memory
sudo systemctl restart ollama
cd /home/biulatech/n8n && docker compose restart
```

**Fix 3: Add Swap Space**
```bash
# Create 8GB swap file
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Disk Space Issues

#### Symptoms
- Model downloads fail
- Services won't start
- "No space left on device" errors

#### Solutions

**Fix 1: Check Disk Usage**
```bash
df -h
# Look for full partitions
```

**Fix 2: Clean Up Docker**
```bash
# Remove unused Docker images
docker system prune -a

# Remove unused volumes
docker volume prune
```

**Fix 3: Clean Model Cache**
```bash
# List models with sizes
ollama list

# Remove unused models
ollama rm unused-model-name
```

---

## When to Get Help

### Try These First
1. Run `/ai-diagnose` in Slack
2. Check this troubleshooting guide
3. Review the [FAQ](FAQ.md)
4. Try restarting services

### Contact Support When
- You've tried all relevant solutions above
- Multiple services are failing
- You're seeing error messages not covered here
- Hardware appears to be failing (GPU errors, etc.)

### Information to Provide
1. What you were trying to do
2. Exact error messages
3. What you've already tried
4. Output of `/ai-diagnose`
5. How long the issue has been occurring

---

## Prevention Tips

### Regular Maintenance
- Run system health checks weekly: `/ai-status`
- Monitor disk space monthly: `df -h`
- Keep models updated: Check for new optimized versions
- Backup configurations: Copy `configs/` directory regularly

### Best Practices
- Don't run multiple large models simultaneously
- Restart services weekly to clear memory
- Monitor GPU temperature during heavy use
- Keep system updated with latest drivers

---

**Still having issues?** The [FAQ](FAQ.md) has answers to common questions, or reach out to support with the information above.
