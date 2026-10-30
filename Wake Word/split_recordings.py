"""Cuts long recording takes into one-word clips and files them for training.

Put each person's takes in recordings/<person>/, one file per part of the script, named:
    close.wav           Session 1, Part A   (20 x BellAi)
    mid.wav             Session 2, Part A   (15 x BellAi)
    far.wav             Session 3           (15 x BellAi)
    nearmiss_close.wav  Session 1, Parts B + C
    nearmiss_mid.wav    Session 2, Part B
    talk.wav            Session 4
Any audio format works (.wav .m4a .mp3 .flac .ogg). People listed in test_speakers.txt (one name per
line, matching their folder name) go to the *_test folders so the model is tested on voices it never heard.

Clips are written to custom_clips/<folder>/<person>/ as 16 kHz mono wav. Re-running replaces the clips
made from a take, so you can re-record one take without touching the rest.
Usage (in WSL, from the training environment): python split_recordings.py
"""
import argparse
import subprocess
from pathlib import Path

import numpy as np
import scipy.io.wavfile

HERE = Path(__file__).resolve().parent
RATE = 16000
AUDIO = {".wav", ".mp3", ".m4a", ".flac", ".ogg"}
EXPECTED = {"close": 20, "mid": 15, "far": 15}  # BellAi lines per take in the script

parser = argparse.ArgumentParser()
parser.add_argument("--recordings", default=str(HERE / "recordings"))
parser.add_argument("--clips", default=str(HERE / "custom_clips"))
args = parser.parse_args()


def load(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-ar", str(RATE), "-ac", "1",
                          "-f", "s16le", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.int16)


def find_words(audio, max_len):
    """Returns (start, end) sample ranges of speech separated by pauses."""
    frame, hop = 480, 160  # 30 ms frames every 10 ms
    if len(audio) < frame:
        return []
    x = audio.astype(np.float32)
    n = 1 + (len(x) - frame) // hop
    rms = np.array([np.sqrt(np.mean(x[i * hop:i * hop + frame] ** 2)) + 1e-3 for i in range(n)])
    db = 20 * np.log10(rms)
    floor, loud = np.percentile(db, 10), np.percentile(db, 98)
    voiced = db > floor + max(6.0, 0.3 * (loud - floor))  # adapts to quiet and far takes

    segments, start, gap = [], None, 0
    for i, v in enumerate(voiced):
        if v:
            start = i if start is None else start
            gap = 0
        elif start is not None:
            gap += 1
            if gap > 35:  # 350 ms of quiet ends a word (gaps inside "bell-ay-eye" are shorter)
                segments.append((start, i - gap))
                start, gap = None, 0
    if start is not None:
        segments.append((start, n - 1))

    words = []
    for s, e in segments:
        a, b = s * hop, e * hop + frame
        if b - a < 0.2 * RATE:  # clicks and bumps
            continue
        a, b = max(0, a - int(0.2 * RATE)), min(len(audio), b + int(0.3 * RATE))  # keep a little air
        if b - a > max_len * RATE:
            words.append((a, b, True))
        else:
            words.append((a, b, False))
    return words


def save(folder, stem, pieces):
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob(f"{stem}_*.wav"):
        old.unlink()
    for i, piece in enumerate(pieces):
        scipy.io.wavfile.write(folder / f"{stem}_{i:03d}.wav", RATE, piece)
    return len(pieces)


rec_root, clip_root = Path(args.recordings), Path(args.clips)
test_file = HERE / "test_speakers.txt"
test_people = {l.strip().lower() for l in test_file.read_text().splitlines() if l.strip()} if test_file.exists() else set()
people = sorted(p for p in rec_root.iterdir() if p.is_dir()) if rec_root.exists() else []
if not people:
    raise SystemExit(f"No recordings yet. Put takes in {rec_root}/<person>/ (see the top of this script).")
if not test_people:
    print("note: test_speakers.txt is missing or empty, so every speaker goes to training.")

for person_dir in people:
    person = person_dir.name
    split = "test" if person.lower() in test_people else "train"
    for take in sorted(f for f in person_dir.iterdir() if f.suffix.lower() in AUDIO):
        kind = take.stem.lower()
        audio = load(take)
        stem = f"{person}_{take.stem}".replace(" ", "_")
        if kind.startswith("talk"):
            # Conversation: 2-second pieces, skipping silent ones
            chunk = 2 * RATE
            pieces = [audio[i:i + chunk] for i in range(0, len(audio) - chunk + 1, chunk)]
            pieces = [p for p in pieces if np.sqrt(np.mean(p.astype(np.float32) ** 2)) > 100]
            n = save(clip_root / f"negative_{split}" / person, stem, pieces)
            print(f"{person}/{take.name}: {n} talk clips -> negative_{split}")
        elif kind.startswith("nearmiss"):
            pieces = []
            for a, b, too_long in find_words(audio, 4.0):
                seg = audio[a:b]
                # sentences longer than 4 s are cut into 2 s pieces
                pieces += [seg[i:i + 2 * RATE] for i in range(0, len(seg), 2 * RATE)] if too_long else [seg]
            n = save(clip_root / f"negative_{split}" / person, stem, pieces)
            print(f"{person}/{take.name}: {n} near-miss clips -> negative_{split}")
        elif kind in EXPECTED:
            words = find_words(audio, 3.0)
            pieces = [audio[a:b] for a, b, too_long in words if not too_long]
            skipped = sum(1 for w in words if w[2])
            n = save(clip_root / f"positive_{split}" / person, stem, pieces)
            flag = "" if n == EXPECTED[kind] else f"  <-- expected {EXPECTED[kind]}, listen to these"
            extra = f", skipped {skipped} too long (words ran together?)" if skipped else ""
            print(f"{person}/{take.name}: {n} BellAi clips -> positive_{split}{extra}{flag}")
        else:
            print(f"{person}/{take.name}: skipped, name it close/mid/far/nearmiss_close/nearmiss_mid/talk")
