"""Shared parts of the map part kits modeled in place like the colony's (assets/parts/<kit>/source/<kit>_build.py:
the drill rig, the habitat, the lander): the material node helper `Mat` with its stripes and dark finish, joining
pieces, cutting below the ground, and the kit flow around a `PartKit` (the pieces, their layout in the part, the
ground's tint and the layout props): the preview scene, piece and layout renders, the report and the bake row.

Usage (a kit's build script):

    sys.path.insert(0, str(ROOT / "tools" / "blender"))
    import colony_part as P
    from colony_part import Mat, join, srgb
    KIT = P.PartKit(pieces=PIECES, layout=LAYOUT, out=OUT, ...)
    P.setup_preview(KIT); P.render_piece(KIT, name, prefix, views, samples, size); P.render_layout(KIT, path, ...)
"""

import dataclasses
import math
import pathlib
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
from common import T, rx, ry, srgb


@dataclasses.dataclass
class PartKit:
    """One map part kit's data for the shared flow."""

    pieces: list  # the pieces' object names
    layout: dict  # piece name: (x, y, z rotation in degrees) in the part (Blender; the way into the area is +Y)
    out: pathlib.Path  # where previews and renders go (tmp/assets/parts/<kit>)
    ground: tuple  # the preview ground's two linear colors (low, high), the biome's tone
    bake_gap: float  # m between the pieces in the saved .blend's row
    footprint: float  # the part's footprint ring (m)
    prop_radius: float  # the prop radius ring (m)
    crate: tuple  # the crate marker (x, y, z rotation in degrees)
    ore_spots: list  # the ore spot markers (x, y)
    pole: tuple  # the 1.89 m scale pole (x, y)


OLIVE = srgb(0.30, 0.31, 0.27)  # the layout crate's olive paint


class Mat:
    """Node helpers around one procedural material (object coordinates, world normal)."""

    def __init__(self, name: str):
        self.mat, self.nt, self.bsdf = C._new_material(name)
        self.geo = self.nt.nodes.new("ShaderNodeNewGeometry")
        self.obj = self.nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        pos = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.obj, pos.inputs["Vector"])
        self.x, self.y, self.z = pos.outputs["X"], pos.outputs["Y"], pos.outputs["Z"]
        nrm = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.geo.outputs["Normal"], nrm.inputs["Vector"])
        self.nz = nrm.outputs["Z"]

    def math(self, op, a, b=None, c=None, clamp=False):
        return C._math(self.nt, op, a, b, c, clamp)

    def noise(self, scale, detail=4.0, rough=0.55, stretch=None):
        vec = self.obj
        if stretch is not None:
            mp = self.nt.nodes.new("ShaderNodeMapping")
            mp.inputs["Scale"].default_value = stretch
            self.nt.links.new(self.obj, mp.inputs["Vector"])
            vec = mp.outputs["Vector"]
        return C._noise(self.nt, scale, detail, rough, vector=vec).outputs["Fac"]

    def ramp(self, a, b, src):
        return C._ramp(self.nt, a, b, src)

    def mix(self, fac, a, b):
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b):
        return C._mix_float(self.nt, fac, a, b)

    def scale(self, col, fac):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = "SCALE"
        self.nt.links.new(col, n.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, n.inputs["Scale"])
        else:
            n.inputs["Scale"].default_value = fac
        return n.outputs[0]

    def cavity(self, distance: float):
        """1 in cavities, 0 in the open (from AO)."""
        ao = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = distance
        ao.samples = 16
        return self.math("SUBTRACT", 1.0, self.ramp(0.3, 0.95, ao.outputs["AO"]), clamp=True)

    def low(self, z0: float, z1: float):
        """1 below z0, fading to 0 at z1 (object Z)."""
        n = self.nt.nodes.new("ShaderNodeMapRange")
        self.nt.links.new(self.z, n.inputs["Value"])
        n.inputs["From Min"].default_value = z0
        n.inputs["From Max"].default_value = z1
        n.inputs["To Min"].default_value = 1.0
        n.inputs["To Max"].default_value = 0.0
        return n.outputs["Result"]

    def out(self, color, rough, metallic, height, strength: float, distance: float) -> bpy.types.Material:
        self.nt.links.new(color, self.bsdf.inputs["Base Color"])
        for sock, val in ((self.bsdf.inputs["Roughness"], rough), (self.bsdf.inputs["Metallic"], metallic)):
            if isinstance(val, bpy.types.NodeSocket):
                self.nt.links.new(val, sock)
            else:
                sock.default_value = val
        C._bump(self.nt, self.bsdf, height, strength, distance)
        return self.mat


def stripes(m: Mat, period: float = 0.42):
    """1 on diagonal hazard bands, 0 between them (object coordinates, along X + Y - Z)."""
    d = m.nt.nodes.new("ShaderNodeVectorMath")
    d.operation = "DOT_PRODUCT"
    m.nt.links.new(m.obj, d.inputs[0])
    d.inputs[1].default_value = (0.7, 0.7, -0.7)
    frac = m.math("FRACT", m.math("DIVIDE", d.outputs["Value"], period))
    return m.math("MULTIPLY", m.ramp(0.47, 0.5, frac), m.ramp(0.0, 0.03, frac))


def mat_dark(name: str) -> bpy.types.Material:
    """Shadowed openings and recesses (inside a housing, a grille): near black, dull."""
    m = Mat(name)
    col = m.mix(m.noise(3.0), (0.008, 0.008, 0.009), (0.016, 0.015, 0.015))
    return m.out(col, 0.75, 0.0, m.noise(20.0), 0.1, 0.01)


def apply_modifiers(obj: bpy.types.Object) -> None:
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old = obj.data
    mats = list(old.materials)
    obj.modifiers.clear()
    obj.data = me
    if not me.materials:
        for mt in mats:
            me.materials.append(mt)
    bpy.data.meshes.remove(old)


def join(name: str, objs: list) -> bpy.types.Object:
    """Apply the objects' modifiers and join them into one mesh object `name` (asset collection, no parent)."""
    for o in objs:
        apply_modifiers(o)
        print(f"TRIS {name} / {o.name}: {sum(len(pl.vertices) - 2 for pl in o.data.polygons)}")
    # One at a time, in order: joining all at once takes them in an order of Blender's (it changes between runs),
    # so the vertex order (and with it the unwrap and the bake) would too.
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs[1:]:
        bpy.ops.object.select_all(action="DESELECT")
        objs[0].select_set(True)
        o.select_set(True)
        bpy.ops.object.join()
    obj = objs[0]
    obj.name = name
    obj.data.name = name
    obj.parent = None
    return obj


def transform_bm(bm: bmesh.types.BMesh, m: Matrix) -> None:
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])


def cut_below(bm: bmesh.types.BMesh, z: float) -> None:
    """Drop everything below z and close the cut."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=(0, 0, z), plane_no=(0, 0, -1), clear_outer=True)
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)


def light_rig(scale: float) -> None:
    """Scale the studio lights (set up for ~2 m props) around the origin for bigger pieces."""
    for o in C.collection("Preview").objects:
        if o.type != "LIGHT":
            continue
        base = o.get("base")
        if base is None:
            o["base"] = (*o.location, o.data.energy)
            base = o["base"]
        o.location = Vector(base[:3]) * scale
        o.data.energy = base[3] * scale * scale
        o.rotation_euler = (Vector((0, 0, 1.6 * scale)) - o.location).to_track_quat("-Z", "Y").to_euler()


def kit_objects(kit: PartKit) -> list:
    return [bpy.data.objects[n] for n in kit.pieces]


def ground_color(kit: PartKit) -> None:
    lo, hi = kit.ground
    C.tint_ground(lo, hi)


def build_layout_scene(kit: PartKit) -> None:
    """The game-angle layout's own props in a "Layout" collection (hidden in the studio renders): a big ground in
    the biome's tone, the 1.89 m pole, prop_radius and footprint rings, the crate and ore spot markers, a weak low
    sun and a little cool sky."""
    coll = bpy.data.collections.new("Layout")
    bpy.context.scene.collection.children.link(coll)

    def add(obj):
        coll.objects.link(obj)
        return obj

    def mat(name, color, rough=0.9, emit=0.0):
        mt, _nt, bsdf = C._new_material(name)
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        if emit:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emit
        return mt

    def mesh_obj(name, bm, material):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(material)
        for poly in me.polygons:
            poly.use_smooth = True
        return add(bpy.data.objects.new(name, me))

    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=45)
    ground = mesh_obj("LayoutGround", bm, bpy.data.materials["PreviewGround"])
    ground.location.z = -0.002
    for r, w, name in ((kit.prop_radius, 0.05, "LayoutRingProps"), (kit.footprint, 0.035, "LayoutRingFootprint")):
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=False, segments=128, radius=r)
        geom = bmesh.ops.extrude_edge_only(bm, edges=bm.edges[:])["geom"]
        for v in [g for g in geom if isinstance(g, bmesh.types.BMVert)]:
            v.co *= (r + w) / r
        mesh_obj(name, bm, mat(name, (0.6, 0.6, 0.55) if r == kit.prop_radius else (0.2, 0.2, 0.19), 0.8, 0.4))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.05, radius2=0.05, depth=1.89,
                          matrix=Matrix.Translation((0, 0, 0.945)))  # fmt: skip
    pole = mesh_obj("LayoutPole", bm, mat("LayoutPole", (0.7, 0.32, 0.05), 0.6, 0.6))
    pole.location = (*kit.pole, 0)
    crate_m = mat("LayoutCrate", OLIVE, 0.6)
    band_m = mat("LayoutCrateBand", (1.0, 0.55, 0.12), 0.5, 3.0)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((1.2, 0.8, 0.7, 1)) @ Matrix.Translation((0, 0, 0.5)))
    crate = mesh_obj("LayoutCrate", bm, crate_m)
    bm = bmesh.new()
    bmesh.ops.create_cube(
        bm, size=1.0, matrix=Matrix.Translation((0, 0, 0.45)) @ Matrix.Diagonal((1.22, 0.82, 0.06, 1))
    )
    band = mesh_obj("LayoutCrateBand", bm, band_m)
    for o in (crate, band):
        o.location = (kit.crate[0], kit.crate[1], 0)
        o.rotation_euler = (0, 0, math.radians(kit.crate[2]))
    ore_m = mat("LayoutOre", (0.12, 0.9, 0.85), 0.3, 4.0)
    rnd = random.Random(3)
    for i, (x, y) in enumerate(kit.ore_spots):
        bm = bmesh.new()
        for k in range(6):
            a = k / 6 * math.tau + rnd.uniform(-0.3, 0.3)
            r = rnd.uniform(0.3, 0.8)
            h = rnd.uniform(0.5, 1.0)
            m = T((math.cos(a) * r, math.sin(a) * r, h * 0.4), rx(-math.sin(a) * 25) @ ry(math.cos(a) * 25))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.13, radius2=0.0, depth=h, matrix=m)
        mesh_obj(f"LayoutOre{i}", bm, ore_m).location = (x, y, 0)
    sun = bpy.data.lights.new("LayoutSun", "SUN")
    sun.energy = 3.5
    sun.color = (0.85, 0.9, 1.0)
    sun.angle = math.radians(1.5)
    sun_obj = add(bpy.data.objects.new("LayoutSun", sun))
    sun_obj.rotation_euler = (math.radians(90 - 30), 0, math.radians(10))
    world = bpy.data.worlds.new("LayoutWorld")
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.05, 0.06, 0.08, 1.0)
    coll.hide_render = True


def setup_preview(kit: PartKit) -> None:
    C.preview_scene(crystals=False, pebbles=False)
    bpy.data.objects["PreviewGround"].scale = (3, 3, 1)
    ground_color(kit)
    build_layout_scene(kit)


def render_piece(kit: PartKit, name: str, prefix: str, views, samples: int, size: int) -> list:
    """The piece alone at the origin, framed by its size, the 1.8 m figure beside it, studio light."""
    obj = bpy.data.objects[name]
    for o in kit_objects(kit):
        o.hide_render = o is not obj
    obj.location = (0, 0, 0)
    dx, dy, dz = obj.dimensions
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # screen right in the iso view
    fig.location = side * (max(dx, dy) / 2 + 0.6)
    w = max(dx, dy, dz * 1.1) * 1.2 + 1.2
    light_rig(max(1.0, w / 5.0))
    target = side * 0.3 + Vector((0, 0, max(0.5, dz * 0.42)))
    out = []
    for view in views:
        path = kit.out / f"{prefix}{name}_{view}.png"
        C.render(
            path, view=view, samples=samples, size=size, target=tuple(target), zoom=w / (9.9 if view == "iso" else 6.3)
        )
        out.append(path)
    for o in kit_objects(kit):
        o.hide_render = False
    light_rig(1.0)
    return out


def render_layout(kit: PartKit, path: pathlib.Path, view: str, samples: int, size: int) -> pathlib.Path:
    """The part as the game places it (kit.layout), from the game's angle: pitched 50 degrees down, 45 degrees around
    (view "a": from +X/-Y like the game camera; "b": from the other side), dim cool light."""
    scene = bpy.context.scene
    coll = bpy.data.collections["Layout"]
    preview = C.collection("Preview")
    studio_world = scene.world
    coll.hide_render = False
    hidden = [o for o in preview.objects if not o.hide_render and o.type != "CAMERA"]
    for o in hidden:
        o.hide_render = True
    for name, (x, y, rot) in kit.layout.items():
        obj = bpy.data.objects[name]
        obj.location = (x, y, 0)
        obj.rotation_euler = (0, 0, math.radians(rot))
        obj.hide_render = False
    scene.world = bpy.data.worlds["LayoutWorld"]
    yaw = math.radians(-45 if view == "a" else 135)
    pitch = math.radians(50)
    dist = 38.0
    target = Vector((0, 0, 1.0))
    loc = (
        target
        + Vector((-math.sin(yaw), -math.cos(yaw), 0)) * dist * math.cos(pitch)
        + Vector((0, 0, dist * math.sin(pitch)))
    )
    C.render_from(path, tuple(loc), tuple(target), lens=42, samples=samples, size=size)
    scene.world = studio_world
    for o in hidden:
        o.hide_render = False
    coll.hide_render = True
    for obj in kit_objects(kit):
        obj.location = (0, 0, 0)
        obj.rotation_euler = (0, 0, 0)
    return path


def apply_bake_layout(kit: PartKit) -> None:
    """Saved .blend: the pieces unrotated in a row along X, kit.bake_gap apart (no AO from a neighbor in the bake)."""
    x = 0.0
    for name in kit.pieces:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + kit.bake_gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


def report(kit: PartKit) -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for name in kit.pieces:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        xs, ys, zs = ([v.co[i] for v in me.vertices] for i in range(3))
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} x=({min(xs):.2f}, {max(xs):.2f})"
            f" y=({min(ys):.2f}, {max(ys):.2f}) z=({min(zs):.2f}, {max(zs):.2f})"
            f" mats={[m.name for m in me.materials]}"
        )
        obj.evaluated_get(dg).to_mesh_clear()
