#!/usr/bin/env bash
# Downloads the training data into the work folder (~30 GB). Safe to re-run: finished parts are skipped
# and the big .npy files resume where they stopped.
#   bash download_data.sh            # 1 hour of FMA music (same as the notebook)
#   FMA_HOURS=3 bash download_data.sh
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BELLAI_WW_DIR:-$HOME/bellai-wakeword}"
cd "$WORK_DIR"
source .venv/bin/activate

HF="https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main"

echo "== Negative features (~17 GB, ~2,000 hours of audio)"
wget -c "$HF/openwakeword_features_ACAV100M_2000_hrs_16bit.npy"

echo "== False-positive validation features (~11 hours)"
wget -c "$HF/validation_set_features.npy"

echo "== Room impulse responses and background audio"
python "$REPO_DIR/download_audio.py" --fma-hours "${FMA_HOURS:-1}"

echo
echo "Data done. Next: bash \"$REPO_DIR/train.sh\""
