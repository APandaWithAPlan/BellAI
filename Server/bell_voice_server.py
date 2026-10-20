# bell voice server: ollama reply in, text + bell's voice out
# app -> ws /ws -> ollama (text) + gpt-sovits (audio per sentence)
#
# app sends an ollama body: {"model": ..., "messages": [...]}  (or "prompt")
# {"type": "cancel"} stops the reply
# gets back:
#   {"type": "text", "delta": "..."}
#   {"type": "sentence", "index": 0, "text": "..."} then one binary wav frame
#   {"type": "tts_error", ...}  no audio for that sentence, text keeps going
#   {"type": "done"} or {"type": "error", "message": "..."}
#
# env: OLLAMA_HOST, TTS_URL, VOICE_DIR, BELL_REF_AUDIO, GPT_WEIGHTS,
#      SOVITS_WEIGHTS, BELL_SYSTEM_PROMPT, HOST, PORT
import asyncio
import json
import logging
import os
import re
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

log = logging.getLogger("bell_voice")

HERE = Path(__file__).resolve().parent
VOICE_DIR = Path(os.environ.get("VOICE_DIR", HERE / "voice")).resolve()
TTS_URL = os.environ.get("TTS_URL", "http://127.0.0.1:9880").rstrip("/")
GPT_WEIGHTS = os.environ.get("GPT_WEIGHTS", "GPT_weights_v2/gpt.ckpt")
SOVITS_WEIGHTS = os.environ.get("SOVITS_WEIGHTS", "SoVITS_weights_v2/sovits.pth")
SYSTEM_PROMPT = os.environ.get("BELL_SYSTEM_PROMPT") or (
    "You are BellAI, a voice assistant for the home, like a smart speaker. Your replies are read aloud, "
    "so answer in one or two short, plain sentences. Never use markdown, lists, emoji or URLs. "
    "If you don't know something, say so briefly. If a request is unclear, ask one short question."
)


def ollama_base():
    host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434").strip().rstrip("/")
    if "://" not in host:
        host = "http://" + host
    return host.replace("//0.0.0.0", "//127.0.0.1")


OLLAMA_URL = ollama_base()


def load_voice():
    cfg = json.loads((VOICE_DIR / "voice.json").read_text(encoding="utf-8"))
    return {
        "text_lang": cfg["language"],
        "ref_audio_path": os.environ.get("BELL_REF_AUDIO") or str(VOICE_DIR / "reference.wav"),
        "prompt_text": cfg["reference_text"],
        "prompt_lang": cfg["language"],
        "text_split_method": cfg["text_split_method"],
        "speed_factor": cfg["speed"],
        "temperature": cfg["temperature"],
        "top_k": cfg["top_k"],
        "top_p": cfg["top_p"],
        "repetition_penalty": cfg["repetition_penalty"],
        "media_type": "wav",
        "streaming_mode": False,  # we go sentence by sentence instead
    }


# --- splitting text into sentences

ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "st", "vs", "e.g", "i.e", "etc", "prof", "sr", "jr"}
SENTENCE_END = re.compile(r"[.!?\u2026]+[\"')\]]*\s+|\n+")
MIN_CHARS = 12  # shorter bits get glued onto the next sentence


def clean(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)  # code blocks
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"[*_`#>~|]+", "", text)  # markdown junk
    text = re.sub(r"[\U00010000-\U0010ffff\u2600-\u27bf\ufe0f]", "", text)  # emoji
    return re.sub(r"\s+", " ", text).strip()


def ends_in_abbreviation(chunk):
    words = chunk.rstrip().rstrip(".").split()
    return bool(words) and words[-1].lower().strip("\"'([") in ABBREVIATIONS


def speakable(s):
    return bool(re.search(r"[A-Za-z0-9]", s))


class SentenceSplitter:
    # a period only counts once whitespace follows, so "3.14" survives
    def __init__(self):
        self.buf = ""

    def feed(self, delta):
        self.buf += delta
        found, start = [], 0
        for m in SENTENCE_END.finditer(self.buf):
            piece = self.buf[start:m.end()]
            if ends_in_abbreviation(piece) or len(clean(piece)) < MIN_CHARS:
                continue
            found.append(piece)
            start = m.end()
        self.buf = self.buf[start:]
        return [s for s in map(clean, found) if speakable(s)]

    def flush(self):
        rest, self.buf = clean(self.buf), ""
        return [rest] if speakable(rest) else []


# --- gpt-sovits

class Voice:
    def __init__(self):
        self.params = load_voice()
        self.http = httpx.AsyncClient(timeout=httpx.Timeout(120, connect=5))
        self.ready = False
        self.lock = asyncio.Lock()

    async def ensure_ready(self):
        # loads bell's wieghts into api_v2, redone if it restarts
        async with self.lock:
            if self.ready:
                return
            for route, path in (("set_gpt_weights", GPT_WEIGHTS), ("set_sovits_weights", SOVITS_WEIGHTS)):
                r = await self.http.get(f"{TTS_URL}/{route}", params={"weights_path": path})
                if r.status_code != 200:
                    raise RuntimeError(f"{route} failed: {r.text}")
            self.ready = True
            log.info("bell voice loaded")

    async def synth(self, text):
        await self.ensure_ready()
        try:
            r = await self.http.post(f"{TTS_URL}/tts", json={**self.params, "text": text})
        except httpx.TransportError:
            self.ready = False  # api_v2 probably restarted and forgot the weights
            raise
        if r.status_code != 200:
            raise RuntimeError(r.text[:300])
        return r.content


voice: Voice


@asynccontextmanager
async def lifespan(_):
    global voice
    voice = Voice()
    try:
        await voice.ensure_ready()
    except Exception as e:  # fine, we retry on the first requset
        log.warning("tts not up yet (%s)", e)
    yield
    await voice.http.aclose()


app = FastAPI(title="BellAI voice server", lifespan=lifespan)


@app.get("/health")
async def health():  # check server
    async def up(url):
        try:
            return (await voice.http.get(url, timeout=3)).status_code < 500
        except httpx.HTTPError:
            return False

    return {"ollama": await up(f"{OLLAMA_URL}/api/version"), "tts": await up(f"{TTS_URL}/docs")}


# --- the actual streaming

async def ollama_deltas(req):
    chat = "messages" in req
    body = {**req, "stream": True}
    # add our system prompt if the app didn't send one
    if chat and not any(m.get("role") == "system" for m in body["messages"]):
        body["messages"] = [{"role": "system", "content": SYSTEM_PROMPT}, *body["messages"]]
    elif not chat:
        body.setdefault("system", SYSTEM_PROMPT)
    body.setdefault("think", False)  # no waiting on hidden reasoning
    for attempt in range(2):
        async with voice.http.stream(
            "POST", f"{OLLAMA_URL}/api/{'chat' if chat else 'generate'}", json=body,
            timeout=httpx.Timeout(None, connect=5),
        ) as r:
            if r.status_code != 200:
                error = (await r.aread()).decode(errors="replace")
                if attempt == 0 and r.status_code == 400 and "think" in error.lower():
                    del body["think"]  # model can't think, try again without it
                    continue
                raise RuntimeError(f"Ollama {r.status_code}: {error[:300]}")
            async for line in r.aiter_lines():
                if not line:
                    continue
                msg = json.loads(line)
                if "error" in msg:
                    raise RuntimeError(f"Ollama: {msg['error']}")
                delta = (msg.get("message") or {}).get("content", "") if chat else msg.get("response", "")
                if delta:
                    yield delta
                if msg.get("done"):
                    return
            return


async def run_request(ws, req):
    # text goes out right away, sentences get voiced while ollama keeps writing
    sentences = asyncio.Queue()

    async def speak():
        index = 0
        while (text := await sentences.get()) is not None:
            try:
                wav = await voice.synth(text)
            except Exception as e:
                log.warning("tts failed on sentence %d: %s", index, e)
                await ws.send_json({"type": "tts_error", "index": index, "message": str(e)})
            else:
                await ws.send_json({"type": "sentence", "index": index, "text": text})
                await ws.send_bytes(wav)
            index += 1

    speaker = asyncio.create_task(speak())
    try:
        splitter = SentenceSplitter()
        async for delta in ollama_deltas(req):
            await ws.send_json({"type": "text", "delta": delta})
            for s in splitter.feed(delta):
                sentences.put_nowait(s)
        for s in splitter.flush():
            sentences.put_nowait(s)
        sentences.put_nowait(None)
        await speaker
        await ws.send_json({"type": "done"})
    finally:
        speaker.cancel()


async def wait_for_cancel(ws):
    while True:
        msg = await ws.receive_json()
        if msg.get("type") == "cancel":
            return


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            req = await ws.receive_json()
            if req.get("type") == "cancel":
                continue
            task = asyncio.create_task(run_request(ws, req))
            listener = asyncio.create_task(wait_for_cancel(ws))
            await asyncio.wait({task, listener}, return_when=asyncio.FIRST_COMPLETED)
            if not task.done():  # cancelled, or the app left
                task.cancel()
            listener.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            except WebSocketDisconnect:
                raise
            except Exception as e:
                log.exception("request failed")
                await ws.send_json({"type": "error", "message": str(e)})
    except WebSocketDisconnect:
        pass


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log.info("ollama %s | tts %s | voice %s", OLLAMA_URL, TTS_URL, VOICE_DIR)
    uvicorn.run(app, host=os.environ.get("HOST", "0.0.0.0"), port=int(os.environ.get("PORT", "8000")))
