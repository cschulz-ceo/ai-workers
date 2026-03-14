#!/usr/bin/env python3
"""
n8n Workflow Prometheus Exporter — port 9201
Exposes per-workflow execution metrics for Prometheus scraping.

Metrics:
  n8n_workflow_last_status          gauge (1=success, 0=error, -1=unknown)
  n8n_workflow_success_total_24h    gauge
  n8n_workflow_error_total_24h      gauge
  n8n_workflow_last_run_timestamp   gauge (unix seconds)
  n8n_workflow_avg_duration_ms_24h  gauge

Install:
  sudo cp configs/systemd/n8n-exporter.service /etc/systemd/system/
  sudo systemctl daemon-reload && sudo systemctl enable --now n8n-exporter

Add to prometheus.yml:
  - job_name: 'n8n-exporter'
    static_configs:
      - targets: ['host.docker.internal:9201']
"""
import sqlite3
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 9201
DB_PATH = "/home/biulatech/n8n/n8n_data/database.sqlite"

# Workflows to track — (display_name, workflow_id)
WORKFLOWS = [
    ("slack_events_receiver",    "f5rTNCSNGXwKiwvE"),
    ("slack_command_handler",    "VqmllB5WdHsKmntj"),
    ("slack_status_handler",     "KxnpgKyTLMAd4Ygs"),
    ("slack_diagnose_handler",   "QCrmHKpu1KktTK1M"),
    ("tasks_channel_handler",    "i1TOhKVyXkLXD01W"),
    ("the_council_router",       "counsel-router-001"),
    ("linear_ai_pm",             "linear-pm-001"),
    ("ops_gpu_alert",            "ops-gpu-alert-001"),
    ("ops_daily_digest",         "IBYZgfl7Du9jTWp6"),
    ("ops_service_monitor",      "hKRONxaLSsSfVjO4"),
    ("github_push_handler",      "ZWma6DaWSwTdvft8"),
    ("news_article_generator",   "cf2282e0-c226-4030-8df4-59ec9fb61a7c"),
    ("weekly_news_digest",       "d7350619-528b-481d-bb87-fa245d2734bb"),
    ("comfyui_text_to_image",    "comfyui-t2i-001"),
    ("comfyui_text_to_video",    "comfyui-t2v-001"),
    ("comfyui_image_enhance",    "comfyui-enh-001"),
    ("cad_3d_generator",         "cad-3d-001"),
    ("patent_spec_generator",    "patent-spec-001"),
    ("preview_image_server",     "preview-image-001"),
]


def get_metrics() -> str:
    try:
        conn = sqlite3.connect(DB_PATH, timeout=5)
        cur = conn.cursor()

        lines = []
        lines.append("# HELP n8n_workflow_last_status Last execution status (1=success 0=error -1=unknown)")
        lines.append("# TYPE n8n_workflow_last_status gauge")
        lines.append("# HELP n8n_workflow_success_total_24h Successful executions in last 24h")
        lines.append("# TYPE n8n_workflow_success_total_24h gauge")
        lines.append("# HELP n8n_workflow_error_total_24h Failed executions in last 24h")
        lines.append("# TYPE n8n_workflow_error_total_24h gauge")
        lines.append("# HELP n8n_workflow_last_run_timestamp Unix timestamp of last execution")
        lines.append("# TYPE n8n_workflow_last_run_timestamp gauge")
        lines.append("# HELP n8n_workflow_avg_duration_ms_24h Average execution duration ms in last 24h")
        lines.append("# TYPE n8n_workflow_avg_duration_ms_24h gauge")

        for name, wf_id in WORKFLOWS:
            label = f'workflow="{name}",id="{wf_id}"'

            # Last execution status + timestamp
            cur.execute("""
                SELECT status, stoppedAt, startedAt
                FROM execution_entity
                WHERE workflowId = ?
                ORDER BY startedAt DESC
                LIMIT 1
            """, (wf_id,))
            row = cur.fetchone()

            if row:
                status_str, stopped_at, started_at = row
                last_status = 1 if status_str == "success" else 0

                # Parse timestamp (stored as ISO string)
                ts_str = stopped_at or started_at or ""
                try:
                    import datetime
                    ts_str_clean = ts_str.replace("Z", "+00:00") if ts_str else ""
                    if ts_str_clean:
                        dt = datetime.datetime.fromisoformat(ts_str_clean)
                        last_ts = dt.timestamp()
                    else:
                        last_ts = 0
                except Exception:
                    last_ts = 0
            else:
                last_status = -1
                last_ts = 0

            lines.append(f"n8n_workflow_last_status{{{label}}} {last_status}")
            lines.append(f"n8n_workflow_last_run_timestamp{{{label}}} {last_ts:.0f}")

            # 24h success / error counts
            cur.execute("""
                SELECT
                    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END),
                    SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)
                FROM execution_entity
                WHERE workflowId = ?
                  AND startedAt >= datetime('now', '-24 hours')
            """, (wf_id,))
            counts = cur.fetchone()
            success_24h = counts[0] or 0 if counts else 0
            error_24h   = counts[1] or 0 if counts else 0

            lines.append(f"n8n_workflow_success_total_24h{{{label}}} {success_24h}")
            lines.append(f"n8n_workflow_error_total_24h{{{label}}} {error_24h}")

            # Avg duration last 24h (stoppedAt - startedAt in ms)
            cur.execute("""
                SELECT AVG(
                    (julianday(stoppedAt) - julianday(startedAt)) * 86400000
                )
                FROM execution_entity
                WHERE workflowId = ?
                  AND startedAt >= datetime('now', '-24 hours')
                  AND stoppedAt IS NOT NULL
            """, (wf_id,))
            dur_row = cur.fetchone()
            avg_dur = dur_row[0] or 0 if dur_row else 0

            lines.append(f"n8n_workflow_avg_duration_ms_24h{{{label}}} {avg_dur:.0f}")

        conn.close()
        return "\n".join(lines) + "\n"

    except Exception as e:
        return f"# ERROR: {e}\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/metrics", "/metrics/"):
            self.send_response(404)
            self.end_headers()
            return
        body = get_metrics().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # suppress access logs


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"n8n exporter running on :{PORT}/metrics")
    server.serve_forever()
