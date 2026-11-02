"""Game-ready rocks kit: bake the procedural look of rocks_procedural.blend into one shared texture set.

Run from the repo root, after rocks_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/rocks/source/rocks_bake.py          # bake, export, check renders
    tools/blender.sh assets/rocks/source/rocks_bake.py verify   # only re-import and render the checks

Writes the game asset assets/rocks/rocks.glb (textures embedded) and its source assets/rocks/source/rocks.blend;
the separate PNGs and check renders go to tmp/assets/rocks/game/.

The shared flow (tools/blender/bake.py) bakes all ten variants into one 2048 texture set with one "Rock" PBR
material. UV unwrap `bake.chart_unwrap`: charts grown over the facets and flattened conformally, folded faces split
off, the never-seen bottom caps shrunk, the cliffs' flat backs at half density. The variants stand in a row for the
bake (no AO from a neighbor); their locations are zeroed for the export.

Every variant is its own mesh node under the "Rocks" root, origin at its ground contact point; a ScatterType reads
one mesh by name. Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "rocks"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import rocks_build as build  # the kit's pieces and layout (importing it doesn't run the build)
from mathutils import Vector

import bake as B
import common as C

SIZE = 2048
CLIFFS = ("Cliff_a", "Cliff_b")


# --- bake job -----------------------------------------------------------------------------------------


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every variant sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="rocks",
    asset="Rocks",
    source=OUT / "rocks_procedural.blend",
    glb=ROOT / "assets" / "rocks" / "rocks.glb",
    blend=ROOT / "assets" / "rocks" / "source" / "rocks.blend",
    game=OUT / "game",
    atlas=build.VARIANTS,
    material="Rock",
    size=SIZE,
    unwrap=B.chart_unwrap(backs=CLIFFS),
    # The base color carries AO cavity grime and Bevel-node ridges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    drop_attributes=("facet",),
    finish=finish,
)


# --- check renders (kit layout and preview framing of rocks_build.py) ---------------------------------

CLOSEUPS = ("Boulder_a", "Boulder_c", "Rubble_a", "Outcrop_b", "Cliff_a", "Cliff_b")


def checks(job: B.Job, rocks: list) -> None:
    assert sorted(o.name for o in rocks) == sorted(build.VARIANTS), [o.name for o in rocks]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for name, (u, v, rot) in build.LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.rotation_mode = "XYZ"  # the glTF importer sets quaternions
        obj.location = build.uv_to_xy(u, v)
        obj.rotation_euler = (0, 0, math.radians(rot))
    bpy.data.objects["PreviewFigure"].location = build.uv_to_xy(*build.FIGURE_UV)
    center = build.uv_to_xy(0.3, -1.2) + Vector((0, 0, 0.9))
    for view, zoom in (("iso", 1.85), ("hero", 2.4)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=tuple(center), zoom=zoom)
    for name in CLOSEUPS:
        for view in ("iso", "hero"):
            B.render_closeup(job, bpy.data.objects[name], rocks, view)


if __name__ == "__main__":
    B.run(JOB, checks)
