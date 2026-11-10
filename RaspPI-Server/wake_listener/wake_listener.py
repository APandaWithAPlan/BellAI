import argparse
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from collections import deque
from pathlib import Path

import numpy as np
import requests

HERE = Path(__file__).resolve().parent
REPO_MODELS = HERE.parent.parent / "Wake Word" / "models"
RATE = 16000
CHUNK = 1280

parser = argparse.ArgumentParser(description="BellAi wake word listener")
parser.add_argument("--model", default=str(HERE / "BellAi.onnx") if (HERE / "BellAi.onnx").exists() else str(REPO_MODELS / "BellAi.onnx"),
                    help="wake word model; melspectrogram.onnx and embedding_model.onnx must be in the same folder")
parser.add_argument("--mic", default="Razer", help="part of the microphone's name (see --list-mics)")
parser.add_argument("--list-mics", action="store_true", help="list microphones and exit")
parser.add_argument("--threshold", type=float, default=0.5, help="0-1; raise it if BellAi wakes up by mistake")
parser.add_argument("--gain", type=float, default=5.0, help="boosts the mic in software (default 5, tuned for the Razer Seiren Mini across a room)")
parser.add_argument("--api", default="http://127.0.0.1:8000", help="the Pi API (api.py)")
parser.add_argument("--server", default="", help="AI server to check when woken, e.g. http://<ai-server>:11434")
parser.add_argument("--tts", default="", help="optional voice API to speak replies, e.g. http://<ai-server>:9880")
parser.add_argument("--wake-sound", default=str(HERE / "wake.wav") if (HERE / "wake.wav").exists() else "",
                    help="chime .wav to play when woken (default: wake.wav next to this script, else a built-in chime)")
parser.add_argument("--dropped-sound", default=str(HERE / "connection_dropped.wav"),
                    help=".wav spoken on connection dropped (recorded in the BellAi voice; skipped if missing)")
parser.add_argument("--max-seconds", type=float, default=8.0, help="longest command to record before cutting off")
parser.add_argument("--wait-seconds", type=float, default=4.0, help="how long to wait for a command after the chime")
parser.add_argument("--timeout", type=float, default=30.0, help="seconds to wait for a reply before saying connection dropped")
parser.add_argument("--wav", default="", help="read audio from this file instead of the mic (for testing)")
parser.add_argument("--scores", action="store_true", help="test mode: only print what the model hears, send nothing")
args = parser.parse_args()


def log(msg):
    """Prints a message with the time in front."""
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def list_mics():
    """Returns the recording devices from `arecord -l` as (card id, device number, description)."""
    out = subprocess.run(["arecord", "-l"], capture_output=True, text=True).stdout
    found = re.findall(r"^card \d+: (\S+) \[(.*?)\], device (\d+): (.*?)$", out, flags=re.M)
    return [(card, dev, f"{name} - {desc}") for card, name, dev, desc in found]


def find_mic(name):
    """Finds the microphone whose name contains `name` and returns its arecord device and description."""
    for card, dev, desc in list_mics():
        if name.lower() in f"{card} {desc}".lower():
            return f"plughw:CARD={card},DEV={dev}", desc
    names = "\n  ".join(d for _, _, d in list_mics()) or "(none)"
    sys.exit(f"No microphone with '{name}' in its name. Microphones found:\n  {names}\nUse --mic with part of one.")


class Mic:
    """Reads the microphone with arecord as 16 kHz mono and hands out 80 ms chunks, without needing PulseAudio."""

    def __init__(self, name):
        """Starts arecord on the chosen mic and a background thread that reads from it."""
        device, desc = find_mic(name)
        self.proc = subprocess.Popen(["arecord", "-q", "-D", device, "-f", "S16_LE", "-r", str(RATE), "-c", "1",
                                      "-t", "raw"], stdout=subprocess.PIPE)
        self.q = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()
        log(f"Listening on {desc}")

    def _reader(self):
        """Keeps reading the mic into a queue so audio never backs up while BellAi is busy."""
        while True:
            data = self.proc.stdout.read(CHUNK * 2)
            if len(data) < CHUNK * 2:
                self.q.put(None)
                return
            self.q.put(boost(np.frombuffer(data, dtype=np.int16)))

    def read(self):
        """Returns the next 80 ms of audio, or stops the program if the mic was unplugged."""
        chunk = self.q.get()
        if chunk is None:
            sys.exit("The microphone stopped (unplugged, or in use by another program).")
        return chunk

    def flush(self):
        """Drops audio that piled up while BellAi was busy, so old sound can't wake it."""
        while not self.q.empty():
            if self.q.get_nowait() is None:
                self.q.put(None)
                return


class WavFile:
    """Feeds a recording through the listener instead of the mic, for testing."""

    def __init__(self, path):
        """Loads the recording as 16 kHz mono."""
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ar", str(RATE), "-ac", "1",
                              "-f", "s16le", "-"], check=True, capture_output=True).stdout
        self.audio, self.pos = np.frombuffer(raw, dtype=np.int16), 0
        log(f"Reading {path} ({len(self.audio) / RATE:.1f} s)")

    def read(self):
        """Returns the next 80 ms of the recording, or None at the end."""
        if self.pos + CHUNK > len(self.audio):
            return None
        self.pos += CHUNK
        return boost(self.audio[self.pos - CHUNK:self.pos])

    def flush(self):
        """Does nothing; a recording has no backed-up audio to drop."""
        pass


def boost(chunk):
    """Makes the audio louder by --gain, without letting it clip past the loudest possible value."""
    if args.gain == 1.0:
        return chunk
    return np.clip(chunk.astype(np.float32) * args.gain, -32768, 32767).astype(np.int16)


def level_db(chunk):
    """Returns how loud a chunk of audio is, in decibels."""
    return 20 * np.log10(np.sqrt(np.mean(chunk.astype(np.float32) ** 2)) + 1)


player = None


def play(path, wait=True):
    """Plays a .wav file through the speaker, if the file exists; with wait=False it plays in the background
    while listening continues."""
    global player
    if not (path and Path(path).exists() and shutil.which("aplay")):
        return
    if wait:
        subprocess.run(["aplay", "-q", str(path)], check=False)
    elif player is None or player.poll() is not None:
        player = subprocess.Popen(["aplay", "-q", str(path)])


def make_chime(path):
    """Writes a short two-note chime, used when there is no wake.wav."""
    import wave
    t = np.arange(int(0.12 * RATE)) / RATE
    notes = [np.sin(2 * np.pi * f * t) * np.hanning(len(t)) for f in (880, 1320)]
    tone = (np.concatenate(notes) * 0.3 * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
        w.writeframes(tone.tobytes())


def server_up(url):
    """Checks whether the AI server answers; only called after the wake word is heard."""
    try:
        return requests.get(url, timeout=3).status_code < 500
    except requests.RequestException:
        return False


def connection_dropped(reason):
    """Prints "connection dropped" with the reason and plays connection_dropped.wav."""
    log(f"connection dropped ({reason})")
    play(args.dropped_sound, wait=False)


def record_command(source, noise_db):
    """Records the command until 1 s of quiet after speech, cutting off at --max-seconds; returns None if nobody
    spoke within --wait-seconds."""
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
        elif seconds >= args.wait_seconds:
            break
    else:
        if heard:
            log(f"Cut off at {args.max_seconds:.0f} s")
    return np.concatenate(frames) if heard else None


def to_webm(audio):
    """Converts the recorded audio to .webm, the format api.py accepts."""
    return subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                           "-c:a", "libopus", "-b:a", "32k", "-f", "webm", "-"],
                          input=audio.tobytes(), check=True, capture_output=True).stdout


def speak(text):
    """Sends the reply to the voice API and plays the audio it returns."""
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
    """Sends the command to api.py (POST /audio) for Whisper and the AI server, then prints the reply."""
    try:
        r = requests.post(f"{args.api}/audio", files={"audio_file": ("command.webm", to_webm(audio), "audio/webm")},
                          timeout=args.timeout)
    except requests.ConnectionError:
        return connection_dropped(f"can't reach the Pi API at {args.api}. Is api.py running?")
    except requests.Timeout:
        return connection_dropped(f"no reply after {args.timeout:.0f} s")
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


def main():
    """Loads the model, listens for "BellAi", and handles each command until stopped with Ctrl+C."""
    if args.list_mics:
        mics = list_mics()
        for card, dev, desc in mics:
            print(f"{card}: {desc}")
        if not mics:
            print("No microphones found. Check `arecord -l`; this user may need: sudo usermod -aG audio $USER")
        return

    from openwakeword.model import Model
    model_path = Path(args.model)
    folder = model_path.parent
    for needed in (model_path, folder / "melspectrogram.onnx", folder / "embedding_model.onnx"):
        if not needed.exists():
            sys.exit(f"Missing {needed}. Copy the files from the Wake Word/models folder (python train.py export).")
    model = Model(wakeword_models=[str(model_path)], inference_framework="onnx",
                  melspec_model_path=str(folder / "melspectrogram.onnx"),
                  embedding_model_path=str(folder / "embedding_model.onnx"))
    if not args.wake_sound:
        args.wake_sound = str(Path(tempfile.gettempdir()) / "bellai_chime.wav")
        make_chime(args.wake_sound)

    source = WavFile(args.wav) if args.wav else Mic(args.mic)
    recent = deque(maxlen=int(3 * RATE / CHUNK))
    log(f"Say \"BellAi\" (threshold {args.threshold})")
    while True:
        chunk = source.read()
        if chunk is None:
            break
        recent.append(level_db(chunk))
        score = max(model.predict(chunk).values())
        if args.scores:
            if score >= 0.05:
                seconds = f"{source.pos / RATE:6.1f}s " if args.wav else time.strftime("%H:%M:%S ")
                mark = "  <-- wakes" if score >= args.threshold else ""
                print(f"{seconds}{score:.2f} {'#' * int(score * 40)}{mark}", flush=True)
            continue
        if score < args.threshold:
            continue
        log(f"Heard BellAi ({score:.2f})")
        model.reset()
        play(args.wake_sound)
        source.flush()
        if args.server and not server_up(args.server):
            connection_dropped(f"the AI server at {args.server} isn't answering")
            continue
        audio = record_command(source, float(np.percentile(recent, 20)))
        if audio is None:
            log(f"No command heard within {args.wait_seconds:.0f} s")
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
