#!/usr/bin/env python3
"""
OpenSCAD Render API
Accepts POST /render with {code, description}
Renders the OpenSCAD code to STL + PNG preview
Returns {success, stl_b64, png_b64, scad_path, error}
Runs on port 8189.
"""
import base64
import json
import os
import subprocess
import tempfile
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

OUTPUT_DIR = "/home/biulatech/ai-workers-1/output/3d"
os.makedirs(OUTPUT_DIR, exist_ok=True)


def render_scad(code: str) -> dict:
    job_id = str(uuid.uuid4())[:8]
    job_dir = os.path.join(OUTPUT_DIR, job_id)
    os.makedirs(job_dir, exist_ok=True)

    scad_path = os.path.join(job_dir, "model.scad")
    stl_path = os.path.join(job_dir, "model.stl")
    png_path = os.path.join(job_dir, "preview.png")

    with open(scad_path, "w") as f:
        f.write(code)

    result = {"success": False, "job_id": job_id, "scad_path": scad_path}

    # Render STL (headless, no display needed)
    try:
        r = subprocess.run(
            ["openscad", "-o", stl_path, scad_path],
            capture_output=True, timeout=90
        )
        if r.returncode == 0 and os.path.exists(stl_path):
            with open(stl_path, "rb") as f:
                result["stl_b64"] = base64.b64encode(f.read()).decode()
            result["stl_path"] = stl_path
        else:
            result["stl_error"] = r.stderr.decode()[:500]
    except subprocess.TimeoutExpired:
        result["stl_error"] = "Render timeout (90s)"

    # Render PNG preview (needs virtual display)
    try:
        r = subprocess.run(
            [
                "xvfb-run", "--auto-servernum",
                "openscad",
                "--render",
                "--camera=0,0,0,55,0,25,500",
                "--imgsize=800,600",
                "-o", png_path,
                scad_path,
            ],
            capture_output=True, timeout=120
        )
        if r.returncode == 0 and os.path.exists(png_path):
            with open(png_path, "rb") as f:
                result["png_b64"] = base64.b64encode(f.read()).decode()
            result["png_path"] = png_path
        else:
            result["png_error"] = r.stderr.decode()[:500]
    except subprocess.TimeoutExpired:
        result["png_error"] = "Preview render timeout (120s)"

    result["success"] = "stl_b64" in result or "png_b64" in result
    return result


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[openscad-api] {fmt % args}")

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"status": "ok"})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/render":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            code = body.get("code", "").strip()
            if not code:
                self._json(400, {"error": "code is required"})
                return
            result = render_scad(code)
            self._json(200, result)
        except Exception as e:
            self._json(500, {"error": str(e)})

    def _json(self, status, data):
        payload = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8189))
    print(f"[openscad-api] Starting on port {port}")
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
