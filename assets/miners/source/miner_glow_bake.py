"""Game-ready miner: bake the procedural look of miner_glow.blend into one shared texture set.

Run from the repo root, after miner_glow_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/miners/source/miner_glow_bake.py          # bake, export, check renders
    tools/blender.sh assets/miners/source/miner_glow_bake.py verify   # only re-import and render the checks

Writes the game asset assets/miners/miner_glow.glb (textures embedded) and its source
assets/miners/source/miner_glow.blend; the separate PNGs and check renders go to tmp/miner_assets/glow/game/.

The shared flow (tools/blender/bake.py) bakes the frame, drill and cable into one 2048 texture set and swaps in one
"Miner" PBR material; glass, fill and the emissive parts keep simple constant materials (the fill a dimmer one), the
glass stays double-sided.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "miner_assets" / "glow"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy

import bake as B
import common as C


def finish(job: B.Job, objs: list) -> None:
    fill = bpy.data.objects["Fill"]
    C.assign(fill, B.mat_constant("OreFill", (0.05, 0.72, 0.8), roughness=0.3, emission=2.0))
    fill.scale = (1, 1, 1)


JOB = B.Job(
    name="miner_glow",
    asset="Miner",
    source=OUT / "miner_glow.blend",
    glb=ROOT / "assets" / "miners" / "miner_glow.glb",
    blend=ROOT / "assets" / "miners" / "source" / "miner_glow.blend",
    game=OUT / "game",
    # Objects whose materials are procedural (or would cost an extra material): they share the atlas.
    atlas=["Frame_Body", "Frame_Legs", "Frame_Boxes", "Frame_Bolts", "Frame_Clamps", "Drill", "Cable"],
    material="Miner",
    pack_method="SCALED",
    pack_margin=0.004,
    double_sided=("Glass",),
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    C.preview_scene()
    for view in ("iso", "hero"):
        C.render(job.game / f"check_{view}.png", view=view, samples=96, size=1024)


B.run(JOB, checks)
