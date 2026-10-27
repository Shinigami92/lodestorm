"""Nell, the bartender at Waypost Ostra: a sturdy woman in her forties with a brown braid, a slate work jacket with
rolled sleeves, tattooed forearms, fingerless gloves, a stained canvas apron with leather straps, a belt with a
holster, cargo trousers with knee pads and lace-up boots (reference: the batch-8 concept "nell_v2", see
docs/design/art.md, Art direction).

Run from the repo root (see docs/technical/characters.md, People):
    tools/blender.sh assets/npcs/nell/source/nell_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/nell/source/nell_build.py final    # renders, nell.blend and the game asset

Made of two (tools/blender/people.py, dressing.py): her body is MakeHuman's (MPFB's sliders, a CC0 skin, eyes, brows and lashes:
her face, her skeleton and its weights); what she wears and her hair are generated (source/trellis/: the A-pose
concept, the TRELLIS.2 model and trellis.json with how). The outfit is cut open where her face is, its hair fitted
over her head, its skin tone matched to the body's; it takes the weights of the body under it, the apron's skirt
from the hips into both thighs. Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle"
and "Walk" from the shared pose code, her work at the bar from nell_clips.py. Meshes: "Skin" (her head and neck are what's left of it), "Eyes",
"Brows", "Lashes", "Outfit"; empty "HeadTop" on the head (where the name plate and the bubbles go); bones
"PropRag", "PropGlass", "PropBottle" with the empties "RagGrip", "GlassGrip", "BottleGrip" (where the game puts
the props' models, assets/props/bar/).

Writes assets/npcs/nell/nell.glb and its source assets/npcs/nell/source/nell.blend; renders go to tmp/assets/npcs/nell/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets" / "npcs" / "nell" / "source"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(SOURCE))

import bpy
import nell_clips

import common as C
import dressing as D
import humanoid as H
import people as P

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

BODY = {
    "macro": {
        "gender": 0.0,
        "age": 0.65,  # about 45
        "muscle": 0.6,
        "weight": 0.6,
        "proportions": 0.5,
        "height": 0.6,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05},
    },
    "skin": "middleage_caucasian_female",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
        ("eyebrows", "eyebrow010", "Brows"),
        ("eyelashes", "eyelashes04", "Lashes"),
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
    "Eyes": ((1.0, 1.0, 1.0), 0.2, False),
    "Brows": ((0.8, 0.65, 0.5), 0.8, True),
    "Lashes": ((1.0, 1.0, 1.0), 0.8, True),
}
# The apron hangs loose below the waist; her fingerless gloves are painted on her hands.
FIT = D.Fit(SOURCE / "trellis" / "nell_trellis.glb", skirt=(0.03, 0.07))
PERSON = D.Person("Nell", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "nell")


def props(arm: bpy.types.Object) -> None:
    """Where her hands hold things while she works (the work clips show them; the models are
    assets/props/bar/: a rag and a bottle in the right hand, a glass in the left)."""
    for name, side in (("Rag", "Right"), ("Glass", "Left"), ("Bottle", "Right")):
        P.prop_grip(arm, name, side)


def clips(body: H.Body) -> dict:
    out = {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
    }
    for name, (frames, fn) in nell_clips.CLIPS.items():
        out[name] = (frames, lambda t, fn=fn: fn(body, t))
    return out


def work(body: H.Body) -> list:
    """Her work poses to render: wiping and polishing halfway, shelving a bottle at three moments."""
    shots = [(f"{n}5", fn(body, 0.5)) for n, fn in (("wipe", nell_clips.wipe), ("polish", nell_clips.polish))]
    return shots + [(f"shelve{i}", nell_clips.shelve(body, t)) for i, t in ((2, 0.24), (5, 0.5), (7, 0.76))]


D.make(PERSON, props, clips, work, MODE, TAG)
