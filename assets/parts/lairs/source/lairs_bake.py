"""Game-ready Lairs kit: bake the procedural look of lairs_procedural.blend (rock, bone, shell, soil, the hive's
chitin, flesh, resin, pod membrane, slime and glands) into one shared texture set with an emission map.

Run from the repo root, after lairs_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/lairs/source/lairs_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/lairs/source/lairs_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/lairs/lairs.glb (textures embedded) and its source
assets/parts/lairs/source/lairs.blend; the separate PNGs and check renders go to tmp/assets/parts/lairs/game/.

The shared flow (tools/blender/bake.py) bakes all eleven pieces into one 2048 texture set with one "Lairs" PBR
material; the glands and the pods' faint glow go into the emission map (emission = map * EMISSION). Own UV unwrap,
as the biome kits' (assets/biomes/frost/source/frost_bake.py): charts grown over the facets and flattened
conformally, folded faces split off, the never-seen bottom caps shrunk, the two ground discs at a lower density
(they're seen from far above and carry only large shapes). The pieces stand in a row for the bake (no AO from a
neighbor); their locations are zeroed for the export.

Every piece is its own mesh node under the "Lairs" root, origin at its ground contact; the game reads one mesh by
name (ModelParts). Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "lairs"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bmesh
import bpy
import lairs_build as LB
from mathutils import Vector

import bake as B

SIZE = 2048
MARGIN_PX = 3  # pack margin (px at 2048)
CHART_CONE = 60.0  # a UV chart takes faces whose normal is within this angle of its seed face's normal
BOTTOM_UV_SCALE = 0.08  # bottom caps sit below ground: keep them in the atlas, but tiny
DISC_UV_SCALE = 0.55  # the ground discs: about half the density of the props
DISCS = ("Den_ground", "Hive_slime")
EMISSION = 3.0  # the glands' strongest glow; the map stores emission / EMISSION


# --- UV unwrap ----------------------------------------------------------------------------------------


def is_hidden_face(f, zmin: float) -> bool:
    return f.normal.z < -0.99 and f.calc_center_median().z < zmin + 1e-3


def mark_chart_seams(obj: bpy.types.Object) -> int:
    """Grow UV charts: from the biggest unassigned face, take in neighbors whose normal stays within CHART_CONE of
    the seed's; seams go between charts. The bottom cap stays a chart of its own. Returns the number of charts."""
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
        chart[seed.index] = seed.index
        stack = [seed]
        while stack and seed.index not in hidden:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in chart or g.index in hidden or g.normal.dot(seed.normal) < cos_cone:
                        continue
                    chart[g.index] = seed.index
                    stack.append(g)
    for e in bm.edges:
        e.seam = len({chart[f.index] for f in e.link_faces}) > 1
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


def scale_uvs(obj: bpy.types.Object) -> None:
    """Shrink the bottom caps to specks around their own centers; a ground disc's UVs as a whole by DISC_UV_SCALE."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    if obj.name in DISCS:
        for f in bm.faces:
            for lp in f.loops:
                lp[uv].uv = lp[uv].uv * DISC_UV_SCALE
    else:
        zmin = min(v.co.z for v in bm.verts)
        for f in bm.faces:
            if is_hidden_face(f, zmin):
                mid = sum((lp[uv].uv for lp in f.loops), Vector((0, 0))) / len(f.loops)
                for lp in f.loops:
                    lp[uv].uv = mid + (lp[uv].uv - mid) * BOTTOM_UV_SCALE
    bm.to_mesh(me)
    bm.free()


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
        scale_uvs(o)
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
    name="lairs",
    asset="Lairs",
    source=OUT / "lairs_procedural.blend",
    glb=ROOT / "assets" / "parts" / "lairs" / "lairs.glb",
    blend=ROOT / "assets" / "parts" / "lairs" / "source" / "lairs.blend",
    game=OUT / "game",
    atlas=LB.PIECES,
    material="Lairs",
    size=SIZE,
    unwrap=unwrap_atlas,
    # The base color carries AO cavity grime and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    emission_strength=EMISSION,
    drop_attributes=("facet", "fresh", "flow", "glow", "edge"),
    finish=finish,
)


# --- check renders (the build's layouts and piece framing on the baked kit) -----------------------------------


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(LB.PIECES), [o.name for o in parts]
    LB.OUT = job.game  # the build's render helpers write below OUT
    LB.setup_preview()
    for part in ("den", "hive"):
        LB.render_layout(part, job.game / f"check_layout_{part}.png", True, 96, 1280)
        LB.render_layout(part, job.game / f"check_layout_{part}_close.png", True, 96, 1280, zoom=0.62)
    for name in LB.PIECES:
        LB.render_piece(name, "check_", ("iso", "hero"), 32, 640)


B.run(JOB, checks)
