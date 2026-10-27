"""Dace, the ship's gunsmith: a wiry man in his mid-thirties with medium brown skin, stubble and black hair
shaved at the sides, goggles pushed up on his forehead, a heavy scorched leather apron from the chest to
the knees over a charcoal work shirt with rolled sleeves, a red collar light, a wide leather belt, soot on
his forearms, cargo trousers and strapped boots (reference: the batch-10 concept "dace_v2", see
docs/planned/crew.md).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/dace/source/dace_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/dace/source/dace_build.py final    # renders, dace.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): his body is MakeHuman's (MPFB's sliders and a CC0 skin: his
skeleton, its weights and his hands); what he wears and his head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (his hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

Writes assets/npcs/dace/dace.glb and its source assets/npcs/dace/source/dace.blend; renders go to
tmp/assets/npcs/dace/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "dace" / "source"
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
        "age": 0.58,  # about 35
        "muscle": 0.55,
        "weight": 0.4,
        "proportions": 0.5,
        "height": 0.55,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.15, "caucasian": 0.6, "african": 0.25},
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
# The apron hangs loose below the waist; the generated forearms in his own tone, his bare hands; his head is the
# generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "dace_trellis.glb",
    skirt=(0.03, 0.07),
    bare_arms=False,
    cuff=0.0,
    gloved=D.BARE,
    center_cuffs=0.15,
    taper_cuffs=0.06,
    own_head=True,
)
# His hands hang clear of the apron.
PERSON = D.Person("Dace", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "dace", wrist_out=0.08)


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
