"""Shrieker: the hive's screaming support (tier 3 hunter), a lean alien on four long, thin legs with a very long neck
that carries a small, narrow head high above the pack. Its jaw gapes very wide, and a glowing throat sac under the
jaw and down the front of the neck swells when it screams; ridged chitin plates run along the top of the neck, a short
tail. Rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/shrieker/source/shrieker_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/shrieker/source/shrieker_build.py stats      # measures and pose bounds, no renders
    tools/blender.sh assets/aliens/shrieker/source/shrieker_build.py final      # renders + shrieker_procedural.blend

Everything it writes goes to tmp/assets/shrieker/; shrieker_bake.py turns shrieker_procedural.blend into the game
asset.

Layout (Blender Z-up meters; the shrieker faces -Y, its left is +X; the game turns the model by 180 degrees). Feet on
the ground at the origin, the origin under the middle of the body; the back about 0.9 m high over the shoulders, the
head carried at about 1.5 m (about 2 m in the scream), snout to tail tip about 1.95 m.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rump) with the tail
(Tail1..2) and the hind legs, Spine, Chest with the front legs, Neck, Neck2, Neck3 (the long neck, from the withers up
to the skull), Sac (the throat sac on the front of Neck3: the clips scale it), Head, Jaw. Legs
(<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (two bones reaching the ankle = the Foot
bone's head, the Foot keeps its angle), so the clips leave them at rest; only "Die" folds them. Front elbows bend
back, hind knees forward (the hind Foot is the long metatarsal).
Meshes: "Creature" (one skinned object: trunk, neck, tail and legs weighted to the nearest bones; plates, teeth,
spines and claws rigid; the cheeks blend from Head to Jaw, so they stretch when the jaw gapes), "Eyes" (constant
emissive) and "Glands" (constant emissive: the throat sac, skinned to Sac; the game flares it with the eyes).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: the neck swaying, the head turning,
the sac pulsing), "Run" (loop: a skittish trot, the neck forward and lower; the legs come from the game), "Attack"
(the scream, once, 1.6 s: the neck rises to full height and the head tilts up while the sac swells; the peak at frame
30 = 1.0 s with the jaw gaping and the sac at its biggest, then it relaxes) and "Die" (once: the neck whips down and
collapses, it rolls onto its left side, the legs fold). The clips key every bone's rotation, the Body's location and
the Sac's scale (own bake, the kit's keys no scale).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "shrieker"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Shrieker"
FPS = 30
GLAND_GLOW = 2.0  # the eyes stay the brightest (8 in the previews); TBD (playtest)
X = Vector((1, 0, 0))

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.76))
PELVIS = Vector((0, 0.42, 0.74))
SHOULDER = Vector((0, -0.2, 0.78))
WITHERS = Vector((0, -0.4, 0.86))
NECK1 = Vector((0, -0.62, 1.0))
NECK2 = Vector((0, -0.8, 1.2))
SKULL = Vector((0, -0.9, 1.5))
SNOUT = Vector((0, -1.2, 1.44))
JAW_PIVOT = Vector((0, -0.91, 1.452))
JAW_TIP = Vector((0, -1.18, 1.405))
TAIL = [PELVIS, Vector((0, 0.62, 0.7)), Vector((0, 0.8, 0.6))]
# The neck's centerline (smooth path) from inside the chest up into the back of the skull, and its radii.
NECK_PATH = [
    Vector((0, -0.3, 0.8)),
    Vector((0, -0.45, 0.88)),
    Vector((0, -0.63, 1.01)),
    Vector((0, -0.8, 1.2)),
    Vector((0, -0.87, 1.37)),
    Vector((0, -0.9, 1.5)),
]
NECK_RADII = [0.13, 0.1, 0.078, 0.066, 0.058, 0.052]
# The throat sac: an ellipsoid on the front of Neck3 (its long axis along the neck), the lower end fuller.
N3_DIR = (SKULL - NECK2).normalized()
N3_FRONT = Vector((0, -N3_DIR.z, N3_DIR.y))  # perpendicular to Neck3, facing forward
SAC_AXIS = NECK2.lerp(SKULL, 0.32)
SAC_C = SAC_AXIS + N3_FRONT * 0.068
SAC_R = (0.07, 0.12, 0.062)  # half-width, half-length (along the neck), depth (out of the throat)
SAC_BANDS = (-0.45, 0.05, 0.5)  # where the straps cross it (-1 bottom .. 1 top)
SAC_HEAD = SAC_AXIS + N3_FRONT * 0.02  # the Sac bone's head: it swells away from the neck
# Leg joints per side (x for the left side): shoulder/hip, elbow/knee, ankle, ball of the foot.
FRONT = [
    Vector((0.12, -0.24, 0.7)),
    Vector((0.165, -0.1, 0.4)),
    Vector((0.15, -0.25, 0.1)),
    Vector((0.15, -0.31, 0.03)),
]
HIND = [
    Vector((0.11, 0.38, 0.7)),
    Vector((0.155, 0.17, 0.45)),
    Vector((0.145, 0.44, 0.17)),
    Vector((0.145, 0.38, 0.03)),
]
LEGS = (("Front", FRONT, "Chest"), ("Hind", HIND, "Hips"))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, SHOULDER, "Body"),
    ("Chest", SHOULDER, WITHERS, "Spine"),
    ("Neck", WITHERS, NECK1, "Chest"),
    ("Neck2", NECK1, NECK2, "Neck"),
    ("Neck3", NECK2, SKULL, "Neck2"),
    ("Sac", SAC_HEAD, SAC_HEAD + N3_FRONT * 0.15, "Neck3"),
    ("Head", SKULL, SNOUT, "Neck3"),
    ("Jaw", JAW_PIVOT, JAW_TIP, "Head"),
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
NECK_BONES = ["Chest", "Neck", "Neck2", "Neck3", "Head"]

# --- shapes -----------------------------------------------------------------------------------------

# Trunk profile from the rump forward: y, center z, half-width, top, bottom. Lean: a deep chest and a tucked waist,
# the shoulders higher than the rump.
TRUNK = [
    (0.54, 0.72, 0.05, 0.045, 0.045),
    (0.46, 0.735, 0.1, 0.072, 0.082),
    (0.34, 0.748, 0.12, 0.078, 0.092),
    (0.19, 0.75, 0.105, 0.072, 0.078),
    (0.04, 0.758, 0.11, 0.076, 0.1),
    (-0.1, 0.77, 0.14, 0.083, 0.155),
    (-0.23, 0.785, 0.155, 0.088, 0.185),
    (-0.35, 0.8, 0.13, 0.084, 0.14),
    (-0.45, 0.82, 0.088, 0.07, 0.085),
]
# Skull with the upper jaw, from the back of the head to the snout: y, center z, half-width, top, bottom. Small and
# narrow, sloping down to a pointed snout.
SKULL_PROFILE = [
    (-0.84, 1.52, 0.04, 0.04, 0.03),
    (-0.89, 1.525, 0.06, 0.056, 0.05),
    (-0.96, 1.513, 0.064, 0.054, 0.046),
    (-1.03, 1.495, 0.054, 0.042, 0.036),
    (-1.1, 1.474, 0.042, 0.032, 0.026),
    (-1.16, 1.456, 0.03, 0.024, 0.018),
    (-1.21, 1.444, 0.014, 0.013, 0.01),
]
# Lower jaw from the hinge to the tip: long and slender.
JAW_PROFILE = [
    (-0.89, 1.448, 0.05, 0.012, 0.03),
    (-0.96, 1.44, 0.052, 0.012, 0.03),
    (-1.04, 1.428, 0.042, 0.011, 0.025),
    (-1.11, 1.417, 0.032, 0.009, 0.019),
    (-1.18, 1.408, 0.016, 0.006, 0.011),
]
TRUNK_SHAPE = K.Profile(TRUNK)
SKULL_SHAPE = K.Profile(SKULL_PROFILE)
JAW_SHAPE = K.Profile(JAW_PROFILE)


def neck_at(t: float) -> tuple:
    """Center, direction, back (dorsal) normal and radius of the neck at t (0 in the chest .. 1 in the skull)."""
    c = K.path_point(NECK_PATH, t)
    d = (K.path_point(NECK_PATH, min(t + 0.02, 1.0)) - K.path_point(NECK_PATH, max(t - 0.02, 0.0))).normalized()
    back = Vector((0, d.z, -d.y)).normalized()
    r = K.catmull([[x] for x in NECK_RADII], t)[0]
    return c, d, back, r


def neck_point(t: float, a: float, out: float = 0.0) -> Vector:
    """Point on the neck at t and angle a (0 = left side, 90 = the back/top, 270 = the throat), pushed out by `out`."""
    c, _d, back, r = neck_at(t)
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    return c + X * ca * (r + out) + back * sa * (r + out)


def sac_point(u: float, a: float, out: float = 0.0) -> Vector:
    """Point on the sac at u (-1 bottom .. 1 top, along the neck) and angle a (0 = left, 90 = out of the throat)."""
    w, length, depth = SAC_R
    e = math.sqrt(max(1.0 - u * u, 0.0)) ** 0.85
    full = 1.0 + 0.16 * (0.5 - 0.5 * u)  # fuller toward the lower end, like a hanging pouch
    pinch = 1.0 - sum(0.1 * math.exp(-(((u - b) / 0.09) ** 2)) for b in SAC_BANDS)
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    x = math.copysign(abs(ca) ** 0.9, ca) * (w * e * full * pinch + out)
    z = math.copysign(abs(sa) ** 0.9, sa) * (depth * e * full * pinch + out)
    return SAC_C + N3_DIR * (u * length) + X * x + N3_FRONT * z


def blend(sk: K.Skin, verts: list, a: str, b: str, weight) -> list:
    """Weights each vertex between bones a and b (weight(v) = b's share, 0..1)."""
    ia, ib = RIG.index[a], RIG.index[b]
    for v in verts:
        w = min(max(weight(v), 0.0), 1.0)
        v[sk.dl].clear()
        if w < 1.0:
            v[sk.dl][ia] = 1.0 - w
        if w > 0.0:
            v[sk.dl][ib] = w
    return verts


def slab(sk: K.Skin, top: list, bottom: list, mi: int) -> list:
    """A closed slab between two grids of points (rows of the same length)."""
    top_v = [[sk.bm.verts.new(p) for p in row] for row in top]
    bot_v = [[sk.bm.verts.new(p) for p in row] for row in bottom]
    return K.close_grid(sk, top_v, bot_v, mi)


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: K.Skin) -> None:
    n = 18
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.006, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # Ribs over the deep chest.
    for _side, s in K.SIDES:
        for y in (-0.3, -0.23, -0.16, -0.09):
            pts = [TRUNK_SHAPE.surface(y + 0.012 * k, 25 - 26 * k if s > 0 else 155 + 26 * k, 0.004) for k in range(5)]
            sk.auto(K.tube_path(sk, pts, [0.012, 0.014, 0.013, 0.011, 0.007], 6, 6, K.SINEW), ["Spine", "Chest"])
    # Dorsal plates from the withers to the rump, the rear edge of each lifting off.
    ys = [-0.46, -0.35, -0.24, -0.13, -0.02, 0.09, 0.2, 0.31, 0.42, 0.52]
    count = len(ys) - 1
    for i, (y0, y1) in enumerate(itertools.pairwise(ys)):
        width = 40 + 12 * math.sin(math.pi * i / (count - 1))
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0 - 0.02, y1 + 0.03, 90 - width, 90 + width, 0.006, 0.02, K.CHITIN, 5, 3, 0.014),
            TRUNK_BONES,
            8.0,
        )
    # Side plates over the shoulders (where the neck rises) and the haunches.
    for _side, s in K.SIDES:
        a0, a1 = (-10, 40) if s > 0 else (140, 190)
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, -0.4, -0.16, a0, a1, 0.012, 0.02, K.CHITIN, 4, 3, 0.014), ["Spine", "Chest"], 8.0
        )
        a0, a1 = (-25, 42) if s > 0 else (138, 205)
        sk.rigid(K.shell(sk, TRUNK_SHAPE, 0.28, 0.5, a0, a1, 0.008, 0.018, K.CHITIN, 4, 3, 0.012), "Hips")
    # Belly plates under the chest.
    sk.auto(K.shell(sk, TRUNK_SHAPE, -0.32, -0.06, 240, 300, 0.004, 0.012, K.CHITIN, 4, 3, 0.006), TRUNK_BONES, 8.0)


def build_neck(sk: K.Skin) -> None:
    rings = []
    n = 24
    for i in range(n + 1):
        t = i / n
        c, d, _back, r = neck_at(t)
        rings.append(K.section(c, d, r, r, r, 14, 0.004, i * 1.1))
    sk.auto(sk.loft(rings, K.SINEW), NECK_BONES)
    # Ridged plates along the top of the neck, overlapping like scales (each one's lower end lifting off over the
    # next), a keel along the middle of each.
    ts = [0.1 + 0.85 * k / 9 for k in range(10)]
    for i, (t0, t1) in enumerate(itertools.pairwise(ts)):
        span = 70 - 18 * i / 8
        top, bot = [], []
        for v in range(4):
            tv = t1 + 0.03 - (t1 - t0 + 0.05) * v / 3  # from the upper end down
            row_t, row_b = [], []
            for k in range(7):
                u = k / 6
                a = 90 - span + 2 * span * u
                edge = math.sin(math.pi * u) ** 0.5
                lift = 0.012 * (v / 3) * edge
                keel = 0.022 * math.exp(-(((u - 0.5) / 0.12) ** 2)) * (0.4 + 0.6 * v / 3)
                row_t.append(neck_point(tv, a, 0.004 + lift + 0.016 * edge + keel))
                row_b.append(neck_point(tv, a, 0.004 + lift))
            top.append(row_t)
            bot.append(row_b)
        sk.auto(slab(sk, top, bot, K.CHITIN), NECK_BONES, 8.0)
        # A hooked spine on each plate's keel, pointing back down the neck, bigger toward the shoulders.
        tm = t0 + (t1 - t0) * 0.6
        c, d, back, r = neck_at(tm)
        base = neck_point(tm, 90, 0.025)
        length = 0.05 + 0.05 * (1 - i / 8)
        tip = base + (back - d * 0.4).normalized() * length
        sk.auto(sk.cone(base + d * 0.012, tip, 0.018 + 0.008 * (1 - i / 8), 5, K.BONE, 0.55), NECK_BONES, 8.0)
    # Rings of gristle down the throat below the sac (the windpipe).
    for t in (0.2, 0.3, 0.4, 0.5):
        pts = [neck_point(t, a, 0.002) for a in range(200, 341, 35)]
        sk.auto(K.tube_path(sk, pts, [0.008, 0.012, 0.013, 0.012, 0.008], 5, 6, K.SINEW), NECK_BONES)
    # A heavy collar plate on each side where the neck leaves the shoulders.
    for _side, s in K.SIDES:
        sk.auto(
            sk.sphere(
                (s * 0.075, -0.42, 0.9), 0.07, 10, 5, scale=(0.55, 1.5, 1.0), rot=rx(-38) @ rz(s * 12), mi=K.CHITIN
            ),
            ["Chest", "Neck"],
            8.0,
        )


def build_sac(sk: K.Skin, glands: K.Skin) -> None:
    rings = []
    n = 14
    for i in range(1, n):
        u = -math.cos(math.pi * i / n)
        rings.append([sac_point(u, 360 * k / 16 - 90) for k in range(16)])
    glands.rigid(glands.loft(rings, 0), "Sac")
    # Chitin straps across it in the pinches, sunk into the neck at both ends.
    for k, u in enumerate(SAC_BANDS):
        pts = [sac_point(u + 0.03 * math.sin(math.radians(a) * 2 + k), a, 0.003) for a in range(-50, 231, 35)]
        radii = [0.007, 0.009, 0.01, 0.011, 0.011, 0.011, 0.01, 0.009, 0.007]
        sk.rigid(K.tube_path(sk, pts, radii, 6, 10, K.CHITIN, 2.2, 0.0, N3_DIR), "Sac")
    # Dark veins over the sides.
    for _side, s in K.SIDES:
        for u0, du in ((-0.75, 0.5), (-0.2, 0.45), (0.25, 0.4)):
            pts = [sac_point(u0 + du * f, (10 + 40 * f) if s > 0 else (170 - 40 * f), 0.001) for f in (0, 0.35, 0.7, 1)]
            sk.rigid(K.tube_path(sk, pts, [0.009, 0.008, 0.007, 0.005], 5, 5, K.SINEW), "Sac")
    # A fleshy cup it bulges out of: sinew over its back and sides, the front edge scalloped between the straps.
    for _side, s in K.SIDES:
        top, bot = [], []
        for i in range(9):
            u = -0.96 + 1.92 * i / 8
            edge = 4 + 16 * abs(math.sin(math.pi * (u + 1) * 1.5 + 0.4))
            row_t, row_b = [], []
            for k in range(5):
                a = -80 + (80 + edge) * k / 4
                if s < 0:
                    a = 180 - a
                rim = math.sin(math.pi * k / 4) ** 0.5
                row_t.append(sac_point(u, a, 0.002 + 0.014 * rim))
                row_b.append(sac_point(u, a, -0.002))
            top.append(row_t)
            bot.append(row_b)
        sk.rigid(slab(sk, top, bot, K.SINEW), "Sac")


def build_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Skull and upper jaw (the underside is the roof of the mouth).
    rings = []
    n = 12
    for i in range(n + 1):
        c, w, top, bot = SKULL_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 14, 0.003, 3 + i))
    _mouth_faces(sk.rigid(sk.loft(rings, K.CHITIN), "Head"), SKULL_SHAPE, below=True)
    # Lower jaw.
    rings = []
    for i in range(10):
        c, w, top, bot = JAW_SHAPE.at(i / 9)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 12, 0.002, 9 + i))
    _mouth_faces(sk.rigid(sk.loft(rings, K.CHITIN), "Jaw"), JAW_SHAPE, below=False)
    # Brow plates over the eyes and the skull, edges lifting off.
    for y0, y1, a in ((-0.86, -0.98, 70), (-0.96, -1.09, 66)):
        sk.rigid(K.shell(sk, SKULL_SHAPE, y0, y1, 90 - a, 90 + a, 0.004, 0.016, K.CHITIN, 6, 3, 0.006), "Head")
    # Swept-back bone spines from the back of the skull: a long pair and a short pair (the crest).
    for _side, s in K.SIDES:
        for base, mid, tip, r in (
            ((0.03, -0.9, 1.565), (0.05, -0.82, 1.62), (0.07, -0.7, 1.68), 0.022),
            ((0.05, -0.93, 1.55), (0.08, -0.88, 1.58), (0.105, -0.81, 1.6), 0.016),
        ):
            pts = [K.mirror(Vector(p), s) for p in (base, mid, tip)]
            sk.rigid(K.tube_path(sk, pts, [r, r * 0.7, 0.004], 6, 6, K.BONE), "Head")
        # Eyes: a slanted slit and a small bead on each side, under the brow.
        for y, a, r, sc in ((-1.0, 34, 0.017, (0.6, 1.6, 0.7)), (-0.96, 46, 0.011, (1, 1, 1))):
            p = SKULL_SHAPE.surface(y, a if s > 0 else 180 - a, -0.003)
            eyes.rigid(eyes.sphere(p, r, 8, 4, scale=sc, rot=rz(s * 18) @ rx(-10)), "Head")
    # Needle teeth along both jaws, longer fangs at the front.
    rnd = random.Random(11)
    for _side, s in K.SIDES:
        for k in range(8):
            t = k / 7
            y = -0.94 - 0.24 * t
            length = 0.022 + 0.018 * t + rnd.uniform(-0.004, 0.005)
            c, w, _top, bot = SKULL_SHAPE.at((SKULL_PROFILE[0][0] - y) / (SKULL_PROFILE[0][0] - SKULL_PROFILE[-1][0]))
            base = c + Vector((s * w * 0.75, 0, -bot * 0.7))
            if y > -1.17:
                sk.rigid(sk.cone(base, base + Vector((s * 0.003, -0.006, -length)), 0.007, 4, K.BONE), "Head")
            if y > -1.16:
                c, w, top, _bot = JAW_SHAPE.at((JAW_PROFILE[0][0] - y) / (JAW_PROFILE[0][0] - JAW_PROFILE[-1][0]))
                base = c + Vector((s * w * 0.72, -0.012, top * 0.5))
                sk.rigid(sk.cone(base, base + Vector((s * 0.002, -0.005, length * 0.8)), 0.006, 4, K.BONE), "Jaw")
    # Cheeks: a sinew web from the skull's edge to the jaw's behind the teeth, weighted from Head (top) to Jaw
    # (bottom), so it stretches into a membrane when the jaw gapes.
    for _side, s in K.SIDES:
        outer, inner = [], []
        for i in range(5):
            top, bottom = cheek_edges(-0.89 - 0.075 * i / 4, s)
            outer.append([top.lerp(bottom, k / 4) for k in range(5)])
            inner.append([top.lerp(bottom, k / 4) - Vector((s * 0.008, 0, 0)) for k in range(5)])
        blend(sk, slab(sk, outer, inner, K.SINEW), "Head", "Jaw", cheek_weight)


def cheek_edges(y: float, s: float) -> tuple:
    """Where a cheek meets the skull (top) and the jaw (bottom) at y."""
    cs, ws, _ts, bs = SKULL_SHAPE.at((SKULL_PROFILE[0][0] - y) / (SKULL_PROFILE[0][0] - SKULL_PROFILE[-1][0]))
    cj, wj, tj, _bj = JAW_SHAPE.at((JAW_PROFILE[0][0] - y) / (JAW_PROFILE[0][0] - JAW_PROFILE[-1][0]))
    return Vector((s * ws * 0.86, y, cs.z - bs * 0.55)), Vector((s * wj * 0.92, y, cj.z + tj * 0.2))


def cheek_weight(v) -> float:
    """The Jaw's share of a cheek vertex: 0 at the skull's edge .. 1 at the jaw's."""
    top, bottom = cheek_edges(v.co.y, 1.0)
    return (top.z - v.co.z) / (top.z - bottom.z)


def _mouth_faces(verts: list, shape: K.Profile, below: bool) -> None:
    """Marks the faces inside the mouth (the skull's underside or the jaw's top) as Mouth, by their outward normal."""
    y0, y1 = shape.rows[0][0], shape.rows[-1][0]
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        c = f.calc_center_median()
        n = f.normal if f.normal.dot(c - shape.at((y0 - c.y) / (y0 - y1))[0]) >= 0 else -f.normal
        if ((n.z < -0.5) if below else (n.z > 0.5)) and c.y < -0.9:
            f.material_index = K.MOUTH


def build_tail(sk: K.Skin) -> None:
    pts = [Vector((0, 0.44, 0.74)), Vector((0, 0.56, 0.72)), Vector((0, 0.7, 0.665)), Vector((0, 0.84, 0.58))]
    radii = [0.06, 0.042, 0.026, 0.012]
    sk.auto(K.tube_path(sk, pts, radii, 10, 10, K.SINEW), ["Hips", "Tail1", "Tail2"])
    for k in range(5):
        t = 0.12 + 0.72 * k / 4
        c = K.path_point(pts, t)
        d = K.path_point(pts, t + 0.02) - K.path_point(pts, t - 0.02)
        r = K.catmull([[x] for x in radii], t)[0]
        bone = "Tail1" if t < 0.5 else "Tail2"
        rings = [K.section(c + d.normalized() * o, d, r + 0.008, r + 0.012, r + 0.003, 10) for o in (-0.014, 0.014)]
        sk.rigid(sk.loft(rings, K.CHITIN), bone)
    end = K.path_point(pts, 1.0)
    sk.rigid(sk.cone(end - Vector((0, 0.03, -0.015)), end + Vector((0, 0.07, -0.04)), 0.012, 5, K.BONE), "Tail2")


def build_legs(sk: K.Skin) -> None:
    for leg, pts, body in LEGS:
        hind = leg == "Hind"
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            # Upper leg: a lean haunch / shoulder muscle, into the body.
            top = j[0] + Vector((s * -0.03, 0.0, 0.06))
            radii = [0.095, 0.09, 0.06, 0.042] if hind else [0.085, 0.078, 0.052, 0.04]
            mid = j[0].lerp(j[1], 0.45) + (Vector((0, 0.025, 0)) if hind else Vector((0, -0.02, 0)))
            sk.auto(K.tube_path(sk, [top, mid, j[1]], radii, 10, 6, K.SINEW, 1.0, 0.004), [body, up, low])
            # Lower leg: long and thin, a chitin greave on its front (hind: the shin points back).
            mid = j[1].lerp(j[2], 0.5)
            sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.04, 0.03, 0.026], 8, 6, K.SINEW), [up, low, foot])
            facing = Vector((0, -1, 0.2)) if hind else Vector((0, 1, 0.1))
            sk.rigid(
                K.limb_plate(
                    sk,
                    j[1].lerp(j[2], 0.12),
                    j[1].lerp(j[2], 0.85),
                    0.03,
                    -70,
                    70,
                    0.012,
                    K.CHITIN,
                    -facing if hind else facing,
                ),
                low,
            )
            # Knee / elbow knob with a spur pointing back (front) or forward and up (hind).
            knob = j[1] + (Vector((0, -0.012, 0)) if hind else Vector((0, 0.015, 0)))
            sk.rigid(sk.sphere(knob, 0.034, 8, 4, mi=K.CHITIN), low)
            spur = Vector((0, -0.07, 0.04)) if hind else Vector((0, 0.08, 0.035))
            sk.rigid(sk.cone(knob, knob + spur, 0.016, 5, K.BONE), low)
            # Foot: the metatarsal (hind: long) to the ball, three long toes with hooked claws.
            sk.auto(
                K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.026, 0.024, 0.027], 8, 4, K.SINEW), [low, foot]
            )
            sk.rigid(sk.sphere(j[3], 0.03, 8, 4, scale=(1.0, 1.2, 0.7), mi=K.SINEW), foot)
            for k, ang in enumerate((-24, 0, 24)):
                toe = Vector((math.sin(math.radians(ang)) * -s, -1, 0)).normalized()
                knuckle = j[3] + toe * 0.055 + Vector((0, 0, 0.012))
                tip = j[3] + toe * (0.1 if k == 1 else 0.085) + Vector((0, 0, -0.02))
                sk.rigid(K.tube_path(sk, [j[3], knuckle, tip - toe * 0.02], [0.015, 0.012, 0.01], 6, 4, K.SINEW), foot)
                sk.rigid(
                    sk.cone(tip - toe * 0.025 + Vector((0, 0, 0.01)), tip + Vector((0, 0, -0.01)), 0.009, 5, K.BONE),
                    foot,
                )
            # Dewclaw spur at the back of the ankle.
            back = Vector((0, 0.05, 0.03)) if not hind else Vector((0, 0.06, 0.02))
            sk.rigid(sk.cone(j[2] + Vector((0, 0.01, -0.02)), j[2] + back, 0.011, 5, K.BONE), low if hind else foot)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk)
    build_neck(sk)
    build_sac(sk, glands)
    build_head(sk, eyes)
    build_tail(sk)
    build_legs(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


class Pose(K.Pose):
    """The kit's pose plus a scale per bone (the sac swelling), as (width, depth, length) in the Sac bone's axes:
    its x is the world's x, its y points out of the throat, its z runs along the neck."""

    def __init__(self, rig: K.Rig, offset=(0, 0, 0)):
        super().__init__(rig, offset)
        self.scale: dict = {}

    def grow(self, bone: str, width: float, depth: float, length: float) -> "Pose":
        self.scale[bone] = Vector((width, depth, length))
        return self


def apply(arm: bpy.types.Object, pose: Pose) -> None:
    K.apply(arm, pose)
    for pb in arm.pose.bones:
        pb.scale = pose.scale.get(pb.name, Vector((1, 1, 1)))


def rest_pose(arm: bpy.types.Object) -> None:
    for pb in arm.pose.bones:
        pb.scale = (1, 1, 1)
    K.rest_pose(arm)


def bake_clips(arm: bpy.types.Object, clips: dict) -> None:
    """K.bake_clips with the Sac's scale keyed too."""
    ad = arm.animation_data_create()
    for name, (frames, fn) in clips.items():
        ad.action = None
        for f in range(frames + 1):
            apply(arm, fn(f / frames))
            for pb in arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                if pb.name == "Body":
                    pb.keyframe_insert("location", frame=f, group=pb.name)
                if pb.name == "Sac":
                    pb.keyframe_insert("scale", frame=f, group=pb.name)
        act = ad.action
        act.name = name
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        track.mute = True
        ad.action = None
    rest_pose(arm)


def swell(p: Pose, amount: float, length: float | None = None) -> None:
    """The sac at `amount` times its size across (width and depth), `length` along the neck (default: less)."""
    p.grow("Sac", amount, amount, length if length is not None else 1.0 + (amount - 1.0) * 0.4)


def tail(p: Pose, sway: float, lift: float) -> None:
    p.set("Tail1", rz(sway) @ rx(lift))
    p.set("Tail2", rz(sway * 0.7) @ rx(lift * 0.6))


def idle(t: float) -> Pose:
    """Breathing, the neck swaying slowly, the head turning to look around (left, back, right), the sac pulsing."""
    a = math.tau * t
    breath = math.sin(a)
    look = math.sin(a) * 0.7 + math.sin(2 * a + 0.6) * 0.3
    p = Pose(RIG, (0, 0, 0.006 * breath))
    p.set("Spine", rx(-0.8 * breath)).set("Chest", rx(-1.2 * breath))
    p.set("Neck", rx(2 * math.sin(a + 0.4)) @ rz(4 * math.sin(a)))
    p.set("Neck2", rx(-2 * math.sin(a + 0.4)) @ rz(4 * math.sin(a - 0.5)))
    p.set("Neck3", rx(1.5 * math.sin(2 * a)) @ rz(4 * math.sin(a - 1.0)))
    p.set("Head", rz(18 * look) @ rx(-3 + 4 * math.sin(2 * a + 1.3)) @ ry(-6 * look))
    p.set("Jaw", rx(2 + 4 * max(0.0, math.sin(3 * a + 0.4)) ** 2))
    swell(p, 1.0 + 0.07 * (0.5 + 0.5 * math.sin(3 * a)))
    tail(p, 7 * math.sin(a + 0.8), 2 * breath)
    return p


def run(t: float) -> Pose:
    """A skittish trot (legs at rest, the game steps them): two bobs per stride, the neck stretched forward and
    lower, the head level and twitching from side to side, the tail up."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = Pose(RIG, (0, 0, -0.02 + 0.02 * bob))
    p.set("Body", rx(2 * math.sin(2 * a)) @ ry(2.5 * math.sin(a)))
    p.set("Spine", rx(-2 * math.sin(2 * a + 0.8)) @ rz(3 * math.sin(a)))
    p.set("Chest", rx(1.5 * math.sin(2 * a + 0.8)))
    p.set("Neck", rx(18 + 3 * math.sin(2 * a + 0.4)) @ rz(-3 * math.sin(a)))
    p.set("Neck2", rx(8 - 2 * math.sin(2 * a + 0.9)))
    p.set("Neck3", rx(4 - 2 * math.sin(2 * a + 1.4)))
    twitch = math.sin(3 * a) * 0.6 + math.sin(5 * a + 1.0) * 0.4
    p.set("Head", rx(-24 + 3 * math.sin(2 * a + 1.8)) @ rz(10 * twitch))
    p.set("Jaw", rx(5 + 2 * math.sin(2 * a)))
    lag = 2 * a - 1.0
    p.set("Sac", rx(4 * math.sin(lag)))
    swell(p, 1.0 + 0.03 * math.sin(lag + 1.0))
    tail(p, 6 * math.sin(a - 0.6), 10 + 4 * math.sin(2 * a - 0.5))
    return p


ATTACK_FRAMES = 48  # 1.6 s
PEAK = 30 / ATTACK_FRAMES  # the scream's peak: frame 30 = 1.0 s


def attack(t: float) -> Pose:
    """The scream (1.6 s): from the start the neck rises to full height and arches back, the head tilts up and the sac
    swells (to the peak at frame 30); the jaw gapes from about frame 15 and is widest at the peak; it holds trembling
    for about a quarter second, then relaxes back to rest."""
    rise = K.smooth(t / PEAK) * (1 - K.smooth((t - 0.8) / 0.2))
    gape = K.smooth((t - 0.3) / (PEAK - 0.3)) * (1 - K.smooth((t - 0.78) / 0.18))
    sac = K.smooth(t / PEAK) ** 1.5 * (1 - K.smooth((t - 0.76) / 0.24))
    hold = K.smooth((t - PEAK + 0.06) / 0.06) * (1 - K.smooth((t - 0.8) / 0.08))
    shake = hold * math.sin(math.tau * (t - PEAK) * 14)
    p = Pose(RIG, (0, 0.03 * rise, 0.045 * rise))
    p.set("Body", rx(-6 * rise))
    p.set("Hips", rx(4 * rise))
    p.set("Chest", rx(-2 * rise))
    p.set("Neck", rx(-54 * rise))
    p.set("Neck2", rx(12 * rise))
    p.set("Neck3", rx(14 * rise + 1.5 * shake))
    p.set("Head", rx(-22 * rise - 8 * gape) @ rz(3 * shake))
    p.set("Jaw", rx(4 + 62 * gape + 2 * shake))
    swell(p, 1.0 + 0.8 * sac, 1.0 + 0.2 * sac)
    tail(p, 2 * shake, 16 * rise)
    return p


DIE_ROLL = 76  # degrees onto its left side
DIE_SHIFT = (0.2, -0.56)
DIE_NECK = (9, 5, 2)  # the neck curls toward the ground (its left after the roll)
DIE_HEAD = (0, 15)  # the head lies on its side  # where the Body ends up (sideways, down), so it rests on the ground


def die(t: float) -> Pose:
    """A jolt with the head thrown up (to 0.1), then the neck whips down and collapses onto the ground while the legs
    buckle and it rolls onto its left side (1.0); the jaw hangs open, the sac sags, the legs fold."""
    jolt = K.smooth(t / 0.1) * (1 - K.smooth((t - 0.1) / 0.15))
    whip = K.smooth((t - 0.08) / 0.3)
    k = K.smooth(t / 0.4)
    f = K.smooth((t - 0.15) / 0.65)
    p = Pose(RIG, (DIE_SHIFT[0] * f, 0.0, 0.02 * jolt + DIE_SHIFT[1] * K.smooth((t - 0.05) / 0.7)))
    p.set("Body", ry(DIE_ROLL * f) @ rx(-4 * jolt))
    p.set("Neck", rx(-18 * jolt + 30 * whip) @ rz(DIE_NECK[0] * f))
    p.set("Neck2", rx(-6 * jolt + 16 * whip) @ rz(DIE_NECK[1] * f))
    p.set("Neck3", rx(10 * whip) @ rz(DIE_NECK[2] * f))
    p.set("Head", rx(-20 * jolt + DIE_HEAD[0] * whip) @ ry(DIE_HEAD[1] * f))
    p.set("Jaw", rx(10 * jolt + 34 * k))
    swell(p, 1.0 - 0.25 * f, 1.0 - 0.1 * f)
    tail(p, 12 * f, -10 * k)
    for side, s in K.SIDES:
        # Front: elbows fold back, paws tuck; hind: knees fold forward under the body.
        out = (22 if s > 0 else 4) * f  # the lower side's legs lift off the ground
        p.set(f"Front{side}UpperLeg", rx(-50 * k) @ ry(s * out))
        p.set(f"Front{side}LowerLeg", rx(100 * k))
        p.set(f"Front{side}Foot", rx(-40 * k))
        p.set(f"Hind{side}UpperLeg", rx(45 * k) @ ry(s * out))
        p.set(f"Hind{side}LowerLeg", rx(-90 * k))
        p.set(f"Hind{side}Foot", rx(50 * k))
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (18, run),
    "Attack": (ATTACK_FRAMES, attack),
    "Die": (40, die),
}

# --- report -------------------------------------------------------------------------------------------


def posed_point(arm: bpy.types.Object, bone: str, p: Vector) -> Vector:
    pb = arm.pose.bones[bone]
    return arm.matrix_world @ pb.matrix @ arm.data.bones[bone].matrix_local.inverted() @ p


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


def lowest_parts(count: int = 14) -> list:
    """The bones whose posed vertices reach lowest (to check a pose stays above the ground)."""
    obj = bpy.data.objects["Creature"]
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    names = {g.index: g.name for g in obj.vertex_groups}
    low: dict = {}
    for v, src in zip(me.vertices, obj.data.vertices):
        g = names.get(max(src.groups, key=lambda e: e.weight).group, "?") if src.groups else "?"
        low[g] = min(low.get(g, 9.0), v.co.z)
    ev.to_mesh_clear()
    return sorted((round(z, 3), n) for n, z in low.items())[:count]


def fmt(v: Vector) -> tuple:
    return tuple(round(x, 3) for x in v)


def mouth(arm: bpy.types.Object) -> Vector:
    """The middle of the open mouth: between the snout's underside and the jaw's tip, a third of the way in."""
    upper = posed_point(arm, "Head", Vector((0, -1.12, 1.44)))
    lower = posed_point(arm, "Jaw", Vector((0, -1.1, 1.42)))
    return (upper + lower) / 2


def report(arm: bpy.types.Object) -> None:
    rest_pose(arm)
    m = arm.data.bones["Sac"].matrix_local.to_3x3()
    print("SAC axes x", fmt(m.col[0]), "y", fmt(m.col[1]), "z", fmt(m.col[2]))
    head_c = SKULL_SHAPE.at(0.35)[0]
    print("POINT head rest (Head)", fmt(head_c), "Head bone head", fmt(SKULL))
    print("POINT mouth rest (Head/Jaw)", fmt(mouth(arm)))
    print("POINT sac center rest (Sac)", fmt(SAC_C))
    print("BOUNDS rest", bounds())
    apply(arm, attack(PEAK))
    bpy.context.view_layer.update()
    print("POINT sac center peak (Sac)", fmt(posed_point(arm, "Sac", SAC_C)))
    print("POINT mouth peak (Head/Jaw)", fmt(mouth(arm)))
    print("POINT head peak (Head)", fmt(posed_point(arm, "Head", head_c)))
    print("BOUNDS peak", bounds())
    for name, pose in (("die", die(1.0)), ("run", run(0.25)), ("idle", idle(0.25))):
        apply(arm, pose)
        bpy.context.view_layer.update()
        print("POSE", name, "bounds", bounds(), "lowest", lowest_parts())
    rest_pose(arm)
    # Every leg bent at rest: the knee's distance from the hip-ankle line.
    for leg, pts, _b in LEGS:
        print("BEND", leg, round(K.seg_dist(pts[1], pts[0], pts[2]), 3))


# --- preview ----------------------------------------------------------------------------------------


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.4, 1.0, 0))
    shots = []
    target = (0, -0.3, 0.85)
    rest_pose(arm)
    for view, zoom in (("iso", 0.4), ("hero", 0.45), ("back", 0.5), ("iso", 1.4)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((4.2, -0.3, 1.0)), (0, -0.3, 0.9), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.9, -2.1, 1.75)), (0, -0.95, 1.4), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    for name, pose in (
        ("idle", idle(0.25)),
        ("run", run(0.25)),
        ("attack15", attack(0.32)),
        ("attack30", attack(PEAK)),
        ("die", die(1.0)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.45)
        shots.append(path)
    apply(arm, attack(PEAK))
    bpy.context.view_layer.update()
    path = OUT / "wip" / f"{tag}_scream_side.png"
    C.render_from(path, Vector((4.4, -0.3, 1.2)), (0, -0.3, 1.1), 50, 32, 512)
    shots.append(path)
    path = OUT / "wip" / f"{tag}_scream_iso.png"
    C.render(path, view="iso", samples=32, size=512, target=target, zoom=0.45)
    shots.append(path)
    path = OUT / "wip" / f"{tag}_scream_head.png"
    C.render_from(path, Vector((1.6, -1.0, 1.95)), (0, -0.45, 1.75), 50, 32, 512)
    shots.append(path)
    path = OUT / "wip" / f"{tag}_scream_mouth.png"
    C.render_from(path, Vector((1.5, -0.75, 1.9)), (0, -0.42, 1.8), 50, 32, 512)
    shots.append(path)
    apply(arm, die(1.0))
    bpy.context.view_layer.update()
    path = OUT / "wip" / f"{tag}_die_side.png"
    C.render_from(path, Vector((4.0, -0.6, 0.6)), (0, -0.3, 0.25), 50, 24, 512)
    shots.append(path)
    rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    report(arm)
    if MODE == "stats":
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "shrieker_procedural.blend")
        C.export_glb(OUT / "shrieker_draft.glb")


main()
