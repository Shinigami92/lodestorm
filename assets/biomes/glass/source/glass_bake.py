"""Game-ready Glass plains kit: bake the procedural look of glass_procedural.blend into one shared texture set.

Run from the repo root, after glass_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/glass/source/glass_bake.py          # bake, export, check renders
    tools/blender.sh assets/biomes/glass/source/glass_bake.py verify   # only re-import and render the checks

Writes the game asset assets/biomes/glass/glass.glb (textures embedded) and its source
assets/biomes/glass/source/glass.blend; the separate PNGs and check renders go to tmp/assets/glass/game/.

The shared flow (tools/blender/bake.py) bakes all eleven variants into one 2048 texture set with one "Glass" PBR
material: base color, ORM (non-metallic), normal and the dim teal glow toward
the glass edges as an emission map. UV unwrap `bake.chart_unwrap`: charts grown over the facets and flattened
conformally, folded faces split off, the never-seen bottom caps shrunk, the cliffs' flat backs at half density.
The variants stand in a row for the bake (no AO from a neighbor); their locations are zeroed for the export.

Every variant is its own mesh node under the "Glass" root, origin at its ground contact point; a ScatterType reads
one mesh by name. Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "glass"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import glass_build as build  # the kit's pieces and layout (importing it doesn't run the build)
from mathutils import Vector

import bake as B
import common as C

SIZE = 2048
GLOW = 0.25  # emission strength the glow map is scaled by (the procedural glow stays below it)
CLIFFS = ("Cliff_a", "Cliff_b")


# --- bake job -----------------------------------------------------------------------------------------


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every variant sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="glass",
    asset="Glass",
    source=OUT / "glass_procedural.blend",
    glb=ROOT / "assets" / "biomes" / "glass" / "glass.glb",
    blend=ROOT / "assets" / "biomes" / "glass" / "source" / "glass.blend",
    game=OUT / "game",
    atlas=build.VARIANTS,
    material="Glass",
    size=SIZE,
    unwrap=B.chart_unwrap(backs=CLIFFS),
    # The base color carries AO cavity grime and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64, "Emission": 32},
    ao_distance=0.4,
    emission_strength=GLOW,
    drop_attributes=("facet", "glass"),
    finish=finish,
)


# --- check renders (kit layout and preview framing of glass_build.py) ---------------------------------

CLOSEUPS = ("Spire_a", "Spike_a", "Splinters_a", "Boulder_a", "Fulgurite_a", "Chunks_a", "Cliff_a", "Cliff_b")


def checks(job: B.Job, kit: list) -> None:
    assert sorted(o.name for o in kit) == sorted(build.VARIANTS), [o.name for o in kit]
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
    center = build.uv_to_xy(0.0, -1.2) + Vector((0, 0, 0.9))
    for view, zoom in (("iso", 1.9), ("hero", 2.4)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=tuple(center), zoom=zoom)
    for name in CLOSEUPS:
        for view in ("iso", "hero"):
            B.render_closeup(job, bpy.data.objects[name], kit, view)


if __name__ == "__main__":
    B.run(JOB, checks)
