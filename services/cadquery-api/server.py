#!/usr/bin/env python3
"""
CadQuery Generate-and-Render API
Accepts POST /generate with {description, channelId, userId, userName, jobId?, inlineCode?, model?}
Calls Ollama to generate CadQuery Python code, executes it, self-corrects on failure (up to 2 attempts),
renders PNG preview via OpenSCAD import trick, and returns the final result.
Returns {success, job_id, code, stl_b64?, png_b64?, code_path, error?, attempts}
Runs on port 8190.
"""

import base64
import json
import os
import subprocess
import sys
import tempfile
import traceback
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

OUTPUT_DIR = "/home/biulatech/ai-workers-1/output/3d"
VENV_PYTHON = "/home/biulatech/cadquery-venv/bin/python"
EXECUTE_HELPER = os.path.join(os.path.dirname(__file__), "execute_cq.py")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434/api/chat")
DEFAULT_MODEL = os.environ.get("CADQUERY_MODEL", "qwen2.5-coder:32b-instruct-q5_K_M")
MAX_ATTEMPTS = 2   # 2 attempts × (~270s Ollama + ~120s CadQuery) ≈ 780s < 900s n8n exec timeout

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ──────────────────────────────────────────────
# System prompt for CadQuery generation
# ──────────────────────────────────────────────
BASE_SYSTEM = """You are an expert CadQuery programmer who creates parametric 3D-printable models.

CadQuery is a Python library for building 3D CAD models using a fluent builder API on top of the OpenCASCADE kernel.

OUTPUT RULES — follow exactly:
1. Output ONLY valid Python/CadQuery code. No markdown fences, no explanations, no extra text.
2. First line must be: import cadquery as cq
3. Declare all dimensions as named Python variables at the top (in mm).
4. Add brief inline comments on key geometry steps.
5. The final model MUST be stored in a Python variable named `result`.
6. The model MUST be genuinely 3D — real volume in X, Y, and Z.
7. Do NOT call cq.exporters.export(), exporters.export(), .save(), or any file I/O — the runner handles export.
8. Do NOT use print() statements.

CADQUERY CHEATSHEET:
- Box:        result = cq.Workplane("XY").box(width, depth, height)
- Cylinder:   result = cq.Workplane("XY").cylinder(height, radius)
- Sphere:     result = cq.Workplane("XY").sphere(radius)
- Hole:       .faces(">Z").workplane().hole(diameter)
- Fillet:     .edges("|Z").fillet(radius)
- Chamfer:    .edges("|Z").chamfer(distance)
- Shell/hollow: .shell(-wall_thickness)
- Array of holes: .faces(">Z").workplane().rarray(x_spacing, y_spacing, nx, ny).hole(d)
- Boolean cut: base_shape.cut(cq.Workplane("XY").box(w, d, h).translate((x, y, z)))
- Boolean union: shape1.union(shape2)
- Extrude polygon: cq.Workplane("XY").polygon(n_sides, circumradius).extrude(height)
- Revolve profile: cq.Workplane("XZ").polyline([(r1,0),(r2,0),(r2,h),(r1,h)]).close().revolve(360)
- Loft between wires: use cq.Workplane.loft() on a shell with multiple wires
- Translate: shape.translate((x, y, z))
- Rotate: shape.rotate((0,0,0),(0,0,1), angle_degrees)
- Text emboss: .faces(">Z").workplane().text("ABC", fontsize=12, distance=2)

PRINTABILITY RULES:
- All models must be watertight/manifold (no open surfaces).
- Minimum wall thickness: 1.5 mm unless user specifies thinner.
- Avoid unsupported overhangs > 45° without support structures.
- Center the finished model at the origin when practical.
- $fn equivalent: use segments=64 in cylinder() and sphere() for smooth curves."""

IMPROVE_SUFFIX = """

IMPROVEMENT MODE:
- Study the existing code carefully.
- Apply ONLY the requested changes.
- Preserve variable names and overall structure where possible.
- Return the COMPLETE updated code, not just the changed sections."""

CORRECTION_SYSTEM = """You are an expert CadQuery programmer fixing a bug in 3D model code.

The following CadQuery Python code failed to execute. Your job is to fix it.

OUTPUT RULES:
1. Output ONLY the corrected Python code. No markdown, no explanations.
2. Fix ALL errors indicated in the error message.
3. Keep the same overall design intent.
4. The final model MUST be in a variable named `result`.
5. Do NOT call export() or any file I/O."""


# ──────────────────────────────────────────────
# Ollama helper
# ──────────────────────────────────────────────
def call_ollama(messages: list, model: str, temperature: float = 0.2) -> str:
    """Call Ollama /api/chat and return the assistant's content string."""
    payload = json.dumps({
        "model": model,
        "messages": messages,
        "stream": False,
        "options": {
            "temperature": temperature,
            "num_predict": 4096,
        },
    }).encode()

    req = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=270) as resp:
        data = json.loads(resp.read())

    return data.get("message", {}).get("content", data.get("response", "")).strip()


# ──────────────────────────────────────────────
# Code cleanup helpers
# ──────────────────────────────────────────────
def strip_fences(raw: str) -> str:
    """Remove markdown code fences if present."""
    raw = raw.strip()
    # Match ```python\n...\n``` or ```\n...\n```
    import re
    m = re.search(r'```(?:python|cadquery|py)?\n([\s\S]*?)```', raw, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    # Also strip single-line fence prefix/suffix
    if raw.startswith("```"):
        lines = raw.split("\n")
        raw = "\n".join(lines[1:])
        if raw.endswith("```"):
            raw = raw[:-3].strip()
    return raw


def ensure_import(code: str) -> str:
    """Ensure 'import cadquery as cq' is the first non-empty line."""
    if "import cadquery" not in code:
        code = "import cadquery as cq\n" + code
    return code


# ──────────────────────────────────────────────
# CadQuery execution
# ──────────────────────────────────────────────
def execute_cq(code: str, stl_path: str) -> tuple[bool, str]:
    """
    Execute CadQuery code in a subprocess.
    Returns (success: bool, error_message: str).
    """
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(code)
        code_path = f.name

    try:
        r = subprocess.run(
            [VENV_PYTHON, EXECUTE_HELPER, code_path, stl_path],
            capture_output=True,
            timeout=120,
        )
        if r.returncode == 0 and os.path.exists(stl_path) and os.path.getsize(stl_path) > 0:
            return True, ""
        else:
            err = (r.stderr.decode("utf-8", errors="replace") or r.stdout.decode("utf-8", errors="replace")).strip()
            return False, err or "Unknown execution error"
    except subprocess.TimeoutExpired:
        return False, "CadQuery execution timed out (120s)"
    except Exception as e:
        return False, f"Subprocess error: {e}"
    finally:
        os.unlink(code_path)


# ──────────────────────────────────────────────
# PNG rendering via OpenSCAD import
# ──────────────────────────────────────────────
def render_png(stl_path: str, png_path: str) -> bool:
    """
    Render a PNG preview of an STL file using OpenSCAD's import() + xvfb-run.
    Returns True on success.
    """
    scad_snippet = f'import("{stl_path}");'
    with tempfile.NamedTemporaryFile(mode='w', suffix='.scad', delete=False) as f:
        f.write(scad_snippet)
        scad_path = f.name

    try:
        r = subprocess.run(
            [
                "xvfb-run", "--auto-servernum",
                "openscad",
                "--render",
                "--autocenter",
                "--viewall",
                "--camera=0,0,0,55,0,25,0",
                "--imgsize=800,600",
                "--colorscheme=DeepOcean",
                "-o", png_path,
                scad_path,
            ],
            capture_output=True,
            timeout=120,
        )
        return r.returncode == 0 and os.path.exists(png_path) and os.path.getsize(png_path) > 0
    except subprocess.TimeoutExpired:
        return False
    except Exception:
        return False
    finally:
        os.unlink(scad_path)


# ──────────────────────────────────────────────
# Main generation pipeline
# ──────────────────────────────────────────────
def generate_3d(
    description: str,
    channel_id: str = "",
    user_id: str = "",
    user_name: str = "user",
    job_id: str = "",
    inline_code: str = "",
    model: str = DEFAULT_MODEL,
) -> dict:
    """
    Full generate-and-render pipeline with self-correction retry.
    Returns result dict suitable for JSON serialisation.
    """
    new_job_id = str(uuid.uuid4())[:8]
    job_dir = os.path.join(OUTPUT_DIR, new_job_id)
    os.makedirs(job_dir, exist_ok=True)

    stl_path = os.path.join(job_dir, "model.stl")
    png_path = os.path.join(job_dir, "preview.png")
    code_path = os.path.join(job_dir, "model.py")

    result = {
        "success": False,
        "job_id": new_job_id,
        "code": "",
        "code_path": code_path,
        "attempts": 0,
        "error": None,
    }

    # ── Build initial prompt ──────────────────
    system_prompt = BASE_SYSTEM

    if job_id:
        # Try to load existing CadQuery code
        existing_py = os.path.join(OUTPUT_DIR, job_id, "model.py")
        existing_code = ""
        if os.path.exists(existing_py):
            with open(existing_py, "r") as f:
                existing_code = f.read()
        if existing_code:
            system_prompt = BASE_SYSTEM + IMPROVE_SUFFIX
            user_message = (
                f"Improve this CadQuery model with: {description}\n\n"
                f"EXISTING CODE (job {job_id}):\n{existing_code}"
            )
        else:
            user_message = f"Generate CadQuery code for: {description}"
    elif inline_code:
        system_prompt = BASE_SYSTEM + IMPROVE_SUFFIX
        user_message = (
            f"Improve this CadQuery model with: {description}\n\n"
            f"EXISTING CODE:\n{inline_code}"
        )
    else:
        user_message = f"Generate CadQuery code for: {description}"

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_message},
    ]

    code = ""
    last_error = ""

    # ── Self-correction retry loop ────────────
    for attempt in range(1, MAX_ATTEMPTS + 1):
        result["attempts"] = attempt
        print(f"[cadquery-api] Attempt {attempt}/{MAX_ATTEMPTS} for job {new_job_id}")

        # 1. Call Ollama
        try:
            raw = call_ollama(messages, model)
        except Exception as e:
            result["error"] = f"Ollama call failed: {e}"
            return result

        # 2. Extract and clean code
        code = strip_fences(raw)
        code = ensure_import(code)
        result["code"] = code

        # 3. Execute
        success, error = execute_cq(code, stl_path)

        if success:
            print(f"[cadquery-api] Execution succeeded on attempt {attempt}")
            break
        else:
            last_error = error
            print(f"[cadquery-api] Execution failed (attempt {attempt}): {error[:200]}")

            if attempt < MAX_ATTEMPTS:
                # Add correction turn to conversation
                messages.append({"role": "assistant", "content": raw})
                messages.append({
                    "role": "user",
                    "content": (
                        f"The code failed with this error:\n\n{error}\n\n"
                        f"Fix the code so it runs correctly without changing the overall design. "
                        f"Output ONLY the corrected Python code."
                    ),
                })
    else:
        # All attempts exhausted
        result["error"] = f"All {MAX_ATTEMPTS} attempts failed. Last error:\n{last_error}"
        # Save the last attempted code anyway
        with open(code_path, "w") as f:
            f.write(code)
        return result

    # ── Save code file ────────────────────────
    with open(code_path, "w") as f:
        f.write(code)

    # ── Export STL (already done by execute_cq) ──
    if os.path.exists(stl_path):
        with open(stl_path, "rb") as f:
            result["stl_b64"] = base64.b64encode(f.read()).decode()
        result["stl_path"] = stl_path

    # ── Render PNG ────────────────────────────
    png_ok = render_png(stl_path, png_path)
    if png_ok:
        with open(png_path, "rb") as f:
            result["png_b64"] = base64.b64encode(f.read()).decode()
        result["png_path"] = png_path
    else:
        print(f"[cadquery-api] PNG render failed for job {new_job_id} (non-fatal)")

    result["success"] = True
    return result


# ──────────────────────────────────────────────
# HTTP server
# ──────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[cadquery-api] {fmt % args}")

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"status": "ok", "model": DEFAULT_MODEL})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/generate":
            self._handle_generate()
        else:
            self._json(404, {"error": f"Unknown path: {self.path}"})

    def _handle_generate(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
        except Exception as e:
            self._json(400, {"error": f"Bad JSON: {e}"})
            return

        description = (body.get("description") or "").strip()
        if not description:
            self._json(400, {"error": "description is required"})
            return

        channel_id = body.get("channelId", "")
        user_id    = body.get("userId", "")
        user_name  = body.get("userName", "user")
        # Sanitise jobId: only 8 lowercase hex chars
        raw_job_id = str(body.get("jobId") or "").lower()
        job_id     = "".join(c for c in raw_job_id if c in "0123456789abcdef")[:8]
        inline_code = (body.get("inlineCode") or "").strip()
        model       = body.get("model", DEFAULT_MODEL)

        try:
            res = generate_3d(
                description=description,
                channel_id=channel_id,
                user_id=user_id,
                user_name=user_name,
                job_id=job_id,
                inline_code=inline_code,
                model=model,
            )
            # Add back the routing info so n8n Format node can use it
            res["channelId"] = channel_id
            res["userId"]    = user_id
            res["userName"]  = user_name
            res["description"] = description
            self._json(200, res)
        except Exception as e:
            tb = traceback.format_exc()
            print(f"[cadquery-api] Unhandled error: {tb}", file=sys.stderr)
            self._json(500, {"error": str(e), "traceback": tb})

    def _json(self, status: int, data: dict):
        payload = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8190))
    print(f"[cadquery-api] Starting on port {port}")
    print(f"[cadquery-api] Ollama URL: {OLLAMA_URL}")
    print(f"[cadquery-api] Default model: {DEFAULT_MODEL}")
    print(f"[cadquery-api] venv python: {VENV_PYTHON}")
    print(f"[cadquery-api] Output dir: {OUTPUT_DIR}")
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
