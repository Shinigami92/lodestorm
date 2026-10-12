"""Shared helpers for asset build scripts (Blender 5.2, run headless with tools/blender.sh).

Usage from an asset script (e.g. assets/miners/source/miner_glow_build.py):

    import sys, pathlib; sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3] / "tools" / "blender"))
    import common as C
    C.reset()
    miner = C.miner_root()               # empty "Miner" at the origin, in collection "Miner"
    ... build meshes, parent them to `miner`, use C.mat_* materials ...
    C.preview_scene()                    # ground, ore crystals, 1.8 m scale figure, lights, world
    C.render(out_dir / "render_iso.png", view="iso")
    C.render(out_dir / "render_hero.png", view="hero")
    C.save_blend(out_dir / "miner_x.blend")
    C.export_glb(out_dir / "miner_x.glb")

Conventions (Blender is Z-up, meters; glTF export converts to Y-up):
- The miner stands over an ore node centered at the origin; the drill tip touches the ground at (0, 0, 0).
- The game camera looks from the +X/-Y diagonal (front of the miner faces -Y, "front" = toward the camera).
- Everything that belongs to the asset is parented (directly or indirectly) to the "Miner" empty; preview props
  live in the "Preview" collection and are never exported.

Other assets name their own collection: C.reset("Rocks"), root = C.asset_root("Rocks"); link(), empty(),
export_glb() and stats() then use that collection. preview_scene(crystals=False) leaves out the placeholder ore,
render(..., target=..., zoom=...) frames smaller or bigger assets (zoom < 1 moves the camera closer),
render_from(...) renders from an own camera (close-ups).

Also here: transform helpers (T, rx/ry/rz, basis, polar), Part (hard-surface mesh builder), node helpers
(_noise, _ramp, _mix_color, _mix_float, _math, _bw, _bump, _bevel_edge, _voronoi_lines, bevel_wear) and
contact_sheet(). Baking procedural materials into textures and exporting the game .glb: tools/blender/bake.py.
"""

import math
import pathlib
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

PLAYER_HEIGHT = 1.8
ORE_NODE_RADIUS = 1.35  # deposit disc of the game's ore node; crystals sit within ~1.1 m
ASSET = "Miner"  # collection of the asset being built (set by reset())


# --- scene ---------------------------------------------------------------------------------------


def reset(asset: str = "Miner") -> None:
    global ASSET
    ASSET = asset
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    for name in (asset, "Preview"):
        coll = bpy.data.collections.new(name)
        scene.collection.children.link(coll)


def args() -> list[str]:
    """The script's own arguments (after Blender's "--")."""
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def collection(name: str) -> bpy.types.Collection:
    return bpy.data.collections[name]


def miner_root() -> bpy.types.Object:
    root = bpy.data.objects.new("Miner", None)
    root.empty_display_type = "PLAIN_AXES"
    collection("Miner").objects.link(root)
    return root


def asset_root(name: str) -> bpy.types.Object:
    """Empty at the origin in the asset's collection; parent everything that gets exported to it."""
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    collection(ASSET).objects.link(root)
    return root


def link(obj: bpy.types.Object, parent: bpy.types.Object | None = None, coll: str | None = None) -> bpy.types.Object:
    """Link a new object into a collection (default: the asset's) and optionally parent it, keeping its transform."""
    collection(coll or ASSET).objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def empty(name: str, location: tuple[float, float, float], parent: bpy.types.Object) -> bpy.types.Object:
    """A marker the game reads (e.g. "HoseOutlet")."""
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = 0.2
    obj.location = location
    return link(obj, parent)


# --- transforms ----------------------------------------------------------------------------------


def T(loc=(0, 0, 0), rot: Matrix | None = None, scale=(1, 1, 1)) -> Matrix:
    """4x4 matrix: translation, then rotation (3x3), then scale."""
    m = Matrix.Translation(Vector(loc))
    if rot is not None:
        m = m @ rot.to_4x4()
    return m @ Matrix.Diagonal((*scale, 1.0))


def rx(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rz(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def basis(z_dir: Vector, x_hint: Vector) -> Matrix:
    """3x3 rotation whose Z axis points along z_dir and X axis as close as possible to x_hint (a hint along z_dir
    falls back to Y or X)."""
    z = Vector(z_dir).normalized()
    x = Vector(x_hint)
    if abs(x.normalized().dot(z)) > 0.99:
        x = Vector((0, 1, 0)) if abs(z.y) < 0.9 else Vector((1, 0, 0))
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def polar(deg: float, r: float, z: float = 0.0) -> Vector:
    a = math.radians(deg)
    return Vector((math.cos(a) * r, math.sin(a) * r, z))


# --- mesh builder --------------------------------------------------------------------------------


class Part:
    """Accumulates primitives into one bmesh, one object at the end (keeps the draw calls low). Faces get the
    material index `mi` (into `mats`); bevel=(width, segments) adds common's bevel modifier, None leaves it off."""

    def __init__(self, name: str, mats: list, bevel: tuple[float, int] | None = (0.012, 2)):
        self.name, self.mats, self.bev = name, mats, bevel
        self.bm = bmesh.new()

    def _tag(self, verts, mi: int, smooth: bool = True):
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = mi
            f.smooth = smooth
        return verts

    def box(self, loc, size, rot: Matrix | None = None, mi: int = 0):
        return self._tag(bmesh.ops.create_cube(self.bm, size=1.0, matrix=T(loc, rot, size))["verts"], mi)

    def cyl(self, loc, r, depth, seg=16, rot: Matrix | None = None, mi=0, r2=None, caps=True, scale=(1, 1, 1), spin=0.0):
        m = T(loc, rot, scale) @ rz(spin).to_4x4()
        verts = bmesh.ops.create_cone(
            self.bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth, matrix=m
        )["verts"]
        return self._tag(verts, mi)

    def ring(self, z0, z1, r, seg=16, mi=0, r2=None, spin=0.0, xy=(0, 0)):
        """Vertical cylinder/frustum from z0 to z1 (r at z0, r2 at z1)."""
        return self.cyl((xy[0], xy[1], (z0 + z1) / 2), r, z1 - z0, seg, mi=mi, r2=r2, spin=spin)

    def beam(self, p0, p1, w, h, side, mi=0, taper=1.0):
        """Rectangular (optionally tapered) beam from p0 to p1; w measured along `side`."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        m = T((p0 + p1) / 2, basis(d, Vector(side)), (w, h, 1.0)) @ rz(45).to_4x4()
        r = math.sqrt(0.5)
        verts = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=4, radius1=r, radius2=r * taper, depth=d.length, matrix=m
        )["verts"]
        return self._tag(verts, mi)

    def rod(self, p0, p1, r, seg=12, mi=0, r2=None):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        m = T((p0 + p1) / 2, basis(d, Vector((0, 0, 1)) if abs(d.normalized().z) < 0.9 else Vector((1, 0, 0))))
        verts = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=d.length, matrix=m
        )["verts"]
        return self._tag(verts, mi)

    def sphere(self, loc, r, seg=12, rings=6, scale=(1, 1, 1), rot=None, mi=0):
        verts = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=r, matrix=T(loc, rot, scale))["verts"]
        return self._tag(verts, mi)

    def ico(self, loc, r, scale=(1, 1, 1), rot=None, mi=0, sub=1):
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=r, matrix=T(loc, rot, scale))["verts"]
        return self._tag(verts, mi, smooth=False)

    def prism(self, pts, z0, z1, m: Matrix | None = None, mi=0):
        """Extrude a CCW 2D polygon from z0 to z1 (local), transformed by m."""
        m = m or Matrix.Identity(4)
        bot = [self.bm.verts.new(m @ Vector((x, y, z0))) for x, y in pts]
        top = [self.bm.verts.new(m @ Vector((x, y, z1))) for x, y in pts]
        n = len(pts)
        faces = [self.bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i])) for i in range(n)]
        faces += [self.bm.faces.new(list(reversed(bot))), self.bm.faces.new(top)]
        for f in faces:  # faces.new() leaves the normal at zero; insets and edge angles need it
            f.normal_update()
        return self._tag(bot + top, mi)

    def _bevel(self, obj: bpy.types.Object) -> None:
        bevel(obj, self.bev[0], self.bev[1])

    def finish(self, parent) -> bpy.types.Object:
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, me)
        link(obj, parent)
        for mat in self.mats:
            me.materials.append(mat)
        if self.bev:
            self._bevel(obj)
        return obj


# --- modifiers -----------------------------------------------------------------------------------


def bevel(obj: bpy.types.Object, width: float = 0.015, segments: int = 2, angle_deg: float = 35.0) -> None:
    """Rounded hard-surface edges (catch the rim light) + weighted normals for clean shading."""
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle_deg)
    mod.harden_normals = True
    obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL").keep_sharp = True


def shade_smooth(obj: bpy.types.Object) -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = True


# --- materials -----------------------------------------------------------------------------------
# Procedural Cycles materials for look development. Edge wear uses Pointiness (Cycles only), grime uses AO.
# For the game they get baked to textures later; keep the node setups self-contained per material.


def _new_material(name: str) -> tuple[bpy.types.Material, bpy.types.NodeTree, bpy.types.Node]:
    mat = bpy.data.materials.get(name)
    if mat:
        return mat, mat.node_tree, mat.node_tree.nodes["Principled BSDF"]
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True  # deprecated (always on) in newer versions
    except AttributeError:
        pass
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF") or nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.get("Material Output") or nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, nt, bsdf


def _noise(
    nt: bpy.types.NodeTree,
    scale: float,
    detail: float = 6.0,
    roughness: float = 0.6,
    vector: bpy.types.NodeSocket | None = None,
    distortion: float | None = None,
) -> bpy.types.Node:
    """Noise texture on `vector` (default: its own object coordinates)."""
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = detail
    tex.inputs["Roughness"].default_value = roughness
    if distortion is not None:
        tex.inputs["Distortion"].default_value = distortion
    if vector is None:
        vector = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    nt.links.new(vector, tex.inputs["Vector"])
    return tex


def _ramp(nt: bpy.types.NodeTree, a: float, b: float, src: bpy.types.NodeSocket) -> bpy.types.NodeSocket:
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = a
    ramp.color_ramp.elements[1].position = b
    nt.links.new(src, ramp.inputs["Fac"])
    return ramp.outputs["Color"]


def _mix_color(nt, fac, a, b) -> bpy.types.NodeSocket:
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(fac, mix.inputs["Factor"])
    for sock, val in ((mix.inputs[6], a), (mix.inputs[7], b)):
        if isinstance(val, bpy.types.NodeSocket):
            nt.links.new(val, sock)
        else:
            sock.default_value = (*val, 1.0) if len(val) == 3 else val
    return mix.outputs[2]


def _mix_float(nt, fac, a, b) -> bpy.types.NodeSocket:
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "FLOAT"
    nt.links.new(fac, mix.inputs["Factor"])
    for sock, val in ((mix.inputs[2], a), (mix.inputs[3], b)):
        if isinstance(val, bpy.types.NodeSocket):
            nt.links.new(val, sock)
        else:
            sock.default_value = val
    return mix.outputs[0]


def _math(nt, op: str, a, b=None, c=None, clamp: bool = False) -> bpy.types.NodeSocket:
    """Math node; a/b/c are sockets (linked) or numbers (set), None leaves an input alone."""
    node = nt.nodes.new("ShaderNodeMath")
    node.operation = op
    node.use_clamp = clamp
    for sock, val in ((node.inputs[0], a), (node.inputs[1], b), (node.inputs[2], c)):
        if val is None:
            continue
        if isinstance(val, bpy.types.NodeSocket):
            nt.links.new(val, sock)
        else:
            sock.default_value = val
    return node.outputs[0]


def _bw(nt, color: bpy.types.NodeSocket) -> bpy.types.NodeSocket:
    rgb = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(color, rgb.inputs["Color"])
    return rgb.outputs["Val"]


def _bump(nt, bsdf: bpy.types.Node, height: bpy.types.NodeSocket, strength: float, distance: float) -> None:
    """Bump from `height` into the BSDF's normal."""
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = distance
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def _bevel_edge(nt, radius: float, geo: bpy.types.Node | None = None) -> bpy.types.NodeSocket:
    """Convex edges: 1 - dot(Bevel node normal, true normal), > 0 near edges (feed it through a ramp). Unlike
    Pointiness (per vertex) it doesn't depend on the mesh density."""
    geo = geo or nt.nodes.new("ShaderNodeNewGeometry")
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = radius
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    return _math(nt, "SUBTRACT", 1.0, dot.outputs["Value"])


def _voronoi_lines(nt, vector: bpy.types.NodeSocket, scale: float, width: float) -> bpy.types.NodeSocket:
    """1 on thin lines along the Voronoi cell edges (cracks, veins), fading to 0 at `width`."""
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = scale
    nt.links.new(vector, vor.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
    ramp.color_ramp.elements[1].position = width
    ramp.color_ramp.elements[1].color = (0, 0, 0, 1)
    nt.links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
    return ramp.outputs["Color"]


def mat_painted_metal(
    name: str,
    color: tuple[float, float, float],
    wear: float = 0.5,
    grime: float = 0.6,
    roughness: float = 0.55,
) -> bpy.types.Material:
    """Weathered painted metal: paint with roughness variation, bare steel on worn edges, grime in cavities,
    fine scratches in the bump. wear/grime 0..1."""
    mat, nt, bsdf = _new_material(name)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    breakup = _noise(nt, 18.0, 8.0, 0.65)
    # Edge wear: convex edges (pointiness > 0.5) broken up by noise.
    # wear 0 disables edge wear (pointiness never reaches 2).
    edge = _ramp(nt, 0.565 - 0.015 * wear if wear > 0 else 2.0, 0.62 - 0.015 * wear if wear > 0 else 2.1, geo.outputs["Pointiness"])
    edge_mask = nt.nodes.new("ShaderNodeMath")
    edge_mask.operation = "MULTIPLY"
    nt.links.new(edge, edge_mask.inputs[0])
    nt.links.new(_ramp(nt, 0.45, 0.6, breakup.outputs["Fac"]), edge_mask.inputs[1])
    # Grime: cavities (AO) and a large blotchy noise.
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.15
    cavity = _ramp(nt, 0.35, 0.95, ao.outputs["AO"])  # white where open, dark in cavities
    blotch = _noise(nt, 2.5, 4.0, 0.5)
    grime_mask = nt.nodes.new("ShaderNodeMath")
    grime_mask.operation = "MULTIPLY"
    inv = nt.nodes.new("ShaderNodeInvert")
    nt.links.new(cavity, inv.inputs["Color"])
    nt.links.new(inv.outputs["Color"], grime_mask.inputs[0])
    grime_mask.inputs[1].default_value = grime
    blotch_mask = _ramp(nt, 0.55, 0.75, blotch.outputs["Fac"])
    grime_total = nt.nodes.new("ShaderNodeMath")
    grime_total.operation = "ADD"
    grime_total.use_clamp = True
    nt.links.new(grime_mask.outputs[0], grime_total.inputs[0])
    blot = nt.nodes.new("ShaderNodeMath")
    blot.operation = "MULTIPLY"
    nt.links.new(blotch_mask, blot.inputs[0])
    blot.inputs[1].default_value = 0.5 * grime
    nt.links.new(blot.outputs[0], grime_total.inputs[1])
    # Paint color varies slightly, then grime darkens it, then worn edges show steel.
    paint = _mix_color(nt, breakup.outputs["Fac"], tuple(c * 0.85 for c in color), tuple(min(1, c * 1.1) for c in color))
    grimy = _mix_color(nt, grime_total.outputs[0], paint, (0.035, 0.03, 0.025))
    steel = (0.55, 0.55, 0.56)
    base = _mix_color(nt, edge_mask.outputs[0], grimy, steel)
    nt.links.new(base, bsdf.inputs["Base Color"])
    nt.links.new(edge_mask.outputs[0], bsdf.inputs["Metallic"])
    rough = _mix_float(nt, breakup.outputs["Fac"], roughness - 0.12, roughness + 0.12)
    rough = _mix_float(nt, grime_total.outputs[0], rough, 0.85)
    rough = _mix_float(nt, edge_mask.outputs[0], rough, 0.32)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    # Scratches: stretched fine noise in the bump.
    _bump(nt, bsdf, _noise(nt, 120.0, 2.0, 0.4).outputs["Fac"], 0.08, 0.002)
    return mat


def bevel_wear(mat: bpy.types.Material, lo: float = 0.015, hi: float = 0.07, radius: float = 0.012) -> None:
    """Swap mat_painted_metal's Pointiness edge mask for a Bevel-node one: Pointiness is per vertex and smears wear
    over whole faces on low-poly meshes (the camouflage look); the Bevel node finds edges independent of density.
    Defaults are sized for the 3.6 m miner."""
    nt = mat.node_tree
    geo = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeNewGeometry")
    link = next(lk for lk in nt.links if lk.from_node == geo and lk.from_socket.name == "Pointiness")
    ramp = link.to_node
    nt.links.remove(link)
    edge = _bevel_edge(nt, radius, geo)
    ramp.color_ramp.elements[0].position = lo
    ramp.color_ramp.elements[1].position = hi
    nt.links.new(edge, ramp.inputs["Fac"])


def mat_bare_metal(name: str = "BareMetal", color=(0.42, 0.42, 0.43), roughness: float = 0.38) -> bpy.types.Material:
    mat, nt, bsdf = _new_material(name)
    noise = _noise(nt, 40.0, 6.0, 0.6)
    nt.links.new(_mix_color(nt, noise.outputs["Fac"], tuple(c * 0.7 for c in color), color), bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 1.0
    nt.links.new(_mix_float(nt, noise.outputs["Fac"], roughness - 0.1, roughness + 0.15), bsdf.inputs["Roughness"])
    return mat


def mat_rubber(name: str = "Rubber", color=(0.025, 0.025, 0.025)) -> bpy.types.Material:
    mat, nt, bsdf = _new_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def mat_glass(name: str = "Glass", tint=(0.8, 0.95, 1.0)) -> bpy.types.Material:
    mat, nt, bsdf = _new_material(name)
    bsdf.inputs["Base Color"].default_value = (*tint, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.05
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["IOR"].default_value = 1.45
    return mat


def mat_emissive(name: str, color: tuple[float, float, float], strength: float = 8.0) -> bpy.types.Material:
    mat, nt, bsdf = _new_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.3
    return mat


def mat_ore_fill(name: str = "OreFill", color=(0.1, 0.95, 0.9)) -> bpy.types.Material:
    """Glowing ore inside the column (in game the ore type's material replaces it)."""
    mat, nt, bsdf = _new_material(name)
    noise = _noise(nt, 6.0, 4.0, 0.55)
    strength = _mix_float(nt, noise.outputs["Fac"], 3.0, 9.0)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    nt.links.new(strength, bsdf.inputs["Emission Strength"])
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Transmission Weight"].default_value = 0.4
    return mat


def assign(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(mat)


# --- preview scene ---------------------------------------------------------------------------------


def _preview_obj(obj: bpy.types.Object) -> bpy.types.Object:
    return link(obj, None, "Preview")


def preview_scene(
    seed: int = 3, crystals: bool = True, figure_location: tuple[float, float, float] = (1.9, -1.6, 0.0)
) -> None:
    """Dark rocky ground, a cyan ore crystal cluster under the miner (crystals=False leaves it out), a 1.8 m
    figure for scale, lights."""
    import random

    rnd = random.Random(seed)
    # Ground.
    bpy.ops.mesh.primitive_plane_add(size=40)
    ground = bpy.context.active_object
    for c in ground.users_collection:
        c.objects.unlink(ground)
    _preview_obj(ground)
    ground.name = "PreviewGround"
    gmat, nt, bsdf = _new_material("PreviewGround")
    noise = _noise(nt, 1.5, 8.0, 0.6)
    nt.links.new(_mix_color(nt, noise.outputs["Fac"], (0.012, 0.011, 0.010), (0.04, 0.037, 0.034)), bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    fine = _noise(nt, 30.0, 6.0, 0.7)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    assign(ground, gmat)
    # Ore crystals (placeholder for the game's ore node).
    crystal = mat_emissive("PreviewCrystal", (0.12, 0.9, 0.85), 4.0)
    crystal.node_tree.nodes["Principled BSDF"].inputs["Transmission Weight"].default_value = 0.6
    for i in range(9 if crystals else 0):
        ang = i / 9 * math.tau + rnd.uniform(-0.2, 0.2)
        r = rnd.uniform(0.75, 1.1)
        h = rnd.uniform(0.5, 1.1)
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.13, radius2=0.0, depth=h)
        obj = bpy.context.active_object
        for c in obj.users_collection:
            c.objects.unlink(obj)
        _preview_obj(obj)
        obj.location = (math.cos(ang) * r, math.sin(ang) * r, h * 0.4)
        obj.rotation_euler = (-math.sin(ang) * 0.45, math.cos(ang) * 0.45, 0)
        assign(obj, crystal)
    # Rubble.
    rock = mat_painted_metal("PreviewRock", (0.07, 0.065, 0.06), wear=0.0, grime=0.3, roughness=0.85)
    for i in range(25):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=rnd.uniform(0.05, 0.35))
        obj = bpy.context.active_object
        for c in obj.users_collection:
            c.objects.unlink(obj)
        _preview_obj(obj)
        ang = rnd.uniform(0, math.tau)
        r = rnd.uniform(1.4, 6.0)
        obj.location = (math.cos(ang) * r, math.sin(ang) * r, 0.02)
        obj.scale = (1, rnd.uniform(0.6, 1.3), rnd.uniform(0.4, 0.8))
        obj.rotation_euler = (rnd.uniform(0, 3), rnd.uniform(0, 3), rnd.uniform(0, 3))
        assign(obj, rock)
    # Scale figure: 1.8 m, standing in front-right of the miner.
    suit = mat_painted_metal("PreviewSuit", (0.6, 0.6, 0.58), wear=0.3, grime=0.5)
    parts = [
        ("cyl", (0.0, 0.0, 0.45), (0.1, 0.1, 0.45)),  # legs block
        ("cyl", (0.0, 0.0, 1.15), (0.22, 0.16, 0.32)),  # torso
        ("sph", (0.0, 0.0, 1.62), (0.15, 0.15, 0.17)),  # helmet
        ("box", (0.0, 0.17, 1.2), (0.17, 0.08, 0.22)),  # backpack
    ]
    figure = bpy.data.objects.new("PreviewFigure", None)
    _preview_obj(figure)
    for kind, loc, scl in parts:
        if kind == "cyl":
            bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=1, depth=2)
        elif kind == "sph":
            bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=1)
        else:
            bpy.ops.mesh.primitive_cube_add(size=2)
        obj = bpy.context.active_object
        for c in obj.users_collection:
            c.objects.unlink(obj)
        _preview_obj(obj)
        obj.location = loc
        obj.scale = scl
        obj.parent = figure
        assign(obj, suit)
    figure.location = figure_location
    figure.rotation_euler = (0, 0, math.radians(30))
    _lights()


def _lights() -> None:
    scene = bpy.context.scene
    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.012, 0.014, 0.018, 1.0)
    bg.inputs["Strength"].default_value = 1.0

    def area(name, loc, energy, color, size):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.color = color
        data.size = size
        obj = bpy.data.objects.new(name, data)
        _preview_obj(obj)
        obj.location = loc
        direction = Vector((0, 0, 1.6)) - Vector(loc)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        return obj

    # Dim warm key from the camera side, strong cool rim from behind, faint fill.
    area("Key", (5.0, -6.0, 7.0), 350, (1.0, 0.86, 0.72), 3.0)
    area("Rim", (-5.5, 6.0, 5.0), 2500, (0.55, 0.75, 1.0), 2.5)
    area("RimLow", (-6.0, 3.0, 1.5), 600, (0.55, 0.75, 1.0), 2.0)
    area("Fill", (-6.0, -4.0, 3.0), 60, (0.6, 0.7, 0.9), 4.0)


# --- render / export -------------------------------------------------------------------------------


def _camera(view: str, target: tuple[float, float, float] = (0, 0, 1.6), zoom: float = 1.0) -> bpy.types.Object:
    for old in [o for o in bpy.data.objects if o.name.startswith("Cam")]:
        bpy.data.objects.remove(old)
    data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", data)
    _preview_obj(cam)
    target = Vector(target)
    if view == "custom":  # render_from() places it
        return cam
    if view == "iso":
        # Game-like: high, along the diagonal, about 45 degrees down.
        data.lens = 50
        cam.location = target + Vector((7.0, -7.0, 9.5)) * zoom
    elif view == "hero":
        data.lens = 40
        cam.location = target + Vector((4.2, -5.5, 1.6)) * zoom
    elif view == "back":
        data.lens = 40
        cam.location = target + Vector((-4.5, 5.5, 2.5)) * zoom
    else:
        raise ValueError(view)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render(
    path: pathlib.Path,
    view: str = "iso",
    samples: int = 96,
    size: int = 1024,
    target: tuple[float, float, float] = (0, 0, 1.6),
    zoom: float = 1.0,
) -> None:
    _render_settings(samples, size)
    _camera(view, target, zoom)
    _write_render(path)


def render_from(path: pathlib.Path, location, target, lens: float = 35.0, samples: int = 96, size: int = 1024) -> None:
    """Render from an own camera (close-ups, debug views), with the same settings as render()."""
    _render_settings(samples, size)
    cam = _camera("custom")
    cam.data.lens = lens
    cam.location = location
    cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    _write_render(path)


def _render_settings(samples: int, size: int) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    scene.cycles.device = "GPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.image_settings.file_format = "PNG"


def _write_render(path: pathlib.Path) -> None:
    bpy.context.scene.render.filepath = str(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


def contact_sheet(paths: list, out: pathlib.Path, cols: int = 4, tile: int | None = None, background: float = 0.0) -> None:
    """Tile renders into one PNG (row-major, top-left first) with Blender's image API (no Pillow needed). tile=None
    keeps the first image's size; missing files leave their cell empty."""
    import numpy as np

    paths = [pathlib.Path(p) for p in paths]
    if tile is None:
        first = bpy.data.images.load(str(next(p for p in paths if p.exists())))
        tile = first.size[0]
        bpy.data.images.remove(first)
    rows = math.ceil(len(paths) / cols)
    sheet = np.full((rows * tile, cols * tile, 4), background, dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, p in enumerate(paths):
        if not p.exists():
            continue
        img = bpy.data.images.load(str(p))
        if tuple(img.size) != (tile, tile):
            img.scale(tile, tile)
        px = np.empty(tile * tile * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * tile  # Blender images start at the bottom row
        sheet[y0 : y0 + tile, c * tile : (c + 1) * tile] = px.reshape(tile, tile, 4)
        bpy.data.images.remove(img)
    img = bpy.data.images.new("sheet", cols * tile, rows * tile, alpha=False)
    img.pixels.foreach_set(sheet.ravel())
    img.filepath_raw = str(out)
    img.file_format = "PNG"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save()
    bpy.data.images.remove(img)
    print("SHEET", out)


def save_blend(path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(path))


def export_glb(path: pathlib.Path, coll: str | None = None) -> None:
    """Export only the asset's collection (modifiers applied). Procedural materials export as their
    Principled defaults until they are baked to textures."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection(coll or ASSET).all_objects:
        obj.select_set(True)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_apply=True)


def tris_per_object(coll: str | None = None) -> dict:
    """Triangles per mesh object of the asset (after modifiers), biggest first."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    rows = {}
    for obj in collection(coll or ASSET).all_objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(depsgraph)
            me = ev.to_mesh()
            me.calc_loop_triangles()
            rows[obj.name] = len(me.loop_triangles)
            ev.to_mesh_clear()
    return dict(sorted(rows.items(), key=lambda kv: -kv[1]))


def stats(coll: str | None = None) -> dict:
    """Triangle count and bounds of the asset (after modifiers) for the report."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tris = 0
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in collection(coll or ASSET).all_objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
        mesh.calc_loop_triangles()
        tris += len(mesh.loop_triangles)
        for v in mesh.vertices:
            w = ev.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        ev.to_mesh_clear()
    return {"triangles": tris, "min": tuple(round(x, 2) for x in lo), "max": tuple(round(x, 2) for x in hi)}
