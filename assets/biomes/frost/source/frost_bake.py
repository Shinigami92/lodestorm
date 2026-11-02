"""Game-ready Frost fields kit: bake the procedural look of frost_procedural.blend (rock, ice, snow and wood
materials) into one shared texture set.

Run from the repo root, after frost_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/frost/source/frost_bake.py          # bake, export, check renders
    tools/blender.sh assets/biomes/frost/source/frost_bake.py verify   # only re-import and render the checks

Writes the game asset assets/biomes/frost/frost.glb (textures embedded) and its source
assets/biomes/frost/source/frost.blend; the separate PNGs and check renders go to tmp/assets/frost/game/.

The shared flow (tools/blender/bake.py) bakes all ten variants into one 2048 texture set with one "Frost" PBR
material (no emission: nothing glows). UV unwrap `bake.chart_unwrap`, as the rocks kit's:
charts grown over the facets and flattened conformally, folded faces split off, the never-seen bottom caps shrunk,
the cliffs' flat backs at half density. The variants stand in a row for the bake (no AO from a neighbor); their
locations are zeroed for the export.

Every variant is its own mesh node under the "Frost" root, origin at its ground contact point; a ScatterType reads
one mesh by name. Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "frost"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
from mathutils import Vector

import bake as B
import common as C
import frost_build as build  # the kit's pieces and layout (importing it doesn't run the build)

SIZE = 2048
CLIFFS = ("Cliff_a", "Cliff_b")


# --- bake job -----------------------------------------------------------------------------------------


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every variant sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="frost",
    asset="Frost",
    source=OUT / "frost_procedural.blend",
    glb=ROOT / "assets" / "biomes" / "frost" / "frost.glb",
    blend=ROOT / "assets" / "biomes" / "frost" / "source" / "frost.blend",
    game=OUT / "game",
    atlas=build.VARIANTS,
    material="Frost",
    size=SIZE,
    unwrap=B.chart_unwrap(backs=CLIFFS),
    # The base color carries AO cavity grime and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    drop_attributes=("facet",),
    finish=finish,
)


# --- check renders (kit layout and preview framing of frost_build.py) ---------------------------------

CLOSEUPS = ("Boulder_a", "Ice_a", "Pinnacle_a", "Drift_a", "Shrub_a", "Rubble_a", "Cliff_a", "Cliff_b")


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(build.VARIANTS), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:  # the frost ground's blue-grey
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*build.GROUND[0], 1.0)
            node.inputs[7].default_value = (*build.GROUND[1], 1.0)
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
            B.render_closeup(job, bpy.data.objects[name], parts, view)


if __name__ == "__main__":
    B.run(JOB, checks)
