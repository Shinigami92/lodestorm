"""Burrower: a flat, shovel-headed digger of the hive (tier 2). Low and wide like an armored grub or a mole cricket:
a broad spade of a head plate with a scooping lip, small glowing eyes deep under its rim and mandibles below it, a
flat back of heavy overlapping plates, a short tapering rear with a blunt tail stump, and six short, thick digging
legs splayed sideways, the front pair with big spade claws. Rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/burrower/source/burrower_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/burrower/source/burrower_build.py final      # renders + burrower_procedural.blend

Everything it writes goes to tmp/assets/burrower/; burrower_bake.py turns burrower_procedural.blend into the game asset.

Layout (Blender Z-up meters; the burrower faces -Y, its left is +X). Feet on the ground at the origin, the origin under
the middle of the body; back 0.45 m high, the head plate's lip to the tail stump about 1.6 m (the mandible tips a bit
further), the head plate 0.76 m wide, the body 0.66 m over its side flanges.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rear) with the tail stump
(Tail1..2) and the hind legs, Spine with the middle legs, Chest with the front legs, Neck, Head (the head plate and
the head under it), Jaw (the lower jaw and the mandibles). Legs (<Front|Mid|Hind><Side>UpperLeg, LowerLeg, Foot):
the game moves them by IK (two bones reaching the ankle = the Foot bone's head, the Foot keeps its angle), so the
clips leave them at rest; only "Die" curls them. Every knee bends up and out (a sprawl).
Meshes: "Creature" (one skinned object: the trunk, head, tail and legs weighted to the nearest bones; the head plate,
mandibles, claws and spades rigid), "Eyes" (constant emissive) and "Glands" (constant emissive: a faint glow in the
seams between the back plates).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: low, the head plate sweeping side
to side as if feeling the ground), "Run" (loop: a low, fast scurry with the trunk wriggling side to side), "Attack"
(once, 0.5 s: the bite from below, the head plate jerks up and forward, the jaw opens and snaps) and "Die" (once: it
rolls onto its left side and the legs curl). The game sinks the whole body into the ground while it digs.
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "burrower"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Burrower"
FPS = 30
GLAND_GLOW = 1.5  # weaker than the eyes (8): the eyes stay the main glow
CHITIN_SHADE = 0.6  # a raider: darker chitin than the swarmer's

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.27))
PELVIS = Vector((0, 0.36, 0.27))
SHOULDER = Vector((0, -0.18, 0.27))
WITHERS = Vector((0, -0.38, 0.28))
SKULL = Vector((0, -0.46, 0.27))
LIP = Vector((0, -0.86, 0.2))
JAW_PIVOT = Vector((0, -0.62, 0.105))
TAIL = [PELVIS, Vector((0, 0.56, 0.25)), Vector((0, 0.74, 0.21))]
# Leg joints per side (x for the left side): hip, knee, ankle, ball of the foot. Short and thick, splayed sideways,
# the knees up and out.
FRONT = [
    Vector((0.19, -0.33, 0.19)),
    Vector((0.41, -0.41, 0.22)),
    Vector((0.49, -0.52, 0.08)),
    Vector((0.53, -0.62, 0.03)),
]
MID = [Vector((0.2, -0.08, 0.19)), Vector((0.4, -0.07, 0.22)), Vector((0.46, -0.1, 0.075)), Vector((0.5, -0.13, 0.025))]
HIND = [Vector((0.18, 0.2, 0.19)), Vector((0.37, 0.25, 0.22)), Vector((0.43, 0.35, 0.075)), Vector((0.47, 0.42, 0.025))]
LEGS = (("Front", FRONT, "Chest"), ("Mid", MID, "Spine"), ("Hind", HIND, "Hips"))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, SHOULDER, "Body"),
    ("Chest", SHOULDER, WITHERS, "Spine"),
    ("Neck", WITHERS, SKULL, "Chest"),
    ("Head", SKULL, LIP, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -0.9, 0.075)), "Head"),
    ("Tail1", TAIL[0], TAIL[1], "Hips"),
    ("Tail2", TAIL[1], TAIL[2], "Tail1"),
]
for _side, _s in K.SIDES:
    for _leg, _pts, _parent in LEGS:
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), _parent),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest", "Neck"]

# --- shapes -----------------------------------------------------------------------------------------

# Trunk profile from the rear forward: y, center z, half-width, top, bottom. Flat and wide, the widest at the middle.
TRUNK = [
    (0.56, 0.26, 0.1, 0.07, 0.07),
    (0.48, 0.265, 0.19, 0.1, 0.1),
    (0.36, 0.27, 0.26, 0.115, 0.13),
    (0.2, 0.27, 0.295, 0.12, 0.14),
    (0.03, 0.27, 0.305, 0.12, 0.14),
    (-0.13, 0.27, 0.295, 0.12, 0.14),
    (-0.27, 0.275, 0.27, 0.115, 0.135),
    (-0.38, 0.28, 0.22, 0.1, 0.12),
    (-0.46, 0.275, 0.15, 0.1, 0.09),
    (-0.52, 0.26, 0.1, 0.07, 0.07),
]
# The head under the plate, from the neck to the mouth: y, center z, half-width, top, bottom.
HEAD = [
    (-0.42, 0.25, 0.09, 0.06, 0.06),
    (-0.5, 0.215, 0.14, 0.07, 0.08),
    (-0.6, 0.19, 0.16, 0.065, 0.085),
    (-0.7, 0.16, 0.15, 0.05, 0.07),
    (-0.78, 0.135, 0.11, 0.04, 0.05),
    (-0.83, 0.125, 0.06, 0.025, 0.03),
]
# Lower jaw: a flat scoop under the head.
JAW = [
    (-0.6, 0.115, 0.1, 0.015, 0.03),
    (-0.68, 0.1, 0.115, 0.015, 0.032),
    (-0.77, 0.088, 0.1, 0.012, 0.028),
    (-0.84, 0.083, 0.06, 0.01, 0.018),
]
# Back plates: their front and rear edges along y (each overlaps the next, its rear edge lifting off).
PLATES = [-0.4, -0.28, -0.16, -0.04, 0.08, 0.2, 0.31, 0.42, 0.52]

PLATE_LIFT = 0.028  # how far a back plate's rear edge stands off the body

TRUNK_SHAPE = K.Profile(TRUNK)


def head_plate_point(u: float, v: float) -> tuple:
    """The head plate's top surface at u (-1 right edge .. 1 left edge) and v (0 back edge .. 1 lip), and its
    thickness there: a broad spade sloping down to the front, domed across, its rim curving down, the lip turned up."""
    y_back = -0.3 - 0.06 * u * u
    y_front = -0.87 + 0.05 * u * u
    y = y_back + (y_front - y_back) * v
    w = 0.22 + 0.18 * math.sin(math.pi / 2 * min(v / 0.7, 1.0))
    z = 0.2 + 0.245 * (1 - v) ** 1.5 + 0.035 * K.smooth((v - 0.8) / 0.2)
    z -= 0.035 * u * u + 0.02 * K.smooth((abs(u) - 0.8) / 0.2)
    thick = (0.035 - 0.012 * v) * (1 - 0.35 * u * u)
    return Vector((u * w, y, z)), thick


def lip_point(u: float) -> Vector:
    return head_plate_point(u, 1.0)[0]


# --- parts ------------------------------------------------------------------------------------------


def slab(sk: K.Skin, top: list, bottom: list, mi: int) -> list:
    """A closed slab between two grids of points (rows of the same length)."""
    top_v = [[sk.bm.verts.new(p) for p in row] for row in top]
    bot_v = [[sk.bm.verts.new(p) for p in row] for row in bottom]
    return K.close_grid(sk, top_v, bot_v, mi)


def plate_bulge(v: float) -> float:
    """A back plate's thickness along it (0 front .. 1 rear): thin where it tucks under the plate before it."""
    return 0.3 + 0.7 * math.sin(math.pi / 2 * v)


def tergite(sk: K.Skin, y0: float, y1: float, thick: float, flare: float, lift: float) -> list:
    """A heavy back plate hugging the trunk from flank to flank between y0 (front) and y1 (rear, lifting off), its
    sides flaring out over the legs as a flange."""
    top, bottom = [], []
    nu, nv = 6, 3
    for i in range(nv + 1):
        v = i / nv
        y = y0 + (y1 - y0) * v
        bulge = plate_bulge(v)
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            a = 4 + 172 * u
            edge = math.sin(math.pi * u) ** 0.4
            o = 0.008 + lift * v * edge
            row_t.append(TRUNK_SHAPE.surface(y, a, o + thick * bulge * (0.5 + 0.5 * edge)))
            row_b.append(TRUNK_SHAPE.surface(y, a, o))
        # The flanges: the plate's edge carried on outward and a little down, thinner.
        for s, idx in ((1.0, 0), (-1.0, -1)):
            t, b = row_t[idx], row_b[idx]
            out = Vector((s * flare, 0, -0.012 - lift * v * 0.3))
            ft, fb = t + out + Vector((0, 0, -thick * 0.25)), b + out + Vector((0, 0, thick * 0.1))
            if idx == 0:
                row_t.insert(0, ft)
                row_b.insert(0, fb)
            else:
                row_t.append(ft)
                row_b.append(fb)
        top.append(row_t)
        bottom.append(row_b)
    return slab(sk, top, bottom, K.CHITIN)


def build_trunk(sk: K.Skin, glands: K.Skin) -> None:
    n = 16
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.005, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # The back plates, the widest in the middle, overlapping front over rear.
    count = len(PLATES) - 1
    spans = [(y0 - 0.015, y1 + 0.03) for y0, y1 in itertools.pairwise(PLATES)]
    for i, (y0, y1) in enumerate(spans):
        mid = math.sin(math.pi * (i + 0.5) / count)
        thick = 0.024 + 0.008 * mid
        sk.auto(tergite(sk, y0, y1, thick, 0.02 + 0.04 * mid, PLATE_LIFT), TRUNK_BONES, 8.0)
        # A faint glow in the seam: on the plate's thin front, just behind the lifted rear edge of the one before.
        if 1 < i < count - 1:
            y = spans[i - 1][1] + 0.005
            v = (y - y0) / (y1 - y0)
            out = 0.008 + PLATE_LIFT * v + thick * plate_bulge(v) + 0.003
            pts = [TRUNK_SHAPE.surface(y, a, out) for a in (66, 78, 90, 102, 114)]
            glands.auto(K.tube_path(glands, pts, [0.007, 0.011, 0.012, 0.011, 0.007], 5, 5, 0, 0.6), TRUNK_BONES, 8.0)
    # Belly plates under the trunk (hidden mostly, they keep the underside from reading as bare flesh).
    for y0, y1 in itertools.pairwise([-0.3, -0.15, 0.0, 0.15, 0.3]):
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0, y1 + 0.02, 235, 305, 0.004, 0.012, K.CHITIN, 4, 2, 0.006), TRUNK_BONES, 8.0
        )


def build_head(sk: K.Skin, eyes: K.Skin) -> None:
    # The head under the plate, its underside the roof of the mouth.
    rings = []
    n = 10
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in HEAD], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 16, 0.003, 3 + i))
    verts = sk.auto(sk.loft(rings, K.SINEW), ["Chest", "Neck", "Head"])
    _mouth_faces(sk, verts, below=True)
    # The head plate: one heavy spade, its worn lip pale bone.
    nu, nv = 12, 9
    top, bottom = [], []
    for i in range(nv + 1):
        row_t, row_b = [], []
        for k in range(nu + 1):
            p, thick = head_plate_point(-1 + 2 * k / nu, i / nv)
            row_t.append(p)
            row_b.append(p - Vector((0, 0, thick)))
        top.append(row_t)
        bottom.append(row_b)
    verts = sk.rigid(slab(sk, top, bottom, K.CHITIN), "Head")
    for f in {f for v in verts for f in v.link_faces}:
        if f.calc_center_median().y < -0.8 or (
            f.calc_center_median().y < -0.74 and abs(f.calc_center_median().x) > 0.3
        ):
            f.material_index = K.BONE
    # Ridges on the plate: a keel down the middle and two curving to the corners of the lip.
    for u0, u1 in ((0.0, 0.0), (0.25, 0.62), (-0.25, -0.62)):
        pts = []
        for v in (0.05, 0.3, 0.55, 0.78):
            p, _t = head_plate_point(u0 + (u1 - u0) * v, v)
            pts.append(p + Vector((0, 0, -0.004)))
        sk.rigid(K.tube_path(sk, pts, [0.022, 0.02, 0.016, 0.01], 6, 6, K.CHITIN, 0.6), "Head")
    # Knobs along the rim's edge (the plate's rim reads thick from above).
    for side, s in K.SIDES:
        for v in (0.35, 0.55, 0.72):
            p, _t = head_plate_point(s * 0.97, v)
            sk.rigid(sk.sphere(p + Vector((0, 0, -0.01)), 0.022, 8, 4, scale=(1.0, 1.6, 0.7), mi=K.CHITIN), "Head")
    # Teeth: a row of short pegs under the front of the head.
    for k in range(6):
        x = -0.075 + 0.03 * k
        base = Vector((x, -0.8, 0.105))
        sk.rigid(sk.cone(base, base + Vector((0, -0.01, -0.03)), 0.009, 4, K.BONE), "Head")
    # Eyes: two pairs deep under the plate's front rim, the inner pair bigger, in chitin sockets.
    for side, s in K.SIDES:
        eyes.rigid(eyes.sphere((s * 0.12, -0.835, 0.158), 0.023, 8, 4, scale=(1.2, 1.1, 0.75), rot=rz(s * 15)), "Head")
        eyes.rigid(eyes.sphere((s * 0.21, -0.81, 0.152), 0.017, 8, 4, scale=(1.2, 1.0, 0.75), rot=rz(s * 35)), "Head")
        sk.rigid(sk.sphere((s * 0.12, -0.815, 0.158), 0.031, 8, 4, scale=(1.3, 1.0, 0.9), mi=K.CHITIN), "Head")
        sk.rigid(sk.sphere((s * 0.21, -0.795, 0.152), 0.023, 8, 4, scale=(1.3, 1.0, 0.9), mi=K.CHITIN), "Head")
    # Lower jaw: a flat scoop, and two thick hooked mandibles reaching out under the lip.
    rings = []
    for i in range(7):
        y, z, w, top_h, bot = K.catmull([list(r) for r in JAW], i / 6)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top_h, bot, 12, 0.002, 9 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Jaw")
    _mouth_faces(sk, verts, below=False)
    for side, s in K.SIDES:
        pts = [
            Vector((s * 0.08, -0.7, 0.1)),
            Vector((s * 0.115, -0.8, 0.09)),
            Vector((s * 0.095, -0.88, 0.082)),
            Vector((s * 0.04, -0.935, 0.078)),
        ]
        sk.rigid(K.tube_path(sk, pts, [0.032, 0.028, 0.02, 0.01], 7, 7, K.BONE, 0.75), "Jaw")
        for t in (0.45, 0.7):
            base = K.path_point(pts, t)
            sk.rigid(sk.cone(base, base + Vector((-s * 0.035, -0.008, 0.0)), 0.01, 4, K.BONE, 0.7), "Jaw")


def _mouth_faces(sk: K.Skin, verts: list, below: bool) -> None:
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        n = f.normal
        if ((n.z < -0.5) if below else (n.z > 0.5)) and f.calc_center_median().y < -0.64:
            f.material_index = K.MOUTH


def build_tail(sk: K.Skin) -> None:
    pts = [Vector((0, 0.42, 0.265)), Vector((0, 0.53, 0.25)), Vector((0, 0.63, 0.232)), Vector((0, 0.71, 0.215))]
    radii = [0.15, 0.115, 0.085, 0.065]
    sk.auto(K.tube_path(sk, pts, radii, 12, 6, K.SINEW, 0.55), ["Hips", "Tail1", "Tail2"])
    # Two heavy chitin bands over the stump and a blunt, armored cap.
    for t, bone in ((0.45, "Tail1"), (0.8, "Tail2")):
        c = K.path_point(pts, t)
        d = K.path_point(pts, t + 0.03) - K.path_point(pts, t - 0.03)
        r = K.catmull([[x] for x in radii], t)[0]
        rings = [
            K.section(c + d.normalized() * o, d, r + 0.022, r * 0.55 + 0.028, r * 0.55 + 0.004, 12)
            for o in (-0.035, 0.035)
        ]
        sk.auto(sk.loft(rings, K.CHITIN), ["Tail1", bone], 8.0)
    sk.rigid(sk.sphere((0, 0.73, 0.214), 0.07, 10, 5, scale=(1.05, 0.55, 0.6), mi=K.CHITIN), "Tail2")


def build_legs(sk: K.Skin) -> None:
    for leg, pts, body in LEGS:
        front = leg == "Front"
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            # Upper leg: a thick, short haunch out from under the flank, a chitin plate on top.
            top = j[0] + Vector((s * -0.05, 0.0, 0.03))
            mid = j[0].lerp(j[1], 0.5) + Vector((0, 0, 0.01))
            sk.auto(K.tube_path(sk, [top, mid, j[1]], [0.075, 0.068, 0.056, 0.05], 10, 5, K.SINEW), [body, up, low])
            sk.rigid(
                K.limb_plate(sk, j[0].lerp(j[1], 0.3), j[1].lerp(j[0], 0.08), 0.058, -75, 75, 0.016, K.CHITIN, K.UP),
                up,
            )
            # Lower leg: thick, armored on the outside, spurs for digging on its back edge.
            mid = j[1].lerp(j[2], 0.5)
            radii = [0.054, 0.05, 0.046] if front else [0.05, 0.042, 0.034]
            sk.auto(K.tube_path(sk, [j[1], mid, j[2]], radii, 8, 5, K.SINEW), [up, low, foot])
            out = Vector((s, 0, 0.35)).normalized()
            sk.rigid(
                K.limb_plate(sk, j[1].lerp(j[2], 0.12), j[1].lerp(j[2], 0.85), radii[1], -80, 80, 0.016, K.CHITIN, out),
                low,
            )
            sk.rigid(sk.sphere(j[1] + Vector((s * 0.01, 0, 0.012)), 0.05, 8, 4, mi=K.CHITIN), low)
            back = Vector((0, 1, 0)) if not front else Vector((s * 0.5, 0.5, 0))
            for t in (0.4, 0.7):
                base = j[1].lerp(j[2], t)
                tip = base + back.normalized() * 0.05 + Vector((s * 0.02, 0, -0.01))
                sk.rigid(sk.cone(base, tip, 0.015, 4, K.BONE), low)
            if front:
                build_spade(sk, j, s, foot)
            else:
                build_foot(sk, j, s, foot, low)


def build_spade(sk: K.Skin, j: list, s: float, foot: str) -> None:
    """The front foot: a broad, cupped digging spade sloping down to the ground, four heavy claws at its edge."""
    fwd = j[3] - j[2]
    flat = Vector((fwd.x, fwd.y, 0)).normalized()
    lat = flat.cross(K.UP).normalized()  # across the spade
    if lat.x * s < 0:
        lat = -lat
    sk.auto(K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5)], [0.05, 0.048], 8, 2, K.SINEW), [foot, foot])
    top, bottom = [], []
    nu, nv = 6, 4
    for i in range(nv + 1):
        v = i / nv
        c = j[2] + Vector((0, 0, 0.012)) + (j[3] - j[2]) * (v * 1.05)
        half = 0.065 + 0.05 * math.sin(math.pi / 2 * v)
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = -1 + 2 * k / nu
            cup = 0.02 * (1 - u * u)
            p = c + lat * (u * half + 0.02) + Vector((0, 0, -cup + 0.03 * u * v))
            th = 0.03 * (1 - 0.45 * v)
            row_t.append(p + Vector((0, 0, th)))
            row_b.append(p)
        top.append(row_t)
        bottom.append(row_b)
    sk.rigid(slab(sk, top, bottom, K.CHITIN), foot)
    # Heavy claws at the spade's front edge, curving down onto the ground.
    edge = j[2] + Vector((0, 0, 0.012)) + (j[3] - j[2]) * 1.05
    half = 0.115
    for k in range(4):
        u = -0.8 + 1.6 * k / 3
        base = edge + lat * (u * half + 0.02) + Vector((0, 0, 0.03 * u - 0.004))
        tip = base + flat * (0.12 if k in (1, 2) else 0.095)
        tip.z = 0.0
        knuckle = base.lerp(tip, 0.45) + Vector((0, 0, 0.02))
        sk.rigid(K.tube_path(sk, [base, knuckle, tip], [0.026, 0.021, 0.009], 6, 4, K.BONE, 0.7), foot)


def build_foot(sk: K.Skin, j: list, s: float, foot: str, low: str) -> None:
    """Middle and hind feet: a short, thick tarsus and three hooked claws gripping the ground."""
    sk.auto(K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.04, 0.034, 0.03], 6, 3, K.SINEW), [low, foot])
    sk.rigid(sk.sphere(j[3], 0.032, 8, 4, scale=(1.1, 1.1, 0.75), mi=K.CHITIN), foot)
    d = j[3] - j[2]
    flat = Vector((d.x, d.y, 0)).normalized()
    for ang in (-35, 0, 35):
        c, sn = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        toe = Vector((flat.x * c - flat.y * sn, flat.x * sn + flat.y * c, 0))
        base = j[3] + toe * 0.02
        tip = j[3] + toe * (0.085 if ang == 0 else 0.07)
        tip.z = 0.0
        knuckle = base.lerp(tip, 0.5) + Vector((0, 0, 0.022))
        sk.rigid(K.tube_path(sk, [base, knuckle, tip], [0.017, 0.014, 0.006], 5, 3, K.BONE, 0.8), foot)


def darken(mat: bpy.types.Material, factor: float) -> bpy.types.Material:
    """Scales the material's constant colors (raiders have darker chitin, see docs/design/aliens.md, Alien look)."""
    for node in mat.node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            for sock in (node.inputs[6], node.inputs[7]):
                if not sock.is_linked:
                    r, g, b, a = sock.default_value
                    sock.default_value = (r * factor, g * factor, b * factor, a)
    return mat


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    darken(mats[K.CHITIN], CHITIN_SHADE)
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk, glands)
    build_head(sk, eyes)
    build_tail(sk)
    build_legs(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


def tail_sway(p: K.Pose, phase: float, amp: float, lift: float) -> None:
    for i, bone in enumerate(("Tail1", "Tail2")):
        p.set(bone, rz(amp * math.sin(phase - i * 0.9)) @ rx(lift))


def idle(t: float) -> K.Pose:
    """Low, breathing; the head plate sweeps slowly side to side and dips, as if feeling the ground."""
    a = math.tau * t
    breath = math.sin(2 * a)
    p = K.Pose(RIG, (0, 0, 0.004 * breath))
    p.set("Spine", rx(-0.8 * breath) @ rz(-2 * math.sin(a))).set("Chest", rx(-0.8 * breath))
    p.set("Neck", rz(9 * math.sin(a)) @ rx(2 + 2 * math.sin(2 * a + 0.5)))
    p.set("Head", rz(5 * math.sin(a - 0.5)) @ rx(2 * math.sin(4 * a + 1.0)))
    p.set("Jaw", rx(2 + 4 * max(0.0, math.sin(3 * a + 2.0)) ** 2))
    tail_sway(p, a, 5, 0)
    return p


def run(t: float) -> K.Pose:
    """The trunk's motion while scurrying (legs at rest, the game steps them): low, a quick bob per step and the
    trunk wriggling side to side in an S, the head plate held level and low."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0, 0, -0.03 + 0.01 * bob))
    p.set("Body", rz(6 * math.sin(a)) @ ry(4 * math.sin(a + 0.4)) @ rx(-1.5 * math.sin(2 * a)))
    p.set("Hips", rz(-9 * math.sin(a - 0.6)))
    p.set("Spine", rz(-4 * math.sin(a + 0.6)))
    p.set("Chest", rz(-4 * math.sin(a + 1.0)))
    p.set("Neck", rz(-3 * math.sin(a + 1.4)) @ rx(5))
    p.set("Head", rx(2 + 2 * math.sin(2 * a)))
    p.set("Jaw", rx(4))
    tail_sway(p, a - 1.2, 12, -4)
    return p


def attack(t: float) -> K.Pose:
    """The bite from below (0.5 s): the head dips (to 0.3), the head plate jerks up and forward with the body
    behind it while the jaw gapes (0.5), the jaw snaps shut (0.6), then it settles."""
    dip = K.smooth(t / 0.3) * (1 - K.smooth((t - 0.3) / 0.12))
    jerk = K.smooth((t - 0.3) / 0.18) * (1 - K.smooth((t - 0.62) / 0.38))
    gape = K.smooth((t - 0.25) / 0.2) * (1 - K.smooth((t - 0.52) / 0.08))
    p = K.Pose(RIG, (0, 0.03 * dip - 0.16 * jerk, -0.015 * dip + 0.09 * jerk))
    p.set("Body", rx(dip - 14 * jerk))
    p.set("Hips", rx(-dip + 12 * jerk))
    p.set("Chest", rx(dip - 6 * jerk))
    p.set("Neck", rx(2 * dip - 14 * jerk))
    p.set("Head", rx(dip - 12 * jerk))
    p.set("Jaw", rx(3 + 30 * gape))
    tail_sway(p, 0.0, 0, 4 * dip - 8 * jerk)
    return p


def die(t: float) -> K.Pose:
    """It jerks, then rolls onto its left side (1.0); the legs curl in toward the belly, the jaw hangs open."""
    jolt = K.smooth(t / 0.2) * (1 - K.smooth((t - 0.2) / 0.3))
    f = K.smooth((t - 0.1) / 0.7)
    k = K.smooth(t / 0.6)
    p = K.Pose(RIG, (DIE_SHIFT[0] * f, 0.0, 0.03 * jolt + DIE_SHIFT[1] * f))
    p.set("Body", ry(DIE_ROLL * f) @ rx(-6 * jolt))
    p.set("Neck", rx(-8 * jolt + 6 * f) @ rz(-8 * f) @ ry(DIE_HEAD * f))
    p.set("Head", rx(8 * f))
    p.set("Jaw", rx(25 * k))
    tail_sway(p, 1.0, 10 * f, 6 * f)
    for side, s in K.SIDES:
        # The legs fold along the flanks (front ones forward, the others back): the upper side's curl in toward the
        # belly, the ones it lies on are pressed flat against its flank.
        for leg, swing in (("Front", -55), ("Mid", 45), ("Hind", 60)):
            if s < 0:
                p.set(f"{leg}{side}UpperLeg", rz(s * swing * k) @ ry(s * 30 * k))
                p.set(f"{leg}{side}LowerLeg", ry(s * 80 * k))
            else:
                fold = math.copysign(50, swing)
                p.set(f"{leg}{side}UpperLeg", rz(s * swing * 1.4 * k) @ ry(-s * 30 * k))
                p.set(f"{leg}{side}LowerLeg", rz(s * fold * k) @ ry(-s * 30 * k))
            p.set(f"{leg}{side}Foot", ry(s * 45 * k))
    return p


DIE_ROLL = 58  # degrees onto its left side
DIE_HEAD = -25  # the head turns back a little, the plate's rim on the ground
DIE_SHIFT = (0.12, 0.05)  # where the Body ends up (sideways, up), so it rests on the ground

CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (60, idle),
    "Run": (16, run),
    "Attack": (15, attack),
    "Die": (30, die),
}

# --- preview ----------------------------------------------------------------------------------------


def bounds() -> tuple:
    """Bounds of the posed meshes (after the armature), and the bones of the lowest and the highest vertex."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    low = high = ("", -1)
    for name in ("Creature", "Eyes", "Glands"):
        obj = bpy.data.objects[name]
        ev = obj.evaluated_get(depsgraph)
        me = ev.to_mesh()
        for v in me.vertices:
            w = ev.matrix_world @ v.co
            if w.z < lo.z:
                low = (name, v.index)
            if w.z > hi.z:
                high = (name, v.index)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        ev.to_mesh_clear()

    def bone(at: tuple) -> str:
        obj = bpy.data.objects[at[0]]
        groups = obj.data.vertices[at[1]].groups
        return obj.vertex_groups[max(groups, key=lambda g: g.weight).group].name if len(groups) else "?"

    return tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi), "low", bone(low), "high", bone(high)


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.4, 1.2, 0))
    shots = []
    target = (0, -0.1, 0.25)
    K.rest_pose(arm)
    print("BOUNDS rest", bounds())
    for view, zoom in (("iso", 0.25), ("hero", 0.3), ("back", 0.32), ("iso", 0.9)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((3.4, -0.1, 0.4)), (0, -0.1, 0.25), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.7, -1.9, 0.55)), (0, -0.7, 0.2), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    C.render_from(OUT / "wip" / f"{tag}_top.png", Vector((0.0, -0.1, 4.2)), (0, -0.1, 0.0), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_top.png")
    for name, pose in (
        ("idle", idle(0.25)),
        ("run", run(0.25)),
        ("attack3", attack(0.3)),
        ("attack5", attack(0.5)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        print("BOUNDS", name, bounds(), "body z", round((arm.matrix_world @ arm.pose.bones["Body"].head).z, 3))
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.3)
        shots.append(path)
    K.rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    if MODE == "stats":  # only the measures and the bounds of the poses, no renders
        body = bpy.data.objects["Creature"].data
        names = {g.index: g.name for g in bpy.data.objects["Creature"].vertex_groups}
        for part, bones in (("trunk", TRUNK_BONES), ("head", ["Head"])):
            xs = [
                abs(v.co.x)
                for v in body.vertices
                if v.groups and names[max(v.groups, key=lambda g: g.weight).group] in bones
            ]
            print("HALF-WIDTH", part, round(max(xs), 3))
        print("LIP", head_plate_point(0, 1), lip_point(1), lip_point(-1))
        for name, pose in (
            ("rest", K.Pose(RIG)),
            ("attack3", attack(0.3)),
            ("attack5", attack(0.5)),
            ("die", die(1.0)),
        ):
            K.apply(arm, pose)
            bpy.context.view_layer.update()
            print("BOUNDS", name, bounds(), "body z", round((arm.matrix_world @ arm.pose.bones["Body"].head).z, 3))
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "burrower_procedural.blend")
        C.export_glb(OUT / "burrower_draft.glb")


main()
