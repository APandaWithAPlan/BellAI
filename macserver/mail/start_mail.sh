#!/bin/sh
# starts the bell mail watcher on port 8003, only this mac can connect (needs ../setup.sh email first, and the llm server up)
# usage: ./start_mail.sh
# first run makes .venv and the database file (mail.db) next to this script
set -e
cd "$(dirname "$0")"
[ -d .venv ] || uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -q -r requirements.txt
exec .venv/bin/python bell_mail_watcher.py
