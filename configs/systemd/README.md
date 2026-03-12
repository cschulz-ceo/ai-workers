# systemd Unit Files

Unit files for all ai-workers services. Copy to `/etc/systemd/system/` and enable.

## Units

| File | Service | Description |
|------|---------|-------------|
| `ollama.service.d/override.conf` | Ollama | Drop-in override: binds to `0.0.0.0`, sets VRAM keep-alive and flash attention |
| `ngrok.service` | ngrok | Persists the ngrok tunnel for n8n webhooks as a systemd service |
| `gpu-exporter.service` | GPU Exporter | Runs the NVIDIA GPU Prometheus exporter on port 9835 |

## Install All

```bash
# Ollama override (drop-in — do NOT copy base unit)
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo cp configs/systemd/ollama.service.d/override.conf /etc/systemd/system/ollama.service.d/
sudo systemctl daemon-reload && sudo systemctl restart ollama

# ngrok
sudo cp configs/systemd/ngrok.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now ngrok

# GPU exporter
sudo cp configs/systemd/gpu-exporter.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now gpu-exporter
```

## Verify

```bash
# Ollama on 0.0.0.0
ss -tlnp | grep 11434

# ngrok tunnel active
curl http://localhost:4040/api/tunnels

# GPU metrics
curl http://localhost:9835/metrics
```

## Notes

- **Ollama base unit**: Do NOT edit `/etc/systemd/system/ollama.service` directly. Ollama's
  own installer overwrites it on upgrade. Use the drop-in override only. See ADR-011.
- **ngrok**: Requires ngrok authtoken already configured (`ngrok config add-authtoken <token>`)
  and the static domain provisioned in the ngrok account.
- **GPU exporter**: Requires `scripts/maintenance/gpu-exporter.py` to be present and
  `nvidia-smi` accessible (comes with NVIDIA drivers).
