#!/bin/sh
# starts the food model (qwen2.5-vl on mlx) on port 8002, only this mac can connect (the voice server passes /analyze on)
# usage: ./start_food.sh
# first run makes .venv and downloads the model (~6 GB)
# set FDC_API_KEY first for real usda lookups (free at https://fdc.nal.usda.gov/api-key-signup), otherwise DEMO_KEY allows a few requests an hour
set -e
cd "$(dirname "$0")"
[ -d .venv ] || uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -q -r requirements.txt
exec .venv/bin/python server.py
