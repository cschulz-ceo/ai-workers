#!/usr/bin/env python3
"""
n8n Queue Metrics Exporter — Enhanced version with Redis and PostgreSQL support
Exposes comprehensive metrics for n8n queue mode monitoring.

New Metrics:
  n8n_queue_depth              gauge (current queue length)
  n8n_active_workers           gauge (active worker count)
  n8n_worker_utilization      gauge (worker CPU/memory %)
  n8n_queue_wait_time          gauge (average wait time in seconds)
  n8n_throughput               gauge (jobs per minute)
  n8n_system_health            gauge (overall health 1/0)
  n8n_processing_rate          gauge (requests per second)
  ollama_response_time          gauge (Ollama API response time)
  ollama_models_available       gauge (number of available models)
  redis_memory_used              gauge (Redis memory usage)
  postgres_connections           gauge (PostgreSQL active connections)

Install:
  docker build -t n8n-exporter-queue .
  docker run -d --name n8n-exporter-queue -p 9201:9201 n8n-exporter-queue

Add to prometheus.yml:
  - job_name: 'n8n-queue-exporter'
    static_configs:
      - targets: ['host.docker.internal:9201']
"""

import sqlite3
import redis
import os
import time
import requests
import psycopg2
import json
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

def get_redis_connection():
    """Get Redis connection with error handling"""
    try:
        return redis.Redis(
            host=os.environ.get('QUEUE_BULL_REDIS_HOST', 'redis'),
            port=int(os.environ.get('QUEUE_BULL_REDIS_PORT', '6379')),
            password=os.environ.get('QUEUE_BULL_REDIS_PASSWORD'),
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            retry_on_timeout=True
        )
    except Exception as e:
        print(f"Redis connection error: {e}")
        return None

def get_postgres_connection():
    """Get PostgreSQL connection with error handling"""
    try:
        return psycopg2.connect(
            host=os.environ.get('DB_POSTGRESDB_HOST', 'postgres'),
            port=int(os.environ.get('DB_POSTGRESDB_PORT', '5432')),
            database=os.environ.get('DB_POSTGRESDB_DATABASE', 'n8n_queue'),
            user=os.environ.get('DB_POSTGRESDB_USER', 'n8n'),
            password=os.environ.get('DB_POSTGRESDB_PASSWORD'),
            connect_timeout=5,
            application_name='n8n-exporter'
        )
    except Exception as e:
        print(f"PostgreSQL connection error: {e}")
        return None

def get_queue_metrics():
    """Get Redis queue statistics"""
    r = get_redis_connection()
    if not r:
        return {'queue_depth': 0, 'error': 'Redis connection failed'}
    
    try:
        # Get queue statistics
        queue_depth = r.llen('n8n:queue') or 0
        active_workers = r.scard('n8n:workers') or 0
        processing_rate = float(r.get('n8n:processing_rate', 0) or 0)
        avg_wait_time = float(r.get('n8n:avg_wait_time', 0) or 0)
        
        # Calculate throughput
        throughput = r.get('n8n:throughput', 0) or 0
        
        # Get Redis memory usage
        redis_info = r.info()
        redis_memory = redis_info.get('used_memory', 0)
        
        return {
            'queue_depth': queue_depth,
            'active_workers': active_workers,
            'processing_rate': processing_rate,
            'avg_wait_time': avg_wait_time,
            'throughput': throughput,
            'redis_memory_used': redis_memory
        }
    except Exception as e:
        return {
            'queue_depth': 0,
            'active_workers': 0,
            'processing_rate': 0,
            'avg_wait_time': 0,
            'throughput': 0,
            'redis_memory_used': 0,
            'error': str(e)
        }

def get_worker_metrics():
    """Get worker performance metrics"""
    r = get_redis_connection()
    if not r:
        return {'worker_count': 0, 'error': 'Redis connection failed'}
    
    try:
        workers = r.smembers('n8n:workers') or []
        worker_metrics = {}
        
        for worker_id in workers:
            if isinstance(worker_id, bytes):
                worker_id = worker_id.decode('utf-8')
            
            # CPU and memory usage per worker
            cpu_usage = float(r.get(f'n8n:worker:{worker_id}:cpu') or 0)
            memory_usage = float(r.get(f'n8n:worker:{worker_id}:memory') or 0)
            
            worker_metrics[worker_id] = {
                'cpu_usage': cpu_usage,
                'memory_usage': memory_usage
            }
        
        return {
            'worker_count': len(worker_metrics),
            'worker_metrics': worker_metrics
        }
    except Exception as e:
        return {
            'worker_count': 0,
            'worker_metrics': {},
            'error': str(e)
        }

def get_system_metrics():
    """Get overall system health metrics"""
    try:
        # Check n8n health
        response = requests.get('http://localhost:5678/healthz', timeout=5)
        n8n_healthy = response.status_code == 200
        
        # Check Redis connectivity
        r = get_redis_connection()
        redis_connected = r.ping() == b'PONG' if r else False
        
        # Check PostgreSQL connectivity
        pg_conn = get_postgres_connection()
        postgres_connected = pg_conn is not None
        if pg_conn:
            pg_conn.close()
        
        return {
            'n8n_healthy': n8n_healthy,
            'redis_connected': redis_connected,
            'postgres_connected': postgres_connected,
            'overall_health': n8n_healthy and redis_connected and postgres_connected
        }
    except Exception as e:
        return {
            'n8n_healthy': False,
            'redis_connected': False,
            'postgres_connected': False,
            'overall_health': False,
            'error': str(e)
        }

def get_ollama_metrics():
    """Get Ollama API metrics"""
    try:
        # Connect to Ollama API
        response = requests.get('http://localhost:11434/api/tags', timeout=5)
        
        if response.status_code == 200:
            models = response.json().get('models', [])
            total_models = len(models)
            
            return {
                'models_available': total_models,
                'api_healthy': True,
                'response_time': response.elapsed.total_seconds()
            }
        else:
            return {
                'models_available': 0,
                'api_healthy': False,
                'response_time': 0
            }
    except Exception as e:
        return {
            'models_available': 0,
            'api_healthy': False,
            'response_time': 0,
            'error': str(e)
        }

def get_postgres_metrics():
    """Get PostgreSQL database metrics"""
    pg_conn = get_postgres_connection()
    if not pg_conn:
        return {'connections': 0, 'error': 'PostgreSQL connection failed'}
    
    try:
        cursor = pg_conn.cursor()
        
        # Get connection count
        cursor.execute("SELECT count(*) FROM pg_stat_activity WHERE state = 'active';")
        active_connections = cursor.fetchone()[0]
        
        cursor.close()
        pg_conn.close()
        
        return {
            'connections': active_connections
        }
    except Exception as e:
        return {
            'connections': 0,
            'error': str(e)
        }

def get_workflow_metrics():
    """Get workflow execution metrics from database"""
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
                    ts_str_clean = ts_str.replace("Z", "+00:00") if ts_str else ""
                    if ts_str_clean:
                        import datetime
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

def get_metrics() -> str:
    """Get all metrics for Prometheus scraping"""
    try:
        lines = []
        
        # Add queue metrics
        queue_metrics = get_queue_metrics()
        lines.append("# HELP n8n_queue_depth Current queue depth")
        lines.append("# TYPE n8n_queue_depth gauge")
        lines.append(f"n8n_queue_depth {queue_metrics.get('queue_depth', 0)}")
        
        lines.append("# HELP n8n_active_workers Current active worker count")
        lines.append("# TYPE n8n_active_workers gauge")
        lines.append(f"n8n_active_workers {queue_metrics.get('active_workers', 0)}")
        
        lines.append("# HELP n8n_worker_utilization Worker CPU/memory utilization")
        lines.append("# TYPE n8n_worker_utilization gauge")
        
        worker_metrics = get_worker_metrics()
        for worker_id, metrics in worker_metrics.get('worker_metrics', {}).items():
            lines.append(f'n8n_worker_utilization{{worker="{worker_id}",metric="cpu"}} {metrics.get("cpu_usage", 0)}')
            lines.append(f'n8n_worker_utilization{{worker="{worker_id}",metric="memory"}} {metrics.get("memory_usage", 0)}')
        
        lines.append("# HELP n8n_queue_wait_time Average time in queue")
        lines.append("# TYPE n8n_queue_wait_time gauge")
        lines.append(f"n8n_queue_wait_time {queue_metrics.get('avg_wait_time', 0)}")
        
        lines.append("# HELP n8n_throughput Jobs processed per minute")
        lines.append("# TYPE n8n_throughput gauge")
        lines.append(f"n8n_throughput {queue_metrics.get('throughput', 0)}")
        
        lines.append("# HELP n8n_processing_rate Processing rate per second")
        lines.append("# TYPE n8n_processing_rate gauge")
        lines.append(f"n8n_processing_rate {queue_metrics.get('processing_rate', 0)}")
        
        # Add system health metrics
        system_metrics = get_system_metrics()
        lines.append("# HELP n8n_system_health Overall system health status")
        lines.append("# TYPE n8n_system_health gauge")
        lines.append(f"n8n_system_health {1 if system_metrics.get('overall_health', False) else 0}")
        
        # Add Ollama metrics
        ollama_metrics = get_ollama_metrics()
        lines.append("# HELP ollama_response_time Ollama average response time")
        lines.append("# TYPE ollama_response_time gauge")
        lines.append(f"ollama_response_time {ollama_metrics.get('response_time', 0)}")
        
        lines.append("# HELP ollama_models_available Number of available models")
        lines.append("# TYPE ollama_models_available gauge")
        lines.append(f"ollama_models_available {ollama_metrics.get('models_available', 0)}")
        
        # Add Redis memory metrics
        lines.append("# HELP redis_memory_used Redis memory usage in bytes")
        lines.append("# TYPE redis_memory_used gauge")
        lines.append(f"redis_memory_used {queue_metrics.get('redis_memory_used', 0)}")
        
        # Add PostgreSQL metrics
        postgres_metrics = get_postgres_metrics()
        lines.append("# HELP postgres_connections PostgreSQL active connections")
        lines.append("# TYPE postgres_connections gauge")
        lines.append(f"postgres_connections {postgres_metrics.get('connections', 0)}")
        
        # Add workflow metrics
        lines.append(get_workflow_metrics())
        
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
    print(f"n8n queue metrics exporter running on :{PORT}/metrics")
    server.serve_forever()
