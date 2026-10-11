"""Blaster: the player's rifle, industrial and weathered, with a glowing ammo counter (concept: weapon_house).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/weapons/source/blaster_build.py wip r1 [views]
    tools/blender.sh assets/weapons/source/blaster_build.py final
    tools/blender.sh assets/weapons/source/blaster_build.py sheet

Everything it writes goes to tmp/assets/blaster/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: iso, hero, back, side, top, right, scale, game); "final" renders the preview set and saves
the procedural blaster_procedural.blend that blaster_bake.py turns into the game asset; "sheet" tiles the final
renders into sheet.png.

Layout (Blender Z-up meters; glTF turns +Y into Godot's -Z = forward): the barrel points along +Y, the origin is
the main hand on the pistol grip. Empties: "Muzzle" (barrel tip), "Grip" (= origin), "Foregrip" (support hand).
Meshes: "Body" (one object, gets the baked atlas), "AmmoCounter" (emissive segments on both sides, UV.x per
segment = 0..1 from the rear to the front, so a shader can light them by ammo fraction) and "EnergyCell"
(emissive windows of the power cell in the magazine well).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "blaster"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["iso", "hero"]

ASSET = "Blaster"
HOLD_Z = 1.1  # preview only: the gun is lifted to the player's hand height (WeaponMount in player.tscn)

# --- layout (meters, Z-up, forward = +Y, origin = main hand on the grip) ----------------------------

GRIP_TILT = -15.0  # degrees around X: grip top leans forward
UPPER_Y = (-0.11, 0.23)
UPPER_Z = (0.11, 0.188)
UPPER_W = 0.076
LOWER_W = 0.066
BORE_Z = 0.150  # barrel axis
SHROUD_Y = (0.22, 0.46)
SHROUD_R = 0.041
BARREL_END = 0.545
MUZZLE_Y = 0.592
TUBE_Z = 0.086  # lower (emitter) tube under the barrel, the support hand holds its ribbed sleeve
TUBE_Y = (0.19, 0.50)
FOREGRIP_Y = 0.35
CELL_PIVOT = Vector((0.0, 0.14, 0.056))  # top of the energy cell in the magazine well
CELL_TILT = 8.0
CELL_SIZE = (0.054, 0.068, 0.105)
COUNTER_Y = (0.012, 0.142)
COUNTER_TILT = 40.0  # the counter sits on the receiver's top edges, facing up and out (seen from the high camera)
COUNTER_H = 0.046  # housing height in its tilted plane
COUNTER_SEGMENTS = 6
STOCK_Y = -0.31

# --- math helpers -----------------------------------------------------------------------------------


def T(loc=(0, 0, 0), rot: Matrix | None = None, scale=(1, 1, 1)) -> Matrix:
    m = Matrix.Translation(Vector(loc))
    if rot is not None:
        m = m @ rot.to_4x4()
    return m @ Matrix.Diagonal((*scale, 1.0))


def rz(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def rx(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "Y")


ALONG_Y = rx(-90)  # primitives are built along Z; this turns them along +Y (the barrel axis)
# Profiles drawn in the side view (y, z) and extruded across X.
SIDE = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0)))


def basis(z_dir: Vector, x_hint: Vector) -> Matrix:
    """3x3 rotation whose Z axis points along z_dir and X axis as close as possible to x_hint."""
    z = Vector(z_dir).normalized()
    x = Vector(x_hint)
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


# --- mesh builder (same as the miner's) -------------------------------------------------------------


class Part:
    """Accumulates primitives into one bmesh, one object at the end (keeps the draw calls low)."""

    def __init__(self, name: str, mats: list, bevel: tuple[float, int] | None = (0.003, 1)):
        self.name, self.mats, self.bev = name, mats, bevel
        self.bm = bmesh.new()
        self.weight = self.bm.edges.layers.float.new("bevel_weight_edge")
        self.detail = False  # small parts: hard edges instead of bevels (saves triangles)

    def _tag(self, verts, mi: int, smooth: bool = True):
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = mi
            f.smooth = smooth
        for e in {e for f in faces for e in f.edges}:
            hard = e.is_manifold and e.calc_face_angle(0.0) > math.radians(35)
            e[self.weight] = 1.0 if hard and not self.detail else 0.0
            e.smooth = not (hard and self.detail)
        return verts

    def box(self, loc, size, rot: Matrix | None = None, mi: int = 0):
        return self._tag(bmesh.ops.create_cube(self.bm, size=1.0, matrix=T(loc, rot, size))["verts"], mi)

    def cyl(self, loc, r, depth, seg=16, rot: Matrix | None = None, mi=0, r2=None, caps=True, scale=(1, 1, 1), spin=0.0):
        m = T(loc, rot, scale) @ rz(spin).to_4x4()
        verts = bmesh.ops.create_cone(
            self.bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth, matrix=m
        )["verts"]
        return self._tag(verts, mi)

    def ycyl(self, y0, y1, r, z, seg=16, mi=0, r2=None, x=0.0, spin=0.0, scale=(1, 1, 1), caps=True):
        """Cylinder/frustum along +Y from y0 to y1 (r at y0, r2 at y1) on the axis (x, z)."""
        return self.cyl((x, (y0 + y1) / 2, z), r, y1 - y0, seg, rot=ALONG_Y, mi=mi, r2=r2, spin=spin, scale=scale, caps=caps)

    def xcyl(self, loc, r, depth, seg=8, mi=0):
        """Short cylinder across X (bolt heads, knobs)."""
        return self.cyl(loc, r, depth, seg, rot=ry(90), mi=mi)

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

    def prism(self, pts, z0, z1, m: Matrix | None = None, mi=0):
        """Extrude a 2D polygon from z0 to z1 (local), transformed by m."""
        m = m or Matrix.Identity(4)
        bot = [self.bm.verts.new(m @ Vector((x, y, z0))) for x, y in pts]
        top = [self.bm.verts.new(m @ Vector((x, y, z1))) for x, y in pts]
        n = len(pts)
        faces = [self.bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i])) for i in range(n)]
        faces += [self.bm.faces.new(list(reversed(bot))), self.bm.faces.new(top)]
        for f in faces:  # faces.new() leaves the normal at zero: _tag()'s edge angles and inset_faces() need it
            f.normal_update()
        return self._tag(bot + top, mi)

    def side_prism(self, pts, width, loc=(0, 0, 0), rot: Matrix | None = None, mi=0, x=0.0):
        """Profile drawn in the side view as (y, z) points, extruded across X (width centered on x)."""
        m = T((loc[0] + x, loc[1], loc[2]), rot) @ SIDE.to_4x4()
        return self.prism(pts, -width / 2, width / 2, m, mi)

    def finish(self, parent) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, me)
        C.link(obj, parent)
        for mat in self.mats:
            me.materials.append(mat)
        if self.bev:
            bevel_weighted(obj, self.bev[0], self.bev[1])
        return obj


def bevel_weighted(obj: bpy.types.Object, width: float, segments: int) -> None:
    """Like common.bevel(), but only on edges with a bevel weight (the big forms, see Part.detail)."""
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "WEIGHT"
    mod.harden_normals = True
    obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL").keep_sharp = True


def inset_faces(part: Part, verts, axis: Vector, thickness=0.005, depth=-0.0015, mi=None, min_area=0.0):
    """Panel lines: inset the faces of a fresh primitive whose normal is (close to) along +-axis."""
    axis = Vector(axis).normalized()
    faces = {f for v in verts for f in v.link_faces if abs(f.normal.dot(axis)) > 0.9 and f.calc_area() > min_area}
    bmesh.ops.inset_individual(part.bm, faces=list(faces), thickness=thickness, depth=depth, use_even_offset=True)
    if mi is not None:
        for f in faces:
            f.material_index = mi


def ring_faces(part: Part, verts, axis: Vector, thickness=0.004, depth=-0.0015):
    """Panel lines on the side faces of a cylinder built along `axis` (normals perpendicular to it)."""
    axis = Vector(axis).normalized()
    faces = [f for f in {f for v in verts for f in v.link_faces} if abs(f.normal.dot(axis)) < 0.2]
    bmesh.ops.inset_individual(part.bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)
    return faces


# --- materials --------------------------------------------------------------------------------------


def bevel_wear(mat: bpy.types.Material, lo: float = 0.012, hi: float = 0.05, radius: float = 0.005) -> None:
    """Swap common's Pointiness edge mask for a Bevel-node one (as on the miner), sized for a hand-held object."""
    nt = mat.node_tree
    geo = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeNewGeometry")
    link = next(lk for lk in nt.links if lk.from_node == geo and lk.from_socket.name == "Pointiness")
    ramp = link.to_node
    nt.links.remove(link)
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = radius
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(dot.outputs["Value"], inv.inputs[1])
    ramp.color_ramp.elements[0].position = lo
    ramp.color_ramp.elements[1].position = hi
    nt.links.new(inv.outputs[0], ramp.inputs["Fac"])


def rescale(mat: bpy.types.Material, noise_factor: float, ao_distance: float) -> None:
    """common's materials are tuned for a 3.6 m machine: shrink their noise and cavity sizes to a 0.9 m gun."""
    for n in mat.node_tree.nodes:
        if n.bl_idname == "ShaderNodeTexNoise":
            n.inputs["Scale"].default_value *= noise_factor
        elif n.bl_idname == "ShaderNodeAmbientOcclusion":
            n.inputs["Distance"].default_value = ao_distance
        elif n.bl_idname == "ShaderNodeBump":
            n.inputs["Distance"].default_value *= 0.5


def add_chips(mat: bpy.types.Material, amount: float = 0.5, scale: float = 70.0) -> None:
    """Paint chips and scuffs on the flat faces too (common's wear only reaches the edges): a fine noise
    thresholded inside a large worn-area mask shows bare metal."""
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    fine = C._noise(nt, scale, 10.0, 0.72)
    area = C._noise(nt, scale / 12.0, 3.0, 0.5)
    chip = nt.nodes.new("ShaderNodeMath")
    chip.operation = "MULTIPLY"
    nt.links.new(C._ramp(nt, 0.64 - 0.06 * amount, 0.67 - 0.06 * amount, fine.outputs["Fac"]), chip.inputs[0])
    nt.links.new(C._ramp(nt, 0.45, 0.6, area.outputs["Fac"]), chip.inputs[1])
    mask = chip.outputs[0]
    for name, val in (("Base Color", (0.32, 0.32, 0.33)), ("Roughness", 0.34)):
        sock = bsdf.inputs[name]
        src = sock.links[0].from_socket
        mixed = C._mix_color(nt, mask, src, val) if name == "Base Color" else C._mix_float(nt, mask, src, val)
        nt.links.new(mixed, sock)
    metal = nt.nodes.new("ShaderNodeMath")
    metal.operation = "MAXIMUM"
    nt.links.new(bsdf.inputs["Metallic"].links[0].from_socket, metal.inputs[0])
    nt.links.new(mask, metal.inputs[1])
    nt.links.new(metal.outputs[0], bsdf.inputs["Metallic"])


def mat_grip_rubber(name: str = "Rubber_Grip", color=(0.022, 0.021, 0.02)) -> bpy.types.Material:
    """Rubberized grip: dull, slightly blotchy (hand wear polishes it), fine stipple in the bump."""
    mat, nt, bsdf = C._new_material(name)
    blotch = C._noise(nt, 14.0, 4.0, 0.55)
    nt.links.new(C._mix_color(nt, blotch.outputs["Fac"], tuple(c * 0.8 for c in color), tuple(c * 1.5 for c in color)), bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, blotch.outputs["Fac"], 0.62, 0.9), bsdf.inputs["Roughness"])
    stipple = C._noise(nt, 900.0, 2.0, 0.5)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.0005
    nt.links.new(stipple.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_materials() -> None:
    global PAINT, GUNMETAL, STEEL, RUBBER, BODY_MATS, CYAN, CELL
    PAINT = C.mat_painted_metal("Paint_Light", (0.25, 0.25, 0.235), wear=0.8, grime=0.3, roughness=0.5)
    GUNMETAL = C.mat_painted_metal("Gunmetal", (0.045, 0.047, 0.05), wear=0.5, grime=0.3, roughness=0.45)
    STEEL = C.mat_bare_metal("BareMetal", (0.4, 0.4, 0.41), 0.32)
    RUBBER = mat_grip_rubber()
    for m in (PAINT, GUNMETAL):
        rescale(m, 3.0, 0.035)
        bevel_wear(m)
    add_chips(PAINT, 0.9)
    add_chips(GUNMETAL, 0.4)
    rescale(STEEL, 3.0, 0.035)
    BODY_MATS = [PAINT, GUNMETAL, STEEL, RUBBER]
    CYAN = C.mat_emissive("AmmoCounter", (0.02, 0.7, 1.0), 4.0)
    CELL = C.mat_emissive("EnergyCell", (0.03, 0.42, 1.0), 3.0)


M_PAINT, M_DARK, M_STEEL, M_RUBBER = 0, 1, 2, 3


# --- parts ------------------------------------------------------------------------------------------


def counter_frame(s: int) -> tuple[Matrix, Vector, Vector]:
    """Rotation, center and outward normal of the counter housing on the right (s=1) or left (s=-1) top edge."""
    rot = ry(-COUNTER_TILT * s)
    center = Vector((s * (UPPER_W / 2 - 0.003), (COUNTER_Y[0] + COUNTER_Y[1]) / 2, UPPER_Z[1] - 0.014))
    return rot, center, rot @ Vector((s, 0, 0))


def build_receiver(body: Part) -> None:
    """Upper receiver (light paint, panel lines), lower receiver (dark), top rail, sights, side details."""
    y0, y1 = UPPER_Y
    z0, z1 = UPPER_Z
    upper = body.side_prism(
        [(y0, z0), (y1, z0), (y1, z1 - 0.014), (y1 - 0.016, z1), (y0 + 0.03, z1), (y0, z1 - 0.024)], UPPER_W, mi=M_PAINT
    )
    inset_faces(body, upper, Vector((1, 0, 0)), 0.006, -0.0015, min_area=0.004)
    body.side_prism(
        [(-0.06, 0.052), (0.2, 0.052), (0.21, 0.07), (0.21, z0 + 0.004), (-0.08, z0 + 0.004), (-0.088, 0.075)], LOWER_W, mi=M_DARK
    )
    # Front end cap where shroud and emitter tube leave the receiver.
    body.box((0, y1 + 0.006, (TUBE_Z + z1) / 2 - 0.004), (UPPER_W - 0.008, 0.016, z1 - TUBE_Z + 0.02), mi=M_DARK)

    body.detail = True
    # Top rail with cross slots, rear and front sights.
    rail_y0, rail_y1 = -0.07, 0.215
    body.box((0, (rail_y0 + rail_y1) / 2, z1 + 0.004), (0.026, rail_y1 - rail_y0, 0.008), mi=M_DARK)
    n = 11
    for i in range(n):
        y = rail_y0 + 0.013 + i * (rail_y1 - rail_y0 - 0.026) / (n - 1)
        body.box((0, y, z1 + 0.011), (0.03, 0.011, 0.007), mi=M_DARK)
    body.box((0, -0.065, z1 + 0.02), (0.034, 0.026, 0.024), mi=M_DARK)  # rear sight block
    for s in (-1, 1):
        body.box((s * 0.011, -0.065, z1 + 0.038), (0.009, 0.018, 0.016), mi=M_DARK)

    # Ammo counter housings on both top edges (the glowing segments are their own mesh).
    for s in (-1, 1):
        rot, center, _n = counter_frame(s)
        housing = body.box(center, (0.014, COUNTER_Y[1] - COUNTER_Y[0] + 0.02, COUNTER_H), rot=rot, mi=M_DARK)
        inset_faces(body, housing, rot @ Vector((1, 0, 0)), 0.003, -0.0015)
    # Right side: ejection port cover and bolts; left side: charging handle.
    xr = UPPER_W / 2
    body.box((xr + 0.002, 0.19, 0.152), (0.006, 0.05, 0.026), mi=M_STEEL)
    body.box((xr + 0.004, 0.19, 0.152), (0.004, 0.036, 0.014), mi=M_DARK)
    for s in (-1, 1):
        for y, z in ((-0.09, 0.128), (-0.035, 0.128), (0.205, 0.124), (-0.06, 0.07), (0.17, 0.07)):
            w = UPPER_W if z > z0 else LOWER_W
            body.xcyl((s * (w / 2 + 0.002), y, z), 0.0055, 0.006, 8, mi=M_STEEL)
    body.box((-xr - 0.006, -0.06, 0.168), (0.012, 0.026, 0.016), mi=M_DARK)
    body.xcyl((-xr - 0.018, -0.06, 0.168), 0.009, 0.014, 10, mi=M_STEEL)
    # Fire selector on the right above the grip.
    body.xcyl((LOWER_W / 2 + 0.003, -0.02, 0.09), 0.011, 0.006, 12, mi=M_DARK)
    body.box((LOWER_W / 2 + 0.007, -0.012, 0.096), (0.004, 0.022, 0.006), rot=rx(30), mi=M_STEEL)
    body.detail = False


def build_grip(body: Part) -> None:
    """Rubber pistol grip with finger ridges, trigger guard and trigger."""
    pts = [
        (-0.025, 0.075),
        (-0.027, 0.02),
        (-0.03, -0.04),
        (-0.028, -0.072),
        (-0.034, -0.088),
        (0.03, -0.088),
        (0.026, -0.074),
        (0.023, -0.055),
        (0.028, -0.04),
        (0.023, -0.024),
        (0.028, -0.008),
        (0.023, 0.008),
        (0.027, 0.026),
        (0.025, 0.075),
    ]
    rot = rx(GRIP_TILT)
    body.side_prism(pts, 0.036, rot=rot, mi=M_RUBBER)
    body.side_prism([(-0.036, -0.085), (0.034, -0.085), (0.036, -0.097), (-0.038, -0.097)], 0.04, rot=rot, mi=M_DARK)  # base cap
    side = Vector((1, 0, 0))
    a, b, c = Vector((0, 0.022, 0.012)), Vector((0, 0.1, 0.012)), Vector((0, 0.112, 0.056))
    body.beam(a, b, 0.014, 0.009, side, M_DARK)
    body.beam(b + Vector((0, -0.004, -0.002)), c, 0.014, 0.009, side, M_DARK)
    body.detail = True
    body.box((0, 0.052, 0.036), (0.008, 0.009, 0.03), rot=rx(-18), mi=M_STEEL)
    body.detail = False


def build_cell_housing(body: Part) -> None:
    """Magazine well holding the energy cell: dark casing, bezels for the glowing windows, base plate."""
    R = rx(CELL_TILT)
    sx, sy, sz = CELL_SIZE
    center = CELL_PIVOT + R @ Vector((0, 0, -sz / 2))
    body.box(center, CELL_SIZE, rot=R, mi=M_DARK)
    body.box(CELL_PIVOT + R @ Vector((0, 0, -sz - 0.006)), (sx + 0.008, sy + 0.008, 0.014), rot=R, mi=M_PAINT)
    for s in (-1, 1):
        body.box(center + R @ Vector((s * (sx / 2 + 0.002), 0, -0.006)), (0.004, sy - 0.014, sz - 0.03), rot=R, mi=M_STEEL)
    # Release latch at the front.
    body.detail = True
    body.box(CELL_PIVOT + R @ Vector((0, sy / 2 + 0.005, -0.02)), (0.02, 0.01, 0.022), rot=R, mi=M_STEEL)
    body.detail = False


def build_barrel(body: Part) -> None:
    """Octagonal shroud over the barrel, muzzle brake, emitter tube with a ribbed rubber sleeve underneath."""
    shroud = body.ycyl(SHROUD_Y[0], SHROUD_Y[1], SHROUD_R, BORE_Z, 8, M_DARK, spin=22.5, scale=(1.08, 1, 1))
    for f in ring_faces(body, shroud, Vector((0, 1, 0)), 0.006, -0.002):
        f.material_index = M_PAINT
    body.ycyl(SHROUD_Y[1] - 0.012, SHROUD_Y[1] + 0.006, SHROUD_R + 0.003, BORE_Z, 8, M_PAINT, spin=22.5)
    body.detail = True
    # Heat vents on the shroud top.
    apo = SHROUD_R * math.cos(math.pi / 8)
    for i in range(4):
        body.box((0, 0.265 + i * 0.042, BORE_Z + apo + 0.002), (0.026, 0.026, 0.004), mi=M_STEEL)
    body.ycyl(SHROUD_Y[1], BARREL_END, 0.0155, BORE_Z, 12, M_STEEL)
    # Muzzle brake with side ports.
    body.ycyl(BARREL_END - 0.008, MUZZLE_Y - 0.008, 0.025, BORE_Z, 8, M_DARK, spin=22.5)
    body.ycyl(MUZZLE_Y - 0.008, MUZZLE_Y, 0.022, BORE_Z, 8, M_PAINT, r2=0.02, spin=22.5)
    for k in range(2):
        y = BARREL_END + 0.007 + k * 0.016
        for s in (-1, 1):
            body.box((s * 0.022, y, BORE_Z), (0.008, 0.008, 0.026), mi=M_STEEL)
    body.ycyl(MUZZLE_Y - 0.004, MUZZLE_Y + 0.001, 0.012, BORE_Z, 10, M_RUBBER)  # dark bore
    # Front sight on the shroud.
    top = BORE_Z + apo
    body.box((0, 0.435, top + 0.006), (0.024, 0.024, 0.012), mi=M_DARK)
    body.box((0, 0.437, top + 0.024), (0.005, 0.007, 0.026), mi=M_DARK)
    for s in (-1, 1):
        body.box((s * 0.011, 0.435, top + 0.022), (0.004, 0.018, 0.024), mi=M_DARK)
    body.detail = False
    # Emitter tube and its ribbed sleeve (support hand), clamped to the shroud at the front.
    body.ycyl(TUBE_Y[0], TUBE_Y[1], 0.021, TUBE_Z, 12, M_DARK)
    body.ycyl(TUBE_Y[1] - 0.004, TUBE_Y[1] + 0.012, 0.024, TUBE_Z, 12, M_STEEL, r2=0.018)
    body.ycyl(0.25, 0.262, 0.031, TUBE_Z, 12, M_STEEL)
    body.ycyl(0.438, 0.45, 0.031, TUBE_Z, 12, M_STEEL)
    body.detail = True
    n = 8
    for i in range(n):
        y = 0.268 + i * 0.0215
        body.ycyl(y, y + 0.015, 0.031, TUBE_Z, 10, M_RUBBER)
    body.ycyl(0.262, 0.438, 0.026, TUBE_Z, 10, M_RUBBER, caps=False)
    body.detail = False
    body.box((0, 0.472, (TUBE_Z + BORE_Z) / 2), (0.03, 0.026, BORE_Z - TUBE_Z), mi=M_PAINT)


def build_stock(body: Part) -> None:
    """Buffer tube and a skeleton stock with a rubber butt pad and cheek riser."""
    body.ycyl(-0.24, UPPER_Y[0] + 0.004, 0.019, 0.142, 12, M_DARK)
    side = Vector((1, 0, 0))
    yb = STOCK_Y + 0.02
    body.beam((0, UPPER_Y[0] + 0.01, 0.17), (0, yb, 0.164), 0.042, 0.038, side, M_PAINT)
    body.beam((0, -0.072, 0.07), (0, yb, 0.026), 0.034, 0.026, side, M_PAINT)
    body.side_prism([(yb - 0.018, 0.0), (yb + 0.022, 0.012), (yb + 0.02, 0.19), (yb - 0.018, 0.2)], 0.046, mi=M_PAINT)
    body.side_prism([(STOCK_Y - 0.006, -0.004), (STOCK_Y + 0.004, -0.002), (STOCK_Y + 0.004, 0.204), (STOCK_Y - 0.006, 0.206)], 0.052, mi=M_RUBBER)
    body.box((0, -0.2, 0.19), (0.036, 0.1, 0.016), mi=M_RUBBER)
    body.box((0, -0.215, 0.135), (0.044, 0.03, 0.024), mi=M_DARK)  # stock lock on the buffer tube
    body.detail = True
    for y in (-0.165, -0.235):
        body.xcyl((0, y, 0.165), 0.007, 0.046, 8, mi=M_STEEL)
    body.detail = False


def build_counter(gun) -> None:
    """Glowing ammo counter: segments on both sides; UV.x per segment from 0 (rear) to 1 (front)."""
    part = Part("AmmoCounter", [CYAN], bevel=None)
    uv = part.bm.loops.layers.uv.new("UVMap")
    y0, y1 = COUNTER_Y
    pitch = (y1 - y0) / COUNTER_SEGMENTS
    for s in (-1, 1):
        rot, center, n = counter_frame(s)
        for i in range(COUNTER_SEGMENTS):
            p = center + n * 0.0065 + Vector((0, y0 + (i + 0.5) * pitch - center.y, 0))
            verts = part.box(p, (0.003, pitch - 0.005, COUNTER_H - 0.016), rot=rot)
            u = (i + 0.5) / COUNTER_SEGMENTS
            for f in {f for v in verts for f in v.link_faces}:
                for lp in f.loops:
                    lp[uv].uv = (u, 0.5)
    part.finish(gun)


def build_cell(gun) -> None:
    """Glowing charge bars of the power cell on both sides of the magazine well, plus a strip at the front."""
    part = Part("EnergyCell", [CELL], bevel=None)
    R = rx(CELL_TILT)
    sx, sy, sz = CELL_SIZE
    center = CELL_PIVOT + R @ Vector((0, 0, -sz / 2 - 0.006))
    for s in (-1, 1):
        for dz in (-0.02, 0.0, 0.02):
            part.box(center + R @ Vector((s * (sx / 2 + 0.0045), 0, dz)), (0.003, sy - 0.03, 0.014), rot=R)
    part.box(CELL_PIVOT + R @ Vector((0, sy / 2 + 0.001, -sz + 0.02)), (sx - 0.02, 0.003, 0.012), rot=R)
    part.finish(gun)


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    gun = C.asset_root(ASSET)
    body = Part("Body", BODY_MATS)
    build_receiver(body)
    build_grip(body)
    build_cell_housing(body)
    build_barrel(body)
    build_stock(body)
    body.finish(gun)
    build_counter(gun)
    build_cell(gun)
    C.empty("Muzzle", (0, MUZZLE_Y, BORE_Z), gun)
    C.empty("Grip", (0, 0, 0), gun)
    C.empty("Foregrip", (0, FOREGRIP_Y, TUBE_Z), gun)
    for name in ("Muzzle", "Grip", "Foregrip"):
        bpy.data.objects[name].empty_display_size = 0.05
    return gun


def per_object_tris() -> dict:
    dg = bpy.context.evaluated_depsgraph_get()
    rows = {}
    for obj in C.collection(ASSET).all_objects:
        if obj.type == "MESH":
            me = obj.evaluated_get(dg).to_mesh()
            me.calc_loop_triangles()
            rows[obj.name] = len(me.loop_triangles)
            obj.evaluated_get(dg).to_mesh_clear()
    print("STATS per object", rows)
    return rows


CENTER = (0.0, 0.14, HOLD_Z + 0.07)  # middle of the gun while it is lifted for previews
# Own cameras (location relative to CENTER, lens): side profile, top-down, and a close look at the right side.
CUSTOM_VIEWS = {
    "side": ((2.4, 0.0, 0.0), 60),
    "top": ((0.6, -0.4, 2.4), 60),
    "right": ((1.1, 0.75, 0.55), 45),
    "close": ((0.42, -0.36, 0.22), 40),
}


def set_figure(visible: bool) -> None:
    fig = bpy.data.objects["PreviewFigure"]
    for child in fig.children:
        child.hide_render = not visible


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    gun = bpy.data.objects[ASSET]
    gun.location = (0, 0, HOLD_Z)
    set_figure(view in ("scale", "game"))
    if view in ("iso", "hero", "back"):
        C.render(path, view=view, samples=samples, size=size, target=CENTER, zoom=0.2 if view == "iso" else 0.18)
    elif view == "scale":
        C.render(path, view="iso", samples=samples, size=size, target=(-0.2, -0.2, 1.0), zoom=0.32)
    elif view == "game":  # roughly the game camera's distance
        C.render(path, view="iso", samples=samples, size=size, target=(-0.2, -0.2, 1.0), zoom=1.0)
    else:
        offset, lens = CUSTOM_VIEWS[view]
        C.render(path, view="hero", samples=1, size=16)  # applies common's render settings and creates "Cam"
        cam = bpy.context.scene.camera
        cam.data.lens = lens
        cam.location = Vector(CENTER) + Vector(offset)
        cam.rotation_euler = (Vector(CENTER) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene = bpy.context.scene
        scene.cycles.samples = samples
        scene.render.resolution_x = scene.render.resolution_y = size
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
    gun.location = (0, 0, 0)


FINAL_VIEWS = ["iso", "hero", "back", "side", "top", "scale"]


def contact_sheet() -> None:
    """Tile the final renders (2 rows of 3) into sheet.png with Blender's image API (no Pillow needed)."""
    import numpy as np

    tile = 512
    cols, rows = 3, 2
    sheet = np.zeros((rows * tile, cols * tile, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, view in enumerate(FINAL_VIEWS):
        img = bpy.data.images.load(str(OUT / f"render_{view}.png"))
        img.scale(tile, tile)
        px = np.empty(tile * tile * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * tile  # Blender images start at the bottom row
        sheet[y0 : y0 + tile, c * tile : (c + 1) * tile] = px.reshape(tile, tile, 4)
    out = bpy.data.images.new("sheet", cols * tile, rows * tile, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = str(OUT / "sheet.png")
    out.file_format = "PNG"
    out.save()
    print("SHEET", OUT / "sheet.png")


def main() -> None:
    if MODE == "sheet":
        contact_sheet()
        return
    C.reset(ASSET)
    make_materials()
    build()
    per_object_tris()
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(-0.35, -0.45, 0.0))
    if MODE == "final":
        for view in FINAL_VIEWS:
            render_view(OUT / f"render_{view}.png", view, samples=64, size=1024)
        C.save_blend(OUT / "blaster_procedural.blend")
    else:
        for view in VIEWS:
            if view != "none":
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, samples=32, size=768 if view == "close" else 640)


main()
