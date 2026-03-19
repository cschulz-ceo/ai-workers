#!/usr/bin/env bash
# Download SD1.5 checkpoint required for AnimateDiff video generation
# v1-5-pruned-emaonly.safetensors (~4.27 GB) from HuggingFace
set -euo pipefail

DEST="/home/biulatech/ComfyUI/models/checkpoints/v1-5-pruned-emaonly.safetensors"
URL="https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"

if [ -f "$DEST" ]; then
  echo "✅ SD1.5 checkpoint already exists at $DEST"
  ls -lh "$DEST"
  exit 0
fi

echo "📥 Downloading SD1.5 checkpoint (~4.27 GB)..."
echo "   From: $URL"
echo "   To:   $DEST"
echo ""

# Use wget with resume support
wget -c --show-progress -O "$DEST" "$URL"

echo ""
echo "✅ Download complete!"
ls -lh "$DEST"
echo ""
echo "⚠️  Restart ComfyUI to pick up the new model:"
echo "   docker restart comfyui"
