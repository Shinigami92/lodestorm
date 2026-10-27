"""Rook, the captain of a rival prospecting crew at Waypost Ostra: a lean, confident man in his thirties with short
messy hair, a scar across his cheek and a cocky grin, in a scuffed pale armored mining suit over a dark quilted
undersuit, a thick neck seal, a crew patch with a star on the chest plate, a leather belt with pouches, a tool holder
on the right thigh, knee guards, padded gloves and heavy boots (reference: the batch-8 concepts "rook_v1" and
"rook_v4", see docs/design/art.md, Art direction; his helmet under the arm comes later as a held prop).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/rook/source/rook_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/rook/source/rook_build.py final    # renders, rook.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): his body is MakeHuman's (MPFB's sliders and a CC0 skin: his
skeleton, its weights and his hands); what he wears and his head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (his hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

Writes assets/npcs/rook/rook.glb and its source assets/npcs/rook/source/rook.blend; renders go to tmp/assets/npcs/rook/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "rook" / "source"
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
        "age": 0.58,  # about 35
        "muscle": 0.65,
        "weight": 0.45,
        "proportions": 0.55,
        "height": 0.6,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05},
    },
    "skin": "middleage_caucasian_male",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
}
# An armored suit (nothing hangs loose), no bare skin below the collar, dark padded gloves over his whole hands (the
# generated forearm plates stay, the glove reaches under them); his head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "rook_trellis.glb",
    bare_arms=False,
    hand_reach=0.22,
    cuff=0.0,
    glove=(0.05, 0.05, 0.055),
    gloved=D.FULL,
    glove_up=0.05,
    center_cuffs=0.15,
    own_head=True,
)
# His hands hang clear of the belt's pouches and the thigh plates.
PERSON = D.Person("Rook", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "rook", wrist_out=0.13)


def props(_arm: bpy.types.Object) -> None:
    """Nothing in his hands yet (his helmet under the arm comes with his talk gestures)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
    }


def work(_body: H.Body) -> list:
    return []


D.make(PERSON, props, clips, work, MODE, TAG)
