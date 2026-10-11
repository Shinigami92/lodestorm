"""Game-ready blaster: bake the procedural look of blaster_procedural.blend into one texture set.

Run from the repo root, after blaster_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/weapons/source/blaster_bake.py          # bake, export, check renders
    tools/blender.sh assets/weapons/source/blaster_bake.py verify   # only re-import and render the checks

Writes the game asset assets/weapons/blaster.glb (textures embedded) and its source
assets/weapons/source/blaster.blend; the separate PNGs and check renders go to tmp/assets/blaster/game/.

Steps (as in miner_glow_bake.py): open the .blend, drop the preview props, apply the modifiers on "Body", unwrap
it into one UV atlas, bake albedo / roughness / metallic (emission trick), AO and a tangent-space normal map at
2x the texture size and scale them down (cheap anti-aliasing for the small, detailed gun), pack
AO+roughness+metallic into an ORM image, swap in one "Blaster" PBR material, export, then re-import the .glb into
a fresh scene and render check images with the shared preview lighting. "AmmoCounter" and "EnergyCell" keep their
constant emissive materials (the game drives the counter's fill through its UV.x), so they are not baked.
Texture size 1024 per the asset budget, TBD (playtest).
"""

import json
import math
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "blaster"
GLB = ROOT / "assets" / "weapons" / "blaster.glb"
BLEND = ROOT / "assets" / "weapons" / "source" / "blaster.blend"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402

ASSET = "Blaster"
GAME = OUT / "game"
SIZE = 1024  # final texture size (budget: one 1024 set, TBD (playtest))
BAKE_SIZE = 2048  # baked at 2x and scaled down
MARGIN_PX = 16  # at BAKE_SIZE, i.e. 8 px in the final texture
AO_DISTANCE = 0.03  # the gun is 0.9 m long: only close cavities darken
ATLAS = ["Body"]
EMISSIVE = ["AmmoCounter", "EnergyCell"]
HOLD_Z = 1.1  # check renders lift the gun to the hand height, like blaster_build.py's previews
CENTER = (0.0, 0.14, HOLD_Z + 0.07)


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
    """Bake on the final geometry (bevels, weighted normals) so the UVs and the normal map match the export."""
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    bpy.data.meshes.remove(old)
    me.name = obj.name  # after removing the old mesh, or the export names it "Body.001"


def unwrap_atlas(objs: list) -> None:
    for o in objs:
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, margin=0.006)
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


def downsample(img: bpy.types.Image, name: str, size: int, non_color: bool, renormalize: bool = False) -> bpy.types.Image:
    """Box-filter the 2x bake down to the final size (in the stored encoding, as the GPU would filter it)."""
    px = pixels(img)
    f = img.size[0] // size
    small = px.reshape(size, f, size, f, 4).mean(axis=(1, 3))
    if renormalize:  # tangent-space normal map: keep unit length after averaging
        n = small[..., :3] * 2.0 - 1.0
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
        small[..., :3] = n * 0.5 + 0.5
    small[..., 3] = 1.0
    out = new_image(name, size, non_color)
    out.pixels.foreach_set(small.ravel())
    return out


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


def is_constant(mat: bpy.types.Material) -> bool:
    """True when the material is only a Principled BSDF with constant inputs on the output."""
    kinds = {n.bl_idname for n in mat.node_tree.nodes}
    return kinds <= {"ShaderNodeBsdfPrincipled", "ShaderNodeOutputMaterial"}


# --- main ---------------------------------------------------------------------------------------------


def bake_and_export() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(OUT / "blaster_procedural.blend"))
    C.ASSET = ASSET
    for obj in list(C.collection("Preview").all_objects):
        bpy.data.objects.remove(obj)
    bpy.data.objects[ASSET].location = (0, 0, 0)
    objs = [bpy.data.objects[n] for n in ATLAS]
    for o in objs:
        apply_modifiers(o)
    unwrap_atlas(objs)
    mats = sorted({s.material for o in objs for s in o.material_slots if s.material}, key=lambda m: m.name)
    print("ATLAS materials", [m.name for m in mats])

    GAME.mkdir(parents=True, exist_ok=True)
    big_base = new_image("bake_basecolor", BAKE_SIZE, non_color=False)
    big_rough = new_image("bake_roughness", BAKE_SIZE, non_color=True)
    big_metal = new_image("bake_metallic", BAKE_SIZE, non_color=True)
    big_ao = new_image("bake_ao", BAKE_SIZE, non_color=True)
    big_nrm = new_image("bake_normal", BAKE_SIZE, non_color=True)

    for img, socket in ((big_base, "Base Color"), (big_rough, "Roughness"), (big_metal, "Metallic")):
        for m in mats:
            route_to_emission(m, socket)
        bake(objs, mats, img, "EMIT", 32)
    for m in mats:
        restore_bsdf(m)
    bpy.context.scene.world.light_settings.distance = AO_DISTANCE
    bake(objs, mats, big_ao, "AO", 64)
    bake(objs, mats, big_nrm, "NORMAL", 16, normal_space="TANGENT")

    img_base = downsample(big_base, "blaster_basecolor", SIZE, non_color=False)
    img_nrm = downsample(big_nrm, "blaster_normal", SIZE, non_color=True, renormalize=True)
    # ORM: occlusion (softened, the albedo already carries cavity grime), roughness, metallic.
    ao = pixels(big_ao)[..., 0]
    orm = np.ones((BAKE_SIZE, BAKE_SIZE, 4), dtype=np.float32)
    orm[..., 0] = 1.0 - 0.6 * (1.0 - ao)
    orm[..., 1] = pixels(big_rough)[..., 0]
    orm[..., 2] = pixels(big_metal)[..., 0]
    big_orm = new_image("bake_orm", BAKE_SIZE, non_color=True)
    big_orm.pixels.foreach_set(orm.ravel())
    img_orm = downsample(big_orm, "blaster_orm", SIZE, non_color=True)
    save_png(img_base, GAME / "blaster_basecolor.png")
    save_png(img_nrm, GAME / "blaster_normal.png")
    save_png(img_orm, GAME / "blaster_orm.png")
    save_png(big_ao, GAME / "bake_ao_2x.png")
    for img in (big_base, big_rough, big_metal, big_ao, big_nrm, big_orm):
        bpy.data.images.remove(img)

    # Swap materials: one PBR material on the body; the emissive parts keep their constant materials.
    body_mat = mat_baked(ASSET, img_base, img_orm, img_nrm)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(body_mat)
        for p in o.data.polygons:
            p.material_index = 0
    for name in EMISSIVE:
        for s in bpy.data.objects[name].material_slots:
            assert is_constant(s.material), (name, s.material.name)
    for m in mats:  # the procedural materials stay out of the committed .blend
        bpy.data.materials.remove(m)
    # Closed meshes: export single-sided (glTF doubleSided=false).
    for o in C.collection(ASSET).all_objects:
        if o.type == "MESH":
            for s in o.material_slots:
                s.material.use_backface_culling = True

    # Pack the baked images, so the committed .blend doesn't point at files in tmp/.
    bpy.ops.file.pack_all()
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backup next to the source
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    C.export_glb(GLB)
    print(f"GLB size {GLB.stat().st_size / 1e6:.2f} MB")


def glb_summary(path: pathlib.Path) -> None:
    data = path.read_bytes()
    n = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20 : 20 + n])
    print("GLB nodes", [(nd["name"], [round(v, 3) for v in nd.get("translation", [0, 0, 0])], nd.get("scale")) for nd in j["nodes"]])
    print("GLB meshes", [(m["name"], [p.get("material") for p in m["primitives"]], list(m["primitives"][0]["attributes"])) for m in j["meshes"]])
    print("GLB materials", [m["name"] for m in j["materials"]])
    print("GLB images", [(im.get("name"), im.get("mimeType"), j["bufferViews"][im["bufferView"]]["byteLength"]) for im in j.get("images", [])])
    print("GLB Blaster material", json.dumps(next(m for m in j["materials"] if m["name"] == ASSET)))
    print(f"GLB size {path.stat().st_size / 1e6:.2f} MB")


def verify() -> None:
    C.reset(ASSET)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    dg = bpy.context.evaluated_depsgraph_get()
    tris = {}
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh()
            me.calc_loop_triangles()
            tris[o.name] = len(me.loop_triangles)
            lo = Vector(map(min, *[o.matrix_world @ v.co for v in me.vertices]))
            hi = Vector(map(max, *[o.matrix_world @ v.co for v in me.vertices]))
            print("CHECK bounds", o.name, tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi))
            o.evaluated_get(dg).to_mesh_clear()
    print("CHECK triangles", tris, sum(tris.values()))
    print("CHECK objects", sorted((o.name, o.parent.name if o.parent else None, tuple(round(x, 3) for x in o.matrix_world.translation)) for o in bpy.context.scene.objects))
    C.preview_scene(crystals=False, figure_location=(-0.35, -0.45, 0.0))
    fig = bpy.data.objects["PreviewFigure"]
    bpy.data.objects[ASSET].location = (0, 0, HOLD_Z)
    for view, zoom in (("iso", 0.2), ("hero", 0.18), ("back", 0.18)):
        for child in fig.children:
            child.hide_render = True
        C.render(GAME / f"check_{view}.png", view=view, samples=64, size=1024, target=CENTER, zoom=zoom)
    # Close look at the right side (blaster_build.py's "close" view): seams and texel density.
    cam = bpy.context.scene.camera
    cam.data.lens = 40
    cam.location = Vector(CENTER) + Vector((0.42, -0.36, 0.22))
    cam.rotation_euler = (Vector(CENTER) - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.render.resolution_x = bpy.context.scene.render.resolution_y = 768
    bpy.context.scene.render.filepath = str(GAME / "check_close.png")
    bpy.ops.render.render(write_still=True)
    for child in fig.children:
        child.hide_render = False
    C.render(GAME / "check_scale.png", view="iso", samples=48, size=768, target=(-0.2, -0.2, 1.0), zoom=0.32)


if "verify" not in sys.argv:
    bake_and_export()
glb_summary(GLB)
verify()
