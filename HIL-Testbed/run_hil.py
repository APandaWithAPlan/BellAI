import argparse
import csv
import hashlib
import importlib.util
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import wave
from datetime import datetime
from pathlib import Path

import numpy as np

import scenarios as sc
from compare_runs import between_devices
from virtual_devices import RATE, Clock, VirtualCamera, VirtualMic, render_audio

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
MOTION = REPO / "Camera" / "homecam-motion.py"
LISTENER = REPO / "RaspPI-Server" / "wake_listener" / "wake_listener.py"
FIELDS = ["time", "commit", "stage", "scenario", "device", "kind", "test", "verdict", "failure_type", "value", "seconds", "detail"]

parser = argparse.ArgumentParser(description="Runs the BellAi camera and microphone tests on virtual or real devices")
parser.add_argument("--stage", choices=["virtual", "physical"], required=True)
parser.add_argument("--scenarios", nargs="*", help="scenario files (default: every .json in scenarios/)")
parser.add_argument("--devices", nargs="*", help="device ids from devices.json (default: every device for the stage)")
parser.add_argument("--only", choices=["camera", "mic"], help="test one kind of device only")
parser.add_argument("--speed", type=float, default=1.0, help="virtual stage: play scenarios faster; homecam-motion.py only runs at 1")
parser.add_argument("--no-service", action="store_true", help="skip running homecam-motion.py itself")
parser.add_argument("--no-model", action="store_true", help="don't add model scenarios for steps the files miss")
parser.add_argument("--mic", default="Razer", help="the --mic name wake_listener.py is started with")
parser.add_argument("--wake-model", default="", help="wake word model to test instead of the one wake_listener.py uses by default")
parser.add_argument("--no-speaker", action="store_true", help="physical stage: don't play sound through the speaker")
parser.add_argument("--results", default=str(HERE / "results"))
args = parser.parse_args()

_motion, _lock = None, threading.Lock()


class Report:
    """Collects the results for one device in one scenario."""

    def __init__(self, scenario, device):
        """Starts an empty list of checks."""
        self.scenario, self.device, self.rows = scenario, device, []

    def add(self, test, verdict, kind="", detail="", value="", seconds=0.0):
        """Saves one check; a failure on a device that isn't required counts as a compatibility finding."""
        if verdict == "fail" and not self.device.get("required", True):
            kind = "compatibility"
        self.rows.append({"stage": args.stage, "scenario": self.scenario["name"], "device": self.device["id"],
                          "kind": self.device["kind"], "test": test, "verdict": verdict,
                          "failure_type": kind if verdict == "fail" else "", "value": value,
                          "seconds": round(seconds, 2), "detail": detail})


def motion_code():
    """Loads homecam-motion.py once so the checks use the same stream reader and motion detector the Pi runs."""
    global _motion
    with _lock:
        if _motion is None:
            spec = importlib.util.spec_from_file_location("homecam_motion", MOTION)
            _motion = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(_motion)
    return _motion


def check_endpoints(report, url, src, size=None, kind="behavior", broken_ok=False):
    """Checks the go2rtc addresses the app and dashboard use: the stream list, a snapshot and the live stream."""
    cv2, begin, problems = motion_code().cv2, time.time(), []
    try:
        with urllib.request.urlopen(f"{url}/api/streams", timeout=5) as r:
            if src not in json.loads(r.read()):
                problems.append(f"{src} missing from /api/streams")
        with urllib.request.urlopen(f"{url}/api/frame.jpeg?src={src}", timeout=10) as r:
            img = cv2.imdecode(np.frombuffer(r.read(), np.uint8), cv2.IMREAD_COLOR)
        if img is None and not broken_ok:
            problems.append("snapshot is not a JPEG")
        elif img is not None and size and (img.shape[1], img.shape[0]) != size:
            problems.append(f"snapshot is {img.shape[1]}x{img.shape[0]}, expected {size[0]}x{size[1]}")
        with urllib.request.urlopen(f"{url}/api/stream.mjpeg?src={src}", timeout=10) as r:
            if not r.headers.get("Content-Type", "").startswith("multipart/x-mixed-replace"):
                problems.append("live stream is not MJPEG")
    except (urllib.error.URLError, OSError, ValueError) as e:
        problems.append(f"request failed ({e})")
    report.add("endpoints", "fail" if problems else "pass", kind,
               "; ".join(problems) or "stream list, snapshot and live stream answer", seconds=time.time() - begin)


def watch_camera(url, src, now, until):
    """Reads the camera stream until scenario time `until`, reconnecting if it drops, and reports what it saw."""
    code = motion_code()
    cv2, detector = code.cv2, code.MotionDetector()
    seen = {"connected": False, "frames": 0, "bad": 0, "error": "", "unreachable": False, "segments": []}
    light, sharp, hashes, hits, streak, last = [], [], [], [], 0, -1.0
    while now() < until:
        try:
            for jpeg in code.mjpeg_frames(f"{url}/api/stream.mjpeg?src={src}"):
                t = now()
                if not seen["segments"] or seen["segments"][-1][1] is not None:
                    seen["segments"].append([t, None])
                    detector.reset()
                    streak = 0
                seen["segments"][-1].append(t)
                seen["frames"] += 1
                hashes.append(hashlib.md5(jpeg).digest())
                img = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_REDUCED_GRAYSCALE_4)
                if img is None:
                    seen["bad"] += 1
                elif t - last >= 1 / code.DETECT_FPS - 1e-6:
                    last = t
                    light.append(float(img.mean()))
                    sharp.append(float(cv2.Laplacian(img, cv2.CV_64F).var()))
                    seen["size"] = f"{img.shape[1] * 4}x{img.shape[0] * 4}"
                    score = detector.score(jpeg)
                    streak = streak + 1 if score is not None and score >= code.MOTION_PCT else 0
                    if streak >= code.TRIGGER_FRAMES:
                        hits.append(t)
                if t >= until:
                    break
        except urllib.error.HTTPError as e:
            seen["error"] = f"camera not found ({e.read().decode(errors='ignore')[:60]})"
        except (ConnectionError, OSError) as e:
            seen["error"] = seen["error"] or f"stream not reachable ({e})"
            seen["unreachable"] = not seen["frames"] and "stream ended" not in str(e)
        if seen["segments"] and seen["segments"][-1][1] is None:
            seen["segments"][-1][1] = seen["segments"][-1].pop()
            del seen["segments"][-1][2:]
        if seen["unreachable"]:
            break
        time.sleep(0.2)
    if not seen["frames"]:
        return seen
    groups = []
    for t in hits:
        if groups and t - groups[-1][1] < 2:
            groups[-1][1] = t
        else:
            groups.append([t, t])
    same = sum(a == b for a, b in zip(hashes, hashes[1:]))
    connected_s = sum(b - a for a, b in seen["segments"]) or 0.01
    seen.update(connected=True, black=bool(light) and float(np.median(light)) < 8,
                frozen=len(hashes) > 5 and same > 0.9 * (len(hashes) - 1), corrupt=seen["bad"] > 0.05 * seen["frames"],
                motion=[[round(a, 1), round(b, 1)] for a, b in groups], first_frame=round(seen["segments"][0][0], 2),
                light=round(float(np.median(light)), 1) if light else 0, sharpness=round(float(np.median(sharp)), 1) if sharp else 0,
                fps=round(seen["frames"] / connected_s, 1), bad_pct=round(100 * seen["bad"] / seen["frames"], 1))
    return seen


def compare(report, want, seen, took, fault_kind="behavior"):
    """Checks connection and picture or sound health; returns True when the device was found as expected."""
    if not seen.get("connected"):
        kind = "environment" if seen.get("unreachable") else "device"
        note = "" if want["connected"] else ", as the scenario expects"
        report.add("connected", "pass" if not want["connected"] else "fail", kind,
                   (seen.get("error") or "not found") + note, seconds=took)
        return False
    if not want["connected"]:
        report.add("connected", "fail", "behavior", "found, but the scenario unplugs it", seconds=took)
        return False
    metrics = [f"{k}={seen[k]}" for k in ("size", "fps", "first_frame", "light", "sharpness", "bad_pct", "level_db") if k in seen]
    report.add("connected", "pass", detail=" ".join(metrics), value=seen.get("first_frame", ""), seconds=took)
    for check in ("black", "frozen", "corrupt", "silent", "clipped"):
        if check in want:
            ok = seen[check] == want[check]
            report.add(check, "pass" if ok else "fail", "device" if seen[check] else fault_kind,
                       f"{'is' if seen[check] else 'not'} {check}" + ("" if ok else f", expected {'' if want[check] else 'not '}{check}"))
    return True


def check_windows(report, test, starts, want, early, late, what):
    """Checks that every required motion was caught and nothing was caught outside a motion window."""
    inside = lambda t, a, b: a - early <= t <= b + late
    missed = [[a, b] for a, b in want["motion"] if not any(inside(t, a, b) for t in starts)]
    extra = [t for t in starts if not any(inside(t, a, b) for a, b in want["allowed"])]
    problems = ([f"missed {missed}"] if missed else []) + ([f"false {what} at {extra}"] if extra else [])
    report.add(test, "fail" if problems else "pass", "behavior",
               f"{what} at {starts}, expected {want['motion']}" + (f" ({'; '.join(problems)})" if problems else ""))


def camera_job(report, url, src, now, until, want, fps, size):
    """Tests one virtual camera for a scenario: addresses, connection, picture, frame rate, reconnect and motion."""
    if want["connected"]:
        check_endpoints(report, url, src, size, broken_ok=want["corrupt"])
    begin = time.time()
    seen = watch_camera(url, src, now, until)
    if not compare(report, want, seen, time.time() - begin):
        return
    drop = round(max(0.0, 100 * (1 - seen["fps"] / fps)), 1)
    report.add("frame_rate", "pass" if drop <= 20 else "fail", "environment",
               f"{seen['fps']} of {fps} fps, {drop}% dropped" + ("" if drop <= 20 else " (test machine too busy)"), value=seen["fps"])
    if want.get("unplug"):
        back = [a for a, _ in seen["segments"] if a >= want["unplug"][1] - 0.1]
        took = round(back[0] - want["unplug"][1], 2) if back else None
        report.add("reconnect", "pass" if back else "fail", "behavior",
                   f"stream back {took} s after replug" if back else "stream never came back", value=took if back else "")
    if "motion" in want:
        check_windows(report, "motion", [g[0] for g in seen["motion"]], want, 0.5, 1, "motion")


def service_job(report, url, src, clock, until, want):
    """Runs homecam-motion.py itself against the virtual camera and checks the clips it records."""
    folder = Path(tempfile.mkdtemp(prefix="hil_rec_"))
    env = dict(os.environ, GO2RTC_URL=url, DETECT_SRC=src, RECORD_DIR=str(folder), PRE_ROLL_S="1", POST_ROLL_S="2", MIN_FREE_GB="0")
    proc = subprocess.Popen([sys.executable, str(MOTION)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    while clock.now() < until + 0.5:
        time.sleep(0.2)
    proc.send_signal(signal.SIGTERM)
    try:
        out = proc.communicate(timeout=60)[0]
    except subprocess.TimeoutExpired:
        proc.kill()
        out = proc.communicate()[0] + "\nkilled: did not stop within 60 s"
    lines = out.strip().splitlines()
    crashed = proc.returncode not in (0, -signal.SIGTERM) or "Traceback" in out
    report.add("service_ran", "fail" if crashed else "pass", "behavior",
               f"exit {proc.returncode}: {lines[-1][:120] if lines else ''}" if crashed else
               f"ran {until:.0f} s without crashing, logged {sum('retrying' in l for l in lines)} stream retries")
    try:
        events = json.loads((folder / "events.json").read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        events = []
    starts = sorted(round(datetime.fromisoformat(e["start"]).timestamp() - clock.t0, 1) for e in events)
    check_windows(report, "recorded", starts, want if "motion" in want else {"motion": [], "allowed": []}, 3, 1.5, "clips")
    shutil.rmtree(folder, ignore_errors=True)


def mic_devices(env):
    """Returns the capture devices `arecord -l` lists, the same way wake_listener.py reads them."""
    out = subprocess.run(["arecord", "-l"], capture_output=True, text=True, env=env).stdout
    return re.findall(r"^card \d+: (\S+) \[(.*?)\], device (\d+): (.*?)$", out, flags=re.M)


def listen(seconds, env=None, play=None):
    """Records from the mic wake_listener.py would pick; returns the audio, or None and the names that were listed."""
    found = mic_devices(env)
    match = [f"plughw:CARD={c},DEV={d}" for c, n, d, desc in found if args.mic.lower() in f"{c} {n} - {desc}".lower()]
    if not match:
        return None, [n for _, n, _, _ in found]
    speaker = subprocess.Popen(["aplay", "-q", str(play)]) if play else None
    raw = subprocess.run(["arecord", "-q", "-D", match[0], "-f", "S16_LE", "-r", str(RATE), "-c", "1", "-t", "raw",
                          "-d", str(math.ceil(seconds))], capture_output=True, env=env).stdout
    if speaker:
        speaker.wait()
    return np.frombuffer(raw[:len(raw) // 2 * 2], dtype=np.int16), []


def tone_snr(audio, start, end, hz):
    """Returns how far a tone of the given pitch stands above the rest of that part of the recording, in dB."""
    part = audio[int(start * RATE):int(end * RATE)].astype(np.float32)
    if len(part) < RATE // 4:
        return -99.0
    spectrum = np.abs(np.fft.rfft(part * np.hanning(len(part))))
    freqs = np.fft.rfftfreq(len(part), 1 / RATE)
    near = spectrum[(freqs > hz * 0.97) & (freqs < hz * 1.03)].max()
    rest = spectrum[(freqs > 100) & ((freqs < hz * 0.9) | (freqs > hz * 1.1))]
    return round(float(20 * np.log10(near / (np.median(rest) + 1e-9))), 1)


def save_wav(audio, path):
    """Writes audio to a 16 kHz mono .wav file."""
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
        w.writeframes(audio.tobytes())


def count_wakes(audio, gain):
    """Runs the recording through wake_listener.py and returns the times it would have woken up."""
    with tempfile.TemporaryDirectory() as folder:
        save_wav(audio, Path(folder) / "heard.wav")
        model = ["--model", str(Path(args.wake_model).resolve())] if args.wake_model else []
        out = subprocess.run([sys.executable, str(LISTENER), "--scores", "--gain", str(gain), *model, "--wav",
                              str(Path(folder) / "heard.wav")], capture_output=True, text=True, timeout=300)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip().splitlines()[-1] if out.stderr.strip() else "wake_listener.py failed")
    times = [float(m) for m in re.findall(r"^\s*([\d.]+)s .*<-- wakes", out.stdout, flags=re.M)]
    return [t for i, t in enumerate(times) if i == 0 or t - times[i - 1] > 1.5]


def describe_mic(audio):
    """Reports what a recording sounds like: silent, clipped and how loud."""
    level = 20 * math.log10(float(np.sqrt(np.mean(audio.astype(np.float64) ** 2))) / 32768 + 1e-9)
    return {"connected": True, "silent": level < -72, "clipped": float(np.mean(np.abs(audio.astype(np.int32)) >= 32700)) > 0.005,
            "level_db": round(level, 1)}


def wake_ready(clips):
    """Returns why the wake word check can't run, or an empty string if it can."""
    if not clips:
        return "no clips in clips/wake"
    if importlib.util.find_spec("openwakeword") is None:
        return "openwakeword not installed"
    return "" if shutil.which("ffmpeg") else "ffmpeg not installed"


def mic_checks(report, scenario, audio, names, clips, gain, took, fault_kind="behavior"):
    """Checks one recording: connection, level, test tones and the wake word."""
    want = sc.expected(scenario)["mic"]
    if audio is None and names and want["connected"]:
        return report.add("connected", "fail", "behavior", f"listed as '{names[0]}', but --mic '{args.mic}' doesn't match it", seconds=took)
    seen = describe_mic(audio) if audio is not None and len(audio) else {"connected": False}
    if not compare(report, want, seen, took, fault_kind) or "tones" not in want:
        return
    for e in scenario["mic"]["events"]:
        if e["type"] == "tone":
            snr = tone_snr(audio, e["start"], e["end"], e["hz"])
            report.add("tone", "pass" if snr >= 20 else "fail", "behavior", f"{e['hz']:.0f} Hz at {snr} dB above the room", value=snr)
    if want["wakes"]:
        reason = wake_ready(clips)
        if reason:
            return report.add("wake_word", "skip", detail=reason)
        begin = time.time()
        try:
            heard = count_wakes(audio, gain)
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            return report.add("wake_word", "fail", "environment", str(e)[:120], seconds=time.time() - begin)
        ok = len(heard) == len(want["wakes"]) and all(a - 0.5 <= t <= a + 3.5 for a, t in zip(want["wakes"], heard))
        report.add("wake_word", "pass" if ok else "fail", "behavior", f"woke at {heard}, expected near {want['wakes']}",
                   seconds=time.time() - begin)


def mic_job(report, scenario, mic, clips):
    """Tests one virtual mic for a scenario by recording it live like wake_listener.py does."""
    begin, start = time.time(), mic.clock.now()
    audio, names = listen(scenario["seconds"] - start, mic.env(start))
    if audio is not None and len(audio):
        audio = np.concatenate([np.zeros(int(start * RATE), dtype=np.int16), audio])
    mic_checks(report, scenario, audio, names, clips, 1, time.time() - begin)


def safely(job, report):
    """Runs a test job and turns a crash in the testbed itself into an environment failure."""
    try:
        job()
    except Exception as e:
        report.add("testbed", "fail", "environment", f"{type(e).__name__}: {e}"[:150])


def run_together(jobs):
    """Starts every job at once so the camera and mic tests follow the same scenario moment."""
    threads = [threading.Thread(target=safely, args=pair) for pair in jobs]
    for t in threads:
        t.start()
    for t in threads:
        t.join()


def show(scenario, reports):
    """Prints a scenario's results grouped by device."""
    print(f"{scenario['name']}: {scenario['description']}")
    for r in reports:
        for row in r.rows:
            print(f"  {row['verdict'].upper():4} {row['device']:24} {row['test']:11} {row['detail']}", flush=True)


def run_virtual(found, devices, clips):
    """Runs every scenario on every virtual device it is allocated to, all on one shared clock."""
    reports = []
    for scenario in found:
        want, clock, jobs, opened, mine = sc.expected(scenario), Clock(args.speed), [], [], []
        built = {}
        makers = [threading.Thread(target=lambda d=d: built.__setitem__(d["id"], VirtualCamera(scenario, d, clock) if d["kind"] == "camera"
                                                                       else VirtualMic(scenario, d, clips, clock))) for d in devices]
        for t in makers:
            t.start()
        for t in makers:
            t.join()
        for d in devices:
            report = Report(scenario, d)
            mine.append(report)
            if d["kind"] == "camera":
                cam = built[d["id"]]
                opened.append(cam)
                jobs.append((lambda r=report, c=cam, d=d: camera_job(r, c.url, "home_cam", clock.now, scenario["seconds"],
                                                                      want["camera"], d["fps"], (d["width"], d["height"])), report))
                if d.get("service") and args.speed == 1 and not args.no_service:
                    service = Report(scenario, d)
                    mine.append(service)
                    jobs.append((lambda r=service, c=cam: service_job(r, c.url, "home_cam", clock, scenario["seconds"], want["camera"]), service))
            else:
                mic = built[d["id"]]
                opened.append(mic)
                jobs.append((lambda r=report, m=mic: mic_job(r, scenario, m, clips), report))
        clock.start()
        run_together(jobs)
        for device in opened:
            device.close()
        show(scenario, mine)
        reports += mine
    return reports


def run_physical(found, devices, clips):
    """Runs the live checks on the Pi's real camera and mic, then plays the scenarios' sound through the speaker."""
    live = sc.clean({"name": "live_room", "description": "The real room as it is right now.", "seconds": 10})
    clock, jobs, reports = Clock(), [], []
    healthy = {"connected": True, "black": False, "frozen": False, "corrupt": False}
    for d in devices:
        report = Report(live, d)
        reports.append(report)
        if d["kind"] == "camera":
            def camera(r=report, d=d):
                check_endpoints(r, d["url"], d["src"], kind="device")
                begin = time.time()
                seen = watch_camera(d["url"], d["src"], clock.now, live["seconds"])
                if compare(r, healthy, seen, time.time() - begin, "device"):
                    r.add("frame_rate", "pass" if seen["fps"] >= 5 else "fail", "device", f"{seen['fps']} fps", value=seen["fps"])
            jobs.append((camera, report))
        else:
            def mic(r=report):
                begin = time.time()
                audio, names = listen(3)
                mic_checks(r, live, audio, names, clips, 5, time.time() - begin, "device")
            jobs.append((mic, report))
    clock.start()
    run_together(jobs)
    show(live, reports)
    for d in devices:
        if d["kind"] != "mic" or not d.get("speaker") or args.no_speaker:
            continue
        for scenario in found:
            if scenario["mic"]["fault"] or not scenario["mic"]["events"]:
                continue
            report = Report(scenario, d)
            with tempfile.TemporaryDirectory() as folder:
                save_wav(render_audio(scenario, clips, room_noise=False), Path(folder) / "play.wav")
                begin = time.time()
                audio, names = listen(scenario["seconds"] + 1, play=Path(folder) / "play.wav")
            mic_checks(report, scenario, audio, names, clips, 5, time.time() - begin)
            show(scenario, [report])
            reports.append(report)
    return reports


def missing_tools(kinds):
    """Returns what this machine still needs before the chosen devices can be tested."""
    need = []
    if "camera" in kinds and importlib.util.find_spec("cv2") is None:
        need.append("opencv (pip install opencv-python-headless)")
    if "camera" in kinds and args.stage == "virtual" and not args.no_service and not shutil.which("ffmpeg"):
        need.append("ffmpeg")
    if "mic" in kinds and args.stage == "physical" and not shutil.which("arecord"):
        need.append("arecord (alsa-utils)")
    if "mic" in kinds and os.name == "nt":
        need.append("Linux, WSL or macOS for the virtual mic")
    return need


def save(reports, summary):
    """Saves the run as a .json file and adds its rows to results/history.csv."""
    out, rows = Path(args.results), [row for r in reports for row in r.rows]
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{args.stage}-{summary['time']}.json").write_text(json.dumps({"summary": summary, "results": rows}, indent=2), encoding="utf-8")
    history = out / "history.csv"
    if history.exists() and history.read_text(encoding="utf-8").split("\n", 1)[0] != ",".join(FIELDS):
        history.replace(out / "history-old.csv")
    new = not history.exists()
    with history.open("a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, FIELDS)
        if new:
            writer.writeheader()
        writer.writerows({"time": summary["time"], "commit": summary["commit"], **row} for row in rows)


def main():
    """Allocates devices, runs the chosen stage, prints a summary and saves the results."""
    every = json.loads((HERE / "devices.json").read_text(encoding="utf-8"))["devices"]
    devices = [d for d in every if d["stage"] == args.stage and (not args.devices or d["id"] in args.devices)
               and args.only in (None, d["kind"])]
    files = args.scenarios or sorted((HERE / "scenarios").glob("*.json"))
    found, clips = sc.load(files), sorted((HERE / "clips" / "wake").glob("*.wav"))
    covered, missing = sc.coverage(found)
    added = [] if args.no_model or args.stage == "physical" else sc.fill(found)
    print(f"Scenarios: {len(found)} from files, reaching {len(covered)} of {len(covered) + len(missing)} model steps")
    if added:
        print(f"Added {len(added)} model scenarios for: {', '.join(missing)}")
    print("Devices: " + ", ".join(f"{d['id']}{'' if d.get('required', True) else ' (compatibility)'}" for d in devices))
    if args.wake_model:
        print(f"Wake word model: {args.wake_model}")
    if args.stage == "virtual" and (args.speed != 1 or args.no_service):
        print("homecam-motion.py itself is skipped (only runs with --speed 1)")

    begin, need = time.time(), missing_tools({d["kind"] for d in devices})
    reports = []
    if need:
        setup = Report({"name": "setup"}, {"id": "this machine", "kind": "setup"})
        setup.add("tools", "fail", "environment", "missing " + ", ".join(need))
        reports.append(setup)
        print(f"  FAIL setup: missing {', '.join(need)}")
    elif devices:
        reports = (run_virtual if args.stage == "virtual" else run_physical)(found + added, devices, clips)
    took = time.time() - begin

    rows = [row for r in reports for row in r.rows]
    count = {v: sum(row["verdict"] == v for row in rows) for v in ("pass", "fail", "skip")}
    kinds = {k: sum(row["failure_type"] == k for row in rows) for k in ("environment", "device", "behavior", "compatibility")}
    blocking = count["fail"] - kinds["compatibility"]
    commit = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    summary = {"stage": args.stage, "commit": commit, "time": time.strftime("%Y%m%d-%H%M%S"), "seconds": round(took, 1),
               **count, "failure_types": kinds, "checks_per_minute": round(len(rows) / max(took, 1) * 60, 1),
               "model_steps": len(covered) + len(missing), "steps_from_files": len(covered), "model_scenarios_added": len(added), "wake_model": args.wake_model or "default"}
    save(reports, summary)

    differ = between_devices(rows)
    if differ:
        print(f"\nDevices disagreed on {len(differ)} checks:")
        for (scenario, kind, test), found_by in differ[:15]:
            print(f"  {scenario} {test}: " + ", ".join(f"{d} {v}" for d, v in found_by.items()))
    print(f"\n{args.stage} stage: {count['pass']} passed, {count['fail']} failed, {count['skip']} skipped "
          f"in {took:.0f} s ({summary['checks_per_minute']} checks a minute)")
    if count["fail"]:
        print("failures by type: " + ", ".join(f"{k} {v}" for k, v in kinds.items() if v))
    if kinds["compatibility"] and not blocking:
        print("Only compatibility findings failed, so the run still passes for the BellAi hardware.")
    sys.exit(1 if blocking else 0)


if __name__ == "__main__":
    main()
