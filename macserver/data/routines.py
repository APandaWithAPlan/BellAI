"""Routines stored alongside tasks in the existing data server database."""
import json
import logging
from contextlib import contextmanager
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import sqlite3
from storage import db
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator

router = APIRouter()
log = logging.getLogger("bell_data.routines")


class Routine(BaseModel):
    id: UUID
    name: str = Field(min_length=1, max_length=100)
    time: str = Field(pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
    timezone: str = Field(max_length=100)
    actions: list[str] = Field(min_length=1, max_length=50)

    @field_validator("name", mode="before")
    @classmethod
    def trim_name(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("actions")
    @classmethod
    def validate_actions(cls, values):
        values = [value.strip() for value in values]
        if any(not value or len(value) > 500 for value in values):
            raise ValueError("Each action must contain 1–500 characters.")
        return values

    @field_validator("timezone")
    @classmethod
    def validate_timezone(cls, value):
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("Use an IANA timezone.")
        return value


@contextmanager
def database():
    try:
        with db() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS routines ("
                "id TEXT PRIMARY KEY, name TEXT NOT NULL, routine_time TEXT NOT NULL, "
                "timezone TEXT NOT NULL, actions TEXT NOT NULL)"
            )
            yield conn
    except sqlite3.Error:
        log.exception("Routine database operation failed")
        raise HTTPException(503, "Routine storage is unavailable. Please try again.")


def decode_row(row):
    return dict(id=row[0], name=row[1], time=row[2], timezone=row[3], actions=json.loads(row[4]))


@router.get("/routines")
def list_routines():
    with database() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id, name, routine_time, timezone, actions FROM routines ORDER BY routine_time, name, id")
        return {"routines": [decode_row(row) for row in cursor.fetchall()]}


@router.post("/routines")
def create_routine(body: Routine):
    with database() as conn:
        cursor = conn.cursor()
        # A stable client-generated ID makes retrying a timed-out save safe.
        cursor.execute(
            "INSERT INTO routines (id, name, routine_time, timezone, actions) VALUES (?, ?, ?, ?, ?) "
            "ON CONFLICT(id) DO NOTHING",
            (str(body.id), body.name, body.time, body.timezone, json.dumps(body.actions)),
        )
        cursor.execute("SELECT id, name, routine_time, timezone, actions FROM routines WHERE id = ?", (str(body.id),))
        saved = decode_row(cursor.fetchone())
        if saved != body.model_dump(mode="json"):
            raise HTTPException(409, "This routine was already saved with different details. Reopen Create to start a new routine.")
        return saved
