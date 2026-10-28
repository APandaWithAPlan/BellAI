"""Copies your own BellAi clips into the openWakeWord training folders.

Put clips in the matching custom_clips folder (any of .wav .mp3 .m4a .flac .ogg, subfolders are fine):
  positive_train/  "BellAi" from recordings and GPT-SoVITS
  positive_test/   "BellAi" from 2-3 people who are NOT in positive_train (honest test)
  negative_train/  recorded near misses ("Bella", "belly", "bell", ...)
  negative_test/   a few near misses held out for testing

Each clip is converted to 16 kHz mono 16-bit wav (the only format openWakeWord trains on) and saved
with a "custom_" prefix. Clips that were already imported are skipped.
"""
import argparse
import subprocess
import wave
from pathlib import Path

FOLDERS = ["positive_train", "positive_test", "negative_train", "negative_test"]
AUDIO = {".wav", ".mp3", ".m4a", ".flac", ".ogg"}
MAX_SECONDS = 3.0

parser = argparse.ArgumentParser()
parser.add_argument("--clips", required=True, help="the custom_clips folder")
parser.add_argument("--dest", required=True, help="<output_dir>/<model_name> from bellai_model.yml")
args = parser.parse_args()

clips_root, dest_root = Path(args.clips), Path(args.dest)
for folder in FOLDERS:
    src = clips_root / folder
    files = sorted(p for p in src.rglob("*") if p.suffix.lower() in AUDIO) if src.exists() else []
    if not files:
        print(f"{folder}: no clips")
        continue
    out = dest_root / folder
    out.mkdir(parents=True, exist_ok=True)
    added = long = 0
    for f in files:
        name = "custom_" + "_".join(f.relative_to(src).with_suffix("").parts).replace(" ", "_") + ".wav"
        target = out / name
        if target.exists():
            continue
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(f),
                        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(target)], check=True)
        with wave.open(str(target)) as w:
            if w.getnframes() / w.getframerate() > MAX_SECONDS:
                long += 1
        added += 1
    print(f"{folder}: added {added} new clips ({len(files)} found)")
    if long:
        print(f"  note: {long} clips are longer than {MAX_SECONDS:.0f} s. Trim them so each holds one word "
              "with little silence, or the end of the clip is what gets used.")
