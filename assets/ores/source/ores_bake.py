"""Game-ready ore clusters: bake the procedural rock of ores_procedural.blend into one shared texture atlas.

Run from the repo root, after ores_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/ores/source/ores_bake.py          # bake, export, check renders
    tools/blender.sh assets/ores/source/ores_bake.py verify   # only re-import and render the checks

Writes the game asset assets/ores/ores.glb (textures embedded) and its source assets/ores/source/ores.blend; the
separate PNGs, check renders and the procedural-vs-baked comparison sheets go to tmp/assets/ores/game/.

Steps: open the .blend, drop the preview props, add a temporary ground plane and cliff wall (so the AO in the
bake sees what the previews saw), apply modifiers on the bases, unwrap all nine Base_* meshes into one UV atlas
(faces buried under the ground or pressed against the cliff get almost no texture space), bake albedo / roughness
(emission trick), AO and a tangent-space normal map at twice the texture size and filter them down, pack
AO+roughness+metallic into an ORM image, swap in one "OreRock" PBR material, keep the crystals on the constant
"OreCrystal" placeholder (the game overrides it), move the roots from their layout grid to the origin, export
ores.glb, then re-import it into a fresh scene and render check images with the shared preview lighting.
"""

import json
import math
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "ores"
GLB = ROOT / "assets" / "ores" / "ores.glb"
BLEND = ROOT / "assets" / "ores" / "source" / "ores.blend"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402

GAME = OUT / "game"
ASSET = "Ores"
TYPES = ("cyan", "green", "violet")
VARIANTS = ("a", "b", "wall")
SIZE = 1024  # shared atlas for the nine bases (brief); TBD (playtest)
SS = 2  # bake at SIZE * SS and filter down: anti-aliased cracks and edges
MARGIN_PX = 8 * SS
# Gap between UV islands as a fraction of the atlas (2 px at 1024). The bases are faceted rock, so smart project
# makes ~1750 small islands: a scaled margin would eat most of the atlas.
ISLAND_MARGIN = 0.002
LAYOUT_SPACING = 3.4  # roots sit on this grid in the procedural .blend (ores_build.py)
# Preview-only crystal look, same as ores_build.py (the game owns the crystal material).
ORE_COLOR = {"cyan": (0.2, 0.85, 0.95), "green": (0.35, 0.9, 0.25), "violet": (0.7, 0.3, 0.95)}
PREVIEW_GLOW = 1.0


def bases() -> list:
    return [bpy.data.objects[f"Base_{t}_{v}"] for t in TYPES for v in VARIANTS]


def roots() -> list:
    return [bpy.data.objects[f"Ore_{t}_{v}"] for t in TYPES for v in VARIANTS]


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
    scene.render.bake.margin = MARGIN_PX
    scene.render.bake.margin_type = "EXTEND"


def select_only(objs: list, active) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


# --- 1. prepare geometry ------------------------------------------------------------------------------


def apply_modifiers(obj: bpy.types.Object) -> None:
    """Bake on the final geometry, keeping the "Crust" attribute the rock material reads."""
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    me.name = obj.name
    bpy.data.meshes.remove(old)


def bake_props() -> list:
    """Ground plane at z = 0 under everything and the cliff face behind the wall row (y = +LAYOUT_SPACING), as in
    the previews: the rock's AO picks up the contact shadow where it meets terrain and cliff."""
    mat, _nt, bsdf = C._new_material("BakeProp")
    bsdf.inputs["Base Color"].default_value = (0.03, 0.03, 0.03, 1.0)
    props = []
    for name, loc, rot, scale in (
        ("BakeGround", (0, 0, 0), (0, 0, 0), (12, 12, 1)),
        ("BakeCliff", (0, LAYOUT_SPACING, 1.6), (math.radians(90), 0, 0), (12, 1.6, 1)),
    ):
        bpy.ops.mesh.primitive_plane_add(size=1)
        obj = bpy.context.active_object
        obj.name = name
        obj.location = loc
        obj.rotation_euler = rot
        obj.scale = scale
        C.assign(obj, mat)
        props.append(obj)
    return props


def hidden_face(obj: bpy.types.Object, poly) -> bool:
    """Faces the camera never sees: fully under the ground (z <= 0), or the flat back of a wall cluster that
    lies on the cliff plane (y = 0, facing +Y)."""
    zs = [obj.data.vertices[i].co.z for i in poly.vertices]
    if max(zs) < 0.003:
        return True
    if obj.name.endswith("_wall"):
        ys = [obj.data.vertices[i].co.y for i in poly.vertices]
        return poly.normal.y > 0.95 and max(abs(y) for y in ys) < 0.003
    return False


def unwrap_atlas(objs: list) -> None:
    for o in objs:
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    # Hidden faces: shrink each to a speck around its own center (it becomes its own tiny island).
    shrunk = 0
    for o in objs:
        uv = o.data.uv_layers["UVMap"].data
        for poly in o.data.polygons:
            if not hidden_face(o, poly):
                continue
            loops = list(poly.loop_indices)
            c = sum((Vector(uv[i].uv) for i in loops), Vector((0, 0))) / len(loops)
            for i in loops:
                uv[i].uv = c + (Vector(uv[i].uv) - c) * 0.03
            shrunk += 1
    print("UV hidden faces shrunk", shrunk)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.uv.select_all(action="SELECT")
    except RuntimeError:
        pass  # no UV editor context: smart_project left every UV selected anyway
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=ISLAND_MARGIN)
    bpy.ops.object.mode_set(mode="OBJECT")


def uv_coverage(objs: list) -> float:
    area = 0.0
    for o in objs:
        uv = o.data.uv_layers["UVMap"].data
        for poly in o.data.polygons:
            pts = [Vector(uv[i].uv) for i in poly.loop_indices]
            for k in range(1, len(pts) - 1):
                a, b = pts[k] - pts[0], pts[k + 1] - pts[0]
                area += abs(a.x * b.y - a.y * b.x) / 2
    return area


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
    set_target(mats, img)
    select_only(objs, objs[0])
    for device in ("GPU", "CPU"):  # five agents share the GPU: fall back to the CPU when it runs out of memory
        setup_cycles(samples, device)
        try:
            bpy.ops.object.bake(type=kind, use_clear=True, margin=MARGIN_PX, margin_type="EXTEND", target="IMAGE_TEXTURES", **kw)
            break
        except RuntimeError as err:
            print("BAKE failed on", device, err)
            if device == "CPU":
                raise
    print("BAKED", kind, img.name)


def pixels(img: bpy.types.Image) -> np.ndarray:
    arr = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    return arr.reshape(img.size[1], img.size[0], 4)


def down(arr: np.ndarray) -> np.ndarray:
    """Box filter by SS (supersampled bake -> texture size)."""
    h, w, c = arr.shape
    return arr.reshape(h // SS, SS, w // SS, SS, c).mean(axis=(1, 3))


def image_from(name: str, arr: np.ndarray, non_color: bool) -> bpy.types.Image:
    img = new_image(name, arr.shape[1], non_color)
    img.pixels.foreach_set(np.clip(arr, 0.0, 1.0).astype(np.float32).ravel())
    return img


def save_png(img: bpy.types.Image, path: pathlib.Path) -> None:
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()


# --- 3. game materials --------------------------------------------------------------------------------


def gltf_output_group() -> bpy.types.NodeTree:
    """The glTF exporter reads occlusion from a node group called "glTF Material Output"."""
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is None:
        ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def mat_rock_baked(base: bpy.types.Image, orm: bpy.types.Image, normal: bpy.types.Image) -> bpy.types.Material:
    old = bpy.data.materials.get("OreRock")
    if old:
        old.name = "OreRock_procedural"
    mat, nt, bsdf = C._new_material("OreRock")

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
    return mat


def is_constant(mat: bpy.types.Material) -> bool:
    """True when the material is only a Principled BSDF with constant inputs on the output."""
    kinds = {n.bl_idname for n in mat.node_tree.nodes}
    return kinds <= {"ShaderNodeBsdfPrincipled", "ShaderNodeOutputMaterial"}


# --- main ---------------------------------------------------------------------------------------------


def bake_and_export() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(OUT / "ores_procedural.blend"))
    C.ASSET = ASSET
    for obj in list(C.collection("Preview").all_objects):
        bpy.data.objects.remove(obj)
    for m in [m for m in bpy.data.materials if m.name.startswith("Preview")]:
        bpy.data.materials.remove(m)
    props = bake_props()
    objs = bases()
    for o in objs:
        apply_modifiers(o)
        assert "Crust" in o.data.color_attributes, o.name
    unwrap_atlas(objs)
    cov = uv_coverage(objs)
    area = sum(p.area for o in objs for p in o.data.polygons)
    print(f"UV coverage {cov:.3f}, {math.sqrt(cov / area) * SIZE:.0f} px/m")
    mats = sorted({s.material for o in objs for s in o.material_slots if s.material}, key=lambda m: m.name)
    print("ATLAS materials", [m.name for m in mats])
    assert [m.name for m in mats] == ["OreRock"], mats

    GAME.mkdir(parents=True, exist_ok=True)
    big = SIZE * SS
    img_base = new_image("bake_basecolor", big, non_color=False)
    img_rough = new_image("bake_roughness", big, non_color=True)
    img_ao = new_image("bake_ao", big, non_color=True)
    img_nrm = new_image("bake_normal", big, non_color=True)

    for img, socket in ((img_base, "Base Color"), (img_rough, "Roughness")):
        for m in mats:
            route_to_emission(m, socket)
        bake(objs, mats, img, "EMIT", 32)
    for m in mats:
        restore_bsdf(m)
    bpy.context.scene.world.light_settings.distance = 0.25
    bake(objs, mats, img_ao, "AO", 64)
    bake(objs, mats, img_nrm, "NORMAL", 16, normal_space="TANGENT")

    # Filter down to the texture size.
    base = down(pixels(img_base))
    base[..., 3] = 1.0
    nrm = down(pixels(img_nrm))
    n = nrm[..., :3] * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    nrm[..., :3] = n * 0.5 + 0.5
    nrm[..., 3] = 1.0
    # ORM: occlusion (softened, the albedo already carries cavity darkening), roughness, metallic (rock: none).
    ao = down(pixels(img_ao))[..., 0]
    orm = np.ones((SIZE, SIZE, 4), dtype=np.float32)
    orm[..., 0] = 1.0 - 0.6 * (1.0 - ao)
    orm[..., 1] = down(pixels(img_rough))[..., 0]
    orm[..., 2] = 0.0
    img_base_out = image_from("ores_basecolor", base, non_color=False)
    img_nrm_out = image_from("ores_normal", nrm, non_color=True)
    img_orm_out = image_from("ores_orm", orm, non_color=True)
    for img in (img_base, img_rough, img_ao, img_nrm):
        save_png(img, GAME / f"{img.name}_{big}.png")
    save_png(img_base_out, GAME / "ores_basecolor.png")
    save_png(img_nrm_out, GAME / "ores_normal.png")
    save_png(img_orm_out, GAME / "ores_orm.png")
    for img in (img_base, img_rough, img_ao, img_nrm):
        bpy.data.images.remove(img)

    # Swap materials: one PBR material on the bases, the crystals keep the constant placeholder.
    rock = mat_rock_baked(img_base_out, img_orm_out, img_nrm_out)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(rock)
        for p in o.data.polygons:
            p.material_index = 0
        o.data.color_attributes.remove(o.data.color_attributes["Crust"])  # baked; keep it out of the glb
    bpy.data.materials.remove(bpy.data.materials["OreRock_procedural"])
    for o in props:
        bpy.data.objects.remove(o)
    bpy.data.materials.remove(bpy.data.materials["BakeProp"])
    for o in C.collection(ASSET).all_objects:
        if o.type == "MESH" and o not in objs:
            assert o.name.startswith("Crystal_"), o.name
            assert [m.name for m in o.data.materials] == ["OreCrystal"], o.name
            assert is_constant(o.data.materials[0]), o.name
    # Closed (or buried-open) meshes: export single-sided (glTF doubleSided=false).
    for m in (rock, bpy.data.materials["OreCrystal"]):
        m.use_backface_culling = True

    # Pack the baked images, so the committed .blend doesn't point at files in tmp/.
    bpy.ops.file.pack_all()
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    # The game places each cluster by its root: export with every root at the origin, keep the grid in the .blend.
    layout = {r.name: tuple(r.location) for r in roots()}
    for r in roots():
        r.location = (0, 0, 0)
    C.export_glb(GLB)
    for r in roots():
        r.location = layout[r.name]
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backup next to the source
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print(f"GLB size {GLB.stat().st_size / 1e6:.2f} MB")


def glb_summary(path: pathlib.Path) -> None:
    data = path.read_bytes()
    n = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20 : 20 + n])
    print("GLB scene roots", [j["nodes"][i]["name"] for i in j["scenes"][0]["nodes"]])
    for nd in j["nodes"]:
        if nd["name"].startswith(("Ore_", "Base_")):
            print("GLB node", nd["name"], [round(v, 3) for v in nd.get("translation", [0, 0, 0])], nd.get("rotation"), nd.get("scale"), len(nd.get("children", [])))
    print("GLB node count", len(j["nodes"]), "meshes", len(j["meshes"]))
    print("GLB materials", [(m["name"], m.get("doubleSided", False)) for m in j["materials"]])
    print("GLB images", [(im.get("name"), im.get("mimeType"), j["bufferViews"][im["bufferView"]]["byteLength"]) for im in j.get("images", [])])
    attrs = sorted({k for m in j["meshes"] for p in m["primitives"] for k in p["attributes"]})
    print("GLB vertex attributes", attrs)
    mm = next(m for m in j["materials"] if m["name"] == "OreRock")
    print("GLB OreRock material", json.dumps(mm))


# --- checks -------------------------------------------------------------------------------------------


def tris_of(obj, dg) -> int:
    me = obj.evaluated_get(dg).to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    obj.evaluated_get(dg).to_mesh_clear()
    return n


def bounds(objs: list) -> tuple:
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def preview_crystal(typ: str) -> bpy.types.Material:
    """Like ores_build.py: the game's ore material, dimmer (Cycles + AgX burns the real energy to white)."""
    mat = C.mat_emissive(f"PreviewOre_{typ}", ORE_COLOR[typ], PREVIEW_GLOW)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Base Color"].default_value = (*(c * 0.3 for c in ORE_COLOR[typ]), 1.0)
    return mat


def cliff(show: bool) -> None:
    """Same stand-in cliff as ores_build.py's previews (its front face on the wall plane y = 0)."""
    obj = bpy.data.objects.get("PreviewCliff")
    if obj is None:
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        for c in obj.users_collection:
            c.objects.unlink(obj)
        C.link(obj, None, "Preview")
        obj.name = "PreviewCliff"
        obj.scale = (5.0, 1.0, 3.2)
        obj.location = (0, 0.5, 1.6)
        C.assign(obj, bpy.data.materials["PreviewRock"])
    obj.hide_render = not show


def contact_sheet(paths: list, out: pathlib.Path, cols: int, cell: int) -> None:
    rows = (len(paths) + cols - 1) // cols
    sheet = np.zeros((rows * cell, cols * cell, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, p in enumerate(paths):
        if not p.exists():
            continue
        img = bpy.data.images.load(str(p))
        if img.size[0] != cell:
            img.scale(cell, cell)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * cell  # Blender images start at the bottom row
        sheet[y0 : y0 + cell, c * cell : (c + 1) * cell] = pixels(img)
        bpy.data.images.remove(img)
    img = bpy.data.images.new("sheet", cols * cell, rows * cell, alpha=False)
    img.pixels.foreach_set(sheet.ravel())
    save_png(img, out)
    bpy.data.images.remove(img)


def verify() -> None:
    C.reset(ASSET)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    imported = [o for o in bpy.context.scene.objects]
    for o in imported:  # into the asset collection, so the preview helpers treat it like the build did
        for c in o.users_collection:
            c.objects.unlink(o)
        C.collection(ASSET).objects.link(o)
    dg = bpy.context.evaluated_depsgraph_get()
    total = 0
    for name in [f"Ore_{t}_{v}" for t in TYPES for v in VARIANTS]:
        root = bpy.data.objects[name]
        kids = list(root.children)
        base = [o for o in kids if o.name.startswith("Base_")]
        crys = [o for o in kids if o.name.startswith("Crystal_")]
        other = [o.name for o in kids if o not in base and o not in crys]
        bt = sum(tris_of(o, dg) for o in base)
        ct = sum(tris_of(o, dg) for o in crys)
        total += bt + ct
        lo, hi = bounds(base)
        clo, chi = bounds(crys)
        rad = max(math.hypot(*(o.matrix_world @ v.co).xy) for o in crys for v in o.data.vertices if (o.matrix_world @ v.co).z > 0.04)
        mats = sorted({m.name for o in kids for m in o.data.materials})
        print(
            f"CHECK {name}: root at {tuple(round(x, 3) for x in root.location)}, base {[o.name for o in base]} {bt} tris, "
            f"{len(crys)} crystals {ct} tris, total {bt + ct}; base min {tuple(round(x, 2) for x in lo)} max {tuple(round(x, 2) for x in hi)}; "
            f"crystal top {chi.z:.2f} radius {rad:.2f}; base origin {tuple(round(x, 3) for x in base[0].location)}; mats {mats}; other {other}"
        )
    print("CHECK triangles", total)
    print("CHECK top-level", sorted(o.name for o in imported if o.parent is None))
    crystals = [o for o in imported if o.name.startswith("Crystal_")]
    print("CHECK crystals", len(crystals), "names ok", all(o.name.split("_")[1] in TYPES for o in crystals))

    C.preview_scene(crystals=False, figure_location=(1.7, 1.7, 0.0))
    for o in crystals:
        C.assign(o, preview_crystal(o.name.split("_")[1]))
    cliff(False)
    all_roots = [bpy.data.objects[f"Ore_{t}_{v}"] for t in TYPES for v in VARIANTS]

    def solo(keep) -> None:
        for r in all_roots:
            for o in [r] + list(r.children_recursive):
                o.hide_render = r is not keep and keep is not None

    shots = []
    for r in all_roots:
        solo(r)
        ground = not r.name.endswith("_wall")
        cliff(not ground)
        tz = 0.35 if ground else 0.65
        ty = 0.0 if ground else -0.3
        stem = r.name[len("Ore_") :]
        p_iso = GAME / f"check_{stem}_iso.png"
        p_hero = GAME / f"check_{stem}_hero.png"
        C.render(p_iso, "iso", 64, 768, target=(0, ty, tz), zoom=0.4)
        C.render(p_hero, "hero", 64, 768, target=(0, ty, tz + 0.07), zoom=0.48)
        shots += [p_iso, p_hero]
    cliff(False)
    solo(None)
    bpy.data.objects["PreviewFigure"].location = (4.6, 4.6, 0)
    for r in all_roots:  # the build's layout grid, game-camera distance
        t, v = r.name.split("_")[1:]
        r.location = ((TYPES.index(t) - 1) * LAYOUT_SPACING, (VARIANTS.index(v) - 1) * LAYOUT_SPACING, 0)
    C.render(GAME / "check_game_distance.png", "iso", 64, 1024, target=(0, 0, 0.3), zoom=1.45)
    C.render(GAME / "check_iso.png", "iso", 96, 1024, target=(0, 0, 0.3), zoom=1.0)
    C.render(GAME / "check_hero.png", "hero", 96, 1024, target=(0, 0, 0.3), zoom=1.3)
    # Procedural previews (left) next to the baked checks (right).
    for view in ("iso", "hero"):
        paths = []
        for t in TYPES:
            for v in VARIANTS:
                paths += [OUT / f"render_{t}_{v}_{view}.png", GAME / f"check_{t}_{v}_{view}.png"]
        contact_sheet(paths, GAME / f"compare_{view}.png", 6, 384)


if "verify" not in sys.argv:
    bake_and_export()
glb_summary(GLB)
verify()
