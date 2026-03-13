# Frequently Asked Questions

**Quick answers to common questions about AI Workers.**

## System Questions

### Q: What exactly is AI Workers?
**A:** AI Workers is a local AI system that gives you a team of 5 specialized AI agents (Kevin, Jason, Scaachi, Christian, Chidi) that handle different tasks like architecture, coding, content, prototyping, and research. Everything runs on your local computer for complete privacy.

### Q: How is this different from ChatGPT?
**A:** 
- **Privacy**: Everything runs locally, no data leaves your computer
- **Specialization**: Each agent has expertise in their domain
- **Integration**: Works with your existing tools like Slack and GitHub
- **Cost**: No subscription fees after initial setup
- **Customization**: Agents can be tailored to your specific needs

### Q: What are the hardware requirements?
**A:** 
- **GPU**: RTX 5070 Ti (16GB VRAM) recommended
- **RAM**: 64GB DDR5 recommended (32GB minimum)
- **Storage**: 2TB NVMe SSD (500GB minimum)
- **OS**: Pop!_OS 24.04 LTS or Ubuntu 24.04

### Q: Can I run this on weaker hardware?
**A:** Partially. You can run smaller models on RTX 3060/4060 with 8GB VRAM, but performance will be slower and some agents may not work optimally.

### Q: How much does this cost to run?
**A:** 
- **Software**: Free (all open-source)
- **Hardware**: One-time cost of your computer
- **Electricity**: Similar to running a gaming PC (~$20-50/month depending on usage)

### Q: Is this secure?
**A:** Yes. Everything runs locally on your computer. No data is sent to external servers except for:
- Slack integration (if you enable it)
- Optional cloud backup (if you configure it)

---

## Agent Capabilities

### Q: What can each agent do?
**A:**
- **Kevin (Architect)**: System design, technical planning, architecture diagrams
- **Jason (Engineer)**: Code writing, debugging, automation, technical implementation
- **Scaachi (Marketing)**: Content creation, copywriting, marketing strategies
- **Christian (Prototyper)**: Quick prototypes, UI design, MVP development
- **Chidi (Researcher)**: Feasibility analysis, technical research, problem solving

### Q: Can agents work together?
**A:** Yes! They can reference each other's work. For example:
1. Ask Kevin to design a system
2. Ask Jason to implement Kevin's design
3. Ask Scaachi to write documentation for it

### Q: Can agents learn from my company data?
**A:** Agents learn from context within a conversation but don't retain information between conversations. They can't access your files unless you provide the content in the conversation.

### Q: Can I create custom agents?
**A:** Yes. You can modify the Modelfiles in `agents/personalities/` to create new personas or adjust existing ones.

### Q: How good are they at coding?
**A:** Jason is excellent at most programming tasks (Python, JavaScript, Bash, etc.). He can write complete, working code, debug issues, and explain technical concepts.

### Q: Can they write documentation?
**A:** Yes. Kevin excels at technical documentation, Scaachi at user-facing content, and all agents can explain their work clearly.

---

## Performance Issues

### Q: Why are responses sometimes slow?
**A:** Common causes:
- Large models loading into GPU memory
- Multiple requests running simultaneously  
- System resources (RAM/VRAM) running low
- Complex tasks requiring more processing

**Solutions:**
- Wait for initial model loading (first request is slower)
- Use `/ai-status` to check system health
- Restart services if needed: `sudo systemctl restart ollama`

### Q: What causes timeout errors?
**A:** Usually one of these:
- Request takes longer than 5 minutes (default timeout)
- Model not properly loaded
- GPU memory issues
- Network connectivity problems

**Solutions:**
- Break complex tasks into smaller steps
- Check system health with `/ai-diagnose`
- Restart services: `sudo systemctl restart ollama`

### Q: How can I improve performance?
**A:** 
- Use optimized models (run the download script)
- Close unnecessary applications
- Ensure sufficient RAM and VRAM
- Use appropriate agents for specific tasks

### Q: Why does the first response take longer?
**A:** The first request loads the model into GPU memory. Subsequent requests are much faster until the model is unloaded (after 5 minutes of inactivity by default).

---

## Integration & Usage

### Q: How do I use AI Workers with Slack?
**A:** 
1. Set up Slack integration with the setup script
2. Use `/ai [agent]: your request` in any Slack channel
3. Or mention @ai-workers in channels
4. Agents respond in threads

### Q: Can I use this without Slack?
**A:** Yes. Use the web interface at `http://localhost:8080` or direct API calls to `http://localhost:11434`.

### Q: Can agents access my files?
**A:** No, agents cannot access your files directly for security. You need to provide file content in your requests.

### Q: Can agents execute code?
**A:** No, agents cannot execute code directly on your system. They can write code that you can run yourself.

### Q: How do I get the best results?
**A:** 
- Be specific in your requests
- Provide relevant context
- Use the right agent for the task
- Break complex tasks into steps
- Ask follow-up questions if needed

---

## Models & Technical

### Q: What models are the agents using?
**A:** Optimized versions of:
- **Kevin**: Qwen2.5 32B (architecture focus)
- **Jason**: DeepSeek Coder V2 Lite 16B (coding focus)
- **Scaachi**: Llama 3.1 8B (content focus)
- **Christian**: Qwen2.5 14B (prototyping focus)
- **Chidi**: Mistral Small 22B (research focus)

### Q: Can I use different models?
**A:** Yes. You can modify the `FROM` line in each agent's Modelfile to use different Ollama models.

### Q: How much VRAM do the models use?
**A:** 
- Kevin: ~19GB
- Jason: ~10GB  
- Scaachi: ~5GB
- Christian: ~9GB
- Chidi: ~12GB

### Q: Can I run multiple agents simultaneously?
**A:** Yes, but it requires more VRAM. With 16GB VRAM, you can run 1-2 agents simultaneously comfortably.

### Q: What happens if I run out of VRAM?
**A:** The system will use system RAM, which is much slower. You may see significant performance degradation.

---

## Troubleshooting

### Q: How do I know if everything is working?
**A:** Run `/ai-status` in Slack or use the system verification script:
```bash
bash /home/biulatech/ai-workers-1/scripts/setup/07-post-reboot-verify.sh
```

### Q: What should I do if an agent gives wrong answers?
**A:** 
- Be more specific in your request
- Provide more context
- Try rephrasing your question
- Use a different agent if better suited
- Check if the task is within the agent's expertise

### Q: How do I reset the system?
**A:** 
```bash
# Restart all services
sudo systemctl restart ollama
cd /home/biulatech/n8n && docker compose restart
cd /home/biulatech/open-webui && docker compose restart
```

### Q: Where can I find error logs?
**A:** 
- Ollama: `journalctl -u ollama -f`
- n8n: `cd /home/biulatech/n8n && docker compose logs -f`
- System: `/var/log/` directory

---

## Privacy & Security

### Q: Is my data private?
**A:** Yes. All processing happens locally on your computer. No data is sent to external servers except for Slack integration (if enabled).

### Q: Can agents access the internet?
**A:** No, agents cannot access the internet directly. They work with the knowledge they were trained on and information you provide.

### Q: Are my conversations stored?
**A:** Conversations are stored locally in the n8n database and Ollama logs. They are not sent to external servers.

### Q: Can I use this for sensitive work?
**A:** Yes, the local-only nature makes it suitable for sensitive work, but follow your organization's data policies.

---

## Updates & Maintenance

### Q: How do I update the system?
**A:** 
```bash
# Update models
ollama pull [model-name]

# Update Docker images
cd /home/biulatech/n8n && docker compose pull
cd /home/biulatech/open-webui && docker compose pull

# Restart services
sudo systemctl restart ollama
```

### Q: How often should I update?
**A:** Check for updates monthly, or when you encounter issues that might be fixed by newer versions.

### Q: Will updates break my setup?
**A:** Generally no, but backup your configuration before major updates:
```bash
cp -r /home/biulatech/ai-workers-1/configs/ ~/backup-configs/
```

---

## Business & Usage

### Q: Can I use this for commercial projects?
**A:** Yes, all components are open-source with commercial-friendly licenses.

### Q: How reliable is this for production use?
**A:** It's quite reliable for development and internal tools. For critical production systems, ensure proper monitoring and backup procedures.

### Q: Can multiple people use this at once?
**A:** Yes, through the web interface or Slack integration. Performance will depend on available hardware resources.

### Q: What's the limit on what agents can do?
**A:** Agents are limited by:
- Their training data and knowledge
- Available system resources
- Their specific domain expertise
- The context window size (typically 16K tokens)

---

**Still have questions?** Check the [Troubleshooting Guide](TROUBLESHOOTING.md) or run `/ai-diagnose` for system health checks.
