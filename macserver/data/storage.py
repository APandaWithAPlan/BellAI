"""Shared database location and transactions for tasks and routines."""
import os
import sqlite3
from contextlib import contextmanager

DB_PATH = os.environ.get("DATA_DB") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "bellai.db")


@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    try:
        with conn:
            yield conn
    finally:
        conn.close()
