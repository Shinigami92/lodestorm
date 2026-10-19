"""Game-ready alien nest: bake the procedural look of nest_procedural.blend into one shared texture set.

Run from the repo root, after nest_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/nest/source/nest_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/nest/source/nest_bake.py verify   # only re-import and render the checks
    tools/blender.sh assets/aliens/nest/source/nest_bake.py verify all   # plus the back, far and close views

Writes the game asset assets/aliens/nest/nest.glb (textures embedded) and its source
assets/aliens/nest/source/nest.blend; the separate PNGs and check renders go to tmp/assets/nest/game/.

The shared flow (tools/blender/bake.py) bakes Mound and Tendrils (materials Flesh, Chitin, Resin, EggSac) into one
2048 texture set with one "Nest" PBR material; the Slime and the emissive Mouth, Glands and Cracks1/Cracks2 (the
burst stages' fissures) get simple constant materials (the game overrides the glowing parts' material to pulse
them). Texture size and triangle counts are provisional, TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "nest"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy

import bake as B
import common as C

GLOW_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)
SLIME_COLOR = (0.02, 0.006, 0.008)


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Slime"], B.mat_constant("Slime", SLIME_COLOR, roughness=0.1))
    glow = B.mat_constant("Nest_Glow", GLOW_COLOR, roughness=0.15, emission=5.0)
    for name in ("Mouth", "Glands", "Cracks1", "Cracks2"):
        C.assign(bpy.data.objects[name], glow)


JOB = B.Job(
    name="nest",
    asset="Nest",
    source=OUT / "nest_procedural.blend",
    glb=ROOT / "assets" / "aliens" / "nest" / "nest.glb",
    blend=ROOT / "assets" / "aliens" / "nest" / "source" / "nest.blend",
    game=OUT / "game",
    atlas=["Mound", "Tendrils"],
    material="Nest",
    pack_method="SCALED",
    pack_margin=0.004,
    finish=finish,
)

CHECK_VIEWS = {  # same framing as nest_build.py's previews
    "iso": dict(view="iso", target=(0, 0, 0.5), zoom=0.95),
    "hero": dict(view="hero", target=(0, 0, 0.7), zoom=1.05),
    "back": dict(view="back", target=(0, 0, 0.7), zoom=1.05),
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
            C.render_from(path, (2.6, -3.2, 3.2), (0, 0, 0.9), 35, 64, 1024)
        else:
            C.render(path, samples=96, size=1024, **CHECK_VIEWS[view])


B.run(JOB, checks)
