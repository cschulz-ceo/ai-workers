# Model Selection Guide

How to choose and manage Ollama models for the AI Workers platform.

---

## The Golden Rule: It Must Fit in VRAM

The RTX 5070 Ti has **16 GB of VRAM**. When a model fits entirely in VRAM, it runs at 50-70+ tokens/second. When it spills to system RAM (CPU offloading), performance drops to 2-5 tokens/second — a 10-30x penalty.

**Check if a model fits:** The on-disk size in `ollama list` is a rough guide, but VRAM usage also depends on context length and quantization. Run `ollama ps` while the model is loaded to see actual VRAM consumption.

**Rule of thumb:** Model file size + ~2-3 GB overhead (KV cache at 4K context) should be under 16 GB.

---

## Current Configuration (as of 2026-03-18)

All 5 agents now use **Qwen3 14B Q4_K_M** (9.3 GB on disk, ~11 GB in VRAM):

| Agent | Temperature | Role | Speed |
|-------|-------------|------|-------|
| Kevin | 0.3 | Systems Architect | ~66 tok/s |
| Jason | 0.2 | Full-Stack Engineer | ~66 tok/s |
| Scaachi | 0.8 | Marketing Lead | ~66 tok/s |
| Christian | 0.5 | Startup Strategist | ~66 tok/s |
| Chidi | 0.4 | Research Analyst | ~66 tok/s |

**Previous setup** used qwen2.5:32b (21 GB) and llama3.1:70b (46 GB), both far exceeding VRAM. This caused 5+ minute response times on every Slack command.

---

## Models That Fit in 16 GB VRAM

| Model | Disk Size | VRAM @ 4K ctx | Speed | Strengths |
|-------|-----------|---------------|-------|-----------|
| Qwen3 14B Q4_K_M | 9.3 GB | ~11 GB | ~66 tok/s | Best all-rounder, strong instruction following |
| Llama 3.3 8B Q4_K_M | ~5 GB | ~7 GB | ~100 tok/s | Fastest option, good for quick tasks |
| Gemma 3 12B Q4_K_M | ~7 GB | ~10 GB | ~70 tok/s | Good reasoning, Google-backed |
| Phi-4 14B Q4_K_M | ~8 GB | ~11 GB | ~60 tok/s | Strong at structured tasks |

## Models That Do NOT Fit

| Model | Disk Size | Problem |
|-------|-----------|---------|
| Any 32B model | ~21 GB | Exceeds VRAM, CPU offloads at 2-5 tok/s |
| Any 70B model | ~46 GB | Far exceeds VRAM, mostly runs on CPU at 1-3 tok/s |
| Llama 3.1 405B | ~230 GB | Impossible on this hardware |

---

## Context Window and VRAM

The context window (num_ctx in the Modelfile) directly affects VRAM usage. Each doubling roughly adds 1-2 GB:

| Context Length | VRAM Impact | When to Use |
|----------------|-------------|-------------|
| 2048 | Lowest | Very short Slack replies |
| 4096 (current default) | Low | Standard Slack interactions, commands |
| 8192 | Moderate | Longer documents, patent specs |
| 16384 | High (~+4 GB) | Only if needed for very long context |

The Modelfiles are set to 4096 by default. For specific workflows needing more context (like patent-spec-generator), you can override per-request via the Ollama API's `num_ctx` parameter.

---

## How to Change Models

1. Edit the Modelfile (e.g., `agents/personalities/kevin.Modelfile`):
   ```
   FROM qwen3:14b-q4_K_M   ← change this line
   ```

2. Pull the new base model if needed:
   ```bash
   ollama pull <model-name>
   ```

3. Rebuild the personality:
   ```bash
   ollama create kevin -f agents/personalities/kevin.Modelfile
   ```

4. Test it:
   ```bash
   ollama run kevin "Say hello in one sentence."
   ```

---

## Running Two Models Simultaneously

With Qwen3 14B (~11 GB each), two models fit in 16 GB VRAM. This is useful for The Council's sequential deliberation (avoids reloading between agents).

Add to the Ollama systemd override:
```ini
Environment="OLLAMA_MAX_LOADED_MODELS=2"
```

Then: `sudo systemctl daemon-reload && sudo systemctl restart ollama`

---

## Keeping a Large Model for Offline Work

If you want higher-quality output for batch tasks (e.g., long-form content, detailed patent specs), you can keep `llama3.1:70b` installed and use it selectively through Open WebUI. It will run slowly (1-3 tok/s) but the quality may justify it for non-time-sensitive work.

The Slack-facing agents should always use VRAM-friendly models for responsive interactions.
