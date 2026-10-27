"""Okoro, the ship's engineer: a tall, upright man of about fifty with dark brown skin, a shaved head and a
short graying beard, welding goggles pushed up on his head, rust-brown bib overalls over a stained pale
work jacket with burn marks on the sleeves, an orange collar light, a heavy tool belt, leather work gloves
and heavy boots (reference: the batch-10 concept "okoro_v2", see docs/planned/crew.md).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/okoro/source/okoro_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/okoro/source/okoro_build.py final    # renders, okoro.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): his body is MakeHuman's (MPFB's sliders and a CC0 skin: his
skeleton, its weights and his hands); what he wears and his head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (his hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

Writes assets/npcs/okoro/okoro.glb and its source assets/npcs/okoro/source/okoro.blend; renders go to
tmp/assets/npcs/okoro/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "okoro" / "source"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy

import common as C
import dressing as D
import fidgets
import humanoid as H

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

BODY = {
    "macro": {
        "gender": 1.0,
        "age": 0.69,  # about 50
        "muscle": 0.6,
        "weight": 0.5,
        "proportions": 0.5,
        "height": 0.62,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.0, "caucasian": 0.05, "african": 0.95},
    },
    "skin": "middleage_african_male",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
}
# Overalls (nothing hangs loose), no bare skin below the collar, leather work gloves over his whole hands (their
# generated gauntlets stay up to the wrist, the glove reaches under them); his head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "okoro_trellis.glb",
    bare_arms=False,
    cuff=0.0,
    glove=(0.04, 0.04, 0.043),
    gloved=D.FULL,
    glove_up=0.05,
    center_cuffs=0.15,
    own_head=True,
)
# His hands hang clear of the tool belt.
PERSON = D.Person("Okoro", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "okoro", wrist_out=0.12)


def props(_arm: bpy.types.Object) -> None:
    """Nothing in his hands yet (what he works with comes with his work at his post)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
        **fidgets.clips(body),
    }


def work(body: H.Body) -> list:
    return fidgets.work(body)


D.make(PERSON, props, clips, work, MODE, TAG)
