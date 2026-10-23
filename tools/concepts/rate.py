"""Local rating page for the concept batches: python tools/concepts/rate.py [port]   (default 8190)

Shows every local/concepts/<batch>/<subject>/*.png (new images appear while a batch renders), with stars and a
note per image, a note per subject and duels: when the best images of a subject are tied, pick the better of two
until they are ranked. A "Best" view shows each subject's top image; the viewer rates with the keyboard (? lists
the keys). Everything is saved in the concept database (db.py).
"""

import ast
import itertools
import json
import pathlib
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import db

HERE = pathlib.Path(__file__).parent
PAGE = HERE / "rate.html"


def describe(batch: str) -> tuple[str, str]:
    """A short title and the whole description from a batch module's docstring ("Batch 8: Waypost Ostra (...)")."""
    module = HERE / "batches" / f"{batch}.py"
    if not module.exists():
        return "", ""
    doc = ast.get_docstring(ast.parse(module.read_text(encoding="utf-8"))) or ""
    text = re.sub(r"\n*Usage:.*", "", doc, flags=re.DOTALL)
    about = re.sub(r"^Batch \d+:\s*", "", " ".join(text.split()))
    about = about[:1].upper() + about[1:]
    # The short title ends before the first parenthesis, colon, comma or full stop
    return re.split(r" \(|[:,.]", about, maxsplit=1)[0], about


def natural(path: pathlib.Path) -> list:
    """Sort key putting batch10 after batch9."""
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", path.name)]


def batches() -> dict[str, dict]:
    """{batch: {"title", "about", "rated", "total", "subjects": {subject: [file, ...]}}}, in batch number order."""
    con = db.connect()
    out: dict[str, dict] = {}
    for b in sorted((p for p in db.ROOT.iterdir() if p.is_dir()), key=natural):
        subjects = {s.name: sorted(f.name for f in s.glob("*.png")) for s in sorted(b.iterdir()) if s.is_dir()}
        if not any(subjects.values()):
            continue
        stars = {
            (r["subject"], r["file"])
            for r in con.execute("select subject, file from ratings where batch = ? and stars > 0", (b.name,))
        }
        title, about = describe(b.name)
        out[b.name] = {
            "title": title,
            "about": about,
            "total": sum(len(f) for f in subjects.values()),
            "rated": sum((s, f) in stars for s, files in subjects.items() for f in files),
            "subjects": subjects,
        }
    return out


def state(batch: str) -> dict:
    """Ratings, notes and duel wins of one batch: {subject: {"files": {file: {...}}, "note": str, "duels": [...]}}."""
    con = db.connect()
    out: dict = {}

    def subject(name: str) -> dict:
        return out.setdefault(name, {"files": {}, "note": "", "duels": []})

    for r in con.execute("select subject, file, stars, note from ratings where batch = ?", (batch,)):
        subject(r["subject"])["files"][r["file"]] = {"stars": r["stars"], "note": r["note"]}
    for r in con.execute("select subject, note from notes where batch = ?", (batch,)):
        subject(r["subject"])["note"] = r["note"]
    for r in con.execute("select subject, winner, loser from duels where batch = ? order by id", (batch,)):
        subject(r["subject"])["duels"].append([r["winner"], r["loser"]])
    for r in con.execute("select subject, file, prompt from images where batch = ?", (batch,)):
        subject(r["subject"])["files"].setdefault(r["file"], {"stars": 0, "note": ""})["prompt"] = r["prompt"]
    return out


def save(batch: str, data: dict) -> None:
    con = db.connect()
    kind, subject = data["kind"], data["subject"]
    if kind == "rating":
        con.execute(
            "insert or replace into ratings values (?, ?, ?, ?, ?, ?)",
            (batch, subject, data["file"], data["stars"], data["note"], db.now()),
        )
    elif kind == "note":
        con.execute("insert or replace into notes values (?, ?, ?)", (batch, subject, data["note"]))
    elif kind == "duel":
        # A new verdict on the same pair replaces the old one
        pair = (data["winner"], data["loser"])
        for a, b in itertools.permutations(pair):
            con.execute(
                "delete from duels where batch = ? and subject = ? and winner = ? and loser = ?", (batch, subject, a, b)
            )
        con.execute(
            "insert into duels (batch, subject, winner, loser, at) values (?, ?, ?, ?, ?)",
            (batch, subject, *pair, db.now()),
        )
    elif kind == "reset_duels":
        con.execute("delete from duels where batch = ? and subject = ?", (batch, subject))
    con.commit()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args: object) -> None:
        pass

    def send(self, code: int, body: bytes, kind: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        if path == "/":
            self.send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        elif path == "/api/batches":
            self.send(200, json.dumps(batches()).encode(), "application/json")
        elif path.startswith("/api/state/"):
            self.send(200, json.dumps(state(path.rsplit("/", 1)[1])).encode(), "application/json")
        elif path.startswith("/img/"):
            f = (db.ROOT / path[5:]).resolve()
            if db.ROOT.resolve() in f.parents and f.suffix == ".png" and f.exists():
                self.send(200, f.read_bytes(), "image/png")
            else:
                self.send(404, b"", "text/plain")
        else:
            self.send(404, b"", "text/plain")

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path.startswith("/api/save/"):
            save(path.rsplit("/", 1)[1], json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
            self.send(200, b"{}", "application/json")
        else:
            self.send(404, b"", "text/plain")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8190
    db.connect()
    print(f"http://127.0.0.1:{port}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
