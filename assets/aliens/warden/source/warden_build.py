"""Warden: the nest's guard (one per nest), the biggest strain of the hive so far. A tall, hunched, front-heavy
sentinel like a gorilla or a mantis-crab: a high hump of heavy layered plates over the shoulders and the chest (the
armored front), softer sinew showing at the flanks and the rear; long, very thick front legs it walks on, knuckle-
walking on heavy club-like chitin plates it also slams with, and shorter hind legs. A wide hood of overlapping chitin
plates fans around and above the low-slung head (small glowing eyes deep under its rim, short heavy mandibles), and a
cluster of glowing glands sits in a gap of the chest armor, above the hood, so it shows from the game's camera when
the warden faces you. Rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/warden/source/warden_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/warden/source/warden_build.py stats      # measures and pose bounds only
    tools/blender.sh assets/aliens/warden/source/warden_build.py final      # renders + warden_procedural.blend

Everything it writes goes to tmp/assets/warden/; warden_bake.py turns warden_procedural.blend into the game asset.

Layout (Blender Z-up meters; the warden faces -Y, its left is +X). Feet on the ground at the origin, the origin under
the middle of the body; the hump about 1.4 m high, the mandibles to the rump about 1.8 m.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rump) with the hind legs,
Spine, Chest with the front legs, Neck with the hood (Hood, the top plates; HoodLeft and HoodRight, the side plates),
Head, Jaw (the mandibles). Four legs (<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the front elbows bend back and
out, the hind knees forward (the hind Foot is the long metatarsal), the front Foot is the club. The game moves the legs
by IK (two bones reaching the ankle = the Foot bone's head, the Foot keeps its angle), so Idle and Run leave them at
rest; Attack keys all four (the hind feet stay where they stand, solved by the same two-bone IK, the clubs rise and
slam), Die folds them.
Meshes: "Creature" (one skinned object: the trunk, neck, head and limbs weighted to the nearest bones; plates, hood,
clubs, claws and mandibles rigid or nearly), "Eyes" (constant emissive) and "Glands" (constant emissive: the cluster
on the chest).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: looming, slow breathing, the
head scanning, the hood twitching), "Run" (loop: a heavy, lumbering knuckle-walk of the trunk), "Attack" (once,
0.8 s: rears up on its hind legs with the clubs raised and the hood flared, then slams both clubs down in front of it,
the impact at frame IMPACT_FRAME) and "Die" (once: the front buckles, it topples onto its left side, the hood
collapses).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "warden"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Matrix, Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Warden"
FPS = 30
GLAND_GLOW = 3.0  # the warden's tell, tied to the nest (the eyes: 8)
I3 = Matrix.Identity(3)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 1.0))
PELVIS = Vector((0, 0.62, 0.92))
SHOULDER = Vector((0, -0.3, 1.04))
WITHERS = Vector((0, -0.58, 0.92))
NECK_BASE = Vector((0, -0.6, 0.8))
SKULL = Vector((0, -0.84, 0.68))
SNOUT = Vector((0, -1.1, 0.6))
JAW_PIVOT = Vector((0, -0.92, 0.6))
HOOD = Vector((0, -0.8, 0.66))  # the hood's center, behind the head
# Leg joints per side (x for the left side): shoulder/hip, elbow/knee, wrist/ankle, the tail of the Foot bone.
FRONT = [
    Vector((0.36, -0.36, 1.08)),
    Vector((0.56, -0.12, 0.64)),
    Vector((0.52, -0.56, 0.3)),
    Vector((0.52, -0.66, 0.04)),
]
HIND = [
    Vector((0.27, 0.5, 0.86)),
    Vector((0.37, 0.27, 0.5)),
    Vector((0.36, 0.62, 0.19)),
    Vector((0.36, 0.52, 0.035)),
]
LEGS = (("Front", FRONT, "Chest"), ("Hind", HIND, "Hips"))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.15, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, SHOULDER, "Body"),
    ("Chest", SHOULDER, WITHERS, "Spine"),
    ("Neck", NECK_BASE, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -1.12, 0.5)), "Head"),
    ("Hood", HOOD, HOOD + Vector((0, 0.04, 0.25)), "Neck"),
    ("HoodLeft", HOOD, HOOD + Vector((0.3, 0.0, 0.05)), "Hood"),
    ("HoodRight", HOOD, HOOD + Vector((-0.3, 0.0, 0.05)), "Hood"),
]
for _side, _s in K.SIDES:
    for _leg, _pts, _parent in LEGS:
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), _parent),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest"]

# --- shapes -----------------------------------------------------------------------------------------

# Trunk profile from the rump forward: y, center z, half-width, top, bottom. Low at the rear, the hump over the
# shoulders, a deep chest.
TRUNK = [
    (0.86, 0.93, 0.08, 0.07, 0.07),
    (0.78, 0.93, 0.2, 0.15, 0.15),
    (0.62, 0.93, 0.27, 0.2, 0.2),
    (0.42, 0.95, 0.26, 0.2, 0.2),
    (0.22, 0.99, 0.28, 0.22, 0.24),
    (0.02, 1.02, 0.34, 0.26, 0.29),
    (-0.16, 1.03, 0.4, 0.3, 0.34),
    (-0.32, 1.02, 0.42, 0.32, 0.36),
    (-0.46, 0.98, 0.39, 0.3, 0.36),
    (-0.57, 0.95, 0.31, 0.24, 0.3),
    (-0.64, 0.93, 0.2, 0.16, 0.2),
    (-0.68, 0.92, 0.08, 0.07, 0.08),
]
TRUNK_SHAPE = K.Profile(TRUNK)
# The head from the back of the skull to the snout: y, center z, half-width, top, bottom. Broad and blunt.
HEAD = [
    (-0.8, 0.69, 0.1, 0.08, 0.08),
    (-0.88, 0.69, 0.135, 0.1, 0.095),
    (-0.97, 0.67, 0.135, 0.095, 0.085),
    (-1.04, 0.635, 0.105, 0.07, 0.065),
    (-1.09, 0.61, 0.055, 0.04, 0.035),
]
CHEST_CENTER = Vector((0, -0.4, 0.97))  # the chest plates are laid out around it (azimuth 0 = forward)
GLAND_GAP = 22  # half-width (degrees) of the gap in the chest armor for the glands and the neck
# The hood: an ellipse of plates in a plane leaning back a little, cupped forward at its rim.
HOOD_X = Vector((1, 0, 0))
HOOD_U = Vector((0, 0.17, 0.985)).normalized()
HOOD_N = HOOD_X.cross(HOOD_U).normalized()  # forward
HOOD_RX, HOOD_RU = 0.62, 0.36
HOOD_PLATES = 7


# --- helpers ----------------------------------------------------------------------------------------


def slab(sk: K.Skin, top: list, bottom: list, mi: int) -> list:
    """A closed slab between two grids of points (rows of the same length)."""
    top_v = [[sk.bm.verts.new(p) for p in row] for row in top]
    bot_v = [[sk.bm.verts.new(p) for p in row] for row in bottom]
    return K.close_grid(sk, top_v, bot_v, mi)


def inside_trunk(p: Vector) -> bool:
    y0, y1 = TRUNK[0][0], TRUNK[-1][0]
    if not y1 < p.y < y0:
        return False
    c, w, top, bot = TRUNK_SHAPE.at((y0 - p.y) / (y0 - y1))
    dx, dz = abs(p.x) / w, abs(p.z - c.z) / (top if p.z > c.z else bot)
    return dx ** (2 / 0.85) + dz ** (2 / 0.9) <= 1.0


def chest_point(az: float, el: float, out: float = 0.0) -> Vector:
    """A point on the front of the trunk seen from CHEST_CENTER at azimuth az (0 forward, + to the left) and
    elevation el (degrees), pushed out by `out`."""
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    lo, hi = 0.0, 1.2
    for _i in range(24):
        mid = (lo + hi) / 2
        if inside_trunk(CHEST_CENTER + d * mid):
            lo = mid
        else:
            hi = mid
    return CHEST_CENTER + d * (lo + out)


def chest_plate(sk: K.Skin, az0: float, az1: float, el0: float, el1: float, thick: float, lift: float) -> list:
    """A curved band of chest armor between az0..az1 and el0..el1; its lower edge lifts off over the band below."""
    top, bottom = [], []
    nu, nv = 5, 2
    for i in range(nv + 1):
        v = i / nv  # 0 at the top edge, 1 at the lower edge
        el = el1 + (el0 - el1) * v
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            az = az0 + (az1 - az0) * u
            edge = math.sin(math.pi * u) ** 0.4
            o = 0.012 + lift * v * edge
            bulge = 0.4 + 0.6 * math.sin(math.pi / 2 * v)
            row_t.append(chest_point(az, el, o + thick * bulge * (0.5 + 0.5 * edge)))
            row_b.append(chest_point(az, el, o))
        top.append(row_t)
        bottom.append(row_b)
    return slab(sk, top, bottom, K.CHITIN)


def hood_point(phi: float, r: float, depth: float = 0.0) -> Vector:
    """A point of the hood at angle phi (degrees, 0 = left, 90 = up) and normalized radius r, cupped forward."""
    a = math.radians(phi)
    return (
        HOOD
        + HOOD_X * (math.cos(a) * HOOD_RX * r)
        + HOOD_U * (math.sin(a) * HOOD_RU * r)
        + HOOD_N * (0.17 * r * r + depth)
    )


def hood_bone(phi: float) -> str:
    return "HoodLeft" if phi < 40 else "HoodRight" if phi > 140 else "Hood"


def rounded_ring(c: Vector, wx: float, wy: float, seg: int) -> list:
    """A horizontal rounded-rectangle ring (superellipse) around c."""
    pts = []
    for k in range(seg):
        a = math.tau * k / seg
        ca, sa = math.cos(a), math.sin(a)
        pts.append(c + Vector((math.copysign(abs(ca) ** 0.6, ca) * wx, math.copysign(abs(sa) ** 0.6, sa) * wy, 0)))
    return pts


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: K.Skin) -> None:
    n = 20
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 18, 0.008, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # Ribs: sinew ridges curving down over the soft flanks behind the shoulders.
    for _side, s in K.SIDES:
        for y in (0.0, 0.12, 0.24, 0.36):
            pts = [
                TRUNK_SHAPE.surface(y + 0.02 * k, (10 - 22 * k) if s > 0 else (170 + 22 * k), 0.006) for k in range(5)
            ]
            sk.auto(K.tube_path(sk, pts, [0.02, 0.024, 0.022, 0.017, 0.01], 5, 4, K.SINEW), TRUNK_BONES)
    # Dorsal plates: heavy overlapping shields over the hump, getting smaller and narrower toward the rump (the rear
    # shows sinew at the flanks).
    ys = [-0.64, -0.52, -0.39, -0.25, -0.1, 0.05, 0.2, 0.35, 0.5, 0.64, 0.76]
    count = len(ys) - 1
    for i, (y0, y1) in enumerate(itertools.pairwise(ys)):
        front = 1 - i / (count - 1)
        width = 34 + 40 * front
        thick = 0.022 + 0.03 * front
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0 - 0.025, y1 + 0.04, 90 - width, 90 + width, 0.01, thick, K.CHITIN, 6, 2, 0.03),
            TRUNK_BONES,
            8.0,
        )
    # Knobs along the ridge of the hump: a row of blunt chitin bosses.
    for y in (-0.44, -0.31, -0.17, -0.02):
        p = TRUNK_SHAPE.surface(y, 90, 0.06)
        sk.auto(sk.sphere(p, 0.05, 8, 4, scale=(0.8, 1.2, 0.7), mi=K.CHITIN), TRUNK_BONES, 8.0)
    # Pauldrons: three layers of plates over each shoulder, arching over the root of the front leg.
    for side, s in K.SIDES:
        up = f"Front{side}UpperLeg"
        for k, (a0, a1, y0, y1, out) in enumerate(
            ((48, 96, -0.56, -0.08, 0.05), (22, 70, -0.54, -0.14, 0.08), (-6, 44, -0.5, -0.2, 0.11))
        ):
            if s < 0:
                a0, a1 = 180 - a1, 180 - a0
            verts = K.shell(sk, TRUNK_SHAPE, y0, y1, a0, a1, out, 0.04 - 0.006 * k, K.CHITIN, 5, 2, 0.03)
            sk.auto(verts, ["Spine", "Chest", up] if k == 2 else ["Spine", "Chest"], 8.0)
    # A short blunt tail stump at the rump.
    pts = [Vector((0, 0.8, 0.93)), Vector((0, 0.92, 0.9)), Vector((0, 1.0, 0.85))]
    sk.auto(K.tube_path(sk, pts, [0.09, 0.06, 0.025], 10, 4, K.SINEW), ["Hips"])


def build_chest(sk: K.Skin, glands: K.Skin) -> None:
    """The armored front: bands of overlapping plates across the chest, split in the middle where the glands sit
    (and lower down, where the neck comes out)."""
    g = GLAND_GAP
    bands = [  # el0, el1 (lower, upper edge), split, lift
        (32, 62, False, 0.035),
        (10, 38, True, 0.035),
        (-12, 16, True, 0.035),
        (-34, -6, True, 0.03),
        (-56, -28, True, 0.025),
    ]
    for i, (el0, el1, split, lift) in enumerate(bands):
        thick = 0.05 - 0.005 * i
        reach = 78 - 4 * i
        if split:
            gap = g if i < 3 else g + 6
            sk.auto(chest_plate(sk, gap, reach, el0, el1, thick, lift), ["Spine", "Chest"], 8.0)
            sk.auto(chest_plate(sk, -reach, -gap, el0, el1, thick, lift), ["Spine", "Chest"], 8.0)
        else:
            sk.auto(chest_plate(sk, -reach, reach, el0, el1, thick, lift), ["Spine", "Chest"], 8.0)
    # The glands: a cluster of glowing bulbs swelling out of the gap, on a pad of raw flesh.
    pad = chest_point(0, 13, 0.0)
    sk.rigid(sk.sphere(pad, 0.13, 10, 6, scale=(1.0, 0.45, 1.3), rot=rx(-12), mi=K.MOUTH), "Chest")
    rnd = random.Random(5)
    for az, el, r in (
        (0, 13, 0.07),
        (-11, 3, 0.055),
        (11, 3, 0.055),
        (-12, 23, 0.058),
        (12, 23, 0.058),
        (0, 31, 0.048),
        (0, -4, 0.045),
        (-17, 13, 0.042),
        (17, 13, 0.042),
    ):
        p = chest_point(az + rnd.uniform(-1, 1), el + rnd.uniform(-1, 1), 0.025)
        glands.rigid(glands.sphere(p, r, 8, 5, scale=(1.0, 0.8, 1.0)), "Chest")


def build_neck_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Neck: short and thick, from low in the chest forward and down into the skull.
    pts = [Vector((0, -0.5, 0.86)), Vector((0, -0.64, 0.78)), Vector((0, -0.76, 0.71)), Vector((0, -0.84, 0.69))]
    sk.auto(K.tube_path(sk, pts, [0.16, 0.14, 0.12, 0.1], 14, 6, K.SINEW), ["Chest", "Neck", "Head"])
    # Skull (chitin; the underside is the roof of the mouth).
    rings = []
    n = 10
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in HEAD], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 16, 0.004, 3 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        if f.normal.z < -0.5 and f.calc_center_median().y < -0.92:
            f.material_index = K.MOUTH
    # A heavy brow plate over the eyes, and a ridge down the middle of the skull.
    top, bottom = [], []
    for i in range(4):
        v = i / 3
        y = -0.84 - 0.2 * v
        row_t, row_b = [], []
        for k in range(7):
            u = -1 + 2 * k / 6
            x = u * (0.15 - 0.03 * v)
            z = 0.79 - 0.05 * v - 0.05 * u * u
            row_b.append(Vector((x, y, z)))
            row_t.append(Vector((x, y, z + 0.03 * (1 - 0.5 * v) * (1 - 0.5 * u * u))))
        top.append(row_t)
        bottom.append(row_b)
    sk.rigid(slab(sk, top, bottom, K.CHITIN), "Head")
    # Eyes: two pairs, small, deep under the brow (and the hood's top rim above it).
    for _side, s in K.SIDES:
        eyes.rigid(eyes.sphere((s * 0.06, -1.035, 0.7), 0.019, 8, 4, scale=(1.3, 0.9, 0.8), rot=rz(s * 20)), "Head")
        eyes.rigid(eyes.sphere((s * 0.11, -0.99, 0.715), 0.014, 8, 4, scale=(1.3, 0.9, 0.8), rot=rz(s * 40)), "Head")
        sk.rigid(sk.sphere((s * 0.06, -1.02, 0.7), 0.028, 8, 4, scale=(1.3, 1.0, 1.0), mi=K.CHITIN), "Head")
    # Lower jaw: a blunt scoop; two short, thick hooked mandibles curving in under the snout.
    rings = []
    jaw = [(-0.9, 0.58, 0.1, 0.02, 0.05), (-0.98, 0.56, 0.1, 0.02, 0.05), (-1.06, 0.545, 0.07, 0.015, 0.035)]
    for i in range(5):
        y, z, w, top_h, bot = K.catmull([list(r) for r in jaw], i / 4)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top_h, bot, 12, 0.003, 9 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Jaw")
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        if f.normal.z > 0.5:
            f.material_index = K.MOUTH
    for _side, s in K.SIDES:
        pts = [
            Vector((s * 0.1, -0.93, 0.57)),
            Vector((s * 0.14, -1.04, 0.54)),
            Vector((s * 0.11, -1.14, 0.53)),
            Vector((s * 0.04, -1.19, 0.54)),
        ]
        sk.rigid(K.tube_path(sk, pts, [0.04, 0.034, 0.024, 0.01], 7, 7, K.BONE, 0.8), "Jaw")
        base = K.path_point(pts, 0.55)
        sk.rigid(sk.cone(base, base + Vector((-s * 0.04, -0.01, 0.0)), 0.012, 4, K.BONE, 0.7), "Jaw")
    # Teeth: short pegs under the snout.
    for k in range(5):
        x = -0.06 + 0.03 * k
        base = Vector((x, -1.05, 0.585))
        sk.rigid(sk.cone(base, base + Vector((0, -0.005, -0.035)), 0.01, 4, K.BONE), "Head")


def build_hood(sk: K.Skin) -> None:
    """Seven overlapping petals of chitin fanning around and above the head, the middle one in front; a membrane of
    sinew behind them at the base."""
    phis = [-12 + (204 * k / (HOOD_PLATES - 1)) for k in range(HOOD_PLATES)]
    half = 204 / (HOOD_PLATES - 1) * 0.7
    for k, phc in enumerate(phis):
        depth = -0.03 * abs(k - HOOD_PLATES // 2) / (HOOD_PLATES // 2)
        top, bottom = [], []
        nu, nv = 4, 4
        r_tip = 1.0 if 30 < phc < 150 else 0.95
        for i in range(nv + 1):
            v = i / nv
            row_t, row_b = [], []
            for j in range(nu + 1):
                u = -1 + 2 * j / nu
                phi = phc + u * half * (0.55 + 0.45 * v)
                r = 0.32 + (r_tip - 0.32) * v * (1 - 0.14 * u * u)
                thick = 0.034 * (1 - 0.45 * v) * (0.45 + 0.55 * (1 - u * u))
                b = hood_point(phi, r, depth)
                row_b.append(b)
                row_t.append(b + HOOD_N * thick)
            top.append(row_t)
            bottom.append(row_b)
        sk.rigid(slab(sk, top, bottom, K.CHITIN), hood_bone(phc))
        # A ridge along the middle of each petal, its tip pale bone.
        ridge = [hood_point(phc, 0.36 + 0.6 * t * r_tip, depth + 0.03 * (1 - 0.45 * t)) for t in (0.0, 0.4, 0.8, 1.0)]
        sk.rigid(K.tube_path(sk, ridge, [0.016, 0.014, 0.011, 0.006], 4, 4, K.CHITIN, 0.7), hood_bone(phc))
        tip = hood_point(phc, r_tip * 0.98, depth + 0.01)
        sk.rigid(
            sk.cone(
                tip - (tip - HOOD).normalized() * 0.05, tip + (tip - HOOD).normalized() * 0.045, 0.02, 4, K.BONE, 0.5
            ),
            hood_bone(phc),
        )
    # The membrane behind the petals' roots, into the neck.
    rings = []
    for z_off, scale in ((-0.05, 0.6), (0.0, 1.0), (0.04, 0.75)):
        c = HOOD + HOOD_N * z_off
        ring = [
            c + HOOD_X * (math.cos(a) * HOOD_RX * 0.42 * scale) + HOOD_U * (math.sin(a) * HOOD_RU * 0.42 * scale)
            for a in (math.tau * k / 16 for k in range(16))
        ]
        rings.append(ring)
    verts = sk.loft(rings, K.SINEW)
    for v in verts:
        side = v.co.x
        bone = "HoodLeft" if side > 0.12 else "HoodRight" if side < -0.12 else "Hood"
        sk.rigid([v], bone)


def build_front_leg(sk: K.Skin, j: list, s: float, side: str) -> None:
    up, low, foot = (f"Front{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
    # Upper arm: a massive muscle out of the shoulder, a plate on its outside.
    top = j[0] + Vector((s * -0.08, 0.0, 0.06))
    mid = j[0].lerp(j[1], 0.45) + Vector((s * 0.02, 0.0, 0.0))
    sk.auto(K.tube_path(sk, [top, mid, j[1]], [0.17, 0.16, 0.13, 0.11], 12, 6, K.SINEW, 1.0, 0.006), ["Chest", up, low])
    out = Vector((s, -0.3, 0.2)).normalized()
    sk.rigid(K.limb_plate(sk, j[0].lerp(j[1], 0.25), j[0].lerp(j[1], 0.9), 0.14, -70, 70, 0.03, K.CHITIN, out), up)
    # Elbow: a heavy knob with a spur pointing back.
    sk.rigid(sk.sphere(j[1] + Vector((s * 0.02, 0.03, 0)), 0.1, 8, 4, mi=K.CHITIN), low)
    sk.rigid(
        sk.cone(j[1] + Vector((s * 0.01, 0.06, 0.02)), j[1] + Vector((s * 0.05, 0.24, 0.04)), 0.045, 5, K.BONE), low
    )
    # Forearm: thick, swelling toward the wrist, armored in front by two layered vambraces.
    mid = j[1].lerp(j[2], 0.5)
    sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.11, 0.13, 0.12], 12, 6, K.SINEW, 1.0, 0.005), [up, low, foot])
    fwd = Vector((s * 0.35, -1, 0.1)).normalized()
    sk.rigid(K.limb_plate(sk, j[1].lerp(j[2], 0.08), j[1].lerp(j[2], 0.6), 0.13, -80, 80, 0.035, K.CHITIN, fwd), low)
    sk.rigid(K.limb_plate(sk, j[1].lerp(j[2], 0.45), j[1].lerp(j[2], 0.95), 0.135, -75, 75, 0.035, K.CHITIN, fwd), low)
    build_club(sk, j, s, low, foot)


def build_club(sk: K.Skin, j: list, s: float, low: str, foot: str) -> None:
    """The front foot: a heavy club of chitin it walks on (its knuckles) and slams with; the sole flat on the
    ground, knuckle plates over its front, bone studs at the striking edge."""
    w = j[2]
    layers = [  # z, half-width x, half-depth y, forward shift
        (0.33, 0.1, 0.1, 0.0),
        (0.24, 0.14, 0.15, 0.03),
        (0.12, 0.165, 0.18, 0.07),
        (0.04, 0.16, 0.175, 0.09),
        (0.0, 0.145, 0.16, 0.09),
    ]
    rings = []
    for z, wx, wy, f in layers:
        c = Vector((w.x + s * 0.01, w.y - f, z))
        rings.append(rounded_ring(c, wx, wy, 14))
    verts = sk.loft(rings, K.CHITIN)
    for v in verts:
        if v.co.z > 0.29:
            sk.auto([v], [low, foot])
        else:
            sk.rigid([v], foot)
    # Knuckle plates over the front and the top, overlapping downward.
    for k, (z0, z1) in enumerate(((0.2, 0.34), (0.1, 0.24), (0.02, 0.14))):
        top, bottom = [], []
        for i in range(3):
            v = i / 2
            z = z1 + (z0 - z1) * v
            fshift = 0.03 + 0.06 * (1 - z / 0.34)
            wx = 0.13 + 0.035 * (1 - z / 0.34)
            wy = 0.13 + 0.05 * (1 - z / 0.34)
            row_t, row_b = [], []
            for kk in range(5):
                a = math.radians(-160 + 140 * kk / 4)  # around the front (-y) of the club
                ca, sa = math.cos(a), math.sin(a)
                base = Vector((w.x + s * 0.01, w.y - fshift, z)) + Vector(
                    (math.copysign(abs(ca) ** 0.6, ca) * wx, math.copysign(abs(sa) ** 0.6, sa) * wy, 0)
                )
                n = Vector((ca, sa, 0.25)).normalized()
                o = 0.012 + 0.02 * v
                row_b.append(base + n * o)
                row_t.append(base + n * (o + 0.03 - 0.008 * k))
            top.append(row_t)
            bottom.append(row_b)
        sk.rigid(slab(sk, top, bottom, K.CHITIN), foot)
    # Studs of bone at the striking edge, worn blunt.
    for k in range(4):
        x = (-0.09 + 0.06 * k) * s
        base = Vector((w.x + s * 0.01 + x, w.y - 0.09 - 0.17, 0.05))
        sk.rigid(sk.cone(base + Vector((0, 0.04, 0)), base + Vector((0, -0.04, -0.03)), 0.03, 5, K.BONE), foot)


def build_hind_leg(sk: K.Skin, j: list, s: float, side: str) -> None:
    up, low, foot = (f"Hind{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
    # Haunch: thick, bare sinew (the soft rear), a small plate on the outside of the thigh.
    top = j[0] + Vector((s * -0.04, 0.02, 0.08))
    mid = j[0].lerp(j[1], 0.45) + Vector((0, 0.04, 0))
    sk.auto(K.tube_path(sk, [top, mid, j[1]], [0.18, 0.17, 0.13, 0.1], 12, 6, K.SINEW, 1.0, 0.006), ["Hips", up, low])
    out = Vector((s, 0.2, 0.3)).normalized()
    sk.rigid(K.limb_plate(sk, j[0].lerp(j[1], 0.2), j[0].lerp(j[1], 0.7), 0.13, -55, 55, 0.022, K.CHITIN, out), up)
    # Shin: back and down to the ankle, a greave behind.
    mid = j[1].lerp(j[2], 0.5)
    sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.1, 0.085, 0.07], 10, 6, K.SINEW), [up, low, foot])
    sk.rigid(sk.sphere(j[1] + Vector((0, -0.02, 0)), 0.085, 8, 4, mi=K.CHITIN), low)
    # Metatarsal to the ball of the foot, three thick toes with hooked claws.
    sk.auto(K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.068, 0.06, 0.062], 8, 4, K.SINEW), [low, foot])
    sk.rigid(sk.sphere(j[3], 0.065, 8, 4, scale=(1.1, 1.2, 0.52), mi=K.SINEW), foot)
    for k, ang in enumerate((-28, 0, 28)):
        toe = Vector((-math.sin(math.radians(ang)) * s, -1, 0)).normalized()
        knuckle = j[3] + toe * 0.07 + Vector((0, 0, 0.015))
        tip = j[3] + toe * (0.13 if k == 1 else 0.11) + Vector((0, 0, -0.012))
        sk.rigid(K.tube_path(sk, [j[3], knuckle, tip - toe * 0.02], [0.032, 0.027, 0.02], 6, 4, K.SINEW), foot)
        sk.rigid(
            sk.cone(
                tip - toe * 0.03 + Vector((0, 0, 0.012)), tip + toe * 0.02 + Vector((0, 0, -0.015)), 0.014, 5, K.BONE
            ),
            foot,
        )
    # Spur at the back of the ankle.
    sk.rigid(sk.cone(j[2] + Vector((0, 0.01, -0.02)), j[2] + Vector((0, 0.09, 0.03)), 0.02, 5, K.BONE), low)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk)
    build_chest(sk, glands)
    build_neck_head(sk, eyes)
    build_hood(sk)
    for side, s in K.SIDES:
        build_front_leg(sk, [K.mirror(p, s) for p in FRONT], s, side)
        build_hind_leg(sk, [K.mirror(p, s) for p in HIND], s, side)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


def posed_head(p: K.Pose, bone: str) -> Vector:
    """Where the head of `bone` is in pose p."""
    parent = RIG.parent[bone]
    if parent is None:
        return RIG.head[bone].copy()
    h = posed_point(p, parent, RIG.head[bone])
    return h + p.offset if bone == "Body" else h


def posed_point(p: K.Pose, bone: str, point: Vector) -> Vector:
    """Where a point that moves with `bone` (at rest at `point`) is in pose p."""
    return p.world(bone) @ (Vector(point) - RIG.head[bone]) + posed_head(p, bone)


def arc(a: Vector, b: Vector) -> Matrix:
    return a.rotation_difference(b).to_matrix()


def two_bone(root: Vector, target: Vector, a: float, b: float, pole: Vector) -> tuple:
    """Knee and end of a two-bone chain from root reaching for target, bending towards pole (as AlienLegs does)."""
    off = target - root
    dist = min(max(off.length, abs(a - b) + 0.001), (a + b) * 0.999)
    d = off.normalized()
    side = (pole - d * pole.dot(d)).normalized()
    cos_a = (a * a + dist * dist - b * b) / (2 * a * dist)
    sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
    return root + (d * cos_a + side * sin_a) * a, root + d * dist


def leg_ik(p: K.Pose, leg: str, ankle: Vector, foot_world: Matrix | None = I3, pole: Vector | None = None) -> None:
    """Bends leg (e.g. "HindLeft") so its ankle reaches `ankle` (world), the knee towards its rest side (or `pole`);
    the Foot gets the world rotation foot_world (None: it keeps its angle to the lower leg)."""
    up, low, foot = f"{leg}UpperLeg", f"{leg}LowerLeg", f"{leg}Foot"
    hip_r, knee_r, ankle_r = RIG.head[up], RIG.head[low], RIG.head[foot]
    wp = p.world(RIG.parent[up])
    if pole is None:
        axis = (ankle_r - hip_r).normalized()
        off = knee_r - hip_r
        pole = wp @ (off - axis * off.dot(axis)).normalized()
    hip = posed_head(p, up)
    knee, end = two_bone(hip, ankle, (knee_r - hip_r).length, (ankle_r - knee_r).length, pole)
    w_up = arc(wp @ (knee_r - hip_r), knee - hip) @ wp
    w_low = arc(w_up @ (ankle_r - knee_r), end - knee) @ w_up
    p.set(up, wp.transposed() @ w_up)
    p.set(low, w_up.transposed() @ w_low)
    if foot_world is not None:
        p.set(foot, w_low.transposed() @ foot_world)


def pivot(rot: Matrix, at: Vector) -> Vector:
    """The Body offset that turns the body by `rot` around the point `at` instead of around the Body bone's head."""
    return (at - BODY) - rot @ (at - BODY)


def plant(p: K.Pose, rows=("Hind",)) -> None:
    """Keeps the feet of `rows` where they stand at rest (flat on the ground)."""
    for leg, pts, _parent in LEGS:
        if leg in rows:
            for side, s in K.SIDES:
                leg_ik(p, f"{leg}{side}", K.mirror(pts[2], s))


def hood(p: K.Pose, flare: float, tilt: float = 0.0, side: float = 0.0) -> None:
    """flare (0..1): the side petals spread out and down, the top ones up; tilt: the whole hood leans back (deg);
    side: an asymmetric twitch of the side petals (deg)."""
    p.set("Hood", rx(-16 * flare - tilt))
    p.set("HoodLeft", ry(22 * flare + side) @ rz(14 * flare))
    p.set("HoodRight", ry(-22 * flare + side) @ rz(-14 * flare))


def idle(t: float) -> K.Pose:
    """Looming: slow, deep breathing, the head scanning from side to side, the hood twitching now and then."""
    a = math.tau * t
    breath = math.sin(2 * a)
    p = K.Pose(RIG, (0, 0, 0.012 * breath))
    p.set("Spine", rx(-1.2 * breath)).set("Chest", rx(-1.5 * breath))
    p.set("Neck", rz(14 * math.sin(a)) @ rx(2 * math.sin(2 * a + 0.6)))
    p.set("Head", rz(6 * math.sin(a - 0.6)) @ rx(-3 + 2 * math.sin(4 * a + 1.0)))
    p.set("Jaw", rx(2 + 5 * max(0.0, math.sin(3 * a + 2.0)) ** 2))
    twitch = max(0.0, math.sin(3 * a + 0.5)) ** 6
    hood(p, 0.15 + 0.35 * twitch, 2 * breath, 4 * math.sin(7 * a) * twitch)
    return p


def run(t: float) -> K.Pose:
    """The trunk's motion while it lumbers (legs at rest, the game steps them): a heavy knuckle-walk, the front
    surging and dropping once per stride with each club, the trunk rolling onto the side that bears its weight,
    the head low and steady."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0.025 * math.sin(a), -0.03 * math.sin(2 * a), -0.035 + 0.03 * bob))
    p.set("Body", rx(2.5 * math.sin(2 * a + 0.6)) @ ry(5 * math.sin(a)) @ rz(-3 * math.sin(a)))
    p.set("Hips", ry(-3 * math.sin(a)) @ rz(4 * math.sin(a)))
    p.set("Spine", rx(-1.5 * math.sin(2 * a)))
    p.set("Chest", ry(-2 * math.sin(a)))
    p.set("Neck", rx(6 + 2 * math.sin(2 * a + 1.2)) @ rz(-4 * math.sin(a)) @ ry(-3 * math.sin(a)))
    p.set("Head", rx(-5 - 2 * math.sin(2 * a + 1.4)))
    p.set("Jaw", rx(4))
    hood(p, 0.1, 3 * math.sin(2 * a + 2.0), 3 * math.sin(2 * a + 1.0))
    return p


ATTACK_FRAMES = 24  # 0.8 s
IMPACT_FRAME = 14  # the clubs hit the ground (t = 14 / 24, about 60 % of the clip)
HIP_PIVOT = Vector((0, 0.5, 0.86))  # it rears up around the hind hips
CLUB_RAISED = Vector((0.34, -0.55, 2.05))  # wrists above its head (left side)
CLUB_IMPACT = Vector((0.4, -1.22, 0.3))  # wrists at the impact: the clubs on the ground in front of it


def attack(t: float) -> K.Pose:
    """Rears up on its hind legs with the clubs raised and the hood flared (to 0.42), holds, slams both clubs down in
    front of it (the impact at IMPACT_FRAME), stays down a moment and pulls back to rest."""
    impact = IMPACT_FRAME / ATTACK_FRAMES
    a = K.smooth(t / 0.42)
    s = min(max((t - 0.46) / (impact - 0.46), 0.0), 1.0) ** 1.6  # accelerating into the ground
    r = K.smooth((t - 0.72) / 0.28)
    pitch = (-34 * a + 44 * s) * (1 - r)
    body = rx(pitch)
    p = K.Pose(RIG, pivot(body, HIP_PIVOT) + Vector((0, -0.12 * s, -0.04 * s)) * (1 - r))
    p.set("Body", body)
    p.set("Spine", rx((-6 * a + 8 * s) * (1 - r)))
    p.set("Chest", rx((-4 * a + 4 * s) * (1 - r)))
    p.set("Neck", rx((22 * a - 22 * s) * (1 - r)))
    p.set("Head", rx((10 * a - 14 * s) * (1 - r)))
    p.set("Jaw", rx((22 * a * (1 - s) + 10 * s) * (1 - r)))
    hood(p, max(a * (1 - r), 0.0) * (1 - 0.3 * s), 6 * a * (1 - r))
    plant(p)
    for side, sg in K.SIDES:
        rest = K.mirror(FRONT[2], sg)
        raised, hit = K.mirror(CLUB_RAISED, sg), K.mirror(CLUB_IMPACT, sg)
        target = rest.lerp(raised, a)
        target = target.lerp(hit, s) + Vector((0, -0.25, 0.1)) * math.sin(math.pi * s)
        target = target.lerp(rest, r)
        # The clubs follow the forearms while raised and land flat.
        flat = 1 - a * (1 - s) * (1 - r)
        # Elbows flare out to the sides while the clubs are up.
        rest_pole = p.world("Chest") @ Vector((sg * 0.5, 1.0, 0.0)).normalized()
        pole = rest_pole.lerp(Vector((sg * 1.0, 0.3, -0.3)).normalized(), a * (1 - s) * (1 - r))
        leg_ik(p, f"Front{side}", target, None, pole)
        w_low = p.world(f"Front{side}LowerLeg")
        p.set(
            f"Front{side}Foot", w_low.transposed() @ w_low.to_quaternion().slerp(I3.to_quaternion(), flat).to_matrix()
        )
    return p


DIE_ROLL = 20  # degrees: it ends on its chest, leaning onto its left shoulder
DIE_DROP = Vector((0.06, -0.12, -0.54))  # where the Body ends up, so it rests on the ground
DIE_CLUB = Vector((0.8, -1.0, 0.23))  # where the left club ends, tipped over onto its side
DIE_FOOT = Vector((0.62, 1.02, 0.25))  # where the left hind foot ends, slid out backwards


def die(t: float) -> K.Pose:
    """The front buckles (the elbows give way, the chest drops, to 0.4), then the whole weight crashes forward onto
    the chest, leaning onto the left shoulder (1.0): the clubs slide out and tip over, the hind legs slide out
    backwards, the hood collapses forward over the head. The legs are solved like AlienLegs does it (the game
    switches it off on death)."""
    k = K.smooth(t / 0.4)
    f = K.smooth((t - 0.25) / 0.6)
    body = ry(DIE_ROLL * f) @ rx(12 * k * (1 - f) + 3 * f)
    p = K.Pose(RIG, DIE_DROP * f + Vector((0, -0.06, -0.28)) * k * (1 - f))
    p.set("Body", body)
    p.set("Neck", rx(-14 * f) @ rz(-18 * f))
    p.set("Head", rx(-6 * f) @ ry(-18 * f))
    p.set("Jaw", rx(26 * k))
    p.set("Hood", rx(34 * f))
    p.set("HoodLeft", rz(-22 * f) @ ry(-30 * f))  # the side it leans on folds up
    p.set("HoodRight", rz(22 * f) @ ry(14 * f))
    for side, s in K.SIDES:
        q = I3.to_quaternion()
        club = K.mirror(FRONT[2], s).lerp(K.mirror(DIE_CLUB, s), f)
        pole = (p.world("Chest") @ Vector((s * 0.5, 1.0, 0.0))).lerp(Vector((s * 1.0, 0.2, 0.8)), f).normalized()
        leg_ik(p, f"Front{side}", club, q.slerp(ry(-s * 80).to_quaternion(), f).to_matrix(), pole)
        foot = K.mirror(HIND[2], s).lerp(K.mirror(DIE_FOOT, s), f)
        pole = (p.world("Hips") @ Vector((0.0, -1.0, 0.0))).lerp(Vector((s * 1.0, 0.0, 0.6)), f).normalized()
        leg_ik(p, f"Hind{side}", foot, q.slerp(rx(20).to_quaternion(), f).to_matrix(), pole)
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (30, run),
    "Attack": (ATTACK_FRAMES, attack),
    "Die": (45, die),
}

# --- preview ----------------------------------------------------------------------------------------


def bounds(names=("Creature", "Eyes", "Glands")) -> tuple:
    """Bounds of the posed meshes (after the armature)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for name in names:
        ev = bpy.data.objects[name].evaluated_get(depsgraph)
        me = ev.to_mesh()
        for v in me.vertices:
            w = ev.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        ev.to_mesh_clear()
    return tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi)


def bone_verts(bones: list) -> list:
    """World positions (posed) of the Creature's vertices weighted mostly to one of `bones`."""
    obj = bpy.data.objects["Creature"]
    names = {g.index: g.name for g in obj.vertex_groups}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(depsgraph)
    me = ev.to_mesh()
    out = [
        ev.matrix_world @ me.vertices[v.index].co
        for v in obj.data.vertices
        if v.groups and names[max(v.groups, key=lambda g: g.weight).group] in bones
    ]
    ev.to_mesh_clear()
    return out


def measures(arm: bpy.types.Object) -> None:
    K.rest_pose(arm)
    print("BOUNDS rest", bounds())
    trunk = bone_verts(TRUNK_BONES)
    print("HUMP top", max(trunk, key=lambda v: v.z))
    print("HALF-WIDTH trunk", round(max(abs(v.x) for v in trunk), 3), "all", bounds()[1][0])
    gl = bpy.data.objects["Glands"].data.vertices
    print("GLANDS center", sum((v.co for v in gl), Vector()) / len(gl))
    for name, pose in (
        ("attack_raised", attack(0.44)),
        ("attack_impact", attack(IMPACT_FRAME / ATTACK_FRAMES)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        print("BOUNDS", name, bounds())
        if name == "die":
            low = {g: round(min((v.z for v in bone_verts([g])), default=9), 3) for g, *_r in BONES}
            print("LOWEST die", {g: z for g, z in low.items() if z < 0.1})
        if name == "attack_impact":
            for side in ("Left", "Right"):
                club = bone_verts([f"Front{side}Foot"])
                low = min(v.z for v in club)
                sole = [v for v in club if v.z < low + 0.02]
                c = sum(sole, Vector()) / len(sole)
                print("CLUB", side, "lowest", round(low, 3), "sole center", c, "front", min(v.y for v in club))
    K.rest_pose(arm)


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.6, 1.2, 0))
    shots = []
    target = (0, -0.15, 0.8)
    K.rest_pose(arm)
    for view, zoom in (("iso", 0.4), ("hero", 0.48), ("back", 0.5), ("iso", 1.6)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((4.6, -0.2, 0.95)), (0, -0.1, 0.75), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.9, -2.6, 1.15)), (0, -0.85, 0.8), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    for name, pose in (
        ("idle", idle(0.3)),
        ("run", run(0.25)),
        ("attack4", attack(0.44)),
        ("attack6", attack(IMPACT_FRAME / ATTACK_FRAMES)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        if name == "attack4":
            C.render(path, view="hero", samples=24, size=512, target=(0, -0.2, 1.3), zoom=0.8)
        else:
            C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.52 if "attack" in name else 0.48)
        shots.append(path)
    K.apply(arm, attack(IMPACT_FRAME / ATTACK_FRAMES))
    bpy.context.view_layer.update()
    C.render_from(OUT / "wip" / f"{tag}_attack_side.png", Vector((5.0, -0.5, 1.1)), (0, -0.4, 0.8), 50, 24, 512)
    shots.append(OUT / "wip" / f"{tag}_attack_side.png")
    K.rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    measures(arm)
    if MODE == "stats":
        return
    if MODE == "pose":  # pose <clip> <t>: one frame of a clip from the front, the side and the iso camera
        clip, t = ARGV[1], float(ARGV[2])
        C.preview_scene(crystals=False, figure_location=(1.6, 1.2, 0))
        K.apply(arm, CLIPS[clip][1](t))
        bpy.context.view_layer.update()
        print("BOUNDS", clip, t, bounds())
        stem = f"pose_{clip}_{t:.2f}"
        shots = [OUT / "wip" / f"{stem}_{v}.png" for v in ("front", "side", "iso", "top")]
        C.render_from(shots[0], Vector((0.0, -5.5, 1.4)), (0, -0.3, 1.0), 50, 24, 512)
        C.render_from(shots[1], Vector((5.5, -0.3, 1.2)), (0, -0.3, 1.0), 50, 24, 512)
        C.render(shots[2], view="iso", samples=24, size=512, target=(0, -0.2, 0.9), zoom=0.45)
        C.render_from(shots[3], Vector((0.0, -0.2, 6.0)), (0, -0.2, 0.0), 50, 24, 512)
        C.contact_sheet(shots, OUT / "wip" / f"{stem}_sheet.png", cols=4, tile=384)
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "warden_procedural.blend")
        C.export_glb(OUT / "warden_draft.glb")


main()
