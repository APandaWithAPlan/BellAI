# BellAi Data Server (Mac)

## Overview

**BellAi Data Server** keeps the app's saved data, like the to-do list, in a SQLite file on the Mac. It replaces the Firebase backend, so nothing is stored outside your own machines. The app reaches it over Tailscale, and being on your tailnet is the login, so there are no accounts.

It stores one JSON object (`{"tasks": [...]}` and whatever else the app saves) in a single row of `bellai.db`.

## Routines

Home → Routine → Create saves a name, local time, timezone, and ordered text actions.
The app uses the same data server address as Tasks (port 8001). Routines live in a
separate `routines` table inside the same `DATA_DB` / `bellai.db` SQLite database;
the table is created automatically. No additional database configuration is needed.
Restart the data server after installing the updated requirements.

`GET /routines` returns `{"routines": [...]}`. `POST /routines` accepts `id` (UUID),
`name` (1–100 characters), `time` (`HH:mm`), `timezone` (IANA), and `actions`
(1–50 strings, each 1–500 characters), and returns the saved routine. Repeated
requests with the same ID and content do not create duplicates; different content
for an existing ID returns 409. Task saves do not overwrite routines.
`DELETE /routines/{id}` removes a routine and returns 204, including if it was already deleted.

These endpoints store routines. The iOS app schedules daily local notifications
in each routine's saved timezone after notification permission is granted. It
refreshes schedules when opened and after saving. Already scheduled reminders
work without the server; changes made elsewhere require opening the app to sync.
Notifications remind you of the actions; they do not execute them.

Run `python -m unittest discover -s tests` from this directory for validation,
retry, and persistence checks against a temporary database.

## Getting Started

### Prerequisites

* Software: `uv` (`brew install uv`). The script installs Python 3.11 and everything else into `.venv`.
* Network: The app connects to port `8001`, so the Mac must be reachable over Tailscale as `ai-server`.

### How to Enable / Access

1. Run `./start_data.sh` in this folder.
2. Open http://127.0.0.1:8001/health. It should show `{"ok": true}`.

## How to Use It

1. **Use it from the app:** The app calls `GET /data` on launch and `PUT /data` with `{"data": {...}}` after every change. `GET` returns `{"data": null}` until something has been saved. Data over 100 KB is refused.
2. **Change settings:** Set these before `./start_data.sh`: `DATA_DB` (path of the database file), `HOST` and `PORT`. If you change the port, set `DATA_SERVER_HOST` in `iOS-App/Config/Debug.xcconfig` to match.
3. **Back it up:** Copy `bellai.db` while the server is stopped, or run `sqlite3 bellai.db ".backup backup.db"`. This file is the only copy of your data.
4. **Reset it:** Stop the server and delete `bellai.db`. It is made again on the next start.

> ⚠️ **Warning:** There is no password, so anyone who can reach the port can read and replace your data. Keep the port off the open internet, and set `HOST` to the Mac's Tailscale address to keep it off your local network too.
