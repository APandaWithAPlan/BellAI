"""
prepare_dataset.py - turn long voice recordings into a training dataset for Orpheus.

What it does
  1. Reads every audio file in voice_data/raw  (wav, flac, mp3, ogg)
  2. Transcribes each one with Whisper, with a timestamp for every word
  3. Cuts the recording into roughly 4-14 second clips at natural pauses
  4. Saves the clips as 24 kHz mono WAV files in voice_data/clips
  5. Writes voice_data/clips/metadata.csv with two columns: file_name,text

Setup (once)
    pip install faster-whisper soundfile

Run (from the folder that contains voice_data)
    python prepare_dataset.py

Useful options
    python prepare_dataset.py --overwrite     rebuild clips (erases transcript edits!)
    python prepare_dataset.py --cpu           skip the GPU if it crashes on startup
    python prepare_dataset.py --model medium  smaller/faster Whisper model

After it finishes, open metadata.csv and fix any transcription mistakes.
The text must match what you actually said, word for word.
"""

import argparse
import csv
import re
import sys
from pathlib import Path

import numpy as np

SAMPLE_RATE = 24000          # Orpheus (SNAC codec) expects 24 kHz audio
WHISPER_RATE = 16000         # Whisper expects 16 kHz audio
AUDIO_TYPES = {".wav", ".flac", ".mp3", ".ogg"}

MIN_LEN = 4.0                # try not to end a clip before this many seconds
TARGET_LEN = 10.0            # past this, cut at the next comma or small pause
MAX_LEN = 14.0               # never let a clip run longer than this
SHORTEST_KEPT = 1.5          # clips shorter than this are thrown away
LONG_PAUSE = 1.5             # a silence this long always ends the clip
PAD = 0.15                   # seconds of breathing room kept around each clip


def chunk_words(words, min_len=MIN_LEN, target_len=TARGET_LEN, max_len=MAX_LEN):
    """Group (start, end, text) words into clips that end at natural pauses."""
    chunks, current = [], []
    for i, (start, end, text) in enumerate(words):
        current.append((start, end, text))
        nxt = words[i + 1] if i + 1 < len(words) else None
        duration = end - current[0][0]
        gap = (nxt[0] - end) if nxt else float("inf")
        word = text.strip()
        sentence_end = word.endswith((".", "?", "!"))
        soft_break = word.endswith((",", ";", ":")) or gap >= 0.25

        cut = (
            nxt is None
            or gap >= LONG_PAUSE
            or (duration >= min_len and (sentence_end or gap >= 0.5))
            or (duration >= target_len and soft_break)
            or (nxt[1] - current[0][0] > max_len)
        )
        if cut:
            chunks.append(current)
            current = []
    return chunks


def clip_bounds(chunk, prev_end, next_start, total):
    """Pad a clip slightly without bleeding into the neighbouring words."""
    first, last = chunk[0][0], chunk[-1][1]
    lo = 0.0 if prev_end is None else (prev_end + first) / 2
    hi = total if next_start is None else (last + next_start) / 2
    return max(first - PAD, lo, 0.0), min(last + PAD, hi, total)


def resample(audio, rate_in, rate_out):
    """Change the sample rate, using whichever resampling library is installed."""
    if rate_in == rate_out:
        return audio
    try:
        import torch
        import torchaudio.functional as AF
        return AF.resample(torch.from_numpy(audio), rate_in, rate_out).numpy()
    except Exception:
        pass
    try:
        from math import gcd
        from scipy.signal import resample_poly
        g = gcd(rate_in, rate_out)
        return resample_poly(audio, rate_out // g, rate_in // g).astype(np.float32)
    except Exception:
        pass
    # Last resort: smooth, then pick samples. Fine for speech going to a lower rate.
    if rate_out < rate_in:
        width = max(1, round(rate_in / rate_out))
        audio = np.convolve(audio, np.ones(width, dtype=np.float32) / width, mode="same")
    positions = np.arange(int(len(audio) * rate_out / rate_in)) * (rate_in / rate_out)
    return np.interp(positions, np.arange(len(audio)), audio).astype(np.float32)


def load_audio(path, rate):
    """Read a recording as mono float32 at the given sample rate."""
    import soundfile as sf

    try:
        audio, rate_in = sf.read(str(path), dtype="float32", always_2d=True)
    except Exception as err:
        sys.exit(
            f"Couldn't read '{path.name}' ({err}).\n"
            "Export it from Audacity as a WAV file (File > Export Audio > WAV) and try again."
        )
    return np.ascontiguousarray(resample(audio.mean(axis=1), rate_in, rate), dtype=np.float32)


def load_model(name, force_cpu):
    if not force_cpu:
        try:
            import torch  # noqa: F401  (loads PyTorch's CUDA files so Whisper can use them)
            has_gpu = torch.cuda.is_available()
        except Exception:
            has_gpu = False
    else:
        has_gpu = False

    from faster_whisper import WhisperModel

    if has_gpu:
        try:
            model = WhisperModel(name, device="cuda", compute_type="float16")
            # Tiny test run so a broken GPU setup fails here, not halfway through.
            segments, _ = model.transcribe(np.zeros(WHISPER_RATE, dtype=np.float32), language="en")
            list(segments)
            print(f"Whisper '{name}' loaded on the GPU.")
            return model
        except Exception as err:
            print(f"GPU Whisper failed ({err}).\nFalling back to CPU - this will be slower.")
    model = WhisperModel(name, device="cpu", compute_type="int8")
    print(f"Whisper '{name}' loaded on the CPU.")
    return model


def transcribe_words(model, path, language):
    audio16 = load_audio(path, WHISPER_RATE)
    total = len(audio16) / WHISPER_RATE
    segments, _ = model.transcribe(
        audio16,
        language=language,
        word_timestamps=True,
        vad_filter=True,
        condition_on_previous_text=False,
        initial_prompt="Hello! This is a clean transcript, with proper punctuation and capitalization.",
    )
    words, last_report = [], 0
    for seg in segments:
        for w in seg.words or []:
            if w.word.strip():
                words.append((float(w.start), float(w.end), w.word))
        percent = int(100 * seg.end / total) if total else 100
        if percent >= last_report + 10:
            last_report = percent - percent % 10
            print(f"    transcribed {min(last_report, 100)}%")
    return words


def main():
    parser = argparse.ArgumentParser(description="Split and transcribe voice recordings.")
    parser.add_argument("--raw", default="voice_data/raw", help="folder with your recordings")
    parser.add_argument("--out", default="voice_data/clips", help="folder for clips + metadata.csv")
    parser.add_argument("--model", default="large-v3", help="Whisper model size")
    parser.add_argument("--language", default="en")
    parser.add_argument("--cpu", action="store_true", help="do not use the GPU")
    parser.add_argument("--overwrite", action="store_true", help="replace an existing dataset")
    args = parser.parse_args()

    raw_dir, out_dir = Path(args.raw), Path(args.out)
    meta_path = out_dir / "metadata.csv"

    if not raw_dir.is_dir():
        sys.exit(f"Can't find the folder '{raw_dir}'. Create it and put your recordings inside.")
    recordings = sorted(p for p in raw_dir.iterdir() if p.suffix.lower() in AUDIO_TYPES)
    if not recordings:
        sys.exit(f"No audio files found in '{raw_dir}'.")
    if meta_path.exists() and not args.overwrite:
        sys.exit(
            f"'{meta_path}' already exists. Running again would erase any transcript fixes.\n"
            "Add --overwrite if you really want to rebuild everything."
        )

    import soundfile as sf

    out_dir.mkdir(parents=True, exist_ok=True)
    if args.overwrite:
        for old in out_dir.glob("*.wav"):
            old.unlink()

    model = load_model(args.model, args.cpu)
    rows, total_seconds, skipped = [], 0.0, 0

    for number, path in enumerate(recordings, 1):
        print(f"[{number}/{len(recordings)}] {path.name}")
        words = transcribe_words(model, path, args.language)
        if not words:
            print("    no speech found, skipping")
            continue

        audio = load_audio(path, SAMPLE_RATE)
        length = len(audio) / SAMPLE_RATE
        chunks = chunk_words(words)
        stem = re.sub(r"[^A-Za-z0-9_-]+", "_", path.stem).strip("_") or f"rec{number}"
        kept = 0

        for i, chunk in enumerate(chunks):
            prev_end = chunks[i - 1][-1][1] if i > 0 else None
            next_start = chunks[i + 1][0][0] if i + 1 < len(chunks) else None
            start, end = clip_bounds(chunk, prev_end, next_start, length)
            text = re.sub(r"\s+", " ", "".join(w[2] for w in chunk)).strip()

            if end - start < SHORTEST_KEPT or not re.search(r"\w", text):
                skipped += 1
                continue

            kept += 1
            name = f"{stem}_{kept:04d}.wav"
            samples = audio[int(start * SAMPLE_RATE): int(end * SAMPLE_RATE)]
            sf.write(str(out_dir / name), samples, SAMPLE_RATE, subtype="PCM_16")
            rows.append((name, text))
            total_seconds += end - start
        print(f"    {kept} clips")

    if not rows:
        sys.exit("No clips were produced. Check that the recordings contain clear speech.")

    with open(meta_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["file_name", "text"])
        writer.writerows(rows)

    print()
    print(f"Done: {len(rows)} clips, {total_seconds / 60:.1f} minutes of speech.")
    if skipped:
        print(f"Skipped {skipped} fragments that were too short.")
    print(f"Clips and metadata.csv are in: {out_dir.resolve()}")
    print("Next: open metadata.csv and correct any transcript mistakes.")
    if total_seconds < 15 * 60:
        print("Note: under 15 minutes is thin for a good voice match. 30-60 minutes is the goal.")


if __name__ == "__main__":
    main()
