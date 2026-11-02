#!/usr/bin/env python3
"""Motion detection and clip recording for the BellAi home camera.

Reads the MJPEG stream from go2rtc and keeps the last few seconds of frames in
memory. Every few frames it checks for motion by comparing the image against a
slowly updating background. When motion starts, it encodes the buffered
pre-roll plus the live frames into an H.264 MP4 until motion has stopped for a
short post-roll, so clips include the moment the movement began.

Every event is logged to the systemd journal and added to events.json in the
recordings folder. The app reads events.json to list events and plays the
MP4 files directly.

All settings can be overridden with environment variables (see CONFIG below).
"""

import json
import logging
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.request
from collections import deque
from datetime import datetime, timedelta
from pathlib import Path

import cv2
import numpy as np


# ---------------------------------------------------------------- CONFIG ----

def env(name, default, cast=str):
    value = os.environ.get(name)
    return cast(value) if value not in (None, "") else default


GO2RTC_URL = env("GO2RTC_URL", "http://127.0.0.1:1984")
DETECT_SRC = env("DETECT_SRC", "home_cam")         # MJPEG stream used for detection and recording
RECORD_DIR = Path(env("RECORD_DIR", "/var/lib/homecam/recordings"))

DETECT_FPS = env("DETECT_FPS", 5.0, float)         # frames analysed per second
MOTION_PCT = env("MOTION_PCT", 2.0, float)         # % of the image that must change to count as motion
TRIGGER_FRAMES = env("TRIGGER_FRAMES", 2, int)     # consecutive motion frames needed to start recording
WARMUP_FRAMES = env("WARMUP_FRAMES", 10, int)      # frames ignored after (re)connecting while exposure settles
PRE_ROLL_S = env("PRE_ROLL_S", 3.0, float)         # seconds kept from before motion was detected
POST_ROLL_S = env("POST_ROLL_S", 8, int)           # keep recording this long after motion stops
MAX_CLIP_S = env("MAX_CLIP_S", 60, int)            # split long events into clips of this length
RETENTION_DAYS = env("RETENTION_DAYS", 3, int)     # delete recordings older than this
MIN_FREE_GB = env("MIN_FREE_GB", 2.0, float)       # delete oldest days if free space drops below this
MAX_STORAGE_GB = env("MAX_STORAGE_GB", 5.0, float) # cap on the recordings folder; oldest clips go first
ENCODE_PRESET = env("ENCODE_PRESET", "superfast")  # x264 speed/size trade-off
ENCODE_CRF = env("ENCODE_CRF", 26, int)            # x264 quality; higher = smaller files

EVENTS_FILE = RECORD_DIR / "events.json"

log = logging.getLogger("homecam-motion")


# ------------------------------------------------------------ STREAMING ----

def mjpeg_frames(url):
    """Yield raw JPEG images from go2rtc's MJPEG HTTP stream."""
    with urllib.request.urlopen(url, timeout=10) as resp:
        read = getattr(resp, "read1", resp.read)
        buf = b""
        while True:
            chunk = read(65536)
            if not chunk:
                raise ConnectionError("stream ended")
            buf += chunk
            while True:
                start = buf.find(b"\xff\xd8")
                if start < 0:
                    buf = buf[-1:]          # keep a possible half marker
                    break
                end = buf.find(b"\xff\xd9", start + 2)
                if end < 0:
                    buf = buf[start:]
                    break
                yield buf[start:end + 2]
                buf = buf[end + 2:]


# ------------------------------------------------------------ DETECTION ----

class MotionDetector:
    """Frame differencing against a running-average background."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.background = None
        self.frames_seen = 0

    def score(self, jpeg):
        """Return the % of the image that changed, or None while warming up."""
        # Decode at 1/4 size in grayscale: fast and plenty for motion.
        img = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_REDUCED_GRAYSCALE_4)
        if img is None:
            return None
        gray = cv2.GaussianBlur(img, (11, 11), 0)

        if self.background is None:
            self.background = gray.astype("float32")
        diff = cv2.absdiff(gray, cv2.convertScaleAbs(self.background))
        cv2.accumulateWeighted(gray, self.background, 0.05)

        self.frames_seen += 1
        if self.frames_seen <= WARMUP_FRAMES:
            return None

        _, mask = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
        mask = cv2.dilate(mask, None, iterations=2)
        return 100.0 * cv2.countNonZero(mask) / mask.size


# ------------------------------------------------------------ RECORDING ----

class Recorder:
    """Encodes buffered and live JPEG frames into one MP4 per motion event.

    Frames go through a queue to a writer thread, so a slow encoder never
    stalls motion detection; if the queue fills, frames are dropped instead.
    """

    def __init__(self):
        self.proc = None

    @property
    def active(self):
        return self.proc is not None

    def failed(self):
        return self.proc.poll() is not None or not self.thread.is_alive()

    def start(self, preroll, fps, trigger_jpeg):
        now = datetime.now().astimezone()
        day_dir = RECORD_DIR / now.strftime("%Y-%m-%d")
        day_dir.mkdir(parents=True, exist_ok=True)

        self.event_id = now.strftime("%Y%m%d-%H%M%S")
        n = 2
        while (day_dir / f"{self.event_id}.jpg").exists():   # two events in the same second
            self.event_id = f"{now.strftime('%Y%m%d-%H%M%S')}-{n}"
            n += 1
        self.video = day_dir / f"{self.event_id}.mp4"
        self.part = day_dir / f"{self.event_id}.mp4.part"
        self.thumb = day_dir / f"{self.event_id}.jpg"
        self.started_at = now - timedelta(seconds=len(preroll) / fps)
        self.started_mono = time.monotonic()
        self.peak = 0.0
        self.dropped = 0

        self.thumb.write_bytes(trigger_jpeg)
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "image2pipe", "-c:v", "mjpeg", "-framerate", f"{fps:.2f}", "-i", "pipe:0",
            "-c:v", "libx264", "-preset", ENCODE_PRESET, "-crf", str(ENCODE_CRF),
            "-pix_fmt", "yuv420p",              # plays on iPhone/AVPlayer
            "-movflags", "+faststart",          # lets the app start playing before the whole file loads
            "-f", "mp4", str(self.part),
        ]
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        self.frames = queue.Queue(maxsize=max(30, int(fps * 10)))
        self.thread = threading.Thread(target=self._write_frames, daemon=True)
        self.thread.start()
        for jpeg in preroll:
            self.add(jpeg)
        log.info("Motion started, recording %s (%.1fs pre-roll at %.1f fps)",
                 self.event_id, len(preroll) / fps, fps)

    def _write_frames(self):
        stdin = self.proc.stdin
        while True:
            jpeg = self.frames.get()
            if jpeg is None:
                break
            try:
                stdin.write(jpeg)
            except (BrokenPipeError, OSError):
                break
        try:
            stdin.close()                       # end of input: ffmpeg finishes the MP4
        except OSError:
            pass

    def add(self, jpeg):
        try:
            self.frames.put_nowait(jpeg)
        except queue.Full:
            self.dropped += 1

    def stop(self):
        """Finish the clip and return the event record."""
        if self.thread.is_alive():
            self.frames.put(None)
            self.thread.join(timeout=120)
        try:
            self.proc.wait(timeout=120)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        self.proc = None
        if self.dropped:
            log.warning("Encoder fell behind on %s and dropped %d frames", self.event_id, self.dropped)

        ended = datetime.now().astimezone()
        saved = self.part.exists() and self.part.stat().st_size > 10_000
        if saved:
            self.part.replace(self.video)
        else:
            self.part.unlink(missing_ok=True)
            log.warning("Recording for %s failed or was empty; keeping the snapshot only", self.event_id)

        return {
            "id": self.event_id,
            "start": self.started_at.isoformat(timespec="seconds"),
            "end": ended.isoformat(timespec="seconds"),
            "duration_s": round((ended - self.started_at).total_seconds()),
            "peak_motion_pct": round(self.peak, 1),
            "video": self.video.relative_to(RECORD_DIR).as_posix() if saved else None,
            "thumbnail": self.thumb.relative_to(RECORD_DIR).as_posix(),
        }


# --------------------------------------------------------------- EVENTS ----

def load_events():
    try:
        return json.loads(EVENTS_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def save_events(events):
    tmp = EVENTS_FILE.with_name(EVENTS_FILE.name + ".tmp")
    tmp.write_text(json.dumps(events, indent=1))
    tmp.replace(EVENTS_FILE)                     # atomic, so the app never reads half a file


def add_event(event):
    events = load_events()
    events.insert(0, event)                      # newest first
    save_events(events)
    log.info("Motion event %s: %ss, peak %.1f%%, video=%s",
             event["id"], event["duration_s"], event["peak_motion_pct"], event["video"])


def cleanup():
    """Apply the retention period, free-space limit and storage cap, then prune the index."""
    day_dirs = lambda: sorted(p for p in RECORD_DIR.iterdir() if p.is_dir() and len(p.name) == 10)
    cutoff = (datetime.now() - timedelta(days=RETENTION_DAYS)).strftime("%Y-%m-%d")
    today = datetime.now().strftime("%Y-%m-%d")

    for d in day_dirs():
        if d.name < cutoff:
            shutil.rmtree(d, ignore_errors=True)
            log.info("Deleted recordings from %s (older than %d days)", d.name, RETENTION_DAYS)

    for d in day_dirs():
        if shutil.disk_usage(RECORD_DIR).free >= MIN_FREE_GB * 1e9 or d.name == today:
            break
        shutil.rmtree(d, ignore_errors=True)
        log.warning("Low disk space: deleted recordings from %s", d.name)

    # Storage cap: delete the oldest clips (and their thumbnails) until under the limit
    files = sorted(f for f in RECORD_DIR.glob("*/*") if f.is_file())
    total = sum(f.stat().st_size for f in files)
    cap = MAX_STORAGE_GB * 1e9
    removed = 0
    for clip in [f for f in files if f.suffix == ".mp4"]:
        if total <= cap:
            break
        for f in (clip, clip.with_suffix(".jpg")):
            if f.exists():
                total -= f.stat().st_size
                f.unlink()
        removed += 1
    if removed:
        log.info("Storage cap %.1f GB reached: deleted %d oldest clips", MAX_STORAGE_GB, removed)
    for d in day_dirs():
        if not any(d.iterdir()):
            d.rmdir()

    events = load_events()
    kept = [e for e in events if (RECORD_DIR / e["thumbnail"]).exists()]
    if len(kept) != len(events):
        save_events(kept)


# ----------------------------------------------------------------- MAIN ----

def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stdout)
    RECORD_DIR.mkdir(parents=True, exist_ok=True)

    stopping = False

    def request_stop(*_):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    detector = MotionDetector()
    recorder = Recorder()
    stream_url = f"{GO2RTC_URL}/api/stream.mjpeg?src={DETECT_SRC}"
    interval = 1.0 / DETECT_FPS
    preroll = deque()                  # (time, jpeg) for the last PRE_ROLL_S seconds
    arrivals = deque(maxlen=60)        # frame arrival times, to measure the camera's real fps
    last_check = last_motion = last_cleanup = 0.0
    retry_after = 0.0                  # pause before recording again after a failed recording
    streak = 0

    def camera_fps():
        if len(arrivals) < 10 or arrivals[-1] <= arrivals[0]:
            return 15.0
        return min(30.0, max(1.0, (len(arrivals) - 1) / (arrivals[-1] - arrivals[0])))

    def finish():
        nonlocal retry_after
        event = recorder.stop()
        add_event(event)
        cleanup()
        if event["video"] is None:
            retry_after = time.monotonic() + 30
            log.warning("Is ffmpeg installed and working? Waiting 30s before recording again")

    log.info("Watching %s (motion threshold %.1f%%, %.0fs pre-roll), saving to %s",
             stream_url, MOTION_PCT, PRE_ROLL_S, RECORD_DIR)
    cleanup()

    while not stopping:
        try:
            for jpeg in mjpeg_frames(stream_url):
                if stopping:
                    break
                now = time.monotonic()
                arrivals.append(now)
                preroll.append((now, jpeg))
                while now - preroll[0][0] > PRE_ROLL_S:
                    preroll.popleft()
                if recorder.active:
                    recorder.add(jpeg)

                if now - last_check < interval:
                    continue
                last_check = now

                pct = detector.score(jpeg)
                if pct is None:
                    continue
                moving = pct >= MOTION_PCT
                streak = streak + 1 if moving else 0

                if recorder.active:
                    recorder.peak = max(recorder.peak, pct)
                    if moving:
                        last_motion = now
                    if (now - last_motion > POST_ROLL_S
                            or now - recorder.started_mono > MAX_CLIP_S
                            or recorder.failed()):
                        finish()
                elif streak >= TRIGGER_FRAMES and now >= retry_after:
                    recorder.start([j for _, j in preroll], camera_fps(), jpeg)
                    recorder.peak = pct
                    last_motion = now

                if now - last_cleanup > 3600:
                    cleanup()
                    last_cleanup = now
        except Exception as exc:  # camera unplugged, go2rtc restarting, network hiccup
            if stopping:
                break
            log.warning("Camera stream unavailable (%s); retrying in 5s", exc)
            if recorder.active:
                finish()
            detector.reset()
            preroll.clear()
            arrivals.clear()
            streak = 0
            time.sleep(5)

    if recorder.active:
        finish()
    log.info("Stopped")


if __name__ == "__main__":
    main()
