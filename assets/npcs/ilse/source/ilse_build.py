"""Ilse, the ship's medic: a thin, upright woman in her mid-fifties with ash-blond hair going gray in a low
knot and thin glasses, in a knee-length pale medical coat with a high collar, a white collar light and a
white cross, a dark harness with medical pouches, a belt with pouches, black gloves, knee pads and tall
strapped boots (reference: the batch-10 concept "ilse_v1", see docs/planned/crew.md).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/ilse/source/ilse_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/ilse/source/ilse_build.py final    # renders, ilse.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): her body is MakeHuman's (MPFB's sliders and a CC0 skin: her
skeleton, its weights and her hands); what she wears and her head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (her hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

Writes assets/npcs/ilse/ilse.glb and its source assets/npcs/ilse/source/ilse.blend; renders go to
tmp/assets/npcs/ilse/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "ilse" / "source"
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
        "gender": 0.0,
        "age": 0.73,  # about 55
        "muscle": 0.45,
        "weight": 0.35,
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
# The coat hangs loose below the waist; no bare skin below the collar; black gloves over her whole hands (the
# generated ones' cuffs stay, the glove reaches under them); her head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "ilse_trellis.glb",
    skirt=(0.03, 0.07),
    bare_arms=False,
    cuff=0.0,
    glove=(0.04, 0.04, 0.043),
    gloved=D.FULL,
    glove_up=0.05,
    center_cuffs=0.15,
    own_head=True,
)
# Her hands hang clear of the coat.
PERSON = D.Person("Ilse", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "ilse", wrist_out=0.08)


def props(_arm: bpy.types.Object) -> None:
    """Nothing in her hands yet (what she works with comes with her work at her post)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
        **fidgets.clips(body),
    }


def work(body: H.Body) -> list:
    return fidgets.work(body)


D.make(PERSON, props, clips, work, MODE, TAG)
