"""Shared bake flow for asset bake scripts (Blender 5.2, run headless with tools/blender.sh).

A build script models an asset with procedural Cycles materials and saves it to tmp/; its bake script describes the
asset in a Job and hands it to run():

    import bake as B
    JOB = B.Job(
        name="rocks",                            # texture prefix: rocks_basecolor / _orm / _normal (/ _emission)
        asset="Rocks",                           # collection (and root empty) of the asset
        source=ROOT / "tmp/assets/rocks/rocks_procedural.blend",
        glb=ROOT / "assets/rocks/rocks.glb",
        blend=ROOT / "assets/rocks/source/rocks.blend",
        game=ROOT / "tmp/assets/rocks/game",     # separate PNGs and check renders
        atlas=["Boulder_a", ...],                # objects sharing one texture set
        material="Rock",                         # the baked PBR material that replaces their materials
    )
    B.run(JOB, checks)                           # bake + export, then glb summary, re-import and checks(job, objs)

`tools/blender.sh <bake script> verify` skips the bake and only re-imports the .glb and renders the checks.
Env var BAKE_OUT=<dir> writes the .glb, the .blend, the PNGs and the check renders to <dir> (source/, game/) instead
of the asset's paths, e.g. to compare a re-bake with the committed asset.

Flow (bake_and_export): open the procedural .blend, drop the preview props, job.prepare(job) (may return bake-only
props, e.g. a ground plane for the AO), apply the modifiers of the atlas objects, unwrap them into one UV atlas
(smart project + pack, or job.unwrap), bake base color / roughness / metallic (emission trick; metallic only when
some material drives it, else its constant), optionally the emission, AO and a tangent-space normal map at
size * supersample, fill the gaps between the islands, pack AO + roughness + metallic into an ORM image, filter down
to the texture size, swap in one baked PBR material, job.finish(job, objs), export the .glb and save the .blend.

Margins: Blender bakes the selected objects one after another and its bake margin of one object paints over pixels
other objects already baked (whole faces came out black), so the bake runs without margin; the islands are then
grown by extend_px (each new pixel the mean of its filled neighbours) and the rest of the gaps is push-pull filled,
so the gutters carry island colors all the way down the mip chain.
"""

import dataclasses
import json
import math
import os
import pathlib
import struct
import sys
from collections.abc import Callable

import bmesh
import bpy
import numpy as np
from mathutils import Vector

import common as C

SAMPLES = {"Base Color": 32, "Roughness": 32, "Metallic": 32, "Emission": 16, "AO": 64, "Normal": 16}


@dataclasses.dataclass
class Job:
    name: str
    asset: str
    source: pathlib.Path
    glb: pathlib.Path
    blend: pathlib.Path
    game: pathlib.Path
    atlas: list
    material: str
    size: int = 2048  # final texture size
    supersample: int = 1  # bake at size * supersample and box-filter down (anti-aliasing for thin or small detail)
    # Unwrap (unwrap_atlas): smart project, average island scale, pack. FRACTION margins are a fixed gap in the
    # atlas (pack_margin * size px); SCALED ones scale with the islands and leave much more of the atlas empty.
    island_margin: float = 0.002
    pack_method: str = "FRACTION"
    pack_margin: float = 0.003
    shrink: Callable | None = None  # (obj, polygon) -> UV scale for faces nobody sees (buried, against a wall), or None
    unwrap: Callable | None = None  # (job, objs) -> None, replaces unwrap_atlas
    # Bake.
    samples: dict = dataclasses.field(default_factory=dict)  # overrides of SAMPLES per pass
    ao_distance: float = 0.25
    ao_strength: float = 0.6  # ORM occlusion = 1 - ao_strength * (1 - AO): the albedo already carries cavity grime
    extend_px: int = 2  # island margin at the bake size, extended from the island edges; the rest is push-pull filled
    emission_strength: float | None = None  # bake the emission (color * strength / this) for the material's emission
    normal_min_z: float | None = None  # clamp the normal map's tilt (see limit_tilt)
    # Game asset.
    double_sided: tuple = ()  # mesh objects whose materials stay double-sided; every other one gets backface culling
    drop_attributes: tuple = ()  # mesh attributes only the procedural materials read, removed after the bake
    export_at_origin: tuple = ()  # objects moved to the origin for the export only (the .blend keeps their layout)
    prepare: Callable | None = None  # (job) -> list of bake-only props, after the .blend is opened
    finish: Callable | None = None  # (job, objs) after the material swap, before the checks and the export
    before_pack: Callable | None = None  # (objs) in unwrap_atlas, before the hidden faces shrink and the pack

    def bake_size(self) -> int:
        return self.size * self.supersample


def kit_job(script: str, out: pathlib.Path, **fields) -> Job:
    """A Job for the bake script `script` (its __file__: assets/<...>/<name>/source/<name>_bake.py) with the usual
    paths: the procedural .blend `out`/<name>_procedural.blend in, the game asset <name>.glb next to the source
    folder and its .blend <name>.blend in it, the PNGs and check renders in `out`/game; `fields` are the rest."""
    here = pathlib.Path(script).resolve()
    name = here.stem.removesuffix("_bake")
    return Job(
        name=name,
        source=out / f"{name}_procedural.blend",
        glb=here.parents[1] / f"{name}.glb",
        blend=here.parent / f"{name}.blend",
        game=out / "game",
        **fields,
    )


def row_ground(names: list, pad: float) -> list:
    """A bake-only ground plane under the row of objects `names` (along X, by their origins), `pad` m longer than the
    row and `pad` m deep: the AO picks up the contact shadow at their feet. Returns it (a Job's prepare result)."""
    xs = [bpy.data.objects[n].location.x for n in names]
    mid = (min(xs) + max(xs)) / 2
    return [bake_plane("BakeGround", location=(mid, 0, 0), scale=(max(xs) - min(xs) + pad, pad, 1))]


def redirected(job: Job) -> Job:
    """The job with its outputs moved to $BAKE_OUT (if set)."""
    out = os.environ.get("BAKE_OUT")
    if not out:
        return job
    out = pathlib.Path(out).resolve()
    print("OUTPUT override", out)
    return dataclasses.replace(job, glb=out / job.glb.name, blend=out / "source" / job.blend.name, game=out / "game")


# --- 1. prepare geometry ------------------------------------------------------------------------------


def select_only(objs: list, active) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def apply_modifiers(obj: bpy.types.Object) -> None:
    """Bake on the final geometry (bevels, weighted normals) so the UVs and the normal map match the export; keeps
    the attributes the procedural materials read."""
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    bpy.data.meshes.remove(old)
    me.name = obj.name  # after removing the old mesh, or the export names it "<name>.001"


def bake_plane(name: str, location=(0, 0, 0), rotation=(0, 0, 0), scale=(1, 1, 1)) -> bpy.types.Object:
    """A 1 m plane (scaled) the bake sees but doesn't bake into, e.g. the ground under the asset so the AO picks up
    the contact shadow. Return it from Job.prepare; the flow removes it before saving."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-0.5, -0.5, 0), (0.5, -0.5, 0), (0.5, 0.5, 0), (-0.5, 0.5, 0)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.location, obj.rotation_euler, obj.scale = location, rotation, scale
    mat, _nt, bsdf = C._new_material("BakeProp")
    bsdf.inputs["Base Color"].default_value = (0.03, 0.03, 0.03, 1.0)
    C.assign(obj, mat)
    return obj


def new_uv_map(objs: list) -> None:
    for o in objs:
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")


def shrink_faces(objs: list, scale_of: Callable) -> int:
    """Scale the UVs of single faces around their own center (scale_of(obj, poly) -> factor or None)."""
    shrunk = 0
    for o in objs:
        uv = o.data.uv_layers["UVMap"].data
        for poly in o.data.polygons:
            s = scale_of(o, poly)
            if s is None:
                continue
            loops = list(poly.loop_indices)
            c = sum((Vector(uv[i].uv) for i in loops), Vector((0, 0))) / len(loops)
            for i in loops:
                uv[i].uv = c + (Vector(uv[i].uv) - c) * s
            shrunk += 1
    return shrunk


def unwrap_atlas(job: Job, objs: list) -> None:
    """One atlas for all objects; average_islands_scale gives them the same texel density."""
    new_uv_map(objs)
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=job.island_margin, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    if job.before_pack or job.shrink:
        bpy.ops.object.mode_set(mode="OBJECT")
        if job.before_pack:
            job.before_pack(objs)
        if job.shrink:
            # Hidden faces: shrink each to a speck around its own center (it becomes its own tiny island).
            print("UV hidden faces shrunk", shrink_faces(objs, job.shrink))
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        try:
            bpy.ops.uv.select_all(action="SELECT")
        except RuntimeError:
            pass  # no UV editor context: smart_project left every UV selected anyway
    bpy.ops.uv.pack_islands(rotate=True, margin_method=job.pack_method, margin=job.pack_margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def chart_unwrap(
    backs: tuple = (),
    by_material: bool = False,
    scale_all: dict | None = None,
    cone: float = 60.0,
    margin_px: int = 3,
    bottom_scale: float = 0.08,
    back_scale: float = 0.5,
) -> Callable:
    """A Job's unwrap for faceted kits (rocks, the biome kits, meteor, vein, lairs): UV charts grown over the facets
    (from the biggest unassigned face, its neighbors whose normal stays within `cone` degrees of the seed's, so a
    chart never wraps around a column; with `by_material`, never across materials) and flattened conformally, folded
    faces cut out into islands of their own, the same texel density everywhere, then packed `margin_px` apart at the
    job's size. The faces nobody sees stay charts of their own and shrink around their own centers: a flat bottom cap
    to `bottom_scale`, the flat +Y back of the objects in `backs` (cliffs against the terrain) to `back_scale`. An
    object in `scale_all` (name: scale) has its whole UVs scaled instead (a ground disc at a lower density)."""

    def unwrap(job: Job, objs: list) -> None:
        new_uv_map(objs)
        print("UV charts", {o.name: _mark_chart_seams(o, backs, cone, by_material) for o in objs})
        select_only(objs, objs[0])
        bpy.context.scene.tool_settings.use_uv_select_sync = False
        for attempt in range(6):
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.unwrap(method="CONFORMAL", fill_holes=False, margin=0.002)
            # A chart can fold over itself in the flattening: cut every overlapping face out into its own island.
            bpy.ops.uv.select_all(action="DESELECT")
            bpy.ops.uv.select_overlap(extend=False)
            bpy.ops.object.mode_set(mode="OBJECT")
            overlapping = {o.name: _split_selected_uv_faces(o) for o in objs}
            print("UV overlap pass", attempt, {k: v for k, v in overlapping.items() if v})
            if not any(overlapping.values()):
                break
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.average_islands_scale()
        bpy.ops.object.mode_set(mode="OBJECT")
        for o in objs:
            _shrink_hidden_islands(o, backs, (scale_all or {}).get(o.name), bottom_scale, back_scale)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=margin_px / job.size)
        bpy.ops.object.mode_set(mode="OBJECT")

    return unwrap


def _is_hidden_face(obj_name: str, f, zmin: float, ymax: float, backs: tuple) -> bool:
    """A flat bottom cap, or the flat +Y back of an object in `backs` (see chart_unwrap)."""
    c = f.calc_center_median()
    if f.normal.z < -0.99 and c.z < zmin + 1e-3:
        return True
    return obj_name in backs and f.normal.y > 0.99 and c.y > ymax - 1e-3


def _mark_chart_seams(obj: bpy.types.Object, backs: tuple, cone: float, by_material: bool) -> int:
    """Seams between the charts of chart_unwrap; returns the number of charts."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    zmin = min(v.co.z for v in bm.verts)
    ymax = max(v.co.y for v in bm.verts)
    hidden = {f.index for f in bm.faces if _is_hidden_face(obj.name, f, zmin, ymax, backs)}
    chart = {}
    cos_cone = math.cos(math.radians(cone))
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
                    if by_material and g.material_index != seed.material_index:
                        continue
                    chart[g.index] = seed.index
                    stack.append(g)
    for e in bm.edges:
        e.seam = len({chart[f.index] for f in e.link_faces}) > 1
    bm.to_mesh(me)
    bm.free()
    return len(set(chart.values()))


def _split_selected_uv_faces(obj: bpy.types.Object) -> int:
    """Seams around the faces the UV editor has selected (uv.select_overlap); returns how many."""
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


def _shrink_hidden_islands(
    obj: bpy.types.Object, backs: tuple, whole: float | None, bottom_scale: float, back_scale: float
) -> None:
    """Before packing: the hidden faces' UVs scaled around their own centers (they detach from their neighbors and
    take little atlas space), or the whole object's UVs by `whole`."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    if whole is not None:
        for f in bm.faces:
            for lp in f.loops:
                lp[uv].uv = lp[uv].uv * whole
    else:
        zmin = min(v.co.z for v in bm.verts)
        ymax = max(v.co.y for v in bm.verts)
        for f in bm.faces:
            if not _is_hidden_face(obj.name, f, zmin, ymax, backs):
                continue
            s = bottom_scale if f.normal.z < -0.99 else back_scale
            mid = sum((lp[uv].uv for lp in f.loops), Vector((0, 0))) / len(f.loops)
            for lp in f.loops:
                lp[uv].uv = mid + (lp[uv].uv - mid) * s
    bm.to_mesh(me)
    bm.free()


def uv_coverage(objs: list) -> tuple[float, float]:
    """Fraction of the atlas covered by UV islands and the UV area per m2 of surface."""
    uv_area = world_area = 0.0
    for o in objs:
        uv = o.data.uv_layers["UVMap"].data
        for p in o.data.polygons:
            pts = [uv[i].uv for i in p.loop_indices]
            a = 0.0
            for k in range(len(pts)):
                x0, y0 = pts[k]
                x1, y1 = pts[(k + 1) % len(pts)]
                a += x0 * y1 - x1 * y0
            uv_area += abs(a) * 0.5
            world_area += p.area
    return uv_area, uv_area / world_area


# --- 2. bake ------------------------------------------------------------------------------------------


def setup_cycles(samples: int, device: str = "GPU") -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    scene.cycles.device = device
    scene.cycles.samples = samples
    scene.render.bake.margin = 0


def new_image(name: str, size: int, non_color: bool) -> bpy.types.Image:
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def output_node(nt) -> bpy.types.Node:
    outs = [n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial"]
    return next((n for n in outs if n.is_active_output), outs[0])


def emit_node(nt) -> bpy.types.Node:
    """The bake's Emission shader (reused), unlinked, strength 1."""
    em = nt.nodes.get("BakeEmit") or nt.nodes.new("ShaderNodeEmission")
    em.name = "BakeEmit"
    em.inputs["Strength"].default_value = 1.0
    for sock in (em.inputs["Color"], em.inputs["Strength"]):
        for lk in list(sock.links):
            nt.links.remove(lk)
    return em


def _feed(nt, sock: bpy.types.NodeSocket, dst: bpy.types.NodeSocket) -> None:
    """Drive dst with whatever drives sock (its link or its constant, as a gray color for a float)."""
    if sock.is_linked:
        nt.links.new(sock.links[0].from_socket, dst)
        return
    v = sock.default_value
    if dst.type == "RGBA":
        dst.default_value = (v[0], v[1], v[2], 1.0) if hasattr(v, "__len__") else (v, v, v, 1.0)
    else:
        dst.default_value = v


def route_to_emission(mat: bpy.types.Material, input_name: str) -> None:
    """Feed whatever drives the BSDF input (link or constant) into an Emission shader on the output."""
    nt = mat.node_tree
    em = emit_node(nt)
    _feed(nt, nt.nodes["Principled BSDF"].inputs[input_name], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], output_node(nt).inputs["Surface"])


def route_glow(mat: bpy.types.Material, strength: float) -> None:
    """Bake the real emission (color * emission strength), scaled by 1 / strength into 0..1."""
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    em = emit_node(nt)
    _feed(nt, bsdf.inputs["Emission Color"], em.inputs["Color"])
    scale = nt.nodes.get("BakeGlowScale") or nt.nodes.new("ShaderNodeMath")
    scale.name = "BakeGlowScale"
    scale.operation = "MULTIPLY"
    scale.use_clamp = True
    scale.inputs[1].default_value = 1.0 / strength
    _feed(nt, bsdf.inputs["Emission Strength"], scale.inputs[0])
    nt.links.new(scale.outputs[0], em.inputs["Strength"])
    nt.links.new(em.outputs["Emission"], output_node(nt).inputs["Surface"])


def route_white(mat: bpy.types.Material) -> None:
    nt = mat.node_tree
    em = emit_node(nt)
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    nt.links.new(em.outputs["Emission"], output_node(nt).inputs["Surface"])


def restore_bsdf(mat: bpy.types.Material) -> None:
    nt = mat.node_tree
    nt.links.new(nt.nodes["Principled BSDF"].outputs["BSDF"], output_node(nt).inputs["Surface"])


def set_target(mats: list, img: bpy.types.Image) -> None:
    for mat in mats:
        nt = mat.node_tree
        node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
        node.name = "BakeTarget"
        node.image = img
        node.interpolation = "Closest"
        for n in nt.nodes:
            n.select = False
        node.select = True
        nt.nodes.active = node


def bake(objs: list, mats: list, img: bpy.types.Image, kind: str, samples: int, **kw) -> None:
    """Bake without margin (see the module docstring); falls back to the CPU when the GPU runs out of memory."""
    set_target(mats, img)
    select_only(objs, objs[0])
    for device in ("GPU", "CPU"):
        setup_cycles(samples, device)
        try:
            bpy.ops.object.bake(type=kind, use_clear=True, margin=0, target="IMAGE_TEXTURES", **kw)
            break
        except RuntimeError as err:
            print("BAKE failed on", device, err)
            if device == "CPU":
                raise
    print("BAKED", kind, img.name, flush=True)


def metallic_constant(mats: list) -> float | None:
    """The shared metallic value when no atlas material drives Metallic (e.g. all 0), else None (bake it)."""
    vals = set()
    for m in mats:
        sock = m.node_tree.nodes["Principled BSDF"].inputs["Metallic"]
        if sock.is_linked:
            return None
        vals.add(round(sock.default_value, 4))
    return vals.pop() if len(vals) == 1 else None


# --- 3. images ----------------------------------------------------------------------------------------


def pixels(img: bpy.types.Image) -> np.ndarray:
    arr = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    return arr.reshape(img.size[1], img.size[0], 4)


def set_pixels(img: bpy.types.Image, arr: np.ndarray) -> None:
    img.pixels.foreach_set(np.clip(arr, 0.0, 1.0).astype(np.float32).ravel())


def image_from(name: str, arr: np.ndarray, non_color: bool) -> bpy.types.Image:
    img = new_image(name, arr.shape[1], non_color)
    set_pixels(img, arr)
    return img


def save_png(img: bpy.types.Image, path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()


def extend_islands(rgba: np.ndarray, mask: np.ndarray, px: int) -> tuple[np.ndarray, np.ndarray]:
    """Grow the islands by px pixels; each new pixel is the mean of its already filled 4-neighbours (like Blender's
    EXTEND margin, but over the whole atlas at once). Returns the colors and the grown mask."""
    col = rgba * mask[..., None]
    filled = mask.copy()
    for _ in range(px):
        w = filled.astype(np.float32)
        acc = np.zeros_like(col)
        cnt = np.zeros_like(w)
        acc[1:] += col[:-1]
        cnt[1:] += w[:-1]
        acc[:-1] += col[1:]
        cnt[:-1] += w[1:]
        acc[:, 1:] += col[:, :-1]
        cnt[:, 1:] += w[:, :-1]
        acc[:, :-1] += col[:, 1:]
        cnt[:, :-1] += w[:, 1:]
        new = (cnt > 0) & ~filled
        col[new] = acc[new] / cnt[new][:, None]
        filled |= new
    return col, filled


def fill_gaps(rgba: np.ndarray, keep: np.ndarray) -> np.ndarray:
    """Push-pull fill: every pixel outside `keep` gets a blurred average of the nearby islands, so the gaps between
    islands carry their colors all the way down the mip chain (square power-of-two images)."""
    w = keep.astype(np.float32)[..., None]
    levels = [(rgba * w, w)]
    while levels[-1][1].shape[0] > 1:
        c, wt = levels[-1]
        c = c.reshape(c.shape[0] // 2, 2, c.shape[1] // 2, 2, 4).sum(axis=(1, 3))
        wt = wt.reshape(wt.shape[0] // 2, 2, wt.shape[1] // 2, 2, 1).sum(axis=(1, 3))
        levels.append((c, wt))
    c, wt = levels[-1]
    col = c / np.maximum(wt, 1e-8)
    for c, wt in reversed(levels[:-1]):
        up = np.repeat(np.repeat(col, 2, axis=0), 2, axis=1)
        col = np.where(wt > 0, c / np.maximum(wt, 1e-8), up)
    col = np.where(keep[..., None], rgba, col)
    col[..., 3] = 1.0
    return col


def downsample(arr: np.ndarray, factor: int, renormalize: bool = False) -> np.ndarray:
    """Box filter by `factor` (in the stored encoding, as the GPU would filter it); a tangent-space normal map keeps
    unit length."""
    if factor == 1:
        return arr
    h, w, c = arr.shape
    small = arr.reshape(h // factor, factor, w // factor, factor, c).mean(axis=(1, 3))
    if renormalize:
        n = small[..., :3] * 2.0 - 1.0
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
        small[..., :3] = n * 0.5 + 0.5
    small[..., 3] = 1.0
    return small


def limit_tilt(rgba: np.ndarray, min_z: float) -> None:
    """Clamp a tangent-space normal map to at most acos(min_z) of tilt, in place (e.g. the undersides of thin
    smooth-shaded blades bake garbage: their smooth normals are far from the geometric ones the bump works from)."""
    n = rgba[..., :3] * 2.0 - 1.0
    bad = n[..., 2] < min_z
    xy = n[..., :2]
    xy_len = np.maximum(np.linalg.norm(xy, axis=-1, keepdims=True), 1e-6)
    clamped = np.concatenate([xy / xy_len * math.sqrt(1 - min_z * min_z), np.full(xy_len.shape, min_z)], axis=-1)
    n[bad] = clamped[bad]
    rgba[..., :3] = n * 0.5 + 0.5
    print(f"NORMAL clamped {int(bad.sum())} px (tilt > {math.degrees(math.acos(min_z)):.0f} deg)")


def bake_maps(job: Job, objs: list, mats: list) -> dict:
    """Bake every pass at the bake size and return the final images {basecolor, orm, normal(, emission)}."""
    size = job.bake_size()
    samples = SAMPLES | job.samples
    passes = [("basecolor", "Base Color"), ("roughness", "Roughness")]
    metal = metallic_constant(mats)
    if metal is None:
        passes.append(("metallic", "Metallic"))
    print("METALLIC", "baked" if metal is None else f"constant {metal}")
    raw = {}
    for key, socket in passes:
        raw[key] = new_image(f"bake_{key}", size, non_color=key != "basecolor")
        for m in mats:
            route_to_emission(m, socket)
        bake(objs, mats, raw[key], "EMIT", samples[socket])
    if job.emission_strength:
        raw["emission"] = new_image("bake_emission", size, non_color=False)
        for m in mats:
            route_glow(m, job.emission_strength)
        bake(objs, mats, raw["emission"], "EMIT", samples["Emission"])
    mask_img = new_image("bake_mask", size, non_color=True)
    for m in mats:
        route_white(m)
    bake(objs, mats, mask_img, "EMIT", 1)
    for m in mats:
        restore_bsdf(m)
    bpy.context.scene.world.light_settings.distance = job.ao_distance
    raw["ao"] = new_image("bake_ao", size, non_color=True)
    bake(objs, mats, raw["ao"], "AO", samples["AO"])
    raw["normal"] = new_image("bake_normal", size, non_color=True)
    bake(objs, mats, raw["normal"], "NORMAL", samples["Normal"], normal_space="TANGENT")

    # Coverage exactly as Cycles rasterizes the islands; grow them, fill the rest of the gaps.
    mask = pixels(mask_img)[..., 0] > 0.5
    print(f"ATLAS coverage (Cycles mask) {mask.mean():.3f}")
    save_png(mask_img, job.game / "bake_mask.png")
    px = {}
    for key, img in raw.items():
        col, keep = extend_islands(pixels(img), mask, job.extend_px)
        px[key] = fill_gaps(col, keep)
    if job.normal_min_z is not None:
        limit_tilt(px["normal"], job.normal_min_z)
    set_pixels(raw["ao"], px["ao"])
    save_png(raw["ao"], job.game / "bake_ao.png")

    orm = np.ones((size, size, 4), dtype=np.float32)
    orm[..., 0] = 1.0 - job.ao_strength * (1.0 - px["ao"][..., 0])
    orm[..., 1] = px["roughness"][..., 0]
    orm[..., 2] = metal if metal is not None else px["metallic"][..., 0]
    px["orm"] = orm
    ss = job.supersample
    out = {}
    for key in ("basecolor", "orm", "normal", "emission"):
        if key in px:
            arr = downsample(px[key], ss, renormalize=key == "normal")
            out[key] = image_from(f"{job.name}_{key}", arr, non_color=key in ("orm", "normal"))
            save_png(out[key], job.game / f"{job.name}_{key}.png")
    for img in (*raw.values(), mask_img):
        bpy.data.images.remove(img)
    return out


# --- 4. game materials --------------------------------------------------------------------------------


def gltf_output_group() -> bpy.types.NodeTree:
    """The glTF exporter reads occlusion from a node group called "glTF Material Output"."""
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is None:
        ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def _replace(name: str) -> tuple:
    """A fresh material `name`; a procedural one of that name is kept as "<name>_procedural"."""
    old = bpy.data.materials.get(name)
    if old:
        old.name = name + "_procedural"
    return C._new_material(name)


def mat_baked(name: str, maps: dict, emission_strength: float | None = None) -> bpy.types.Material:
    """PBR material on the baked textures: base color, ORM (occlusion via the glTF output group), normal map and,
    with an emission map, emission = texture * emission_strength."""
    mat, nt, bsdf = _replace(name)

    def tex(img, x, y):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.location = (x, y)
        return n

    nt.links.new(tex(maps["basecolor"], -700, 400).outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-400, 100)
    nt.links.new(tex(maps["orm"], -700, 100).outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    occ = nt.nodes.new("ShaderNodeGroup")
    occ.node_tree = gltf_output_group()
    occ.location = (-150, -250)
    nt.links.new(sep.outputs["Red"], occ.inputs["Occlusion"])
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-400, -200)
    nt.links.new(tex(maps["normal"], -700, -200).outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if "emission" in maps:
        nt.links.new(tex(maps["emission"], -700, -500).outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def mat_constant(name: str, color, roughness: float = 0.5, emission: float = 0.0) -> bpy.types.Material:
    """Constant material for a part outside the atlas (replaces a procedural one of the same name); emission > 0
    glows in its own color."""
    mat, _nt, bsdf = _replace(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def is_constant(mat: bpy.types.Material) -> bool:
    """True when the material is only a Principled BSDF with constant inputs on the output."""
    kinds = {n.bl_idname for n in mat.node_tree.nodes}
    return kinds <= {"ShaderNodeBsdfPrincipled", "ShaderNodeOutputMaterial"}


# --- check renders ------------------------------------------------------------------------------------


def render_closeup(job: Job, obj: bpy.types.Object, parts: list, view: str, turn: float = 0.0) -> None:
    """A check render of `obj` alone (the other `parts` hidden) at the origin, turned `turn` around Z, framed by its
    size with the scale figure beside it: check_<name>_<view>.png in the job's game folder."""
    for o in parts:
        o.hide_render = o is not obj
    loc, rot = obj.location.copy(), obj.rotation_euler.copy()
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, turn)
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


# --- main ---------------------------------------------------------------------------------------------


def bake_and_export(job: Job) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(job.source))
    C.ASSET = job.asset
    preview = bpy.data.collections.get("Preview")
    if preview:
        for obj in list(preview.all_objects):
            bpy.data.objects.remove(obj)
        bpy.data.collections.remove(preview)
    props = (job.prepare(job) if job.prepare else None) or []
    objs = [bpy.data.objects[n] for n in job.atlas]
    for o in objs:
        apply_modifiers(o)
    (job.unwrap or unwrap_atlas)(job, objs)
    cover, density = uv_coverage(objs)
    print(f"ATLAS UV coverage {cover:.3f}, texel density {math.sqrt(density) * job.size:.0f} px/m at {job.size}")
    mats = sorted({s.material for o in objs for s in o.material_slots if s.material}, key=lambda m: m.name)
    print("ATLAS materials", [m.name for m in mats])

    maps = bake_maps(job, objs, mats)

    # Swap materials: one baked PBR material on the atlas objects; the procedural ones stay out of the .blend.
    baked = mat_baked(job.material, maps, job.emission_strength)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(baked)
        for p in o.data.polygons:
            p.material_index = 0
        for name in job.drop_attributes:
            o.data.attributes.remove(o.data.attributes[name])
    for m in mats:
        if m.users == 0:
            bpy.data.materials.remove(m)
    for o in props:
        bpy.data.objects.remove(o)
    if job.finish:
        job.finish(job, objs)
    for o in C.collection(job.asset).all_objects:
        if o.type != "MESH":
            continue
        for s in o.material_slots:
            assert o in objs or is_constant(s.material), ("not baked", o.name, s.material.name)
            if o.name not in job.double_sided:  # closed meshes: export single-sided (glTF doubleSided=false)
                s.material.use_backface_culling = True

    # Pack the baked images, so the committed .blend doesn't point at files in tmp/.
    bpy.ops.file.pack_all()
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    layout = {n: tuple(bpy.data.objects[n].location) for n in job.export_at_origin}
    for n in layout:
        bpy.data.objects[n].location = (0, 0, 0)
    C.export_glb(job.glb)
    for n, loc in layout.items():
        bpy.data.objects[n].location = loc
    print(f"GLB size {job.glb.stat().st_size / 1e6:.2f} MB")
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backup next to the source
    job.blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(job.blend))


def glb_summary(job: Job) -> None:
    data = job.glb.read_bytes()
    n = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20 : 20 + n])
    print("GLB scene roots", [j["nodes"][i]["name"] for i in j["scenes"][0]["nodes"]])
    print(
        "GLB nodes",
        [
            (
                nd["name"],
                [round(v, 3) for v in nd.get("translation", [0, 0, 0])],
                nd.get("rotation"),
                nd.get("scale"),
                len(nd.get("children", [])),
            )
            for nd in j["nodes"]
        ],
    )
    print(
        "GLB meshes",
        [
            (m["name"], [p.get("material") for p in m["primitives"]], sorted(m["primitives"][0]["attributes"]))
            for m in j["meshes"]
        ],
    )
    print("GLB materials", [(m["name"], m.get("doubleSided", False)) for m in j["materials"]])
    print(
        "GLB images",
        [
            (im.get("name"), im.get("mimeType"), j["bufferViews"][im["bufferView"]]["byteLength"])
            for im in j.get("images", [])
        ],
    )
    print(f"GLB {job.material} material", json.dumps(next(m for m in j["materials"] if m["name"] == job.material)))
    print(f"GLB size {job.glb.stat().st_size / 1e6:.2f} MB")


def import_glb(job: Job) -> list:
    """Re-import the .glb into a fresh scene (objects in the asset's collection, so the preview helpers treat it
    like the build did) and print per-mesh checks; returns the mesh objects."""
    C.reset(job.asset)
    bpy.ops.import_scene.gltf(filepath=str(job.glb))
    for o in list(bpy.context.scene.objects):
        for c in o.users_collection:
            c.objects.unlink(o)
        C.collection(job.asset).objects.link(o)
    dg = bpy.context.evaluated_depsgraph_get()
    meshes, total = [], 0
    for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        if o.type != "MESH":
            print(
                "CHECK node",
                o.name,
                o.type,
                "parent",
                o.parent.name if o.parent else None,
                tuple(round(v, 3) for v in o.location),
            )
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        pts = [o.matrix_world @ v.co for v in me.vertices]
        lo, hi = Vector(map(min, *pts)), Vector(map(max, *pts))
        print(
            f"CHECK {o.name}: tris {len(me.loop_triangles)} parent {o.parent.name if o.parent else None}"
            f" origin {tuple(round(v, 3) for v in o.matrix_world.translation)} min {tuple(round(v, 2) for v in lo)}"
            f" max {tuple(round(v, 2) for v in hi)} mats {[m.name for m in me.materials]} uvs {len(me.uv_layers)}"
        )
        total += len(me.loop_triangles)
        ev.to_mesh_clear()
        meshes.append(o)
    print("CHECK triangles", total)
    return meshes


def run(job: Job, checks: Callable | None = None) -> None:
    """Bake and export (unless the script got "verify"), then summarize the .glb, re-import it and run
    checks(job, meshes) (check renders into job.game)."""
    job = redirected(job)
    if "verify" not in sys.argv:
        bake_and_export(job)
    glb_summary(job)
    meshes = import_glb(job)
    if checks:
        checks(job, meshes)
