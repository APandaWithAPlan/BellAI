#!/bin/sh
# starts the food and workout insights on port 8004, only this mac can connect (the voice server passes /insights on)
# usage: ./start_insights.sh
# first run makes .venv, needs the llm server up for the model's suggestions (without it the defaults answer)
set -e
cd "$(dirname "$0")"
[ -d .venv ] || uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -q -r requirements.txt
exec .venv/bin/python insights_server.py
