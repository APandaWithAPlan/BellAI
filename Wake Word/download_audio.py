"""Downloads room impulse responses (MIT) and background audio (AudioSet + FMA) as 16 kHz wav files.

Based on the download cells of the openWakeWord automatic training notebook. Background clips go into
./background_clips, which is the folder bellai_model.yml points to. Run from the work folder.
"""
import argparse
import os
import subprocess
from pathlib import Path

import datasets
import numpy as np
import scipy.io.wavfile
from tqdm import tqdm

parser = argparse.ArgumentParser()
parser.add_argument("--fma-hours", type=float, default=1, help="hours of FMA music to download (30 s clips)")
args = parser.parse_args()


def save_wav(path, audio):
    audio = np.clip(np.asarray(audio, dtype=np.float32), -1.0, 1.0)
    scipy.io.wavfile.write(path, 16000, (audio * 32767).astype(np.int16))


def has_files(folder, minimum):
    return folder.exists() and len(list(folder.glob("*.wav"))) >= minimum


# Room impulse responses
rir_dir = Path("mit_rirs")
if has_files(rir_dir, 200):
    print("mit_rirs already downloaded")
else:
    rir_dir.mkdir(exist_ok=True)
    rirs = datasets.load_dataset("davidscripka/MIT_environmental_impulse_responses", split="train", streaming=True)
    for row in tqdm(rirs, desc="MIT RIRs"):
        name = row["audio"]["path"].split("/")[-1]
        save_wav(rir_dir / name, row["audio"]["array"])

bg_dir = Path("background_clips")
bg_dir.mkdir(exist_ok=True)

# AudioSet (one part of the balanced train set)
if has_files(bg_dir, 1) and any(bg_dir.glob("audioset_*.wav")):
    print("AudioSet clips already converted")
else:
    tar_name = "bal_train09.tar"
    os.makedirs("audioset", exist_ok=True)
    url = "https://huggingface.co/datasets/agkphysics/AudioSet/resolve/main/data/" + tar_name
    subprocess.run(["wget", "-c", "-O", f"audioset/{tar_name}", url], check=True)
    subprocess.run(["tar", "-xf", tar_name], cwd="audioset", check=True)
    files = [str(p) for p in Path("audioset/audio").glob("**/*.flac")]
    ds = datasets.Dataset.from_dict({"audio": files}).cast_column("audio", datasets.Audio(sampling_rate=16000))
    for row in tqdm(ds, desc="AudioSet -> 16 kHz"):
        name = "audioset_" + row["audio"]["path"].split("/")[-1].replace(".flac", ".wav")
        save_wav(bg_dir / name, row["audio"]["array"])

# Free Music Archive (all clips are 30 s)
wanted = int(args.fma_hours * 3600 // 30)
have = len(list(bg_dir.glob("fma_*.wav")))
if have >= wanted:
    print("FMA clips already downloaded")
else:
    fma = datasets.load_dataset("rudraml/fma", name="small", split="train", streaming=True)
    fma = iter(fma.cast_column("audio", datasets.Audio(sampling_rate=16000)))
    for _ in tqdm(range(wanted), desc="FMA music"):
        try:
            row = next(fma)
        except StopIteration:
            break
        name = "fma_" + row["audio"]["path"].split("/")[-1].replace(".mp3", ".wav")
        save_wav(bg_dir / name, row["audio"]["array"])

print("Background clips:", len(list(bg_dir.glob("*.wav"))))
