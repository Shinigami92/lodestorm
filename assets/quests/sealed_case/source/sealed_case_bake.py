"""Game-ready sealed case: bake the procedural look of sealed_case_procedural.blend into one texture set.

Run from the repo root, after sealed_case_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/quests/sealed_case/source/sealed_case_bake.py          # bake, export, check renders
    tools/blender.sh assets/quests/sealed_case/source/sealed_case_bake.py verify   # only re-import and render the checks

Writes the game asset assets/quests/sealed_case/sealed_case.glb (textures embedded) and its source
assets/quests/sealed_case/source/sealed_case.blend; the separate PNGs and check renders go to
tmp/assets/sealed_case/game/.

The shared flow (tools/blender/bake.py) bakes "Case" (materials Shell, Guard, Steel, Rubber, SealPanel) into one
1024 texture set (at 2x and scaled down: cheap anti-aliasing for the small hardware) with one "SealedCase" PBR
material. "Glow" gets a constant emissive amber material (the game may override it to pulse the seal light).
Texture size and triangle count per the asset budget, TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "sealed_case"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "SealedCase"
AMBER = (1.0, 0.522, 0.073)  # linear for the seal light's sRGB Color(1.0, 0.75, 0.3)
CENTER = (0.0, 0.0, 0.1)  # same framing as sealed_case_build.py's previews


def shrink(obj: bpy.types.Object, poly: bpy.types.MeshPolygon) -> float | None:
    """The bottom faces lie on the ground (or against the backpack): half the texel density."""
    return 0.5 if poly.normal.z < -0.9 else None


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Glow"], B.mat_constant("SealedCase_Glow", AMBER, roughness=0.3, emission=3.0))


JOB = B.Job(
    name="sealed_case",
    asset=ASSET,
    source=OUT / "sealed_case_procedural.blend",
    glb=ROOT / "assets" / "quests" / "sealed_case" / "sealed_case.glb",
    blend=ROOT / "assets" / "quests" / "sealed_case" / "source" / "sealed_case.blend",
    game=OUT / "game",
    atlas=["Case"],
    material=ASSET,
    size=1024,  # final texture size (budget: one 1024 set, TBD (playtest))
    supersample=2,
    island_margin=0.003,
    pack_method="SCALED",
    pack_margin=0.006,
    shrink=shrink,
    ao_distance=0.03,  # the case is 0.55 m long: only close cavities darken
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    C.preview_scene(crystals=False, figure_location=(0.75, 0.6, 0.0))
    fig = bpy.data.objects["PreviewFigure"]
    for child in fig.children:
        child.hide_render = True
    C.render(job.game / "check_iso.png", view="iso", samples=64, size=1024, target=CENTER, zoom=0.1)
    for view in ("hero", "back"):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=CENTER, zoom=0.13)
    # Close look at the front right corner (sealed_case_build.py's "close" view): seams and texel density.
    C.render_from(job.game / "check_close.png", Vector(CENTER) + Vector((0.35, -0.42, 0.22)), CENTER, 40, 64, 1024)
    for child in fig.children:
        child.hide_render = False
    C.render(job.game / "check_scale.png", view="iso", samples=48, size=768, target=(0.3, 0.25, 0.6), zoom=0.3)
    paths = [job.game / f"check_{v}.png" for v in ("iso", "hero", "back", "close", "scale")]
    C.contact_sheet(paths, job.game / "check_sheet.png", cols=3, tile=512)


B.run(JOB, checks)
