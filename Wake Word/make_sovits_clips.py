"""Generates "BellAi" clips in the BellAi (GPT-SoVITS) voice for wake word training.

Open BellAi Studio first ("BellAi Studio.bat", wait for Ready), then in PowerShell from this folder:
    python make_sovits_clips.py --listen          # 6 sample clips to check the pronunciation
    python make_sovits_clips.py                   # 1,500 positives + 300 near misses

Positives go to custom_clips/positive_train/sovits and near misses to custom_clips/negative_train/sovits.
The speaking speed is varied for variety, and the Studio's saved speed is put back when it finishes.
Clips are saved at the voice's own sample rate; import_clips.py converts them to 16 kHz mono.
Only the standard library is used, so any Python 3 works. Re-running adds more clips; it never overwrites.

To use the stand-alone voice API (bellai_voice_server.py) instead: --api http://127.0.0.1:9880
"""
import argparse
import json
import random
import struct
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent

# How the wake word is spelled for the voice. Punctuation changes the delivery (flat, asking, excited).
# If --listen shows it saying "bell-eye", switch to the spelling that sounds like "bell-ay-eye".
SPELLING = "Bell A I"
# "!", "..." and "Hmm," versions were dropped: they sounded off or added an extra sound before the word.
WAKE_TEXTS = [f"{SPELLING}.", f"{SPELLING}?"]

# Near misses in the BellAi voice, so the model learns these are NOT the wake word
NEAR_MISSES = ["Bella.", "Hey Bella.", "Bell.", "Belle.", "Belly.", "Bali.", "Ballet.", "Bailey.", "Billy.",
               "Alibi.", "Delhi.", "Valley.", "Bagel.", "Bel Air.", "Ally.", "A I.", "Bella?", "Bella!"]

SPEEDS_PER_BATCH = 25  # clips made at one speed before picking a new one

parser = argparse.ArgumentParser()
parser.add_argument("--studio", default="http://127.0.0.1:9890", help="BellAi Studio address")
parser.add_argument("--api", default="", help="use bellai_voice_server.py at this address instead of the Studio")
parser.add_argument("--key", default="", help="API key, if the voice server was started with one")
parser.add_argument("--positives", type=int, default=1500)
parser.add_argument("--negatives", type=int, default=300)
parser.add_argument("--listen", action="store_true", help="make 6 test clips in custom_clips/_listen and stop")
args = parser.parse_args()


def call(url, body=None, timeout=60):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    if args.key:
        req.add_header("x-api-key", args.key)
    r = urllib.request.urlopen(req, timeout=timeout)
    return r.read(), r.headers


def wav(pcm, rate):
    return (b"RIFF" + struct.pack("<I", len(pcm) + 36) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) + b"data" + struct.pack("<I", len(pcm)) + pcm)


def set_speed(speed):
    if not args.api:
        call(f"{args.studio}/api/settings", {"speed": speed})


def speak(text, speed):
    if args.api:
        audio, _ = call(f"{args.api}/tts", {"text": text, "speed": speed, "stream": False})
        return audio
    pcm, headers = call(f"{args.studio}/api/speak", {"text": text})
    return wav(pcm, int(headers.get("X-Sample-Rate", "32000")))


def make(texts, count, folder, prefix):
    folder.mkdir(parents=True, exist_ok=True)
    start = len(list(folder.glob(f"{prefix}_*.wav")))
    made = failed = 0
    speed = 1.0
    for n, i in enumerate(range(start, start + count)):
        if n % SPEEDS_PER_BATCH == 0:
            speed = round(random.uniform(0.85, 1.25), 2)  # every clip differs anyway: the voice's seed is random
            set_speed(speed)
        text = random.choice(texts)
        try:
            (folder / f"{prefix}_{i:05d}.wav").write_bytes(speak(text, speed))
            made += 1
        except Exception as e:  # keep going if one request fails
            failed += 1
            print(f"  failed: {text!r} ({e})")
            if failed >= 10 and made == 0:
                raise SystemExit("The voice isn't answering. Is BellAi Studio open and showing Ready?")
        if made and made % 50 == 0:
            print(f"  {made}/{count} {prefix} clips")
    print(f"{prefix}: {made} new clips in {folder}")


# Check the voice is up and remember the Studio's speed so it can be restored
original_speed = None
try:
    if args.api:
        call(f"{args.api}/health", timeout=10)
    else:
        status = json.loads(call(f"{args.studio}/api/status", timeout=10)[0])
        if not status.get("ready"):
            raise SystemExit(f"BellAi Studio isn't ready yet ({status.get('status')}). Wait for Ready and try again.")
        original_speed = status["settings"]["speed"]
except OSError:
    where = args.api or args.studio
    raise SystemExit(f"Can't reach the voice at {where}. Open BellAi Studio and wait for Ready.")

clips = HERE / "custom_clips"
try:
    if args.listen:
        folder = clips / "_listen"
        folder.mkdir(parents=True, exist_ok=True)
        set_speed(1.0)
        for i, text in enumerate(WAKE_TEXTS * 3):
            (folder / f"listen_{i}.wav").write_bytes(speak(text, 1.0))
        print(f"Listen to the clips in {folder}. If they don't say bell-ay-eye, change SPELLING at the top.")
    else:
        make(WAKE_TEXTS, args.positives, clips / "positive_train" / "sovits", "sovits")
        make(NEAR_MISSES, args.negatives, clips / "negative_train" / "sovits", "sovits_miss")
finally:
    if original_speed is not None:
        set_speed(original_speed)
        print(f"Studio speed set back to {original_speed}.")
