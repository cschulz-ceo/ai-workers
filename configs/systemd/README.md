# systemd Unit Files

Unit files for all ai-workers services. Copy to `/etc/systemd/system/` and enable:

```bash
sudo cp configs/systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ollama n8n
```

## Units
(Add unit files as services are configured)
