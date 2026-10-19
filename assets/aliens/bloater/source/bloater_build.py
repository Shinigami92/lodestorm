"""Bloater: a tier 4 raider of the hive that bursts. A huge, taut, veined bladder slung between six long, thin, spidery
legs with high knees, a small armored head hanging low at its front; the bladder glows through its veins and patches
(see docs/GAME_DESIGN.md, Alien look), rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/bloater/source/bloater_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/bloater/source/bloater_build.py final      # renders + bloater_procedural.blend

Everything it writes goes to tmp/assets/bloater/; bloater_bake.py turns bloater_procedural.blend into the game asset.

Layout (Blender Z-up meters; the bloater faces -Y, its left is +X; the game turns the model by 180 degrees). Feet on
the ground at the origin, the origin under the middle of the body. The bladder is 1.4 m across, its top at 1.7 m and
its belly at 0.5 m; the knees stand above its middle (about 1.6 m), the feet reach far out (about 2.9 m across).

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips with the hind legs, Spine with the
mid legs and Sac (the bladder: clips scale it to throb, swell and burst), Chest with the front legs, Neck, Head, Jaw
(the mandibles' base) with LeftMandible and RightMandible. The trunk is a short sinewy core inside the bladder that
carries the legs; it only shows once the bladder has burst. Legs (<Front|Mid|Hind><Side>UpperLeg, LowerLeg, Foot):
the game moves them by IK (the femur rising out of the bladder to a high knee, the long tibia down to the ankle, the
Foot is the short tarsus with its claws), so the clips leave them at rest; only "Die" folds them. Meshes: "Creature"
(one skinned object: the core weighted to the nearest bones; the bladder, its plates, the head, mandibles and leg
segments rigid), "Eyes" (constant emissive, two pairs of small beads) and "Glands" (constant emissive: the veins and
patches on the bladder, skinned to Sac; the game flares it with the eyes).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: a slow double throb of the
bladder, the head swaying), "Run" (loop: a slow wobbling lumber, the bladder sloshing behind the trunk; the legs come
from the game), "Attack" (once, 0.5 s: the pre-burst, the bladder swells to x1.3 and shudders while the body sinks and
the legs brace; it ends at its biggest) and "Die" (once: the bladder pops to x1.25 and bursts into a wrinkled husk of
about x0.35 by 0.15 s, then the legs buckle and fold, it drops to the ground and the husk sags over the core).
The clips key every bone's rotation, the Body's location and the Sac's scale (own bake, the kit's keys no scale).
"""

import functools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "bloater"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Matrix, Vector, noise

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Bloater"
FPS = 30
GLAND_GLOW = 2.0  # the bladder's veins and patches (eyes 8 in the previews)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.95))
CHEST = Vector((0, -0.3, 0.93))
NECK = Vector((0, -0.6, 0.84))
SKULL = Vector((0, -0.8, 0.68))
SNOUT = Vector((0, -1.05, 0.575))
JAW = Vector((0, -0.98, 0.56))
# The bladder: an egg-shaped sac around the core, fuller toward the rear; Sac scales it from the core's middle.
SAC_BASE = Vector((0, 0.05, 0.97))
SAC_C = Vector((0, 0.05, 1.05))
SAC_R = (0.7, 0.74, 0.65, 0.55)  # half-width, half-length, top, bottom
LUMPS = 0.02  # how far the taut skin bulges in and out
# Leg joints per side (x for the left side): hip, knee, ankle, pad (the claws' base on the ground).
LEGS = {
    "Front": [
        Vector((0.17, -0.42, 0.9)),
        Vector((0.7, -0.98, 1.55)),
        Vector((0.98, -1.42, 0.09)),
        Vector((1.02, -1.52, 0.03)),
    ],
    "Mid": [
        Vector((0.21, -0.08, 0.93)),
        Vector((0.98, -0.14, 1.62)),
        Vector((1.38, -0.2, 0.09)),
        Vector((1.47, -0.22, 0.03)),
    ],
    "Hind": [
        Vector((0.19, 0.26, 0.93)),
        Vector((0.8, 0.76, 1.56)),
        Vector((1.08, 1.16, 0.09)),
        Vector((1.14, 1.25, 0.03)),
    ],
}
LEG_PARENT = {"Front": "Chest", "Mid": "Spine", "Hind": "Hips"}
MANDIBLE = [Vector((0.07, -1.0, 0.55)), Vector((0.1, -1.07, 0.53)), Vector((0.075, -1.14, 0.51))]
MANDIBLE_TIP = Vector((0.03, -1.17, 0.505))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.3, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.15, 0)), "Root"),
    ("Hips", BODY, Vector((0, 0.42, 0.95)), "Body"),
    ("Spine", BODY, CHEST, "Body"),
    ("Chest", CHEST, NECK, "Spine"),
    ("Neck", NECK, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW, Vector((0, -1.1, 0.52)), "Head"),
    ("Sac", SAC_BASE, SAC_BASE + Vector((0, 0, 0.6)), "Spine"),
]
for _side, _s in K.SIDES:
    BONES.append((f"{_side}Mandible", K.mirror(MANDIBLE[0], _s), K.mirror(MANDIBLE[2], _s), "Jaw"))
    for _leg, _pts in LEGS.items():
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), LEG_PARENT[_leg]),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest", "Neck"]


# --- mesh -------------------------------------------------------------------------------------------


def even_rows(y0: float, y1: float, rows: list) -> list:
    """Profile rows (center z, half-width, top, bottom) spread evenly from y0 to y1."""
    n = len(rows) - 1
    return [(y0 + (y1 - y0) * i / n, *r) for i, r in enumerate(rows)]


# The core inside the bladder from the rump forward: center z, half-width, top, bottom.
CORE = K.Profile(
    even_rows(
        0.4,
        -0.64,
        [
            (0.95, 0.06, 0.05, 0.05),
            (0.95, 0.16, 0.11, 0.1),
            (0.95, 0.21, 0.14, 0.12),
            (0.95, 0.22, 0.14, 0.12),
            (0.945, 0.21, 0.135, 0.12),
            (0.93, 0.19, 0.12, 0.11),
            (0.91, 0.16, 0.11, 0.1),
            (0.875, 0.12, 0.09, 0.09),
        ],
    )
)
# Skull from the back of the head to its blunt front, sloping down: center z, half-width, top, bottom.
SKULL_SHAPE = K.Profile(
    even_rows(
        -0.76,
        -1.06,
        [
            (0.69, 0.09, 0.07, 0.06),
            (0.675, 0.14, 0.088, 0.075),
            (0.655, 0.165, 0.096, 0.08),
            (0.635, 0.17, 0.094, 0.08),
            (0.612, 0.16, 0.084, 0.075),
            (0.59, 0.13, 0.07, 0.065),
            (0.568, 0.075, 0.045, 0.045),
        ],
    )
)


def sac_shape(y: float) -> tuple:
    """Center, half-width, top and bottom of the bladder's cross-section at y: an egg, fuller and lower at the rear."""
    cx, cy, cz = SAC_C
    w, ry_, top, bot = SAC_R
    u = min(max((y - cy) / ry_, -1.0), 1.0)
    e = math.sqrt(max(1.0 - u * u, 0.0)) ** 0.8
    swell = 1.0 + 0.06 * u
    return Vector((cx, y, cz - 0.03 * u)), w * e * swell, top * e * swell, bot * e * swell


def sac_point(y: float, a: float, out: float = 0.0) -> Vector:
    """Point on the bladder at y and angle a (0 = left side, 90 = top, 270 = belly), pushed out by `out`."""
    c, w, top, bot = sac_shape(y)
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    k = crease(a)
    x = math.copysign(abs(ca) ** 0.92, ca)
    z = math.copysign(abs(sa) ** 0.92, sa)
    h = top if sa > 0 else bot
    skin = c + Vector((x * w * k, 0, z * h * k))
    lump = (skin - SAC_C).normalized() * LUMPS * noise.noise(skin * 3.5 + Vector((4.1, 2.3, 7.7)))
    return skin + lump + Vector((x * out, 0, z * out))


def crease(a: float) -> float:
    """The bladder's two lobes: a crease down the top (under the scales) and a shallower one along the belly."""

    def near(c: float, w: float) -> float:
        return math.exp(-((((a - c + 180) % 360 - 180) / w) ** 2))

    return 1.0 - 0.07 * near(90, 13) - 0.04 * near(270, 20)


def side_angle(a: float, s: float) -> float:
    """An angle given for the left side, mirrored to side s."""
    return a if s > 0 else 180.0 - a


def sac_slab(sk: K.Skin, y0, y1, a0, a1, out: float, thick: float, mi: int, nu: int, nv: int, lift: float = 0.0):
    """Slab hugging the bladder between y0..y1 and angles a0(v)..a1(v) (functions of v = 0..1 along y); its rear edge
    lifts off by `lift` like a scale."""
    top_rows, bot_rows = [], []
    for i in range(nv + 1):
        v = i / nv
        y = y0 + (y1 - y0) * v
        lo, hi = a0(v), a1(v)
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            a = lo + (hi - lo) * u
            edge = math.sin(math.pi * u) ** 0.5
            o = out + lift * v * v * edge
            row_t.append(sk.bm.verts.new(sac_point(y, a, o + thick * edge * (0.5 + 0.5 * math.sin(math.pi * v)))))
            row_b.append(sk.bm.verts.new(sac_point(y, a, o)))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return K.close_grid(sk, top_rows, bot_rows, mi)


def patch(sk: K.Skin, y: float, a: float, ly: float, la: float, out: float, thick: float, mi: int) -> list:
    """Oval slab on the bladder centered at y, a (half-length ly in y, half-width la in degrees)."""

    def lo(v: float) -> float:
        return a - la * math.sin(math.pi * (0.06 + 0.88 * v)) ** 0.6

    def hi(v: float) -> float:
        return a + la * math.sin(math.pi * (0.06 + 0.88 * v)) ** 0.6

    return sac_slab(sk, y - ly, y + ly, lo, hi, out, thick, mi, 4, 4)


def cap(sk: K.Skin, ring: list, pole: Vector, mi: int) -> list:
    """Closes a ring of verts with a fan around a pole vertex."""
    p = sk.bm.verts.new(pole)
    n = len(ring)
    for k in range(n):
        sk.bm.faces.new((ring[k], ring[(k + 1) % n], p)).normal_update()
    return sk._tag(ring + [p], mi)


# --- parts ------------------------------------------------------------------------------------------


def build_core(sk: K.Skin) -> None:
    """The short trunk inside the bladder carrying the legs: sinew under a ventral plate and plates around the leg
    sockets (they only show once the bladder has burst)."""
    n = 12
    rings = []
    for i in range(n + 1):
        c, w, top, bot = CORE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 12, 0.004, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    sk.auto(K.shell(sk, CORE, -0.6, 0.36, 235, 305, 0.005, 0.022, K.CHITIN, 4, 5, 0.0), TRUNK_BONES, 8.0)
    for y0, y1 in ((-0.52, -0.24), (-0.22, 0.08), (0.1, 0.36)):
        for _side, s in K.SIDES:
            a0, a1 = (-25, 35) if s > 0 else (145, 205)
            sk.auto(K.shell(sk, CORE, y0, y1, a0, a1, 0.006, 0.02, K.CHITIN, 3, 3, 0.01), TRUNK_BONES, 8.0)


def sac_coords(p: Vector) -> tuple:
    """(y, angle) of the point on the bladder nearest p (inverse of sac_point, ignoring the lumps and crease)."""
    c, w, top, bot = sac_shape(p.y)
    h = top if p.z > c.z else bot
    return p.y, math.degrees(math.atan2((p.z - c.z) / max(h, 1e-3), p.x / max(w, 1e-3)))


def vein_tree(rnd, glands: K.Skin, s: float, y: float, a: float, heading: float, length: float, r: float, depth: int):
    """A glowing vein on side s from (y, angle a) heading `heading` degrees off straight up the flank (positive
    toward the rear), forking `depth` more times into two thinner, shorter veins; stops at the top crease."""
    n = max(2, round(length / 0.09))
    step = length / n
    pts = [(y, a)]
    for _i in range(n):
        heading += rnd.uniform(-12, 12)
        _c, w, _t, _b = sac_shape(y)
        h = math.radians(heading)
        y = min(max(y + step * math.sin(h), SAC_C.y - SAC_R[1] + 0.07), SAC_C.y + SAC_R[1] - 0.07)
        a += math.degrees(step * math.cos(h) / max(w, 0.15))
        pts.append((y, a))
        if a > 80:
            depth = 0
            break
    path = [sac_point(py, side_angle(pa, s), 0.002) for py, pa in pts]
    tip = 0.75 if depth == 0 or a > 80 else 0.9
    glands.rigid(K.tube_path(glands, path, [r, r * (1 + tip) / 2, r * tip], 4, len(pts) + 1, 0), "Sac")
    if depth > 0:
        if a > 25 and rnd.random() < 0.35:
            glands.rigid(patch(glands, y, side_angle(a, s), 0.045, 6.5, 0.002, 0.012, 0), "Sac")
        spread = rnd.uniform(24, 36)
        for turn in (-spread, spread):
            vein_tree(rnd, glands, s, y, a, heading + turn, length * 0.68, max(r * 0.8, 0.012), depth - 1)


def build_sac(sk: K.Skin, glands: K.Skin) -> None:
    _w, ry_, _top, _bot = SAC_R
    seg, n = 28, 24
    rings = []
    for i in range(1, n):
        th = math.pi * i / n
        y = SAC_C.y - ry_ * math.cos(th)
        rings.append([sac_point(y, 360 * k / seg) for k in range(seg)])
    verts = sk.loft(rings, K.SINEW, caps=False)
    sk.rigid(verts, "Sac")
    sk.rigid(cap(sk, list(reversed(verts[:seg])), sac_point(SAC_C.y - ry_, 0), K.SINEW), "Sac")
    sk.rigid(cap(sk, verts[-seg:], sac_point(SAC_C.y + ry_, 0), K.SINEW), "Sac")
    # A few small chitin scutes down the top crease, apart, the glow showing between and beside them.
    for y0, y1, half in ((-0.5, -0.28, 10), (-0.16, 0.08, 12), (0.2, 0.42, 11), (0.52, 0.68, 8)):

        def width(v: float, h: float = half) -> float:  # an oval shield, blunt in front, pointed at the rear
            return h * (0.3 + 0.7 * math.sin(math.pi * (0.12 + 0.8 * v)) ** 0.7)

        lo, hi = (lambda v, w=width: 90 - w(v)), (lambda v, w=width: 90 + w(v))
        sk.rigid(sac_slab(sk, y0, y1, lo, hi, 0.006, 0.03, K.CHITIN, 6, 5, 0.025), "Sac")
    # Glowing veins: trees spreading from the legs' collars up over the flanks to the top crease and down to the
    # belly, from the neck up the front, and glowing patches where the skin is stretched thin at some forks.
    rnd = random.Random(7)
    for _side, s in K.SIDES:
        for pts in LEGS.values():
            y, a = sac_coords(sac_exit(pts[0], pts[1]))
            for heading, length, depth in ((-35, 0.3, 2), (35, 0.3, 2), (180 + rnd.uniform(-30, 30), 0.22, 1)):
                vein_tree(rnd, glands, s, y, a + 4, heading + rnd.uniform(-10, 10), length, 0.022, depth)
        vein_tree(rnd, glands, s, -0.6, -40, 20, 0.3, 0.02, 2)
        vein_tree(rnd, glands, s, 0.7, -10, -10, 0.25, 0.018, 1)


def build_neck_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Neck from the core out of the bladder's lower front down into the back of the head.
    pts = [Vector((0, -0.45, 0.89)), Vector((0, -0.62, 0.83)), Vector((0, -0.77, 0.715))]
    sk.auto(K.tube_path(sk, pts, [0.13, 0.11, 0.085], 14, 6, K.SINEW), ["Chest", "Neck", "Head"])
    # Collar plates over the neck where it leaves the bladder.
    for a, b, r, bone in (
        (Vector((0, -0.5, 0.875)), Vector((0, -0.64, 0.825)), 0.115, "Chest"),
        (Vector((0, -0.62, 0.83)), Vector((0, -0.76, 0.725)), 0.095, "Neck"),
    ):
        sk.rigid(K.limb_plate(sk, a, b, r, -75, 75, 0.024, K.CHITIN, Vector((0, -0.3, 1))), bone)
    # Small armored head: a broad, flat capsule under a collar plate and a shield overhanging its sides and front,
    # the eyes peering out under the shield's rim.
    rings = []
    n = 10
    for i in range(n + 1):
        c, w, top, bot = SKULL_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, -0.4)), w, top, bot, 14, 0.003, 3 + i))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    sk.rigid(K.shell(sk, SKULL_SHAPE, -0.76, -0.86, -20, 200, 0.006, 0.024, K.CHITIN, 10, 2, 0.02), "Head")
    sk.rigid(K.shell(sk, SKULL_SHAPE, -0.83, -1.05, -12, 192, 0.01, 0.03, K.CHITIN, 10, 4, 0.03), "Head")
    # The mouth between the mandibles.
    sk.rigid(sk.sphere(Vector((0, -1.035, 0.535)), 0.045, 10, 5, scale=(1.0, 0.7, 0.8), mi=K.MOUTH), "Head")
    for side, s in K.SIDES:
        bone = f"{side}Mandible"
        mp = [K.mirror(p, s) for p in MANDIBLE] + [K.mirror(MANDIBLE_TIP, s)]
        sk.rigid(K.tube_path(sk, mp, [0.032, 0.03, 0.022, 0.008], 8, 8, K.BONE, 0.7), bone)
        base = K.path_point(mp, 0.55)
        sk.rigid(sk.cone(base, base + Vector((-s, -0.3, 0)).normalized() * 0.03, 0.011, 4, K.BONE, 0.6), bone)
        sk.rigid(sk.sphere(K.mirror(MANDIBLE[0], s), 0.034, 8, 4, mi=K.CHITIN), "Head")
        # Eyes: two pairs of small glowing beads on the sides of the head, under the shield.
        for y, a, r in ((-0.95, 4, 0.024), (-0.995, -6, 0.018)):
            p = SKULL_SHAPE.surface(y, side_angle(a, s), 0.0)
            eyes.rigid(eyes.sphere(p, r, 8, 4), "Head")


def sac_exit(hip: Vector, knee: Vector) -> Vector:
    """Where the femur leaves the bladder (the first point along it outside the bladder's surface)."""
    for i in range(1, 101):
        p = hip.lerp(knee, i / 100)
        c, w, top, bot = sac_shape(p.y)
        h = top if p.z > c.z else bot
        if w < 1e-3 or ((p.x - c.x) / w) ** 2 + ((p.z - c.z) / h) ** 2 > 1.0:
            return p
    return knee


def build_legs(sk: K.Skin) -> None:
    for leg, pts in LEGS.items():
        body = LEG_PARENT[leg]
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            out = Vector((s, 0, 0))
            # Coxa: a fleshy socket in the core.
            sk.auto(sk.sphere(j[0], 0.075, 8, 5, mi=K.SINEW), [body, up])
            # Femur: a thin chitin segment rising out of the bladder to the high knee, a collar where it leaves it.
            mid = j[0].lerp(j[1], 0.5) + Vector((0, 0, 0.03))
            sk.rigid(K.tube_path(sk, [j[0], mid, j[1]], [0.05, 0.05, 0.042], 8, 8, K.CHITIN, 1.0, 0.002), up)
            ex = sac_exit(j[0], j[1])
            d = (j[1] - j[0]).normalized()
            sk.rigid(K.tube_path(sk, [ex - d * 0.06, ex, ex + d * 0.05], [0.075, 0.07, 0.055], 10, 3, K.CHITIN), up)
            a, b = ex.lerp(j[1], 0.15), j[1].lerp(ex, 0.12)
            sk.rigid(K.limb_plate(sk, a, b, 0.046, -55, 55, 0.014, K.CHITIN, Vector((s * 0.2, 0, 1))), up)
            # Knee: a chitin knob with a bone spur pointing up and out (the high knees are the silhouette).
            sk.rigid(sk.sphere(j[1], 0.062, 8, 5, scale=(1.0, 1.0, 1.1), mi=K.CHITIN), low)
            spur = (Vector((0, 0, 1)) + (j[1] - j[0]).normalized() * 0.6).normalized()
            sk.rigid(sk.cone(j[1] + spur * 0.04, j[1] + spur * 0.15, 0.03, 6, K.BONE), low)
            # Tibia: long and thin down to the ankle, two bands and a pair of spurs on its inner side.
            mid = j[1].lerp(j[2], 0.5) + out * 0.03
            sk.rigid(K.tube_path(sk, [j[1], mid, j[2]], [0.045, 0.034, 0.026], 8, 10, K.CHITIN, 1.0, 0.002), low)
            for t in (0.22, 0.5):
                c = K.path_point([j[1], mid, j[2]], t)
                dd = K.path_point([j[1], mid, j[2]], t + 0.03) - c
                sk.rigid(K.tube_path(sk, [c - dd, c, c + dd], [0.042, 0.048, 0.04], 8, 2, K.CHITIN), low)
            inner = Vector((j[0].x - j[1].x, j[0].y - j[1].y, 0)).normalized()
            for t in (0.62, 0.8):
                base = K.path_point([j[1], mid, j[2]], t)
                tip = base + (inner * 0.7 + Vector((0, 0, -0.4))).normalized() * 0.07
                sk.rigid(sk.cone(base, tip, 0.016, 4, K.BONE), low)
            # Tarsus to the pad, two hooked claws gripping the ground.
            tarsus = K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.03, 0.026, 0.028], 6, 3, K.SINEW)
            sk.auto(tarsus, [low, foot])
            sk.rigid(sk.sphere(j[3], 0.034, 8, 4, scale=(1.1, 1.2, 0.8), mi=K.CHITIN), foot)
            fwd = Vector((j[3].x - j[0].x, j[3].y - j[0].y, 0)).normalized()
            for k in (-1, 1):
                dk = (fwd + Vector((-fwd.y, fwd.x, 0)) * 0.45 * k).normalized()
                tip = j[3] + dk * 0.065 + Vector((0, 0, -0.03))
                sk.rigid(sk.cone(j[3] + Vector((0, 0, 0.004)), tip, 0.016, 5, K.BONE), foot)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_core(sk)
    build_sac(sk, glands)
    build_neck_head(sk, eyes)
    build_legs(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


class Pose(K.Pose):
    """The kit's pose plus a scale per bone (the bladder throbbing, swelling and bursting), as (width, height,
    length) in the bone's axes: for Sac (pointing up) x, z and y of the world."""

    def __init__(self, rig: K.Rig, offset=(0, 0, 0)):
        super().__init__(rig, offset)
        self.scale: dict = {}

    def grow(self, bone: str, width: float, height: float, length: float) -> "Pose":
        self.scale[bone] = Vector((width, height, length))
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


def pose_point(p: Pose, bone: str, pt: Vector) -> Vector:
    """Where a rest-pose point carried by `bone` lies in pose p (without scales)."""
    return pose_head(p, bone) + p.world(bone) @ (Vector(pt) - RIG.head[bone])


def pose_head(p: Pose, bone: str) -> Vector:
    parent = RIG.parent[bone]
    if parent is None:
        return RIG.head[bone].copy()
    h = pose_point(p, parent, RIG.head[bone])
    return h + p.offset if bone == "Body" else h


def aim(p: Pose, bone: str, direction: Vector) -> None:
    """Turns a bone (relative to its posed parent) so it points along `direction`."""
    rest = (RIG.tail[bone] - RIG.head[bone]).normalized()
    w = rest.rotation_difference(direction.normalized()).to_matrix()
    p.set(bone, p.world(RIG.parent[bone]).transposed() @ w)


def mandibles(p: Pose, spread: float) -> None:
    for side, s in K.SIDES:
        p.set(f"{side}Mandible", rz(s * spread))


def pulse(x: float, c: float, w: float) -> float:
    return math.exp(-((((x % 1.0) - c) / w) ** 2))


def idle(t: float) -> Pose:
    """A slow double throb of the bladder (a heartbeat over slow breathing), the body bobbing with it, the head
    swaying low, the mandibles working."""
    a = math.tau * t
    beat = pulse(t, 0.2, 0.06) + 0.6 * pulse(t, 0.36, 0.06)
    p = Pose(RIG, (0, 0, 0.012 * math.sin(a) - 0.008 * beat))
    p.set("Body", rx(-1.0 * math.sin(a)))
    p.set("Neck", rz(7 * math.sin(a + 1.0)) @ rx(3 * math.sin(2 * a)))
    p.set("Head", rx(-3 + 3 * math.sin(a + 1.3)) @ rz(-4 * math.sin(a + 1.0)))
    p.set("Jaw", rx(-2 * max(0.0, math.sin(a * 3))))
    mandibles(p, 7 + 7 * max(0.0, math.sin(a * 3 + 0.5)))
    s = 1.0 + 0.02 * math.sin(a) + 0.04 * beat
    p.grow("Sac", s, s + 0.01 * beat, s)
    return p


def run(t: float) -> Pose:
    """A slow, wobbling lumber (legs at rest, the game steps them): two heavy bobs per stride, the trunk rolling from
    side to side, the bladder lagging behind it, sloshing and squashing; the head low."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = Pose(RIG, (0, 0, -0.03 + 0.03 * bob))
    p.set("Body", rx(2 * math.sin(2 * a + 0.4)) @ ry(5 * math.sin(a)) @ rz(2.5 * math.sin(a)))
    p.set("Hips", rz(-2 * math.sin(a - 0.5)))
    p.set("Chest", rz(-2 * math.sin(a)))
    p.set("Neck", rx(5 + 3 * math.sin(2 * a)) @ rz(-4 * math.sin(a)))
    p.set("Head", rx(-3 * math.sin(2 * a)))
    mandibles(p, 6)
    lag = 2 * a - 1.3
    p.set("Sac", rx(3 * math.sin(lag)) @ ry(-4 * math.sin(a - 1.0)))
    sq = math.sin(lag)
    p.grow("Sac", 1.0 + 0.035 * math.sin(lag + 1.0), 1.0 - 0.06 * sq, 1.0 + 0.035 * math.sin(lag + 1.0))
    return p


ATTACK_FRAMES = 15  # 0.5 s


def attack(t: float) -> Pose:
    """The pre-burst (0.5 s): the bladder swells to x1.3 (by 0.8) and shudders harder and harder, the body sinks
    and trembles, the legs brace, the head pulls up with the mandibles flared; it ends at its biggest."""
    swell = K.smooth(t / 0.8)
    brace = K.smooth(t / 0.4)
    shudder = 0.03 * math.sin(math.tau * 7 * t) * K.smooth(t / 0.3)
    p = Pose(RIG, (0, 0, -0.1 * brace))
    p.set("Body", rx(-3 * brace) @ rz(1.5 * math.sin(math.tau * 9 * t) * brace))
    p.set("Neck", rx(-10 * brace))
    p.set("Head", rx(-8 * brace))
    p.set("Jaw", rx(-6 * brace))
    mandibles(p, 7 + 25 * brace)
    s = 1.0 + 0.3 * swell
    p.grow("Sac", s + shudder, s - 0.7 * shudder, s + shudder)
    return p


DIE_FRAMES = 45  # 1.5 s
DEAD_Z = 0.38  # the Body's height once it lies on its folded legs
HUSK = (0.45, 0.28, 0.45)  # the burst bladder's scale (width, height, length)
# Per leg row: the femur's elevation and the turn of the folded tibia away from pointing straight back at the body
# (degrees, for the left side).
DEAD_FOLD = {"Front": (32, -30), "Mid": (30, -20), "Hind": (32, 30)}


def die_trunk(p: Pose, f: float) -> None:
    p.set("Body", ry(6 * f) @ rx(3 * f))
    p.set("Neck", rx(-38 * f) @ rz(12 * f))
    p.set("Head", rx(-10 * f))
    p.set("Jaw", rx(10 * f))
    mandibles(p, 30 * f)


@functools.cache
def dead_legs() -> dict:
    """Per leg once folded (world positions with the body down): the knee and the ankle; the knees buckled up and
    out, the tibias folded back under the body."""
    p = Pose(RIG, (0, 0, DEAD_Z - BODY.z))
    die_trunk(p, 1.0)
    out = {}
    for leg, (elev, fold) in DEAD_FOLD.items():
        for side, s in K.SIDES:
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            hip, ankle = RIG.head[up], RIG.head[foot]
            h = Vector((ankle.x - hip.x, ankle.y - hip.y, 0)).normalized()
            e = math.radians(elev)
            knee = pose_head(p, up) + (h * math.cos(e) + K.UP * math.sin(e)) * (RIG.head[low] - hip).length
            length = (ankle - RIG.head[low]).length
            dz = knee.z - 0.11
            back = Matrix.Rotation(math.radians(fold * s), 3, "Z") @ -h
            tib = back * math.sqrt(max(length * length - dz * dz, 0.0)) + Vector((0, 0, -dz))
            out[f"{leg}{side}"] = (knee, knee + tib)
    return out


def two_bone(hip: Vector, target: Vector, a: float, b: float, pole: Vector) -> Vector:
    """The knee of a two-bone chain from hip reaching target (bone lengths a, b), bending towards pole."""
    d = target - hip
    dist = min(max(d.length, abs(a - b) + 1e-4), a + b - 1e-4)
    axis = d.normalized()
    x = (a * a - b * b + dist * dist) / (2 * dist)
    side = (pole - axis * pole.dot(axis)).normalized()
    return hip + axis * x + side * math.sqrt(max(a * a - x * x, 0.0))


def fold_legs(p: Pose, u: float) -> None:
    """Folds the legs by u (0 = rest, 1 = dead) on the posed body: each ankle slides on the ground from its rest spot
    to its folded one, the knee bending by two-bone IK towards a pole turning from the rest knee to the folded one."""
    for name, (knee1, ankle1) in dead_legs().items():
        up, low, foot = f"{name}UpperLeg", f"{name}LowerLeg", f"{name}Foot"
        hip = pose_head(p, up)
        hip1 = RIG.head[up] + Vector((0, 0, DEAD_Z - BODY.z))
        knee0, ankle0 = RIG.head[low], RIG.head[foot]
        pole = (knee0 - RIG.head[up]).lerp(knee1 - hip1, u)
        a, b = (knee0 - RIG.head[up]).length, (ankle0 - knee0).length
        ankle = ankle0.lerp(ankle1, u)
        knee = two_bone(hip, ankle, a, b, pole)
        aim(p, up, knee - hip)
        aim(p, low, ankle - knee)
        heading = Vector((ankle.x - knee.x, ankle.y - knee.y, 0)).normalized()
        aim(p, foot, (RIG.tail[foot] - RIG.head[foot]).normalized().lerp(heading + Vector((0, 0, -0.6)), min(u * 3, 1)))


def die(t: float) -> Pose:
    """The burst: the bladder pops to x1.25 (0.05 s) and collapses into a wrinkled husk (x0.28-0.45 by 0.15 s)
    which wobbles and sags; then the legs buckle and fold under it and it sinks onto them (by about 1 s), the feet
    sliding in on the ground, the head dropping forward onto the ground."""
    st = t * DIE_FRAMES / FPS
    f = K.smooth((st - 0.12) / 0.8)
    sag = K.smooth((st - 0.15) / 1.0)
    p = Pose(RIG, (0, 0, (DEAD_Z - BODY.z) * f + 0.02 * math.sin(math.pi * min(st / 0.15, 1.0))))
    die_trunk(p, f)
    fold_legs(p, K.smooth((st - 0.15) / 0.8))
    p.set("Sac", rx(10 * sag) @ ry(14 * sag))
    if st < 0.05:
        k = 1.0 + 0.25 * K.smooth(st / 0.05)
        p.grow("Sac", k, k, k)
    elif st < 0.15:
        u = K.smooth((st - 0.05) / 0.1)
        p.grow("Sac", *(1.25 + (h - 1.25) * u for h in HUSK))
    else:
        wob = 0.06 * math.exp(-(st - 0.15) * 7) * math.sin((st - 0.15) * 34)
        w, h, ln = HUSK
        p.grow("Sac", w + 0.05 * sag + 0.5 * wob, h - 0.05 * sag - wob, ln + 0.03 * sag + 0.5 * wob)
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (30, run),
    "Attack": (ATTACK_FRAMES, attack),
    "Die": (DIE_FRAMES, die),
}

# --- report -------------------------------------------------------------------------------------------


def lowest_parts(count: int = 12) -> list:
    """The bones whose posed vertices reach lowest (to check a pose stays above the ground)."""
    obj = bpy.data.objects["Creature"]
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    names = {g.index: g.name for g in obj.vertex_groups}
    low: dict = {}
    for v, src in zip(me.vertices, obj.data.vertices):
        g = max(src.groups, key=lambda e: e.weight).group if src.groups else -1
        low[names.get(g, "?")] = min(low.get(names.get(g, "?"), 9.0), v.co.z)
    ev.to_mesh_clear()
    return sorted((round(z, 3), n) for n, z in low.items())[:count]


def rnd(v) -> tuple:
    return tuple(round(x, 3) for x in v)


def report(arm: bpy.types.Object) -> None:
    rest_pose(arm)
    w, ry_, top, bot = SAC_R
    print("POINT sac center rest", rnd(SAC_C), "half-width", w, "half-length", ry_, "top", top, "bottom", bot)
    print("POINT sac top", round(SAC_C.z + top, 3), "belly", round(SAC_C.z - bot, 3))
    print("POINT head (Head bone head)", rnd(SKULL), "snout", rnd(SNOUT), "head center", rnd(SKULL.lerp(SNOUT, 0.5)))
    for leg, pts in LEGS.items():
        print("POINT knee", leg, rnd(pts[1]), "ankle", rnd(pts[2]))
    for name, pose in (
        ("die15", die(0.15 * FPS / DIE_FRAMES)),
        ("die5", die(0.5)),
        ("die", die(1.0)),
        ("attack", attack(1.0)),
        ("run", run(0.25)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        print("POINT", name, "stats", C.stats(), "lowest", lowest_parts())
    dips = []
    for f in range(0, DIE_FRAMES + 1, 3):
        apply(arm, die(f / DIE_FRAMES))
        bpy.context.view_layer.update()
        dips.append((C.stats()["min"][2], f, lowest_parts(2)))
    print("POINT die lowest per frame", dips)
    rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------


def add_spitter(x: float) -> list:
    """The spitter's rest-pose mesh beside the bloater for a comparison (wip only, from its procedural .blend)."""
    src = ROOT / "tmp" / "assets" / "spitter" / "spitter_procedural.blend"
    if not src.exists():
        return []
    with bpy.data.libraries.load(str(src)) as (data_from, data_to):
        data_to.meshes = [m for m in ("Creature", "Eyes", "Glands") if m in data_from.meshes]
    objs = []
    for me in data_to.meshes:
        obj = bpy.data.objects.new("Scale" + me.name, me)
        C.link(obj, None, "Preview")
        obj.location = (x, 0.8, 0)
        objs.append(obj)
    return objs


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(2.3, 1.6, 0))
    shots = []
    w = OUT / "wip"
    target = (0, -0.05, 0.85)
    rest_pose(arm)
    for view, zoom in (("iso", 0.62), ("hero", 0.7), ("back", 0.75), ("iso", 1.4)):
        path = w / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(w / f"{tag}_side.png", Vector((6.5, -0.1, 1.0)), (0, 0.0, 0.85), 50, 32, 512)
    C.render_from(w / f"{tag}_head.png", Vector((1.2, -2.6, 1.2)), (0, -0.9, 0.62), 50, 32, 512)
    C.render_from(w / f"{tag}_top.png", Vector((0.0, -0.01, 7.0)), (0, 0.0, 0.0), 50, 32, 512)
    shots += [w / f"{tag}_side.png", w / f"{tag}_head.png", w / f"{tag}_top.png"]
    for name, pose in (
        ("idle", idle(0.2)),
        ("run", run(0.25)),
        ("attack", attack(1.0)),
        ("die1", die(0.1)),
        ("die5", die(0.5)),
        ("die", die(1.0)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        path = w / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.7)
        shots.append(path)
    apply(arm, die(1.0))
    bpy.context.view_layer.update()
    path = w / f"{tag}_die_side.png"
    C.render_from(path, Vector((6.5, -0.1, 0.6)), (0, 0.0, 0.3), 50, 24, 512)
    shots.append(path)
    path = w / f"{tag}_die_iso.png"
    C.render(path, view="iso", samples=24, size=512, target=(0, 0, 0.3), zoom=0.62)
    shots.append(path)
    rest_pose(arm)
    if MODE == "wip":
        scale = add_spitter(-2.6)
        if scale:
            path = w / f"{tag}_scale.png"
            C.render(path, view="iso", samples=32, size=512, target=(-1.2, 0.3, 0.6), zoom=0.85)
            shots.append(path)
            for obj in scale:
                bpy.data.objects.remove(obj)
    C.contact_sheet(shots, w / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    report(arm)
    if MODE != "stats":
        preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "bloater_procedural.blend")
        C.export_glb(OUT / "bloater_draft.glb")


main()
