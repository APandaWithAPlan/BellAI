# bell music log (mac): the songs the user has played in Apple Music, so BellAI can learn their taste
# the app reads what is new in Apple Music's history and posts it here, then reads it back to suggest songs
#
# POST /music/plays {"plays": [{"song_id", "title", "artist", "genres": [...], "played_at"}]} -> {"added": 3}
# GET /music/plays?limit=500 -> {"plays": [...]}, newest first
#
# played_at is when the app noticed the play, since Apple Music's history has no times
from datetime import datetime

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

MAX_PLAYS_PER_POST = 200


class Play(BaseModel):
    song_id: str = Field(min_length=1, max_length=64)
    title: str = Field(max_length=300)
    artist: str = Field(max_length=300)
    genres: list[str] = Field(default_factory=list, max_length=10)
    played_at: str = Field(max_length=40)  # ISO 8601


class Plays(BaseModel):
    plays: list[Play]


def make_router(db):
    with db() as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS song_plays ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, song_id TEXT NOT NULL, title TEXT NOT NULL, "
            "artist TEXT NOT NULL, genres TEXT NOT NULL, played_at TEXT NOT NULL, played_ts REAL NOT NULL)"
        )
        conn.execute("CREATE INDEX IF NOT EXISTS song_plays_time ON song_plays (played_ts DESC)")

    router = APIRouter()

    @router.post("/music/plays")
    def add_plays(body: Plays):
        if len(body.plays) > MAX_PLAYS_PER_POST:
            raise HTTPException(413, f"Send at most {MAX_PLAYS_PER_POST} plays at a time.")
        rows = []
        for play in body.plays:
            try:
                stamp = datetime.fromisoformat(play.played_at.replace("Z", "+00:00")).timestamp()
            except ValueError:
                raise HTTPException(422, "`played_at` must be an ISO 8601 date.")
            rows.append((play.song_id, play.title, play.artist, "\n".join(play.genres), play.played_at, stamp))
        with db() as conn:
            conn.executemany(
                "INSERT INTO song_plays (song_id, title, artist, genres, played_at, played_ts) VALUES (?, ?, ?, ?, ?, ?)",
                rows,
            )
        return {"added": len(rows)}

    @router.get("/music/plays")
    def list_plays(limit: int = Query(500, ge=1, le=2000)):
        with db() as conn:
            rows = conn.execute(
                "SELECT song_id, title, artist, genres, played_at FROM song_plays ORDER BY played_ts DESC, id DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return {"plays": [
            {"song_id": r[0], "title": r[1], "artist": r[2], "genres": r[3].split("\n") if r[3] else [], "played_at": r[4]}
            for r in rows
        ]}

    return router
