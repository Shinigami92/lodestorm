"""The local voice database: what made each take, its rating and notes, and the duels between tied favorites.

It lives in local/voice/voice.db (ignored by git, like the takes next to it in local/voice/<round>/<character>/).
"""

import pathlib
import sqlite3
from datetime import UTC, datetime

ROOT = pathlib.Path(__file__).resolve().parents[2] / "local" / "voice"
PATH = ROOT / "voice.db"

SCHEMA = """
create table if not exists takes (
    round text, character text, file text, engine text, model text, seed integer, language text,
    description text, text text, source text, seconds real, created text, primary key (round, character, file));
create table if not exists ratings (
    round text, character text, file text, stars real, note text, updated text,
    primary key (round, character, file));
create table if not exists notes (round text, character text, note text, primary key (round, character));
create table if not exists duels (id integer primary key, round text, character text, winner text, loser text, at text);
"""


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def connect() -> sqlite3.Connection:
    ROOT.mkdir(parents=True, exist_ok=True)
    # Godot must not import the generated takes
    (ROOT / ".gdignore").touch()
    con = sqlite3.connect(PATH)
    con.row_factory = sqlite3.Row
    con.executescript(SCHEMA)
    return con
