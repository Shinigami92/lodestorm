"""Wren, the ship's suit technician: a small, quick young woman in her early twenties with light olive skin
and a short black bob with teal tips, in a fitted light-grey technician jumpsuit with many pockets and
pushed-up sleeves, a teal collar light, fingerless gloves, a belt with small pouches, knee pads and black
boots (reference: the batch-10 concept "wren_v1", see docs/planned/crew.md).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/wren/source/wren_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/wren/source/wren_build.py final    # renders, wren.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): her body is MakeHuman's (MPFB's sliders and a CC0 skin: her
skeleton, its weights and her hands); what she wears and her head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (her hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

Writes assets/npcs/wren/wren.glb and its source assets/npcs/wren/source/wren.blend; renders go to
tmp/assets/npcs/wren/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "wren" / "source"
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
        "age": 0.48,  # about 22
        "muscle": 0.5,
        "weight": 0.4,
        "proportions": 0.5,
        "height": 0.42,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.2, "caucasian": 0.7, "african": 0.1},
    },
    "skin": "young_caucasian_female",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
}
# A jumpsuit (nothing hangs loose), the generated forearms in her own tone, fingerless gloves (the generated ones'
# cuffs cut, the painted glove reaches up the wrist); her head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "wren_trellis.glb",
    bare_arms=False,
    cuff=0.05,
    glove_up=0.05,
    center_cuffs=0.15,
    taper_cuffs=0.06,
    own_head=True,
)
# Her hands hang clear of the belt.
PERSON = D.Person("Wren", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "wren", wrist_out=0.07)


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
