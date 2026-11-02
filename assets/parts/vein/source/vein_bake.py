"""Game-ready rich vein kit: bake the procedural look of vein_procedural.blend (rock and smoky crystal) into one
shared texture set.

Run from the repo root, after vein_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/vein/source/vein_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/vein/source/vein_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/vein/vein.glb (textures embedded) and its source
assets/parts/vein/source/vein.blend; the separate PNGs and check renders go to tmp/assets/parts/vein/game/.

The shared flow (tools/blender/bake.py) bakes the four pieces into one 2048 texture set with one "Vein" PBR material
(no emission: nothing glows, the ore in front of the wall stays the brightest thing). Own UV unwrap, as the biome
kits': charts grown over the facets and flattened conformally, folded faces split off, the never-seen bottom caps
shrunk. The pieces stand in a row for the bake (no AO from a neighbor); their locations are zeroed for the export.

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

import bmesh
import bpy
from mathutils import Vector

import bake as B
import common as C

SIZE = 2048
MARGIN_PX = 3  # pack margin (px at 2048); islands end up about 5 px apart
CHART_CONE = 60.0  # a UV chart takes faces whose normal is within this angle of its seed face's normal
BOTTOM_UV_SCALE = 0.08  # bottom caps sit below ground: keep them in the atlas, but tiny
PIECES = ["Vein_wall", "Vein_cluster_a", "Vein_cluster_b", "Vein_shards"]


# --- UV unwrap (as the biome kits) --------------------------------------------------------------------


def is_hidden_face(f, zmin: float) -> bool:
    return f.normal.z < -0.99 and f.calc_center_median().z < zmin + 1e-3


def shrink_hidden_islands(obj: bpy.types.Object) -> None:
    """Scale the UVs of the flat bottom cap around their own center before packing: they detach from their
    neighbors and take little atlas space."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    zmin = min(v.co.z for v in bm.verts)
    for f in bm.faces:
        if not is_hidden_face(f, zmin):
            continue
        mid = sum((lp[uv].uv for lp in f.loops), Vector((0, 0))) / len(f.loops)
        for lp in f.loops:
            lp[uv].uv = mid + (lp[uv].uv - mid) * BOTTOM_UV_SCALE
    bm.to_mesh(me)
    bm.free()


def mark_chart_seams(obj: bpy.types.Object) -> int:
    """Grow UV charts over the faceted surface: from the biggest unassigned face, take in neighbors whose normal
    stays within CHART_CONE of the seed's, so a chart never wraps around a column; seams go between charts.
    The bottom cap stays a chart of its own. Returns the number of charts."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    zmin = min(v.co.z for v in bm.verts)
    hidden = {f.index for f in bm.faces if is_hidden_face(f, zmin)}
    chart = {}
    cos_cone = math.cos(math.radians(CHART_CONE))
    for seed in sorted(bm.faces, key=lambda f: -f.calc_area()):
        if seed.index in chart:
            continue
        cid = seed.index
        chart[seed.index] = cid
        stack = [seed]
        while stack and seed.index not in hidden:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in chart or g.index in hidden or g.normal.dot(seed.normal) < cos_cone:
                        continue
                    if g.material_index != seed.material_index:
                        continue  # rock and crystal never share a chart
                    chart[g.index] = cid
                    stack.append(g)
    for e in bm.edges:
        ids = {chart[f.index] for f in e.link_faces}
        e.seam = len(ids) > 1
    bm.to_mesh(me)
    bm.free()
    return len(set(chart.values()))


def split_selected_uv_faces(obj: bpy.types.Object) -> int:
    """Mark seams around the faces the UV editor has selected (uv.select_overlap); returns how many."""
    me = obj.data
    attr = me.attributes.get(".uv_select_face")
    if attr is None:
        return 0
    sel = [0] * len(me.polygons)
    attr.data.foreach_get("value", sel)
    faces = [i for i, s in enumerate(sel) if s]
    if faces:
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        for i in faces:
            for e in bm.faces[i].edges:
                e.seam = True
        bm.to_mesh(me)
        bm.free()
    return len(faces)


def unwrap_atlas(job: B.Job, objs: list) -> None:
    B.new_uv_map(objs)
    print("UV charts", {o.name: mark_chart_seams(o) for o in objs})
    B.select_only(objs, objs[0])
    bpy.context.scene.tool_settings.use_uv_select_sync = False
    for attempt in range(6):
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.unwrap(method="CONFORMAL", fill_holes=False, margin=0.002)
        # A chart can fold over itself in the flattening: cut every overlapping face out into its own island.
        bpy.ops.uv.select_all(action="DESELECT")
        bpy.ops.uv.select_overlap(extend=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        overlapping = {o.name: split_selected_uv_faces(o) for o in objs}
        print("UV overlap pass", attempt, {k: v for k, v in overlapping.items() if v})
        if not any(overlapping.values()):
            break
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        shrink_hidden_islands(o)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=MARGIN_PX / SIZE)
    bpy.ops.object.mode_set(mode="OBJECT")


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
    atlas=PIECES,
    material="Vein",
    size=SIZE,
    unwrap=unwrap_atlas,
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


def render_closeup(job: B.Job, obj: bpy.types.Object, parts: list, view: str) -> None:
    for o in parts:
        o.hide_render = o is not obj
    loc, rot = obj.location.copy(), obj.rotation_euler.copy()
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, math.pi if obj.name in FRONT_Y else 0.0)
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
    assert sorted(o.name for o in parts) == sorted(PIECES), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for o in parts:
        o.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    for name in PIECES:
        for view in ("iso", "hero"):
            render_closeup(job, bpy.data.objects[name], parts, view)
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


B.run(JOB, checks)
