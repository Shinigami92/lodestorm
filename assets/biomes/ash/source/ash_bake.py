"""Game-ready Ash fields kit: bake the procedural look of ash_procedural.blend into one shared texture set.

Run from the repo root, after ash_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/ash/source/ash_bake.py          # bake, export, check renders
    tools/blender.sh assets/biomes/ash/source/ash_bake.py verify   # only re-import and render the checks

Writes the game asset assets/biomes/ash/ash.glb (textures embedded) and its source assets/biomes/ash/source/ash.blend;
the separate PNGs and check renders go to tmp/assets/ash/game/.

The shared flow (tools/blender/bake.py) bakes all nine parts (basalt, scoria, char and cinder crust materials) into
one 2048 texture set with one "Ash" PBR material, including an emission map for the faint embers in the charred
wood's cracks and the vent's throat. UV unwrap `bake.chart_unwrap`: charts grown over the facets and flattened
conformally, folded faces split off, the never-seen bottom caps shrunk, the cliffs' flat backs at half density. The
parts stand in a row for the bake (no AO from a neighbor) over a ground plane (contact shadow in the AO); their
locations are zeroed for the export.

Every part is its own mesh node under the "Ash" root, origin at its ground contact point; a ScatterType reads one
mesh by name (the vent hazard reads Vent_a). Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "ash"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import ash_build as build  # the kit's pieces and layout (importing it doesn't run the build)
import bpy
from mathutils import Vector

import bake as B
import common as C

SIZE = 2048
CLIFFS = ("Cliff_a", "Cliff_b")


# --- bake job -----------------------------------------------------------------------------------------


def prepare(job: B.Job) -> list:
    """A ground plane under the row of parts: the AO picks up the contact shadow at their feet."""
    xs = [bpy.data.objects[n].location.x for n in build.VARIANTS]
    mid = (min(xs) + max(xs)) / 2
    return [B.bake_plane("BakeGround", location=(mid, 0, 0), scale=(max(xs) - min(xs) + 20, 20, 1))]


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every part sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="ash",
    asset="Ash",
    source=OUT / "ash_procedural.blend",
    glb=ROOT / "assets" / "biomes" / "ash" / "ash.glb",
    blend=ROOT / "assets" / "biomes" / "ash" / "source" / "ash.blend",
    game=OUT / "game",
    atlas=build.VARIANTS,
    material="Ash",
    size=SIZE,
    unwrap=B.chart_unwrap(backs=CLIFFS),
    # The base color and the glow carry ray-traced cavity grime, Bevel-node ridges and AO-masked embers.
    samples={"Base Color": 64, "Emission": 64},
    ao_distance=0.4,
    emission_strength=3.0,  # glTF emissive strength of the shared material; the texture holds color * glow / 3
    drop_attributes=("facet", "inner"),
    prepare=prepare,
    finish=finish,
)


# --- check renders (kit layout and preview framing of ash_build.py) -----------------------------------


def ash_ground() -> None:
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (0.024, 0.023, 0.022, 1.0)
            node.inputs[7].default_value = (0.043, 0.04, 0.038, 1.0)


def render_scatter(job: B.Job, parts: list) -> None:
    """Game-distance check with linked copies, as in ash_build.py's scatter view."""
    rnd = random.Random(5)
    for o in parts:
        o.hide_render = True
    fig = bpy.data.objects["PreviewFigure"]
    fig_loc = fig.location.copy()
    fig.location = (0.6, -0.8, 0)
    dupes = []

    def put(name, x, y, scale, tilt, sink, rot=None):
        d = bpy.data.objects[name].copy()
        C.collection("Preview").objects.link(d)
        d.hide_render = False
        d.parent = None
        d.rotation_mode = "XYZ"
        d.location = (x, y, -sink * scale)
        d.rotation_euler = (
            math.radians(rnd.uniform(-tilt, tilt)),
            math.radians(rnd.uniform(-tilt, tilt)),
            math.radians(rot if rot is not None else rnd.uniform(0, 360)),
        )
        d.scale = (scale,) * 3
        dupes.append(d)

    put("Cliff_a", -4.5, 5.2, 1.0, 0, 0, rot=0)
    put("Cliff_b", 1.8, 5.4, 1.0, 0, 0, rot=0)
    put("Columns_a", -6.4, -0.2, 0.9, 3, 0.1)
    put("Vent_a", 2.4, -2.6, 1.0, 0, 0, rot=0)
    put("Stump_a", 5.6, 0.6, 1.0, 5, 0.05)
    put("Stump_a", -3.2, -4.6, 0.85, 5, 0.05)
    put("Stump_b", -0.6, 1.9, 1.0, 3, 0.03)
    spots = [(-2.6, 1.0), (4.2, -3.8), (-4.6, -1.8), (6.5, -1.6), (-1.2, -5.6), (0.9, 3.4)]
    for i, (x, y) in enumerate(spots):
        put(("Boulder_a", "Boulder_b")[i % 2], x, y, rnd.uniform(0.6, 1.3), 12, 0.12)
    for _ in range(10):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.5, 8.0)
        put("Scoria_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.6, 1.3), 10, 0.04)
    C.render(job.game / "check_scatter.png", view="iso", samples=64, size=1024, target=(0, 0, 0.5), zoom=1.4)
    for d in dupes:
        bpy.data.objects.remove(d)
    fig.location = fig_loc
    for o in parts:
        o.hide_render = False


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(build.VARIANTS), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    ash_ground()
    for name, (u, v, rot) in build.LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.rotation_mode = "XYZ"  # the glTF importer sets quaternions
        obj.location = build.uv_to_xy(u, v)
        obj.rotation_euler = (0, 0, math.radians(rot))
    bpy.data.objects["PreviewFigure"].location = build.uv_to_xy(*build.FIGURE_UV)
    center = build.uv_to_xy(0.3, -1.4) + Vector((0, 0, 0.9))
    for view, zoom in (("iso", 1.95), ("hero", 2.5)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=tuple(center), zoom=zoom)
    render_scatter(job, parts)
    for name in build.VARIANTS:
        for view in ("iso", "hero"):
            B.render_closeup(job, bpy.data.objects[name], parts, view)


if __name__ == "__main__":
    B.run(JOB, checks)
