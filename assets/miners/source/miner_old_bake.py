"""Game-ready old miner (Hollis' old miner, a static prop): bake the procedural look of miner_old.blend into one shared
texture set.

Run from the repo root, after miner_old_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/miners/source/miner_old_bake.py          # bake, export, check renders
    tools/blender.sh assets/miners/source/miner_old_bake.py verify   # only re-import and render the checks

Writes the game asset assets/miners/miner_old.glb (textures embedded) and its source assets/miners/source/miner_old.blend;
the separate PNGs and check renders go to tmp/miner_assets/old/game/.

Like the glow miner's bake: the frame, drill, cable and mud share one 2048 texture set (baked at twice the size and
filtered down, for the fine scratches and chips) under one "MinerOld" PBR material; glass, fill, lamp and lights keep
their constant materials (dim, or off), the glass stays double-sided.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "miner_assets" / "old"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bake as B
import common as C

JOB = B.Job(
    name="miner_old",
    asset="Miner",
    source=OUT / "miner_old.blend",
    glb=ROOT / "assets" / "miners" / "miner_old.glb",
    blend=ROOT / "assets" / "miners" / "source" / "miner_old.blend",
    game=OUT / "game",
    atlas=["Frame_Body", "Frame_Legs", "Frame_Boxes", "Frame_Bolts", "Frame_Clamps", "Drill", "Cable", "Mud"],
    material="MinerOld",
    supersample=2,
    # FRACTION packing (a fixed gap): SCALED margins left 83 % of the atlas empty around the many small islands.
    double_sided=("Glass",),
)


def checks(job: B.Job, meshes: list) -> None:
    C.preview_scene(crystals=False, figure_location=(2.4, -0.6, 0.0))
    for view in ("iso", "hero", "back"):
        C.render(job.game / f"check_{view}.png", view=view, samples=96, size=1024)
    C.render(job.game / "check_isoclose.png", view="iso", samples=96, size=1024, zoom=0.42)


B.run(JOB, checks)
