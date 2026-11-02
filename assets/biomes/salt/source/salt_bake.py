"""Game-ready salt pans kit: bake the procedural look of salt_procedural.blend into one shared texture set.

Run from the repo root, after salt_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/salt/source/salt_bake.py          # bake, export, check renders
    tools/blender.sh assets/biomes/salt/source/salt_bake.py verify   # only re-import and render the checks

Writes the game asset assets/biomes/salt/salt.glb (textures embedded) and its source
assets/biomes/salt/source/salt.blend; the separate PNGs and check renders go to tmp/assets/salt/game/.

The shared flow (tools/blender/bake.py) bakes all ten parts into one 2048 texture set (base color, ORM, normal; no
emission, nothing in the kit glows) with one "Salt" PBR material. Smart-project unwrap; the never-seen bottom caps
are shrunk to specks, the cliffs' flat backs get half the texel density. The parts stand in a row for the bake (no
AO from a neighbor); their locations are zeroed for the export.

Every part is its own mesh node under the "Salt" root, origin at its ground contact point; a ScatterType reads one
mesh by name. Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "salt"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Salt"
PARTS = [
    "Boulder_a",
    "Boulder_b",
    "Pillar_a",
    "Halite_a",
    "Shrub_a",
    "Bones_a",
    "Bones_b",
    "Crust_a",
    "Cliff_a",
    "Cliff_b",
]
CLIFFS = ("Cliff_a", "Cliff_b")
BOTTOM_UV_SCALE = 0.08  # bottom caps sit below ground: keep them in the atlas, but tiny
BACK_UV_SCALE = 0.5  # cliffs' flat backs face the terrain: half the texel density


def hidden_scale(obj: bpy.types.Object, poly: bpy.types.MeshPolygon) -> float | None:
    """UV scale for faces nobody sees: the flat bottom caps below ground and the cliffs' flat backs."""
    if poly.normal.z < -0.99 and poly.center.z < -0.04:
        return BOTTOM_UV_SCALE
    if obj.name in CLIFFS and poly.normal.y > 0.99 and poly.center.y > 0.99:
        return BACK_UV_SCALE
    return None


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every part sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="salt",
    asset=ASSET,
    source=OUT / "salt_procedural.blend",
    glb=ROOT / "assets" / "biomes" / "salt" / "salt.glb",
    blend=ROOT / "assets" / "biomes" / "salt" / "source" / "salt.blend",
    game=OUT / "game",
    atlas=PARTS,
    material="Salt",
    size=2048,
    shrink=hidden_scale,
    # The base color carries AO cavity crust and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    drop_attributes=("facet", "kind"),
    finish=finish,
)


# --- check renders (kit layout and preview framing of salt_build.py) ----------------------------------

# (u along screen right, v toward the camera, z rotation); the iso camera looks from +X/-Y.
LAYOUT = {
    "Cliff_a": (-3.4, -5.0, 45),
    "Cliff_b": (3.3, -5.0, 45),
    "Pillar_a": (-5.6, -0.6, 0),
    "Boulder_a": (-3.2, -0.4, 0),
    "Boulder_b": (-0.9, -0.4, 0),
    "Halite_a": (1.1, -0.3, 0),
    "Bones_a": (3.5, -0.3, 30),
    "Bones_b": (-2.6, 2.5, 0),
    "Shrub_a": (-0.5, 2.7, 0),
    "Crust_a": (1.7, 2.7, 0),
}
FIGURE_UV = (4.0, 2.7)
GROUND = ((0.17, 0.17, 0.16), (0.25, 0.25, 0.24))  # linear albedo of the salt crust ground, as in salt_build.py


def uv_to_xy(u: float, v: float) -> Vector:
    k = math.sqrt(0.5)
    return Vector((u * k + v * k, u * k - v * k, 0.0))


def render_closeup(job: B.Job, obj: bpy.types.Object, parts: list, view: str) -> None:
    for o in parts:
        o.hide_render = o is not obj
    loc, rot = obj.location.copy(), obj.rotation_euler.copy()
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    dx, dy, dz = obj.dimensions
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
    fig_loc = fig.location.copy()
    fig.location = side * (max(dx, dy) / 2 + 0.55)
    w = max(dx, dy, dz * 1.1) * 1.3 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.5, dz * 0.42)))
    zoom = w / (9.9 if view == "iso" else 6.3)
    C.render(
        job.game / f"check_{obj.name}_{view}.png", view=view, samples=32, size=640, target=tuple(target), zoom=zoom
    )
    obj.location, obj.rotation_euler, fig.location = loc, rot, fig_loc
    for o in parts:
        o.hide_render = False


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(PARTS), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*GROUND[0], 1.0)
            node.inputs[7].default_value = (*GROUND[1], 1.0)
    for name, (u, v, rot) in LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.rotation_mode = "XYZ"  # the glTF importer sets quaternions
        obj.location = uv_to_xy(u, v)
        obj.rotation_euler = (0, 0, math.radians(rot))
    bpy.data.objects["PreviewFigure"].location = uv_to_xy(*FIGURE_UV)
    center = uv_to_xy(0.0, -1.2) + Vector((0, 0, 0.9))
    for view, zoom in (("iso", 1.85), ("hero", 2.4)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=tuple(center), zoom=zoom)
    for name in PARTS:
        render_closeup(job, bpy.data.objects[name], parts, "iso")
    C.contact_sheet(
        [job.game / f"check_{v}.png" for v in ("iso", "hero")] + [job.game / f"check_{n}_iso.png" for n in PARTS],
        job.game / "check_sheet.png",
        tile=384,
        background=0.02,
    )


B.run(JOB, checks)
