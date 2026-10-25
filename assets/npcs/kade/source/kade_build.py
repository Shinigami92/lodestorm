"""Kade, the depot master at Waypost Ostra: a broad, heavy-set man in his early fifties with a graying beard, a
stained pale work jacket and overalls with orange high-visibility stripes, a padded right shoulder guard, a strap
across the chest, a belt with pouches, a tool holder on the right thigh, knee pads, thick work gloves and heavy boots
(reference: the batch-8 concept "kade_v3", see GAME_DESIGN.md, Art direction).

Run from the repo root (see docs/TECHNICAL.md, People):
    tools/blender.sh assets/npcs/kade/source/kade_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/kade/source/kade_build.py final    # renders, kade.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): his body is MakeHuman's (MPFB's sliders and a CC0 skin: his
skeleton, its weights and his hands); what he wears and his head (face, hair and beard, on the head's bone: it
doesn't blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and
trellis.json with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and
"Walk" from the shared pose code. Meshes: "Skin" (his hands are what's left of it), "Outfit"; empty "HeadTop" on the
head (where the name plate and the bubbles go).

Writes assets/npcs/kade/kade.glb and its source assets/npcs/kade/source/kade.blend; renders go to tmp/assets/npcs/kade/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "kade" / "source"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy

import common as C
import dressing as D
import humanoid as H

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

BODY = {
    "macro": {
        "gender": 1.0,
        "age": 0.75,  # about 55
        "muscle": 0.65,
        "weight": 0.7,
        "proportions": 0.5,
        "height": 0.55,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05},
    },
    "skin": "old_caucasian_male",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
}
# Overalls (nothing hangs loose), no bare skin below the collar, thick black gloves over his whole hands (their
# generated gauntlets stay up to the wrist); his head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "kade_trellis.glb",
    bare_arms=False,
    cuff=0.0,
    glove=(0.035, 0.035, 0.038),
    gloved=D.FULL,
    own_head=True,
)
PERSON = D.Person("Kade", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "kade")


def props(_arm: bpy.types.Object) -> None:
    """Nothing in his hands yet (his slate comes with his work at the counter)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
    }


def work(_body: H.Body) -> list:
    return []


D.make(PERSON, props, clips, work, MODE, TAG)
