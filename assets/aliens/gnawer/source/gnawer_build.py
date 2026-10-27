"""Gnawer: the hive's raider (tier 1), a low, fast runner built around an oversized crushing jaw. It goes for the
miners and chews them apart: a huge, wide and blunt head (a third of its length) with heavy bone crushing plates and
stubby grinding teeth, a pair of short, thick mandibles at the corners of the mouth, glowing glands along the jaw
muscles (it digests metal and ore dust), small eyes set high on the skull, thick neck and shoulder muscles behind
the head, a compact body tapering to a stub tail, and four short, sturdy legs. Rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/gnawer/source/gnawer_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/gnawer/source/gnawer_build.py stats      # measures and pose bounds, no renders
    tools/blender.sh assets/aliens/gnawer/source/gnawer_build.py final      # renders + gnawer_procedural.blend

Everything it writes goes to tmp/assets/gnawer/; gnawer_bake.py turns gnawer_procedural.blend into the game asset.

Layout (Blender Z-up meters; the gnawer faces -Y, its left is +X). Feet on the ground at the origin, the origin under
the middle of the body; back 0.52 m high (over the shoulders), the crushing plates' front to the tail stub 1.35 m, the
head 0.58 m wide over the mandibles (0.5 m over the cheekbones), the trunk 0.46 m over its side plates.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rump) with the tail stub
(Tail1..2) and the hind legs, Spine, Chest with the front legs, Neck, Head (skull, upper crushing plates, the jaw
muscles and the glands), Jaw (the lower jaw and its crushing plates) and the mandibles (<Side>Mandible, under Head).
Legs (<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (two bones reaching the ankle = the Foot
bone's head, the Foot keeps its angle), so the clips leave them at rest; only "Die" folds them. Front elbows bend
back, hind knees forward (the hind Foot is the metatarsal), both a little out.
Meshes: "Creature" (one skinned object: the trunk, neck, head, tail and legs weighted to the nearest bones; plates,
crushing plates, teeth, mandibles and claws rigid), "Eyes" (constant emissive) and "Glands" (constant emissive: a
sac along each jaw muscle, under chitin straps).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: the jaw grinding side to side,
the head jerking now and then), "Run" (loop: a fast, low, bounding scurry, the head low and forward), "Attack"
(once, 0.4 s: the head lunges forward and down, the jaw gapes and clamps shut, then a grinding shake) and "Die"
(once: it rolls onto its left side, the jaw slack, the legs folded).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "gnawer"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Gnawer"
FPS = 30
GLAND_GLOW = 2.0  # weaker than the eyes (8): the eyes stay the main glow
CHITIN_SHADE = 0.6  # a raider: darker chitin than the swarmer's

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.36))
PELVIS = Vector((0, 0.36, 0.315))
SHOULDER = Vector((0, -0.18, 0.37))
WITHERS = Vector((0, -0.3, 0.385))
SKULL = Vector((0, -0.4, 0.38))
SNOUT = Vector((0, -0.76, 0.33))
JAW_PIVOT = Vector((0, -0.42, 0.29))
JAW_TIP = Vector((0, -0.76, 0.25))
TAIL = [PELVIS, Vector((0, 0.44, 0.3)), Vector((0, 0.53, 0.28))]
MANDIBLE = [Vector((0.17, -0.5, 0.275)), Vector((0.24, -0.565, 0.27)), Vector((0.238, -0.645, 0.265))]
# Leg joints per side (x for the left side): shoulder/hip, elbow/knee, ankle, ball of the foot.
FRONT = [
    Vector((0.14, -0.2, 0.34)),
    Vector((0.2, -0.1, 0.2)),
    Vector((0.19, -0.22, 0.075)),
    Vector((0.19, -0.29, 0.03)),
]
HIND = [
    Vector((0.13, 0.3, 0.315)),
    Vector((0.185, 0.17, 0.215)),
    Vector((0.175, 0.35, 0.095)),
    Vector((0.175, 0.29, 0.03)),
]
LEGS = (("Front", FRONT, "Chest"), ("Hind", HIND, "Hips"))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, SHOULDER, "Body"),
    ("Chest", SHOULDER, WITHERS, "Spine"),
    ("Neck", WITHERS, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, JAW_TIP, "Head"),
    ("Tail1", TAIL[0], TAIL[1], "Hips"),
    ("Tail2", TAIL[1], TAIL[2], "Tail1"),
]
for _side, _s in K.SIDES:
    BONES.append((f"{_side}Mandible", K.mirror(MANDIBLE[0], _s), K.mirror(MANDIBLE[2], _s), "Head"))
    for _leg, _pts, _parent in LEGS:
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), _parent),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest", "Neck"]

# --- shapes -----------------------------------------------------------------------------------------

# Trunk profile from the rump forward: y, center z, half-width, top, bottom. Deep and wide over the shoulders (the
# neck muscles carry the head), tapering to the rump.
TRUNK = [
    (0.4, 0.305, 0.06, 0.045, 0.045),
    (0.35, 0.312, 0.11, 0.07, 0.08),
    (0.25, 0.322, 0.13, 0.076, 0.09),
    (0.1, 0.338, 0.148, 0.088, 0.115),
    (-0.05, 0.36, 0.17, 0.098, 0.15),
    (-0.18, 0.372, 0.195, 0.11, 0.17),
    (-0.3, 0.38, 0.18, 0.105, 0.13),
    (-0.38, 0.375, 0.135, 0.085, 0.095),
    (-0.43, 0.37, 0.085, 0.06, 0.06),
]
# Skull with the upper jaw, from the back of the head to the blunt front: y, center z, half-width, top, bottom.
SKULL_PROFILE = [
    (-0.36, 0.405, 0.1, 0.07, 0.06),
    (-0.42, 0.41, 0.16, 0.092, 0.08),
    (-0.5, 0.4, 0.18, 0.098, 0.088),
    (-0.58, 0.385, 0.176, 0.088, 0.085),
    (-0.65, 0.37, 0.162, 0.074, 0.076),
    (-0.71, 0.36, 0.14, 0.06, 0.066),
    (-0.75, 0.355, 0.115, 0.045, 0.05),
]
# Lower jaw: heavy and deep, from the hinge to the front.
JAW_PROFILE = [
    (-0.4, 0.255, 0.11, 0.03, 0.06),
    (-0.48, 0.24, 0.152, 0.032, 0.09),
    (-0.58, 0.232, 0.155, 0.032, 0.095),
    (-0.66, 0.232, 0.14, 0.032, 0.085),
    (-0.72, 0.237, 0.11, 0.028, 0.068),
    (-0.75, 0.242, 0.075, 0.022, 0.044),
]

TRUNK_SHAPE = K.Profile(TRUNK)
SKULL_SHAPE = K.Profile(SKULL_PROFILE)

# The crushing plates: a U of thick bone around each jaw (in plan: back corner x, y; front corner x; front y) and
# its height (z0 .. z1). The upper plates hang over the lower ones like an overbite.
UPPER_PLATE = dict(xb=0.182, yb=-0.5, xf=0.14, yf=-0.765, z0=0.286, z1=0.346, thick=0.036)
LOWER_PLATE = dict(xb=0.154, yb=-0.5, xf=0.115, yf=-0.755, z0=0.228, z1=0.272, thick=0.03)
GLAND = [
    Vector((0.165, -0.33, 0.45)),
    Vector((0.195, -0.39, 0.465)),
    Vector((0.205, -0.46, 0.458)),
    Vector((0.195, -0.53, 0.43)),
]
# The plates' cusps along each half of the U (0 back corner .. 0.5 middle): where, how high, how wide.
UPPER_CUSPS = [(0.43, 0.03, 0.035), (0.3, 0.014, 0.04), (0.17, 0.012, 0.04)]
LOWER_CUSPS = [(0.37, 0.026, 0.035), (0.235, 0.012, 0.04), (0.11, 0.01, 0.04)]


def u_path(xb: float, yb: float, xf: float, yf: float) -> list:
    """Control points (z = 0) of a blunt U in plan, from the left back corner around the front to the right one."""
    left = [
        Vector((xb, yb, 0)),
        Vector((xb + 0.004, yb + (yf - yb) * 0.4, 0)),
        Vector((xf + 0.004, yf + 0.07, 0)),
        Vector((xf - 0.012, yf + 0.025, 0)),
        Vector((xf * 0.62, yf + 0.004, 0)),
        Vector((0, yf, 0)),
    ]
    return left + [K.mirror(p, -1) for p in reversed(left[:-1])]


def u_samples(plate: dict, ts: list) -> list:
    """Points and outward plan normals along a plate's U at ts (0 left back corner .. 1 right back corner)."""
    ctrl = u_path(plate["xb"], plate["yb"], plate["xf"], plate["yf"])
    center = Vector((0, (plate["yb"] + plate["yf"]) / 2 + 0.06, 0))
    out = []
    for t in ts:
        p = K.path_point(ctrl, t)
        d = K.path_point(ctrl, min(t + 0.01, 1.0)) - K.path_point(ctrl, max(t - 0.01, 0.0))
        nrm = Vector((d.y, -d.x, 0)).normalized()
        if nrm.dot(p - center) < 0:
            nrm = -nrm
        out.append((p, nrm, t))
    return out


# --- parts ------------------------------------------------------------------------------------------


def slab(sk: K.Skin, top: list, bottom: list, mi: int) -> list:
    """A closed slab between two grids of points (rows of the same length)."""
    top_v = [[sk.bm.verts.new(p) for p in row] for row in top]
    bot_v = [[sk.bm.verts.new(p) for p in row] for row in bottom]
    return K.close_grid(sk, top_v, bot_v, mi)


def build_trunk(sk: K.Skin) -> None:
    n = 16
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.006, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # The neck muscles: thick bulges from the shoulders into the back of the skull, on both sides.
    for _side, s in K.SIDES:
        sk.auto(
            sk.sphere((s * 0.12, -0.37, 0.38), 0.085, 10, 5, scale=(0.95, 1.45, 1.0), rot=rz(s * -12), mi=K.SINEW),
            ["Chest", "Neck", "Head"],
        )
    # Dorsal plates from the neck to the rump, heavy over the shoulders, the rear edge of each lifting off.
    ys = [-0.44, -0.35, -0.25, -0.15, -0.05, 0.05, 0.15, 0.25, 0.35]
    count = len(ys) - 1
    for i, (y0, y1) in enumerate(itertools.pairwise(ys)):
        width = 48 + 16 * math.sin(math.pi * i / (count - 1)) - (8 if i == 0 else 0)
        thick = 0.026 if i < 3 else 0.02
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0 - 0.02, y1 + 0.03, 90 - width, 90 + width, 0.006, thick, K.CHITIN, 5, 3, 0.016),
            TRUNK_BONES,
            8.0,
        )
    # Side plates: a heavy shoulder plate over each front leg and one over each haunch.
    for _side, s in K.SIDES:
        a0, a1 = (-20, 38) if s > 0 else (142, 200)
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, -0.3, -0.08, a0, a1, 0.012, 0.022, K.CHITIN, 4, 3, 0.014), ["Spine", "Chest"], 8.0
        )
        a0, a1 = (-20, 42) if s > 0 else (138, 200)
        sk.rigid(K.shell(sk, TRUNK_SHAPE, 0.15, 0.36, a0, a1, 0.008, 0.02, K.CHITIN, 4, 3, 0.012), "Hips")
    # Belly plates (they keep the underside from reading as bare flesh).
    for y0, y1 in itertools.pairwise([-0.26, -0.06]):
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0, y1 + 0.02, 240, 300, 0.004, 0.012, K.CHITIN, 4, 2, 0.006), TRUNK_BONES, 8.0
        )


def crushing_plate(sk: K.Skin, plate: dict, bone: str, upper: bool) -> None:
    """A shearing plate of thick bone along each half of the jaw's U, a chisel in section (the outer face slanting in
    to a narrow edge), the edge rising and falling in blunt cusps with a heavy fang beside the middle; stubby
    grinding teeth (molars) behind the plates."""
    z0, z1, thick = plate["z0"], plate["z1"], plate["thick"]
    edge_z, root_z = (z0, z1) if upper else (z1, z0)
    cusps = UPPER_CUSPS if upper else LOWER_CUSPS
    n = 12
    for half in (0, 1):
        ts = [0.005 + 0.48 * k / n for k in range(n + 1)]
        if half:
            ts = [1 - t for t in reversed(ts)]
        outer, inner = [], []
        for p, nrm, t in u_samples(plate, ts):
            u = min(t, 1 - t)  # 0 at the back corners, 0.5 at the middle
            rear = K.smooth(u / 0.1)  # the plate tapers into the cheek at its rear end
            cusp = sum(h * math.exp(-(((u - c) / w) ** 2)) for c, h, w in cusps)
            ez = edge_z + (root_z - edge_z) * 0.5 * (1 - rear) + (-cusp if upper else cusp)
            row_o, row_i = [], []
            for v in (0.0, 0.4, 1.0):  # edge .. root
                z = ez + (root_z - ez) * v
                row_o.append(Vector((p.x, p.y, z)) + nrm * thick * (-0.1 + 0.55 * v**0.5))
                row_i.append(Vector((p.x, p.y, z)) - nrm * thick * (0.3 + 0.25 * v))
            outer.append(row_o)
            inner.append(row_i)
        sk.rigid(slab(sk, outer, inner, K.BONE), bone)
    # Stubby grinding teeth behind the plates, the biggest at the back; the upper and lower rows interlock.
    ts = [0.08, 0.18, 0.28, 0.72, 0.82, 0.92] if upper else [0.13, 0.23, 0.77, 0.87]
    for p, nrm, t in u_samples(plate, ts):
        back = 1 - min(t, 1 - t) * 2  # 1 at the back corners, 0 at the front
        r = 0.016 + 0.008 * back
        length = 0.026 + 0.01 * back
        base = Vector((p.x, p.y, edge_z + (0.008 if upper else -0.008))) - nrm * (thick * 0.55 + r * 0.5)
        tip = base + Vector((0, 0, -length if upper else length)) - nrm * 0.004
        sk.rigid(sk.cone(base, tip, r, 5, K.BONE, 0.85), bone)


def build_head(sk: K.Skin, eyes: K.Skin, glands: K.Skin) -> None:
    # Skull and upper jaw (the underside is the roof of the mouth).
    rings = []
    n = 12
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in SKULL_PROFILE], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 14, 0.003, 3 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    _mouth_faces(sk, verts, below=True)
    # Cranium plates.
    for y0, y1, a in ((-0.37, -0.52, 62), (-0.5, -0.64, 56), (-0.62, -0.74, 64)):
        sk.rigid(K.shell(sk, SKULL_SHAPE, y0, y1, 90 - a, 90 + a, 0.004, 0.022, K.CHITIN, 6, 3, -0.004), "Head")
    # A keel down the middle of the skull (the jaw muscles' anchor), thin and tall, sloping to the neck.
    crest = [SKULL_SHAPE.surface(y, 90, -0.01) for y in (-0.64, -0.55, -0.45)] + [Vector((0, -0.34, 0.462))]
    rings = []
    for i in range(7):
        t = i / 6
        c = K.path_point(crest, t)
        d = K.path_point(crest, min(t + 0.05, 1)) - K.path_point(crest, max(t - 0.05, 0))
        h = 0.012 + 0.038 * math.sin(math.pi * (0.1 + 0.75 * t)) ** 0.8
        rings.append(K.section(c, d, 0.014 + 0.006 * h / 0.05, h, 0.01, 6))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    # Throat: under the head, from the neck into the lower jaw.
    pts = [Vector((0, -0.3, 0.3)), Vector((0, -0.38, 0.27)), Vector((0, -0.46, 0.24))]
    sk.auto(K.tube_path(sk, pts, [0.11, 0.1, 0.08], 12, 4, K.SINEW), ["Neck", "Head", "Jaw"])
    # Lower jaw.
    rings = []
    for i in range(9):
        y, z, w, top, bot = K.catmull([list(r) for r in JAW_PROFILE], i / 8)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 12, 0.002, 9 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Jaw")
    _mouth_faces(sk, verts, below=False)
    # The crushing plates around both jaws.
    crushing_plate(sk, UPPER_PLATE, "Head", True)
    crushing_plate(sk, LOWER_PLATE, "Jaw", False)
    for side, s in K.SIDES:
        # Jaw muscles: a big bulge on each side of the skull (on top, the glands' seat) and the cheek muscle down
        # to the lower jaw.
        sk.rigid(
            sk.sphere((s * 0.15, -0.43, 0.42), 0.075, 10, 5, scale=(1.0, 1.6, 0.85), rot=rz(s * 8), mi=K.SINEW),
            "Head",
        )
        sk.auto(
            sk.sphere((s * 0.165, -0.48, 0.31), 0.062, 10, 5, scale=(0.8, 1.45, 1.3), mi=K.SINEW), ["Head", "Jaw"], 2.0
        )
        # The glands: a long, swollen, glowing sac along the top of each jaw muscle, under three chitin straps.
        g = [K.mirror(p, s) for p in GLAND]
        radii = [0.016, 0.022, 0.022, 0.015]
        glands.rigid(K.tube_path(glands, g, radii, 8, 8, 0, 0.8), "Head")
        for t in (0.3, 0.55, 0.8):
            c = K.path_point(g, t)
            d = K.path_point(g, t + 0.05) - K.path_point(g, t - 0.05)
            r = K.catmull([[x] for x in radii], t)[0]
            band = [K.section(c + d.normalized() * o, d, r + 0.008, r * 0.8 + 0.01, r * 0.5, 10) for o in (-0.01, 0.01)]
            sk.rigid(sk.loft(band, K.CHITIN), "Head")
        # Cheek plate over the cheek muscle's flank.
        sk.rigid(
            sk.sphere((s * 0.21, -0.47, 0.33), 0.055, 10, 5, scale=(0.45, 1.5, 0.8), rot=ry(s * 15), mi=K.CHITIN),
            "Head",
        )
        # Cheekbone: a heavy arch of chitin from under the eye back along the jaw muscle.
        arch = [
            Vector((s * x, y, z)) for x, y, z in ((0.165, -0.63, 0.365), (0.215, -0.54, 0.372), (0.228, -0.44, 0.38))
        ]
        arch.append(Vector((s * 0.19, -0.35, 0.395)))
        sk.rigid(K.tube_path(sk, arch, [0.016, 0.026, 0.026, 0.014], 6, 6, K.CHITIN, 0.7), "Head")
        # Eyes: small, high on the skull, a bigger pair in front of a smaller one, under brow ridges.
        for y, a, r in ((-0.645, 50, 0.018), (-0.59, 44, 0.012)):
            aa = a if s > 0 else 180 - a
            p = SKULL_SHAPE.surface(y, aa, 0.002)
            eyes.rigid(eyes.sphere(p, r, 8, 4, scale=(1.0, 1.3, 0.8), rot=rz(s * 25)), "Head")
            brow = SKULL_SHAPE.surface(y + 0.004, aa + (8 if s > 0 else -8), 0.012)
            sk.rigid(sk.sphere(brow, r * 1.6, 8, 4, scale=(1.0, 1.4, 0.5), rot=rz(s * 25), mi=K.CHITIN), "Head")
        # The mandibles: short, thick and horizontal, from the corners of the mouth hooking forward and in.
        m = [K.mirror(p, s) for p in MANDIBLE] + [Vector((s * 0.19, -0.705, 0.262))]
        bone = f"{side}Mandible"
        sk.rigid(sk.sphere(m[0], 0.042, 10, 5, scale=(1.0, 1.2, 0.9), mi=K.CHITIN), bone)
        sk.rigid(K.tube_path(sk, m, [0.05, 0.046, 0.032, 0.013], 8, 7, K.BONE, 0.75), bone)
        for t in (0.45, 0.7):
            base = K.path_point(m, t)
            sk.rigid(sk.cone(base, base + Vector((-s * 0.03, -0.01, 0.0)), 0.012, 4, K.BONE, 0.7), bone)


def _mouth_faces(sk: K.Skin, verts: list, below: bool) -> None:
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        n = f.normal
        if ((n.z < -0.5) if below else (n.z > 0.5)) and f.calc_center_median().y < -0.45:
            f.material_index = K.MOUTH


def build_tail(sk: K.Skin) -> None:
    pts = [Vector((0, 0.31, 0.316)), Vector((0, 0.4, 0.305)), Vector((0, 0.47, 0.292)), Vector((0, 0.53, 0.28))]
    radii = [0.11, 0.08, 0.058, 0.04]
    sk.auto(K.tube_path(sk, pts, radii, 10, 5, K.SINEW, 0.8), ["Hips", "Tail1", "Tail2"])
    for t, bone in ((0.4, "Tail1"), (0.75, "Tail2")):
        c = K.path_point(pts, t)
        d = K.path_point(pts, t + 0.03) - K.path_point(pts, t - 0.03)
        r = K.catmull([[x] for x in radii], t)[0]
        rings = [
            K.section(c + d.normalized() * o, d, r + 0.014, r * 0.8 + 0.02, r * 0.8 + 0.004, 12) for o in (-0.03, 0.03)
        ]
        sk.auto(sk.loft(rings, K.CHITIN), ["Tail1", bone], 8.0)
    sk.rigid(sk.sphere((0, 0.54, 0.28), 0.045, 10, 5, scale=(1.0, 0.8, 0.85), mi=K.CHITIN), "Tail2")


def build_legs(sk: K.Skin) -> None:
    for leg, pts, body in LEGS:
        hind = leg == "Hind"
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            # Upper leg: a thick haunch / shoulder muscle, into the body.
            top = j[0] + Vector((s * -0.03, 0.0, 0.06))
            radii = [0.115, 0.11, 0.082, 0.064] if hind else [0.105, 0.1, 0.08, 0.064]
            mid = j[0].lerp(j[1], 0.45) + (Vector((0, 0.02, 0)) if hind else Vector((0, -0.015, 0)))
            sk.auto(K.tube_path(sk, [top, mid, j[1]], radii, 10, 5, K.SINEW, 1.0, 0.004), [body, up, low])
            # Lower leg: short and thick, a chitin greave on the front.
            mid = j[1].lerp(j[2], 0.5)
            sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.064, 0.054, 0.048], 8, 4, K.SINEW), [up, low, foot])
            facing = Vector((0, -1, 0.2)) if hind else Vector((0, 1, 0.1))
            sk.rigid(
                K.limb_plate(
                    sk,
                    j[1].lerp(j[2], 0.15),
                    j[1].lerp(j[2], 0.85),
                    0.055,
                    -75,
                    75,
                    0.016,
                    K.CHITIN,
                    -facing if hind else facing,
                ),
                low,
            )
            sk.rigid(
                sk.sphere(j[1] + (Vector((0, -0.015, 0)) if hind else Vector((0, 0.02, 0))), 0.054, 8, 4, mi=K.CHITIN),
                low,
            )
            # Foot: a short, thick tarsus to the ball, three heavy claws gripping the ground.
            sk.auto(
                K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.048, 0.042, 0.038], 8, 3, K.SINEW), [low, foot]
            )
            sk.rigid(sk.sphere(j[3], 0.042, 8, 4, scale=(1.2, 1.2, 0.72), mi=K.SINEW), foot)
            for k, ang in enumerate((-28, 0, 28)):
                toe = Vector((math.sin(math.radians(ang)) * -s, -1, 0)).normalized()
                base = j[3] + toe * 0.02
                tip = j[3] + toe * (0.085 if k == 1 else 0.07)
                tip.z = 0.0
                knuckle = base.lerp(tip, 0.5) + Vector((0, 0, 0.022))
                sk.rigid(K.tube_path(sk, [base, knuckle, tip], [0.024, 0.019, 0.008], 5, 3, K.BONE, 0.8), foot)
            # Spur at the back of the ankle.
            back = Vector((0, 0.05, 0.02)) if hind else Vector((0, 0.045, 0.025))
            sk.rigid(sk.cone(j[2] + Vector((0, 0.01, -0.015)), j[2] + back, 0.014, 5, K.BONE), low if hind else foot)


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
    build_trunk(sk)
    build_head(sk, eyes, glands)
    build_tail(sk)
    build_legs(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


def pulse(t: float, t0: float, rise: float = 0.035, fall: float = 0.12) -> float:
    """A quick twitch at t0: up in `rise`, back down in `fall`."""
    return K.smooth((t - t0) / rise) * (1 - K.smooth((t - t0 - rise) / fall))


def mandibles(p: K.Pose, spread: float) -> None:
    """Both mandibles swing out (spread > 0) or clamp in (< 0), in degrees."""
    for side, s in K.SIDES:
        p.set(f"{side}Mandible", rz(s * spread))


def tail(p: K.Pose, sway: float, lift: float) -> None:
    p.set("Tail1", rz(sway) @ rx(lift))
    p.set("Tail2", rz(sway * 0.6) @ rx(lift * 0.6))


def idle(t: float) -> K.Pose:
    """Low and breathing, the jaw grinding (opening a little and sliding side to side), the head jerking twice."""
    a = math.tau * t
    breath = math.sin(a)
    chew = 0.5 - 0.5 * math.cos(4 * a)
    j1, j2 = pulse(t, 0.3), pulse(t, 0.7)
    p = K.Pose(RIG, (0, 0, 0.005 * breath))
    p.set("Spine", rx(-1.0 * breath)).set("Chest", rx(-1.2 * breath))
    p.set("Neck", rx(2 * math.sin(a + 0.5) + 4 * j2) @ rz(9 * j1 - 7 * j2))
    p.set("Head", rx(-1.5 * chew - 7 * j1 + 3 * j2) @ rz(5 * j1 - 8 * j2) @ ry(-4 * j1))
    p.set("Jaw", rx(3 + 9 * chew) @ rz(4 * math.sin(4 * a - 1.2)))
    mandibles(p, 4 * math.sin(4 * a + 0.6) + 10 * j1)
    tail(p, 6 * math.sin(a), 2 * breath)
    return p


def run(t: float) -> K.Pose:
    """The trunk's motion while scurrying (legs at rest, the game steps them): low and bounding, two bobs per stride
    with the trunk rocking front to back, the head held low and forward, the jaw a little open."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0, 0, -0.025 + 0.022 * bob))
    p.set("Body", rx(4 * math.sin(2 * a)) @ ry(2.5 * math.sin(a)))
    p.set("Spine", rx(-3 * math.sin(2 * a + 0.8)) @ rz(3 * math.sin(a)))
    p.set("Chest", rx(2 * math.sin(2 * a + 0.8)))
    p.set("Neck", rx(9 - 3 * math.sin(2 * a + 0.3)) @ rz(-2 * math.sin(a)))
    p.set("Head", rx(-4 - 3 * math.sin(2 * a)))
    p.set("Jaw", rx(7 + 3 * math.sin(2 * a + 1.0)))
    mandibles(p, 8)
    tail(p, 5 * math.sin(a), -8 * math.sin(2 * a - 0.5))
    return p


def attack(t: float) -> K.Pose:
    """The bite (0.4 s): the head lunges forward and down while the jaw gapes (to 0.25), the jaw and the mandibles
    clamp shut (0.35), a grinding shake of the head (to 0.8), then it pulls back."""
    lunge = K.smooth(t / 0.28) * (1 - K.smooth((t - 0.75) / 0.25))
    gape = K.smooth(t / 0.25) * (1 - K.smooth((t - 0.26) / 0.09))
    hold = K.smooth((t - 0.3) / 0.06) * (1 - K.smooth((t - 0.78) / 0.15))
    shake = hold * math.sin(math.tau * (t - 0.34) / 0.14)
    p = K.Pose(RIG, (0, -0.13 * lunge, -0.025 * lunge))
    p.set("Body", rx(4 * lunge))
    p.set("Hips", rx(-4 * lunge))
    p.set("Chest", rx(2 * lunge))
    p.set("Neck", rx(7 * lunge) @ rz(5 * shake))
    p.set("Head", rx(5 * lunge - 17 * gape) @ rz(9 * shake) @ ry(7 * shake))
    p.set("Jaw", rx(36 * gape - 1 * hold) @ rz(5 * shake))
    mandibles(p, 28 * gape - 12 * hold)
    tail(p, -4 * shake, -10 * lunge)
    return p


def die(t: float) -> K.Pose:
    """It jerks, then rolls onto its left side (1.0); the jaw hangs slack, the legs fold in."""
    jolt = K.smooth(t / 0.15) * (1 - K.smooth((t - 0.15) / 0.25))
    f = K.smooth((t - 0.1) / 0.7)
    k = K.smooth(t / 0.5)
    p = K.Pose(RIG, (DIE_SHIFT[0] * f, 0.0, 0.03 * jolt + DIE_SHIFT[1] * f))
    p.set("Body", ry(DIE_ROLL * f) @ rx(-6 * jolt))
    p.set("Neck", rx(-10 * jolt + 6 * f) @ ry(DIE_HEAD * f))
    p.set("Head", rx(6 * f))
    p.set("Jaw", rx(30 * k) @ rz(-6 * f))
    mandibles(p, 14 * k)
    tail(p, 10 * f, 6 * f)
    for side, s in K.SIDES:
        # Front: elbows fold back, paws tuck; hind: knees fold forward under the body.
        p.set(f"Front{side}UpperLeg", rx(-45 * k) @ ry(s * 12 * f))
        p.set(f"Front{side}LowerLeg", rx(85 * k))
        p.set(f"Front{side}Foot", rx(-35 * k))
        p.set(f"Hind{side}UpperLeg", rx(40 * k) @ ry(s * 12 * f))
        p.set(f"Hind{side}LowerLeg", rx(-75 * k))
        p.set(f"Hind{side}Foot", rx(45 * k))
    return p


DIE_ROLL = 75  # degrees onto its left side
DIE_HEAD = 15  # the head turns over a little less than the body
DIE_SHIFT = (0.14, -0.055)  # where the Body ends up (sideways, up), so it rests on the ground

CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (60, idle),
    "Run": (16, run),
    "Attack": (12, attack),
    "Die": (30, die),
}

# --- preview ----------------------------------------------------------------------------------------


def bounds() -> tuple:
    """Bounds of the posed meshes (after the armature)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for name in ("Creature", "Eyes", "Glands"):
        ev = bpy.data.objects[name].evaluated_get(depsgraph)
        me = ev.to_mesh()
        for v in me.vertices:
            w = ev.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        ev.to_mesh_clear()
    return tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi)


def measures() -> None:
    """The positions the game needs: the jaw's front, the glands' center and the body's half-width."""
    body = bpy.data.objects["Creature"].data
    names = {g.index: g.name for g in bpy.data.objects["Creature"].vertex_groups}

    def owned(bones: list) -> list:
        return [v.co for v in body.vertices if v.groups and names[max(v.groups, key=lambda g: g.weight).group] in bones]

    trunk = owned(["Hips", "Spine", "Chest"])
    print("HALF-WIDTH trunk", round(max(abs(c.x) for c in trunk), 3))
    head = owned(["Head", "Jaw", "LeftMandible", "RightMandible"])
    print("HALF-WIDTH head", round(max(abs(c.x) for c in head), 3))
    front = min(head, key=lambda c: c.y)
    print("JAW FRONT", tuple(round(x, 3) for x in front))
    gl = [v.co for v in bpy.data.objects["Glands"].data.vertices]
    left = [c for c in gl if c.x > 0]
    center = sum(left, Vector()) / len(left)
    print("GLANDS center (left, mirrored right)", tuple(round(x, 3) for x in center))
    print("GLANDS center (both)", tuple(round(x, 3) for x in sum(gl, Vector()) / len(gl)))


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.4, 1.2, 0))
    shots = []
    target = (0, -0.12, 0.28)
    K.rest_pose(arm)
    print("BOUNDS rest", bounds())
    for view, zoom in (("iso", 0.24), ("hero", 0.28), ("back", 0.3), ("iso", 0.9)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((3.2, -0.12, 0.4)), (0, -0.1, 0.27), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.75, -1.75, 0.6)), (0, -0.55, 0.3), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    C.render_from(OUT / "wip" / f"{tag}_top.png", Vector((0.0, -0.1, 4.0)), (0, -0.1, 0.0), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_top.png")
    for name, pose in (
        ("idle", idle(0.31)),
        ("run", run(0.25)),
        ("attack2", attack(0.24)),
        ("attack5", attack(0.5)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        print("BOUNDS", name, bounds())
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.28)
        shots.append(path)
    K.apply(arm, attack(0.24))
    bpy.context.view_layer.update()
    C.render_from(OUT / "wip" / f"{tag}_bite.png", Vector((0.9, -1.9, 0.55)), (0, -0.6, 0.25), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_bite.png")
    K.rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    measures()
    if MODE == "stats":  # only the measures and the bounds of the poses, no renders
        for name, pose in (("rest", K.Pose(RIG)), ("attack2", attack(0.24)), ("die", die(1.0))):
            K.apply(arm, pose)
            bpy.context.view_layer.update()
            print("BOUNDS", name, bounds(), "body z", round((arm.matrix_world @ arm.pose.bones["Body"].head).z, 3))
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "gnawer_procedural.blend")
        C.export_glb(OUT / "gnawer_draft.glb")


main()
