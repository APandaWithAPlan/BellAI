# bell voice server (mac): llm reply in, text + bell's voice out
# app -> ws /ws -> mlx-lm (text) + orpheus on mlx (audio per sentence)
# same messages as Server/bell_voice_server.py, so the app doesn't change
#
# app sends an ollama style body: {"model": ..., "messages": [...]}  (or "prompt")
# {"type": "cancel"} stops the reply
# gets back:
#   {"type": "text", "delta": "..."}
#   {"type": "sentence", "index": 0, "text": "..."} then one binary wav frame
#   {"type": "tts_error", ...}  no audio for that sentence, text keeps going
#   {"type": "done"} or {"type": "error", "message": "..."}
#
# also: GET /health, POST /speak {"text": "..."} -> wav,
#       POST /transcribe (wav body, 16 kHz mono) -> {"text": "..."}, what was said, whisper on mlx,
#       POST /analyze (food photo and/or text) passed on to the food server,
#       POST /insights (meals and preferences) passed on to the insights server,
#       /mail and /drafts passed on to the mail server (the emails, and replies waiting for approval)
#
# env: LLM_HOST, FOOD_URL, INSIGHTS_URL, MAIL_URL, TTS_MODEL, STT_MODEL, STT_LANGUAGE, BELL_VOICE, BELL_SYSTEM_PROMPT, HOST, PORT
import asyncio
import io
import json
import logging
import os
import re
import wave
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
import numpy as np
import uvicorn
from fastapi import FastAPI, HTTPException, Request, Response, WebSocket, WebSocketDisconnect

log = logging.getLogger("bell_voice")

BELLA_MODEL = Path(__file__).parent / "models" / "bella-orpheus-4bit"  # made by convert_bella.py
HAS_BELLA = BELLA_MODEL.is_dir()
TTS_MODEL = os.environ.get("TTS_MODEL", str(BELLA_MODEL) if HAS_BELLA else "mlx-community/orpheus-3b-0.1-ft-4bit")
VOICE_NAME = os.environ.get("BELL_VOICE", "bella" if HAS_BELLA else "tara")  # tara is the stock voice
SAMPLE_RATE = 24000
SYSTEM_PROMPT = os.environ.get("BELL_SYSTEM_PROMPT") or (
    "You are BellAI, a voice assistant for the home, like a smart speaker. Your replies are read aloud, "
    "so answer in one or two short, plain sentences. Never use markdown, lists, emoji or URLs. "
    "If you don't know something, say so briefly. If a request is unclear, ask one short question."
)


def llm_base():
    host = os.environ.get("LLM_HOST", "127.0.0.1:11434").strip().rstrip("/")
    if "://" not in host:
        host = "http://" + host
    return host.replace("//0.0.0.0", "//127.0.0.1")


LLM_URL = llm_base()
FOOD_URL = os.environ.get("FOOD_URL", "http://127.0.0.1:8002").rstrip("/")
INSIGHTS_URL = os.environ.get("INSIGHTS_URL", "http://127.0.0.1:8004").rstrip("/")
MAIL_URL = os.environ.get("MAIL_URL", "http://127.0.0.1:8003").rstrip("/")
STT_MODEL = os.environ.get("STT_MODEL", "mlx-community/whisper-large-v3-turbo-asr-fp16")
STT_LANGUAGE = os.environ.get("STT_LANGUAGE", "en")  # whisper guesses wrong on a short clip, "" lets it guess anyway
STT_RATE = 16000
MAX_RECORDING = 5_000_000  # bytes, over two minutes of speech
QUIET = 0.003  # a recording this quiet is silence, whisper would make up words for it


# --- splitting text into sentences

ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "st", "vs", "e.g", "i.e", "etc", "prof", "sr", "jr"}
SENTENCE_END = re.compile(r"[.!?…]+[\"')\]]*\s+|\n+")
MIN_CHARS = 12  # shorter bits get glued onto the next sentence


def clean(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)  # code blocks
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"[*_`#>~|]+", "", text)  # markdown junk
    text = re.sub(r"[\U00010000-\U0010ffff☀-➿️]", "", text)  # emoji
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


# --- orpheus

def to_wav(audio):
    pcm = (np.clip(audio, -1, 1) * 32767).astype(np.int16)
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())
    return out.getvalue()


class Voice:
    def __init__(self):
        # mlx wants the model used on the thread that loaded it, so one thread does all of it
        self.pool = ThreadPoolExecutor(max_workers=1)
        self.model = None
        self.listener = None
        self.ready = False

    def load(self):
        from mlx_audio.stt.utils import load_model as load_listener
        from mlx_audio.tts.utils import load_model
        self.model = load_model(TTS_MODEL)
        self.render("Warming up.")  # first run compiles, so do it before the app asks
        self.listener = load_listener(STT_MODEL)
        self.transcribe(np.zeros(STT_RATE, dtype=np.float32))
        self.ready = True
        log.info("bell voice loaded")

    def transcribe(self, audio):
        return self.listener.generate(audio, language=STT_LANGUAGE or None).text.strip()

    async def listen(self, audio):
        return await asyncio.get_running_loop().run_in_executor(self.pool, self.transcribe, audio)

    def render(self, text):
        chunks = [
            np.array(r.audio, dtype=np.float32).reshape(-1)
            for r in self.model.generate(text=text, voice=VOICE_NAME)  # not stream=True, its chunks repeat audio at the joins
        ]
        if not chunks:
            raise RuntimeError("no audio came back")
        return to_wav(np.concatenate(chunks))

    async def synth(self, text):
        return await asyncio.get_running_loop().run_in_executor(self.pool, self.render, text)


voice: Voice
http: httpx.AsyncClient


@asynccontextmanager
async def lifespan(_):
    global voice, http
    voice = Voice()
    http = httpx.AsyncClient(timeout=httpx.Timeout(120, connect=5))
    await asyncio.get_running_loop().run_in_executor(voice.pool, voice.load)
    yield
    await http.aclose()
    voice.pool.shutdown(wait=False)


app = FastAPI(title="BellAI voice server (mac)", lifespan=lifespan)


@app.get("/health")
async def health():  # check server
    try:
        llm = (await http.get(f"{LLM_URL}/v1/models", timeout=3)).status_code < 500
    except httpx.HTTPError:
        llm = False
    async def up(url):
        try:
            return (await http.get(url, timeout=3)).status_code < 500
        except httpx.HTTPError:
            return False

    return {"llm": llm, "tts": voice.ready, "stt": voice.ready, "food": await up(f"{FOOD_URL}/health"),
            "insights": await up(f"{INSIGHTS_URL}/insights/health"), "mail": await up(f"{MAIL_URL}/health")}


@app.post("/speak")
async def speak_text(req: dict):
    text = clean(str(req.get("text", "")))
    if not speakable(text):
        raise HTTPException(400, "nothing to say")
    return Response(await voice.synth(text), media_type="audio/wav")


@app.post("/transcribe")
async def transcribe(request: Request):
    body = await request.body()
    if len(body) > MAX_RECORDING:
        raise HTTPException(413, "That recording is too long.")
    try:
        with wave.open(io.BytesIO(body)) as w:
            ok = (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (STT_RATE, 1, 2)
            pcm = w.readframes(w.getnframes()) if ok else b""
    except (wave.Error, EOFError):
        ok = False
    if not ok:
        raise HTTPException(400, "Send a wav recording: 16 kHz, mono, 16 bit.")
    audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768
    if len(audio) < STT_RATE // 5 or float(np.sqrt(np.mean(audio ** 2))) < QUIET:
        return {"text": ""}
    return {"text": await voice.listen(audio)}


async def pass_on(request, url, name):
    # these servers run on this mac too, but the app only knows this host
    try:
        r = await http.request(
            request.method, url, params=request.query_params, content=await request.body(),
            headers={"content-type": request.headers.get("content-type", "application/json")}, timeout=120,
        )
    except httpx.TransportError:
        raise HTTPException(503, f"The {name} server isn't running.")
    return Response(r.content, status_code=r.status_code, media_type="application/json")


@app.post("/analyze")
async def analyze(request: Request):
    return await pass_on(request, f"{FOOD_URL}/analyze", "food")


@app.post("/insights")
async def insights(request: Request):
    return await pass_on(request, f"{INSIGHTS_URL}/insights", "insights")


# the emails the mail server has read, and the replies it has written that wait for approval
@app.get("/mail")
async def mail(request: Request):
    return await pass_on(request, f"{MAIL_URL}/mail", "mail")


@app.get("/drafts")
async def drafts(request: Request):
    return await pass_on(request, f"{MAIL_URL}/drafts", "mail")


@app.post("/drafts")
async def new_draft(request: Request):
    return await pass_on(request, f"{MAIL_URL}/drafts", "mail")


@app.post("/drafts/{draft_id}/send")
async def send_draft(draft_id: int, request: Request):
    return await pass_on(request, f"{MAIL_URL}/drafts/{draft_id}/send", "mail")


@app.post("/drafts/{draft_id}/discard")
async def discard_draft(draft_id: int, request: Request):
    return await pass_on(request, f"{MAIL_URL}/drafts/{draft_id}/discard", "mail")


# --- the actual streaming

async def llm_deltas(req):
    # the app sends an ollama body, mlx-lm wants an openai one
    messages = req.get("messages") or [{"role": "user", "content": req.get("prompt", "")}]
    # add our system prompt if the app didn't send one
    if not any(m.get("role") == "system" for m in messages):
        messages = [{"role": "system", "content": req.get("system") or SYSTEM_PROMPT}, *messages]
    # default_model is whatever mlx-lm loaded, it can't load others on request
    body = {"model": "default_model", "messages": messages, "stream": True}
    async with http.stream(
        "POST", f"{LLM_URL}/v1/chat/completions", json=body, timeout=httpx.Timeout(None, connect=5),
    ) as r:
        if r.status_code != 200:
            error = (await r.aread()).decode(errors="replace")
            raise RuntimeError(f"LLM {r.status_code}: {error[:300]}")
        async for line in r.aiter_lines():
            if not line.startswith("data:"):  # keepalive comments
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                return
            msg = json.loads(data)
            if "error" in msg:
                raise RuntimeError(f"LLM: {msg['error']}")
            delta = (msg["choices"] or [{}])[0].get("delta", {}).get("content")
            if delta:
                yield delta


async def run_request(ws, req):
    # text goes out right away, sentences get voiced while the llm keeps writing
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
        async for delta in llm_deltas(req):
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
    log.info("llm %s | tts %s | voice %s", LLM_URL, TTS_MODEL, VOICE_NAME)
    uvicorn.run(app, host=os.environ.get("HOST", "0.0.0.0"), port=int(os.environ.get("PORT", "8000")))
