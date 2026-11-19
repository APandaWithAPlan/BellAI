# checks the captures endpoints against a made up camera folder, a temporary store for the copies and a temporary database
# it starts its own server on a free port, so nothing else needs to be running
# run: .venv/bin/python tests/test_captures.py
import http.client
import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import time
from pathlib import Path

import uvicorn

folder = Path(tempfile.mkdtemp())
os.environ["CAPTURES_DIR"] = str(folder / "recordings")
os.environ["CAPTURES_STORE"] = str(folder / "store")
os.environ["DATA_DB"] = str(folder / "test.db")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import bell_data_server  # noqa: E402
import captures  # noqa: E402

recordings = folder / "recordings"
(recordings / "2026-10-28").mkdir(parents=True)
(recordings / "2026-10-29").mkdir()
VIDEO = bytes(range(256)) * 40  # 10,240 bytes, so a range is easy to check


def clip(day, name, start, end, motion=12.5, thumbnail=True):
    (recordings / day / f"{name}.mp4").write_bytes(VIDEO)
    if thumbnail:
        (recordings / day / f"{name}.jpg").write_bytes(b"\xff\xd8thumb")
    return {"id": name, "start": start, "end": end, "duration_s": 18, "peak_motion_pct": motion,
            "video": f"{day}/{name}.mp4", "thumbnail": f"{day}/{name}.jpg"}


def write_events(events):
    (recordings / "events.json").write_text(json.dumps(events))


older = clip("2026-10-28", "20261028-120000", "2026-10-28T12:00:00-05:00", "2026-10-28T12:00:18-05:00")
newer = clip("2026-10-29", "20261029-153000", "2026-10-29T15:30:00-05:00", "2026-10-29T15:30:18-05:00", motion=63.3)
bare = clip("2026-10-29", "20261029-160000", "2026-10-29T16:00:00-05:00", "2026-10-29T16:00:18-05:00", thumbnail=False)
gone = {"id": "20261029-170000", "start": "2026-10-29T17:00:00-05:00", "end": "2026-10-29T17:00:18-05:00",
        "duration_s": 18, "video": "2026-10-29/20261029-170000.mp4", "thumbnail": "2026-10-29/20261029-170000.jpg"}
outside = {**older, "id": "escape", "video": "../outside.mp4"}
absolute = {**older, "id": "absolute", "video": "/etc/hosts"}
badid = {**older, "id": "../bad"}
write_events([newer, older, bare, gone, outside, absolute, badid, {"id": "x"}, "nonsense"])
(folder / "outside.mp4").write_bytes(VIDEO)

with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
server = uvicorn.Server(uvicorn.Config(bell_data_server.app, host="127.0.0.1", port=port, log_level="warning"))
threading.Thread(target=server.run, daemon=True).start()
while not server.started:
    time.sleep(0.05)


class Reply:
    def __init__(self, response):
        self.status_code = response.status
        self.headers = {k.lower(): v for k, v in response.getheaders()}
        self.content = response.read()

    def json(self):
        return json.loads(self.content)


class Client:
    def request(self, method, path, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        try:
            conn.request(method, path, headers=headers or {})
            return Reply(conn.getresponse())
        finally:
            conn.close()

    def get(self, path, headers=None):
        return self.request("GET", path, headers)

    def post(self, path):
        return self.request("POST", path)


client = Client()

# importing keeps the clips that exist and says how many it left out, and does it again without doubling anything
result = client.post("/captures/import").json()
assert result == {"added": 3, "updated": 0, "skipped": 6}, result

# every clip and thumbnail was copied into the store, in the same place, and nothing half copied is left
store = folder / "store"
assert (store / "2026-10-29" / "20261029-153000.mp4").read_bytes() == VIDEO
assert (store / "2026-10-28" / "20261028-120000.jpg").read_bytes() == b"\xff\xd8thumb"
assert not list(store.rglob("*.part")) and not (store / "20261029-170000.mp4").exists()
assert not any(p.name == "outside.mp4" for p in store.rglob("*"))
copied = (store / "2026-10-29" / "20261029-153000.mp4").stat().st_mtime_ns
assert client.post("/captures/import").json() == {"added": 0, "updated": 3, "skipped": 6}
assert (store / "2026-10-29" / "20261029-153000.mp4").stat().st_mtime_ns == copied  # the same file isn't copied again

# newest first, with what the app needs and whether the clip can be played
listing = client.get("/captures").json()
assert listing["total"] == 3 and [c["id"] for c in listing["captures"]] == [bare["id"], newer["id"], older["id"]], listing
first = listing["captures"][1]
assert first == {"id": newer["id"], "camera": "home_cam", "started_at": "2026-10-29T15:30:00-05:00",
                 "ended_at": "2026-10-29T15:30:18-05:00", "duration_s": 18, "peak_motion_pct": 63.3,
                 "size_bytes": len(VIDEO), "available": True}, first
assert [c["id"] for c in client.get("/captures?limit=1&offset=1").json()["captures"]] == [newer["id"]]
assert client.get("/captures?limit=0").status_code == 422

# the video comes back whole, and in pieces for a player that seeks
whole = client.get(f"/captures/{newer['id']}/video")
assert whole.status_code == 200 and whole.content == VIDEO and whole.headers["content-type"] == "video/mp4"
piece = client.get(f"/captures/{newer['id']}/video", headers={"Range": "bytes=100-199"})
assert piece.status_code == 206 and piece.content == VIDEO[100:200], piece.status_code
assert piece.headers["content-range"] == f"bytes 100-199/{len(VIDEO)}"
head = client.request("HEAD", f"/captures/{newer['id']}/video")
assert head.status_code == 200 and head.headers["content-length"] == str(len(VIDEO)) and head.content == b""
assert client.get(f"/captures/{newer['id']}/thumbnail").content == b"\xff\xd8thumb"
assert client.get(f"/captures/{bare['id']}/thumbnail").status_code == 404  # none was recorded

# only clips in the database can be asked for, and never by a path
assert client.get("/captures/nonsense/video").status_code == 404
assert client.get("/captures/escape/video").status_code == 404
assert client.get("/captures/..%2Foutside/video").status_code == 404

# a new events.json is picked up by just listing
fresh = clip("2026-10-29", "20261029-180000", "2026-10-29T18:00:00-05:00", "2026-10-29T18:00:18-05:00")
write_events([fresh, newer, older, bare])
client.get("/captures")  # starts the copy in the background
for _ in range(100):
    if client.get("/captures").json()["total"] == 4:
        break
    time.sleep(0.05)
assert client.get("/captures").json()["total"] == 4
assert (store / "2026-10-29" / "20261029-180000.mp4").read_bytes() == VIDEO

# with the drive out everything still plays, because it is played from the copies, and only importing needs the drive
os.rename(recordings, folder / "away")
listing = client.get("/captures").json()
assert listing["total"] == 4 and all(c["available"] for c in listing["captures"])
assert client.get(f"/captures/{newer['id']}/video").content == VIDEO
assert client.post("/captures/import").status_code == 503
os.rename(folder / "away", recordings)

# the camera deletes old clips, but the copy stays and keeps playing
(recordings / "2026-10-28" / "20261028-120000.mp4").unlink()
write_events([fresh, newer, bare])
assert client.post("/captures/import").json()["added"] == 0
listing = client.get("/captures").json()
assert listing["total"] == 4 and all(c["available"] for c in listing["captures"])
assert client.get(f"/captures/{older['id']}/video").content == VIDEO

# a copy that goes missing from the store is said so, not served as something else
(store / "2026-10-28" / "20261028-120000.mp4").unlink()
assert [c["available"] for c in client.get("/captures").json()["captures"] if c["id"] == older["id"]] == [False]
assert client.get(f"/captures/{older['id']}/video").status_code == 503

# nothing is copied if there isn't room for it
captures.shutil.disk_usage = lambda path: type("Usage", (), {"free": 1024})()
extra = clip("2026-10-29", "20261029-190000", "2026-10-29T19:00:00-05:00", "2026-10-29T19:00:18-05:00")
write_events([extra, fresh, newer, bare])
no_room = client.post("/captures/import")
assert no_room.status_code == 507 and "room" in no_room.json()["detail"]
assert not (store / "2026-10-29" / "20261029-190000.mp4").exists() and client.get("/captures").json()["total"] == 4
captures.shutil.disk_usage = shutil.disk_usage

# without a folder set there is nothing to import, but what was copied is still listed and plays
os.environ["CAPTURES_DIR"] = ""
captures.CONFIG = folder / "no-such-config"
assert client.post("/captures/import").status_code == 409
listing = client.get("/captures").json()
assert listing["total"] == 4 and [c["available"] for c in listing["captures"]].count(True) == 3
assert client.get(f"/captures/{newer['id']}/video").content == VIDEO
assert client.get("/health").json() == {"ok": True}
server.should_exit = True
print("All captures checks passed.")
