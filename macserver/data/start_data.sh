#!/bin/sh
# starts the bell data server (sqlite) on port 8001
# usage: ./start_data.sh
# first run makes .venv and the database file (bellai.db) next to this script
set -e
cd "$(dirname "$0")"
[ -d .venv ] || uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -q -r requirements.txt
exec .venv/bin/python bell_data_server.py
