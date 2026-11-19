# checks the music log endpoints against a temporary database
# it starts its own server on a free port, so nothing else needs to be running
# run: .venv/bin/python tests/test_music.py
import http.client
import json
import os
import socket
import sys
import tempfile
import threading
import time
from pathlib import Path

import uvicorn

os.environ["DATA_DB"] = str(Path(tempfile.mkdtemp()) / "test.db")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import bell_data_server  # noqa: E402

with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
server = uvicorn.Server(uvicorn.Config(bell_data_server.app, host="127.0.0.1", port=port, log_level="warning"))
threading.Thread(target=server.run, daemon=True).start()
while not server.started:
    time.sleep(0.05)


def request(method, path, body=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    headers = {"Content-Type": "application/json"} if body is not None else {}
    conn.request(method, path, json.dumps(body) if body is not None else None, headers)
    response = conn.getresponse()
    data = response.read()
    conn.close()
    return response.status, json.loads(data)


def play(song_id, at, genres=("Pop",)):
    return {"song_id": song_id, "title": f"Song {song_id}", "artist": "Artist", "genres": list(genres), "played_at": at}


try:
    assert request("GET", "/music/plays") == (200, {"plays": []})

    status, body = request("POST", "/music/plays", {"plays": [
        play("1", "2026-11-01T10:00:00Z"), play("2", "2026-11-01T11:00:00+00:00", genres=()),
    ]})
    assert (status, body) == (200, {"added": 2}), (status, body)

    plays = request("GET", "/music/plays")[1]["plays"]
    assert [p["song_id"] for p in plays] == ["2", "1"], plays  # newest first
    assert plays[0]["genres"] == [] and plays[1]["genres"] == ["Pop"]
    assert len(request("GET", "/music/plays?limit=1")[1]["plays"]) == 1

    assert request("POST", "/music/plays", {"plays": [play("3", "yesterday")]})[0] == 422
    assert request("POST", "/music/plays", {"plays": [play(str(i), "2026-11-01T10:00:00Z") for i in range(201)]})[0] == 413
    assert request("GET", "/music/plays?limit=0")[0] == 422
    assert len(request("GET", "/music/plays")[1]["plays"]) == 2  # the bad posts added nothing
finally:
    server.should_exit = True

print("music checks passed")
