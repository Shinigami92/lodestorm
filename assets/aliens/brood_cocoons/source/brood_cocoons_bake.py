"""Game-ready brood nest (cocoon cluster): bake the procedural look of brood_cocoons_procedural.blend into one shared
texture set.

Run from the repo root, after brood_cocoons_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/brood_cocoons/source/brood_cocoons_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/brood_cocoons/source/brood_cocoons_bake.py verify   # only re-import and render
    tools/blender.sh assets/aliens/brood_cocoons/source/brood_cocoons_bake.py verify all   # plus back, far, close

Writes the game asset assets/aliens/brood_cocoons/brood_cocoons.glb (textures embedded) and its source
assets/aliens/brood_cocoons/source/brood_cocoons.blend; the separate PNGs and check renders go to
tmp/assets/brood_cocoons/game/.

Like the ordinary nest's bake (nest_bake.py): Mound and Tendrils (materials Flesh, Chitin, Resin, EggSac) share one
2048 texture set with one "BroodCocoons" PBR material; the Slime and the emissive Mouth, Glands (with the slits) and
Cracks1/Cracks2/Cracks3 get simple constant materials, the glow in the brood nests' violet (the game overrides the
glowing parts' material to pulse them). Texture size and triangle counts are provisional, TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "brood_cocoons"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy

import bake as B
import common as C

GLOW_COLOR = (0.477, 0.0648, 1.0)  # linear for the brood nests' violet Color(0.72, 0.28, 1.0)
SLIME_COLOR = (0.02, 0.006, 0.008)


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Slime"], B.mat_constant("Slime", SLIME_COLOR, roughness=0.1))
    glow = B.mat_constant("BroodCocoons_Glow", GLOW_COLOR, roughness=0.15, emission=5.0)
    for name in ("Mouth", "Glands", "Cracks1", "Cracks2", "Cracks3"):
        C.assign(bpy.data.objects[name], glow)


JOB = B.Job(
    name="brood_cocoons",
    asset="BroodCocoons",
    source=OUT / "brood_cocoons_procedural.blend",
    glb=ROOT / "assets" / "aliens" / "brood_cocoons" / "brood_cocoons.glb",
    blend=ROOT / "assets" / "aliens" / "brood_cocoons" / "source" / "brood_cocoons.blend",
    game=OUT / "game",
    atlas=["Mound", "Tendrils"],
    material="BroodCocoons",
    pack_method="SCALED",
    pack_margin=0.004,
    finish=finish,
)

CHECK_VIEWS = {  # same framing as brood_cocoons_build.py's previews
    "iso": dict(view="iso", target=(0, 0, 1.1), zoom=1.05),
    "hero": dict(view="hero", target=(0, 0, 1.3), zoom=1.3),
    "back": dict(view="back", target=(0, 0, 1.3), zoom=1.3),
    "far": dict(view="iso", target=(0, 0, 0.5), zoom=1.35),
}


def checks(job: B.Job, meshes: list) -> None:
    C.preview_scene(crystals=False, figure_location=(2.5, 2.1, 0.0))
    for obj in list(C.collection("Preview").objects):  # keep the shared rubble off the nest, as in the build
        if obj.type == "MESH" and obj.name.startswith("Icosphere") and obj.location.xy.length < 4.7:
            bpy.data.objects.remove(obj)
    views = ["iso", "hero"] + (["back", "far", "close"] if "all" in sys.argv else [])
    for view in views:
        path = job.game / f"check_{view}.png"
        if view == "close":
            C.render_from(path, (2.6, -3.1, 3.4), (0, 0, 1.3), 35, 64, 1024)
        else:
            C.render(path, samples=96, size=1024, **CHECK_VIEWS[view])


B.run(JOB, checks)
