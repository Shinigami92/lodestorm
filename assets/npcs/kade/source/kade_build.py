"""Kade, the depot master at Waypost Ostra: a broad, heavy-set man in his early fifties with a graying beard, a
stained pale work jacket and overalls with orange high-visibility stripes, a padded right shoulder guard, a strap
across the chest, a belt with pouches, a tool holder on the right thigh, knee pads, thick work gloves and heavy boots
(reference: the batch-8 concept "kade_v3", see docs/design/art.md, Art direction).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/kade/source/kade_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/kade/source/kade_build.py final    # renders, kade.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): his body is MakeHuman's (MPFB's sliders and a CC0 skin: his
skeleton, its weights and his hands); what he wears and his head (face, hair and beard, on the head's bone: it
doesn't blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and
trellis.json with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and
"Walk" from the shared pose code. Meshes: "Skin" (his hands are what's left of it), "Outfit"; empty "HeadTop" on the
head (where the name plate and the bubbles go).
The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

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
import fidgets
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
# generated gauntlets stay up to the wrist, the glove reaches under them); his head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "kade_trellis.glb",
    bare_arms=False,
    cuff=0.0,
    glove=(0.035, 0.035, 0.038),
    gloved=D.FULL,
    glove_up=0.05,
    center_cuffs=0.15,
    own_head=True,
)
# His hands hang clear of the belt's pouches.
PERSON = D.Person("Kade", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "kade", wrist_out=0.12)


def props(_arm: bpy.types.Object) -> None:
    """Nothing in his hands yet (his slate comes with his work at the counter)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
        **fidgets.clips(body),
    }


def work(body: H.Body) -> list:
    return fidgets.work(body)


D.make(PERSON, props, clips, work, MODE, TAG)
