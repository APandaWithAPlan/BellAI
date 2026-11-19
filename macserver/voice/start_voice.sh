#!/bin/sh
# starts the bell voice server (orpheus on mlx) on port 8000
# usage: ./start_voice.sh
# first run makes .venv and downloads the model (~3.5 GB)
set -e
cd "$(dirname "$0")"
[ -d .venv ] || uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -q -r requirements.txt
exec .venv/bin/python bell_voice_server.py
