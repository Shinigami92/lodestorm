"""Game-ready blaster: bake the procedural look of blaster_procedural.blend into one texture set.

Run from the repo root, after blaster_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/weapons/source/blaster_bake.py          # bake, export, check renders
    tools/blender.sh assets/weapons/source/blaster_bake.py verify   # only re-import and render the checks

Writes the game asset assets/weapons/blaster.glb (textures embedded) and its source
assets/weapons/source/blaster.blend; the separate PNGs and check renders go to tmp/assets/blaster/game/.

The shared flow (tools/blender/bake.py) bakes "Body" into one 1024 texture set (at 2x and scaled down: cheap
anti-aliasing for the small, detailed gun) with one "Blaster" PBR material. "AmmoCounter" and "EnergyCell" keep their
constant emissive materials (the game drives the counter's fill through its UV.x), so they are not baked.
Texture size 1024 per the asset budget, TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "blaster"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import bake as B  # noqa: E402
import common as C  # noqa: E402

ASSET = "Blaster"
HOLD_Z = 1.1  # check renders lift the gun to the hand height, like blaster_build.py's previews
CENTER = (0.0, 0.14, HOLD_Z + 0.07)


def prepare(job: B.Job) -> list:
    bpy.data.objects[ASSET].location = (0, 0, 0)
    return []


JOB = B.Job(
    name="blaster",
    asset=ASSET,
    source=OUT / "blaster_procedural.blend",
    glb=ROOT / "assets" / "weapons" / "blaster.glb",
    blend=ROOT / "assets" / "weapons" / "source" / "blaster.blend",
    game=OUT / "game",
    atlas=["Body"],
    material=ASSET,
    size=1024,  # final texture size (budget: one 1024 set, TBD (playtest))
    supersample=2,
    island_margin=0.003,
    pack_method="SCALED",
    pack_margin=0.006,
    ao_distance=0.03,  # the gun is 0.9 m long: only close cavities darken
    prepare=prepare,
)


def checks(job: B.Job, meshes: list) -> None:
    C.preview_scene(crystals=False, figure_location=(-0.35, -0.45, 0.0))
    fig = bpy.data.objects["PreviewFigure"]
    bpy.data.objects[ASSET].location = (0, 0, HOLD_Z)
    for child in fig.children:
        child.hide_render = True
    for view, zoom in (("iso", 0.2), ("hero", 0.18), ("back", 0.18)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=CENTER, zoom=zoom)
    # Close look at the right side (blaster_build.py's "close" view): seams and texel density.
    C.render_from(job.game / "check_close.png", Vector(CENTER) + Vector((0.42, -0.36, 0.22)), CENTER, 40, 64, 768)
    for child in fig.children:
        child.hide_render = False
    C.render(job.game / "check_scale.png", view="iso", samples=48, size=768, target=(-0.2, -0.2, 1.0), zoom=0.32)


B.run(JOB, checks)
