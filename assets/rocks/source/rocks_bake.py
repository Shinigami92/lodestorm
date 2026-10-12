"""Game-ready rocks kit: bake the procedural look of rocks_procedural.blend into one shared texture set.

Run from the repo root, after rocks_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/rocks/source/rocks_bake.py          # bake, export, check renders
    tools/blender.sh assets/rocks/source/rocks_bake.py verify   # only re-import and render the checks

Writes the game asset assets/rocks/rocks.glb (textures embedded) and its source assets/rocks/source/rocks.blend;
the separate PNGs and check renders go to tmp/assets/rocks/game/.

The shared flow (tools/blender/bake.py) bakes all ten variants into one 2048 texture set with one "Rock" PBR material.
Own UV unwrap: charts grown over the facets and flattened conformally, folded faces split off, the never-seen bottom
caps shrunk, the cliffs' flat backs at half density. The variants stand in a row for the bake (no AO from a
neighbor); their locations are zeroed for the export.

Every variant is its own mesh node under the "Rocks" root, origin at its ground contact point; a ScatterType reads
one mesh by name. Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "rocks"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import bake as B  # noqa: E402
import common as C  # noqa: E402

SIZE = 2048
MARGIN_PX = 3  # pack margin (px at 2048); islands end up about 5 px apart
CHART_CONE = 60.0  # a UV chart takes faces whose normal is within this angle of its seed face's normal
BOTTOM_UV_SCALE = 0.08  # bottom caps sit below ground: keep them in the atlas, but tiny
BACK_UV_SCALE = 0.5  # cliffs' flat backs face the terrain: half the texel density
VARIANTS = [
    "Boulder_a",
    "Boulder_b",
    "Boulder_c",
    "Boulder_d",
    "Rubble_a",
    "Rubble_b",
    "Outcrop_a",
    "Outcrop_b",
    "Cliff_a",
    "Cliff_b",
]
CLIFFS = ("Cliff_a", "Cliff_b")


# --- UV unwrap ----------------------------------------------------------------------------------------


def shrink_hidden_islands(obj: bpy.types.Object) -> None:
    """Scale the UVs of the flat bottom cap (and a cliff's flat back) around their own center before packing:
    they detach from their neighbors and take little atlas space."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    zmin = min(v.co.z for v in bm.verts)
    ymax = max(v.co.y for v in bm.verts)
    for f in bm.faces:
        if not is_hidden_face(obj.name, f, zmin, ymax):
            continue
        s = BOTTOM_UV_SCALE if f.normal.z < -0.99 else BACK_UV_SCALE
        mid = sum((lp[uv].uv for lp in f.loops), Vector((0, 0))) / len(f.loops)
        for lp in f.loops:
            lp[uv].uv = mid + (lp[uv].uv - mid) * s
    bm.to_mesh(me)
    bm.free()


def is_hidden_face(obj_name: str, f, zmin: float, ymax: float) -> bool:
    c = f.calc_center_median()
    if f.normal.z < -0.99 and c.z < zmin + 1e-3:
        return True
    return obj_name in CLIFFS and f.normal.y > 0.99 and c.y > ymax - 1e-3


def mark_chart_seams(obj: bpy.types.Object) -> int:
    """Grow UV charts over the faceted surface: from the biggest unassigned face, take in neighbors whose normal
    stays within CHART_CONE of the seed's, so a chart never wraps around a column; seams go between charts.
    The bottom cap and a cliff's back stay charts of their own. Returns the number of charts."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    zmin = min(v.co.z for v in bm.verts)
    ymax = max(v.co.y for v in bm.verts)
    hidden = {f.index for f in bm.faces if is_hidden_face(obj.name, f, zmin, ymax)}
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
        o.location = (0, 0, 0)  # the bake row layout; in the game every variant sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="rocks",
    asset="Rocks",
    source=OUT / "rocks_procedural.blend",
    glb=ROOT / "assets" / "rocks" / "rocks.glb",
    blend=ROOT / "assets" / "rocks" / "source" / "rocks.blend",
    game=OUT / "game",
    atlas=VARIANTS,
    material="Rock",
    size=SIZE,
    unwrap=unwrap_atlas,
    # The base color carries AO cavity grime and Bevel-node ridges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    drop_attributes=("facet",),
    finish=finish,
)


# --- check renders (kit layout and preview framing of rocks_build.py) ---------------------------------

# (u along screen right, v toward the camera, z rotation); the iso camera looks from +X/-Y.
LAYOUT = {
    "Cliff_a": (-3.4, -5.0, 45),
    "Cliff_b": (3.3, -5.0, 45),
    "Outcrop_a": (-5.4, -0.6, 0),
    "Boulder_a": (-2.4, -0.4, 0),
    "Boulder_b": (0.4, -0.4, 0),
    "Boulder_c": (3.0, -0.4, 0),
    "Outcrop_b": (6.0, -0.6, 0),
    "Boulder_d": (-2.0, 2.8, 0),
    "Rubble_a": (0.2, 2.8, 0),
    "Rubble_b": (1.9, 2.8, 0),
}
FIGURE_UV = (3.6, 2.8)
CLOSEUPS = ("Boulder_a", "Boulder_c", "Rubble_a", "Outcrop_b", "Cliff_a", "Cliff_b")


def uv_to_xy(u: float, v: float) -> Vector:
    s = math.sqrt(0.5)
    return Vector((u * s + v * s, u * s - v * s, 0.0))


def render_closeup(job: B.Job, obj: bpy.types.Object, rocks: list, view: str) -> None:
    for o in rocks:
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
    C.render(job.game / f"check_{obj.name}_{view}.png", view=view, samples=32, size=640, target=tuple(target), zoom=zoom)
    obj.location, obj.rotation_euler, fig.location = loc, rot, fig_loc
    for o in rocks:
        o.hide_render = False


def checks(job: B.Job, rocks: list) -> None:
    assert sorted(o.name for o in rocks) == sorted(VARIANTS), [o.name for o in rocks]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for name, (u, v, rot) in LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.rotation_mode = "XYZ"  # the glTF importer sets quaternions
        obj.location = uv_to_xy(u, v)
        obj.rotation_euler = (0, 0, math.radians(rot))
    bpy.data.objects["PreviewFigure"].location = uv_to_xy(*FIGURE_UV)
    center = uv_to_xy(0.3, -1.2) + Vector((0, 0, 0.9))
    for view, zoom in (("iso", 1.85), ("hero", 2.4)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=tuple(center), zoom=zoom)
    for name in CLOSEUPS:
        for view in ("iso", "hero"):
            render_closeup(job, bpy.data.objects[name], rocks, view)


B.run(JOB, checks)
