# bell data server (mac): the app's saved data (tasks and so on) in a local sqlite file
# app -> http over tailscale -> sqlite, replaces the firebase functions
#
# GET /data -> {"data": {...}}, or {"data": null} if nothing is saved yet
# PUT /data {"data": {...}} -> {"ok": true}
# GET /health
#
# one user, being on the tailnet is the login
#
# env: DATA_DB, HOST, PORT
import json
import logging
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

log = logging.getLogger("bell_data")

DB_PATH = os.environ.get("DATA_DB") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "bellai.db")
MAX_PAYLOAD_BYTES = 100_000


@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    try:
        with conn:  # commits, or rolls back if something raises
            yield conn
    finally:
        conn.close()


# the id check keeps it to a single row
with db() as conn:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS user_data ("
        "id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL, updated_at TEXT NOT NULL)"
    )

app = FastAPI()


class Save(BaseModel):
    data: dict[str, Any]


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/data")
def get_data():
    with db() as conn:
        row = conn.execute("SELECT payload FROM user_data WHERE id = 1").fetchone()
    return {"data": json.loads(row[0]) if row else None}


@app.put("/data")
def put_data(body: Save):
    payload = json.dumps(body.data, separators=(",", ":"))
    if len(payload.encode()) > MAX_PAYLOAD_BYTES:
        raise HTTPException(413, "`data` is too large.")
    with db() as conn:
        conn.execute(
            "INSERT INTO user_data (id, payload, updated_at) VALUES (1, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at",
            (payload, datetime.now(timezone.utc).isoformat()),
        )
    return {"ok": True}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log.info("db %s", DB_PATH)
    uvicorn.run(app, host=os.environ.get("HOST", "0.0.0.0"), port=int(os.environ.get("PORT", "8001")))
