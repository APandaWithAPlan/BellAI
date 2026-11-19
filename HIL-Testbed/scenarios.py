import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CAMERA_FAULTS = ("black", "frozen", "unplugged", "corrupt")
MIC_FAULTS = ("silent", "clipped", "unplugged")
RECOVERY_S = 8

PROMPT = """You design test scenarios for a smart home device with a USB camera and a USB microphone.
Reply with JSON only: {"scenarios": [ ... ]} holding COUNT scenarios. Each scenario looks like this:
{"name": "short_snake_case", "description": "one sentence about the room and what happens", "seconds": 14,
 "camera": {"brightness": 0.6, "noise": 0.02, "fault": null,
            "events": [{"type": "motion", "start": 4, "end": 7, "size": 0.2}, {"type": "unplug", "start": 8, "end": 10}]},
 "mic": {"noise_db": -55, "fault": null,
         "events": [{"type": "tone", "start": 1, "end": 2, "hz": 1000, "db": -12}, {"type": "wake", "start": 5}]}}
Rules: brightness is 0.08 (dark) to 1 (daylight). noise is 0.005 to 0.08. size is how wide the moving person is, 0.1 to 0.4.
Motion starts at 3 seconds or later. An unplug event is the camera cable being pulled out and pushed back in.
noise_db is -65 (quiet) to -30 (loud room). A wake event is someone saying the wake word.
camera fault is null, "black", "frozen", "corrupt" or "unplugged". mic fault is null, "silent", "clipped" or "unplugged".
Make the scenarios different from each other: day and night, quiet and noisy, cables pulled, with and without faults.
Do not reuse these names: USED"""

TEMPLATES = [
    {"name": "model_camera_replug", "seconds": 26,
     "description": "Someone walks by, the camera cable is pulled while a second person passes, then a third visit after it is plugged back in.",
     "camera": {"brightness": 0.7, "events": [{"type": "motion", "start": 3, "end": 4.5}, {"type": "unplug", "start": 7, "end": 11},
                                              {"type": "motion", "start": 8.5, "end": 10}, {"type": "motion", "start": 20, "end": 23}]},
     "mic": {"events": [{"type": "tone", "start": 1, "end": 2, "hz": 1500, "db": -12}]}},
    {"name": "model_corrupt_frames", "seconds": 8, "description": "A loose USB cable makes the camera send broken frames.",
     "camera": {"fault": "corrupt"}, "mic": {"events": [{"type": "tone", "start": 1, "end": 2, "hz": 600, "db": -12}]}},
    {"name": "model_two_wakes", "seconds": 14, "description": "Someone walks by and the wake word is said twice.",
     "camera": {"events": [{"type": "motion", "start": 4, "end": 6}]},
     "mic": {"events": [{"type": "wake", "start": 3}, {"type": "wake", "start": 9}]}},
]


def num(value, low, high, default):
    """Returns value as a number kept between low and high, or default if it is not a number."""
    try:
        return min(max(float(value), low), high)
    except (TypeError, ValueError):
        return default


def clean(raw):
    """Returns a safe copy of a scenario with every setting kept inside its allowed range."""
    name = re.sub(r"[^a-z0-9]+", "_", str(raw.get("name", "")).lower()).strip("_")[:40]
    if not name:
        raise ValueError("scenario has no name")
    seconds = num(raw.get("seconds"), 8, 30, 12)
    cam, mic = raw.get("camera") or {}, raw.get("mic") or {}
    cam_fault = cam.get("fault") if cam.get("fault") in CAMERA_FAULTS else None
    cam_events = [] if cam_fault else cam.get("events") or []

    unplug = None
    for e in cam_events:
        if e.get("type") == "unplug" and unplug is None:
            start = num(e.get("start"), 3, seconds - 4, 5)
            unplug = {"type": "unplug", "start": start, "end": num(e.get("end"), start + 1, min(start + 6, seconds - 1), start + 3)}

    motion, last = [], 0.0
    for e in sorted(cam_events, key=lambda e: num(e.get("start"), 0, 99, 0)):
        start = max(num(e.get("start"), 3, seconds - 3, 3), last + 4 if motion else 3)
        end = num(e.get("end"), start + 1.5, start + 5, start + 2.5)
        if e.get("type") == "motion" and end <= seconds - 1 and len(motion) < 3:
            motion.append({"type": "motion", "start": start, "end": end, "size": num(e.get("size"), 0.1, 0.4, 0.2)})
            last = end

    wakes, tones = [], []
    for e in sorted((mic.get("events") or []), key=lambda e: num(e.get("start"), 0, 99, 0)):
        start = num(e.get("start"), 0.5, seconds - 3, 1)
        if e.get("type") == "wake" and len(wakes) < 2 and (not wakes or start >= wakes[-1]["start"] + 4):
            wakes.append({"type": "wake", "start": start})
    for e in mic.get("events") or []:
        start = num(e.get("start"), 0.5, seconds - 1.5, 1)
        end = num(e.get("end"), start + 0.5, min(start + 3, seconds - 0.5), start + 1)
        near_wake = any(start < w["start"] + 2.5 and end > w["start"] - 0.5 for w in wakes)
        if e.get("type") == "tone" and len(tones) < 3 and not near_wake:
            tones.append({"type": "tone", "start": start, "end": end, "hz": num(e.get("hz"), 300, 4000, 1000),
                          "db": num(e.get("db"), -30, -6, -12)})

    return {"name": name, "description": str(raw.get("description", ""))[:200], "seconds": seconds,
            "camera": {"brightness": num(cam.get("brightness"), 0.08, 1, 0.6), "noise": num(cam.get("noise"), 0.005, 0.08, 0.02),
                       "fault": cam_fault, "events": motion + ([unplug] if unplug else [])},
            "mic": {"noise_db": num(mic.get("noise_db"), -65, -30, -55),
                    "fault": mic.get("fault") if mic.get("fault") in MIC_FAULTS else None, "events": tones + wakes}}


def motions(s):
    """Returns the motion events of a scenario."""
    return [e for e in s["camera"]["events"] if e["type"] == "motion"]


def unplug_window(s):
    """Returns when the camera is unplugged during a scenario as (start, end), or None."""
    found = [(e["start"], e["end"]) for e in s["camera"]["events"] if e["type"] == "unplug"]
    return found[0] if found else None


def expected(s):
    """Works out what a healthy run should see for a scenario, from the device model and not from the AI."""
    cam, mic = s["camera"], s["mic"]
    want_cam = {"connected": cam["fault"] != "unplugged"}
    if want_cam["connected"]:
        want_cam.update(black=cam["fault"] == "black", frozen=cam["fault"] == "frozen", corrupt=cam["fault"] == "corrupt")
        if not cam["fault"]:
            gap = unplug_window(s)
            seen = lambda e: not gap or e["end"] <= gap[0] or e["start"] >= gap[1] + RECOVERY_S
            want_cam.update(motion=[[e["start"], e["end"]] for e in motions(s) if seen(e)],
                            allowed=[[e["start"], e["end"]] for e in motions(s)], unplug=gap)
    want_mic = {"connected": mic["fault"] != "unplugged"}
    if want_mic["connected"]:
        want_mic.update(silent=mic["fault"] == "silent", clipped=mic["fault"] == "clipped")
        if not mic["fault"]:
            want_mic["tones"] = [e["hz"] for e in mic["events"] if e["type"] == "tone"]
            want_mic["wakes"] = [e["start"] for e in mic["events"] if e["type"] == "wake"]
    return {"camera": want_cam, "mic": want_mic}


def steps(s):
    """Checks each step of the camera and mic model against a scenario."""
    cam, mic, gap = s["camera"], s["mic"], unplug_window(s)
    during = [e for e in motions(s) if gap and e["start"] < gap[1] and e["end"] > gap[0]]
    after = [e for e in motions(s) if gap and e["start"] >= gap[1] + RECOVERY_S]
    steps = {
        "camera: plugged in -> streaming": cam["fault"] != "unplugged",
        "camera: missing at start": cam["fault"] == "unplugged",
        "camera: streaming -> motion -> streaming": not cam["fault"] and len(motions(s)) >= 1,
        "camera: motion -> motion (two visits)": not cam["fault"] and len(motions(s)) >= 2,
        "camera: streaming -> unplugged -> streaming": bool(gap),
        "camera: motion while unplugged": bool(during),
        "camera: replugged -> motion": bool(after),
        "camera: streaming -> black": cam["fault"] == "black",
        "camera: streaming -> frozen": cam["fault"] == "frozen",
        "camera: streaming -> corrupt frames": cam["fault"] == "corrupt",
        "mic: plugged in -> listening": mic["fault"] != "unplugged",
        "mic: missing at start": mic["fault"] == "unplugged",
        "mic: listening -> tone": any(e["type"] == "tone" for e in mic["events"]) and not mic["fault"],
        "mic: listening -> wake word": any(e["type"] == "wake" for e in mic["events"]) and not mic["fault"],
        "mic: wake word -> wake word": sum(e["type"] == "wake" for e in mic["events"]) >= 2 and not mic["fault"],
        "mic: listening -> silent": mic["fault"] == "silent",
        "mic: listening -> clipped": mic["fault"] == "clipped",
    }
    return steps


def transitions(s):
    """Returns the steps of the camera and mic model that a scenario exercises."""
    return {step for step, hit in steps(s).items() if hit}


def coverage(found):
    """Returns which model steps the scenarios cover and which they miss."""
    every = set(steps(clean({"name": "blank"})))
    covered = set().union(*(transitions(s) for s in found)) if found else set()
    return sorted(covered), sorted(every - covered)


def fill(found):
    """Adds model scenarios for any model steps the given scenarios don't reach."""
    added = []
    for raw in TEMPLATES:
        missing = set(coverage(found + added)[1])
        scenario = clean(raw)
        if scenario["name"] not in {s["name"] for s in found} and transitions(scenario) & missing:
            added.append(scenario)
    return added


def load(paths):
    """Reads scenarios from one or more .json files and cleans each one."""
    found = {}
    for path in paths:
        for raw in json.loads(Path(path).read_text(encoding="utf-8"))["scenarios"]:
            scenario = clean(raw)
            found.setdefault(scenario["name"], scenario)
    return list(found.values())


def generate(count, server, model, used):
    """Asks the AI model for new scenarios and keeps the ones that pass clean()."""
    prompt = PROMPT.replace("COUNT", str(count)).replace("USED", ", ".join(used) or "(none)")
    body = json.dumps({"model": model, "stream": False, "format": "json",
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    request = urllib.request.Request(f"{server}/api/chat", body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=300) as r:
        reply = json.loads(r.read())["message"]["content"]
    kept = []
    for raw in json.loads(reply).get("scenarios", []):
        try:
            scenario = clean(raw)
        except (ValueError, AttributeError):
            continue
        if scenario["name"] not in used:
            used.append(scenario["name"])
            kept.append(scenario)
    return kept


def speak(server, text, path):
    """Asks the BellAi voice server to say the wake word and saves it as a clip for wake events."""
    body = json.dumps({"text": text, "stream": False}).encode()
    request = urllib.request.Request(f"{server}/tts", body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as r:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(r.read())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Makes test scenarios with an AI model and checks them against the device model")
    parser.add_argument("--generate", type=int, default=0, help="how many new scenarios to ask the model for")
    parser.add_argument("--server", default="http://127.0.0.1:11434", help="Ollama-style server that runs the model")
    parser.add_argument("--model", default="qwen3.5:4b-q4_K_M")
    parser.add_argument("--speak", default="", help="voice server, e.g. http://<ai-server>:9880; saves a spoken wake word clip")
    parser.add_argument("--coverage", nargs="*", help="show which model steps these scenario files cover")
    parser.add_argument("--out", default=str(HERE / "scenarios" / "generated.json"))
    args = parser.parse_args()
    if args.speak:
        speak(args.speak, "BellAi.", HERE / "clips" / "wake" / "bellai_voice.wav")
        print("Saved clips/wake/bellai_voice.wav")
    if args.generate:
        out = Path(args.out)
        old = load([out]) if out.exists() else []
        used = [s["name"] for s in load([HERE / "scenarios" / "baseline.json"]) + old]
        new = generate(args.generate, args.server, args.model, used)
        out.write_text(json.dumps({"scenarios": old + new}, indent=2) + "\n", encoding="utf-8")
        print(f"Kept {len(new)} of {args.generate} scenarios from {args.model}: {', '.join(s['name'] for s in new)}")
        covered, missing = coverage(new)
        print(f"The new scenarios reach {len(covered)} of {len(covered) + len(missing)} model steps")
        if not new:
            sys.exit(1)
    if args.coverage is not None:
        covered, missing = coverage(load(args.coverage or sorted((HERE / "scenarios").glob("*.json"))))
        print(f"{len(covered)} of {len(covered) + len(missing)} model steps covered")
        for step in missing:
            print(f"  missing: {step}")
