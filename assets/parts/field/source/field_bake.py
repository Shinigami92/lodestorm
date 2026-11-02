"""Game-ready field equipment kit: bake the procedural look of field_procedural.blend into one shared texture set.

Run from the repo root, after field_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/field/source/field_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/field/source/field_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/field/field.glb (textures embedded) and its source
assets/parts/field/source/field.blend; the separate PNGs and check renders go to tmp/assets/parts/field/game/.

The shared flow (tools/blender/bake.py) bakes all fourteen pieces into one 2048 texture set (base color, ORM,
normal and an emission map for the lamps: the work light's lens, the beacon's red lens, the repeller's status light)
with one "Field" PBR material. Smart-project unwrap, mostly hollow islands (rings) cut into single faces; faces below ground are shrunk to specks and the crate's light
strip (the game draws it in its own glowing material) gets a third of the texel density. A ground plane under the
row darkens the pieces' feet in the AO; the pieces stand in a row for the bake (no AO from a neighbor), their
locations are zeroed for the export.

Every piece is its own mesh node at the root, origin at its ground contact point (the lid on its hinge line, the
lens at its center); the game reads one mesh by name. Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "field"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Field"
PARTS = [
    "Crate_base",
    "Crate_lid",
    "Crate_strip",
    "Crate_small",
    "Crate_stack",
    "Barrel_a",
    "Barrel_b",
    "Tarp_stack",
    "Beacon_pole",
    "Beacon_lens",
    "Work_light",
    "Cable_spool",
    "Stake",
    "Repeller_post",
]
EMIT = 6.0  # as in field_build.py
LENS_Z = 3.105
LID_AT = (0.0, -0.4, 0.6)
LID_OPEN = 1.9
BURIED_UV_SCALE = 0.08  # faces below ground: keep them in the atlas, but tiny
STRIP_UV_SCALE = 0.33  # the crate's light strip: drawn in its own material in the game


def hidden_scale(obj: bpy.types.Object, poly: bpy.types.MeshPolygon) -> float | None:
    """UV scale for faces that hardly show: the buried ones and the light strip."""
    if obj.name == "Crate_strip":
        return STRIP_UV_SCALE
    if obj.name in ("Crate_lid", "Beacon_lens"):
        return None
    if poly.center.z < -0.06 and all(obj.data.vertices[v].co.z < -0.01 for v in poly.vertices):
        return BURIED_UV_SCALE
    return None


def uv_islands(bm: bmesh.types.BMesh, uv) -> list:
    """Faces grouped into UV islands (neighbors whose shared edge has the same UVs on both sides)."""
    parent = list(range(len(bm.faces)))

    def root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    bm.faces.index_update()
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        f1, f2 = e.link_faces
        uv1 = {lp.vert: lp[uv].uv for lp in f1.loops if lp.vert in e.verts}
        uv2 = {lp.vert: lp[uv].uv for lp in f2.loops if lp.vert in e.verts}
        if all((uv1[v] - uv2[v]).length < 1e-6 for v in e.verts):
            parent[root(f1.index)] = root(f2.index)
    groups: dict = {}
    for f in bm.faces:
        groups.setdefault(root(f.index), []).append(f)
    return list(groups.values())


def split_hollow(objs: list, fill: float = 0.35) -> int:
    """Cut UV islands that are mostly empty inside their bounds (the rings of frames, chamfers round a disc) into
    single faces: the packer keeps an island's hole empty, these rings left two thirds of the atlas unused."""
    split = 0
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        uv = bm.loops.layers.uv.active
        for faces in uv_islands(bm, uv):
            if len(faces) < 2:
                continue
            pts = [lp[uv].uv for f in faces for lp in f.loops]
            lo, hi = Vector(map(min, *pts)), Vector(map(max, *pts))
            box = (hi.x - lo.x) * (hi.y - lo.y)
            area = 0.0
            for f in faces:
                q = [lp[uv].uv for lp in f.loops]
                area += abs(sum(q[k].x * q[k - 1].y - q[k - 1].x * q[k].y for k in range(len(q)))) / 2
            if box < 1e-9 or area / box >= fill:
                continue
            for k, f in enumerate(faces):
                for lp in f.loops:
                    lp[uv].uv += Vector((0.003 * (k + 1), 0.0))
            split += 1
        bm.to_mesh(o.data)
        bm.free()
    return split


def unwrap(job: B.Job, objs: list) -> None:
    """The shared unwrap (smart project, same texel density, hidden faces shrunk, pack) with the hollow islands
    cut apart before packing."""
    B.new_uv_map(objs)
    B.select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=job.island_margin, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    print("UV hollow islands cut", split_hollow(objs))
    print("UV hidden faces shrunk", B.shrink_faces(objs, job.shrink))
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.uv.select_all(action="SELECT")
    except RuntimeError:
        pass
    bpy.ops.uv.pack_islands(rotate=True, margin_method=job.pack_method, margin=job.pack_margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def ground(job: B.Job) -> list:
    """A dark ground plane under the row, so the AO darkens the pieces' feet."""
    xs = [bpy.data.objects[n].location.x for n in PARTS]
    span = max(xs) - min(xs) + 6.0
    return [B.bake_plane("BakeGround", ((max(xs) + min(xs)) / 2, 0, 0), scale=(span, 8.0, 1.0))]


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every piece sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="field",
    asset=ASSET,
    source=OUT / "field_procedural.blend",
    glb=ROOT / "assets" / "parts" / "field" / "field.glb",
    blend=ROOT / "assets" / "parts" / "field" / "source" / "field.blend",
    game=OUT / "game",
    atlas=PARTS,
    material="Field",
    size=2048,
    shrink=hidden_scale,
    unwrap=unwrap,
    # Many small islands (cylinder strips, rods): a 3 px gap instead of 6 px takes the atlas use from 0.38 to 0.59.
    pack_margin=0.0015,
    # The base color carries AO grime and Bevel-node edge wear (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.3,
    emission_strength=EMIT,
    prepare=ground,
    finish=finish,
)


# --- check renders ------------------------------------------------------------------------------------

# Overview: piece -> (x, y, z rotation); secondary pieces are placed from their group's first piece.
LAYOUT = {
    "Tarp_stack": (-4.0, 2.2, 10),
    "Crate_stack": (-1.0, 2.4, 0),
    "Cable_spool": (1.6, 2.4, 0),
    "Beacon_pole": (3.6, 2.2, 0),
    "Work_light": (5.0, 2.2, 0),
    "Repeller_post": (6.6, 2.2, 0),
    "Crate_base": (-4.0, -0.6, 0),
    "Crate_small": (-2.2, -0.6, 0),
    "Barrel_a": (-0.8, -0.6, 0),
    "Barrel_b": (0.8, -0.6, 0),
    "Stake": (2.2, -0.6, 0),
}
GROUND = ((0.05, 0.047, 0.043), (0.09, 0.085, 0.078))


def put(obj: bpy.types.Object, loc, rot_x: float = 0.0, rot_z: float = 0.0) -> None:
    obj.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    obj.location = loc
    obj.rotation_euler = (rot_x, 0, math.radians(rot_z))


def assemble(lid_open: bool) -> None:
    """Every piece at its overview spot, the lid and the strip on the crate, the lens on the pole."""
    for name, (x, y, rot) in LAYOUT.items():
        put(bpy.data.objects[name], (x, y, 0), 0.0, rot)
    base = bpy.data.objects["Crate_base"].location
    put(bpy.data.objects["Crate_strip"], base)
    put(bpy.data.objects["Crate_lid"], base + Vector(LID_AT), LID_OPEN if lid_open else 0.0)
    put(bpy.data.objects["Beacon_lens"], bpy.data.objects["Beacon_pole"].location + Vector((0, 0, LENS_Z)))


def render_closeup(job: B.Job, names: list, parts: list, tag: str) -> pathlib.Path:
    """The pieces `names` alone (as assembled), framed by their size, the scale figure beside them."""
    for o in parts:
        o.hide_render = o.name not in names
    bpy.context.view_layer.update()
    objs = [bpy.data.objects[n] for n in names]
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo, hi = Vector(map(min, *pts)), Vector(map(max, *pts))
    center = (lo + hi) / 2
    dx, dy, dz = hi.x - lo.x, hi.y - lo.y, hi.z - max(lo.z, 0.0)
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
    fig = bpy.data.objects["PreviewFigure"]
    fig.location = Vector((center.x, center.y, 0)) + side * (max(dx, dy) / 2 + 0.55)
    w = max(dx, dy, dz * 1.1) * 1.3 + 1.4
    target = Vector((center.x, center.y, 0)) + side * 0.3 + Vector((0, 0, max(0.5, dz * 0.42)))
    path = job.game / f"check_{tag}.png"
    C.render(path, view="iso", samples=32, size=640, target=tuple(target), zoom=w / 9.9)
    for o in parts:
        o.hide_render = False
    return path


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(PARTS), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*GROUND[0], 1.0)
            node.inputs[7].default_value = (*GROUND[1], 1.0)
    assemble(lid_open=False)
    fig = bpy.data.objects["PreviewFigure"]
    fig.location = (4.0, -0.6, 0)
    center = (1.2, 0.9, 0.7)
    sheet = []
    for view, zoom in (("iso", 1.15), ("hero", 1.5)):
        sheet.append(job.game / f"check_{view}.png")
        C.render(sheet[-1], view=view, samples=64, size=1024, target=center, zoom=zoom)
    sheet.append(render_closeup(job, ["Crate_base", "Crate_strip", "Crate_lid"], parts, "Crate"))
    assemble(lid_open=True)
    sheet.append(render_closeup(job, ["Crate_base", "Crate_strip", "Crate_lid"], parts, "Crate_open"))
    sheet.append(render_closeup(job, ["Beacon_pole", "Beacon_lens"], parts, "Beacon"))
    lid = bpy.data.objects["Crate_lid"]
    put(lid, (-4.0, -3.0, 0.0), 0.0, 180)  # alone and flat, its stencil turned to the camera
    sheet.append(render_closeup(job, ["Crate_lid"], parts, "Crate_lid"))
    for name in ("Crate_small", "Crate_stack", "Barrel_a", "Barrel_b", "Tarp_stack", "Work_light"):
        sheet.append(render_closeup(job, [name], parts, name))
    for name in ("Cable_spool", "Stake", "Repeller_post"):
        sheet.append(render_closeup(job, [name], parts, name))
    put(bpy.data.objects["Work_light"], bpy.data.objects["Work_light"].location, 0.0, 180)
    sheet.append(render_closeup(job, ["Work_light"], parts, "Work_light_front"))
    C.contact_sheet(sheet, job.game / "check_sheet.png", cols=4, tile=384, background=0.02)


B.run(JOB, checks)
