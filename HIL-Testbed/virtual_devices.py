import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import wave
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np

RATE = 16000

ARECORD = '''#!PYTHON
import os, sys, time
fault, speed = os.environ.get("HIL_MIC_FAULT", ""), float(os.environ.get("HIL_SPEED", "1"))
if "-l" in sys.argv:
    if fault != "unplugged":
        print("**** List of CAPTURE Hardware Devices ****")
        print(os.environ["HIL_MIC_CARD"])
    sys.exit(0)
if fault == "unplugged":
    sys.exit("arecord: main:831: audio open error: No such file or directory")
data, t0 = open(os.environ["HIL_MIC_RAW"], "rb").read(), float(os.environ["HIL_T0"])
start = float(os.environ["HIL_FROM"]) if os.environ.get("HIL_FROM") else max(0.0, (time.time() - t0) * speed)
pos = int(start * 16000) * 2
stop = pos + int(float(sys.argv[sys.argv.index("-d") + 1]) * speed * 32000) if "-d" in sys.argv else len(data)
try:
    while pos < min(stop, len(data)):
        sys.stdout.buffer.write(data[pos:pos + 3200])
        sys.stdout.buffer.flush()
        pos += 3200
        time.sleep(max(0.0, t0 + pos / 32000 / speed - time.time()))
except BrokenPipeError:
    pass
'''


class Clock:
    """One scenario clock shared by every virtual device, so the camera and mic play the same moment together."""

    def __init__(self, speed=1.0):
        """Sets how fast scenario time runs compared with real time."""
        self.speed, self.t0 = speed, None

    def start(self):
        """Starts scenario time at zero."""
        self.t0 = time.time()

    def now(self):
        """Returns the current scenario time in seconds."""
        return 0.0 if self.t0 is None else (time.time() - self.t0) * self.speed

    def wall(self, t):
        """Returns the real time at which scenario time t happens."""
        return self.t0 + t / self.speed


def seed(scenario):
    """Returns a random generator that gives the same result every time for the same scenario name."""
    return np.random.default_rng(zlib.crc32(scenario["name"].encode()))


def load_clip(path):
    """Reads a .wav clip as 16 kHz mono numbers between -1 and 1."""
    if shutil.which("ffmpeg"):
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-ar", str(RATE), "-ac", "1",
                              "-f", "s16le", "-"], check=True, capture_output=True).stdout
    else:
        with wave.open(str(path), "rb") as w:
            raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768


def render_audio(scenario, clips=(), room_noise=True, gain_db=0.0):
    """Builds what the microphone hears in a scenario: room noise, test tones, spoken wake words and any fault."""
    mic, rng = scenario["mic"], seed(scenario)
    n = int(scenario["seconds"] * RATE)
    audio = rng.normal(0, 10 ** (mic["noise_db"] / 20), n) if room_noise else np.zeros(n)
    spoken = 0
    for e in mic["events"]:
        a = int(e["start"] * RATE)
        if e["type"] == "tone":
            t = np.arange(int((e["end"] - e["start"]) * RATE)) / RATE
            fade = np.minimum(1, np.minimum(t, t[::-1]) / 0.02)
            audio[a:a + len(t)] += 10 ** (e["db"] / 20) * np.sin(2 * np.pi * e["hz"] * t) * fade
        elif e["type"] == "wake" and clips:
            clip = load_clip(clips[spoken % len(clips)])[:n - a]
            audio[a:a + len(clip)] += clip * 0.5 / (np.abs(clip).max() + 1e-9)
            spoken += 1
    audio *= 10 ** (gain_db / 20)
    if mic["fault"] == "silent":
        audio[:] = 0
    if mic["fault"] == "clipped":
        audio *= 40
    return (np.clip(audio, -1, 1) * 32767).astype(np.int16)


def render_frames(scenario, width, height, fps):
    """Builds what the camera sees in a scenario as JPEG frames: a room, people walking by, the light level and any fault."""
    import cv2
    cam, rng = scenario["camera"], seed(scenario)
    room = np.tile(np.linspace(70, 130, width, dtype=np.float32), (height, 1))
    for _ in range(6):
        x, y = int(rng.uniform(0, 0.85) * width), int(rng.uniform(0.33, 0.8) * height)
        room[y:y + int(rng.uniform(0.1, 0.35) * height), x:x + int(rng.uniform(0.08, 0.23) * width)] = rng.integers(50, 170)
    frames = []
    for i in range(int(scenario["seconds"] * fps)):
        t, frame = i / fps, room.copy()
        for e in cam["events"]:
            if e["type"] == "motion" and e["start"] <= t < e["end"]:
                wide = int(e["size"] * width)
                x = int(-wide + (width + wide) * (t - e["start"]) / (e["end"] - e["start"]))
                frame[int(height * 0.25):, max(x, 0):max(x + wide, 0)] = 235
                frame[int(height * 0.1):int(height * 0.25), max(x + wide // 4, 0):max(x + 3 * wide // 4, 0)] = 200
        frame = frame * cam["brightness"] + rng.normal(0, cam["noise"] * 255, frame.shape)
        if cam["fault"] == "black":
            frame = rng.normal(2, 1, frame.shape)
        if cam["fault"] == "frozen" and frames:
            frames.append(frames[0])
            continue
        gray = np.clip(frame, 0, 255).astype(np.uint8)
        jpeg = cv2.imencode(".jpg", cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR), [cv2.IMWRITE_JPEG_QUALITY, 80])[1].tobytes()
        if cam["fault"] == "corrupt" and rng.random() < 0.25:
            jpeg = b"\xff\xd8" + rng.integers(0, 255, 3000, dtype=np.uint8).tobytes().replace(b"\xff", b"\x00") + b"\xff\xd9"
        frames.append(jpeg)
    return frames


class VirtualCamera:
    """Stands in for go2rtc and the webcam: serves a scenario on the same addresses the Pi uses, following the shared clock."""

    def __init__(self, scenario, device, clock):
        """Renders the scenario at this device's size and frame rate and starts serving it on a free local port."""
        cam, fps = scenario["camera"], device["fps"]
        frames = [] if cam["fault"] == "unplugged" else render_frames(scenario, device["width"], device["height"], fps)
        gaps = [(e["start"], e["end"]) for e in cam["events"] if e["type"] == "unplug"]
        seconds = scenario["seconds"]

        def plugged(t):
            """Says whether the camera is plugged in at scenario time t."""
            return bool(frames) and t < seconds and not any(a <= t < b for a, b in gaps)

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                """Answers like go2rtc: the stream list, one snapshot, or a live MJPEG stream."""
                if self.path.startswith("/api/streams"):
                    return self.reply(200, "application/json", json.dumps({"home_cam": {"producers": [{"url": "/dev/homecam"}]}}).encode())
                if not plugged(clock.now()):
                    return self.reply(500, "text/plain", b"exec: /dev/homecam: No such file or directory")
                if self.path.startswith("/api/frame.jpeg"):
                    return self.reply(200, "image/jpeg", frames[min(int(clock.now() * fps), len(frames) - 1)])
                self.send_response(200)
                self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
                self.end_headers()
                last = -1
                try:
                    while plugged(clock.now()):
                        i = min(int(clock.now() * fps), len(frames) - 1)
                        if i != last:
                            jpeg, last = frames[i], i
                            self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n" % len(jpeg))
                            self.wfile.write(jpeg + b"\r\n")
                        time.sleep(max(0.002, clock.wall((i + 1) / fps) - time.time()))
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def reply(self, code, kind, body):
                """Sends one short response."""
                self.send_response(code)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                """Keeps the test output free of web server logs."""
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        """Stops the server."""
        self.server.shutdown()
        self.server.server_close()


class VirtualMic:
    """Stands in for a USB microphone: puts a fake `arecord` first on PATH that plays the scenario on the shared clock."""

    def __init__(self, scenario, device, clips, clock):
        """Renders the scenario audio for this device and writes the fake arecord next to it in a temporary folder."""
        self.folder, self.clock = Path(tempfile.mkdtemp(prefix="hil_mic_")), clock
        (self.folder / "mic.raw").write_bytes(render_audio(scenario, clips, gain_db=device.get("gain_db", 0)).tobytes())
        shim = self.folder / "arecord"
        shim.write_text(ARECORD.replace("PYTHON", sys.executable), encoding="utf-8", newline="\n")
        shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
        self.card = f"card 1: {device['card']} [{device['name']}], device 0: USB Audio [USB Audio]"
        self.fault = scenario["mic"]["fault"] or ""

    def env(self, start=None):
        """Returns the environment that makes arecord find this virtual mic, recording from scenario time `start` if given."""
        return dict(os.environ, PATH=f"{self.folder}{os.pathsep}{os.environ['PATH']}", HIL_SPEED=str(self.clock.speed),
                    HIL_T0=str(self.clock.t0), HIL_MIC_RAW=str(self.folder / "mic.raw"), HIL_MIC_CARD=self.card,
                    HIL_MIC_FAULT=self.fault, HIL_FROM="" if start is None else str(start))

    def close(self):
        """Removes the temporary folder."""
        shutil.rmtree(self.folder, ignore_errors=True)
