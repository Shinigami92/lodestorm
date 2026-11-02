"""Game-ready rich vein kit: bake the procedural look of vein_procedural.blend (rock and smoky crystal) into one
shared texture set.

Run from the repo root, after vein_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/vein/source/vein_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/vein/source/vein_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/vein/vein.glb (textures embedded) and its source
assets/parts/vein/source/vein.blend; the separate PNGs and check renders go to tmp/assets/parts/vein/game/.

The shared flow (tools/blender/bake.py) bakes the four pieces into one 2048 texture set with one "Vein" PBR material
(no emission: nothing glows, the ore in front of the wall stays the brightest thing). UV unwrap `bake.chart_unwrap`,
as the biome kits': charts grown over the facets and flattened conformally, folded faces split off, the never-seen
bottom caps shrunk. The pieces stand in a row for the bake (no AO from a neighbor); their locations are zeroed for
the export.

Every piece is its own mesh node at the kit's root, origin at its ground contact point (the wall's at the middle of
its bounds, its open side toward +Y); the part's scene places them by name. Texel density and budgets are
TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "vein"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import vein_build as build  # the kit's pieces and layout (importing it doesn't run the build)
from mathutils import Vector

import bake as B
import common as C

SIZE = 2048


# --- bake job -----------------------------------------------------------------------------------------


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every piece sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="vein",
    asset="Vein",
    source=OUT / "vein_procedural.blend",
    glb=ROOT / "assets" / "parts" / "vein" / "vein.glb",
    blend=ROOT / "assets" / "parts" / "vein" / "source" / "vein.blend",
    game=OUT / "game",
    atlas=build.PIECES,
    material="Vein",
    size=SIZE,
    unwrap=B.chart_unwrap(by_material=True),
    # The base color carries AO cavity grime and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    drop_attributes=("facet",),
    finish=finish,
)


# --- check renders ---------------------------------------------------------------------------------------

# The part's layout as vein_build.py proposes it (Godot position, rotation y in degrees, scale).
LAYOUT = [
    ("Vein_wall", (-0.072, 0.0, 4.405), 0.0, 1.0),
    ("Vein_cluster_a", (-5.7, 0.0, 0.1), 20.0, 1.0),
    ("Vein_cluster_b", (5.5, 0.0, -0.3), -35.0, 1.15),
    ("Vein_shards", (2.0, 0.0, 4.6), 30.0, 1.0),
]
FRONT_Y = ("Vein_wall",)


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(build.PIECES), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for o in parts:
        o.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    for name in build.PIECES:
        for view in ("iso", "hero"):
            B.render_closeup(job, bpy.data.objects[name], parts, view, math.pi if name in FRONT_Y else 0.0)
    # The part's layout from the game's angle (front side), the studio lights.
    for name, pos, rot, scale in LAYOUT:
        obj = bpy.data.objects[name]
        obj.location = (pos[0], -pos[2], pos[1])
        obj.rotation_euler = (0, 0, math.radians(rot))
        obj.scale = (scale,) * 3
    bpy.data.objects["PreviewFigure"].location = (1.2, 1.0, 0)
    center = Vector((0, -2.8, 1.5))
    a, pitch = math.radians(45), math.radians(50)
    loc = center + Vector((math.cos(a) * math.cos(pitch), math.sin(a) * math.cos(pitch), math.sin(pitch))) * 27.0
    C.render_from(job.game / "check_layout.png", loc, center, lens=42.0, samples=64, size=1024)


if __name__ == "__main__":
    B.run(JOB, checks)
