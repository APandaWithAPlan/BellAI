"""Cuts long recording takes into one-word clips and files them for training.

Put each person's takes in recordings/<person>/, one file per part of the script, named:
    close.wav           Session 1, Part A   (20 x BellAi)
    mid.wav             Session 2, Part A   (15 x BellAi)
    far.wav             Session 3           (15 x BellAi)
    nearmiss_close.wav  Session 1, Parts B + C
    nearmiss_mid.wav    Session 2, Parts B + C
    nearmiss_far.wav    Session 3, Parts B + C
    talk.wav            Session 4
A folder per take also works (recordings/<person>/close/anything.wav), and names with spaces such as
"Bella near miss close.wav" are understood. Any audio format works (.wav .m4a .mp3 .flac .ogg). People listed in test_speakers.txt (one name per
line, matching their folder name) go to the *_test folders so the model is tested on voices it never heard.

Clips are written to custom_clips/<folder>/<person>/ as 16 kHz mono wav. Takes that were already split are skipped,
so clips you delete stay deleted. Re-recording a take (a newer file) splits it again; --force re-splits all.
Usage (in WSL, from the training environment): python split_recordings.py
"""
import argparse
import subprocess
from pathlib import Path

import numpy as np
import scipy.io.wavfile
import scipy.signal

HERE = Path(__file__).resolve().parent
RATE = 16000
AUDIO = {".wav", ".mp3", ".m4a", ".flac", ".ogg"}
EXPECTED = {"close": 20, "mid": 15, "far": 15}  # BellAi lines per take in the script

parser = argparse.ArgumentParser()
parser.add_argument("--recordings", default=str(HERE / "recordings"))
parser.add_argument("--clips", default=str(HERE / "custom_clips"))
parser.add_argument("--force", action="store_true", help="re-split takes that were already split")
args = parser.parse_args()


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
    """Returns (start, end, too_long) sample ranges of words.

    With an expected count (BellAi takes), several sensitivities are tried and the one that finds that many
    words is used. Otherwise a setting that worked well on real takes is used.
    """
    db = loudness(audio)
    if len(db) < 100:
        return []
    if expected:
        best = None
        for frac in (0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7):
            for gap in (15, 20, 25, 35):
                segs = find_segments(db, frac, gap)
                if not segs:
                    continue
                longest = max(b - a for a, b in segs) / 100
                score = (longest > max_len, abs(len(segs) - expected), longest)  # separate words first, then the count
                if best is None or score < best[0]:
                    best = (score, segs)
        segs = best[1] if best else []
    else:
        segs = find_segments(db, 0.6, 20)
    hop, frame = 160, 480
    words = []
    for s, e in segs:
        a, b = s * hop, e * hop + frame
        a, b = max(0, a - int(0.2 * RATE)), min(len(audio), b + int(0.3 * RATE))  # keep a little air
        words.append((a, b, (b - a) / RATE > max_len + 0.5))
    return words


def take_kind(person_dir, f):
    """close / mid / far / nearmiss / talk, from the take's folder name or its file name."""
    label = f.parent.name if f.parent != person_dir else f.stem
    t = "".join(ch for ch in label.lower() if ch.isalnum())
    if "nearmiss" in t:
        return "nearmiss"
    for kind in ("talk", "close", "mid", "far"):
        if kind in t:
            return kind
    return None


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
    for take in sorted(f for f in person_dir.rglob("*") if f.is_file() and f.suffix.lower() in AUDIO):
        kind = take_kind(person_dir, take)
        if kind is None:
            print(f"{person}/{take.name}: skipped, put close/mid/far/near miss/talk in its folder or file name")
            continue
        stem = f"{person}_{take.stem}".replace(" ", "_")
        done = list(clip_root.rglob(f"{stem}_*.wav"))
        if done and not args.force and min(f.stat().st_mtime for f in done) >= take.stat().st_mtime:
            # Already split; skipping keeps any clips you deleted after listening
            print(f"{person}/{take.name}: already split ({len(done)} clips), skipping")
            continue
        audio = load(take)
        if kind == "talk":
            # Conversation: 2-second pieces, skipping silent ones
            chunk = 2 * RATE
            pieces = [audio[i:i + chunk] for i in range(0, len(audio) - chunk + 1, chunk)]
            pieces = [p for p in pieces if np.sqrt(np.mean(p.astype(np.float32) ** 2)) > 100]
            n = save(clip_root / f"negative_{split}" / person, stem, pieces)
            print(f"{person}/{take.name}: {n} talk clips -> negative_{split}")
        elif kind == "nearmiss":
            pieces = []
            for a, b, too_long in find_words(audio, 4.0):
                seg = audio[a:b]
                # sentences longer than 4 s are cut into 2 s pieces
                pieces += [seg[i:i + 2 * RATE] for i in range(0, len(seg), 2 * RATE)] if too_long else [seg]
            n = save(clip_root / f"negative_{split}" / person, stem, pieces)
            print(f"{person}/{take.name}: {n} near-miss clips -> negative_{split}")
        else:
            words = find_words(audio, 2.5, EXPECTED[kind])
            kept = [(a, b) for a, b, too_long in words if not too_long]
            skipped = len(words) - len(kept)
            n = save(clip_root / f"positive_{split}" / person, stem, [audio[a:b] for a, b in kept])
            extra = f", skipped {skipped} too long (words ran together?)" if skipped else ""
            print(f"{person}/{take.name}: {n} BellAi clips -> positive_{split}{extra}")
            if n != EXPECTED[kind]:
                print(f"  expected {EXPECTED[kind]}. Listen to {stem}_*.wav and delete any that aren't BellAi. Found at:")
                print("  " + "  ".join(f"{i:03d}={a / RATE:.1f}s" for i, (a, b) in enumerate(kept)))
