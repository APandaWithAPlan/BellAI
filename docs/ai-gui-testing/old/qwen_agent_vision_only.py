# kept only because run 2 used it: the screenshot-only tester, it gave qwen no list of controls and looped. not maintained, the new qwen_agent.py replaces it
# it still reads UDID and IDB from the environment and takes --steps and --out
"""Qwen-driven GUI tester for the BellAI iOS app (stdlib only).

Loop: screenshot the simulator -> ask a vision Qwen on NVIDIA PAIR what it sees and what to do next
-> perform the action with idb -> log everything. The model is the brain, idb is its hands.

    python3 qwen_agent_vision_only.py --steps 25 --out runs/qwen4b
    python3 qwen_agent_vision_only.py --dry-run --steps 1      # brain only, no taps

Qwen3.5 returns coordinates on a 0-1000 grid over the whole image, so they are converted to
simulator points (402x874 on an iPhone 18 Pro).
"""
import argparse, base64, json, os, shutil, subprocess, sys, time, urllib.request

UDID = os.environ.get("UDID", "2ED2D5B6-72A6-4F65-87E0-D1AAEBC1AA13")  # simulator: xcrun simctl list devices booted
IDB = os.environ.get("IDB") or shutil.which("idb") or "idb"  # needs idb_companion running: idb_companion --udid <UDID>
W, H = 402, 874  # simulator points

PROMPT = """You are a QA tester exploring an iOS app called BellAI, a personal assistant. The screenshot is the screen right now.
Goal: visit every tab and screen, and report anything that looks broken: unreadable or low-contrast text,
overlapping or cut-off elements, error messages, misleading labels, empty or stuck loading states.
Do NOT send email, delete anything or press destructive buttons.

Already done (oldest first):
{history}

Reply ONLY with JSON:
{{"observation": "<what is on screen in one sentence>",
  "bug": null or "<one concrete problem you can see on THIS screen>",
  "action": "tap" | "swipe_up" | "back" | "done",
  "x": <0-1000 across the image>, "y": <0-1000 down the image>,
  "why": "<which unvisited screen or control you are going to>"}}
Pick something you have not done yet. Use "done" only when everything has been visited."""


def shot(path):
    full = path + ".full.png"
    subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", full], check=True, capture_output=True)
    subprocess.run(["sips", "-z", str(H), str(W), full, "--out", path], check=True, capture_output=True)
    os.remove(full)
    return base64.b64encode(open(path, "rb").read()).decode()


def ask(endpoint, model, img, history):
    body = {"model": model, "stream": False, "think": False, "format": "json",
            "options": {"temperature": 0.2, "num_predict": 300},
            "messages": [{"role": "user", "images": [img],
                          "content": PROMPT.format(history="\n".join(history[-12:]) or "(nothing yet)")}]}
    req = urllib.request.Request(endpoint + "/api/chat", json.dumps(body).encode(), {"Content-Type": "application/json"})
    t = time.time()
    raw = json.load(urllib.request.urlopen(req, timeout=170))["message"]["content"]
    return json.loads(raw), time.time() - t


def point(a):
    return round(float(a["x"]) / 1000 * W), round(float(a["y"]) / 1000 * H)


def act(a, dry):
    kind = a.get("action")
    if kind == "tap":
        x, y = point(a)
        cmd = [IDB, "ui", "tap", "--udid", UDID, str(x), str(y)]
    elif kind == "swipe_up":
        cmd = [IDB, "ui", "swipe", "--udid", UDID, str(W // 2), "650", str(W // 2), "250"]
    elif kind == "back":
        cmd = [IDB, "ui", "tap", "--udid", UDID, "40", "110"]  # BellAI's close/back button sits top-left
    else:
        return "no action"
    if dry:
        return "DRY " + " ".join(cmd[3:])
    subprocess.run(cmd, check=True, capture_output=True)
    return "ran " + " ".join(cmd[3:])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--endpoint", default="http://127.0.0.1:11435")  # PAIR proxy, forwards to the GPU nodes
    p.add_argument("--model", default="qwen3.5:4b-q4_K_M")
    p.add_argument("--steps", type=int, default=25)
    p.add_argument("--out", default="runs/qwen")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    history, log = [], open(os.path.join(a.out, "steps.jsonl"), "w")
    for i in range(1, a.steps + 1):
        png = os.path.join(a.out, f"step{i:02d}.png")
        img = shot(png)
        try:
            reply, secs = ask(a.endpoint, a.model, img, history)
        except Exception as e:  # bad JSON or a gateway error: record it and keep going
            reply, secs = {"action": "swipe_up", "observation": f"model error: {e}", "bug": None}, 0
        result = act(reply, a.dry_run)
        entry = {"step": i, "shot": os.path.basename(png), "secs": round(secs, 1), **reply, "result": result}
        log.write(json.dumps(entry) + "\n"); log.flush()
        print(f"[{i:02d}] {secs:4.1f}s  {reply.get('action')} ({reply.get('x')},{reply.get('y')})  "
              f"{reply.get('observation')}  BUG: {reply.get('bug')}")
        history.append(f"{i}. saw: {reply.get('observation')} -> {reply.get('action')} ({reply.get('why')})")
        if reply.get("action") == "done":
            break
        time.sleep(1.5)


if __name__ == "__main__":
    main()
