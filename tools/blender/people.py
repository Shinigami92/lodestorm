"""Shared helpers for people (see docs/TECHNICAL.md, People): a MakeHuman body (MPFB 2, a Blender extension) shaped by
its sliders, rigged with MPFB's "game_engine" skeleton renamed to Godot's humanoid bone names, so the shared clips
(tools/blender/humanoid.py) play on everyone, wearing a generated outfit (TRELLIS.2) fitted over it.

    import people as P
    C.reset("Nell")
    mpfb = P.enable()                      # after C.reset(): the reset unloads extensions
    arm, parts = P.build(PERSON, root)     # PERSON: the sliders and the assets, see build()
    outfit = P.load_outfit(path, root, parts["Skin"], top, band)
    P.pose_limbs(arm, P.limb_directions(outfit, arm, waist))   # the body in the outfit's pose
    w, near = P.transfer_weights(outfit_co, P.posed_vertices(parts["Skin"]), body_weights)
    P.unskin(outfit, arm, names, w)        # back to the body's rest pose
    body = P.body_of(arm)                  # humanoid.Body with the measures the clips stand it on

Assets come from MPFB's user data folder (installed asset packs, CC0 unless a person's script says otherwise).
"""

import pathlib

import addon_utils
import bpy
import numpy as np
from mathutils import Matrix, Vector

import common as C
import generated as G
import humanoid as H

EXTENSION = "bl_ext.blender_org.mpfb"

# MPFB's game_engine bones and the Godot humanoid names they get (SkeletonProfileHumanoid).
BONES = {"Root": "Root", "pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest"}
BONES |= {"neck_01": "Neck", "head": "Head"}
FINGERS = {"index": "Index", "middle": "Middle", "ring": "Ring", "pinky": "Little"}
for _s, _side in (("l", "Left"), ("r", "Right")):
    BONES |= {
        f"clavicle_{_s}": f"{_side}Shoulder",
        f"upperarm_{_s}": f"{_side}UpperArm",
        f"lowerarm_{_s}": f"{_side}LowerArm",
        f"hand_{_s}": f"{_side}Hand",
        f"thigh_{_s}": f"{_side}UpperLeg",
        f"calf_{_s}": f"{_side}LowerLeg",
        f"foot_{_s}": f"{_side}Foot",
        f"ball_{_s}": f"{_side}Toes",
        f"thumb_01_{_s}": f"{_side}ThumbMetacarpal",
        f"thumb_02_{_s}": f"{_side}ThumbProximal",
        f"thumb_03_{_s}": f"{_side}ThumbDistal",
    }
    for _mh, _godot in FINGERS.items():
        for _i, _joint in enumerate(("Proximal", "Intermediate", "Distal"), 1):
            BONES[f"{_mh}_0{_i}_{_s}"] = f"{_side}{_godot}{_joint}"

_services = {}


def enable() -> dict:
    """Turns MPFB on for this run and returns its services by name (HumanService, TargetService, ...)."""
    addon_utils.enable(EXTENSION, default_set=True, persistent=False)
    from bl_ext.blender_org.mpfb.services.exportservice import ExportService
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    from bl_ext.blender_org.mpfb.services.locationservice import LocationService
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService

    _services.update(
        ExportService=ExportService,
        HumanService=HumanService,
        LocationService=LocationService,
        TargetService=TargetService,
    )
    return _services


def data_dir() -> pathlib.Path:
    return pathlib.Path(_services["LocationService"].get_user_data())


def asset(kind: str, name: str) -> pathlib.Path:
    """An installed asset's file: an .mhclo (kind: clothes, hair, eyes, ...) or a skin's .mhmat."""
    folder = data_dir() / kind / name
    found = sorted(folder.glob("*.mhmat" if kind == "skins" else "*.mhclo"))
    if not found:
        raise FileNotFoundError(f"MPFB asset {kind}/{name} is not installed (see docs/TECHNICAL.md, People)")
    return found[0]


ASSET_TYPES = {"eyes": "Eyes", "eyebrows": "Eyebrows", "eyelashes": "Eyelashes", "hair": "Hair", "clothes": "Clothes"}


def build(person: dict, root: bpy.types.Object) -> tuple:
    """The person, baked for export: `person` has "macro" (MPFB's macro sliders: gender, age, muscle, weight,
    proportions, height, cupsize, firmness and race), "skin" (a skin's name) and "assets" ((kind, name, object name)
    each: eyes, eyebrows, eyelashes, hair, clothes, outermost last). Returns the armature ("Skeleton", Godot's bone
    names, rest pose MPFB's A-pose) and the meshes by their object names ("Skin" for the body), all under `root`;
    the skin under the clothes is deleted where they cover it, the sliders are baked into the mesh."""
    hs, ts, es = _services["HumanService"], _services["TargetService"], _services["ExportService"]
    human = hs.create_human(macro_detail_dict=person["macro"])
    rig = hs.add_builtin_rig(human, "game_engine")
    hs.set_character_skin(str(asset("skins", person["skin"])), human, skin_type="GAMEENGINE")
    names = {}
    for kind, name, obj_name in person["assets"]:
        before = set(bpy.data.objects)
        hs.add_mhclo_asset(str(asset(kind, name)), human, asset_type=ASSET_TYPES[kind], subdiv_levels=0)
        (names[obj_name],) = [o for o in set(bpy.data.objects) - before if o.type == "MESH"]
    ts.bake_targets(human)
    es.bake_modifiers_remove_helpers(human, bake_masks=True, bake_subdiv=False, remove_helpers=True, also_proxy=True)
    names["Skin"] = human
    _rename_bones(rig)
    rig.name = rig.data.name = "Skeleton"
    C.link(rig, root)
    parts = {}
    for obj_name, obj in names.items():
        obj.name = obj.data.name = obj_name
        for group in obj.vertex_groups:
            if group.name in BONES:
                group.name = BONES[group.name]
        for coll in list(obj.users_collection):
            coll.objects.unlink(obj)
        C.link(obj)
        obj.parent = rig
        parts[obj_name] = obj
    for coll in list(rig.users_collection):
        if coll.name != C.ASSET:
            coll.objects.unlink(rig)
    return rig, parts


def _image(mat: bpy.types.Material, name: str) -> bpy.types.Image | None:
    """The image of the MPFB material's texture node named `name` (e.g. "diffuseTexture"), any case."""
    for node in mat.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.name.lower() == name.lower() and node.image:
            return node.image
    return None


def export_material(
    obj: bpy.types.Object, tint=(1.0, 1.0, 1.0), roughness: float = 0.8, clip: bool = False, size: int = 1024
) -> bpy.types.Material:
    """Replaces the MPFB material by one the glTF export keeps: its diffuse texture as the base color (a packed
    copy, multiplied by `tint` in sRGB, or with a (dark, light) pair: recolored by its brightness), its normal map if it has one, `roughness`; `clip`: the texture's alpha cut
    at 0.5 (hair, brows, lashes: alpha scissor in Godot), else opaque; the textures at most `size` square. Bump maps
    are dropped."""
    old = obj.data.materials[0]
    diffuse = _image(old, "diffuseTexture")
    normal = _image(old, "normalmapTexture")
    w, h = diffuse.size
    rgba = np.array(diffuse.pixels[:], dtype=np.float32).reshape(h, w, 4)
    if len(tint) == 2:  # a palette: the texture's brightness from the dark color to the light one
        lum = rgba[..., :3].mean(2, keepdims=True)
        lum = (lum - lum.min()) / max(float(lum.max() - lum.min()), 1e-3)
        rgba[..., :3] = np.array(tint[0]) * (1 - lum) + np.array(tint[1]) * lum
    else:
        rgba[..., :3] = np.clip(rgba[..., :3] * np.array(tint, dtype=np.float32), 0, 1)
    if not clip:
        rgba[..., 3] = 1.0
    base = bpy.data.images.new(f"{obj.name}Base", w, h, alpha=clip)
    base.pixels.foreach_set(rgba.ravel())
    if w > size:
        base.scale(size, size)
    base.pack()
    if normal:  # a copy under the part's name (the exported texture's name)
        nw, nh = normal.size
        pixels = np.array(normal.pixels[:], dtype=np.float32)
        normal = bpy.data.images.new(f"{obj.name}Normal", nw, nh, is_data=True)
        normal.pixels.foreach_set(pixels)
        if nw > size:
            normal.scale(size, size)
        normal.pack()
    mat = bpy.data.materials.new(obj.name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = base
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if clip:
        cut = nt.nodes.new("ShaderNodeMath")
        cut.operation = "ROUND"
        nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
        nt.links.new(cut.outputs[0], bsdf.inputs["Alpha"])
        mat.surface_render_method = "DITHERED"
    if normal:
        normal.colorspace_settings.name = "Non-Color"
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = normal
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return mat


def _rename_bones(rig: bpy.types.Object) -> None:
    for bone in rig.data.bones:
        bone.name = BONES.get(bone.name, bone.name)
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"


def body_of(arm: bpy.types.Object, *, foot_out: float = 0.03, wrist_out: float = 0.09, reach: float = 0.93) -> H.Body:
    """The humanoid.Body of a person's armature: its bones at rest (armature space), the feet `foot_out` outside the
    hips' joints, the hanging wrists `wrist_out` outside the shoulders and `reach` of the arm's length below them,
    the palms measured on the fingers."""
    bones = []
    for b in arm.data.bones:
        bones.append((b.name, tuple(b.head_local), tuple(b.tail_local), b.parent.name if b.parent else None))
    head = {n: Vector(h) for n, h, _t, _p in bones}
    tail = {n: Vector(t) for n, _h, t, _p in bones}
    palm = {}
    for side, s in H.SIDES:
        across = head[f"{side}LittleProximal"] - head[f"{side}IndexProximal"]
        palm[side] = tuple(-s * (tail[f"{side}Hand"] - head[f"{side}Hand"]).cross(across).normalized())
    shoulder = head["LeftUpperArm"]
    arm_length = (head["LeftLowerArm"] - shoulder).length + (head["LeftHand"] - head["LeftLowerArm"]).length
    return H.Body(
        bones,
        foot_x=head["LeftUpperLeg"].x + foot_out,
        wrist_x=shoulder.x + wrist_out,
        wrist_z=shoulder.z - reach * arm_length,
        palm=palm,
    )


# --- a generated outfit -----------------------------------------------------------------------------
# What a person wears (and their hair) can come from a generated model (TRELLIS.2 on an A-pose concept, see
# docs/TECHNICAL.md, Generated models), worn over the MakeHuman body: the body keeps its face, its skeleton and its
# weights, the outfit is cut where the body shows (the face), its hair is fitted over the head, the body is posed
# into the outfit's pose and the outfit takes the weights of the body under it (loose cloth below the waist, an
# apron, from the hips into both thighs instead, so it doesn't tear between the legs), then both go back to the
# body's rest pose. The body's skin the outfit covers is deleted.


def weight_matrix(obj: bpy.types.Object, names: list) -> np.ndarray:
    """The vertices' weights (vertices x names) from their vertex groups."""
    w = np.zeros((len(obj.data.vertices), len(names)))
    index = {g.index: names.index(g.name) for g in obj.vertex_groups if g.name in names}
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in index:
                w[v.index, index[g.group]] = g.weight
    return w


def posed_vertices(obj: bpy.types.Object) -> np.ndarray:
    """The mesh's vertices as its modifiers (the armature's pose) leave them, in world space."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.array([ev.matrix_world @ v.co for v in me.vertices])
    ev.to_mesh_clear()
    return co


def load_outfit(path, root: bpy.types.Object, skin: bpy.types.Object, top: float, band: tuple) -> bpy.types.Object:
    """The generated model as "Outfit": centered, scaled to `top` (m, its hair's top), moved front to back so its
    torso (heights `band`) is where the body's is."""
    obj = G.load(path, root, "Outfit")
    co = G.vertices(obj.data)
    lo, hi = co.min(0), co.max(0)
    co = (co - [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]) * (top / (hi[2] - lo[2]))
    body = G.vertices(skin.data)

    def middle(c):
        m = (c[:, 2] > band[0]) & (c[:, 2] < band[1]) & (np.abs(c[:, 0]) < 0.12)
        return (c[m, 1].min() + c[m, 1].max()) / 2

    co[:, 1] += middle(body) - middle(co)
    G.set_vertices(obj.data, co)
    for mat in obj.data.materials:
        mat.use_backface_culling = False  # cut open at the neck: its inside may show
        for link in mat.node_tree.links:  # the textures named after what they are (the export's file names)
            if link.from_node.type == "TEX_IMAGE" and link.from_node.image:
                kind = {"BSDF_PRINCIPLED": "Base", "NORMAL_MAP": "Normal"}.get(link.to_node.type, "ORM")
                link.from_node.image.name = f"Outfit{kind}"
    return obj


def _line(points: np.ndarray) -> tuple:
    """A line through the points (their middle and main direction)."""
    mid = points.mean(0)
    _u, _s, vt = np.linalg.svd(points - mid)
    return mid, vt[0]


def limb_directions(outfit: bpy.types.Object, arm: bpy.types.Object, waist: float) -> dict:
    """Where the outfit's arms and legs point, per bone (armature space): each arm along the line through the
    middles of its slices (from the shoulder out, the hand left out), each thigh from the hip's joint to the top of
    the lower leg's line (the middles of the trousers' slices below the knee), each lower leg along that line."""
    co = G.vertices(outfit.data)
    head = {b.name: Vector(b.head_local) for b in arm.data.bones}
    out = {}
    for side, s in H.SIDES:
        shoulder = head[f"{side}UpperArm"]
        reach = float((s * co[:, 0]).max())
        mids = []
        for x in np.arange(shoulder.x * s + 0.15, reach - 0.18, 0.03):
            m = (s * co[:, 0] > x) & (s * co[:, 0] < x + 0.03) & (co[:, 2] > waist)
            if m.sum() > 10:
                mids.append(co[m].mean(0))
        _mid, d = _line(np.array(mids))
        d = Vector(d * (1 if d[0] * s > 0 else -1))
        for bone in ("UpperArm", "LowerArm", "Hand"):
            out[f"{side}{bone}"] = d
        hip = head[f"{side}UpperLeg"]
        mids = []
        for z in np.arange(0.18, 0.46, 0.03):
            m = (s * co[:, 0] > 0.02) & (np.abs(co[:, 2] - z) < 0.015)
            if m.sum() > 10:
                mids.append(co[m].mean(0))
        mid, d = _line(np.array(mids))
        d = d * (1 if d[2] < 0 else -1)
        knee = Vector(mid + d * ((0.46 - mid[2]) / d[2]))
        out[f"{side}UpperLeg"] = (knee - hip).normalized()
        out[f"{side}LowerLeg"] = Vector(d)
    return out


def pose_limbs(arm: bpy.types.Object, directions: dict) -> None:
    """Turns each bone (parents first) about its head so it points along its direction."""
    for name, want in directions.items():
        pb = arm.pose.bones[name]
        head = pb.head.copy()
        turn = (pb.tail - pb.head).rotation_difference(want).to_matrix().to_4x4()
        pb.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ pb.matrix
        bpy.context.view_layer.update()


def transfer_weights(co: np.ndarray, body: np.ndarray, w: np.ndarray, k: int = 4) -> tuple:
    """The weights of the nearest body vertices (k, by inverse distance, normalized) at each point, and the distance
    to the nearest."""
    from mathutils.kdtree import KDTree

    tree = KDTree(len(body))
    for i, p in enumerate(body):
        tree.insert(p, i)
    tree.balance()
    out = np.zeros((len(co), w.shape[1]))
    near = np.zeros(len(co))
    for i, p in enumerate(co):
        found = tree.find_n(p, k)
        inv = np.array([1.0 / max(d, 1e-4) for _c, _j, d in found])
        row = (inv[:, None] * w[[j for _c, j, _d in found]]).sum(0)
        out[i] = row / max(row.sum(), 1e-6)
        near[i] = found[0][2]
    return out, near


def skirt_weights(co: np.ndarray, names: list, waist: float, hem: float, width: float) -> np.ndarray:
    """A skirt's weights: the hips at the waist, blending into the thigh on its side towards the hem."""
    w = np.zeros((len(co), len(names)))
    t = np.clip((waist - co[:, 2]) / (waist - hem), 0, 1)
    side = np.clip((co[:, 0] / width + 1) / 2, 0, 1)  # 1: the left (+x)
    w[:, names.index("Hips")] = 1 - 0.5 * t
    w[:, names.index("LeftUpperLeg")] = 0.5 * t * side
    w[:, names.index("RightUpperLeg")] = 0.5 * t * (1 - side)
    return w


def unskin(obj: bpy.types.Object, arm: bpy.types.Object, names: list, w: np.ndarray) -> None:
    """Moves the mesh from the armature's pose back into its rest pose (the inverse of its blended bones)."""
    co = G.vertices(obj.data)
    mats = np.array([np.array(arm.pose.bones[b].matrix @ arm.data.bones[b].matrix_local.inverted()) for b in names])
    blend = np.einsum("nb,bij->nij", w, mats)
    rest = np.einsum("nij,nj->ni", np.linalg.inv(blend), np.column_stack((co, np.ones(len(co)))))[:, :3]
    G.set_vertices(obj.data, rest)


def delete_faces(obj: bpy.types.Object, mask: np.ndarray) -> int:
    """Deletes the faces where `mask` (per face) is set, and the vertices left without faces."""
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    gone = [f for f in bm.faces if mask[f.index]]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    return len(gone)


def face_centers(obj: bpy.types.Object) -> np.ndarray:
    co = G.vertices(obj.data)
    return np.array([co[list(p.vertices)].mean(0) for p in obj.data.polygons])


def noise(size: int, scale: int, seed: int, octaves: int = 4) -> np.ndarray:
    """Tileable value noise in 0..1 (size x size), `scale` cells across in the first octave."""
    rnd = np.random.default_rng(seed)
    out = np.zeros((size, size))
    total = 0.0
    for o in range(octaves):
        cells = scale * 2**o
        g = rnd.random((cells, cells))
        idx = np.arange(size) * cells / size
        i0 = idx.astype(int)
        f = idx - i0
        f = f * f * (3 - 2 * f)
        i1 = (i0 + 1) % cells
        a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
        b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
        out += (a * (1 - f)[:, None] + b * f[:, None]) * 0.5**o
        total += 0.5**o
    return out / total
