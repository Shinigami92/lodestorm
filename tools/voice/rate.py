"""Local listening page for the voice spike: python tools/voice/rate.py [port]   (default 8191)

Shows every local/voice/<round>/<character>/*.flac (new takes appear while a round renders), with (half) stars and a
note per take and a note per character, a Best view of each character's favorites across all rounds, duels
between tied favorites and a Settled view of what the game has: each voiced NPC's anchors and rendered lines. Takes are anonymous ("Take 7c2", from a hash of the file name) until rated, so the engine
name doesn't steer the ear. Everything is saved in the voice database (db.py); the page is rate.html.
"""

import hashlib
import json
import pathlib
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import lines
from characters import CHARACTERS

import db

PAGE = pathlib.Path(__file__).parent / "rate.html"


def tag(character: str, file: str) -> str:
    return hashlib.sha1(f"{character}/{file}".encode()).hexdigest()[:3]


def rounds() -> dict:
    """{"rounds": {round: {character: {"name", "role", "description", "note", "takes": [...]}}},
    "duels": {round: {character: [[winner, loser], ...]}}}; a duel of the Best view has the round "best"."""
    con = db.connect()
    takes: dict = {}
    for r in con.execute("select * from takes"):
        takes[(r["round"], r["character"], r["file"])] = dict(r)
    ratings = {(r["round"], r["character"], r["file"]): dict(r) for r in con.execute("select * from ratings")}
    notes = {(r["round"], r["character"]): r["note"] for r in con.execute("select * from notes")}
    out: dict = {}
    for folder in sorted(p for p in db.ROOT.iterdir() if p.is_dir()):
        for char_dir in sorted(p for p in folder.iterdir() if p.is_dir()):
            files = sorted(f.name for f in char_dir.glob("*.flac"))
            if not files:
                continue
            # Ordered and labeled by a hash, so neither gives the engine away and new takes don't relabel old ones
            files.sort(key=lambda f: tag(char_dir.name, f))
            c = CHARACTERS.get(char_dir.name, {})
            entry = {
                "name": c.get("name", char_dir.name),
                "role": c.get("role", ""),
                "description": c.get("description", ""),
                "note": notes.get((folder.name, char_dir.name), ""),
                "takes": [],
            }
            for f in files:
                key = (folder.name, char_dir.name, f)
                rating = ratings.get(key, {})
                entry["takes"].append(
                    takes.get(key, {"file": f})
                    | {
                        "round": folder.name,
                        "tag": tag(char_dir.name, f),
                        "stars": rating.get("stars", 0),
                        "note": rating.get("note", ""),
                    }
                )
            # Each round shows the description its takes were made from, not today's
            made_from = [t["description"] for t in entry["takes"] if t.get("description")]
            if made_from:
                entry["description"] = made_from[0]
            out.setdefault(folder.name, {})[char_dir.name] = entry
    duels: dict = {}
    for r in con.execute("select * from duels order by id"):
        duels.setdefault(r["round"], {}).setdefault(r["character"], []).append([r["winner"], r["loser"]])
    return {"rounds": out, "duels": duels}


def settled() -> dict:
    """The NPCs with anchors: {npc: {"name", "role", "languages": {language: voice.json's entry | {"lines": [{"file",
    "text"}]}}}}, the lines in the game's order; files are relative to assets/voice/."""
    profiles = lines.profiles()
    out = {}
    for npc in lines.voiced():
        info = json.loads((lines.SOURCE / npc / "voice.json").read_text(encoding="utf-8"))
        manifest = lines.load_manifest(npc)
        text = profiles[npc].read_text(encoding="utf-8")
        resource = text[text.rfind("[resource]") :]
        fields = dict(re.findall(r'^(display_name|role) = "(.*)"$', resource, re.MULTILINE))
        order = [lines.line_hash(line) for line in lines.npc_lines(npc, info.get("lines") == "reactions")]
        languages = {}
        for language, entry in info.items():
            if not isinstance(entry, dict) or "anchor" not in entry:
                continue
            rendered = manifest.get(language, {})
            found = [h for h in order if h in rendered and (lines.OUT / npc / language / f"{h}.ogg").exists()]
            languages[language] = entry | {
                "anchor": f"source/{npc}/{entry['anchor']}",
                "lines": [{"file": f"{npc}/{language}/{h}.ogg", "text": rendered[h]["text"]} for h in found],
            }
        out[npc] = {"name": fields.get("display_name", npc), "role": fields.get("role", ""), "languages": languages}
    return out


def save(data: dict) -> None:
    con = db.connect()
    if data["kind"] == "rating":
        con.execute(
            "insert or replace into ratings values (?, ?, ?, ?, ?, ?)",
            (data["round"], data["character"], data["file"], data["stars"], data["note"], db.now()),
        )
    elif data["kind"] == "note":
        con.execute("insert or replace into notes values (?, ?, ?)", (data["round"], data["character"], data["note"]))
    elif data["kind"] == "duel":
        # A new verdict on the same pair replaces the old one
        key = (data["round"], data["character"])
        for a, b in ((data["winner"], data["loser"]), (data["loser"], data["winner"])):
            con.execute(
                "delete from duels where round = ? and character = ? and winner = ? and loser = ?", (*key, a, b)
            )
        con.execute(
            "insert into duels (round, character, winner, loser, at) values (?, ?, ?, ?, ?)",
            (*key, data["winner"], data["loser"], db.now()),
        )
    elif data["kind"] == "reset_duels":
        con.execute("delete from duels where round = ? and character = ?", (data["round"], data["character"]))
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
        elif path == "/api/rounds":
            self.send(200, json.dumps(rounds()).encode(), "application/json")
        elif path.startswith("/audio/"):
            f = (db.ROOT / path[7:]).resolve()
            if db.ROOT.resolve() in f.parents and f.suffix == ".flac" and f.exists():
                self.send(200, f.read_bytes(), "audio/flac")
            else:
                self.send(404, b"", "text/plain")
        elif path == "/api/settled":
            self.send(200, json.dumps(settled()).encode(), "application/json")
        elif path.startswith("/voice/"):
            f = (lines.OUT / path[7:]).resolve()
            kinds = {".flac": "audio/flac", ".ogg": "audio/ogg"}
            if lines.OUT.resolve() in f.parents and f.suffix in kinds and f.exists():
                self.send(200, f.read_bytes(), kinds[f.suffix])
            else:
                self.send(404, b"", "text/plain")
        else:
            self.send(404, b"", "text/plain")

    def do_POST(self) -> None:
        if urllib.parse.urlparse(self.path).path == "/api/save":
            save(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
            self.send(200, b"{}", "application/json")
        else:
            self.send(404, b"", "text/plain")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8191
    db.connect()
    print(f"http://127.0.0.1:{port}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
