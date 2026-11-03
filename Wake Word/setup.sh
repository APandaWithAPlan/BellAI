#!/usr/bin/env bash
# One-time setup for BellAi wake word training. Run in WSL (Ubuntu): bash setup.sh
# Installs everything and downloads ~30 GB of training data to ~/bellai-wakeword. Safe to re-run: finished parts are skipped.
set -euo pipefail
WORK_DIR="${BELLAI_WW_DIR:-$HOME/bellai-wakeword}"
MODELS="$WORK_DIR/openwakeword/openwakeword/resources/models"

echo "== System packages"
sudo apt-get update
sudo apt-get install -y git wget curl ffmpeg build-essential
command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
[ -d .venv ] || uv venv --python 3.10 .venv
source .venv/bin/activate

echo "== Piper and openWakeWord"
# Piper v2.0.0 and openWakeWord v0.6.0 are the versions that work together
[ -d piper-sample-generator ] || git clone --branch v2.0.0 --depth 1 https://github.com/rhasspy/piper-sample-generator
mkdir -p piper-sample-generator/models
wget -c -O piper-sample-generator/models/en_US-libritts_r-medium.pt \
    "https://github.com/rhasspy/piper-sample-generator/releases/download/v2.0.0/en_US-libritts_r-medium.pt"
[ -d openwakeword ] || git clone --branch v0.6.0 --depth 1 https://github.com/dscripka/openwakeword

echo "== Python packages"
# Versions from the openWakeWord training notebook; TensorFlow 2.8 needs Python 3.10, numpy 1.23 and protobuf 3.20
uv pip install -e ./openwakeword \
    torch==2.1.2 torchaudio==2.1.2 numpy==1.23.5 scipy==1.10.1 piper-phonemize==1.1.0 webrtcvad-wheels \
    mutagen==1.47.0 torchinfo==1.8.0 torchmetrics==1.2.0 speechbrain==0.5.14 audiomentations==0.33.0 \
    torch-audiomentations==0.11.0 acoustics==0.2.6 tensorflow-cpu==2.8.1 tensorflow_probability==0.16.0 \
    tensorflow-addons==0.17.1 onnx_tf==1.10.0 onnx==1.14.0 onnxruntime==1.16.3 protobuf==3.20.3 \
    pronouncing==0.2.0 datasets==2.14.6 huggingface_hub==0.20.3 pyarrow==14.0.2 fsspec==2023.9.2 \
    deep-phonemizer==0.0.19 soundfile librosa==0.10.1 setuptools==69.5.1 pyyaml tqdm requests

mkdir -p "$MODELS"
for f in embedding_model.onnx embedding_model.tflite melspectrogram.onnx melspectrogram.tflite; do
    [ -s "$MODELS/$f" ] || wget -O "$MODELS/$f" "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/$f"
done

echo "== Training data"
HF="https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main"
wget -c "$HF/openwakeword_features_ACAV100M_2000_hrs_16bit.npy"   # ~17 GB of general audio (negatives)
wget -c "$HF/validation_set_features.npy"                         # ~11 hours for false-positive checks

# Room echo (MIT) and background noise (AudioSet + 1 hour of FMA music) as 16 kHz wav
python - <<'PY'
import os, subprocess
from pathlib import Path
import datasets, numpy as np, scipy.io.wavfile
from tqdm import tqdm

def save(path, audio):
    audio = np.clip(np.asarray(audio, dtype=np.float32), -1.0, 1.0)
    scipy.io.wavfile.write(path, 16000, (audio * 32767).astype(np.int16))

rirs = Path("mit_rirs")
if len(list(rirs.glob("*.wav"))) < 200:
    rirs.mkdir(exist_ok=True)
    for row in tqdm(datasets.load_dataset("davidscripka/MIT_environmental_impulse_responses", split="train", streaming=True), desc="Room echo"):
        save(rirs / row["audio"]["path"].split("/")[-1], row["audio"]["array"])

bg = Path("background_clips")
bg.mkdir(exist_ok=True)
if not any(bg.glob("audioset_*.wav")):
    os.makedirs("audioset", exist_ok=True)
    subprocess.run(["wget", "-c", "-O", "audioset/bal_train09.tar",
                    "https://huggingface.co/datasets/agkphysics/AudioSet/resolve/main/data/bal_train09.tar"], check=True)
    subprocess.run(["tar", "-xf", "bal_train09.tar"], cwd="audioset", check=True)
    files = [str(p) for p in Path("audioset/audio").glob("**/*.flac")]
    ds = datasets.Dataset.from_dict({"audio": files}).cast_column("audio", datasets.Audio(sampling_rate=16000))
    for row in tqdm(ds, desc="AudioSet"):
        save(bg / ("audioset_" + row["audio"]["path"].split("/")[-1].replace(".flac", ".wav")), row["audio"]["array"])

if len(list(bg.glob("fma_*.wav"))) < 120:
    fma = iter(datasets.load_dataset("rudraml/fma", name="small", split="train", streaming=True)
               .cast_column("audio", datasets.Audio(sampling_rate=16000)))
    for _ in tqdm(range(120), desc="FMA music"):
        row = next(fma)
        save(bg / ("fma_" + row["audio"]["path"].split("/")[-1].replace(".mp3", ".wav")), row["audio"]["array"])
PY

python -c "import torch; print('GPU found:', torch.cuda.get_device_name(0)) if torch.cuda.is_available() else print('WARNING: no GPU found. Check that nvidia-smi works in WSL.')"
echo "Setup done. Next: source $WORK_DIR/.venv/bin/activate && python train.py"
