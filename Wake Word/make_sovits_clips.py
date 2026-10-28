"""Generates "BellAi" clips in the BellAi (GPT-SoVITS) voice for wake word training.

Start the voice API first (Voice Training/studio/bellai_voice_server.py, port 9880), then on Windows:
    python make_sovits_clips.py --listen          # 6 sample clips to check the pronunciation
    python make_sovits_clips.py                   # 1,500 positives + near misses

Positives go to custom_clips/positive_train/sovits and near misses to custom_clips/negative_train/sovits.
Clips are saved as they come from the voice (32 kHz). import_clips.py converts them to 16 kHz mono.
Only the standard library is used, so any Python 3 works. Re-running adds more clips; it never overwrites.
"""
import argparse
import json
import random
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent

# How the wake word is spelled for the voice. Punctuation changes the delivery (flat, asking, excited).
# If --listen shows it saying "bell-eye", switch to the spelling that sounds like "bell-ay-eye".
SPELLING = "Bell A I"
WAKE_TEXTS = [f"{SPELLING}.", f"{SPELLING}?", f"{SPELLING}!", f"{SPELLING}...", f"Hmm, {SPELLING}."]

# Near misses in the BellAi voice, so the model learns these are NOT the wake word
NEAR_MISSES = ["Bella.", "Hey Bella.", "Bell.", "Belle.", "Belly.", "Bali.", "Ballet.", "Bailey.", "Billy.",
               "Alibi.", "Delhi.", "Valley.", "Bagel.", "Bel Air.", "Ally.", "A I.", "Bella?", "Bella!"]

parser = argparse.ArgumentParser()
parser.add_argument("--url", default="http://127.0.0.1:9880/tts", help="the BellAi voice API")
parser.add_argument("--key", default="", help="API key, if the voice server was started with one")
parser.add_argument("--positives", type=int, default=1500)
parser.add_argument("--negatives", type=int, default=300)
parser.add_argument("--listen", action="store_true", help="make 6 test clips in custom_clips/_listen and stop")
args = parser.parse_args()


def speak(text, speed):
    body = json.dumps({"text": text, "speed": speed, "stream": False}).encode()
    req = urllib.request.Request(args.url, data=body, headers={"Content-Type": "application/json"})
    if args.key:
        req.add_header("x-api-key", args.key)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def make(texts, count, folder, prefix):
    folder.mkdir(parents=True, exist_ok=True)
    start = len(list(folder.glob(f"{prefix}_*.wav")))
    made = failed = 0
    for i in range(start, start + count):
        text = random.choice(texts)
        speed = round(random.uniform(0.85, 1.25), 2)  # the API's seed is random, so every clip differs
        try:
            (folder / f"{prefix}_{i:05d}.wav").write_bytes(speak(text, speed))
            made += 1
        except Exception as e:  # keep going if one request fails
            failed += 1
            print(f"  failed: {text!r} ({e})")
            if failed >= 10 and made == 0:
                raise SystemExit("The voice API isn't answering. Is bellai_voice_server.py running on port 9880?")
        if made and made % 50 == 0:
            print(f"  {made}/{count} {prefix} clips")
    print(f"{prefix}: {made} new clips in {folder}")


clips = HERE / "custom_clips"
if args.listen:
    folder = clips / "_listen"
    folder.mkdir(parents=True, exist_ok=True)
    for i, text in enumerate(WAKE_TEXTS + [f"{SPELLING}."]):
        (folder / f"listen_{i}.wav").write_bytes(speak(text, 1.0))
    print(f"Listen to the clips in {folder}. If they don't say bell-ay-eye, change SPELLING at the top.")
else:
    make(WAKE_TEXTS, args.positives, clips / "positive_train" / "sovits", "sovits")
    make(NEAR_MISSES, args.negatives, clips / "negative_train" / "sovits", "sovits_miss")
