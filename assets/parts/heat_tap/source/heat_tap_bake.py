"""Game-ready heat_tap kit: bake the procedural look of heat_tap_procedural.blend into one shared texture set.

Run from the repo root, after heat_tap_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/heat_tap/source/heat_tap_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/heat_tap/source/heat_tap_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/heat_tap/heat_tap.glb (textures embedded) and its source
assets/parts/heat_tap/source/heat_tap.blend; the separate PNGs and check renders go to tmp/assets/parts/heat_tap/game/.

The shared flow (tools/blender/bake.py) bakes every piece into one 2048 texture set (base color, ORM, normal and an
emission map (the ember glow in the housing's well)) with one "HeatTap" PBR material. Smart-project unwrap; the flat bottoms below the ground are shrunk to
specks. The pieces stand in a row for the bake (no AO from a neighbor); their locations are zeroed for the export.
Every piece is its own mesh node at the root, named as the build script's PIECES; the game picks them by name.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "tools" / "blender"))  # the shared colony look
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import colony as K
import heat_tap_build as build  # the kit's pieces and layout (importing it doesn't run the build)

import bake as B

KIT = build.KIT
JOB = B.kit_job(
    __file__,
    KIT.out,
    asset=KIT.collection,
    atlas=list(KIT.pieces),
    material="HeatTap",
    size=2048,
    shrink=K.hidden_scale,
    # The base color carries AO cavity grime and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    emission_strength=3.0,  # glTF emissive strength of the shared material; the texture holds color * glow / 3.0
    finish=K.bake_finish,
)

B.run(JOB, lambda job, meshes: K.bake_checks(KIT, job, meshes))
