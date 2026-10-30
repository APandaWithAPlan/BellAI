"""BellAi wake word listener for the Raspberry Pi.

Listens on the microphone for "BellAi". When it hears it, it plays a chime, records the command until you stop
talking, and sends it to the Pi API (api.py, POST /audio) as .webm. api.py transcribes it with whisper.cpp and
asks the AI server, and the reply is printed (and spoken, if --tts is set).

If someone says "BellAi" while the AI server can't be reached, it says "connection dropped" instead of
recording. Nothing plays while nobody is asking.

    python wake_listener.py --list-mics
    python wake_listener.py --server http://<ai-server>:11434
    python wake_listener.py --wav test.wav       # test with a recording instead of the mic
"""
import argparse
import queue
import shutil
import subprocess
import sys
import tempfile
import time
from collections import deque
from pathlib import Path

import numpy as np
import requests
import scipy.signal

HERE = Path(__file__).resolve().parent
REPO_MODELS = HERE.parent.parent / "Wake Word" / "models"
RATE = 16000
CHUNK = 1280  # 80 ms at 16 kHz, the frame size openWakeWord expects

parser = argparse.ArgumentParser(description="BellAi wake word listener")
parser.add_argument("--model", default=str(REPO_MODELS / "BellAi.onnx"),
                    help="wake word model; melspectrogram.onnx and embedding_model.onnx must be in the same folder")
parser.add_argument("--mic", default="Razer", help="part of the microphone's name (see --list-mics)")
parser.add_argument("--list-mics", action="store_true", help="list microphones and exit")
parser.add_argument("--threshold", type=float, default=0.5, help="0-1; raise it if BellAi wakes up by mistake")
parser.add_argument("--api", default="http://127.0.0.1:8000", help="the Pi API (api.py)")
parser.add_argument("--server", default="", help="AI server to check when woken, e.g. http://<ai-server>:11434")
parser.add_argument("--tts", default="", help="optional voice API to speak replies, e.g. http://<ai-server>:9880")
parser.add_argument("--wake-sound", default="", help="chime .wav to play when woken (default: a built-in chime)")
parser.add_argument("--dropped-sound", default=str(HERE / "connection_dropped.wav"),
                    help=".wav spoken on connection dropped (recorded in the BellAi voice; skipped if missing)")
parser.add_argument("--max-seconds", type=float, default=8.0, help="longest command to record")
parser.add_argument("--wav", default="", help="read audio from this file instead of the mic (for testing)")
args = parser.parse_args()


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


# ---------- audio in

def find_mic(sd, name):
    inputs = [(i, d) for i, d in enumerate(sd.query_devices()) if d["max_input_channels"] > 0]
    for i, d in inputs:
        if name.lower() in d["name"].lower():
            return i
    names = "\n  ".join(d["name"] for _, d in inputs) or "(none)"
    sys.exit(f"No microphone with '{name}' in its name. Microphones found:\n  {names}\nUse --mic with part of one.")


class Mic:
    """Reads the microphone and hands out 80 ms chunks of 16 kHz mono int16."""

    def __init__(self, name):
        import sounddevice as sd
        device = find_mic(sd, name)
        self.q = queue.Queue()
        self.buf = np.zeros(0, dtype=np.int16)
        self.rate = RATE
        try:  # ask for 16 kHz; many USB mics only do 48 kHz, so fall back to their own rate
            self.stream = self._open(sd, device, RATE)
        except Exception:
            self.rate = int(sd.query_devices(device)["default_samplerate"])
            self.stream = self._open(sd, device, self.rate)
        self.step = self.rate // RATE if self.rate % RATE == 0 else 0
        if self.rate != RATE:
            # anti-alias filter that keeps its state between blocks, so there are no clicks at block edges
            self.sos = scipy.signal.butter(8, 7000, fs=self.rate, output="sos")
            self.zi = scipy.signal.sosfilt_zi(self.sos) * 0
            self.offset = 0
        self.stream.start()
        log(f"Listening on {sd.query_devices(device)['name']} ({self.rate} Hz)")

    def _open(self, sd, device, rate):
        return sd.InputStream(device=device, channels=1, samplerate=rate, dtype="int16",
                              blocksize=int(rate * 0.08), callback=lambda d, f, t, s: self.q.put(d[:, 0].copy()))

    def _to_16k(self, block):
        if self.rate == RATE:
            return block
        y, self.zi = scipy.signal.sosfilt(self.sos, block.astype(np.float32), zi=self.zi)
        if self.step:  # e.g. 48 kHz -> every 3rd sample
            out = y[self.offset::self.step]
            self.offset = (self.offset - len(y)) % self.step
        else:  # odd rates such as 44.1 kHz
            out = scipy.signal.resample_poly(y, RATE, self.rate)
        return np.clip(out, -32768, 32767).astype(np.int16)

    def read(self):
        while len(self.buf) < CHUNK:
            self.buf = np.concatenate([self.buf, self._to_16k(self.q.get())])
        chunk, self.buf = self.buf[:CHUNK], self.buf[CHUNK:]
        return chunk

    def flush(self):
        """Drops audio that piled up while BellAi was busy, so old sound can't wake it."""
        while not self.q.empty():
            self.q.get_nowait()
        self.buf = np.zeros(0, dtype=np.int16)


class WavFile:
    """Plays a recording through the listener instead of the mic."""

    def __init__(self, path):
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ar", str(RATE), "-ac", "1",
                              "-f", "s16le", "-"], check=True, capture_output=True).stdout
        self.audio, self.pos = np.frombuffer(raw, dtype=np.int16), 0
        log(f"Reading {path} ({len(self.audio) / RATE:.1f} s)")

    def read(self):
        if self.pos + CHUNK > len(self.audio):
            return None
        self.pos += CHUNK
        return self.audio[self.pos - CHUNK:self.pos]

    def flush(self):
        pass


def level_db(chunk):
    return 20 * np.log10(np.sqrt(np.mean(chunk.astype(np.float32) ** 2)) + 1)


# ---------- sound out

def play(path):
    if path and Path(path).exists() and shutil.which("aplay"):
        subprocess.run(["aplay", "-q", str(path)], check=False)


def make_chime(path):
    """A short two-note chime, used when no --wake-sound is given."""
    import wave
    t = np.arange(int(0.12 * RATE)) / RATE
    notes = [np.sin(2 * np.pi * f * t) * np.hanning(len(t)) for f in (880, 1320)]
    tone = (np.concatenate(notes) * 0.3 * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
        w.writeframes(tone.tobytes())


# ---------- server status

def server_up(url):
    """Quick check, made only when someone says BellAi, so nothing plays while nobody is asking."""
    try:
        return requests.get(url, timeout=3).status_code < 500
    except requests.RequestException:
        return False


def connection_dropped(reason):
    log(f"connection dropped ({reason})")
    play(args.dropped_sound)


# ---------- one command

def record_command(source, noise_db):
    """Records until there's 1 s of quiet after speech. Returns None if nobody spoke within 4 s."""
    speech_db = max(noise_db + 10, 35)
    frames, heard, quiet, seconds = [], False, 0.0, 0.0
    while seconds < args.max_seconds:
        chunk = source.read()
        if chunk is None:
            break
        frames.append(chunk)
        seconds += CHUNK / RATE
        if level_db(chunk) > speech_db:
            heard, quiet = True, 0.0
        elif heard:
            quiet += CHUNK / RATE
            if quiet >= 1.0:
                break
        elif seconds >= 4.0:
            break
    return np.concatenate(frames) if heard else None


def to_webm(audio):
    return subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                           "-c:a", "libopus", "-b:a", "32k", "-f", "webm", "-"],
                          input=audio.tobytes(), check=True, capture_output=True).stdout


def speak(text):
    try:
        r = requests.post(f"{args.tts}/tts", json={"text": text, "stream": False}, timeout=60)
        r.raise_for_status()
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(r.content)
        play(f.name)
        Path(f.name).unlink(missing_ok=True)
    except requests.RequestException as e:
        log(f"couldn't speak the reply ({e})")


def ask(audio):
    try:
        r = requests.post(f"{args.api}/audio", files={"audio_file": ("command.webm", to_webm(audio), "audio/webm")},
                          timeout=180)
    except requests.ConnectionError:
        return connection_dropped(f"can't reach the Pi API at {args.api}. Is api.py running?")
    except requests.Timeout:
        return connection_dropped("the request timed out")
    if r.status_code in (502, 503, 504):
        return connection_dropped(r.json().get("detail", "the AI server is offline") if r.headers.get(
            "content-type", "").startswith("application/json") else "the AI server is offline")
    if r.status_code == 422:
        return log("Didn't catch that. Try again.")
    if not r.ok:
        return log(f"Error {r.status_code}: {r.text[:200]}")
    reply = r.json().get("response", "")
    log(f"BellAi: {reply}")
    if args.tts and reply:
        speak(reply)


# ---------- main

def main():
    if args.list_mics:
        import sounddevice as sd
        for i, d in enumerate(sd.query_devices()):
            if d["max_input_channels"] > 0:
                print(f"{i}: {d['name']} ({int(d['default_samplerate'])} Hz)")
        return

    from openwakeword.model import Model
    model_path = Path(args.model)
    folder = model_path.parent
    for needed in (model_path, folder / "melspectrogram.onnx", folder / "embedding_model.onnx"):
        if not needed.exists():
            sys.exit(f"Missing {needed}. Copy the files from the Wake Word/models folder (bash train.sh export).")
    model = Model(wakeword_models=[str(model_path)], inference_framework="onnx",
                  melspec_model_path=str(folder / "melspectrogram.onnx"),
                  embedding_model_path=str(folder / "embedding_model.onnx"))
    if not args.wake_sound:
        args.wake_sound = str(Path(tempfile.gettempdir()) / "bellai_chime.wav")
        make_chime(args.wake_sound)

    source = WavFile(args.wav) if args.wav else Mic(args.mic)
    recent = deque(maxlen=int(3 * RATE / CHUNK))  # last 3 s of levels, to know how loud the room is
    log(f"Say \"BellAi\" (threshold {args.threshold})")
    while True:
        chunk = source.read()
        if chunk is None:
            break
        recent.append(level_db(chunk))
        score = max(model.predict(chunk).values())
        if score < args.threshold:
            continue
        log(f"Heard BellAi ({score:.2f})")
        if args.server and not server_up(args.server):
            connection_dropped(f"the AI server at {args.server} isn't answering")
        else:
            play(args.wake_sound)
            source.flush()  # don't record the chime
            audio = record_command(source, float(np.percentile(recent, 20)))
            if audio is None:
                log("No command heard")
            else:
                log(f"Sending {len(audio) / RATE:.1f} s of audio")
                ask(audio)
        model.reset()
        source.flush()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
