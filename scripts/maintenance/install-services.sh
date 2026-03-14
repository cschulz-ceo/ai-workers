#!/bin/bash
# Run with sudo to install systemd services
# Usage: sudo bash scripts/maintenance/install-services.sh

set -e
REPO="/home/biulatech/ai-workers-1"

echo "Installing n8n-exporter..."
cp "$REPO/configs/systemd/n8n-exporter.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now n8n-exporter
echo "  n8n-exporter: $(systemctl is-active n8n-exporter)"

echo "Installing gpu-exporter..."
cp "$REPO/configs/systemd/gpu-exporter.service" /etc/systemd/system/
systemctl enable --now gpu-exporter
echo "  gpu-exporter: $(systemctl is-active gpu-exporter)"

echo "Done. Services active:"
systemctl status n8n-exporter gpu-exporter --no-pager -l 2>/dev/null | grep -E "Loaded|Active"
