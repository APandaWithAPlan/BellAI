"""
pi_client_example.py - make the BellAi voice speak from another device (Raspberry Pi, laptop, ...).

It sends text to the BellAi voice server and plays the audio while it is still arriving,
so speech starts within about a second. Only uses Python's standard library.

    python3 pi_client_example.py "Good morning! The coffee is ready."
    python3 pi_client_example.py --server http://192.168.1.50:9880 --key SECRET "Hello"

Playback uses `aplay` on Linux / Raspberry Pi (preinstalled on Raspberry Pi OS),
`ffplay` if it is installed, or saves bellai.wav on other systems.

To use it from your own code:
    from pi_client_example import say
    say("Your timer is done!")
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

SERVER = os.environ.get("BELLAI_SERVER", "http://127.0.0.1:9880")
KEY = os.environ.get("BELLAI_KEY", "")


def say(text, server=SERVER, key=KEY, save_to=None):
    """Speak `text` out loud through the BellAi voice server."""
    request = urllib.request.Request(
        server.rstrip("/") + "/tts",
        data=json.dumps({"text": text}).encode(),
        headers={"Content-Type": "application/json", **({"X-API-Key": key} if key else {})},
    )
    player = None
    if not save_to:
        if shutil.which("aplay"):
            player = subprocess.Popen(["aplay", "-q", "-"], stdin=subprocess.PIPE)
        elif shutil.which("ffplay"):
            player = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", "-"], stdin=subprocess.PIPE)
        else:
            save_to = "bellai.wav"
    out = open(save_to, "wb") if save_to else None
    finished = False
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            while True:
                chunk = response.read(4096)
                if not chunk:
                    break
                if player:
                    player.stdin.write(chunk)
                    player.stdin.flush()
                if out:
                    out.write(chunk)
        finished = True
    finally:
        if player:
            player.stdin.close()
            player.wait()
        if out:
            out.close()
            if finished:
                print(f"Saved {save_to}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Speak through the BellAi voice server.")
    p.add_argument("text")
    p.add_argument("--server", default=SERVER)
    p.add_argument("--key", default=KEY)
    p.add_argument("--save", default=None, help="save to this WAV file instead of playing")
    a = p.parse_args()
    try:
        say(a.text, a.server, a.key, a.save)
    except urllib.error.URLError as err:
        sys.exit(f"Couldn't reach the BellAi voice server at {a.server}: {err}")
