"""
test_api.py - send a photo or a typed meal to the running server.py, the same way the app will.

Run in a SECOND terminal while server.py is running (with the .venv active):
    python test_api.py photos/lunch.jpg
    python test_api.py photos/lunch.jpg --text "half portion"
    python test_api.py --text "2 eggs and a slice of toast"
    python test_api.py --text "a big bowl of chicken alfredo" --url http://192.168.1.50:8000

If you set FOOD_API_KEY for the server, this script sends the same key automatically.
"""

import argparse
import json
import mimetypes
import os
import sys
import time
from pathlib import Path

import requests


def main():
    ap = argparse.ArgumentParser(description="Send a food photo or description to the BellAi Food API.")
    ap.add_argument("image", nargs="?", help="food photo (optional if --text is given)")
    ap.add_argument("--text", default="", help="meal description, or a note for the photo")
    ap.add_argument("--url", default="http://127.0.0.1:8000")
    args = ap.parse_args()

    if not args.image and not args.text:
        ap.error("give a photo, --text, or both")

    headers = {}
    if os.environ.get("FOOD_API_KEY"):
        headers["X-API-Key"] = os.environ["FOOD_API_KEY"]

    files = None
    if args.image:
        path = Path(args.image)
        if not path.is_file():
            sys.exit(f"Can't find the photo: {path}")
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        files = {"image": (path.name, open(path, "rb"), content_type)}

    start = time.perf_counter()
    resp = requests.post(f"{args.url.rstrip('/')}/analyze", files=files,
                         data={"text": args.text}, headers=headers, timeout=300)
    elapsed = time.perf_counter() - start

    print(f"HTTP {resp.status_code}  ({elapsed:.2f} s round trip)")
    try:
        data = resp.json()
        print(json.dumps(data, indent=2))
        if isinstance(data, dict) and data.get("summary"):
            print(f"\nBellAi would say: {data['summary']}")
    except ValueError:
        print(resp.text)


if __name__ == "__main__":
    main()
