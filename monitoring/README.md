# Monitoring

Configuration overrides and alert rules for the monitoring stack.

## Components
- `netdata/` — Custom alert thresholds (CPU, GPU, RAM, disk)
- `uptime-kuma/` — Service monitor definitions (exported backup)
- `portainer/` — Stack definitions for Portainer-managed containers

## Alert Routing
All alerts route to n8n via webhook, then to Slack.
n8n webhook endpoint: `http://YOUR_LAN_IP:5678/webhook/monitoring-alert`
