"""Game-ready rocks kit: bake the procedural look of rocks_procedural.blend into one shared texture set.

Run from the repo root, after rocks_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/rocks/source/rocks_bake.py          # bake, export, check renders
    tools/blender.sh assets/rocks/source/rocks_bake.py verify   # only re-import and render the checks

Writes the game asset assets/rocks/rocks.glb (textures embedded) and its source assets/rocks/source/rocks.blend;
the separate PNGs and check renders go to tmp/assets/rocks/game/.

Steps: open the .blend, drop the preview props, apply modifiers, unwrap all ten variants into one UV atlas (charts
grown over the facets and flattened conformally, folded faces split off, the never-seen bottom caps shrunk, the
cliffs' flat backs at half density), bake albedo and roughness (emission trick), AO and a tangent-space normal map
at 2048, fill the gaps between the islands (push-pull, so mips don't bleed black), pack AO+roughness+metallic into
an ORM image, swap in one "Rock" PBR material, zero the variants' locations (they stand in a row for the bake),
export rocks.glb, then re-import it into a fresh scene and render check images with the shared preview lighting.

Every variant is its own mesh node under the "Rocks" root, origin at its ground contact point; a ScatterType reads
one mesh by name. Texel density and budgets are TBD (playtest).
"""

import json
import math
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "rocks"
GLB = ROOT / "assets" / "rocks" / "rocks.glb"
BLEND = ROOT / "assets" / "rocks" / "source" / "rocks.blend"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402

C.ASSET = "Rocks"
GAME = OUT / "game"
SIZE = 2048
MARGIN_PX = 3  # pack margin (px at 2048); islands end up about 5 px apart
BAKE_MARGIN_PX = 2  # less than half the island gap: one object's margin must not paint over another's island
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


def setup_cycles(samples: int) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    scene.cycles.device = "GPU"
    scene.cycles.samples = samples
    scene.render.bake.margin = BAKE_MARGIN_PX
    scene.render.bake.margin_type = "EXTEND"


def select_only(objs: list, active) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


# --- 1. prepare geometry ------------------------------------------------------------------------------


def apply_modifiers(obj: bpy.types.Object) -> None:
    """Bake on the final geometry so the UVs and the normal map match the export (the build applies its
    booleans already; this is a guard)."""
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    me.name = obj.name
    bpy.data.meshes.remove(old)


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


def unwrap_atlas(objs: list) -> None:
    for o in objs:
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
    print("UV charts", {o.name: mark_chart_seams(o) for o in objs})
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


def texel_density(objs: list) -> float:
    """Pixels per meter on the visible faces (bottom caps excluded)."""
    area3d = area_uv = 0.0
    for o in objs:
        me = o.data
        uv = me.uv_layers.active.data
        zmin = min(v.co.z for v in me.vertices)
        for p in me.polygons:
            if p.normal.z < -0.99 and p.center.z < zmin + 1e-3:
                continue
            pts = [uv[i].uv for i in p.loop_indices]
            a = 0.0
            for i in range(len(pts)):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % len(pts)]
                a += x0 * y1 - x1 * y0
            area_uv += abs(a) / 2
            area3d += p.area
    print(f"UV visible area {area3d:.1f} m2, atlas coverage {area_uv:.3f}")
    return math.sqrt(area_uv * SIZE * SIZE / area3d)


# --- 2. bake ------------------------------------------------------------------------------------------


def new_image(name: str, size: int, non_color: bool) -> bpy.types.Image:
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def output_node(nt) -> bpy.types.Node:
    outs = [n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial"]
    return next((n for n in outs if n.is_active_output), outs[0])


def route_to_emission(mat: bpy.types.Material, input_name: str) -> None:
    """Feed whatever drives the BSDF input (link or constant) into an Emission shader on the output."""
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    em = nt.nodes.get("BakeEmit") or nt.nodes.new("ShaderNodeEmission")
    em.name = "BakeEmit"
    em.inputs["Strength"].default_value = 1.0
    for lk in list(em.inputs["Color"].links):
        nt.links.remove(lk)
    sock = bsdf.inputs[input_name]
    if sock.is_linked:
        nt.links.new(sock.links[0].from_socket, em.inputs["Color"])
    else:
        v = sock.default_value
        em.inputs["Color"].default_value = (v[0], v[1], v[2], 1.0) if hasattr(v, "__len__") else (v, v, v, 1.0)
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
    setup_cycles(samples)
    set_target(mats, img)
    select_only(objs, objs[0])
    bpy.ops.object.bake(type=kind, use_clear=True, margin=BAKE_MARGIN_PX, margin_type="EXTEND", target="IMAGE_TEXTURES", **kw)
    print("BAKED", kind, img.name)


def pixels(img: bpy.types.Image) -> np.ndarray:
    arr = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    return arr.reshape(img.size[1], img.size[0], 4)



def bake_mask(objs: list, mats: list) -> np.ndarray:
    """Coverage of the UV islands exactly as Cycles rasterizes them: a white emission baked without margin."""
    img = new_image("bake_mask", SIZE, non_color=True)
    for mat in mats:
        nt = mat.node_tree
        em = nt.nodes.get("BakeEmit") or nt.nodes.new("ShaderNodeEmission")
        em.name = "BakeEmit"
        for lk in list(em.inputs["Color"].links):
            nt.links.remove(lk)
        em.inputs["Color"].default_value = (1, 1, 1, 1)
        nt.links.new(em.outputs["Emission"], output_node(nt).inputs["Surface"])
    setup_cycles(1)
    set_target(mats, img)
    select_only(objs, objs[0])
    bpy.ops.object.bake(type="EMIT", use_clear=True, margin=0, target="IMAGE_TEXTURES")
    mask = pixels(img)[..., 0] > 0.5
    bpy.data.images.remove(img)
    return mask


def dilate(mask: np.ndarray, px: int) -> np.ndarray:
    out = mask.copy()
    for _ in range(px):
        m = out.copy()
        m[1:] |= out[:-1]
        m[:-1] |= out[1:]
        m[:, 1:] |= out[:, :-1]
        m[:, :-1] |= out[:, 1:]
        out = m
    return out


def fill_gaps(img: bpy.types.Image, keep: np.ndarray) -> None:
    """Push-pull fill: every pixel outside `keep` gets a blurred average of the nearby islands, so the gaps between
    islands carry rock colors all the way down the mip chain (Blender's own bake margin is kept small, see
    BAKE_MARGIN_PX)."""
    rgba = pixels(img)
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
    img.pixels.foreach_set(col.ravel())


def save_png(img: bpy.types.Image, path: pathlib.Path) -> None:
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()


# --- 3. game material ---------------------------------------------------------------------------------


def gltf_output_group() -> bpy.types.NodeTree:
    """The glTF exporter reads occlusion from a node group called "glTF Material Output"."""
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is None:
        ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def mat_rock_baked(base: bpy.types.Image, orm: bpy.types.Image, normal: bpy.types.Image) -> bpy.types.Material:
    old = bpy.data.materials.get("Rock")
    if old:
        old.name = "Rock_procedural"
    mat, nt, bsdf = C._new_material("Rock")

    def tex(img, x, y):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.location = (x, y)
        return n

    t_base = tex(base, -700, 300)
    nt.links.new(t_base.outputs["Color"], bsdf.inputs["Base Color"])
    t_orm = tex(orm, -700, 0)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-400, 0)
    nt.links.new(t_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    occ = nt.nodes.new("ShaderNodeGroup")
    occ.node_tree = gltf_output_group()
    occ.location = (-150, -250)
    nt.links.new(sep.outputs["Red"], occ.inputs["Occlusion"])
    t_nrm = tex(normal, -700, -300)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-400, -300)
    nt.links.new(t_nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    mat.use_backface_culling = True  # closed meshes: glTF doubleSided = false
    return mat


# --- main ---------------------------------------------------------------------------------------------


def bake_and_export() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(OUT / "rocks_procedural.blend"))
    C.ASSET = "Rocks"
    for obj in list(C.collection("Preview").all_objects):
        bpy.data.objects.remove(obj)
    objs = [bpy.data.objects[n] for n in VARIANTS]
    for o in objs:
        apply_modifiers(o)
    unwrap_atlas(objs)
    print(f"TEXEL density ~{texel_density(objs):.0f} px/m")
    mats = sorted({s.material for o in objs for s in o.material_slots if s.material}, key=lambda m: m.name)
    print("ATLAS materials", [m.name for m in mats])
    assert [m.name for m in mats] == ["Rock"], mats

    GAME.mkdir(parents=True, exist_ok=True)
    img_base = new_image("rocks_basecolor", SIZE, non_color=False)
    img_rough = new_image("bake_roughness", SIZE, non_color=True)
    img_ao = new_image("bake_ao", SIZE, non_color=True)
    img_nrm = new_image("rocks_normal", SIZE, non_color=True)

    # The base color carries AO cavity grime and Bevel-node ridges (both ray traced): more samples than flat colors.
    for img, socket, samples in ((img_base, "Base Color", 64), (img_rough, "Roughness", 32)):
        for m in mats:
            route_to_emission(m, socket)
        bake(objs, mats, img, "EMIT", samples)
    for m in mats:
        restore_bsdf(m)
    bpy.context.scene.world.light_settings.distance = 0.4
    bake(objs, mats, img_ao, "AO", 64)
    bake(objs, mats, img_nrm, "NORMAL", 16, normal_space="TANGENT")
    keep = dilate(bake_mask(objs, mats), BAKE_MARGIN_PX)
    for m in mats:
        restore_bsdf(m)
    print(f"ATLAS coverage (Cycles mask) {keep.mean():.3f}")
    for img in (img_base, img_rough, img_ao, img_nrm):
        fill_gaps(img, keep)

    # ORM: occlusion (softened, the albedo already carries cavity grime), roughness, metallic (rock: none).
    ao = pixels(img_ao)[..., 0]
    orm = np.ones((SIZE, SIZE, 4), dtype=np.float32)
    orm[..., 0] = 1.0 - 0.6 * (1.0 - ao)
    orm[..., 1] = pixels(img_rough)[..., 0]
    orm[..., 2] = 0.0
    img_orm = new_image("rocks_orm", SIZE, non_color=True)
    img_orm.pixels.foreach_set(orm.ravel())
    save_png(img_base, GAME / "rocks_basecolor.png")
    save_png(img_nrm, GAME / "rocks_normal.png")
    save_png(img_orm, GAME / "rocks_orm.png")
    save_png(img_ao, GAME / "bake_ao.png")

    # Swap in the baked material; drop the bake-only data the game doesn't need.
    rock = mat_rock_baked(img_base, img_orm, img_nrm)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(rock)
        for p in o.data.polygons:
            p.material_index = 0
        if "facet" in o.data.attributes:
            o.data.attributes.remove(o.data.attributes["facet"])
        o.location = (0, 0, 0)  # the bake row layout; in the game every variant sits at its own origin
        o.rotation_euler = (0, 0, 0)
    bpy.data.materials.remove(bpy.data.materials["Rock_procedural"])
    for img in (img_rough,):
        bpy.data.images.remove(img)

    # Pack the baked images, so the committed .blend doesn't point at files in tmp/.
    bpy.ops.file.pack_all()
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backup next to the source
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    C.export_glb(GLB)
    print(f"GLB size {GLB.stat().st_size / 1e6:.2f} MB")


def glb_summary(path: pathlib.Path) -> None:
    data = path.read_bytes()
    n = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20 : 20 + n])
    print("GLB nodes", [(nd["name"], [round(v, 3) for v in nd.get("translation", [0, 0, 0])], nd.get("rotation"), nd.get("scale"), nd.get("children")) for nd in j["nodes"]])
    print("GLB meshes", [(m["name"], len(m["primitives"]), sorted(m["primitives"][0]["attributes"])) for m in j["meshes"]])
    print("GLB materials", [m["name"] for m in j["materials"]])
    print("GLB images", [(im.get("name"), im.get("mimeType"), j["bufferViews"][im["bufferView"]]["byteLength"]) for im in j.get("images", [])])
    print("GLB Rock material", json.dumps(j["materials"][0]))


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


def render_closeup(obj: bpy.types.Object, rocks: list, view: str) -> None:
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
    C.render(GAME / f"check_{obj.name}_{view}.png", view=view, samples=32, size=640, target=tuple(target), zoom=zoom)
    obj.location, obj.rotation_euler, fig.location = loc, rot, fig_loc
    for o in rocks:
        o.hide_render = False


def verify() -> None:
    C.reset("Rocks")
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0
    rocks = []
    for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        if o.type != "MESH":
            print("CHECK node", o.name, o.type, tuple(round(v, 3) for v in o.location))
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        n = len(me.loop_triangles)
        lo = [min(v.co[i] for v in me.vertices) for i in range(3)]
        hi = [max(v.co[i] for v in me.vertices) for i in range(3)]
        print(
            f"CHECK {o.name}: tris={n} parent={o.parent.name if o.parent else None} loc={tuple(round(v, 3) for v in o.matrix_world.translation)}"
            f" min={tuple(round(v, 2) for v in lo)} max={tuple(round(v, 2) for v in hi)}"
            f" center_xy=({(lo[0] + hi[0]) / 2:.3f}, {(lo[1] + hi[1]) / 2:.3f}) mats={[m.name for m in o.data.materials]}"
            f" uvs={len(o.data.uv_layers)} attrs={sorted(a.name for a in o.data.attributes if not a.name.startswith('.'))}"
        )
        tris += n
        o.evaluated_get(dg).to_mesh_clear()
        rocks.append(o)
    print("CHECK triangles", tris)
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
        C.render(GAME / f"check_{view}.png", view=view, samples=64, size=1024, target=tuple(center), zoom=zoom)
    for name in CLOSEUPS:
        for view in ("iso", "hero"):
            render_closeup(bpy.data.objects[name], rocks, view)


if "verify" not in sys.argv:
    bake_and_export()
glb_summary(GLB)
verify()
