"""
bellai_voice_server.py - the BellAi voice as a small web API, for the app, the website and the Pi.

Send it text, get BellAi's voice back as a WAV stream that starts playing within about a second.
It uses a voice pack exported from BellAi Studio (gpt.ckpt, sovits.pth, reference.wav, voice.json)
and needs GPT-SoVITS installed on the same machine, plus an NVIDIA GPU for real-time speed.

Run it with GPT-SoVITS's Python, from the unzipped voice pack folder:

    Windows (GPT-SoVITS package):
        "C:\\path\\to\\GPT-SoVITS-v3lora-20250228\\runtime\\python.exe" bellai_voice_server.py --gpt-sovits "C:\\path\\to\\GPT-SoVITS-v3lora-20250228"
    Linux (GPT-SoVITS installed from GitHub):
        python bellai_voice_server.py --gpt-sovits ~/GPT-SoVITS

Options
    --pack PATH        voice pack folder or .zip (default: the folder this file is in)
    --host 0.0.0.0     let other devices on the network reach it (default: this computer only)
    --port 9880
    --key SECRET       require this key (header "X-API-Key: SECRET" or ?key=SECRET). Also read from
                       the BELLAI_KEY environment variable. Use one whenever --host is not 127.0.0.1.

API
    GET  /health                       {"ready": true, "voice": "...", "sample_rate": 32000}
    POST /tts   {"text": "Hello!"}     streams audio/wav as it is generated
    GET  /tts?text=Hello!              same thing, handy for testing in a browser
         optional fields: "speed" (0.6-1.6), "stream" (false = wait and return one complete WAV)
"""

import argparse
import json
import os
import re
import struct
import sys
import threading
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

parser = argparse.ArgumentParser(description="BellAi voice API")
parser.add_argument("--pack", default=None, help="voice pack folder or .zip")
parser.add_argument("--gpt-sovits", default=None, help="GPT-SoVITS folder")
parser.add_argument("--host", default="127.0.0.1")
parser.add_argument("--port", type=int, default=9880)
parser.add_argument("--key", default=os.environ.get("BELLAI_KEY", ""))
args = parser.parse_args()


def find_pack():
    path = (Path(args.pack) if args.pack else HERE).resolve()
    if path.suffix.lower() == ".zip":
        target = path.with_suffix("")
        if not (target / "voice.json").exists():
            print(f"Unzipping {path.name}...")
            with zipfile.ZipFile(path) as z:
                z.extractall(target)
        path = target
    if not (path / "voice.json").exists():
        sys.exit(f"No voice.json in {path}. Point --pack at an unzipped BellAi voice pack.")
    return path


def find_gpt_sovits():
    candidates = [args.gpt_sovits, os.environ.get("GPT_SOVITS_DIR"), os.getcwd(), str(HERE), str(HERE.parent)]
    for c in candidates:
        if c and (Path(c) / "GPT_SoVITS" / "TTS_infer_pack").is_dir():
            return Path(c).resolve()
    sys.exit("Can't find GPT-SoVITS. Pass its folder with --gpt-sovits (the one containing GPT_SoVITS).")


PACK = find_pack()
VOICE = json.loads((PACK / "voice.json").read_text(encoding="utf-8"))
SOVITS_DIR = find_gpt_sovits()
os.chdir(SOVITS_DIR)
sys.path.insert(0, str(SOVITS_DIR))
sys.path.insert(1, str(SOVITS_DIR / "GPT_SoVITS"))
os.environ.setdefault("version", VOICE.get("version", "v2"))

import numpy as np  # noqa: E402
import torch  # noqa: E402
import uvicorn  # noqa: E402
from fastapi import Body, FastAPI, HTTPException, Request  # noqa: E402
from fastapi.responses import JSONResponse, Response, StreamingResponse  # noqa: E402

HAS_GPU = torch.cuda.is_available()


class Voice:
    def __init__(self):
        self.tts = None
        self.ready = False
        self.lock = threading.Lock()
        self.rate = 32000
        self._free = None
        self._cleanup_token = None

    def load(self):
        from GPT_SoVITS.TTS_infer_pack.TTS import TTS, TTS_Config
        config = {"version": VOICE.get("version", "v2"), "custom": {
            "device": "cuda" if HAS_GPU else "cpu", "is_half": HAS_GPU, "version": VOICE.get("version", "v2"),
            "t2s_weights_path": str(PACK / "gpt.ckpt"), "vits_weights_path": str(PACK / "sovits.pth"),
            "bert_base_path": "GPT_SoVITS/pretrained_models/chinese-roberta-wwm-ext-large",
            "cnhuhbert_base_path": "GPT_SoVITS/pretrained_models/chinese-hubert-base",
        }}
        self.tts = TTS(TTS_Config(config))
        self.rate = int(self.tts.configs.sampling_rate)
        self._free = self.tts.empty_cache          # clean up once when idle, not after every line
        self.tts.empty_cache = lambda: None
        for _ in self.tts.run(self.request("Hi there. Ready when you are.", fragment=False)):
            pass
        self.ready = True

    def request(self, text, fragment=True, speed=None):
        return {
            "text": text, "text_lang": "en",
            "ref_audio_path": str(PACK / "reference.wav"), "prompt_text": VOICE["reference_text"], "prompt_lang": "en",
            "top_k": int(VOICE.get("top_k", 15)), "top_p": 1.0, "temperature": float(VOICE.get("temperature", 1.0)),
            "text_split_method": "cut5", "batch_size": 1, "batch_threshold": 0.75,
            "split_bucket": not fragment, "return_fragment": fragment,
            "speed_factor": float(speed or VOICE.get("speed", 1.0)), "fragment_interval": 0.2,
            "seed": -1, "parallel_infer": True, "repetition_penalty": 1.35,
        }

    def acquire(self, wait=20):
        self._cleanup_token = None
        if self.lock.acquire(timeout=0.02):
            return True
        self.tts.stop()                             # a new request interrupts the one still talking
        return self.lock.acquire(timeout=wait)

    def release(self):
        self.lock.release()
        self._cleanup_token = token = object()

        def cleanup():
            if self._cleanup_token is token and self.lock.acquire(blocking=False):
                try:
                    self._free()
                finally:
                    self.lock.release()

        timer = threading.Timer(4.0, cleanup)
        timer.daemon = True
        timer.start()


VOICE_ENGINE = Voice()
app = FastAPI(title="BellAi voice")


def wav_header(rate, data_bytes=None):
    """A WAV header. Without a length it says 'unknown/streaming', which players accept."""
    size = 0xFFFFFFFF - 36 if data_bytes is None else data_bytes
    return (b"RIFF" + struct.pack("<I", min(size + 36, 0xFFFFFFFF)) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) + b"data" + struct.pack("<I", size))


def check_key(request):
    if args.key and args.key not in (request.headers.get("x-api-key"), request.query_params.get("key")):
        raise HTTPException(401, "Missing or wrong API key.")


def clean(text):
    text = re.sub(r"<[a-zA-Z]+>", " ", text or "")
    return re.sub(r"\s+", " ", text).strip()[:2000]


def speak(text, stream=True, speed=None):
    text = clean(text)
    if not text:
        raise HTTPException(400, "No text to speak.")
    if not VOICE_ENGINE.ready:
        raise HTTPException(503, "The voice is still loading.")
    if not VOICE_ENGINE.acquire():
        raise HTTPException(503, "The voice is busy. Try again.")
    if speed is not None:
        speed = min(max(float(speed), 0.6), 1.6)
    request = VOICE_ENGINE.request(text, fragment=True, speed=speed)
    rate = VOICE_ENGINE.rate

    def pcm():
        started, first = time.time(), None
        try:
            for _, chunk in VOICE_ENGINE.tts.run(request):
                chunk = np.asarray(chunk)
                if chunk.dtype != np.int16:
                    chunk = (np.clip(chunk, -1, 1) * 32767).astype(np.int16)
                if first is None:
                    first = time.time() - started
                    print(f"first audio after {first:.2f}s: {text[:60]!r}")
                yield chunk.tobytes()
        finally:
            VOICE_ENGINE.release()

    if stream:
        def body():
            yield wav_header(rate)
            yield from pcm()
        return StreamingResponse(body(), media_type="audio/wav", headers={"Cache-Control": "no-store"})
    data = b"".join(pcm())
    return Response(wav_header(rate, len(data)) + data, media_type="audio/wav")


@app.get("/health")
def health(request: Request):
    check_key(request)
    return {"ready": VOICE_ENGINE.ready, "voice": VOICE.get("name", "BellAi"), "sample_rate": VOICE_ENGINE.rate,
            "gpu": torch.cuda.get_device_name(0) if HAS_GPU else "CPU (slow)"}


@app.post("/tts")
def tts_post(request: Request, body: dict = Body(...)):
    check_key(request)
    return speak(body.get("text", ""), stream=body.get("stream", True) is not False, speed=body.get("speed"))


@app.get("/tts")
def tts_get(request: Request, text: str = "", speed: float = None, stream: bool = True):
    check_key(request)
    return speak(text, stream=stream, speed=speed)


def main():
    if args.host not in ("127.0.0.1", "localhost") and not args.key:
        print("WARNING: other devices can reach this server and no --key is set. Anyone on the network can use it.")
    print(f"Voice pack: {PACK}\nGPT-SoVITS: {SOVITS_DIR}\nLoading the voice{' on the GPU' if HAS_GPU else ' on the CPU (this will be slow)'}...")
    VOICE_ENGINE.load()
    print(f"\nBellAi voice is ready on http://{args.host}:{args.port}")
    print(f"Try it: http://localhost:{args.port}/tts?text=Hello%20there" + (f"&key={args.key}" if args.key else ""))
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
