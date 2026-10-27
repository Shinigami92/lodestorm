"""Bloater: a tier 4 raider of the hive that bursts. A fat, swollen grub on six short, stubby legs: a soft, ringed
sinew body low over the ground, its whole upper back one taut, veined bladder that glows through its veins and
patches, a small blunt armored head low at its front (see docs/design/aliens.md, Alien look), rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/bloater/source/bloater_build.py wip v2r1   # quick renders of the poses
    tools/blender.sh assets/aliens/bloater/source/bloater_build.py final      # renders + bloater_procedural.blend

Everything it writes goes to tmp/assets/bloater/; bloater_bake.py turns bloater_procedural.blend into the game asset.

Layout (Blender Z-up meters; the bloater faces -Y, its left is +X; the game turns the model by 180 degrees). Feet on
the ground at the origin, the origin under the middle of the body. The body is about 1.75 m long (rump to the
mandibles) and 1.0 m wide, its belly about 0.15 m above the ground; the bladder's top is at about 0.96 m. Ten ring
segments from the neck to the rump; the legs hang under the first, third and fifth, three pairs of soft prolegs under
the rear ones.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (the rear half) with the hind legs
and Tail (the last segments), Spine (the front half) with the mid legs and Sac (the bladder: clips scale it to throb,
swell and burst), Chest (the first segments) with the front legs, Neck, Head, Jaw (the mandibles' base) with
LeftMandible and RightMandible. Legs (<Front|Mid|Hind><Side>UpperLeg, LowerLeg, Foot): short and thick, tucked under
the belly; the game moves them by IK (the fleshy femur out to a low knee, the chitin tibia down to the ankle, the Foot
is the pad with its claw), so the clips leave them at rest; only "Die" splays them. Meshes: "Creature" (one skinned
object: the ringed body and the prolegs weighted to the nearest trunk bones; the bladder rigid to Sac; the head, its
plates, the mandibles and leg segments rigid), "Eyes" (constant emissive, three small beads a side) and "Glands"
(constant emissive: the dorsal vessel, veins and patches on the bladder, skinned to Sac; the game flares it with the
eyes).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: a slow throb of the bladder over
the segments' breathing, the head swaying), "Run" (loop: a slow, heavy waddle, the segments rippling from front to
back, the bladder sloshing; the legs come from the game), "Attack" (once, 0.5 s: the pre-burst, the bladder swells to
x1.3 and shudders while the body braces; it ends at its biggest) and "Die" (once: the bladder pops to x1.15 and
collapses into a flat husk by 0.15 s, then the body sags flat, the legs splaying and the head dropping).
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
from mathutils import Vector, noise

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "v2r0"

ASSET = "Bloater"
FPS = 30
GLAND_GLOW = 2.0  # the bladder's vessel, veins and patches (eyes 8 in the previews)

# --- layout ---------------------------------------------------------------------------------------

# The ring segments from the neck (SEG_Y0) to the rump, each SEG long.
SEG_Y0, SEG, SEGS = -0.6, 0.144, 10
RUMP_Y = SEG_Y0 + SEG * SEGS  # 0.84


def seg_mid(k: int) -> float:
    return SEG_Y0 + SEG * (k + 0.5)


BODY = Vector((0, 0.0, 0.46))
CHEST = Vector((0, -0.3, 0.455))
NECK = Vector((0, -0.56, 0.41))
SKULL = Vector((0, -0.64, 0.375))
SNOUT = Vector((0, -0.87, 0.3))
JAW = Vector((0, -0.82, 0.255))
TAIL = Vector((0, 0.42, 0.44))
# The bladder: a long dome over the whole back, its lower half sunk into the body; Sac scales it from inside.
SAC_BASE = Vector((0, 0.14, 0.46))
SAC_C = Vector((0, 0.14, 0.56))
SAC_R = (0.53, 0.64, 0.4, 0.24)  # half-width, half-length, top, bottom
LUMPS = 0.012  # how far the taut skin bulges in and out
CREASE = 0.14  # how deep the segments' rings pinch the bladder (the body: TRUNK_CREASE)
TRUNK_CREASE = 0.085
# Leg joints per side (x for the left side): hip, knee, ankle, pad (the claw's base on the ground). The legs hang under
# the first, third and fifth segments, the knees just out from under the belly.
LEG_Y = {"Front": seg_mid(0), "Mid": seg_mid(2), "Hind": seg_mid(4)}
LEGS = {
    "Front": [
        Vector((0.2, LEG_Y["Front"], 0.27)),
        Vector((0.37, LEG_Y["Front"] - 0.03, 0.225)),
        Vector((0.4, LEG_Y["Front"] - 0.07, 0.075)),
        Vector((0.42, LEG_Y["Front"] - 0.11, 0.034)),
    ],
    "Mid": [
        Vector((0.25, LEG_Y["Mid"], 0.25)),
        Vector((0.43, LEG_Y["Mid"] - 0.01, 0.21)),
        Vector((0.46, LEG_Y["Mid"] - 0.03, 0.075)),
        Vector((0.49, LEG_Y["Mid"] - 0.07, 0.034)),
    ],
    "Hind": [
        Vector((0.26, LEG_Y["Hind"], 0.24)),
        Vector((0.44, LEG_Y["Hind"] + 0.01, 0.2)),
        Vector((0.47, LEG_Y["Hind"] + 0.02, 0.075)),
        Vector((0.5, LEG_Y["Hind"] - 0.02, 0.034)),
    ],
}
LEG_PARENT = {"Front": "Chest", "Mid": "Spine", "Hind": "Hips"}
PROLEGS = (6, 7, 8)  # the segments with a pair of prolegs
MANDIBLE = [Vector((0.075, -0.83, 0.25)), Vector((0.095, -0.88, 0.235)), Vector((0.065, -0.925, 0.225))]
MANDIBLE_TIP = Vector((0.022, -0.945, 0.22))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.3, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.15, 0)), "Root"),
    ("Hips", BODY, TAIL, "Body"),
    ("Tail", TAIL, Vector((0, RUMP_Y, 0.34)), "Hips"),
    ("Spine", BODY, CHEST, "Body"),
    ("Chest", CHEST, NECK, "Spine"),
    ("Neck", NECK, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW, Vector((0, -0.92, 0.23)), "Head"),
    ("Sac", SAC_BASE, SAC_BASE + Vector((0, 0, 0.5)), "Spine"),
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
TRUNK_BONES = ["Tail", "Hips", "Spine", "Chest", "Neck"]


# --- shapes -------------------------------------------------------------------------------------------


def even_rows(y0: float, y1: float, rows: list) -> list:
    """Profile rows (center z, half-width, top, bottom) spread evenly from y0 to y1."""
    n = len(rows) - 1
    return [(y0 + (y1 - y0) * i / n, *r) for i, r in enumerate(rows)]


# The body's envelope from the rump forward to the neck (before the rings pinch it): center z, half-width, top, bottom.
ENVELOPE = K.Profile(
    even_rows(
        RUMP_Y,
        SEG_Y0,
        [
            (0.33, 0.17, 0.14, 0.13),
            (0.37, 0.34, 0.22, 0.22),
            (0.42, 0.44, 0.24, 0.27),
            (0.45, 0.5, 0.24, 0.31),
            (0.46, 0.51, 0.23, 0.32),
            (0.46, 0.5, 0.23, 0.32),
            (0.455, 0.46, 0.22, 0.31),
            (0.44, 0.38, 0.2, 0.27),
            (0.41, 0.25, 0.155, 0.19),
        ],
    )
)
# The head capsule from its back (inside the first segment) to its blunt front: center z, half-width, top, bottom.
HEAD_SHAPE = K.Profile(
    even_rows(
        -0.56,
        -0.88,
        [
            (0.4, 0.19, 0.15, 0.135),
            (0.39, 0.23, 0.175, 0.155),
            (0.375, 0.245, 0.18, 0.16),
            (0.355, 0.24, 0.172, 0.155),
            (0.333, 0.215, 0.15, 0.138),
            (0.312, 0.172, 0.115, 0.108),
            (0.292, 0.095, 0.068, 0.062),
        ],
    )
)


def ring_u(y: float) -> float:
    """Where y lies within its segment (0 at the ring between two segments, 0.5 in its middle)."""
    x = (y - SEG_Y0) / SEG
    return x - math.floor(x)


def bulge(y: float) -> float:
    """1 in a segment's middle, 0 in the ring between two."""
    return math.sin(math.pi * ring_u(y)) ** 0.6


def trunk_shape(y: float) -> tuple:
    """Center, half-width, top and bottom of the body's cross-section at y, pinched by the segments' rings."""
    t = (RUMP_Y - y) / (RUMP_Y - SEG_Y0)
    c, w, top, bot = ENVELOPE.at(t)
    k = 1.0 - TRUNK_CREASE * (1.0 - bulge(y))
    return c, w * k, top * k, bot * k


def trunk_point(y: float, a: float, out: float = 0.0) -> Vector:
    """Point on the body at y and angle a (0 = left side, 90 = top, 270 = belly), pushed out by `out`."""
    c, w, top, bot = trunk_shape(y)
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    x = math.copysign(abs(ca) ** 0.85, ca) * (w + out)
    z = math.copysign(abs(sa) ** 0.9, sa) * ((top if sa > 0 else bot) + out)
    return c + Vector((x, 0, z))


def sac_shape(y: float) -> tuple:
    """Center, half-width, top and bottom of the bladder's cross-section at y: a long dome, a little fuller at the
    rear, pinched lightly where the body's rings run under it."""
    cx, cy, cz = SAC_C
    w, ry_, top, bot = SAC_R
    u = min(max((y - cy) / ry_, -1.0), 1.0)
    e = math.sqrt(max(1.0 - u * u, 0.0)) ** 0.7
    k = (1.0 + 0.05 * u) * (1.0 - CREASE * (1.0 - bulge(y)))
    return Vector((cx, y, cz - 0.02 * u)), w * e * k, top * e * k, bot * e * k


def sac_point(y: float, a: float, out: float = 0.0) -> Vector:
    """Point on the bladder at y and angle a (0 = left side, 90 = top, 270 = belly), pushed out by `out`."""
    c, w, top, bot = sac_shape(y)
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    x = math.copysign(abs(ca) ** 0.9, ca)
    z = math.copysign(abs(sa) ** 0.9, sa)
    skin = c + Vector((x * w, 0, z * (top if sa > 0 else bot)))
    lump = (skin - SAC_C).normalized() * LUMPS * noise.noise(skin * 3.5 + Vector((4.1, 2.3, 7.7)))
    return skin + lump + Vector((x * out, 0, z * out))


def side_angle(a: float, s: float) -> float:
    """An angle given for the left side, mirrored to side s."""
    return a if s > 0 else 180.0 - a


def slab(sk: K.Skin, point, y0: float, y1: float, a0, a1, out: float, thick: float, mi: int, nu: int, nv: int,
         lift: float = 0.0) -> list:  # fmt: skip
    """Slab hugging a surface `point(y, a, out)` between y0..y1 and angles a0..a1 (numbers or functions of v = 0..1
    along y); its rear edge lifts off by `lift` like a scale."""
    lo_f = a0 if callable(a0) else (lambda _v: a0)
    hi_f = a1 if callable(a1) else (lambda _v: a1)
    top_rows, bot_rows = [], []
    for i in range(nv + 1):
        v = i / nv
        y = y0 + (y1 - y0) * v
        lo, hi = lo_f(v), hi_f(v)
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            a = lo + (hi - lo) * u
            edge = math.sin(math.pi * u) ** 0.5
            o = out + lift * v * v * edge
            row_t.append(sk.bm.verts.new(point(y, a, o + thick * edge * (0.5 + 0.5 * math.sin(math.pi * v)))))
            row_b.append(sk.bm.verts.new(point(y, a, o)))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return K.close_grid(sk, top_rows, bot_rows, mi)


def oval(point, sk: K.Skin, y: float, a: float, ly: float, la: float, out: float, thick: float, mi: int,
         n: int = 3) -> list:  # fmt: skip
    """Oval slab on a surface centered at y, a (half-length ly in y, half-width la in degrees)."""

    def width(v: float) -> float:
        return la * math.sin(math.pi * (0.08 + 0.84 * v)) ** 0.6

    return slab(sk, point, y - ly, y + ly, lambda v: a - width(v), lambda v: a + width(v), out, thick, mi, n, n)


def cap(sk: K.Skin, ring: list, pole: Vector, mi: int) -> list:
    """Closes a ring of verts with a fan around a pole vertex."""
    p = sk.bm.verts.new(pole)
    n = len(ring)
    for k in range(n):
        sk.bm.faces.new((ring[k], ring[(k + 1) % n], p)).normal_update()
    return sk._tag(ring + [p], mi)


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: K.Skin) -> None:
    """The ringed body: ten fat segments, each pinched at its rings, the front tucked in around the head; a shield
    over the first segment, small plates along the flanks, soft prolegs under the rear."""
    seg = 22
    ys = [SEG_Y0 + SEG * (k + u) for k in range(SEGS) for u in (0.0, 0.14, 0.38, 0.62, 0.86)] + [RUMP_Y]
    rings = []
    # The front folds in around the neck.
    for y, f in ((SEG_Y0 - 0.018, 0.6), (SEG_Y0 - 0.012, 0.86)):
        c, w, top, bot = trunk_shape(SEG_Y0)
        rings.append(K.section(c, Vector((0, -1, 0)), w * f, top * f, bot * f, seg))
        for p in rings[-1]:
            p.y = y
    for i, y in enumerate(ys):
        c, w, top, bot = trunk_shape(y)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, seg, 0.004, i * 0.9))
    # The rump closes in a round dome.
    for dy, f in ((0.03, 0.78), (0.05, 0.42)):
        c, w, top, bot = trunk_shape(RUMP_Y)
        rings.append(K.section(c + Vector((0, dy, 0)), Vector((0, -1, 0)), w * f, top * f, bot * f, seg))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # Shield over the first segment, in front of the bladder.
    sk.auto(slab(sk, trunk_point, SEG_Y0 - 0.005, SEG_Y0 + SEG * 0.92, 28, 152, 0.006, 0.032, K.CHITIN, 8, 4, 0.02),
            TRUNK_BONES, 8.0)  # fmt: skip
    # Small plates down each flank, under the bladder's edge (one per segment), and over the leg sockets.
    for k in range(1, SEGS - 1):
        ym = seg_mid(k)
        for _side, s in K.SIDES:
            a0, a1 = side_angle(-12, s), side_angle(12, s)
            lo, hi = min(a0, a1), max(a0, a1)
            plate = oval(trunk_point, sk, ym, (lo + hi) / 2, SEG * 0.3, 12, 0.004, 0.018, K.CHITIN)
            sk.auto(plate, TRUNK_BONES, 8.0)
    for leg in LEGS:
        for _side, s in K.SIDES:
            a = side_angle(-38, s)
            plate = oval(trunk_point, sk, LEG_Y[leg], a, SEG * 0.32, 13, 0.004, 0.02, K.CHITIN)
            sk.auto(plate, TRUNK_BONES, 8.0)
    # Prolegs: soft stumps under the rear segments with a dark ring of hooks at the sole.
    for k in PROLEGS:
        ym = seg_mid(k)
        for _side, s in K.SIDES:
            p = trunk_point(ym, side_angle(-62, s), -0.02)
            foot = Vector((p.x * 1.05, ym, 0.115))
            stump = K.tube_path(sk, [p, p.lerp(foot, 0.5), foot], [0.07, 0.065, 0.06], 8, 3, K.SINEW)
            sk.auto(stump, ["Hips", "Tail"])
            sk.auto(sk.sphere(foot, 0.058, 8, 4, scale=(1.0, 1.0, 0.7), mi=K.SINEW), ["Hips", "Tail"])
            sole = sk.sphere(foot + Vector((0, 0, -0.022)), 0.05, 8, 3, scale=(1.0, 1.0, 0.35), mi=K.CHITIN)
            sk.auto(sole, ["Hips", "Tail"])


def build_sac(sk: K.Skin, glands: K.Skin) -> None:
    """The bladder over the whole back, its glowing dorsal vessel down the middle, veins branching from it over the
    flanks and patches where the skin is stretched thin."""
    _w, ry_, _top, _bot = SAC_R
    seg, n = 28, 30
    rings = []
    for i in range(1, n):
        th = math.pi * i / n
        y = SAC_C.y - ry_ * math.cos(th)
        rings.append([sac_point(y, 360 * k / seg) for k in range(seg)])
    verts = sk.loft(rings, K.SINEW, caps=False)
    sk.rigid(verts, "Sac")
    sk.rigid(cap(sk, list(reversed(verts[:seg])), sac_point(SAC_C.y - ry_, 0), K.SINEW), "Sac")
    sk.rigid(cap(sk, verts[-seg:], sac_point(SAC_C.y + ry_, 0), K.SINEW), "Sac")
    # The dorsal vessel: a glowing cord down the top, swelling into a chamber in every segment.
    y0, y1 = SAC_C.y - ry_ + 0.1, SAC_C.y + ry_ - 0.08
    m = 36
    path = [sac_point(y0 + (y1 - y0) * i / m, 90, 0.0) for i in range(m + 1)]
    radii = [0.018 + 0.014 * bulge(y0 + (y1 - y0) * i / m) for i in range(m + 1)]
    glands.rigid(tube_radii(glands, path, radii, 6), "Sac")
    # Veins from the vessel down the flanks, one tree a segment and side, and patches between them.
    rnd = random.Random(11)
    for k in range(1, SEGS - 1):
        ym = seg_mid(k)
        if not (y0 + 0.02 < ym < y1 - 0.02):
            continue
        for _side, s in K.SIDES:
            heading = math.copysign(rnd.uniform(35, 55), ym - SAC_C.y + 0.05)
            vein_tree(rnd, glands, s, ym + rnd.uniform(-0.02, 0.02), 84, heading, 0.42, 0.021, 2)
            if (k + (s > 0)) % 2 == 0 or rnd.random() < 0.3:
                yp = ym + SEG * rnd.uniform(0.15, 0.3) * rnd.choice((-1, 1))
                ap = side_angle(rnd.uniform(22, 50), s)
                glands.rigid(oval(sac_point, glands, yp, ap, 0.04, rnd.uniform(6, 9), 0.002, 0.012, 0), "Sac")


def tube_radii(sk: K.Skin, path: list, radii: list, seg: int) -> list:
    """Tube through every point of `path` (one ring each) with its own radius, closed at both ends."""
    rings = []
    for i, c in enumerate(path):
        d = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        rings.append(K.section(c, d, radii[i], radii[i], radii[i], seg))
    return sk.loft(rings, 0)


def vein_tree(rnd, glands: K.Skin, s: float, y: float, a: float, heading: float, length: float, r: float, depth: int):
    """A glowing vein on side s from (y, angle a) down the flank, heading `heading` degrees off straight down
    (positive toward the rear), forking `depth` more times into two thinner, shorter veins; it stops at the
    bladder's lower edge."""
    n = max(2, round(length / 0.08))
    step = length / n
    pts = [(y, a)]
    lo_y, hi_y = SAC_C.y - SAC_R[1] + 0.08, SAC_C.y + SAC_R[1] - 0.08
    for _i in range(n):
        heading += rnd.uniform(-10, 10)
        _c, w, top, _b = sac_shape(y)
        h = math.radians(heading)
        y = min(max(y + step * math.sin(h), lo_y), hi_y)
        a -= math.degrees(step * math.cos(h) / max((w + top) / 2, 0.12))
        pts.append((y, a))
        if a < -8:
            depth = 0
            break
    path = [sac_point(py, side_angle(pa, s), 0.0) for py, pa in pts]
    tip = 0.75 if depth == 0 else 0.9
    glands.rigid(K.tube_path(glands, path, [r, r * (1 + tip) / 2, r * tip], 4, max(len(pts) - 1, 2), 0), "Sac")
    if depth > 0:
        spread = rnd.uniform(26, 40)
        for turn in (-spread, spread):
            vein_tree(rnd, glands, s, y, a, heading + turn, length * 0.62, max(r * 0.85, 0.016), depth - 1)


def build_head(sk: K.Skin, eyes: K.Skin) -> None:
    """Small, blunt, armored head low at the front: a capsule tucked into the first segment under a shield, short
    thick mandibles, three small eyes a side under the shield's rim."""
    rings = []
    n = 10
    for i in range(n + 1):
        c, w, top, bot = HEAD_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, -0.3)), w, top, bot, 16, 0.003, 3 + i))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    sk.rigid(K.shell(sk, HEAD_SHAPE, -0.6, -0.7, -10, 190, 0.006, 0.026, K.CHITIN, 10, 2, 0.02), "Head")
    sk.rigid(K.shell(sk, HEAD_SHAPE, -0.68, -0.86, 18, 162, 0.01, 0.032, K.CHITIN, 8, 4, 0.025), "Head")
    # The mouth between the mandibles.
    sk.rigid(sk.sphere(Vector((0, -0.855, 0.26)), 0.05, 10, 5, scale=(1.0, 0.7, 0.8), mi=K.MOUTH), "Head")
    for side, s in K.SIDES:
        bone = f"{side}Mandible"
        mp = [K.mirror(p, s) for p in MANDIBLE] + [K.mirror(MANDIBLE_TIP, s)]
        sk.rigid(K.tube_path(sk, mp, [0.036, 0.034, 0.025, 0.012], 8, 8, K.BONE, 0.75), bone)
        sk.rigid(sk.sphere(K.mirror(MANDIBLE[0], s), 0.04, 8, 4, mi=K.CHITIN), "Head")
        for y, a, r in ((-0.79, 8, 0.022), (-0.765, 16, 0.019), (-0.815, -2, 0.018)):
            p = HEAD_SHAPE.surface(y, side_angle(a, s), 0.004)
            eyes.rigid(eyes.sphere(p, r, 8, 4), "Head")


def build_legs(sk: K.Skin) -> None:
    for leg, pts in LEGS.items():
        body = LEG_PARENT[leg]
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            out = Vector((s, 0, 0))
            # Coxa and femur: a fat, fleshy stump out of the belly to the knee, a chitin band over it.
            sk.auto(sk.sphere(j[0], 0.085, 8, 4, scale=(1.0, 1.0, 0.85), mi=K.SINEW), [body, up])
            mid = j[0].lerp(j[1], 0.5) + Vector((0, 0, 0.012))
            sk.auto(K.tube_path(sk, [j[0], mid, j[1]], [0.085, 0.075, 0.066], 8, 4, K.SINEW), [body, up])
            a, b = j[0].lerp(j[1], 0.42), j[0].lerp(j[1], 0.9)
            sk.rigid(K.limb_plate(sk, a, b, 0.07, -70, 70, 0.016, K.CHITIN, out * 0.4 + Vector((0, 0, 1))), up)
            # Knee: a chitin knob; tibia: a short, thick chitin cone down to the ankle with a band.
            sk.rigid(sk.sphere(j[1], 0.07, 8, 4, mi=K.CHITIN), low)
            mid = j[1].lerp(j[2], 0.5) + out * 0.01
            sk.rigid(K.tube_path(sk, [j[1], mid, j[2]], [0.064, 0.056, 0.047], 8, 4, K.CHITIN), low)
            c = j[1].lerp(j[2], 0.45)
            d = (j[2] - j[1]).normalized() * 0.018
            sk.rigid(K.tube_path(sk, [c - d, c, c + d], [0.06, 0.066, 0.058], 8, 2, K.CHITIN), low)
            # The pad on the ground and one short hooked claw.
            sk.auto(K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.045, 0.045, 0.046], 8, 3, K.SINEW),
                    [low, foot])  # fmt: skip
            sk.rigid(sk.sphere(j[3], 0.05, 8, 4, scale=(1.05, 1.15, 0.68), mi=K.SINEW), foot)
            fwd = Vector((j[3].x - j[2].x, j[3].y - j[2].y, 0)).normalized()
            base = j[3] + fwd * 0.03 + Vector((0, 0, 0.004))
            sk.rigid(sk.cone(base, base + fwd * 0.055 + Vector((0, 0, -0.03)), 0.022, 6, K.BONE), foot)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk)
    build_sac(sk, glands)
    build_head(sk, eyes)
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


def ripple(p: Pose, phase: float, amp: float) -> None:
    """A wave along the segments from front to back (the hump travels toward the rump), amp in degrees."""
    p.set("Chest", rx(amp * 0.6 * math.sin(phase)))
    p.set("Hips", rx(-amp * 0.5 * math.sin(phase - 1.2)))
    p.set("Tail", rx(-amp * math.sin(phase - 2.2)))


def idle(t: float) -> Pose:
    """A slow throb of the bladder (a heartbeat over slow breathing), the segments breathing with it, the head
    swaying low, the mandibles working."""
    a = math.tau * t
    beat = pulse(t, 0.2, 0.06) + 0.6 * pulse(t, 0.36, 0.06)
    p = Pose(RIG, (0, 0, 0.008 * math.sin(a) - 0.006 * beat))
    p.set("Body", rx(-0.8 * math.sin(a)))
    ripple(p, a, 1.5)
    p.set("Neck", rz(6 * math.sin(a + 1.0)) @ rx(3 * math.sin(2 * a)))
    p.set("Head", rx(-2 + 3 * math.sin(a + 1.3)) @ rz(-4 * math.sin(a + 1.0)))
    p.set("Jaw", rx(-2 * max(0.0, math.sin(a * 3))))
    mandibles(p, 6 + 7 * max(0.0, math.sin(a * 3 + 0.5)))
    s = 1.0 + 0.02 * math.sin(a) + 0.035 * beat
    p.grow("Sac", s, s + 0.01 * beat, s)
    return p


def run(t: float) -> Pose:
    """A slow, heavy waddle (legs at rest, the game steps them): two heavy bobs per stride, the body rolling from side
    to side, the segments rippling from front to back, the bladder lagging behind, sloshing and squashing."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = Pose(RIG, (0, 0, -0.015 + 0.015 * bob))
    p.set("Body", rx(1.2 * math.sin(2 * a + 0.4)) @ ry(4 * math.sin(a)) @ rz(2.5 * math.sin(a)))
    ripple(p, 2 * a, 3.0)
    p.set("Neck", rx(3 + 3 * math.sin(2 * a + 0.8)) @ rz(-4 * math.sin(a)))
    p.set("Head", rx(-2 * math.sin(2 * a)))
    mandibles(p, 6)
    lag = 2 * a - 1.3
    p.set("Sac", rx(2 * math.sin(lag)) @ ry(-3.5 * math.sin(a - 1.0)))
    sq = math.sin(lag)
    p.grow("Sac", 1.0 + 0.03 * math.sin(lag + 1.0), 1.0 - 0.05 * sq, 1.0 + 0.03 * math.sin(lag + 1.0))
    return p


ATTACK_FRAMES = 15  # 0.5 s


def attack(t: float) -> Pose:
    """The pre-burst (0.5 s): the bladder swells to x1.3 (by 0.85) and shudders harder and harder, the body braces
    (sinks, the segments bunching, the rump pressing down), the head pulls up with the mandibles flared; it ends at its
    biggest."""
    swell = K.smooth(t / 0.85)
    brace = K.smooth(t / 0.4)
    shudder = 0.03 * math.sin(math.tau * 7 * t) * K.smooth(t / 0.3)
    p = Pose(RIG, (0, 0, -0.035 * brace))
    p.set("Body", rx(-1.5 * brace) @ rz(1.2 * math.sin(math.tau * 9 * t) * brace))
    p.set("Chest", rx(3 * brace))
    p.set("Hips", rx(2 * brace))
    p.set("Tail", rx(-6 * brace))
    p.set("Neck", rx(10 * brace))
    p.set("Head", rx(6 * brace))
    p.set("Jaw", rx(-8 * brace))
    mandibles(p, 6 + 22 * brace)
    s = 1.0 + 0.3 * swell
    p.grow("Sac", s + shudder, s - 0.7 * shudder, s + shudder)
    return p


DIE_FRAMES = 45  # 1.5 s
DEAD_DROP = 0.06  # how far the Body sinks once it lies flat
HUSK = (1.03, 0.5, 0.95)  # the burst bladder's scale (width, height, length): a flat skin over the back


def die_trunk(p: Pose, f: float) -> None:
    p.set("Body", ry(4 * f) @ rx(1.5 * f))
    p.set("Chest", rx(-3 * f))
    p.set("Hips", rx(-1.5 * f))
    p.set("Tail", rx(-1.5 * f))
    p.set("Neck", rx(-14 * f) @ rz(10 * f))
    p.set("Head", rx(-6 * f))
    p.set("Jaw", rx(10 * f))
    mandibles(p, 26 * f)


@functools.cache
def dead_legs() -> dict:
    """Per leg once splayed (world positions with the body down): the ankle slid out sideways on the ground."""
    out = {}
    for leg in LEGS:
        for side, s in K.SIDES:
            ankle = RIG.head[f"{leg}{side}Foot"]
            out[f"{leg}{side}"] = ankle + Vector((s * 0.09, 0, -0.02))
    return out


def two_bone(hip: Vector, target: Vector, a: float, b: float, pole: Vector) -> Vector:
    """The knee of a two-bone chain from hip reaching target (bone lengths a, b), bending towards pole."""
    d = target - hip
    dist = min(max(d.length, abs(a - b) + 1e-4), a + b - 1e-4)
    axis = d.normalized()
    x = (a * a - b * b + dist * dist) / (2 * dist)
    side = (pole - axis * pole.dot(axis)).normalized()
    return hip + axis * x + side * math.sqrt(max(a * a - x * x, 0.0))


def splay_legs(p: Pose, u: float) -> None:
    """Splays the legs by u (0 = rest, 1 = dead) on the posed body: each ankle slides out on the ground, the knee
    bending by two-bone IK up and out under the sagging belly, the pad tipping flat."""
    for name, ankle1 in dead_legs().items():
        up, low, foot = f"{name}UpperLeg", f"{name}LowerLeg", f"{name}Foot"
        s = 1.0 if "Left" in name else -1.0
        hip = pose_head(p, up)
        knee0, ankle0 = RIG.head[low], RIG.head[foot]
        pole = (knee0 - RIG.head[up]) + Vector((s * 0.05, 0, 0.12 * u))
        a, b = (knee0 - RIG.head[up]).length, (ankle0 - knee0).length
        ankle = ankle0.lerp(ankle1, u)
        knee = two_bone(hip, ankle, a, b, pole)
        aim(p, up, knee - hip)
        aim(p, low, ankle - knee)
        rest = (RIG.tail[foot] - RIG.head[foot]).normalized()
        flat = Vector((rest.x + s * 0.4, rest.y, 0)).normalized() + Vector((0, 0, -0.25))
        aim(p, foot, rest.lerp(flat.normalized(), u))


def die(t: float) -> Pose:
    """The burst: the bladder pops to x1.15 (0.04 s) and collapses into a flat husk by 0.15 s, which wobbles and
    sags; the body sinks flat onto the ground (by about 1 s), the legs splaying out under it, the head dropping."""
    st = t * DIE_FRAMES / FPS
    f = K.smooth((st - 0.1) / 0.9)
    sag = K.smooth((st - 0.15) / 1.0)
    jolt = 0.015 * math.sin(math.pi * min(st / 0.15, 1.0))
    p = Pose(RIG, (0, 0, -DEAD_DROP * f + jolt))
    die_trunk(p, f)
    splay_legs(p, K.smooth((st - 0.1) / 0.8))
    p.set("Sac", rx(-3 * sag) @ ry(9 * sag))
    if st < 0.04:
        k = 1.0 + 0.15 * K.smooth(st / 0.04)
        p.grow("Sac", k, k, k)
    elif st < 0.15:
        u = K.smooth((st - 0.04) / 0.11)
        p.grow("Sac", *(1.15 + (h - 1.15) * u for h in HUSK))
    else:
        wob = 0.05 * math.exp(-(st - 0.15) * 7) * math.sin((st - 0.15) * 34)
        w, h, ln = HUSK
        p.grow("Sac", w + 0.02 * sag + 0.4 * wob, h - 0.04 * sag - wob, ln + 0.4 * wob)
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
    ry_ = SAC_R[1]
    _c, cw, ct, _cb = sac_shape(SAC_C.y)
    print("POINT sac center rest", rnd(SAC_C), "half-width", round(cw, 3), "half-length", ry_, "top", round(ct, 3))
    print("POINT sac top", round(SAC_C.z + ct, 3), "radius (mean)", round((cw + ry_ + ct) / 3, 3))
    print("POINT head (Head bone head)", rnd(SKULL), "snout", rnd(SNOUT), "head center", rnd(HEAD_SHAPE.at(0.5)[0]))
    for leg, pts in LEGS.items():
        print("POINT knee", leg, rnd(pts[1]), "ankle", rnd(pts[2]))
    for name, pose in (
        ("rest", Pose(RIG)),
        ("die15", die(0.15 * FPS / DIE_FRAMES)),
        ("die5", die(0.5)),
        ("die", die(1.0)),
        ("attack", attack(1.0)),
        ("run", run(0.0)),
        ("run25", run(0.25)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        print("POINT", name, "stats", C.stats(), "lowest", lowest_parts(6))
    dips = []
    for f in range(0, DIE_FRAMES + 1, 3):
        apply(arm, die(f / DIE_FRAMES))
        bpy.context.view_layer.update()
        dips.append((C.stats()["min"][2], f, lowest_parts(2)))
    print("POINT die lowest per frame", dips)
    rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------


def add_other(strain: str, x: float, y: float) -> list:
    """Another strain's rest-pose mesh beside the bloater for a comparison (wip only, from its procedural .blend)."""
    src = ROOT / "tmp" / "assets" / strain / f"{strain}_procedural.blend"
    if not src.exists():
        return []
    with bpy.data.libraries.load(str(src)) as (data_from, data_to):
        data_to.meshes = [m for m in ("Creature", "Eyes", "Glands") if m in data_from.meshes]
    objs = []
    for me in data_to.meshes:
        obj = bpy.data.objects.new(f"Scale{strain}{me.name}", me)
        C.link(obj, None, "Preview")
        obj.location = (x, y, 0)
        objs.append(obj)
    return objs


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.9, 1.5, 0))
    shots = []
    w = OUT / "wip"
    target = (0, -0.05, 0.42)
    rest_pose(arm)
    for view, zoom in (("iso", 0.5), ("hero", 0.55), ("back", 0.6), ("iso", 1.4)):
        path = w / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(w / f"{tag}_side.png", Vector((6.0, -0.05, 0.6)), (0, -0.05, 0.42), 50, 32, 512)
    C.render_from(w / f"{tag}_head.png", Vector((0.9, -2.3, 0.75)), (0, -0.72, 0.33), 50, 32, 512)
    C.render_from(w / f"{tag}_top.png", Vector((0.0, -0.01, 6.0)), (0, 0.0, 0.0), 50, 32, 512)
    shots += [w / f"{tag}_side.png", w / f"{tag}_head.png", w / f"{tag}_top.png"]
    for name, pose in (
        ("idle", idle(0.2)),
        ("run", run(0.25)),
        ("attack", attack(1.0)),
        ("die1", die(0.15 * FPS / DIE_FRAMES)),
        ("die5", die(0.5)),
        ("die", die(1.0)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        path = w / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.55)
        shots.append(path)
    apply(arm, die(1.0))
    bpy.context.view_layer.update()
    path = w / f"{tag}_die_side.png"
    C.render_from(path, Vector((6.0, -0.05, 0.4)), (0, -0.05, 0.25), 50, 24, 512)
    shots.append(path)
    rest_pose(arm)
    path = w / f"{tag}_under.png"
    C.render_from(path, Vector((2.2, -1.6, 0.25)), (0.2, -0.15, 0.2), 40, 24, 512)
    shots.append(path)
    if MODE == "wip":
        scale = add_other("spitter", -2.2, 0.8) + add_other("burrower", 2.3, 0.6)
        if scale:
            path = w / f"{tag}_scale.png"
            C.render(path, view="iso", samples=32, size=512, target=(0.0, 0.3, 0.4), zoom=0.95)
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
