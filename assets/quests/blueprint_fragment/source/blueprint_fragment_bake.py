"""Game-ready blueprint fragment: bake the procedural look of blueprint_fragment_procedural.blend into one texture set.

Run from the repo root, after blueprint_fragment_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/quests/blueprint_fragment/source/blueprint_fragment_bake.py          # bake, export, checks
    tools/blender.sh assets/quests/blueprint_fragment/source/blueprint_fragment_bake.py verify   # only the checks

Writes the game asset assets/quests/blueprint_fragment/blueprint_fragment.glb (textures embedded) and its source
assets/quests/blueprint_fragment/source/blueprint_fragment.blend; the separate PNGs and check renders go to
tmp/assets/blueprint_fragment/game/.

The shared flow (tools/blender/bake.py) bakes "Plate" and "Sleeve" (materials PlateFace, PlateRim, PlateFracture,
Gunmetal, Steel, Black) into one 1024 texture set (at 2x and scaled down: cheap anti-aliasing for the small, finely
etched plate) with one "BlueprintFragment" PBR material. "Glow" (the amber data trace and the lamp) gets a constant
emissive material the game may override. Texture size per the asset budget, TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "blueprint_fragment"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "BlueprintFragment"
AMBER = (1.0, 0.522, 0.073)  # linear for sRGB Color(1.0, 0.75, 0.3), as in blueprint_fragment_build.py
GLOW_STRENGTH = 2.5


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Glow"], B.mat_constant("BlueprintFragment_Glow", AMBER, 0.3, GLOW_STRENGTH))


JOB = B.Job(
    name="blueprint_fragment",
    asset=ASSET,
    source=OUT / "blueprint_fragment_procedural.blend",
    glb=ROOT / "assets" / "quests" / "blueprint_fragment" / "blueprint_fragment.glb",
    blend=ROOT / "assets" / "quests" / "blueprint_fragment" / "source" / "blueprint_fragment.blend",
    game=OUT / "game",
    atlas=["Plate", "Sleeve"],
    material=ASSET,
    size=1024,  # final texture size (budget: one 1024 set, TBD (playtest))
    supersample=2,
    island_margin=0.003,
    pack_method="SCALED",
    pack_margin=0.006,
    ao_distance=0.02,  # the fragment is 0.23 m tall: only close cavities darken
    finish=finish,
)

TARGET = Vector((0.0, 0.0, 0.12))  # same framing as blueprint_fragment_build.py's previews
GAME = Vector((-0.3, 0.3, 0.3))
GAME_OFFSET = Vector((7.0, -7.0, 9.5)) * 1.35


def checks(job: B.Job, meshes: list) -> None:
    C.preview_scene(crystals=False, figure_location=(-0.75, 0.75, 0.0))
    fig = bpy.data.objects["PreviewFigure"]
    for child in fig.children:
        child.hide_render = True
    for view in ("iso", "hero", "back"):
        zoom = 0.028 if view == "iso" else 0.055
        C.render(job.game / f"check_{view}.png", view=view, samples=96, size=1024, target=TARGET, zoom=zoom)
    C.render_from(job.game / "check_front.png", TARGET + Vector((0.04, -0.42, 0.03)), TARGET, 50, 96, 1024)
    for child in fig.children:
        child.hide_render = False
    C.render_from(job.game / "check_game4.png", GAME + GAME_OFFSET, GAME, 200, 64, 768)


B.run(JOB, checks)
