"""Hollis, the ship's miner mechanic: a wiry, slightly stooped man in his late sixties with deeply tanned
leathery skin, a white stubble beard and long thin gray hair, a scuffed hard hat with a headlamp, a faded
canvas work jacket open over a dark green shirt, a green collar light, old prospector's trousers with
leather knee pads, greasy bare hands and heavy boots (reference: the batch-10 concept "hollis_v2", see
docs/planned/crew.md).

Run from the repo root (see docs/TECHNICAL.md, People):
    tools/blender.sh assets/npcs/hollis/source/hollis_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/hollis/source/hollis_build.py final    # renders, hollis.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): his body is MakeHuman's (MPFB's sliders and a CC0 skin: his
skeleton, its weights and his hands); what he wears and his head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (his hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

Writes assets/npcs/hollis/hollis.glb and its source assets/npcs/hollis/source/hollis.blend; renders go to
tmp/assets/npcs/hollis/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "hollis" / "source"
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
        "age": 0.83,  # about 68
        "muscle": 0.45,
        "weight": 0.4,
        "proportions": 0.5,
        "height": 0.5,
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
# A canvas jacket (nothing hangs loose), his bare hands; his head is the generated one (with the hard hat).
FIT = D.Fit(
    SOURCE / "trellis" / "hollis_trellis.glb",
    bare_arms=False,
    cuff=0.0,
    gloved=D.BARE,
    center_cuffs=0.15,
    taper_cuffs=0.06,
    own_head=True,
)
# His hands hang clear of the jacket.
PERSON = D.Person("Hollis", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "hollis", wrist_out=0.1)


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
