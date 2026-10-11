"""Game-ready biome scatter kit: bake the procedural look of plants_procedural.blend into one shared texture set.

Run from the repo root, after plants_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/plants/source/plants_bake.py          # bake, export, check renders
    tools/blender.sh assets/plants/source/plants_bake.py verify   # only re-import and render the checks

Writes the game asset assets/plants/plants.glb (textures embedded) and its source assets/plants/source/plants.blend;
the separate PNGs and check renders go to tmp/assets/scatter/game/.

Steps (as in miner_glow_bake.py): open the .blend, drop the preview props, unwrap all ten variants into one UV atlas,
bake albedo / roughness (emission trick), the bulbs' glow, AO and a tangent-space normal map at 2x the texture size
and scale them down (cheap anti-aliasing for the thin blades), pack AO+roughness+metallic into an ORM image, swap in
one shared "Plants" PBR material (emission from a texture, so the dim bulbs need no second material slot), move the
variants to the origin, export, then re-import the .glb into a fresh scene and render check images with the shared
preview lighting.

The bakes run with the variants still in their preview rows (they would occlude each other at the origin) and with
a ground plane at z = 0, as in the procedural previews (cavity darkening and AO see the ground).
Texture size: one 2048 set for the whole kit, per the asset budget, TBD (playtest).
"""

import json
import math
import pathlib
import random
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "tmp" / "assets" / "plants" / "plants_procedural.blend"
GAME = ROOT / "tmp" / "assets" / "scatter" / "game"
GLB = ROOT / "assets" / "plants" / "plants.glb"
BLEND = ROOT / "assets" / "plants" / "source" / "plants.blend"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402

ASSET = "Plants"
SIZE = 2048  # final texture size (budget: one shared 2048 set, TBD (playtest))
BAKE_SIZE = 4096  # baked at 2x and scaled down
MARGIN_PX = 16  # at BAKE_SIZE, i.e. 8 px in the final texture
AO_DISTANCE = 0.25
EMIT_STRENGTH = 3.0  # glTF emissive strength of the shared material; the texture holds color * glow * strength / 3
DUST = ["Dust_Debris_a", "Dust_Shrub_a", "Dust_Spire_a", "Dust_Shrub_b", "Dust_Debris_b"]
OVERGROWTH = ["Overgrowth_Frond_b", "Overgrowth_Fungus_a", "Overgrowth_Tube_a", "Overgrowth_Fungus_b", "Overgrowth_Frond_a"]
VARIANTS = DUST + OVERGROWTH

# Check-render layout, as in plants_build.py (rows perpendicular to the iso view).
ROW_STEP = 2.1
ROW_DIR = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
ROW_CENTER = {"dust": Vector((2.0, -2.0, 0)), "overgrowth": Vector((-2.0, 2.0, 0))}
GROUND = {
    "dust": ((0.055, 0.042, 0.03), (0.11, 0.085, 0.06)),
    "overgrowth": ((0.018, 0.019, 0.011), (0.045, 0.047, 0.026)),
}


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


def unwrap_atlas(objs: list) -> None:
    """One atlas for all variants; average_islands_scale gives every variant the same texel density."""
    for o in objs:
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    # FRACTION margin: a fixed 6 px gap at SIZE (the default SCALED margin left the atlas only 16 % covered).
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")


def uv_coverage(objs: list) -> tuple[float, float]:
    """Fraction of the atlas covered by UV islands and the texel density (px per m at SIZE) for the report."""
    uv_area = 0.0
    world_area = 0.0
    for o in objs:
        me = o.data
        uv = me.uv_layers.active.data
        for p in me.polygons:
            pts = [uv[i].uv for i in p.loop_indices]
            a = 0.0
            for k in range(len(pts)):
                x0, y0 = pts[k]
                x1, y1 = pts[(k + 1) % len(pts)]
                a += x0 * y1 - x1 * y0
            uv_area += abs(a) * 0.5
            world_area += p.area
    return uv_area, math.sqrt(uv_area / world_area) * SIZE


def bake_ground() -> bpy.types.Object:
    """Ground at z = 0 for the bakes only (not selected, so it isn't baked; removed before the save)."""
    me = bpy.data.meshes.new("BakeGround")
    me.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new("BakeGround", me)
    bpy.context.scene.collection.objects.link(obj)
    mat, _nt, bsdf = C._new_material("BakeGround")
    bsdf.inputs["Base Color"].default_value = (0.05, 0.045, 0.04, 1.0)
    C.assign(obj, mat)
    return obj


# --- 2. bake ------------------------------------------------------------------------------------------


def new_image(name: str, size: int, non_color: bool) -> bpy.types.Image:
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def output_node(nt) -> bpy.types.Node:
    outs = [n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial"]
    return next((n for n in outs if n.is_active_output), outs[0])


def emit_node(nt) -> bpy.types.Node:
    em = nt.nodes.get("BakeEmit") or nt.nodes.new("ShaderNodeEmission")
    em.name = "BakeEmit"
    em.inputs["Strength"].default_value = 1.0
    for sock in (em.inputs["Color"], em.inputs["Strength"]):
        for lk in list(sock.links):
            nt.links.remove(lk)
    return em


def route_to_emission(mat: bpy.types.Material, input_name: str) -> None:
    """Feed whatever drives the BSDF input (link or constant) into an Emission shader on the output."""
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    em = emit_node(nt)
    sock = bsdf.inputs[input_name]
    if sock.is_linked:
        nt.links.new(sock.links[0].from_socket, em.inputs["Color"])
    else:
        v = sock.default_value
        em.inputs["Color"].default_value = (v[0], v[1], v[2], 1.0) if hasattr(v, "__len__") else (v, v, v, 1.0)
    nt.links.new(em.outputs["Emission"], output_node(nt).inputs["Surface"])


def route_glow(mat: bpy.types.Material) -> None:
    """Bake the real emission (color * glow attribute * strength), scaled by 1 / EMIT_STRENGTH into 0..1."""
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    em = emit_node(nt)
    em.inputs["Color"].default_value = bsdf.inputs["Emission Color"].default_value
    strength = bsdf.inputs["Emission Strength"]
    scale = nt.nodes.get("BakeGlowScale") or nt.nodes.new("ShaderNodeMath")
    scale.name = "BakeGlowScale"
    scale.operation = "MULTIPLY"
    scale.use_clamp = True
    scale.inputs[1].default_value = 1.0 / EMIT_STRENGTH
    if strength.is_linked:
        nt.links.new(strength.links[0].from_socket, scale.inputs[0])
    else:
        scale.inputs[0].default_value = strength.default_value
    nt.links.new(scale.outputs[0], em.inputs["Strength"])
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
    print("BAKED", kind, img.name, flush=True)


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


def limit_tilt(img: bpy.types.Image, min_z: float = 0.7) -> None:
    """Clamp the tangent-space normal map to at most ~45 degrees of tilt. The bump is subtle everywhere (z > 0.9);
    only the undersides of the thin smooth-shaded fronds bake garbage (their smooth normals are far from the
    geometric ones, which the bump node works from)."""
    px = pixels(img)
    n = px[..., :3] * 2.0 - 1.0
    bad = n[..., 2] < min_z
    xy = n[..., :2]
    xy_len = np.maximum(np.linalg.norm(xy, axis=-1, keepdims=True), 1e-6)
    clamped = np.concatenate([xy / xy_len * math.sqrt(1 - min_z * min_z), np.full(xy_len.shape, min_z)], axis=-1)
    n[bad] = clamped[bad]
    px[..., :3] = n * 0.5 + 0.5
    img.pixels.foreach_set(px.ravel())
    print(f"NORMAL clamped {int(bad.sum())} px (tilt > {math.degrees(math.acos(min_z)):.0f} deg)")


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


def mat_baked(name: str, base, orm, normal, emission) -> bpy.types.Material:
    mat, nt, bsdf = C._new_material(name)

    def tex(img, x, y):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.location = (x, y)
        return n

    nt.links.new(tex(base, -700, 400).outputs["Color"], bsdf.inputs["Base Color"])
    t_orm = tex(orm, -700, 100)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-400, 100)
    nt.links.new(t_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    occ = nt.nodes.new("ShaderNodeGroup")
    occ.node_tree = gltf_output_group()
    occ.location = (-150, -250)
    nt.links.new(sep.outputs["Red"], occ.inputs["Occlusion"])
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-400, -200)
    nt.links.new(tex(normal, -700, -200).outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(tex(emission, -700, -500).outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = EMIT_STRENGTH
    mat.use_backface_culling = True  # closed blades / stems, open ends only below the ground: single-sided
    return mat


# --- main ---------------------------------------------------------------------------------------------


def bake_and_export() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(SRC))
    C.ASSET = ASSET
    for obj in list(C.collection("Preview").all_objects):
        bpy.data.objects.remove(obj)
    bpy.data.collections.remove(C.collection("Preview"))
    root = bpy.data.objects[ASSET]
    root.location = (0, 0, 0)
    objs = [bpy.data.objects[n] for n in VARIANTS]
    for o in objs:
        assert o.type == "MESH" and not o.modifiers and o.parent == root, o.name
        assert len(o.data.materials) == 1, o.name
        assert tuple(o.rotation_euler) == (0, 0, 0) and tuple(o.scale) == (1, 1, 1), o.name
    unwrap_atlas(objs)
    cover, density = uv_coverage(objs)
    print(f"ATLAS coverage {cover:.2f}, texel density {density:.0f} px/m at {SIZE}")
    mats = sorted({s.material for o in objs for s in o.material_slots if s.material}, key=lambda m: m.name)
    print("ATLAS materials", [m.name for m in mats])
    ground = bake_ground()

    GAME.mkdir(parents=True, exist_ok=True)
    big = {k: new_image(f"bake_{k}", BAKE_SIZE, non_color=k not in ("basecolor", "emission"))
           for k in ("basecolor", "roughness", "emission", "ao", "normal")}
    for key, socket in (("basecolor", "Base Color"), ("roughness", "Roughness")):
        for m in mats:
            route_to_emission(m, socket)
        bake(objs, mats, big[key], "EMIT", 64)  # 64: the cavity AO node in the albedo needs the samples
    for m in mats:
        route_glow(m)
    bake(objs, mats, big["emission"], "EMIT", 16)
    for m in mats:
        restore_bsdf(m)
    bpy.context.scene.world.light_settings.distance = AO_DISTANCE
    bake(objs, mats, big["ao"], "AO", 64)
    bake(objs, mats, big["normal"], "NORMAL", 16, normal_space="TANGENT")

    img_base = downsample(big["basecolor"], "plants_basecolor", SIZE, non_color=False)
    img_emit = downsample(big["emission"], "plants_emission", SIZE, non_color=False)
    limit_tilt(big["normal"])
    img_nrm = downsample(big["normal"], "plants_normal", SIZE, non_color=True, renormalize=True)
    # ORM: occlusion (softened, the albedo already carries cavity darkening), roughness, metallic (0 everywhere).
    ao = pixels(big["ao"])[..., 0]
    orm = np.ones((BAKE_SIZE, BAKE_SIZE, 4), dtype=np.float32)
    orm[..., 0] = 1.0 - 0.6 * (1.0 - ao)
    orm[..., 1] = pixels(big["roughness"])[..., 0]
    orm[..., 2] = 0.0
    big_orm = new_image("bake_orm", BAKE_SIZE, non_color=True)
    big_orm.pixels.foreach_set(orm.ravel())
    img_orm = downsample(big_orm, "plants_orm", SIZE, non_color=True)
    for img in (img_base, img_orm, img_nrm, img_emit):
        save_png(img, GAME / f"{img.name}.png")
    save_png(big["ao"], GAME / "bake_ao_2x.png")
    for img in (*big.values(), big_orm):
        bpy.data.images.remove(img)

    # Swap materials: one shared PBR material on every variant.
    plants_mat = mat_baked(ASSET, img_base, img_orm, img_nrm, img_emit)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(plants_mat)
        for p in o.data.polygons:
            p.material_index = 0
        o.location = (0, 0, 0)  # the preview rows were layout only: every variant's origin is its base center
    for m in mats:  # the procedural materials stay out of the committed .blend
        bpy.data.materials.remove(m)
    bpy.data.materials.remove(bpy.data.materials["BakeGround"])
    bpy.data.objects.remove(ground)

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
    print("GLB nodes", [(nd["name"], [round(v, 3) for v in nd.get("translation", [0, 0, 0])], nd.get("children")) for nd in j["nodes"]])
    print("GLB meshes", [(m["name"], [p.get("material") for p in m["primitives"]], list(m["primitives"][0]["attributes"])) for m in j["meshes"]])
    print("GLB materials", [m["name"] for m in j["materials"]])
    print("GLB images", [(im.get("name"), im.get("mimeType"), j["bufferViews"][im["bufferView"]]["byteLength"]) for im in j.get("images", [])])
    print("GLB Plants material", json.dumps(next(m for m in j["materials"] if m["name"] == ASSET)))
    print(f"GLB size {path.stat().st_size / 1e6:.2f} MB")


# --- verify -------------------------------------------------------------------------------------------


def row_location(name: str) -> Vector:
    group, names = ("dust", DUST) if name in DUST else ("overgrowth", OVERGROWTH)
    k = names.index(name) - (len(names) - 1) / 2
    return ROW_CENTER[group] + ROW_DIR * (k * ROW_STEP)


def ground_color(biome: str) -> None:
    lo, hi = GROUND[biome]
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*lo, 1.0)
            node.inputs[7].default_value = (*hi, 1.0)


def scatter(objs: dict, biome: str, seed: int) -> list:
    """Game-like scatter of linked copies, as in plants_build.py."""
    rnd = random.Random(seed)
    counts = (
        {"Dust_Shrub_a": 9, "Dust_Shrub_b": 12, "Dust_Spire_a": 4, "Dust_Debris_a": 8, "Dust_Debris_b": 3}
        if biome == "dust"
        else {"Overgrowth_Frond_b": 24, "Overgrowth_Fungus_a": 8, "Overgrowth_Tube_a": 4, "Overgrowth_Fungus_b": 5, "Overgrowth_Frond_a": 9}
    )
    copies, placed = [], []
    for name, count in counts.items():
        for _ in range(count):
            for _try in range(30):
                x, y = rnd.uniform(-7, 7), rnd.uniform(-7, 7)
                if all((x - px) ** 2 + (y - py) ** 2 > 1.0 for px, py in placed) and (x - 1.5) ** 2 + (y + 1.5) ** 2 > 2.0:
                    break
            placed.append((x, y))
            o = objs[name].copy()
            o.parent = None
            C.link(o, None, "Preview")
            o.name = f"Scatter_{biome}"
            o.location = (x, y, 0)
            o.rotation_euler = (rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06), rnd.uniform(0, math.tau))
            s = rnd.uniform(0.7, 1.3)
            o.scale = (s, s, s)
            copies.append(o)
    return copies


def show_only(visible: list) -> None:
    vis = {o.name for o in visible}
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and (o.name in VARIANTS or o.name.startswith("Scatter")):
            o.hide_render = o.name not in vis


def verify() -> None:
    C.reset(ASSET)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    dg = bpy.context.evaluated_depsgraph_get()
    tris = {}
    for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        tris[o.name] = len(me.loop_triangles)
        cos = [o.matrix_world @ v.co for v in me.vertices]
        lo, hi = Vector(map(min, *cos)), Vector(map(max, *cos))
        # Base center: bounds center of the vertices near the ground (they should sit around the origin).
        base = [c for c in cos if c.z < lo.z + 0.15]
        bc = sum(base, Vector()) / len(base)
        print(f"CHECK {o.name:22s} tris {tris[o.name]:5d}  size {tuple(round(x, 2) for x in hi - lo)}  zmin {lo.z:.3f} "
              f"zmax {hi.z:.2f}  base center ({bc.x:.2f}, {bc.y:.2f})  origin {tuple(round(x, 3) for x in o.matrix_world.translation)}"
              f"  mats {[m.name for m in me.materials]}  smooth {sum(p.use_smooth for p in me.polygons)}/{len(me.polygons)}")
        o.evaluated_get(dg).to_mesh_clear()
    print("CHECK triangles total", sum(tris.values()))
    print("CHECK objects", sorted((o.name, o.parent.name if o.parent else None) for o in bpy.context.scene.objects))
    assert sorted(tris) == sorted(VARIANTS), sorted(tris)

    objs = {n: bpy.data.objects[n] for n in VARIANTS}
    for n, o in objs.items():
        o.location = row_location(n)
    C.preview_scene(crystals=False, figure_location=(0, 0, 0))
    for o in list(C.collection("Preview").all_objects):
        if o.type == "MESH" and o.name.startswith("Ico"):
            bpy.data.objects.remove(o)
    fig = bpy.data.objects["PreviewFigure"]
    sets = {"dust": scatter(objs, "dust", 5), "overgrowth": scatter(objs, "overgrowth", 9)}
    for biome, names in (("dust", DUST), ("overgrowth", OVERGROWTH)):
        ground_color(biome)
        center = ROW_CENTER[biome]
        show_only([objs[n] for n in names])
        fig.location = center + ROW_DIR * (ROW_STEP * 2.9)
        tgt = tuple(center + Vector((0, 0, 0.5)))
        C.render(GAME / f"check_{biome}_iso.png", view="iso", samples=64, size=1024, target=tgt, zoom=1.12)
        C.render(GAME / f"check_{biome}_hero.png", view="hero", samples=64, size=1024, target=tgt, zoom=1.7)
        show_only(sets[biome])
        fig.location = (1.5, -1.5, 0)
        C.render(GAME / f"check_{biome}_scatter.png", view="iso", samples=48, size=768, target=(0, 0, 0.3), zoom=1.45)
        if "noclose" in sys.argv:
            continue
        for name in names:  # close-ups like plants_build.py's final_<Variant>_<view>.png
            obj = objs[name]
            h = obj.dimensions.z
            show_only([obj])
            fig.location = obj.location + Vector((1.3, 0.9, 0))
            tgt = tuple(obj.location + Vector((0, 0, max(0.15, h * 0.45))))
            zoom = max(0.2, min(0.62, 0.12 + h * 0.16))
            for view in ("iso", "hero"):
                C.render(GAME / f"check_{name}_{view}.png", view=view, samples=48, size=384, target=tgt,
                         zoom=zoom * (0.9 if view == "iso" else 1.0))


if "verify" not in sys.argv:
    bake_and_export()
glb_summary(GLB)
verify()
