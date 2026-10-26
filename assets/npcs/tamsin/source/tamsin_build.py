"""Tamsin, the ship's pilot: a lean woman in her late thirties with freckles and auburn hair in a low bun, a
headset with a microphone boom, a worn dark navy flight jacket with a high collar over a charcoal flight
suit, a blue collar light, fingerless flight gloves, padded knees and tall laced boots (reference: the
batch-10 concept "tamsin_v1", see docs/planned/crew.md).

Run from the repo root (see docs/TECHNICAL.md, People):
    tools/blender.sh assets/npcs/tamsin/source/tamsin_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/tamsin/source/tamsin_build.py final    # renders, tamsin.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): her body is MakeHuman's (MPFB's sliders and a CC0 skin: her
skeleton, its weights and her hands); what she wears and her head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (her hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

Writes assets/npcs/tamsin/tamsin.glb and its source assets/npcs/tamsin/source/tamsin.blend; renders go to
tmp/assets/npcs/tamsin/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "tamsin" / "source"
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
        "gender": 0.0,
        "age": 0.6,  # about 38
        "muscle": 0.55,
        "weight": 0.4,
        "proportions": 0.5,
        "height": 0.55,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05},
    },
    "skin": "middleage_caucasian_female",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
}
# A flight jacket over a flight suit (nothing hangs loose), no bare skin below the collar, fingerless gloves (the
# generated ones' cuffs cut, the painted glove reaches up under the sleeves); her head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "tamsin_trellis.glb",
    bare_arms=False,
    cuff=0.05,
    glove_up=0.05,
    center_cuffs=0.15,
    own_head=True,
)
# Her hands hang clear of the belt.
PERSON = D.Person("Tamsin", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "tamsin", wrist_out=0.08)


def props(_arm: bpy.types.Object) -> None:
    """Nothing in her hands yet (what she works with comes with her work at her post)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
    }


def work(_body: H.Body) -> list:
    return []


D.make(PERSON, props, clips, work, MODE, TAG)
