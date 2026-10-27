"""Fenna, the ship's cook: a sturdy, round-faced Black woman in her mid-forties with dark curly hair tied
back under a short brimmed cap, a calm smile, in a double-breasted off-white cook's jacket with rolled
sleeves, a pink collar light, a long dark apron with a towel through its string, a leather belt, dark
trousers and laced boots (reference: the batch-10 concept "fenna_v3", see docs/planned/crew.md).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/fenna/source/fenna_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/fenna/source/fenna_build.py final    # renders, fenna.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): her body is MakeHuman's (MPFB's sliders and a CC0 skin: her
skeleton, its weights and her hands); what she wears and her head (face and hair, on the head's bone: it doesn't
blink or move its lips) are generated (source/trellis/: the A-pose concept, the TRELLIS.2 model and trellis.json
with how). Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the
shared pose code. Meshes: "Skin" (her hands are what's left of it), "Outfit"; empty "HeadTop" on the head (where the
name plate and the bubbles go).

The crew's shared clips too (tools/blender/fidgets.py: "LookAround", "Stretch", "CheckWrist", "Tap").

Writes assets/npcs/fenna/fenna.glb and its source assets/npcs/fenna/source/fenna.blend; renders go to
tmp/assets/npcs/fenna/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "fenna" / "source"
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
        "age": 0.65,  # about 45
        "muscle": 0.5,
        "weight": 0.65,
        "proportions": 0.5,
        "height": 0.5,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.0, "caucasian": 0.05, "african": 0.95},
    },
    "skin": "middleage_african_female",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
}
# The apron hangs loose below the waist; the generated forearms in her own tone, her bare hands in theirs (her face's
# tone reads too light under the cap's brim); her head is the generated one.
FIT = D.Fit(
    SOURCE / "trellis" / "fenna_trellis.glb",
    skirt=(0.03, 0.07),
    bare_arms=False,
    cuff=0.0,
    gloved=D.BARE,
    center_cuffs=0.15,
    taper_cuffs=0.06,
    own_head=True,
    forearm_tone=True,
)
# Her hands hang clear of the apron.
PERSON = D.Person("Fenna", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "fenna", wrist_out=0.08)


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
