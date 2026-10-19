"""Send text to the voice server and play it (for the Pi or any other device).

Usage: python3 pi_client_example.py "Hello" [--server URL] [--key KEY]
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
    """Speak `text` out loud through the BellAi voice server"""
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
