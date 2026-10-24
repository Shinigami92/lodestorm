"""Shared helpers for people made with MakeHuman (MPFB 2, a Blender extension; see docs/TECHNICAL.md, People): a body
shaped by its sliders, dressed in MakeHuman garments that fit any body, rigged with MPFB's "game_engine" skeleton
renamed to Godot's humanoid bone names, so the shared clips (tools/blender/humanoid.py) play on everyone.

    import people as P
    C.reset("Nell")
    mpfb = P.enable()                      # after C.reset(): the reset unloads extensions
    arm, parts = P.build(PERSON, root)     # PERSON: the sliders and the assets, see build()
    body = P.body_of(arm)                  # humanoid.Body with the measures the clips stand it on

Assets come from MPFB's user data folder (installed asset packs, CC0 unless a person's script says otherwise).
"""

import pathlib

import addon_utils
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import common as C
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


# --- garments made here -----------------------------------------------------------------------------
# Parts no asset pack has (an apron, a belt) are built on the dressed body in its rest pose: their points are found
# by casting rays at the body and its clothes, and they take the weights of the body under them (a skirt-like
# panel blends from the hips into both thighs instead, so it doesn't tear between the legs).


def weight_matrix(obj: bpy.types.Object, names: list) -> np.ndarray:
    """The vertices' weights (vertices x names) from their vertex groups."""
    w = np.zeros((len(obj.data.vertices), len(names)))
    index = {g.index: names.index(g.name) for g in obj.vertex_groups if g.name in names}
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in index:
                w[v.index, index[g.group]] = g.weight
    return w


def nearest_weights(co: np.ndarray, points, w: np.ndarray) -> np.ndarray:
    """The weights of the vertex nearest to each point."""
    pts = np.asarray(points, dtype=float)
    out = np.empty((len(pts), w.shape[1]))
    for i in range(0, len(pts), 256):
        d = ((co[None, :, :] - pts[i : i + 256, None, :]) ** 2).sum(2)
        out[i : i + 256] = w[d.argmin(1)]
    return out


class Surface:
    """Ray casts against the given meshes (world space, rest pose), and the weights of their vertices nearest to a
    point (for what lies on them)."""

    def __init__(self, objs: list, names: list):
        dg = bpy.context.evaluated_depsgraph_get()
        self.trees = [BVHTree.FromObject(o, dg) for o in objs]
        self.names = names
        self.co = np.vstack([np.array([o.matrix_world @ v.co for v in o.data.vertices]) for o in objs])
        self.w = np.vstack([weight_matrix(o, names) for o in objs])

    def hit(self, origin, direction):
        """The nearest hit point along the ray, or None."""
        best, best_d = None, 1e9
        for t in self.trees:
            loc, _n, _i, dist = t.ray_cast(Vector(origin), Vector(direction).normalized(), 3.0)
            if loc is not None and dist < best_d:
                best, best_d = loc, dist
        return best

    def weights_at(self, points) -> np.ndarray:
        return nearest_weights(self.co, points, self.w)


def _mesh(name: str, verts, faces, uvs) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    layer = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        layer.data[loop.index].uv = uvs[loop.vertex_index]
    me.update()
    obj = bpy.data.objects.new(name, me)
    C.link(obj)
    for p in me.polygons:
        p.use_smooth = True
    return obj


def _skin(obj: bpy.types.Object, arm: bpy.types.Object, names: list, w: np.ndarray) -> None:
    for i, name in enumerate(names):
        g = obj.vertex_groups.new(name=name)
        for vi in np.nonzero(w[:, i] > 1e-4)[0]:
            g.add([int(vi)], float(w[vi, i]), "REPLACE")
    obj.parent = arm
    obj.modifiers.new("Armature", "ARMATURE").object = arm


def apron(
    arm: bpy.types.Object,
    surface: Surface,
    *,
    top: float,
    waist: float,
    hem: float,
    widths: tuple,
    gap: float = 0.012,
    drop: float = 0.04,
    columns: int = 14,
    rows: int = 32,
) -> bpy.types.Object:
    """An apron (`top`, `waist`, `hem`: heights in m; `widths`: half-widths at the top, the waist and the hem): the
    bib lies on the chest, the skirt hangs from the front-most point above it (straight down past the thighs), leaning
    out to `drop` (m) at the hem (clear of the knees when they bend) and curving back a little towards its sides. Weights: the bib the body's under it, the skirt from the hips into
    both thighs, more towards the hem."""
    zs = np.linspace(top, hem, rows + 1)
    us = np.linspace(-1.0, 1.0, columns + 1)
    half = np.interp(zs, [hem, waist, top], [widths[2], widths[1], widths[0]])
    grid = np.zeros((rows + 1, columns + 1, 3))
    hang = None
    for r, z in enumerate(zs):
        ys = np.array(
            [loc.y - gap if (loc := surface.hit((u * half[r], -1.0, z), (0, 1, 0))) is not None else np.nan for u in us]
        )
        front = np.nanmin(ys)
        t = (waist - z) / (waist - hem)
        if z < waist:
            hang = front if hang is None else min(hang, front)
            # Hanging straight, curving back towards the sides, never into the body.
            ys = np.fmin(hang - drop * t + 0.1 * np.abs(us) ** 3, np.where(np.isnan(ys), np.inf, ys))
        else:
            ys = np.where(np.isnan(ys), front, ys)
        grid[r, :, 0] = us * half[r]
        grid[r, :, 1] = ys
        grid[r, :, 2] = z
    verts = grid.reshape(-1, 3)
    n = columns + 1
    faces = [
        (r * n + c, r * n + c + 1, (r + 1) * n + c + 1, (r + 1) * n + c) for r in range(rows) for c in range(columns)
    ]
    uvs = [((u + 1) / 2, (z - hem) / (top - hem)) for z in zs for u in us]
    obj = _mesh("Apron", verts, faces, uvs)
    names = surface.names
    w = surface.weights_at(verts)
    hips, left, right = names.index("Hips"), names.index("LeftUpperLeg"), names.index("RightUpperLeg")
    skirt = verts[:, 2] < waist
    t = np.clip((waist - verts[skirt, 2]) / (waist - hem), 0, 1)
    side = np.clip((verts[skirt, 0] / widths[2] + 1) / 2, 0, 1)  # 1: her left (+x)
    w[skirt] = 0.0
    w[skirt, hips] = 1 - 0.5 * t
    w[skirt, left] = 0.5 * t * side
    w[skirt, right] = 0.5 * t * (1 - side)
    _skin(obj, arm, names, w)
    return obj


def strap(arm: bpy.types.Object, surface: Surface, points: list, *, width: float = 0.025, gap: float = 0.006):
    """A strap through `points` (an open path), each point moved onto the surface from outside (along the way from
    the neck's middle line), `width` wide across the path, lying flat on it. Weights: the body's under it."""
    path = []
    for p in points:
        p = Vector(p)
        out = Vector((p.x, p.y + 0.02, 0)).normalized()  # away from the neck's line (x = 0, y = -0.02)
        loc = surface.hit(p + out * 0.3, -out)
        path.append((loc if loc is not None else p) + out * gap)
    verts, uvs = [], []
    for k, p in enumerate(path):
        nxt = path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]
        out = Vector((p.x, p.y + 0.02, 0)).normalized()
        across = nxt.cross(out).normalized() * (width / 2)
        verts += [tuple(p - across), tuple(p + across)]
        uvs += [(0.0, k / (len(path) - 1)), (1.0, k / (len(path) - 1))]
    faces = [(2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2) for k in range(len(path) - 1)]
    obj = _mesh("Strap", verts, faces, uvs)
    _skin(obj, arm, surface.names, surface.weights_at(verts))
    return obj


def ring(surface: Surface, z: float, gap: float, steps: int = 48, reach: float = 0.32) -> np.ndarray:
    """Points round the body at height z, `gap` outside what's there (rays from `reach` outside the middle towards
    it: inside the arms hanging beside the body), the first at the front (-y), going round counter-clockwise seen
    from above."""
    pts = []
    for k in range(steps):
        a = 2 * np.pi * k / steps
        d = Vector((np.sin(a), -np.cos(a), 0.0))
        loc = surface.hit(Vector((0, 0, z)) + d * reach, -d)
        r = Vector((loc.x, loc.y, 0)).length if loc is not None else 0.15
        pts.append(tuple(Vector((0, 0, z)) + d * (r + gap)))
    return np.array(pts)


def belt(
    arm: bpy.types.Object,
    surface: Surface,
    *,
    z: float,
    height: float = 0.05,
    gap: float = 0.01,
    pouches: tuple = (),
) -> bpy.types.Object:
    """A belt round the body at height z (its middle), lying on what's there (an apron too), with `pouches` hanging
    on it ((angle in degrees from the front, counter-clockwise seen from above, (width, height, depth)) each):
    boxes, rigid on the hips like the belt."""
    lo = ring(surface, z - height / 2, gap)
    hi = ring(surface, z + height / 2, gap)
    steps = len(lo)
    verts = [tuple(v) for v in np.vstack([lo, hi])]
    faces = [(k, (k + 1) % steps, steps + (k + 1) % steps, steps + k) for k in range(steps)]
    uvs = [(k / steps, 0.0) for k in range(steps)] + [(k / steps, 0.25) for k in range(steps)]
    for angle, (w_, h_, d_) in pouches:
        a = np.radians(angle)
        out = np.array([np.sin(a), -np.cos(a), 0.0])
        along = np.array([np.cos(a), np.sin(a), 0.0])
        k = round(angle / 360 * steps) % steps
        base = (lo[k] + hi[k]) / 2 + out * (d_ / 2) - np.array([0, 0, h_ * 0.3])
        first = len(verts)
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    verts.append(tuple(base + along * sx * w_ / 2 + out * sy * d_ / 2 + np.array([0, 0, sz * h_ / 2])))
                    uvs.append((0.5 + 0.25 * sx, 0.6 + 0.3 * sz))
        boxes = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))
        faces += [tuple(first + i for i in f) for f in boxes]
    obj = _mesh("Belt", verts, faces, uvs)
    for p in obj.data.polygons[steps:]:
        p.use_smooth = False
    names = surface.names
    w = np.zeros((len(verts), len(names)))
    w[:, names.index("Hips")] = 1.0
    _skin(obj, arm, names, w)
    return obj


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


def worn_material(
    name: str, base, dark, *, size: int = 1024, seed: int = 1, roughness: float = 0.85, seam: float = 0.0
) -> bpy.types.Material:
    """A worn cloth or leather look in a texture: the `base` color (sRGB) mottled towards `dark` (stains, grime),
    `seam`: a darker border that wide (in UV; 0: none)."""
    stains = noise(size, 4, seed) * 0.6 + noise(size, 24, seed + 1) * 0.4
    grime = np.clip((stains - 0.45) * 2.5, 0, 1)[..., None]
    rgb = np.array(base)[None, None, :] * (1 - grime) + np.array(dark)[None, None, :] * grime
    if seam:
        u = np.linspace(0, 1, size)
        edge = np.minimum.outer(np.minimum(u, 1 - u), np.minimum(u, 1 - u))
        rgb *= np.where(edge < seam, 0.7, 1.0)[..., None]
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((size, size, 1))], axis=2).astype(np.float32)
    img = bpy.data.images.new(f"{name}Base", size, size)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat
