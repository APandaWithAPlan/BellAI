# BellAi Data Server (Mac)

## Overview

**BellAi Data Server** keeps the app's saved data, like the to-do list, in a SQLite file on the Mac. It replaces the Firebase backend, so nothing is stored outside your own machines. The app reaches it over Tailscale, and being on your tailnet is the login, so there are no accounts.

It stores one JSON object (`{"tasks": [...]}` and whatever else the app saves) in a single row of `bellai.db`. It also keeps the home camera's earlier motion clips, the app's **previous captures**: one row per clip in the `captures` table. Each clip and its thumbnail is copied onto the Mac's own disk, so the previous captures play whether or not the drive they came from is still connected. It also logs the songs played in Apple Music, one row per play in the `song_plays` table, so the app can learn the listener's taste.

## Getting Started

### Prerequisites

* Software: `uv` (`brew install uv`). The script installs Python 3.11 and everything else into `.venv`.
* Network: The app connects to port `8001`, so the Mac must be reachable over Tailscale as `ai-server`.
* Recordings (optional): The camera's `events.json` and its dated folders of `.mp4` clips and `.jpg` thumbnails, copied from the Pi's `/var/lib/homecam/recordings` (see [Home Camera](../../Camera/README.md)) to a folder on the Mac or an attached drive, for example `rsync -av bella@100.85.250.95:/var/lib/homecam/recordings/ /Volumes/Untitled/camera-recordings/`. The clips are H.264, which iPhones play. The Mac needs room for a copy, about the same size as the folder (1.2 GB for 130 clips) plus 2 GB to spare.

### How to Enable / Access

1. Run `./start_data.sh` in this folder.
2. Open http://127.0.0.1:8001/health. It should show `{"ok": true}`.
3. To list the camera's clips, add `CAPTURES_DIR=/path/to/recordings` to `../config/bellai.env` (or set it before `./start_data.sh`) and restart. The clips are copied in the background when the server starts, so the first time takes a minute or two (the log says `captures: 130 added`) and clips appear in the app as they are copied.

## How to Use It

1. **Use it from the app:** The app calls `GET /data` on launch and `PUT /data` with `{"data": {...}}` after every change. `GET` returns `{"data": null}` until something has been saved. Data over 100 KB is refused.
2. **See the previous captures:** The app's Security screen lists the latest clips under **Previous captures** and opens all of them by day. A tap plays the clip, streamed from this Mac, and it can be scrubbed. From the API: `GET /captures?limit=100&offset=0` returns `{"captures": [...], "total": 130}`, newest first, each with `id`, `started_at`, `ended_at`, `duration_s`, `peak_motion_pct`, `size_bytes` and `available`. `GET /captures/<id>/video` returns the mp4 (range requests are supported, which is how the app seeks) and `GET /captures/<id>/thumbnail` the picture.
3. **Add new clips:** Copy the Pi's recordings into the folder again. The next time the app (or `GET /captures`) asks, a changed `events.json` is noticed and the new clips are copied in the background. `curl -X POST http://127.0.0.1:8001/captures/import` does it now and waits until it is done, answering `{"added": 3, "updated": 0, "skipped": 1}`. Clips that are already copied are not copied again. Skipped means an event without its clip in the folder, which the Pi deletes after a few days, or one with a bad id or path.
4. **When the drive is out:** Everything already copied still lists and plays. Only importing needs the drive, and answers `503` until it is back. When the Pi deletes an old clip, the copy here stays.
5. **Where the copies are:** In `~/Library/Application Support/BellAI/captures`, in the same dated folders as the recordings. It is not in Documents, so iCloud doesn't sync it. Set `CAPTURES_STORE` to use another folder. A clip whose copy has gone from that folder is marked `available: false`, and the app greys it out as **Not available right now**. Import it again with the drive connected to get it back. The database holds each clip's details, and the video is not in it, so it stays small. If the disk doesn't have room for the new clips, nothing is copied and the import answers `507`.
6. **Change settings:** Set these before `./start_data.sh`: `DATA_DB` (path of the database file), `CAPTURES_DIR` (the recordings folder), `CAPTURES_STORE` (where the copies go), `HOST` and `PORT`. If you change the port, set `DATA_SERVER_HOST` in `iOS-App/Config/Debug.xcconfig` to match.
7. **Back it up:** Copy `bellai.db` while the server is stopped, or run `sqlite3 bellai.db ".backup backup.db"`. This file is the only copy of your data. The clips are in the store folder, so back that up too.
8. **Run the checks:** `.venv/bin/python tests/test_captures.py` starts its own server with a made up camera folder and store, and checks the copying, the list, range requests, the drive being unplugged, a full disk, and that nothing outside the folder can be asked for.
9. **Log songs:** The app posts new Apple Music plays with `POST /music/plays` and `{"plays": [{"song_id", "title", "artist", "genres", "played_at"}]}` (up to 200 at a time, `played_at` as an ISO 8601 date), and reads them back with `GET /music/plays?limit=500`, newest first. `.venv/bin/python tests/test_music.py` checks both.
10. **Reset it:** Stop the server and delete `bellai.db`. It is made again on the next start, and the captures are imported again from the recordings folder. Deleting the store folder as well means copying them all again.

> ⚠️ **Warning:** There is no password, so anyone who can reach the port can read and replace your data and watch the camera's clips. Keep the port off the open internet, and set `HOST` to the Mac's Tailscale address to keep it off your local network too.
