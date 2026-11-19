"""Qwen GUI tester: a vision Qwen explores the BellAI app in the iOS Simulator and reports what looks broken.

Every step, the accessibility tree lists the controls not yet tapped on the current screen. Qwen looks at the
screenshot, reports any bug and picks one control by number, and idb taps it. The tree says where to tap and
remembers what was already tried, which keeps a small model from going round in circles.

Usage: python3 qwen_agent.py <model> <folder>
The folder gets steps.jsonl and a screenshot of every step. A run starts wherever the app is now, and
run_qwen.sh puts the app back on Home first.

Environment: UDID (the simulator), IDB, ENDPOINT, STEPS.
"""
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

UDID = os.environ["UDID"]
IDB = os.environ.get("IDB") or os.path.expanduser("~/.idbenv/bin/idb")
ENDPOINT = os.environ.get("ENDPOINT", "http://127.0.0.1:11435")  # The PAIR proxy passes the request on to the GPU machines.
STEPS = int(os.environ.get("STEPS", "40"))
W, H = 402, 874  # The simulator screen in points.
SKIP = re.compile(r"send|reset|delete|remove|erase|sign out|request apple health|connect apple health", re.I)  # Never tapped.

PROMPT = """You are a QA tester exploring an iOS app called BellAI, a personal assistant. The screenshot is the screen right now.
Report anything that looks broken: unreadable or low-contrast text, overlapping or cut-off elements, error messages,
misleading labels, empty or stuck loading states. Do NOT report things that look fine.

Controls you have not tapped yet on this screen:
{options}

Reply ONLY with JSON:
{{"observation": "<what is on screen, one sentence>",
  "bug": null or "<one concrete problem you can see on THIS screen>",
  "choice": <the number of the control to tap next>,
  "why": "<why that one>"}}"""


def idb(*args):
    return subprocess.run([IDB, *args, "--udid", UDID], check=True, capture_output=True, text=True).stdout


def shot(path):
    full = path + ".full.png"
    subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", full], check=True, capture_output=True)
    subprocess.run(["sips", "-z", str(H), str(W), full, "--out", path], check=True, capture_output=True)
    os.remove(full)
    return base64.b64encode(open(path, "rb").read()).decode()


def read_screen():
    # Returns the screen's id (a hash of its buttons and headings), its buttons, and whether more of it is below the fold.
    tree = json.loads(idb("ui", "describe-all"))
    names = sorted(f"{e['type']}:{e.get('AXLabel')}" for e in tree if e["type"] in ("Button", "Heading", "PopUpButton"))
    screen = hashlib.md5("|".join(names).encode()).hexdigest()[:8]
    buttons, below = [], False
    for e in tree:
        f = e["frame"]
        if e["type"] not in ("Button", "TextField", "CheckBox") or f["width"] <= 0:
            continue
        if f["y"] >= H:
            below = True
        elif e["type"] == "Button" and e.get("AXLabel") and not SKIP.search(e["AXLabel"]):
            buttons.append({"label": e["AXLabel"], "x": round(f["x"] + f["width"] / 2), "y": round(f["y"] + f["height"] / 2)})
    return screen, buttons, below


def ask(model, image, options):
    listing = "\n".join(f"{i}. {o['label']}" for i, o in enumerate(options, 1))
    body = {"model": model, "stream": False, "think": False, "format": "json",
            "options": {"temperature": 0.2, "num_predict": 300},
            "messages": [{"role": "user", "images": [image], "content": PROMPT.format(options=listing)}]}
    req = urllib.request.Request(ENDPOINT + "/api/chat", json.dumps(body).encode(), {"Content-Type": "application/json"})
    started = time.time()
    reply = json.loads(json.load(urllib.request.urlopen(req, timeout=170))["message"]["content"])
    return reply, time.time() - started


def main(model, folder):
    os.makedirs(folder, exist_ok=True)
    log = open(os.path.join(folder, "steps.jsonl"), "w")
    tapped = set()  # Pairs of (screen, label) already pressed.
    last = {}  # Maps (screen, label) to the step it was pressed on.
    stale = 0
    for step in range(1, STEPS + 1):
        screen, buttons, below = read_screen()
        options = [b for b in buttons if (screen, b["label"]) not in tapped]
        if below and (screen, "(scroll down)") not in tapped:
            options.append({"label": "(scroll down)", "scroll": True})
        if options:
            stale = 0
        elif buttons and stale < 4:
            # Nothing new here, like a dialog whose only button was pressed before: press the one pressed longest ago.
            options = [min(buttons, key=lambda b: last.get((screen, b["label"]), 0))]
            stale += 1
        else:
            print(f"[{step:02d}] Nothing left to try on screen {screen}, stopping.")
            break
        png = os.path.join(folder, f"step{step:02d}.png")
        image = shot(png)
        try:
            reply, seconds = ask(model, image, options)
            choice = int(reply["choice"]) - 1
            valid = 0 <= choice < len(options)
        except Exception as e:
            # No usable answer: write it down and press the first control so the run goes on.
            reply, seconds, valid = {"observation": f"model error: {e}", "bug": None}, 0, False
        pick = options[choice] if valid else options[0]
        if pick.get("scroll"):
            idb("ui", "swipe", str(W // 2), "650", str(W // 2), "250")
        else:
            idb("ui", "tap", str(pick["x"]), str(pick["y"]))
        tapped.add((screen, pick["label"]))
        last[(screen, pick["label"])] = step
        log.write(json.dumps({"step": step, "screen": screen, "shot": os.path.basename(png), "secs": round(seconds, 1), **reply,
                              "valid_choice": valid, "tapped": pick["label"], "options": [o["label"] for o in options]}) + "\n")
        log.flush()
        print(f"[{step:02d}] {seconds:4.1f}s {screen} tap '{pick['label']}'{'' if valid else ' (invalid answer)'}  "
              f"{reply.get('observation')}  BUG: {reply.get('bug')}", flush=True)
        time.sleep(1.2)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: python3 qwen_agent.py <model> <folder>")
    main(sys.argv[1], sys.argv[2])
