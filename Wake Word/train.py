"""Prepares the BellAi wake word dataset and trains the model. Run in WSL after setup.sh:

    source ~/bellai-wakeword/.venv/bin/activate
    python train.py              # every step, in order
    python train.py prepare      # one step: generate, prepare, augment, train or export

Steps
    generate  Piper makes synthetic "BellAi" and near-miss clips (in ~/bellai-wakeword).
    prepare   Cuts the takes in recordings/ into one-word clips in custom_clips/, then copies every clip in
              custom_clips/ into the training folders. Takes already cut are skipped, so clips you delete stay
              deleted (--force cuts them all again).
    augment   Adds room echo and background noise and computes features.
    train     Trains the model.
    export    Copies BellAi.onnx and the two feature models it needs into models/.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import scipy.io.wavfile
import scipy.signal
import yaml

HERE = Path(__file__).resolve().parent
WORK = Path(os.environ.get("BELLAI_WW_DIR", Path.home() / "bellai-wakeword"))
OWW_TRAIN = WORK / "openwakeword" / "openwakeword" / "train.py"
RATE = 16000
AUDIO = {".wav", ".mp3", ".m4a", ".flac", ".ogg"}
FOLDERS = ["positive_train", "positive_test", "negative_train", "negative_test"]
EXPECTED = {"close": 20, "mid": 15, "far": 15}  # BellAi lines per take in the recording script

parser = argparse.ArgumentParser(description="BellAi wake word training")
parser.add_argument("step", nargs="?", default="all", choices=["all", "generate", "prepare", "augment", "train", "export"])
parser.add_argument("--force", action="store_true", help="prepare: cut every take again, even ones already cut")
args = parser.parse_args()

config_path = WORK / "bellai_model.yml"
config = yaml.safe_load((HERE / "bellai_model.yml").read_text())
if not OWW_TRAIN.exists():
    sys.exit(f"Nothing set up in {WORK} yet. Run: bash setup.sh")
os.chdir(WORK)  # paths in bellai_model.yml are relative to the work folder
OUT = Path(config["output_dir"]).resolve()
MODEL = config["model_name"]


def oww(*flags):
    """Runs one openWakeWord training step with the repo's config."""
    config_path.write_text((HERE / "bellai_model.yml").read_text())
    return subprocess.run([sys.executable, str(OWW_TRAIN), "--training_config", str(config_path), *flags]).returncode


# ---------- prepare: cut recordings into clips

def load(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-ar", str(RATE), "-ac", "1",
                          "-f", "s16le", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.int16)


VOICE_BAND = scipy.signal.butter(4, [250, 3800], btype="bandpass", fs=RATE, output="sos")


def loudness(audio):
    """dB per 10 ms frame, measured only in the voice range so fans, hum and rumble don't count."""
    x = scipy.signal.sosfilt(VOICE_BAND, audio.astype(np.float32))
    frame, hop = 480, 160
    n = max(0, 1 + (len(x) - frame) // hop)
    rms = np.array([np.sqrt(np.mean(x[i * hop:i * hop + frame] ** 2)) + 1e-3 for i in range(n)])
    return 20 * np.log10(rms)


def find_segments(db, frac, gap_frames):
    """Frame ranges louder than the threshold, split at quiet gaps longer than gap_frames."""
    floor, loud = np.percentile(db, 10), np.percentile(db, 98)
    voiced = db > floor + frac * (loud - floor)
    voiced[:30] = False   # skip the first and last 0.3 s: record-button clicks
    voiced[-30:] = False
    out, start, gap = [], None, 0
    for i, v in enumerate(voiced):
        if v:
            start = i if start is None else start
            gap = 0
        elif start is not None:
            gap += 1
            if gap > gap_frames:
                out.append((start, i - gap))
                start, gap = None, 0
    if start is not None:
        out.append((start, len(voiced) - 1))
    return [(a, b) for a, b in out if b - a >= 35]  # shorter than 0.35 s = a click or bump, not a word


def find_words(audio, max_len, expected=None):
    """(start, end, too_long) sample ranges of words. With an expected count, the sensitivity that finds
    that many separate words is used."""
    db = loudness(audio)
    if len(db) < 100:
        return []
    if expected:
        best = None
        for frac in (0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7):
            for gap in (15, 20, 25, 35):
                segs = find_segments(db, frac, gap)
                if segs:
                    longest = max(b - a for a, b in segs) / 100
                    score = (longest > max_len, abs(len(segs) - expected), longest)  # separate words first
                    if best is None or score < best[0]:
                        best = (score, segs)
        segs = best[1] if best else []
    else:
        segs = find_segments(db, 0.6, 20)
    words = []
    for s, e in segs:
        a, b = max(0, s * 160 - int(0.2 * RATE)), min(len(audio), e * 160 + 480 + int(0.3 * RATE))
        words.append((a, b, (b - a) / RATE > max_len + 0.5))
    return words


def take_kind(person_dir, f):
    """close / mid / far / nearmiss / talk, from the take's folder name or its file name."""
    label = f.parent.name if f.parent != person_dir else f.stem
    t = "".join(ch for ch in label.lower() if ch.isalnum())
    if "nearmiss" in t:
        return "nearmiss"
    return next((k for k in ("talk", "close", "mid", "far") if k in t), None)


def take_label(person_dir, f, kind):
    """The take's name in clip file names: close, mid, far, talk, or nearmiss_close / _mid / _far."""
    if kind != "nearmiss":
        return kind
    label = f.parent.name if f.parent != person_dir else f.stem
    t = "".join(ch for ch in label.lower() if ch.isalnum())
    return next((f"nearmiss_{d}" for d in ("close", "mid", "far") if d in t), "nearmiss")


def save(folder, stem, pieces):
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob(f"{stem}_*.wav"):
        old.unlink()
    for i, piece in enumerate(pieces):
        scipy.io.wavfile.write(folder / f"{stem}_{i:03d}.wav", RATE, piece)
    return len(pieces)


def cut_recordings():
    rec_root, clip_root = HERE / "recordings", HERE / "custom_clips"
    test_file = HERE / "test_speakers.txt"
    test_people = {l.strip().lower() for l in test_file.read_text().splitlines() if l.strip()} \
        if test_file.exists() else set()
    people = sorted(p for p in rec_root.iterdir() if p.is_dir()) if rec_root.exists() else []
    if not people:
        print("No recordings yet")
        return
    for person_dir in people:
        person = person_dir.name
        split = "test" if person.lower() in test_people else "train"
        used = {}
        for take in sorted(f for f in person_dir.rglob("*") if f.is_file() and f.suffix.lower() in AUDIO):
            kind = take_kind(person_dir, take)
            if kind is None:
                print(f"{person}/{take.name}: skipped, put close/mid/far/near miss/talk in its folder or file name")
                continue
            label = take_label(person_dir, take, kind)
            used[label] = used.get(label, 0) + 1
            if used[label] > 1:  # a second take of the same part
                label += f"_{used[label]}"
            stem = f"{person}_{label}".replace(" ", "_")  # e.g. Bella_far -> Bella_far_000.wav
            done = list(clip_root.rglob(f"{stem}_*.wav"))
            if done and not args.force and min(f.stat().st_mtime for f in done) >= take.stat().st_mtime:
                print(f"{person}/{take.name}: already cut ({len(done)} clips)")
                continue
            audio = load(take)
            if kind == "talk":  # conversation: 2-second pieces, skipping silent ones
                pieces = [audio[i:i + 2 * RATE] for i in range(0, len(audio) - 2 * RATE + 1, 2 * RATE)]
                pieces = [p for p in pieces if np.sqrt(np.mean(p.astype(np.float32) ** 2)) > 100]
                n = save(clip_root / f"negative_{split}" / person, stem, pieces)
                print(f"{person}/{take.name}: {n} talk clips -> negative_{split}")
            elif kind == "nearmiss":  # sentences over 4 s are cut into 2 s pieces
                pieces = []
                for a, b, too_long in find_words(audio, 4.0):
                    seg = audio[a:b]
                    pieces += [seg[i:i + 2 * RATE] for i in range(0, len(seg), 2 * RATE)] if too_long else [seg]
                n = save(clip_root / f"negative_{split}" / person, stem, pieces)
                print(f"{person}/{take.name}: {n} near-miss clips -> negative_{split}")
            else:
                kept = [(a, b) for a, b, too_long in find_words(audio, 2.5, EXPECTED[kind]) if not too_long]
                n = save(clip_root / f"positive_{split}" / person, stem, [audio[a:b] for a, b in kept])
                print(f"{person}/{take.name}: {n} BellAi clips -> positive_{split}")
                if n != EXPECTED[kind]:
                    print(f"  expected {EXPECTED[kind]}. Listen to {stem}_*.wav and delete any that aren't BellAi:")
                    print("  " + "  ".join(f"{i:03d}={a / RATE:.1f}s" for i, (a, b) in enumerate(kept)))


def copy_clips():
    """Converts every clip in custom_clips/ to 16 kHz mono and copies it into the training folders."""
    for folder in FOLDERS:
        src = HERE / "custom_clips" / folder
        files = sorted(p for p in src.rglob("*") if p.suffix.lower() in AUDIO) if src.exists() else []
        out = OUT / MODEL / folder
        out.mkdir(parents=True, exist_ok=True)
        wanted = {"custom_" + f.stem.replace(" ", "_") + ".wav" for f in files}
        removed = 0
        for old in out.glob("custom_*.wav"):  # clips that were deleted or renamed in custom_clips
            if old.name not in wanted:
                old.unlink()
                removed += 1
        added = 0
        for f in files:
            target = out / ("custom_" + f.stem.replace(" ", "_") + ".wav")
            if target.exists() and target.stat().st_mtime >= f.stat().st_mtime:
                continue  # already copied and unchanged
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(f), "-ar", str(RATE), "-ac", "1",
                            "-c:a", "pcm_s16le", str(target)], check=True)
            added += 1
        print(f"{folder}: {len(files)} clips ({added} new, {removed} removed)")


# ---------- steps

def generate():
    if oww("--generate_clips"):
        sys.exit("Generation stopped. Run `python train.py generate` again to continue where it left off.")


def prepare():
    cut_recordings()
    copy_clips()


def augment():
    if oww("--augment_clips", "--overwrite"):
        sys.exit("Augment failed.")


def train():
    code = oww("--train_model")
    if not (OUT / f"{MODEL}.onnx").exists():
        sys.exit("Training failed before the model was saved.")
    if code:  # openWakeWord's last step converts to .tflite, which the Pi doesn't use
        print("The .onnx model was saved (the .tflite conversion at the end failed; it isn't needed).")


def export():
    if not (OUT / f"{MODEL}.onnx").exists():
        sys.exit("No trained model yet. Run: python train.py train")
    models = HERE / "models"
    models.mkdir(exist_ok=True)
    resources = WORK / "openwakeword" / "openwakeword" / "resources" / "models"
    for f in (OUT / f"{MODEL}.onnx", resources / "melspectrogram.onnx", resources / "embedding_model.onnx"):
        (models / f.name).write_bytes(f.read_bytes())
    print(f"Model saved to {models}")


STEPS = {"generate": generate, "prepare": prepare, "augment": augment, "train": train, "export": export}
for name, step in STEPS.items():
    if args.step in ("all", name):
        print(f"== {name}")
        step()
