# BellAi Voice Server (Mac)

## Overview

**BellAi Voice Server** streams the chat model's reply to the app as text and speaks it one sentence at a time, and turns what you say into text. Speech is made by Orpheus 3B (4-bit) and understood by Whisper large-v3-turbo, both running on MLX in the same process, so there is no separate speech server to start. It sends the same messages as `Server/bell_voice_server.py`, so the app connects to it the same way.

It speaks in Bella's voice when `models/bella-orpheus-4bit` exists, and falls back to the stock `tara` voice when it doesn't. That folder is not in git. Make it with `convert_bella.py` (see below).

## Getting Started

### Prerequisites

* Hardware: A Mac with Apple Silicon. It was tested on an M5 Pro with 24 GB.
* Software: `uv` (`brew install uv`). The script installs Python 3.11 and everything else into `.venv`.
* Chat model: The [`llm`](../llm/README.md) server running on port `11434`. Start it first.
* Disk: About 3.7 GB for the Orpheus model and the SNAC decoder, and about 1.6 GB for Whisper, downloaded to `~/.cache/huggingface` on the first start.
* Network: The app connects to port `8000`, so the Mac must be reachable over Tailscale.

### How to Enable / Access

1. Run `./start_voice.sh` in this folder. The first start downloads the model and takes a few minutes.
2. Wait for `bell voice loaded` in the log.
3. Open http://127.0.0.1:8000/health. It should show `"llm": true`, `"tts": true` and `"stt": true`.

## How to Use It

1. **Use it from the app:** The app connects to `ws://<this Mac>:8000/ws` and sends an Ollama style request body (`messages` or `prompt`; the model name is ignored). It gets back text as it is written and one wav clip per sentence. Messages are listed at the top of `bell_voice_server.py`.
2. **What you say:** `POST /transcribe` takes a wav recording (16 kHz, mono, 16 bit, up to about two minutes) as the request body and returns `{"text": "..."}`. The app records on the phone and sends it here, so the audio never goes to Apple. A recording with nobody speaking comes back as `""`, because Whisper would otherwise make up words for silence. Anything that isn't that kind of wav gets a `400`.
3. **Food photos, insights and mail:** `POST /analyze` is passed on to the [food server](../food/README.md) on port `8002`, `POST /insights` to [Insights](../insights/README.md) on port `8004`, and `/mail` and `/drafts` to the [mail watcher](../mail/README.md) on port `8003`, because the app sends all of them to this host. `/health` shows `"food"`, `"insights"` and `"mail"` when they are up.
4. **Test the voice:** Run `curl -X POST http://127.0.0.1:8000/speak -H 'Content-Type: application/json' -d '{"text": "Hello there."}' -o hello.wav`, then open `hello.wav`.
5. **Make Bella's model:** Copy `bella_voice_f16.gguf` (the Bella LoRA merged into Orpheus 3B) onto this Mac's disk, then run `.venv/bin/python convert_bella.py bella_voice_f16.gguf models/bella-orpheus-4bit`. It takes a couple of minutes, and the stock 4-bit model must already be in the Hugging Face cache (the first `./start_voice.sh` downloads it). Restart the server afterwards.
6. **Change settings:** Set these before `./start_voice.sh`: `LLM_HOST`, `FOOD_URL`, `INSIGHTS_URL`, `MAIL_URL`, `TTS_MODEL` (the MLX model, a folder or a Hugging Face name), `STT_MODEL` (the Whisper model, `mlx-community/whisper-large-v3-turbo-asr-fp16` by default), `STT_LANGUAGE` (`en` by default, because Whisper guesses wrong on a short clip, set it to an empty value to let it guess), `BELL_VOICE` (the speaker name, `bella` or `tara`), `BELL_SYSTEM_PROMPT`, `HOST` and `PORT`.
7. **Handle an error:** If `"llm"` is false, start `llm/start_llm.sh` or set `LLM_HOST`. If the app gets a `tts_error`, the log shows why.

> 💡 **Tip:** Each sentence is rendered in full before it is sent, so the first sound waits for the whole first sentence. It took about 2 seconds for a short sentence and 6 seconds for an 80-character one. Speech is made in about 0.65 seconds per second of audio, so later sentences keep ahead of playback. Whisper turns a short sentence into text in well under a second once it is loaded.
