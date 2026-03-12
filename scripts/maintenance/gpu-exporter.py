#!/usr/bin/env python3
"""
NVIDIA GPU Prometheus Exporter — port 9835
Exposes gpu_utilization_percent, gpu_memory_used_mb, gpu_memory_total_mb,
gpu_temperature_celsius for Prometheus scraping.

Install:
  sudo cp configs/systemd/gpu-exporter.service /etc/systemd/system/
  sudo systemctl daemon-reload && sudo systemctl enable --now gpu-exporter

Add to prometheus.yml:
  - job_name: 'gpu-exporter'
    static_configs:
      - targets: ['host.docker.internal:9835']
"""
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 9835


def get_gpu_metrics() -> str:
    result = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
            "--format=csv,noheader,nounits",
        ],
        capture_output=True,
        text=True,
        timeout=5,
    )
    util, mem_used, mem_total, temp = [x.strip() for x in result.stdout.strip().split(",")]
    return (
        "# HELP gpu_utilization_percent GPU utilization percentage\n"
        "# TYPE gpu_utilization_percent gauge\n"
        f"gpu_utilization_percent {util}\n"
        "# HELP gpu_memory_used_mb GPU memory used in MiB\n"
        "# TYPE gpu_memory_used_mb gauge\n"
        f"gpu_memory_used_mb {mem_used}\n"
        "# HELP gpu_memory_total_mb GPU memory total in MiB\n"
        "# TYPE gpu_memory_total_mb gauge\n"
        f"gpu_memory_total_mb {mem_total}\n"
        "# HELP gpu_temperature_celsius GPU temperature in Celsius\n"
        "# TYPE gpu_temperature_celsius gauge\n"
        f"gpu_temperature_celsius {temp}\n"
    )


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            try:
                data = get_gpu_metrics().encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; version=0.0.4")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass  # Suppress access logs; errors go to stderr -> journal


if __name__ == "__main__":
    print(f"GPU exporter listening on 0.0.0.0:{PORT}/metrics", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
