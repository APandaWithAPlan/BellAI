# BellAi Chat Model (Mac)

## Overview

**BellAi Chat Model** runs Qwen3.5 4B (4-bit) on MLX and answers the way Ollama does, on port `11434`, the port Ollama used. The app, the [voice server](../voice/README.md), the Discord bridge, the [mail watcher](../mail/README.md), [Insights](../insights/README.md) and the Raspberry Pi all talk to it without any changes to how they ask. Thinking is turned off so replies start right away.

It is a small server (`ollama_compat.py`) in front of `mlx-lm`, which it starts itself on port `11435` for this Mac only.

## Getting Started

### Prerequisites

* Hardware: A Mac with Apple Silicon. It was tested on an M5 Pro with 24 GB.
* Software: `uv` (`brew install uv`). The script installs Python 3.11 and `mlx-lm` into `.venv`.
* Disk: About 3 GB for the model, downloaded to `~/.cache/huggingface` on the first start.
* Network: The app and the Pi connect to port `11434`, so the Mac must be reachable over Tailscale as `ai-server`.

### How to Enable / Access

1. Run `./start_llm.sh` in this folder. The first start downloads the model and takes a few minutes.
2. Wait for `chat model loaded` in the log.
3. Check it with `curl http://127.0.0.1:11434/api/version`.

## How to Use It

1. **Use it like Ollama:** `GET /api/version`, `GET /api/tags` and `POST /api/chat` work as in Ollama, streaming by default. `options` (`temperature`, `top_p`, `top_k`, `num_predict`) and `format` (`"json"` or a JSON schema) are used. `think` is ignored. The model name in a request is ignored too, because only one model runs.
2. **Use it like OpenAI:** Everything under `/v1/` is passed straight to `mlx-lm`, so `/v1/chat/completions` works with any model name. For example `curl http://127.0.0.1:11434/v1/chat/completions -H 'Content-Type: application/json' -d '{"model": "anything", "messages": [{"role": "user", "content": "Hello"}]}'`.
3. **Use a different model:** Run `./start_llm.sh <Hugging Face model>`, for example `mlx-community/Qwen3.5-9B-4bit`. A bigger model needs more of the Mac's 24 GB, which the voice and food models share.
4. **Change the port or host:** Set `PORT` or `HOST` before `./start_llm.sh`.
5. **Handle an error:** If a request says the chat model isn't running, check the log for the `mlx-lm` error.

> 💡 **Tip:** `format` can't force the shape of the reply, because `mlx-lm` has no structured output. The server asks for it in the prompt and trims anything around the JSON, and Insights falls back to safe defaults when the model gets it wrong.
