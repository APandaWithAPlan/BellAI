#!/bin/sh
# starts the bell discord bridge (needs ../setup.sh discord first, and the llm and food servers up)
# usage: ./start_discord.sh
# first run makes .venv
set -e
cd "$(dirname "$0")"
[ -d .venv ] || uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -q -r requirements.txt
exec .venv/bin/python bell_discord_bot.py
