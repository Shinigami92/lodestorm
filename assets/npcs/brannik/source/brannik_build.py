"""Brannik, the ship's quartermaster: a broad, heavy man in his early sixties with close-cropped gray-white
hair and a gray stubble beard, in a dark olive padded armorer's vest with magazine pouches over a charcoal
work jumpsuit with rolled sleeves, a violet collar light, a belt with leather pouches and a key ring, leather
knee pads, wristbands and heavy boots (reference: the batch-10 concept "brannik_v2", see
docs/planned/crew.md).

Run from the repo root (see docs/TECHNICAL.md, People):
    tools/blender.sh assets/npcs/brannik/source/brannik_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/brannik/source/brannik_build.py final    # renders, brannik.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): his body is MakeHuman's (MPFB's sliders and a CC0 skin: his
skeleton, its weights and his hands); what he wears and his head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (his hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

Writes assets/npcs/brannik/brannik.glb and its source assets/npcs/brannik/source/brannik.blend; renders go to
tmp/assets/npcs/brannik/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "brannik" / "source"
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
        "age": 0.79,  # about 62
        "muscle": 0.6,
        "weight": 0.75,
        "proportions": 0.5,
        "height": 0.6,
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
# A padded vest over a jumpsuit (nothing hangs loose), the generated forearms in his own tone, his bare hands (they
# hang below the waist in the concept: the arm's line is found down there too); his head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "brannik_trellis.glb",
    arms_below=0.3,
    bare_arms=False,
    cuff=0.0,
    gloved=D.BARE,
    center_cuffs=0.15,
    taper_cuffs=0.06,
    own_head=True,
)
# His hands hang clear of the belt's pouches.
PERSON = D.Person("Brannik", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "brannik", wrist_out=0.11)


def props(_arm: bpy.types.Object) -> None:
    """Nothing in his hands yet (what he works with comes with his work at his post)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
    }


def work(_body: H.Body) -> list:
    return []


D.make(PERSON, props, clips, work, MODE, TAG)
