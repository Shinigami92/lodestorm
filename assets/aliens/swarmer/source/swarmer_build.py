"""Swarmer: a lean, dog-sized alien runner on four clawed legs with a long toothed jaw and two scythe-like bone
blades rising from its back (concept: swarmer_v1..v4), rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/swarmer/source/swarmer_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/swarmer/source/swarmer_build.py final      # renders + swarmer_procedural.blend

Everything it writes goes to tmp/assets/swarmer/; swarmer_bake.py turns swarmer_procedural.blend into the game asset.

Layout (Blender Z-up meters; the swarmer faces -Y, its left is +X; glTF turns -Y into Godot's +Z, so the game turns
the model by 180 degrees to face the alien's -Z). Feet on the ground at the origin, the origin under the middle of
the body; back 0.72 m high, the blades reach 1.5 m, nose to rump 1.5 m plus a 0.9 m tail.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the pelvis) with the tail
(Tail1..3) and the hind legs, Spine, Chest with the front legs and the blades (<Side>Scythe, <Side>ScytheBlade),
Neck, Head, Jaw. Legs (<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (two bones reaching
the ankle = the Foot bone's head, the Foot keeps its angle to the body), so the clips leave them at rest; only "Die"
folds them. Front elbows bend back, hind knees forward (digitigrade hind legs: the Foot is the long metatarsal).
Meshes: "Creature" (one skinned object, organic parts weighted to the nearest bones, chitin plates, teeth, claws and
blades rigid) and "Eyes" (constant emissive; the game shows the facing with them).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop), "Run" (loop, the body's motion
while running: spine flex, head low, tail streaming; the legs come from the game), "Attack" (once: rears back, then
snaps forward with the jaw open and the blades striking) and "Die" (once: legs buckle, it falls on its side).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "swarmer"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import itertools

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import common as C
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Swarmer"
FPS = 30
I3 = Matrix.Identity(3)
SIDES = (("Left", 1.0), ("Right", -1.0))
UP = Vector((0, 0, 1))

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.66))
PELVIS = Vector((0, 0.44, 0.66))
WITHERS = Vector((0, -0.42, 0.7))
SKULL = Vector((0, -0.6, 0.72))
JAW_PIVOT = Vector((0, -0.63, 0.665))
SNOUT = Vector((0, -1.02, 0.64))
TAIL = [PELVIS, Vector((0, 0.76, 0.69)), Vector((0, 1.05, 0.77)), Vector((0, 1.32, 0.9))]
# Leg joints per side (x for the left side): hip/shoulder, knee/elbow, ankle, ball of the foot, toe tips.
FRONT = [
    Vector((0.13, -0.26, 0.6)),
    Vector((0.145, -0.15, 0.36)),
    Vector((0.14, -0.27, 0.11)),
    Vector((0.14, -0.33, 0.035)),
    Vector((0.14, -0.42, 0.0)),
]
HIND = [
    Vector((0.125, 0.42, 0.6)),
    Vector((0.145, 0.22, 0.39)),
    Vector((0.14, 0.5, 0.2)),
    Vector((0.14, 0.42, 0.035)),
    Vector((0.14, 0.32, 0.0)),
]
SCYTHE = [Vector((0.1, -0.18, 0.8)), Vector((0.19, 0.2, 1.1)), Vector((0.24, -0.3, 1.42))]


def mirror(v: Vector, s: float) -> Vector:
    return Vector((v.x * s, v.y, v.z))


BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, Vector((0, -0.2, 0.67)), "Body"),
    ("Chest", Vector((0, -0.2, 0.67)), WITHERS, "Spine"),
    ("Neck", WITHERS, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -1.0, 0.585)), "Head"),
    ("Tail1", TAIL[0], TAIL[1], "Hips"),
    ("Tail2", TAIL[1], TAIL[2], "Tail1"),
    ("Tail3", TAIL[2], TAIL[3], "Tail2"),
]
for _side, _s in SIDES:
    BONES += [
        (f"{_side}Scythe", mirror(SCYTHE[0], _s), mirror(SCYTHE[1], _s), "Chest"),
        (f"{_side}ScytheBlade", mirror(SCYTHE[1], _s), mirror(SCYTHE[2], _s), f"{_side}Scythe"),
    ]
    for _leg, _pts, _parent in (("Front", FRONT, "Chest"), ("Hind", HIND, "Hips")):
        BONES += [
            (f"{_leg}{_side}UpperLeg", mirror(_pts[0], _s), mirror(_pts[1], _s), _parent),
            (f"{_leg}{_side}LowerLeg", mirror(_pts[1], _s), mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", mirror(_pts[2], _s), mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
HEAD = {n: Vector(h) for n, h, _t, _p in BONES}
TAILPOS = {n: Vector(t) for n, _h, t, _p in BONES}
PARENT = {n: p for n, _h, _t, p in BONES}
BONE_INDEX = {n: i for i, (n, *_r) in enumerate(BONES)}


def build_skeleton(root: bpy.types.Object) -> bpy.types.Object:
    data = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", data)
    C.link(arm, root)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        eb.roll = 0.0
        if parent:
            eb.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    data.display_type = "STICK"
    return arm


# --- mesh -------------------------------------------------------------------------------------------


def seg_dist(p: Vector, a: Vector, b: Vector) -> float:
    d = b - a
    t = min(max((p - a).dot(d) / max(d.length_squared, 1e-9), 0.0), 1.0)
    return (p - (a + d * t)).length


def catmull(table: list, t: float) -> list:
    """Smooth interpolation through the rows of `table` (lists of floats) at t in 0..1 (Catmull-Rom)."""
    n = len(table) - 1
    x = min(max(t, 0.0), 1.0) * n
    i = min(int(x), n - 1)
    u = x - i
    p0, p1, p2, p3 = table[max(i - 1, 0)], table[i], table[i + 1], table[min(i + 2, n)]
    return [
        0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (-a + 3 * b - 3 * c + d) * u * u * u)
        for a, b, c, d in zip(p0, p1, p2, p3)
    ]


def path_point(pts: list, t: float) -> Vector:
    return Vector(catmull([list(p) for p in pts], t))


class Skin(C.Part):
    """Organic part builder with vertex weights: rigid(verts, bone) or auto(verts, bones) (the two nearest of
    `bones` by distance to their segments, blended smoothly)."""

    def __init__(self, name: str, mats: list):
        super().__init__(name, mats, None)
        self.dl = self.bm.verts.layers.deform.verify()

    def rigid(self, verts, bone: str):
        for v in verts:
            v[self.dl].clear()
            v[self.dl][BONE_INDEX[bone]] = 1.0
        return verts

    def auto(self, verts, bones: list, power: float = 4.0):
        for v in verts:
            ds = sorted((max(seg_dist(v.co, HEAD[b], TAILPOS[b]), 1e-4), b) for b in bones)[:2]
            w = [1.0 / d**power for d, _b in ds]
            total = sum(w)
            v[self.dl].clear()
            for (_d, b), wi in zip(ds, w):
                v[self.dl][BONE_INDEX[b]] = wi / total
        return verts

    def loft(self, rings: list, mi: int = 0, caps: bool = True):
        """Closed tube through rings of points (same count each); caps close the ends."""
        loops = [[self.bm.verts.new(p) for p in ring] for ring in rings]
        n = len(loops[0])
        faces = []
        for a, b in itertools.pairwise(loops):
            for k in range(n):
                faces.append(self.bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k])))
        if caps:
            faces.append(self.bm.faces.new(list(reversed(loops[0]))))
            faces.append(self.bm.faces.new(loops[-1]))
        for f in faces:
            f.normal_update()
        return self._tag([v for lp in loops for v in lp], mi)

    def cone(self, base: Vector, tip: Vector, r: float, seg: int = 5, mi: int = 0, flat: float = 1.0):
        """Pointed cone (teeth, claws, spikes); flat squashes it sideways."""
        d = tip - base
        m = C.basis(d, Vector((1, 0, 0)) if abs(d.normalized().x) < 0.9 else Vector((0, 1, 0)))
        ring = [
            self.bm.verts.new(base + m @ Vector((math.cos(a) * r, math.sin(a) * r * flat, 0)))
            for a in (math.tau * k / seg for k in range(seg))
        ]
        top = self.bm.verts.new(tip)
        faces = [self.bm.faces.new((ring[k], ring[(k + 1) % seg], top)) for k in range(seg)]
        faces.append(self.bm.faces.new(list(reversed(ring))))
        for f in faces:
            f.normal_update()
        return self._tag(ring + [top], mi)

    def finish(self, parent) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        obj = super().finish(parent)
        for name, *_r in BONES:
            obj.vertex_groups.new(name=name)
        return obj


def frame_at(d: Vector, up: Vector = UP) -> tuple:
    """Side and up axes of a cross-section perpendicular to d."""
    d = d.normalized()
    side = d.cross(up)
    if side.length < 1e-4:
        side = d.cross(Vector((0, 1, 0)))
    side.normalize()
    return side, side.cross(d).normalized() * (1 if side.cross(d).z >= 0 else -1)


def section(
    c: Vector,
    d: Vector,
    w: float,
    top: float,
    bot: float,
    seg: int,
    wobble: float = 0.0,
    seed: float = 0.0,
    up=UP,
) -> list:
    """Cross-section around c (perpendicular to d): half-width w, top above, bot below; slightly squared."""
    side, upv = frame_at(d, up)
    pts = []
    for k in range(seg):
        a = math.tau * k / seg
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** 0.85, ca) * w
        y = math.copysign(abs(sa) ** 0.9, sa) * (top if sa > 0 else bot)
        p = c + side * x + upv * y
        if wobble:
            p += (p - c).normalized() * wobble * noise.noise(p * 9.0 + Vector((seed, seed, seed)))
        pts.append(p)
    return pts


def tube_path(
    sk: Skin,
    pts: list,
    radii: list,
    seg: int,
    rings: int,
    mi: int,
    flat: float = 1.0,
    wobble: float = 0.0,
    up=UP,
):
    """Tube along a smooth path through pts with radii interpolated along it; flat squashes it vertically."""
    out = []
    for i in range(rings + 1):
        t = i / rings
        c = path_point(pts, t)
        d = path_point(pts, min(t + 0.02, 1.0)) - path_point(pts, max(t - 0.02, 0.0))
        r = catmull([[x] for x in radii], t)[0]
        out.append(section(c, d, r, r * flat, r * flat, seg, wobble, i * 1.7, up))
    return sk.loft(out, mi)


# Body profile along the spine, from the rump forward: y, center z, half-width, top, bottom.
TRUNK = [
    (0.62, 0.64, 0.06, 0.06, 0.06),
    (0.54, 0.665, 0.13, 0.09, 0.11),
    (0.4, 0.68, 0.155, 0.1, 0.14),
    (0.25, 0.67, 0.14, 0.095, 0.12),
    (0.08, 0.66, 0.12, 0.085, 0.11),
    (-0.08, 0.665, 0.15, 0.1, 0.19),
    (-0.22, 0.67, 0.175, 0.11, 0.245),
    (-0.34, 0.685, 0.16, 0.105, 0.2),
    (-0.44, 0.705, 0.115, 0.09, 0.11),
    (-0.54, 0.715, 0.085, 0.07, 0.075),
    (-0.6, 0.72, 0.08, 0.065, 0.07),
]
# Skull from the back of the head to the snout: y, center z, half-width, top, bottom.
SKULL_PROFILE = [
    (-0.55, 0.735, 0.05, 0.04, 0.03),
    (-0.6, 0.74, 0.075, 0.065, 0.035),
    (-0.68, 0.735, 0.085, 0.07, 0.04),
    (-0.78, 0.715, 0.068, 0.05, 0.035),
    (-0.88, 0.69, 0.052, 0.04, 0.03),
    (-0.97, 0.665, 0.04, 0.032, 0.025),
    (-1.03, 0.65, 0.022, 0.02, 0.016),
]
JAW_PROFILE = [
    (-0.6, 0.66, 0.055, 0.012, 0.03),
    (-0.7, 0.648, 0.06, 0.012, 0.035),
    (-0.82, 0.632, 0.048, 0.01, 0.03),
    (-0.93, 0.615, 0.036, 0.01, 0.024),
    (-1.0, 0.603, 0.02, 0.008, 0.014),
]


def trunk(t: float) -> tuple:
    y, z, w, top, bot = catmull([list(r) for r in TRUNK], t)
    return Vector((0, y, z)), w, top, bot


def trunk_surface(y: float, a: float, out: float = 0.0) -> Vector:
    """Point on the trunk's surface at y and angle a (0 = left side, 90 = top), pushed out by `out`."""
    t = (TRUNK[0][0] - y) / (TRUNK[0][0] - TRUNK[-1][0])
    c, w, top, bot = trunk(t)
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    x = math.copysign(abs(ca) ** 0.85, ca) * (w + out)
    z = math.copysign(abs(sa) ** 0.9, sa) * ((top if sa > 0 else bot) + out)
    return c + Vector((x, 0, z))


def shell(
    sk: Skin,
    y0: float,
    y1: float,
    a0: float,
    a1: float,
    out: float,
    thick: float,
    mi: int,
    nu: int = 6,
    nv: int = 3,
    lift: float = 0.0,
):
    """Curved plate hugging the trunk between y0..y1 and angles a0..a1; its rear edge lifts off like a scale."""
    top_rows, bot_rows = [], []
    for i in range(nv + 1):
        v = i / nv
        y = y0 + (y1 - y0) * v
        bulge = math.sin(math.pi * v) * 0.6 + 0.4
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            a = a0 + (a1 - a0) * u
            edge = math.sin(math.pi * u) ** 0.5
            o = out + lift * v * edge
            row_t.append(sk.bm.verts.new(trunk_surface(y, a, o + thick * bulge * edge)))
            row_b.append(sk.bm.verts.new(trunk_surface(y, a, o)))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return _close_grid(sk, top_rows, bot_rows, mi)


def _close_grid(sk: Skin, top_rows: list, bot_rows: list, mi: int):
    faces = []
    nv, nu = len(top_rows) - 1, len(top_rows[0]) - 1
    for i in range(nv):
        for k in range(nu):
            faces.append(
                sk.bm.faces.new((top_rows[i][k], top_rows[i][k + 1], top_rows[i + 1][k + 1], top_rows[i + 1][k]))
            )
            faces.append(
                sk.bm.faces.new((bot_rows[i][k], bot_rows[i + 1][k], bot_rows[i + 1][k + 1], bot_rows[i][k + 1]))
            )
    rim_t = (
        [r[0] for r in top_rows]
        + top_rows[-1][1:]
        + list(reversed([r[-1] for r in top_rows]))[1:]
        + list(reversed(top_rows[0]))[1:-1]
    )
    rim_b = (
        [r[0] for r in bot_rows]
        + bot_rows[-1][1:]
        + list(reversed([r[-1] for r in bot_rows]))[1:]
        + list(reversed(bot_rows[0]))[1:-1]
    )
    for k in range(len(rim_t)):
        k2 = (k + 1) % len(rim_t)
        faces.append(sk.bm.faces.new((rim_t[k], rim_b[k], rim_b[k2], rim_t[k2])))
    for f in faces:
        f.normal_update()
    verts = [v for r in top_rows + bot_rows for v in r]
    return sk._tag(verts, mi)


def limb_plate(sk: Skin, a: Vector, b: Vector, r: float, a0: float, a1: float, thick: float, mi: int, facing: Vector):
    """Curved plate wrapped around a limb segment a..b (radius r) on the side `facing` (angles a0..a1 around it)."""
    d = (b - a).normalized()
    side = facing - d * facing.dot(d)
    side.normalize()
    other = d.cross(side)
    top_rows, bot_rows = [], []
    for i in range(4):
        v = i / 3
        c = a.lerp(b, v)
        row_t, row_b = [], []
        for k in range(5):
            ang = math.radians(a0 + (a1 - a0) * k / 4)
            n = side * math.cos(ang) + other * math.sin(ang)
            bulge = thick * (0.5 + 0.5 * math.sin(math.pi * k / 4))
            row_t.append(sk.bm.verts.new(c + n * (r + bulge)))
            row_b.append(sk.bm.verts.new(c + n * r))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return _close_grid(sk, top_rows, bot_rows, mi)


# --- materials ---------------------------------------------------------------------------------------


def _coord(nt, out: str = "Object") -> bpy.types.NodeSocket:
    return nt.nodes.new("ShaderNodeTexCoord").outputs[out]


def _noise(nt, vec, scale: float, detail: float = 4.0, rough: float = 0.55, dist: float = 0.0) -> bpy.types.Node:
    return C._noise(nt, scale, detail, rough, vector=vec, distortion=dist)


def _cavity(nt, distance: float = 0.08, lo: float = 0.35, hi: float = 0.95) -> bpy.types.NodeSocket:
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = distance
    ao.samples = 16
    return C._math(nt, "SUBTRACT", 1.0, C._bw(nt, C._ramp(nt, lo, hi, ao.outputs["AO"])))


def _edges(nt, radius: float = 0.01, lo: float = 0.02, hi: float = 0.12) -> bpy.types.NodeSocket:
    return C._bw(nt, C._ramp(nt, lo, hi, C._bevel_edge(nt, radius)))


def mat_sinew() -> bpy.types.Material:
    """Sinewy hide between the plates: dark wine-red flesh with fine muscle striation, wet in the folds (the nest's
    flesh, tuned for a small creature)."""
    mat, nt, bsdf = C._new_material("Sinew")
    co = _coord(nt)
    big = _noise(nt, co, 4.0, 4.0, 0.5)
    col = C._mix_color(nt, big.outputs["Fac"], (0.075, 0.016, 0.014), (0.035, 0.01, 0.012))
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 28.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 2.0
    nt.links.new(co, wave.inputs["Vector"])
    stri = C._ramp(nt, 0.35, 0.75, wave.outputs["Fac"])
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", C._bw(nt, stri), 0.4), col, (0.018, 0.005, 0.007))
    veins = C._bw(nt, C._voronoi_lines(nt, co, 9.0, 0.035))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", veins, 0.6), col, (0.13, 0.03, 0.02))
    edge = _edges(nt, 0.01, 0.03, 0.2)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", edge, 0.3), col, (0.16, 0.06, 0.05))
    cav = _cavity(nt, 0.06)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.9), col, (0.01, 0.003, 0.004))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, big.outputs["Fac"], 0.25, 0.45)
    rough = C._mix_float(nt, cav, rough, 0.08)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    fine = _noise(nt, co, 60.0, 3.0, 0.6)
    h = C._math(nt, "ADD", C._math(nt, "MULTIPLY", C._bw(nt, stri), 0.5), C._math(nt, "MULTIPLY", veins, 0.5))
    h = C._math(nt, "ADD", h, C._math(nt, "MULTIPLY", fine.outputs["Fac"], 0.2))
    C._bump(nt, bsdf, h, 0.35, 0.004)
    return mat


def mat_chitin() -> bpy.types.Material:
    """Chitin plates: near-black shell with deep crimson in the growth bands, glossy, worn lighter at the edges."""
    mat, nt, bsdf = C._new_material("Chitin")
    co = _coord(nt)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Y"
    wave.inputs["Scale"].default_value = 18.0
    wave.inputs["Distortion"].default_value = 4.0
    wave.inputs["Detail"].default_value = 3.0
    nt.links.new(co, wave.inputs["Vector"])
    bands = C._bw(nt, C._ramp(nt, 0.3, 0.8, wave.outputs["Fac"]))
    big = _noise(nt, co, 5.0, 4.0, 0.5)
    shell = C._mix_color(nt, big.outputs["Fac"], (0.018, 0.009, 0.01), (0.06, 0.012, 0.016))
    shell = C._mix_color(nt, C._math(nt, "MULTIPLY", bands, 0.55), shell, (0.12, 0.018, 0.022))
    edge = _edges(nt, 0.006, 0.03, 0.16)
    breakup = _noise(nt, co, 25.0, 6.0, 0.6)
    worn = C._math(nt, "MULTIPLY", edge, C._bw(nt, C._ramp(nt, 0.35, 0.6, breakup.outputs["Fac"])))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", worn, 0.6), shell, (0.2, 0.09, 0.07))
    cav = _cavity(nt, 0.05)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.85), col, (0.006, 0.003, 0.003))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, big.outputs["Fac"], 0.16, 0.3)
    rough = C._mix_float(nt, worn, rough, 0.5)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Coat Weight"].default_value = 0.3
    fine = _noise(nt, co, 90.0, 3.0, 0.6)
    h = C._math(nt, "ADD", C._math(nt, "MULTIPLY", bands, 0.4), C._math(nt, "MULTIPLY", fine.outputs["Fac"], 0.2))
    C._bump(nt, bsdf, h, 0.3, 0.003)
    return mat


def mat_bone() -> bpy.types.Material:
    """Blades, teeth, claws and horns: yellowed bone, dark at the base, sharp edges pale."""
    mat, nt, bsdf = C._new_material("Bone")
    co = _coord(nt)
    streak = _noise(nt, co, 12.0, 6.0, 0.6, dist=1.5)
    col = C._mix_color(nt, streak.outputs["Fac"], (0.32, 0.25, 0.16), (0.5, 0.42, 0.3))
    cav = _cavity(nt, 0.04)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.85), col, (0.05, 0.03, 0.02))
    grime = _noise(nt, co, 4.0, 3.0, 0.5)
    col = C._mix_color(
        nt,
        C._math(nt, "MULTIPLY", C._bw(nt, C._ramp(nt, 0.5, 0.7, grime.outputs["Fac"])), 0.6),
        col,
        (0.08, 0.04, 0.03),
    )
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, streak.outputs["Fac"], 0.3, 0.5), bsdf.inputs["Roughness"])
    C._bump(nt, bsdf, streak.outputs["Fac"], 0.25, 0.003)
    return mat


def mat_mouth() -> bpy.types.Material:
    """Gums and the inside of the mouth: raw, glossy red."""
    mat, nt, bsdf = C._new_material("Mouth")
    co = _coord(nt)
    big = _noise(nt, co, 30.0, 3.0, 0.5)
    nt.links.new(
        C._mix_color(nt, big.outputs["Fac"], (0.16, 0.012, 0.012), (0.3, 0.04, 0.035)), bsdf.inputs["Base Color"]
    )
    bsdf.inputs["Roughness"].default_value = 0.15
    C._bump(nt, bsdf, big.outputs["Fac"], 0.3, 0.003)
    return mat


SINEW, CHITIN, BONE, MOUTH = range(4)
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: Skin) -> None:
    n = 22
    rings = []
    for i in range(n + 1):
        c, w, top, bot = trunk(i / n)
        rings.append(section(c, Vector((0, -1, 0)), w, top, bot, 18, 0.006, i * 0.9))
    sk.auto(sk.loft(rings, SINEW), ["Hips", "Spine", "Chest", "Neck"])
    # Ribs on the flanks: thin ridges curving down over the chest.
    for side, s in SIDES:
        for y in (-0.3, -0.24, -0.18, -0.12, -0.06, 0.0):
            pts = [trunk_surface(y + 0.012 * k, 25 - 24 * k if s > 0 else 155 + 24 * k, 0.004) for k in range(5)]
            sk.auto(tube_path(sk, pts, [0.012, 0.013, 0.012, 0.01, 0.006], 6, 6, SINEW), ["Spine", "Chest"])
    # Dorsal plates: overlapping shields from the neck to the rump, the rear edge of each lifting off.
    ys = [-0.6, -0.5, -0.4, -0.29, -0.18, -0.07, 0.04, 0.15, 0.26, 0.37, 0.48]
    for i, (y0, y1) in enumerate(itertools.pairwise(ys)):
        width = 38 + 14 * math.sin(math.pi * i / (len(ys) - 2))
        sk.auto(
            shell(sk, y0 - 0.02, y1 + 0.035, 90 - width, 90 + width, 0.006, 0.02, CHITIN, 6, 3, 0.015),
            ["Hips", "Spine", "Chest", "Neck"],
            8.0,
        )
    # Side plates over the ribs and the haunches.
    for side, s in SIDES:
        a0, a1 = (5, 40) if s > 0 else (140, 175)
        sk.auto(shell(sk, -0.32, -0.12, a0 - 30, a1 - 20, 0.012, 0.016, CHITIN, 5, 3, 0.012), ["Spine", "Chest"], 8.0)
        a0, a1 = (-30, 45) if s > 0 else (135, 210)
        sk.rigid(shell(sk, 0.3, 0.52, a0, a1, 0.008, 0.02, CHITIN, 6, 3, 0.01), "Hips")


def build_neck_head(sk: Skin, eyes: Skin) -> None:
    # Neck: from the withers into the back of the skull.
    pts = [Vector((0, -0.48, 0.705)), Vector((0, -0.54, 0.715)), Vector((0, -0.6, 0.72))]
    sk.auto(tube_path(sk, pts, [0.095, 0.08, 0.065], 14, 4, SINEW), ["Chest", "Neck", "Head"])
    # Skull (the underside is the roof of the mouth).
    rings = []
    n = 12
    for i in range(n + 1):
        y, z, w, top, bot = catmull([list(r) for r in SKULL_PROFILE], i / n)
        rings.append(section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 16, 0.003, 3 + i))
    verts = sk.rigid(sk.loft(rings, CHITIN), "Head")
    _mouth_faces(sk, verts, below=True)
    # Lower jaw.
    rings = []
    for i in range(9):
        y, z, w, top, bot = catmull([list(r) for r in JAW_PROFILE], i / 8)
        rings.append(section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 14, 0.002, 9 + i))
    verts = sk.rigid(sk.loft(rings, CHITIN), "Jaw")
    _mouth_faces(sk, verts, below=False)
    # Teeth along both jaws (longer fangs in front), bone colored.
    rnd = random.Random(7)
    for side, s in SIDES:
        for k in range(9):
            t = k / 8
            y = -0.66 - 0.33 * t
            _y, z, w, _top, bot = catmull([list(r) for r in SKULL_PROFILE], (-0.55 - y) / 0.48)
            length = 0.03 + 0.02 * (1 - abs(t - 0.75) * 2) + rnd.uniform(-0.005, 0.008)
            base = Vector((s * w * 0.8, y, z - bot * 0.75))
            sk.rigid(sk.cone(base, base + Vector((s * 0.004, -0.006, -length)), 0.008, 5, BONE), "Head")
            _y, zj, wj, topj, _b = catmull([list(r) for r in JAW_PROFILE], (-0.6 - y) / 0.4)
            if -1.0 < y < -0.62:
                base = Vector((s * wj * 0.8, y - 0.01, zj + topj * 0.5))
                sk.rigid(sk.cone(base, base + Vector((s * 0.003, -0.004, length * 0.8)), 0.007, 5, BONE), "Jaw")
    # Brow ridges over the eyes and two horns sweeping back from the skull.
    for side, s in SIDES:
        sk.rigid(
            sk.sphere((s * 0.06, -0.7, 0.78), 0.04, 10, 5, scale=(0.9, 2.0, 0.45), rot=ry(s * 25) @ rx(-8), mi=CHITIN),
            "Head",
        )
        horn = [Vector((s * 0.045, -0.6, 0.78)), Vector((s * 0.06, -0.52, 0.83)), Vector((s * 0.07, -0.42, 0.86))]
        sk.rigid(tube_path(sk, horn, [0.025, 0.016, 0.004], 6, 5, BONE), "Head")
        # Eyes: slanted glowing slits on the sides of the skull.
        eyes.rigid(
            eyes.sphere((s * 0.068, -0.735, 0.752), 0.022, 10, 5, scale=(0.5, 1.4, 0.6), rot=rz(s * 20) @ rx(-12)),
            "Head",
        )


def _mouth_faces(sk: Skin, verts: list, below: bool) -> None:
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        n = f.normal
        if ((n.z < -0.6) if below else (n.z > 0.6)) and f.calc_center_median().y < -0.62:
            f.material_index = MOUTH


def build_tail(sk: Skin) -> None:
    pts = TAIL + [Vector((0, 1.42, 0.98))]
    sk.auto(tube_path(sk, pts, [0.055, 0.04, 0.026, 0.014, 0.006], 10, 18, SINEW), ["Hips", "Tail1", "Tail2", "Tail3"])
    # Chitin rings along the tail and a spike at the tip.
    for k in range(10):
        t = 0.08 + 0.8 * k / 9
        c = path_point(pts, t)
        d = path_point(pts, t + 0.02) - path_point(pts, t - 0.02)
        r = catmull([[x] for x in [0.055, 0.04, 0.026, 0.014, 0.006]], t)[0]
        bone = "Tail1" if t < 0.33 else "Tail2" if t < 0.66 else "Tail3"
        rings = [
            section(c + d.normalized() * o, d, r + 0.006 + o * 0.15, r + 0.008, r + 0.002, 10) for o in (-0.012, 0.012)
        ]
        sk.rigid(sk.loft(rings, CHITIN), bone)
    end = path_point(pts, 1.0)
    sk.rigid(sk.cone(end - Vector((0, 0.03, 0.02)), end + Vector((0, 0.08, 0.03)), 0.012, 6, BONE), "Tail3")


def build_legs(sk: Skin) -> None:
    for leg, pts in (("Front", FRONT), ("Hind", HIND)):
        hind = leg == "Hind"
        for side, s in SIDES:
            j = [mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            body = "Hips" if hind else "Chest"
            # Upper leg: thick haunch / shoulder muscle, into the body.
            top = j[0] + Vector((s * -0.03, 0.0, 0.07))
            radii = [0.115, 0.12, 0.085, 0.055] if hind else [0.1, 0.095, 0.068, 0.048]
            mid = j[0].lerp(j[1], 0.45) + (Vector((0, 0.03, 0)) if hind else Vector((0, -0.02, 0)))
            sk.auto(tube_path(sk, [top, mid, j[1]], radii, 12, 6, SINEW, 1.0, 0.004), [body, up, low])
            # Lower leg: lean, a chitin greave on the front (hind: the shin points back).
            mid = j[1].lerp(j[2], 0.5)
            sk.auto(
                tube_path(sk, [j[1], mid, j[2]], [0.055, 0.04, 0.032] if hind else [0.052, 0.038, 0.032], 10, 6, SINEW),
                [up, low, foot],
            )
            facing = Vector((0, -1, 0.2)) if hind else Vector((0, 1, 0.1))
            sk.rigid(
                limb_plate(
                    sk,
                    j[1].lerp(j[2], 0.15),
                    j[1].lerp(j[2], 0.8),
                    0.04,
                    -70,
                    70,
                    0.014,
                    CHITIN,
                    -facing if hind else facing,
                ),
                low,
            )
            # Knee / elbow knob.
            sk.rigid(
                sk.sphere(j[1] + (Vector((0, -0.015, 0)) if hind else Vector((0, 0.02, 0))), 0.035, 10, 5, mi=CHITIN),
                low,
            )
            # Foot: metatarsal (hind: long) to the ball, then three long toes with hooked claws.
            sk.auto(tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.03, 0.027, 0.03], 8, 4, SINEW), [low, foot])
            sk.rigid(sk.sphere(j[3], 0.032, 10, 5, scale=(1.0, 1.2, 0.7), mi=SINEW), foot)
            for k, ang in enumerate((-22, 0, 22)):
                toe_dir = Vector((math.sin(math.radians(ang)) * s * -1, -1, 0)).normalized()
                knuckle = j[3] + toe_dir * 0.06 + Vector((0, 0, 0.012))
                tip = j[3] + toe_dir * (0.11 if k == 1 else 0.09) + Vector((0, 0, -0.025))
                sk.rigid(tube_path(sk, [j[3], knuckle, tip - toe_dir * 0.02], [0.016, 0.013, 0.01], 6, 4, SINEW), foot)
                sk.rigid(
                    sk.cone(
                        tip - toe_dir * 0.025 + Vector((0, 0, 0.012)), tip + Vector((0, 0, -0.012)), 0.009, 5, BONE
                    ),
                    foot,
                )
            # Dewclaw spur at the back of the ankle.
            back = Vector((0, 0.05, 0.03)) if not hind else Vector((0, 0.06, 0.02))
            sk.rigid(sk.cone(j[2] + Vector((0, 0.01, -0.02)), j[2] + back, 0.012, 5, BONE), low if hind else foot)


def build_scythes(sk: Skin) -> None:
    for side, s in SIDES:
        base, joint, _tip = (mirror(p, s) for p in SCYTHE)
        arm, blade = f"{side}Scythe", f"{side}ScytheBlade"
        # Mount: a knob of chitin on the shoulder.
        sk.auto(sk.sphere(base + Vector((0, 0, -0.02)), 0.055, 12, 6, scale=(1.0, 1.3, 0.8), mi=CHITIN), ["Chest", arm])
        # Arm: bony, knuckled, rising backward.
        mid = base.lerp(joint, 0.5) + Vector((s * 0.01, 0.02, 0))
        sk.rigid(tube_path(sk, [base, mid, joint], [0.045, 0.036, 0.042], 8, 6, BONE, 1.0, 0.003), arm)
        for t in (0.3, 0.65):
            sk.rigid(sk.sphere(base.lerp(joint, t), 0.046, 8, 4, scale=(1, 1, 0.7), mi=BONE), arm)
        sk.rigid(sk.sphere(joint, 0.06, 10, 5, mi=BONE), blade)
        # Blade: a long flat curved scythe sweeping forward, sharp lower edge, a row of spurs on its back.
        n = 14
        ctrl = [
            joint,
            joint + Vector((s * 0.02, -0.05, 0.2)),
            joint + Vector((s * 0.04, -0.3, 0.33)),
            joint + Vector((s * 0.05, -0.6, 0.27)),
            joint + Vector((s * 0.055, -0.8, 0.12)),
        ]
        top_rows, bot_rows = [], []
        spurs = []
        for i in range(n + 1):
            t = i / n
            c = path_point(ctrl, t)
            d = (path_point(ctrl, min(t + 0.03, 1)) - path_point(ctrl, max(t - 0.03, 0))).normalized()
            side_n = Vector((s, 0, 0))
            inner = d.cross(side_n).normalized()  # toward the sharp (inner) edge
            if inner.z > 0:
                inner = -inner
            width = 0.12 * math.sin(math.pi * min(0.15 + t, 1.0)) ** 0.6 * (1 - t) ** 0.35 + 0.006
            thick = 0.02 * (1 - t) + 0.003
            back = c - inner * width * 0.35
            edge = c + inner * width * 0.65
            top_rows.append([back + side_n * thick * 0.6, c + side_n * thick, edge + side_n * 0.001])
            bot_rows.append([back - side_n * thick * 0.6, c - side_n * thick, edge - side_n * 0.001])
            if 0.15 < t < 0.75 and i % 2 == 0:
                spurs.append((back, -inner, d))
        top_v = [[sk.bm.verts.new(p) for p in row] for row in top_rows]
        bot_v = [[sk.bm.verts.new(p) for p in row] for row in bot_rows]
        sk.rigid(_close_grid(sk, top_v, bot_v, BONE), blade)
        for back, out, d in spurs:
            sk.rigid(sk.cone(back, back + out * 0.035 - d * 0.015, 0.009, 4, BONE, 0.5), blade)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = [mat_sinew(), mat_chitin(), mat_bone(), mat_mouth()]
    sk = Skin("Creature", mats)
    eyes = Skin("Eyes", [C.mat_emissive("Eyes", EYE_COLOR, 8.0)])
    build_trunk(sk)
    build_neck_head(sk, eyes)
    build_tail(sk)
    build_legs(sk)
    build_scythes(sk)
    body = sk.finish(root)
    eye_obj = eyes.finish(root)
    for obj in (body, eye_obj):
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return body, eye_obj


# --- posing -----------------------------------------------------------------------------------------


class Pose:
    """Rotations per bone relative to its parent, in world axes at rest (a bone without one follows its parent),
    plus the Body's offset."""

    def __init__(self, offset=(0, 0, 0)):
        self.offset = Vector(offset)
        self.rel: dict = {}

    def set(self, bone: str, rot: Matrix) -> "Pose":
        self.rel[bone] = rot
        return self

    def world(self, bone: str) -> Matrix:
        parent = PARENT[bone]
        base = self.world(parent) if parent else I3
        return base @ self.rel.get(bone, I3)


def apply(arm: bpy.types.Object, pose: Pose) -> None:
    """Set the armature's pose bones from a Pose (local rotation q = R^-1 W_parent^-1 W R)."""
    for name, _h, _t, parent in BONES:
        pb = arm.pose.bones[name]
        rest = arm.data.bones[name].matrix_local.to_3x3()
        w = pose.world(name)
        wp = pose.world(parent) if parent else I3
        q = (rest.transposed() @ wp.transposed() @ w @ rest).to_quaternion()
        if pb.rotation_quaternion.dot(q) < 0:
            q.negate()
        pb.rotation_quaternion = q
        pb.location = rest.transposed() @ pose.offset if name == "Body" else Vector()


def rest_pose(arm: bpy.types.Object) -> None:
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


def smooth(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def tail_wave(p: Pose, phase: float, amp: float, lift: float) -> None:
    for i, bone in enumerate(("Tail1", "Tail2", "Tail3")):
        p.set(bone, rz(amp * math.sin(phase - i * 0.9)) @ rx(lift))


def idle(t: float) -> Pose:
    a = math.tau * t
    breath = math.sin(a)
    p = Pose((0, 0, 0.006 * breath))
    p.set("Spine", rx(-1.0 * breath)).set("Chest", rx(-1.5 * breath))
    p.set("Neck", rx(4 + 2 * math.sin(a + 0.6)) @ rz(6 * math.sin(a * 2 + 1.0)))
    p.set("Head", rx(-6 + 3 * math.sin(a + 1.2)) @ rz(-4 * math.sin(a * 2 + 1.0)))
    p.set("Jaw", rx(-3 - 3 * max(0.0, math.sin(a * 2 + 2.0))))
    tail_wave(p, a, 9, -6)
    for side, s in SIDES:
        p.set(f"{side}Scythe", rx(2 * math.sin(a + s)))
        p.set(f"{side}ScytheBlade", rx(-3 * math.sin(a * 2 + s)))
    return p


def run(t: float) -> Pose:
    """The trunk's motion while running (legs at rest, the game steps them): two bobs per stride, the spine flexing,
    the head low and steady, the tail streaming back."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = Pose((0, 0, -0.02 + 0.018 * bob))
    p.set("Body", rx(2.5 * math.sin(2 * a)) @ ry(3 * math.sin(a)))
    p.set("Spine", rx(3 * math.sin(2 * a + 0.8)) @ rz(4 * math.sin(a)))
    p.set("Chest", rx(-2 * math.sin(2 * a + 0.8)))
    p.set("Neck", rx(-10 - 2.5 * math.sin(2 * a)) @ rz(-3 * math.sin(a)))
    p.set("Head", rx(-4 + 4 * math.sin(2 * a)))
    p.set("Jaw", rx(-10))
    for i, bone in enumerate(("Tail1", "Tail2", "Tail3")):
        p.set(bone, rz(10 * math.sin(a - i * 1.1)) @ rx(-9 + 4 * math.sin(2 * a - i)))
    for side, s in SIDES:
        p.set(f"{side}Scythe", rx(10 + 4 * math.sin(2 * a + 0.5)) @ ry(s * -4))
        p.set(f"{side}ScytheBlade", rx(6 * math.sin(2 * a + 1.2)))
    return p


def attack(t: float) -> Pose:
    """Rears back (to 0.35), snaps forward with the jaw open and both blades striking down (0.5), recovers."""
    back = smooth(t / 0.35) * (1 - smooth((t - 0.35) / 0.12))
    strike = smooth((t - 0.35) / 0.15) * (1 - smooth((t - 0.6) / 0.4))
    p = Pose((0, 0.08 * back - 0.22 * strike, 0.03 * back - 0.05 * strike))
    p.set("Body", rx(6 * back - 8 * strike))
    p.set("Chest", rx(5 * back - 4 * strike))
    p.set("Neck", rx(18 * back - 22 * strike))
    p.set("Head", rx(10 * back - 6 * strike))
    p.set("Jaw", rx(-6 - 30 * back - 18 * strike))
    tail_wave(p, 0.0, 0, 15 * back - 10 * strike)
    for side, s in SIDES:
        p.set(f"{side}Scythe", rx(-25 * back + 55 * strike) @ ry(s * 10 * strike))
        p.set(f"{side}ScytheBlade", rx(-20 * back + 45 * strike))
    return p


def die(t: float) -> Pose:
    """Legs buckle (to 0.35), it rolls onto its left side (1.0) with the jaw open and the blades splayed."""
    k = smooth(t / 0.35)
    f = smooth((t - 0.2) / 0.65)
    p = Pose((0.12 * f, 0.0, -0.32 * k - 0.16 * f))
    p.set("Body", ry(78 * f) @ rx(-4 * k))
    p.set("Neck", rx(-14 * k) @ rz(15 * f))
    p.set("Head", rx(-10 * k) @ ry(-20 * f))
    p.set("Jaw", rx(-28 * k))
    tail_wave(p, 1.0, 14 * f, -10 * k)
    for side, s in SIDES:
        p.set(f"{side}Scythe", rx(35 * f) @ ry(s * 30 * f))
        p.set(f"{side}ScytheBlade", rx(25 * f))
        # Front: elbows fold back, paws tuck; hind: knees fold forward under the body.
        p.set(f"Front{side}UpperLeg", rx(-50 * k) @ ry(s * 10 * f))
        p.set(f"Front{side}LowerLeg", rx(95 * k))
        p.set(f"Front{side}Foot", rx(-40 * k))
        p.set(f"Hind{side}UpperLeg", rx(45 * k) @ ry(s * 10 * f))
        p.set(f"Hind{side}LowerLeg", rx(-80 * k))
        p.set(f"Hind{side}Foot", rx(50 * k))
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (60, idle),
    "Run": (20, run),
    "Attack": (15, attack),
    "Die": (30, die),
}


def bake_clips(arm: bpy.types.Object) -> None:
    ad = arm.animation_data_create()
    for name, (frames, fn) in CLIPS.items():
        ad.action = None
        for f in range(frames + 1):
            apply(arm, fn(f / frames))
            for pb in arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                if pb.name == "Body":
                    pb.keyframe_insert("location", frame=f, group=pb.name)
        act = ad.action
        act.name = name
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        track.mute = True
        ad.action = None
    rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.4, 1.2, 0))
    shots = []
    target = (0, -0.2, 0.7)
    rest_pose(arm)
    for view, zoom in (("iso", 0.3), ("hero", 0.36), ("back", 0.4), ("iso", 0.9)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((3.4, -0.25, 0.75)), (0, -0.05, 0.62), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.9, -1.7, 0.9)), (0, -0.8, 0.68), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    for name, pose in (
        ("idle", idle(0.25)),
        ("run", run(0.25)),
        ("attack3", attack(0.3)),
        ("attack5", attack(0.5)),
        ("die", die(1.0)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.36)
        shots.append(path)
    rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = build_skeleton(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        bake_clips(arm)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "swarmer_procedural.blend")
        C.export_glb(OUT / "swarmer_draft.glb")


main()
