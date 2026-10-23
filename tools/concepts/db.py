"""The local concept database: what made each image, its rating and the duels between close ones.

It lives in local/concepts/concepts.db (ignored by git, like the images next to it).
"""

import pathlib
import sqlite3
from datetime import UTC, datetime

ROOT = pathlib.Path(__file__).resolve().parents[2] / "local" / "concepts"
PATH = ROOT / "concepts.db"

SCHEMA = """
create table if not exists images (
    batch text, subject text, file text, style text, seed integer, size integer, model text, prompt text,
    created text, primary key (batch, subject, file));
create table if not exists ratings (
    batch text, subject text, file text, stars integer, note text, updated text,
    primary key (batch, subject, file));
create table if not exists notes (batch text, subject text, note text, primary key (batch, subject));
create table if not exists duels (
    id integer primary key, batch text, subject text, winner text, loser text, at text);
"""


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def connect() -> sqlite3.Connection:
    ROOT.mkdir(parents=True, exist_ok=True)
    # Godot must not import the generated images
    (ROOT / ".gdignore").touch()
    con = sqlite3.connect(PATH)
    con.row_factory = sqlite3.Row
    con.executescript(SCHEMA)
    return con
