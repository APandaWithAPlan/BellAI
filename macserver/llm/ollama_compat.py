# ollama compatible chat server (mac): qwen3.5 on mlx, answering the way ollama does on port 11434
# the app, insights and the pi all talk to ollama's api, so they work here without changes
# ollama api in -> this -> mlx-lm (openai api, started here on 127.0.0.1:11435) -> ollama style reply out
#
# GET /api/version, GET /api/tags
# POST /api/chat   streams unless "stream" is false, like ollama
#                  "options" (temperature, top_p, top_k, num_predict) and "format" (json or a json schema) are used,
#                  "think" is ignored because thinking is always off, replies are read aloud so nobody waits on it
# GET or POST /v1/...   passed straight on, with the model name replaced because mlx-lm only runs the one it loaded
#
# env: LLM_MODEL, HOST, PORT
import asyncio
import json
import logging
import os
import re
import subprocess
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse

log = logging.getLogger("ollama_compat")

MODEL = os.environ.get("LLM_MODEL", "mlx-community/Qwen3.5-4B-4bit")
NAME = "qwen3.5:4b-q4_K_M"  # what clients expect to see in /api/tags, they ask for it by this name
BACKEND = "http://127.0.0.1:11435"
SAMPLING = {"temperature": "temperature", "top_p": "top_p", "top_k": "top_k", "num_predict": "max_tokens"}

backend: subprocess.Popen
http: httpx.AsyncClient


def now():
    return datetime.now(timezone.utc).isoformat()


@asynccontextmanager
async def lifespan(_):
    global backend, http
    backend = subprocess.Popen([
        sys.executable, "-m", "mlx_lm", "server", "--model", MODEL, "--host", "127.0.0.1", "--port", "11435",
        "--temp", "0.7", "--max-tokens", "1024", "--chat-template-args", '{"enable_thinking": false}',
    ])
    http = httpx.AsyncClient(timeout=httpx.Timeout(None, connect=5))
    try:
        # the first start downloads the model, so there is no time limit, only whether the server is still there
        while not await ready():
            if backend.poll() is not None:
                raise RuntimeError("mlx-lm stopped, see the log above")
            await asyncio.sleep(3)
        log.info("chat model loaded")
        yield
    finally:
        await http.aclose()
        backend.terminate()
        try:
            backend.wait(timeout=20)
        except subprocess.TimeoutExpired:
            backend.kill()


async def ready():
    # a tiny question, because the server answers before the model is in memory
    try:
        r = await http.post(f"{BACKEND}/v1/chat/completions", timeout=120, json={
            "model": "default_model", "max_tokens": 1, "messages": [{"role": "user", "content": "hi"}]})
    except httpx.TransportError:
        return False
    return r.status_code == 200


app = FastAPI(title="BellAI chat model (ollama compatible)", lifespan=lifespan)


@app.get("/")
def root():
    return PlainTextResponse("Ollama is running")  # some clients look for this


@app.get("/api/version")
def version():
    return {"version": "0.0.0-mlx"}


@app.get("/api/tags")
def tags():
    return {"models": [{"name": NAME, "model": NAME, "modified_at": now(), "size": 0}]}


# --- /api/chat

def openai_body(req, stream):
    messages = [dict(m) for m in req.get("messages") or []]
    if req.get("format"):
        # mlx-lm can't force a shape, so ask for it
        rule = "Reply with only a JSON object, no other text."
        if isinstance(req["format"], dict):
            rule += " It must match this JSON schema: " + json.dumps(req["format"])
        if messages and messages[0].get("role") == "system":
            messages[0]["content"] += "\n\n" + rule
        else:
            messages.insert(0, {"role": "system", "content": rule})
    body = {"model": "default_model", "messages": messages, "stream": stream}
    for key, value in (req.get("options") or {}).items():
        if key in SAMPLING and value is not None:
            body[SAMPLING[key]] = value
    return body


def only_json(text):
    # models like to wrap json in a code fence or add a sentence around it
    start, end = text.find("{"), text.rfind("}")
    return text[start:end + 1] if 0 <= start < end else text


def chunk(model, content, done=False):
    reply = {"model": model, "created_at": now(), "message": {"role": "assistant", "content": content}, "done": done}
    if done:
        reply["done_reason"] = "stop"
    return json.dumps(reply) + "\n"


async def stream_chat(model, body):
    try:
        async with http.stream("POST", f"{BACKEND}/v1/chat/completions", json=body) as r:
            if r.status_code != 200:
                yield json.dumps({"error": (await r.aread()).decode(errors="replace")[:300]}) + "\n"
                return
            async for line in r.aiter_lines():
                if not line.startswith("data:"):  # keepalive comments
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                delta = (json.loads(data)["choices"] or [{}])[0].get("delta", {}).get("content")
                if delta:
                    yield chunk(model, delta)
    except httpx.TransportError:
        yield json.dumps({"error": "the chat model isn't running"}) + "\n"
        return
    yield chunk(model, "", done=True)


@app.post("/api/chat")
async def chat(request: Request):
    req = await request.json()
    model = req.get("model") or NAME
    stream = req.get("stream", True)
    body = openai_body(req, stream)
    if stream:
        return StreamingResponse(stream_chat(model, body), media_type="application/x-ndjson")
    try:
        r = await http.post(f"{BACKEND}/v1/chat/completions", json=body)
    except httpx.TransportError:
        return JSONResponse({"error": "the chat model isn't running"}, status_code=503)
    if r.status_code != 200:
        return JSONResponse({"error": r.text[:300]}, status_code=r.status_code)
    answer = r.json()
    content = answer["choices"][0]["message"]["content"]
    if req.get("format"):
        content = only_json(content)
    usage = answer.get("usage") or {}
    reply = json.loads(chunk(model, content, done=True))
    reply.update(prompt_eval_count=usage.get("prompt_tokens", 0), eval_count=usage.get("completion_tokens", 0))
    return reply


# --- the openai api, as it is

@app.api_route("/v1/{path:path}", methods=["GET", "POST"])
async def openai(path: str, request: Request):
    url = f"{BACKEND}/v1/{path}"
    if request.method == "GET":
        r = await http.get(url)
        return JSONResponse(r.json(), status_code=r.status_code)
    body = await request.json()
    body["model"] = "default_model"
    if not body.get("stream"):
        r = await http.post(url, json=body)
        return JSONResponse(r.json(), status_code=r.status_code)

    async def relay():
        async with http.stream("POST", url, json=body) as r:
            async for line in r.aiter_lines():
                yield line + "\n"

    return StreamingResponse(relay(), media_type="text/event-stream")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log.info("model %s", MODEL)
    uvicorn.run(app, host=os.environ.get("HOST", "0.0.0.0"), port=int(os.environ.get("PORT", "11434")))
