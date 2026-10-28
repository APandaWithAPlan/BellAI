#!/usr/bin/env bash
# One-time setup for training the BellAi wake word. Run inside WSL (Ubuntu):
#   bash "/mnt/c/Users/<you>/Documents/GitHub/BellAI/Wake Word/setup.sh"
#
# The big training data (~30 GB) and the Python environment live in the WSL home folder
# (~/bellai-wakeword by default) because reading tens of thousands of clips from /mnt/c is very slow.
# Only the config, scripts, your own clips and the finished model stay in this folder.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BELLAI_WW_DIR:-$HOME/bellai-wakeword}"
MODELS="$WORK_DIR/openwakeword/openwakeword/resources/models"
OWW_RELEASE="https://github.com/dscripka/openWakeWord/releases/download/v0.5.1"

echo "Wake Word folder: $REPO_DIR"
echo "Work folder:      $WORK_DIR"

echo "== System packages"
sudo apt-get update
sudo apt-get install -y git wget curl ffmpeg build-essential

echo "== uv (Python 3.10 manager)"
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "== Python 3.10 environment"
[ -d .venv ] || uv venv --python 3.10 .venv
source .venv/bin/activate

echo "== Piper sample generator (synthetic clips)"
# v2.0.0 is the last version with the generate_samples.py layout openWakeWord imports
[ -d piper-sample-generator ] || git clone --branch v2.0.0 --depth 1 https://github.com/rhasspy/piper-sample-generator
mkdir -p piper-sample-generator/models
wget -c -O piper-sample-generator/models/en_US-libritts_r-medium.pt \
    "https://github.com/rhasspy/piper-sample-generator/releases/download/v2.0.0/en_US-libritts_r-medium.pt"

echo "== openWakeWord"
# v0.6.0 matches the training notebook (newer main needs extra Linux libraries)
[ -d openwakeword ] || git clone --branch v0.6.0 --depth 1 https://github.com/dscripka/openwakeword

echo "== Python packages"
uv pip install -r "$REPO_DIR/requirements.txt" -e ./openwakeword

echo "== openWakeWord feature models"
mkdir -p "$MODELS"
for f in embedding_model.onnx embedding_model.tflite melspectrogram.onnx melspectrogram.tflite; do
    [ -s "$MODELS/$f" ] || wget -O "$MODELS/$f" "$OWW_RELEASE/$f"
done

echo "== GPU check"
python - <<'PY'
import torch
if torch.cuda.is_available():
    print("GPU found:", torch.cuda.get_device_name(0))
else:
    print("WARNING: no GPU found. Check that `nvidia-smi` works in WSL. Training will be very slow on CPU.")
PY

echo
echo "Setup done. Next: bash \"$REPO_DIR/download_data.sh\""
