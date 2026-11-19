# bell captures (mac): the home camera's earlier motion clips, listed from the database and streamed to the app
# the camera's events.json and its dated folders of clips are read from a folder on this mac or an attached drive,
# and each clip is copied onto this mac's own disk, so it plays whether or not the drive is still connected
#
# GET /captures?limit=100&offset=0 -> {"captures": [...], "total": 130}, newest first
# GET /captures/<id>/video -> the mp4, with range requests so the app can seek and start before it has all of it
# GET /captures/<id>/thumbnail -> the jpg
# POST /captures/import -> {"added": 3, "updated": 0, "skipped": 1}, copies what is new and reads events.json again
#
# the database holds the details of each clip, and the clips and thumbnails are in the store folder
# a clip is only ever found by its id, so the app can't ask for any other file
# new clips are copied in the background when the server starts and when events.json changes
#
# env: CAPTURES_DIR (where the camera's recordings are), CAPTURES_STORE (where the copies go), or the same in ../config/bellai.env
import json
import logging
import os
import re
import shutil
import threading
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

log = logging.getLogger("bell_captures")

CONFIG = Path(__file__).resolve().parent.parent / "config" / "bellai.env"
CAMERA = "home_cam"  # the one camera, events.json doesn't name it
ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
MAX_SECONDS = 24 * 60 * 60
STORE = Path.home() / "Library" / "Application Support" / "BellAI" / "captures"  # not in Documents, which iCloud may sync
SPARE_BYTES = 2 * 1024 ** 3  # room left on the disk after copying, so the mac doesn't fill up

COLUMNS = "id, camera, started_at, ended_at, duration_s, peak_motion_pct, size_bytes, video"
KEYS = ("id", "camera", "started_at", "ended_at", "duration_s", "peak_motion_pct", "size_bytes")


def setting(name):
    value = os.environ.get(name, "")
    if not value:
        try:
            for line in CONFIG.read_text(encoding="utf-8").splitlines():
                key, _, text = line.partition("=")
                if key == name:
                    value = text.strip()
        except FileNotFoundError:
            pass
    return value


# where the camera's recordings are, or None if that isn't set up
def captures_dir():
    path = setting("CAPTURES_DIR")
    return Path(path).expanduser() if path else None


# where the copies are
def store_dir():
    path = setting("CAPTURES_STORE")
    return Path(path).expanduser() if path else STORE


# the file at this path inside the folder, or None if it points anywhere else
def inside(base, relative):
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        return None
    path = (base / relative).resolve()
    return path if base.resolve() in path.parents else None


# the file at this path inside the folder, and its path from the folder, or None if it points anywhere else
def locate(base, relative):
    path = inside(base, relative)
    return (path, path.relative_to(base.resolve())) if path is not None else None


# one event from events.json as a row and the files to copy for it, or None if it can't be used
# (no clip, a bad id, a path outside the folder)
def read_event(base, event):
    try:
        clip_id = str(event["id"])
        video = locate(base, event["video"])
        started = datetime.fromisoformat(event["start"])
        ended = datetime.fromisoformat(event["end"])
        duration = max(0, min(int(event["duration_s"]), MAX_SECONDS))
    except (KeyError, TypeError, ValueError):
        return None
    if not ID.match(clip_id) or video is None or video[0].suffix.lower() != ".mp4" or not video[0].is_file():
        return None
    thumbnail = locate(base, event.get("thumbnail"))
    if thumbnail is not None and not thumbnail[0].is_file():
        thumbnail = None
    motion = event.get("peak_motion_pct")
    row = {
        "id": clip_id, "camera": CAMERA, "started_at": started.isoformat(), "ended_at": ended.isoformat(),
        "start_ts": started.timestamp(), "duration_s": duration,
        "peak_motion_pct": float(motion) if isinstance(motion, (int, float)) else None,
        "video": video[1].as_posix(), "size_bytes": video[0].stat().st_size,
        "thumbnail": thumbnail[1].as_posix() if thumbnail else None,
    }
    return row, [video, *([thumbnail] if thumbnail else [])]


# copies a file into the store, in the same place in the folder, unless the same one is already there
# it is copied under another name and renamed, so a copy that stops half way is never mistaken for the clip
def copy_in(store, source, relative):
    target = store / relative
    if target.is_file() and target.stat().st_size == source.stat().st_size:
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    shutil.copyfile(source, partial)
    os.replace(partial, target)
    return source.stat().st_size


def make_router(db):
    with db() as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS captures ("
            "id TEXT PRIMARY KEY, camera TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT NOT NULL, "
            "start_ts REAL NOT NULL, duration_s INTEGER NOT NULL, peak_motion_pct REAL, "
            "video TEXT NOT NULL, size_bytes INTEGER NOT NULL, thumbnail TEXT)"
        )
        conn.execute("CREATE INDEX IF NOT EXISTS captures_start ON captures (start_ts DESC)")

    router = APIRouter()
    importing = threading.Lock()  # one copy at a time
    seen = {"events": None}  # events.json as it was last read, so a new one is picked up without being asked

    def import_events(source):
        try:
            events = json.loads((source / "events.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            raise HTTPException(503, "I can't read events.json in the captures folder. Is the drive connected?")
        if not isinstance(events, list):
            raise HTTPException(502, "events.json isn't a list of events.")
        store = store_dir()
        found = [read_event(source, event) if isinstance(event, dict) else None for event in events]
        usable = [item for item in found if item is not None]
        # check there is room before starting, for what isn't in the store yet
        needed = sum(path.stat().st_size for _, files in usable for path, relative in files
                     if not (store / relative).is_file() or (store / relative).stat().st_size != path.stat().st_size)
        store.mkdir(parents=True, exist_ok=True)
        if needed and shutil.disk_usage(store).free < needed + SPARE_BYTES:
            raise HTTPException(507, f"There isn't room on this Mac for {needed // 1024 ** 2} MB of clips.")
        added = updated = 0
        try:
            for row, files in usable:
                for path, relative in files:
                    copy_in(store, path, relative)
                with db() as conn:
                    exists = conn.execute("SELECT 1 FROM captures WHERE id = ?", (row["id"],)).fetchone()
                    conn.execute(
                        "INSERT INTO captures (id, camera, started_at, ended_at, start_ts, duration_s, peak_motion_pct, "
                        "video, size_bytes, thumbnail) VALUES (:id, :camera, :started_at, :ended_at, :start_ts, "
                        ":duration_s, :peak_motion_pct, :video, :size_bytes, :thumbnail) ON CONFLICT(id) DO UPDATE SET "
                        "camera = excluded.camera, started_at = excluded.started_at, ended_at = excluded.ended_at, "
                        "start_ts = excluded.start_ts, duration_s = excluded.duration_s, "
                        "peak_motion_pct = excluded.peak_motion_pct, video = excluded.video, "
                        "size_bytes = excluded.size_bytes, thumbnail = excluded.thumbnail", row)
                if exists:
                    updated += 1
                else:
                    added += 1
        except OSError as e:  # the drive was unplugged part way, or the disk is full. what was copied is kept
            log.exception("copying the captures stopped")
            raise HTTPException(503, f"Copying the clips stopped after {added + updated} ({e.strerror or 'a file error'}).")
        skipped = len(events) - len(usable)
        log.info("captures: %d added, %d updated, %d skipped", added, updated, skipped)
        return {"added": added, "updated": updated, "skipped": skipped}

    def events_signature(source):
        stat = (source / "events.json").stat()
        return (str(source), stat.st_mtime_ns, stat.st_size)

    # copies what is new while the app carries on, for a first copy takes a while
    def sync():
        source = captures_dir()
        if source is None:
            return
        try:
            signature = events_signature(source)
        except OSError:
            return  # the drive isn't there, the copies already made still play
        if seen["events"] == signature or not importing.acquire(blocking=False):
            return
        seen["events"] = signature

        def work():
            try:
                import_events(source)
            except HTTPException as e:
                seen["events"] = None  # try again next time
                log.warning("captures: %s", e.detail)
            except Exception:
                seen["events"] = None
                log.exception("captures: the import failed")
            finally:
                importing.release()

        threading.Thread(target=work, daemon=True).start()

    def find(clip_id):
        with db() as conn:
            row = conn.execute("SELECT video, thumbnail FROM captures WHERE id = ?", (clip_id,)).fetchone()
        if row is None:
            raise HTTPException(404, "I don't have that capture.")
        return store_dir(), row

    @router.get("/captures")
    def list_captures(limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
        sync()
        store = store_dir()
        with db() as conn:
            total = conn.execute("SELECT COUNT(*) FROM captures").fetchone()[0]
            rows = conn.execute(
                f"SELECT {COLUMNS} FROM captures ORDER BY start_ts DESC LIMIT ? OFFSET ?", (limit, offset),
            ).fetchall()
        captures = []
        for row in rows:
            clip = dict(zip(KEYS, row))
            path = inside(store, row[7])
            clip["available"] = bool(path and path.is_file())  # false if the copy is gone from the store
            captures.append(clip)
        return {"captures": captures, "total": total}

    @router.api_route("/captures/{clip_id}/video", methods=["GET", "HEAD"])  # players ask with HEAD too
    def video(clip_id: str):
        store, row = find(clip_id)
        path = inside(store, row[0])
        if path is None or not path.is_file():
            raise HTTPException(503, "That recording isn't available. Its copy is missing from this Mac.")
        return FileResponse(path, media_type="video/mp4")

    @router.api_route("/captures/{clip_id}/thumbnail", methods=["GET", "HEAD"])
    def thumbnail(clip_id: str):
        store, row = find(clip_id)
        path = inside(store, row[1])
        if path is None or not path.is_file():
            raise HTTPException(404, "There is no thumbnail for that capture.")
        return FileResponse(path, media_type="image/jpeg")

    @router.post("/captures/import")
    def import_now():
        source = captures_dir()
        if source is None:
            raise HTTPException(409, "No captures folder is set up. Set CAPTURES_DIR, see data/README.md.")
        with importing:  # waits if a copy is already running
            result = import_events(source)
            seen["events"] = events_signature(source)
        return result

    return router, sync
