"""
compare_engines.py - make the same lines with Orpheus and with GPT-SoVITS, side by side.

Before running:
  * Ollama is running (Orpheus lives there as "bellai-voice")
  * BellAi Studio is open (double-click "BellAi Studio.bat"), which serves GPT-SoVITS

Run (from the Voice Training folder):
    python compare_engines.py
    python compare_engines.py --orpheus-model bellai-voice-q6

It saves:
    test_outputs/compare/orpheus/line_1.wav ...    Orpheus
    test_outputs/compare/sovits/line_1.wav ...     GPT-SoVITS
    test_outputs/compare/blind/line_1_A.wav / _B.wav   the same files with the names hidden,
                                                       so you can pick a favourite without bias
    test_outputs/compare/blind/answers.txt          which letter was which (peek after!)
and prints how quickly each one started talking.

Then, for a voice-similarity score against your real clips:
    python compare_voice.py test_outputs\\compare\\orpheus test_outputs\\compare\\sovits --similarity
"""

import argparse
import json
import random
import time
import urllib.error
import urllib.request
from pathlib import Path

import numpy as np
import soundfile as sf

from fast_speak import SAMPLE_RATE, Decoder, stream_frames
from speak import split_text

HERE = Path(__file__).resolve().parent
OUT = HERE / "test_outputs" / "compare"
STUDIO = "http://127.0.0.1:9890/api/speak"

# Lines that are not in your recordings, so neither model can just repeat what it learned.
LINES = [
    "Good morning! It's sixty-two degrees and sunny, so it's a great day for a walk.",
    "I set a timer for twelve minutes. I'll let you know when the pasta is ready.",
    "Hmm, I'm not totally sure, but I think the store closes at nine tonight.",
    "Oh no, it looks like the front door is still unlocked. Do you want me to lock it?",
    "Your friends just pulled into the driveway! Should I turn on the porch light?",
    "Beanie's food bowl has been empty since this afternoon, and she is not happy about it.",
    "Here's a fun fact: octopuses have three hearts, and two of them stop when they swim.",
    "That's everything on your calendar for today. Get some rest, you earned it.",
]


def orpheus(text, decoder, model):
    """Returns (seconds until the first sound could play, audio)."""
    started, first, frames = time.time(), None, []
    for part in split_text(text):
        for frame in stream_frames(part, model):
            frames.append(frame)
            if first is None and len(frames) == 4:          # fast_speak plays after ~4 frames
                decoder.decode(frames)                      # include the time to decode them
                first = time.time() - started
    audio = decoder.decode(frames)
    return (first or time.time() - started), np.asarray(audio, dtype=np.float32), SAMPLE_RATE


def sovits(text):
    body = json.dumps({"text": text}).encode()
    request = urllib.request.Request(STUDIO, data=body, headers={"Content-Type": "application/json"})
    started, first, chunks = time.time(), None, []
    with urllib.request.urlopen(request, timeout=120) as response:
        rate = int(response.headers.get("X-Sample-Rate", 32000))
        while True:
            chunk = response.read(4096)
            if not chunk:
                break
            if first is None:
                first = time.time() - started
            chunks.append(chunk)
    data = b"".join(chunks)
    audio = np.frombuffer(data[: len(data) // 2 * 2], dtype=np.int16).astype(np.float32) / 32768
    return first, to_24k(audio, rate), SAMPLE_RATE


def to_24k(audio, rate):
    """Save both voices at the same sample rate, so the scores compare fairly."""
    if rate == SAMPLE_RATE:
        return audio
    try:
        from math import gcd
        from scipy.signal import resample_poly
        g = gcd(SAMPLE_RATE, rate)
        return resample_poly(audio, SAMPLE_RATE // g, rate // g).astype(np.float32)
    except ImportError:
        positions = np.arange(int(len(audio) * SAMPLE_RATE / rate)) * rate / SAMPLE_RATE
        return np.interp(positions, np.arange(len(audio)), audio).astype(np.float32)


def main():
    parser = argparse.ArgumentParser(description="Compare Orpheus and GPT-SoVITS on the same lines.")
    parser.add_argument("--orpheus-model", default="bellai-voice")
    args = parser.parse_args()

    try:
        urllib.request.urlopen("http://127.0.0.1:9890/api/status", timeout=3)
    except (urllib.error.URLError, OSError):
        raise SystemExit("BellAi Studio isn't running. Double-click 'BellAi Studio.bat' first, then run this again.")

    for folder in ("orpheus", "sovits", "blind"):
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    print("Loading the Orpheus audio decoder...")
    decoder = Decoder()
    print("Warming up both voices...")
    orpheus("Hi.", decoder, args.orpheus_model)
    sovits("Hi.")

    answers, rows = [], []
    for n, line in enumerate(LINES, 1):
        print(f"\n[{n}/{len(LINES)}] {line}")
        o_first, o_audio, o_rate = orpheus(line, decoder, args.orpheus_model)
        s_first, s_audio, s_rate = sovits(line)
        sf.write(str(OUT / "orpheus" / f"line_{n}.wav"), o_audio, o_rate)
        sf.write(str(OUT / "sovits" / f"line_{n}.wav"), s_audio, s_rate)
        pair = [("orpheus", o_audio, o_rate), ("sovits", s_audio, s_rate)]
        random.shuffle(pair)
        for letter, (name, audio, rate) in zip("AB", pair):
            sf.write(str(OUT / "blind" / f"line_{n}_{letter}.wav"), audio, rate)
        answers.append(f"line {n}: A = {pair[0][0]}, B = {pair[1][0]}")
        rows.append((n, o_first, s_first))
        print(f"    Orpheus starts in {o_first:.2f}s   GPT-SoVITS starts in {s_first:.2f}s")

    (OUT / "blind" / "answers.txt").write_text("\n".join(answers) + "\n", encoding="utf-8")
    o_avg = sum(r[1] for r in rows) / len(rows)
    s_avg = sum(r[2] for r in rows) / len(rows)
    print("\n" + "-" * 52)
    print(f"Average time to first sound:  Orpheus {o_avg:.2f}s   GPT-SoVITS {s_avg:.2f}s")
    print(f"\nFiles are in {OUT}")
    print("Listen to the 'blind' folder first, pick A or B for each line, then check answers.txt.")
    print("For a voice-similarity score:")
    print("    python compare_voice.py test_outputs\\compare\\orpheus test_outputs\\compare\\sovits --similarity")


if __name__ == "__main__":
    main()
