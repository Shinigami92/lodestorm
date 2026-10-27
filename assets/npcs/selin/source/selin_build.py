"""Selin, the colony council's member at Waypost Ostra: a calm, slim woman in her fifties with short dark hair, a long
pale coat worn open over a dark quilted station uniform, a colony patch, a belt with a buckle, fingerless gloves,
trousers with knee pads and lace-up boots (reference: the batch-8 concepts "selin_v1" and "selin_v2", see
docs/design/art.md, Art direction).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/selin/source/selin_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/selin/source/selin_build.py final    # renders, selin.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): her body is MakeHuman's (MPFB's sliders and a CC0 skin: her
skeleton, its weights and her hands); what she wears and her head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). The coat blends from the hips into both thighs below the waist. Skeleton "Skeleton" (Godot's humanoid
bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the shared pose code. Meshes: "Skin" (her hands are
what's left of it), "Outfit"; empty "HeadTop" on the head (where the name plate and the bubbles go).
The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

Writes assets/npcs/selin/selin.glb and its source assets/npcs/selin/source/selin.blend; renders go to
tmp/assets/npcs/selin/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "selin" / "source"
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
        "age": 0.75,  # about 55
        "muscle": 0.5,
        "weight": 0.45,
        "proportions": 0.5,
        "height": 0.55,
        "cupsize": 0.45,
        "firmness": 0.5,
        "race": {"asian": 0.1, "caucasian": 0.85, "african": 0.05},
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
# The open coat hangs loose below the waist; no bare skin below the collar; fingerless gloves (the generated ones'
# cuffs cut, the painted glove reaches up under the coat's sleeves); her head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "selin_trellis.glb",
    skirt=(0.03, 0.07),
    bare_arms=False,
    cuff=0.05,
    glove_up=0.05,
    center_cuffs=0.15,
    own_head=True,
    dents=(((-0.14, 0.3, 0.66), 0.05),),  # in the coat's back, on her right below the hip
)
PERSON = D.Person("Selin", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "selin", wrist_out=0.08)


def props(_arm: bpy.types.Object) -> None:
    """Nothing in her hands yet (her tablet comes with her work at the council's table)."""


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
        **fidgets.clips(body),
    }


def work(body: H.Body) -> list:
    return fidgets.work(body)


D.make(PERSON, props, clips, work, MODE, TAG)
