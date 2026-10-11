"""Game-ready alien nest: bake the procedural look of nest_procedural.blend into one shared texture set.

Run from the repo root, after nest_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/nest/source/nest_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/nest/source/nest_bake.py verify   # only re-import and render the checks

Writes the game asset assets/aliens/nest/nest.glb (textures embedded) and its source
assets/aliens/nest/source/nest.blend; the separate PNGs and check renders go to tmp/assets/nest/game/.

Steps: open the .blend, drop the preview props, apply modifiers on the procedural objects, unwrap Mound and
Tendrils into one UV atlas, bake albedo / roughness (emission trick), AO and a tangent-space normal map at 2048,
pack AO+roughness+metallic into an ORM image, swap in one "Nest" PBR material on the atlas objects plus simple
constant materials for the Slime and the emissive Mouth/Glands (the game overrides the Mouth's material to
pulse it), export nest.glb, then re-import it into a fresh scene and render check images with the shared
preview lighting. Texture size and triangle counts are provisional, TBD (playtest).
"""

import json
import math
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "nest"
GLB = ROOT / "assets" / "aliens" / "nest" / "nest.glb"
BLEND = ROOT / "assets" / "aliens" / "nest" / "source" / "nest.blend"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402

ASSET = "Nest"
GAME = OUT / "game"
SIZE = 2048
MARGIN_PX = 8
# Objects with procedural materials: they share the atlas (materials Flesh, Chitin, Resin, EggSac).
ATLAS = ["Mound", "Tendrils"]
GLOW_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)
SLIME_COLOR = (0.02, 0.006, 0.008)


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
    scene.render.bake.margin = MARGIN_PX
    scene.render.bake.margin_type = "EXTEND"


def select_only(objs: list, active) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


# --- 1. prepare geometry ------------------------------------------------------------------------------


def apply_modifiers(obj: bpy.types.Object) -> None:
    """Bake on the final geometry; keeps the "flow" attribute the procedural materials read."""
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    me.name = obj.name
    bpy.data.meshes.remove(old)


def unwrap_atlas(objs: list) -> None:
    for o in objs:
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


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
    bpy.ops.object.bake(type=kind, use_clear=True, margin=MARGIN_PX, margin_type="EXTEND", target="IMAGE_TEXTURES", **kw)
    print("BAKED", kind, img.name)


def pixels(img: bpy.types.Image) -> np.ndarray:
    arr = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    return arr.reshape(img.size[1], img.size[0], 4)


def save_png(img: bpy.types.Image, path: pathlib.Path) -> None:
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()


def metallic_constant(mats: list) -> float | None:
    """The shared metallic value when no atlas material drives Metallic (organic: all 0), else None."""
    vals = set()
    for m in mats:
        sock = m.node_tree.nodes["Principled BSDF"].inputs["Metallic"]
        if sock.is_linked:
            return None
        vals.add(round(sock.default_value, 4))
    return vals.pop() if len(vals) == 1 else None


# --- 3. game materials --------------------------------------------------------------------------------


def gltf_output_group() -> bpy.types.NodeTree:
    """The glTF exporter reads occlusion from a node group called "glTF Material Output"."""
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is None:
        ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def mat_baked(name: str, base: bpy.types.Image, orm: bpy.types.Image, normal: bpy.types.Image) -> bpy.types.Material:
    mat, nt, bsdf = C._new_material(name)

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


def _replace(name: str) -> tuple:
    old = bpy.data.materials.get(name)
    if old:
        old.name = name + "_procedural"
    return C._new_material(name)


def mat_simple(name: str, color, roughness: float) -> bpy.types.Material:
    mat, _nt, bsdf = _replace(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def mat_simple_emissive(name: str, color, strength: float) -> bpy.types.Material:
    mat, _nt, bsdf = _replace(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.15
    return mat


def is_constant(mat: bpy.types.Material) -> bool:
    """True when the material is only a Principled BSDF with constant inputs on the output."""
    kinds = {n.bl_idname for n in mat.node_tree.nodes}
    return kinds <= {"ShaderNodeBsdfPrincipled", "ShaderNodeOutputMaterial"}


# --- main ---------------------------------------------------------------------------------------------


def bake_and_export() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(OUT / "nest_procedural.blend"))
    C.ASSET = ASSET
    preview = C.collection("Preview")
    for obj in list(preview.all_objects):
        bpy.data.objects.remove(obj)
    bpy.data.collections.remove(preview)
    objs = [bpy.data.objects[n] for n in ATLAS]
    for o in objs:
        apply_modifiers(o)
    unwrap_atlas(objs)
    mats = sorted({s.material for o in objs for s in o.material_slots if s.material}, key=lambda m: m.name)
    print("ATLAS materials", [m.name for m in mats])

    GAME.mkdir(parents=True, exist_ok=True)
    img_base = new_image("nest_basecolor", SIZE, non_color=False)
    img_rough = new_image("bake_roughness", SIZE, non_color=True)
    img_ao = new_image("bake_ao", SIZE, non_color=True)
    img_nrm = new_image("nest_normal", SIZE, non_color=True)
    passes = [(img_base, "Base Color"), (img_rough, "Roughness")]
    metal = metallic_constant(mats)
    img_metal = None
    if metal is None:
        img_metal = new_image("bake_metallic", SIZE, non_color=True)
        passes.append((img_metal, "Metallic"))
    print("METALLIC", "baked" if metal is None else f"constant {metal}")

    for img, socket in passes:
        for m in mats:
            route_to_emission(m, socket)
        bake(objs, mats, img, "EMIT", 32)
    for m in mats:
        restore_bsdf(m)
    bpy.context.scene.world.light_settings.distance = 0.25
    bake(objs, mats, img_ao, "AO", 64)
    bake(objs, mats, img_nrm, "NORMAL", 16, normal_space="TANGENT")

    # ORM: occlusion (softened, the albedo already carries cavity darkening), roughness, metallic.
    ao = pixels(img_ao)[..., 0]
    orm = np.ones((SIZE, SIZE, 4), dtype=np.float32)
    orm[..., 0] = 1.0 - 0.6 * (1.0 - ao)
    orm[..., 1] = pixels(img_rough)[..., 0]
    orm[..., 2] = metal if img_metal is None else pixels(img_metal)[..., 0]
    img_orm = new_image("nest_orm", SIZE, non_color=True)
    img_orm.pixels.foreach_set(orm.ravel())
    save_png(img_base, GAME / "nest_basecolor.png")
    save_png(img_nrm, GAME / "nest_normal.png")
    save_png(img_orm, GAME / "nest_orm.png")
    save_png(img_ao, GAME / "bake_ao.png")

    # Swap materials: one PBR material on the atlas objects, constant ones on Slime, Mouth and Glands.
    nest_mat = mat_baked("Nest", img_base, img_orm, img_nrm)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(nest_mat)
        for p in o.data.polygons:
            p.material_index = 0
    C.assign(bpy.data.objects["Slime"], mat_simple("Slime", SLIME_COLOR, 0.1))
    glow = mat_simple_emissive("Nest_Glow", GLOW_COLOR, 5.0)
    for name in ("Mouth", "Glands"):
        C.assign(bpy.data.objects[name], glow)
    for o in C.collection(ASSET).all_objects:
        if o.type == "MESH" and o.name not in ATLAS:
            for s in o.material_slots:
                assert is_constant(s.material), (o.name, s.material.name)
    # Closed or ground-hugging meshes only seen from outside/above: export single-sided.
    for o in C.collection(ASSET).all_objects:
        if o.type == "MESH":
            for s in o.material_slots:
                s.material.use_backface_culling = True

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
    print("GLB nodes", [(nd["name"], [round(v, 3) for v in nd.get("translation", [0, 0, 0])], nd.get("scale"), nd.get("children")) for nd in j["nodes"]])
    print("GLB meshes", [(m["name"], [sorted(p["attributes"]) for p in m["primitives"]]) for m in j["meshes"]])
    print("GLB materials", [(m["name"], m.get("doubleSided", False), m.get("extensions")) for m in j["materials"]])
    print("GLB images", [(im.get("name"), im.get("mimeType"), j["bufferViews"][im["bufferView"]]["byteLength"]) for im in j.get("images", [])])
    for name in ("Nest", "Nest_Glow", "Slime"):
        mm = next(m for m in j["materials"] if m["name"] == name)
        print(f"GLB material {name}", json.dumps(mm))
    print(f"GLB size {path.stat().st_size / 1e6:.2f} MB")


CHECK_VIEWS = {  # same framing as nest_build.py's previews
    "iso": dict(view="iso", target=(0, 0, 0.5), zoom=0.95),
    "hero": dict(view="hero", target=(0, 0, 0.7), zoom=1.05),
    "back": dict(view="back", target=(0, 0, 0.7), zoom=1.05),
    "far": dict(view="iso", target=(0, 0, 0.5), zoom=1.35),
}


def render_close(path: pathlib.Path, loc, target, lens: float, samples: int, size: int) -> None:
    C.render(path, view="hero", samples=1, size=16)  # applies common's render settings and creates "Cam"
    cam = bpy.context.scene.camera
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    scene.cycles.samples = samples
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def verify() -> None:
    C.reset(ASSET)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    dg = bpy.context.evaluated_depsgraph_get()
    tris, rows = 0, []
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            me.calc_loop_triangles()
            pts = [ev.matrix_world @ v.co for v in me.vertices]
            lo = [round(min(p[i] for p in pts), 3) for i in range(3)]
            hi = [round(max(p[i] for p in pts), 3) for i in range(3)]
            rows.append((o.name, len(me.loop_triangles), lo, hi))
            tris += len(me.loop_triangles)
            ev.to_mesh_clear()
    print("CHECK triangles", tris)
    print("CHECK per object (name, tris, min, max)", rows)
    print("CHECK objects", sorted((o.name, o.type, o.parent.name if o.parent else None, tuple(round(v, 3) for v in o.matrix_world.translation)) for o in bpy.context.scene.objects))
    C.preview_scene(crystals=False, figure_location=(2.5, 2.1, 0.0))
    for obj in list(C.collection("Preview").objects):  # keep the shared rubble off the nest, as in the build
        if obj.type == "MESH" and obj.name.startswith("Icosphere") and obj.location.xy.length < 4.7:
            bpy.data.objects.remove(obj)
    views = ["iso", "hero"] + (["back", "far", "close"] if "all" in sys.argv else [])
    for view in views:
        path = GAME / f"check_{view}.png"
        if view == "close":
            render_close(path, (2.6, -3.2, 3.2), (0, 0, 0.9), 35, 64, 1024)
        else:
            C.render(path, samples=96, size=1024, **CHECK_VIEWS[view])


if "verify" not in sys.argv:
    bake_and_export()
glb_summary(GLB)
verify()
