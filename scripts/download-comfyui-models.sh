#!/bin/bash
# ComfyUI Model Downloader — with resume support
# Run directly: bash ~/ai-workers-1/scripts/download-comfyui-models.sh
# For gated repos (FLUX.1-schnell): HF_TOKEN=<your_token> bash ~/ai-workers-1/scripts/download-comfyui-models.sh
# Logs: ~/ComfyUI/download_progress.log
set -euo pipefail

COMFY_DIR="/home/biulatech/ComfyUI"
LOG="$COMFY_DIR/download_progress.log"
VENV="$COMFY_DIR/venv/bin/python3"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "============================================================"
log "ComfyUI Model Downloader — $(date)"
log "============================================================"

# ── Helper: wget with resume ──────────────────────────────────────────────
download_wget() {
    local url="$1" dest="$2" label="$3"
    if [[ -f "$dest" ]] && [[ $(stat -c%s "$dest") -gt 1000000 ]]; then
        log "  SKIP $label (already exists: $(du -sh "$dest" | cut -f1))"
        return 0
    fi
    log "  DOWNLOAD $label"
    wget -q --show-progress --progress=bar:force --continue \
        -O "$dest" "$url" 2>&1 | tail -1 | tee -a "$LOG" || true
    if [[ -f "$dest" ]] && [[ $(stat -c%s "$dest") -gt 1000000 ]]; then
        log "  DONE $label ($(du -sh "$dest" | cut -f1))"
    else
        log "  WARN $label may be incomplete"
    fi
}

# ── Helper: huggingface hub download ────────────────────────────────────
download_hf() {
    local repo="$1" filename="$2" dest_dir="$3" label="$4"
    local dest_file="$dest_dir/$filename"
    if [[ -f "$dest_file" ]] && [[ $(stat -c%s "$dest_file") -gt 1000000 ]]; then
        log "  SKIP $label ($(du -sh "$dest_file" | cut -f1))"
        return 0
    fi
    log "  DOWNLOAD $label from $repo"
    $VENV -c "
from huggingface_hub import hf_hub_download
import os
token = os.environ.get('HF_TOKEN') or os.environ.get('HUGGING_FACE_HUB_TOKEN') or None
path = hf_hub_download(
    repo_id='$repo',
    filename='$filename',
    local_dir='$dest_dir',
    token=token,
)
print(f'  Saved to: {path}')
" 2>&1 | grep -v UserWarning | grep -v "warnings.warn" | tee -a "$LOG" || log "  ERROR on $label"
    if [[ -f "$dest_file" ]]; then
        log "  DONE $label ($(du -sh "$dest_file" | cut -f1))"
    fi
}

# ═══════════════════════════════════════════════════════════════════════
log ""
log "[1/6] FLUX.1-schnell FP8 (~8.1GB)"
download_hf "Comfy-Org/flux1-schnell" "flux1-schnell-fp8.safetensors" \
    "$COMFY_DIR/models/diffusion_models" "flux1-schnell-fp8.safetensors"

log ""
log "[2/6] T5-XXL text encoder FP8 (~4.9GB)"
download_hf "comfyanonymous/flux_text_encoders" "t5xxl_fp8_e4m3fn.safetensors" \
    "$COMFY_DIR/models/clip" "t5xxl_fp8_e4m3fn.safetensors"

log ""
log "[3/6] FLUX VAE ae.safetensors (~335MB)"
download_hf "black-forest-labs/FLUX.1-schnell" "ae.safetensors" \
    "$COMFY_DIR/models/vae" "ae.safetensors"

log ""
log "[4/6] SDXL Base 1.0 (~6.5GB)"
download_hf "stabilityai/stable-diffusion-xl-base-1.0" "sd_xl_base_1.0.safetensors" \
    "$COMFY_DIR/models/checkpoints" "sd_xl_base_1.0.safetensors"

log ""
log "[5/6] AnimateDiff v3 motion module (~1.7GB)"
ANIMATEDIFF_DIR="$COMFY_DIR/custom_nodes/ComfyUI-AnimateDiff-Evolved/models"
mkdir -p "$ANIMATEDIFF_DIR"
download_hf "guoyww/animatediff" "v3_sd15_mm.ckpt" \
    "$ANIMATEDIFF_DIR" "v3_sd15_mm.ckpt"

log ""
log "[6/6] Real-ESRGAN 4x Plus (~64MB)"
download_wget \
    "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth" \
    "$COMFY_DIR/models/upscale_models/RealESRGAN_x4plus.pth" \
    "RealESRGAN_x4plus.pth"

log ""
log "============================================================"
log "All downloads complete. Restart ComfyUI: sudo systemctl restart comfyui"
log "============================================================"
