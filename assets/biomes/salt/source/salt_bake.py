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
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import salt_build as build  # the kit's pieces and layout (importing it doesn't run the build)
from mathutils import Vector

import bake as B
import common as C

ASSET = "Salt"
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
    atlas=build.PARTS,
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


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(build.PARTS), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*build.GROUND[0], 1.0)
            node.inputs[7].default_value = (*build.GROUND[1], 1.0)
    for name, (u, v, rot) in build.LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.rotation_mode = "XYZ"  # the glTF importer sets quaternions
        obj.location = build.uv_to_xy(u, v)
        obj.rotation_euler = (0, 0, math.radians(rot))
    bpy.data.objects["PreviewFigure"].location = build.uv_to_xy(*build.FIGURE_UV)
    center = build.uv_to_xy(0.0, -1.2) + Vector((0, 0, 0.9))
    for view, zoom in (("iso", 1.85), ("hero", 2.4)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=tuple(center), zoom=zoom)
    for name in build.PARTS:
        B.render_closeup(job, bpy.data.objects[name], parts, "iso")
    C.contact_sheet(
        [job.game / f"check_{v}.png" for v in ("iso", "hero")] + [job.game / f"check_{n}_iso.png" for n in build.PARTS],
        job.game / "check_sheet.png",
        tile=384,
        background=0.02,
    )


if __name__ == "__main__":
    B.run(JOB, checks)
