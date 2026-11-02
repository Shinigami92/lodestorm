"""Game-ready Lairs kit: bake the procedural look of lairs_procedural.blend (rock, bone, shell, soil, the hive's
chitin, flesh, resin, pod membrane, slime and glands) into one shared texture set with an emission map.

Run from the repo root, after lairs_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/lairs/source/lairs_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/lairs/source/lairs_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/lairs/lairs.glb (textures embedded) and its source
assets/parts/lairs/source/lairs.blend; the separate PNGs and check renders go to tmp/assets/parts/lairs/game/.

The shared flow (tools/blender/bake.py) bakes all eleven pieces into one 2048 texture set with one "Lairs" PBR
material; the glands and the pods' faint glow go into the emission map (emission = map * EMISSION). UV unwrap
`bake.chart_unwrap`, as the biome kits': charts grown over the facets and flattened
conformally, folded faces split off, the never-seen bottom caps shrunk, the two ground discs at a lower density
(they're seen from far above and carry only large shapes). The pieces stand in a row for the bake (no AO from a
neighbor); their locations are zeroed for the export.

Every piece is its own mesh node under the "Lairs" root, origin at its ground contact; the game reads one mesh by
name (ModelParts). Texel density and budgets are TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "lairs"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import lairs_build as LB

import bake as B

SIZE = 2048
DISC_UV_SCALE = 0.55  # the ground discs: about half the density of the props
DISCS = ("Den_ground", "Hive_slime")
EMISSION = 3.0  # the glands' strongest glow; the map stores emission / EMISSION


# --- bake job -----------------------------------------------------------------------------------------


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every piece sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.kit_job(
    __file__,
    OUT,
    asset="Lairs",
    atlas=LB.PIECES,
    material="Lairs",
    size=SIZE,
    unwrap=B.chart_unwrap(scale_all=dict.fromkeys(DISCS, DISC_UV_SCALE)),
    # The base color carries AO cavity grime and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    emission_strength=EMISSION,
    drop_attributes=("facet", "fresh", "flow", "glow", "edge"),
    finish=finish,
)


# --- check renders (the build's layouts and piece framing on the baked kit) -----------------------------------


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(LB.PIECES), [o.name for o in parts]
    LB.OUT = job.game  # the build's render helpers write below OUT
    LB.setup_preview()
    for part in ("den", "hive"):
        LB.render_layout(part, job.game / f"check_layout_{part}.png", True, 96, 1280)
        LB.render_layout(part, job.game / f"check_layout_{part}_close.png", True, 96, 1280, zoom=0.62)
    for name in LB.PIECES:
        LB.render_piece(name, "check_", ("iso", "hero"), 32, 640)


if __name__ == "__main__":
    B.run(JOB, checks)
