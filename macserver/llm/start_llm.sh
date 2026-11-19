#!/bin/sh
# starts the chat model (qwen3.5 4b on mlx) on port 11434, answering the way ollama does
# usage: ./start_llm.sh [model]  (default mlx-community/Qwen3.5-4B-4bit)
# first run makes .venv and downloads the model (~3 GB)
set -e
cd "$(dirname "$0")"
[ -d .venv ] || uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -q -r requirements.txt
[ -n "$1" ] && export LLM_MODEL="$1"
exec .venv/bin/python ollama_compat.py
