"""Tender: the hive's healer (tier 4), a hunter that stays back and mends the others. A medium, low and wide alien on
six splayed legs, its back a mosaic of chitin plates with clusters of glowing glands bulging between them like grape
bunches, and three long tendrils rising from its shoulders and its back, curling forward over its head, each tipped
with a glowing bulb (the game's healing links start at the tips). A short blunt head low at the front under a shield,
small glowing eyes and small mandibles. Rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/tender/source/tender_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/tender/source/tender_build.py stats      # measures and pose bounds only
    tools/blender.sh assets/aliens/tender/source/tender_build.py final      # renders + tender_procedural.blend

Everything it writes goes to tmp/assets/tender/; tender_bake.py turns tender_procedural.blend into the game asset.

Layout (Blender Z-up meters; the tender faces -Y, its left is +X; the game turns the model by 180 degrees). Feet on
the ground at the origin, the origin under the middle of the body; the back about 0.7 m high, the mandibles to the
rump about 1.45 m, the tendrils' curls reaching about 1.6 m (the middle one) and 1.5 m (the shoulder ones).

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rump) with the hind legs,
Spine with the mid legs and the middle tendril, Chest with the front legs and the shoulder tendrils, Neck, Head, Jaw
with LeftMandible and RightMandible. Tendrils Tendril<n>A, B, C (the stalk from its base up and over the curl) and
Tendril<n>Tip (the bulb, its head at the tip): 1 the left shoulder, 2 the middle of the back, 3 the right shoulder.
Legs (<Front|Mid|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (the femur rising out to a high
knee, the tibia down to the ankle, the Foot is the short tarsus with its claws), so the clips leave them at rest;
only "Die" folds them.
Meshes: "Creature" (one skinned object: trunk, neck, tendrils and the leg joints weighted to the nearest bones;
plates, head, mandibles and claws rigid or nearly), "Eyes" (constant emissive) and "Glands" (constant emissive: the
gland clusters on the back, skinned to the trunk, and the three bulbs, rigid to their Tip bones; the game flares
them with the eyes).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: the tendrils sway slowly and out
of phase, slow breathing), "Run" (loop: a low scuttle of the trunk, the tendrils trailing back; the legs come from
the game), "Attack" (once, 0.5 s: the tendrils draw back, then lash forward over the head, the impact at frame 8)
and "Die" (once: the tendrils go limp and drop, the legs fold, it sinks onto its belly).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "tender"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Matrix, Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Tender"
FPS = 30
GLAND_GLOW = 2.5  # the clusters and the bulbs (the eyes: 8 in the previews)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.46))
CHEST = Vector((0, -0.22, 0.455))
NECK = Vector((0, -0.46, 0.44))
SKULL = Vector((0, -0.53, 0.43))
SNOUT = Vector((0, -0.72, 0.39))
JAW = Vector((0, -0.66, 0.37))
MANDIBLE = [Vector((0.07, -0.69, 0.355)), Vector((0.085, -0.75, 0.345)), Vector((0.05, -0.8, 0.335))]
MANDIBLE_TIP = Vector((0.018, -0.815, 0.332))
# Leg joints per side (x for the left side): hip, knee, ankle, pad (the claws' base on the ground).
LEGS = {
    "Front": [
        Vector((0.22, -0.3, 0.39)),
        Vector((0.47, -0.47, 0.6)),
        Vector((0.58, -0.66, 0.09)),
        Vector((0.61, -0.71, 0.028)),
    ],
    "Mid": [
        Vector((0.27, -0.06, 0.38)),
        Vector((0.56, -0.07, 0.6)),
        Vector((0.7, -0.09, 0.09)),
        Vector((0.74, -0.1, 0.028)),
    ],
    "Hind": [
        Vector((0.25, 0.18, 0.39)),
        Vector((0.5, 0.35, 0.6)),
        Vector((0.61, 0.56, 0.09)),
        Vector((0.645, 0.61, 0.028)),
    ],
}
LEG_PARENT = {"Front": "Chest", "Mid": "Spine", "Hind": "Hips"}
# Tendrils (x for the left one; 3 mirrors 1): the parent and the stalk's path from its base inside the body up over
# the curl to the tip; the joints at path points 0, 1, 2 and the last (the tip, the Tip bone's head); point 3 only
# shapes the curl.
TENDRILS = {
    "Tendril1": (
        "Chest",
        1.0,
        [
            Vector((0.19, -0.16, 0.6)),
            Vector((0.29, -0.11, 0.97)),
            Vector((0.39, -0.15, 1.32)),
            Vector((0.44, -0.3, 1.49)),
            Vector((0.45, -0.5, 1.38)),
        ],
    ),
    "Tendril2": (
        "Spine",
        0.0,
        [
            Vector((0.0, 0.05, 0.62)),
            Vector((0.0, 0.12, 1.05)),
            Vector((0.0, 0.08, 1.45)),
            Vector((0.0, -0.1, 1.63)),
            Vector((0.0, -0.3, 1.52)),
        ],
    ),
}
# A point inside each curl: the stalk's scales face away from it.
CURL_CENTER = {"Tendril1": Vector((0.5, -0.36, 1.25)), "Tendril2": Vector((0.0, -0.16, 1.38))}
CURL_CENTER["Tendril3"] = K.mirror(CURL_CENTER["Tendril1"], -1.0)
TENDRILS["Tendril3"] = ("Chest", -1.0, [K.mirror(p, -1.0) for p in TENDRILS["Tendril1"][2]])
TENDRIL_RADII = [0.075, 0.06, 0.05, 0.042, 0.034]  # along the stalk (the tip's diameter about 7 cm)
TIP_LENGTH = 0.14


def tip_dir(pts: list) -> Vector:
    """Direction the stalk ends in at its tip (the bulb's axis)."""
    return (K.path_point(pts, 1.0) - K.path_point(pts, 0.94)).normalized()


BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, Vector((0, 0.6, 0.44)), "Body"),
    ("Spine", BODY, CHEST, "Body"),
    ("Chest", CHEST, NECK, "Spine"),
    ("Neck", NECK, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW, Vector((0, -0.78, 0.35)), "Head"),
]
for _n, (_parent, _s, _pts) in TENDRILS.items():
    _tip = _pts[-1]
    BONES += [
        (f"{_n}A", _pts[0], _pts[1], _parent),
        (f"{_n}B", _pts[1], _pts[2], f"{_n}A"),
        (f"{_n}C", _pts[2], _tip, f"{_n}B"),
        (f"{_n}Tip", _tip, _tip + tip_dir(_pts) * TIP_LENGTH, f"{_n}C"),
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

# Trunk profile from the rump forward (rows evenly spaced in y): y, center z, half-width, top, bottom. Broad and
# flattened, widest over the mid legs.
TRUNK = [
    (0.64, 0.44, 0.06, 0.045, 0.04),
    (0.524, 0.45, 0.235, 0.15, 0.125),
    (0.408, 0.46, 0.33, 0.2, 0.155),
    (0.292, 0.465, 0.37, 0.215, 0.165),
    (0.176, 0.466, 0.385, 0.22, 0.17),
    (0.06, 0.466, 0.385, 0.222, 0.17),
    (-0.056, 0.463, 0.375, 0.218, 0.165),
    (-0.172, 0.458, 0.355, 0.208, 0.16),
    (-0.288, 0.452, 0.32, 0.192, 0.15),
    (-0.404, 0.444, 0.25, 0.155, 0.12),
    (-0.52, 0.435, 0.13, 0.085, 0.075),
]
TRUNK_SHAPE = K.Profile(TRUNK)
# Head from the back of the skull to its blunt front: y, center z, half-width, top, bottom.
HEAD = [
    (-0.48, 0.432, 0.11, 0.085, 0.075),
    (-0.523, 0.427, 0.14, 0.098, 0.085),
    (-0.567, 0.421, 0.152, 0.1, 0.088),
    (-0.61, 0.413, 0.148, 0.095, 0.083),
    (-0.653, 0.404, 0.134, 0.084, 0.074),
    (-0.697, 0.394, 0.104, 0.064, 0.058),
    (-0.74, 0.384, 0.056, 0.034, 0.032),
]
HEAD_SHAPE = K.Profile(HEAD)
# The gland clusters between the plates of the back: (y, angle on the left side (90 = the top), grapes); the right
# side mirrors them.
CLUSTERS = [(-0.03, 50, 9), (0.19, 48, 10), (0.4, 50, 9)]
CENTER_CLUSTERS = [(0.27, 11), (0.47, 9)]  # down the middle behind the middle tendril: (y, grapes)
CLUSTER_CENTERS: list = []  # filled by build_back (rest pose, for the report)


def side_angle(a: float, s: float) -> float:
    return a if s > 0 else 180 - a


def angles(a0: float, a1: float, s: float) -> tuple:
    return tuple(sorted((side_angle(a0, s), side_angle(a1, s))))


def build_trunk(sk: K.Skin) -> None:
    n = 18
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.006, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # Belly: overlapping segments under the trunk.
    for y0, y1 in ((-0.42, -0.2), (-0.24, 0.0), (-0.04, 0.2), (0.16, 0.4), (0.36, 0.58)):
        sk.auto(K.shell(sk, TRUNK_SHAPE, y0, y1, 222, 318, 0.004, 0.018, K.CHITIN, 6, 2, 0.008), TRUNK_BONES, 8.0)


def build_back(sk: K.Skin, glands: K.Skin) -> None:
    """Plates over the back: a shield over the shoulders and the chest, a plate in front of the middle tendril, the
    flanks in overlapping segments, a row of narrow plates on each side of the middle and a cap over the rump; the
    gland clusters bulge out between them, in a row along each side and two down the middle."""
    w = TRUNK_BONES
    sk.auto(K.shell(sk, TRUNK_SHAPE, -0.55, -0.24, -4, 184, 0.008, 0.045, K.CHITIN, 12, 4, 0.03), w, 8.0)
    sk.auto(K.shell(sk, TRUNK_SHAPE, -0.27, -0.05, 68, 112, 0.008, 0.04, K.CHITIN, 4, 3, 0.02), w, 8.0)
    sk.auto(K.shell(sk, TRUNK_SHAPE, 0.53, 0.68, 8, 172, 0.008, 0.035, K.CHITIN, 8, 2, 0.02), w, 8.0)
    for _side, s in K.SIDES:
        a0, a1 = angles(-22, 34, s)
        for y0, y1 in ((-0.3, -0.06), (-0.1, 0.15), (0.11, 0.36), (0.32, 0.6)):
            sk.auto(K.shell(sk, TRUNK_SHAPE, y0, y1, a0, a1, 0.01, 0.034, K.CHITIN, 4, 3, 0.03), w, 8.0)
        a0, a1 = angles(60, 77, s)
        for y0, y1 in ((-0.04, 0.2), (0.16, 0.4), (0.36, 0.58)):
            sk.auto(K.shell(sk, TRUNK_SHAPE, y0, y1, a0, a1, 0.01, 0.034, K.CHITIN, 2, 3, 0.025), w, 8.0)
        for k, (y, a, count) in enumerate(CLUSTERS):
            grapes(sk, glands, y, side_angle(a, s), count, 11 + k * 7 + (s > 0) * 3)
    for k, (y, count) in enumerate(CENTER_CLUSTERS):
        grapes(sk, glands, y, 90, count, 5 + k)


def grapes(sk: K.Skin, glands: K.Skin, y: float, a: float, count: int, seed: int) -> None:
    """A bunch of glowing glands bulging out of a fleshy pad between the plates."""
    rnd = random.Random(seed)
    c = TRUNK_SHAPE.surface(y, a, 0.0)
    n = (TRUNK_SHAPE.surface(y, a, 0.05) - c).normalized()
    m = C.basis(n, Vector((0, 1, 0)))
    u, v = m.col[0], m.col[1]
    sk.auto(sk.sphere(c, 0.085, 10, 4, scale=(1.25, 1.0, 0.35), rot=m, mi=K.SINEW), TRUNK_BONES)
    pts = []
    for i in range(count):
        ang = i * 2.39996 + rnd.uniform(-0.3, 0.3)
        rad = 0.075 * math.sqrt((i + 0.4) / count)
        r = 0.046 - 0.016 * rad / 0.075 + rnd.uniform(-0.004, 0.004)
        p = c + u * math.cos(ang) * rad * 1.25 + v * math.sin(ang) * rad + n * (0.012 + 0.03 * (1 - rad / 0.075))
        glands.auto(glands.sphere(p, r, 8, 4, scale=(1.0, 1.0, 0.9), rot=m), TRUNK_BONES)
        pts.append(p)
    CLUSTER_CENTERS.append(sum(pts, Vector()) / len(pts))


def path_length(pts: list) -> float:
    return sum((b - a).length for a, b in itertools.pairwise(pts))


def radius_at(radii: list, t: float) -> float:
    return K.catmull([[x] for x in radii], t)[0]


def band(sk: K.Skin, pts: list, radii: list, t: float, length: float, bones: list) -> None:
    """A chitin ring around the stalk at t along its path (a ridged collar)."""
    rings = []
    total = path_length(pts)
    for k, (dt, grow) in enumerate(((-0.5, 0.004), (-0.15, 0.016), (0.25, 0.014), (0.5, 0.003))):
        tt = t + dt * length / total
        c = K.path_point(pts, tt)
        d = K.path_point(pts, tt + 0.02) - K.path_point(pts, tt - 0.02)
        r = radius_at(radii, tt) + grow
        rings.append(K.section(c, d, r, r, r, 10, 0.002, t * 30 + k))
    sk.auto(sk.loft(rings, K.CHITIN), bones, 8.0)


def scale_plate(sk: K.Skin, pts: list, radii: list, t0: float, t1: float, center: Vector, bones: list) -> None:
    """A curved chitin scale on the outer side of the stalk (away from the curl's center) between t0 and t1."""
    a, b = K.path_point(pts, t0), K.path_point(pts, t1)
    facing = (a.lerp(b, 0.5) - center).normalized()
    r = radius_at(radii, (t0 + t1) / 2) + 0.003
    sk.auto(K.limb_plate(sk, a, b, r, -80, 80, 0.02, K.CHITIN, facing), bones, 8.0)


def build_tendrils(sk: K.Skin, glands: K.Skin) -> None:
    for name, (parent, _s, pts) in TENDRILS.items():
        bones = [parent, f"{name}A", f"{name}B", f"{name}C", f"{name}Tip"]
        d0 = (pts[1] - pts[0]).normalized()
        path = [pts[0] - d0 * 0.06] + pts
        radii = [TENDRIL_RADII[0] + 0.006] + TENDRIL_RADII
        sk.auto(K.tube_path(sk, path, radii, 10, 22, K.SINEW, 1.0, 0.006), bones[1:])
        # Socket: a fleshy mound where the stalk leaves the body, ringed by a chitin collar.
        base = pts[0] + d0 * 0.03
        sk.auto(sk.sphere(base, 0.11, 12, 5, scale=(1.0, 1.0, 0.55), mi=K.SINEW), [parent, bones[1]])
        ring = [base + d0 * 0.03, base + d0 * 0.07]
        sk.auto(K.tube_path(sk, ring, [0.095, 0.083], 12, 1, K.CHITIN), [parent, bones[1]], 8.0)
        # Chitin rings low on the stalk, then overlapping scales up its outer side and over the curl.
        for t, length in ((0.12, 0.05), (0.22, 0.04)):
            band(sk, path, radii, t, length, bones[1:])
        for k in range(6):
            t0 = 0.29 + k * 0.096
            scale_plate(sk, path, radii, t0, t0 + 0.115, CURL_CENTER[name], bones[1:])
        # The bulb: a glowing swelling held in a chitin cup at the tip.
        tip, d = pts[-1], tip_dir(pts)
        cup = [tip - d * 0.05, tip - d * 0.01, tip + d * 0.02]
        sk.rigid(K.tube_path(sk, cup, [0.036, 0.056, 0.058], 12, 3, K.CHITIN), f"{name}Tip")
        bulb = C.basis(d, Vector((1, 0, 0)))
        glands.rigid(glands.sphere(tip + d * 0.06, 0.066, 14, 8, scale=(1.0, 1.0, 1.2), rot=bulb), f"{name}Tip")


def build_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Short neck from under the shield into the back of the head.
    pts = [Vector((0, -0.4, 0.445)), Vector((0, -0.46, 0.44)), Vector((0, -0.51, 0.435))]
    sk.auto(K.tube_path(sk, pts, [0.12, 0.1, 0.09], 14, 4, K.SINEW), ["Chest", "Neck", "Head"])
    rings = []
    n = 10
    for i in range(n + 1):
        c, w, top, bot = HEAD_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.003, 3 + i))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    # A brow plate over the eyes and the blunt front.
    sk.rigid(K.shell(sk, HEAD_SHAPE, -0.5, -0.7, 18, 162, 0.005, 0.02, K.CHITIN, 8, 3, 0.01), "Head")
    # Mouth between the mandibles.
    sk.rigid(sk.sphere((0, -0.715, 0.36), 0.04, 10, 5, scale=(1.3, 1.0, 0.7), mi=K.MOUTH), "Jaw")
    for side, s in K.SIDES:
        bone = f"{side}Mandible"
        mp = [K.mirror(p, s) for p in MANDIBLE] + [K.mirror(MANDIBLE_TIP, s)]
        sk.rigid(K.tube_path(sk, mp, [0.024, 0.022, 0.016, 0.006], 8, 7, K.BONE, 0.7), bone)
        sk.rigid(sk.sphere(K.mirror(MANDIBLE[0], s), 0.028, 8, 4, mi=K.CHITIN), "Head")
        # Eyes: two pairs of small glowing beads on the front corners, under the brow.
        for y, a, r in ((-0.63, 44, 0.019), (-0.67, 26, 0.014)):
            eyes.rigid(eyes.sphere(HEAD_SHAPE.surface(y, side_angle(a, s), -0.004), r, 8, 4), "Head")


def build_legs(sk: K.Skin) -> None:
    for leg, pts in LEGS.items():
        body = LEG_PARENT[leg]
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            out = Vector((s, 0, 0))
            # Coxa: a fleshy socket where the leg leaves the body.
            sk.auto(sk.sphere(j[0] + out * 0.03, 0.075, 8, 5, scale=(1.0, 1.0, 0.85), mi=K.SINEW), [body, up])
            # Femur: a chitin segment rising out to the high knee, a ridge plate on top.
            mid = j[0].lerp(j[1], 0.5) + Vector((0, 0, 0.022))
            femur = K.tube_path(sk, [j[0], mid, j[1]], [0.066, 0.06, 0.046], 8, 5, K.CHITIN, 1.0, 0.003)
            sk.auto(femur, [body, up, low])
            a, b = j[0].lerp(j[1], 0.3), j[1].lerp(j[0], 0.12)
            sk.rigid(K.limb_plate(sk, a, b, 0.058, -60, 60, 0.014, K.CHITIN, Vector((s * 0.3, 0, 1))), up)
            # Knee: a chitin cap with a short blunt spur.
            cap = j[1] + Vector((s * 0.01, 0, 0.014))
            sk.rigid(sk.sphere(cap, 0.05, 8, 4, scale=(1.1, 1.1, 0.8), mi=K.CHITIN), low)
            sk.rigid(sk.cone(cap, cap + Vector((s * 0.05, 0, 0.035)), 0.026, 5, K.CHITIN), low)
            # Tibia: down to the ankle, a spur on its inner side.
            mid = j[1].lerp(j[2], 0.5) + out * 0.014
            sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.046, 0.038, 0.029], 8, 5, K.CHITIN), [up, low, foot])
            inner = Vector((j[0].x - j[1].x, j[0].y - j[1].y, 0)).normalized()
            base = j[1].lerp(j[2], 0.55)
            sk.rigid(sk.cone(base, base + (inner * 0.6 + Vector((0, 0, -0.5))).normalized() * 0.05, 0.013, 4), low)
            # Tarsus to the pad, two hooked claws gripping the ground.
            tarsus = K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.029, 0.026, 0.028], 6, 3, K.SINEW)
            sk.auto(tarsus, [low, foot])
            sk.rigid(sk.sphere(j[3], 0.031, 8, 4, scale=(1.1, 1.2, 0.8), mi=K.CHITIN), foot)
            fwd = Vector((j[3].x - j[0].x, j[3].y - j[0].y, 0)).normalized()
            for k in (-1, 1):
                d = (fwd + Vector((-fwd.y, fwd.x, 0)) * 0.45 * k).normalized()
                tip = j[3] + d * 0.055 + Vector((0, 0, -0.026))
                sk.rigid(sk.cone(j[3] + Vector((0, 0, 0.004)), tip, 0.014, 5, K.BONE), foot)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk)
    build_back(sk, glands)
    build_tendrils(sk, glands)
    build_head(sk, eyes)
    build_legs(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------
# Tendril rotations: rx(+) tips a stalk forward (towards -Y), ry(+) towards +X (the left).


def mandibles(p: K.Pose, spread: float) -> None:
    for side, s in K.SIDES:
        p.set(f"{side}Mandible", rz(s * spread))


def stalk(p: K.Pose, name: str, pitch: tuple, roll: tuple = (0, 0, 0, 0), yaw: float = 0.0) -> None:
    """Bends a tendril: pitch and roll per segment (A, B, C, Tip), yaw turns it around its base."""
    for k, seg in enumerate(("A", "B", "C", "Tip")):
        m = rx(pitch[k]) @ ry(roll[k])
        if k == 0:
            m = rz(yaw) @ m
        p.set(f"{name}{seg}", m)


def out_side(name: str) -> float:
    """+1 for the left tendril, -1 for the right, 0 for the middle one."""
    return TENDRILS[name][1]


def idle(t: float) -> K.Pose:
    """Slow breathing; each tendril sways in its own phase, the motion running up the stalk to the bulb."""
    a = math.tau * t
    breath = math.sin(a)
    p = K.Pose(RIG, (0, 0, 0.008 * breath))
    p.set("Body", rx(-0.8 * breath))
    p.set("Chest", rx(0.8 * breath))
    p.set("Neck", rx(2 * math.sin(a + 0.6)) @ rz(5 * math.sin(a + 1.0)))
    p.set("Head", rx(-2 + 2 * math.sin(2 * a + 1.2)) @ rz(-3 * math.sin(a + 1.0)))
    p.set("Jaw", rx(-2 * max(0.0, math.sin(a * 3))))
    mandibles(p, 5 + 6 * max(0.0, math.sin(a * 4 + 0.5)))
    for i, name in enumerate(TENDRILS):
        ph = i * 2.2
        o = out_side(name)
        sw = [math.sin(a + ph - 0.7 * k) for k in range(4)]
        side = [math.sin(a + ph + 1.3 - 0.7 * k) for k in range(4)]
        pitch = (3 * sw[0], 5 * sw[1], 7 * sw[2], 8 * sw[3])
        roll = tuple(v * (2 + 2 * k) * (o if o else 1.0) for k, v in enumerate(side))
        stalk(p, name, pitch, roll, 4 * math.sin(a + ph + 0.4))
    return p


def run(t: float) -> K.Pose:
    """A low scuttle (legs at rest, the game steps them): two quick bobs per stride, the trunk swaying, the head low;
    the tendrils lean back and trail, fluttering with the bobs."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0, 0, -0.02 + 0.015 * bob))
    p.set("Body", rx(2 + 1.5 * math.sin(2 * a + 0.4)) @ ry(3 * math.sin(a)) @ rz(2.5 * math.sin(a)))
    p.set("Hips", rx(-1.5 * math.sin(2 * a - 0.8)) @ rz(-2.5 * math.sin(a - 0.5)))
    p.set("Chest", rz(-1.5 * math.sin(a)))
    p.set("Neck", rx(5 + 1.5 * math.sin(2 * a)))
    p.set("Head", rx(2 - 2 * math.sin(2 * a)))
    mandibles(p, 4)
    for i, name in enumerate(TENDRILS):
        ph = 2 * a - 1.0 - 0.5 * i
        o = out_side(name)
        fl = [math.sin(ph - 0.8 * k) for k in range(4)]
        pitch = (-32 + 2 * fl[0], -24 + 4 * fl[1], -36 + 6 * fl[2], -24 + 8 * fl[3])
        roll = (6 * o, 3 * o + 2 * math.sin(a - 0.8 - 0.4 * i), 2 * math.sin(a - 0.6), 0)
        stalk(p, name, pitch, roll, -4 * o * math.sin(a))
    return p


ATTACK_FRAMES = 15
IMPACT = 8  # the frame the tendrils strike (0.27 s)


def attack(t: float) -> K.Pose:
    """The lash (0.5 s): the trunk crouches and the tendrils draw back and up (to 0.3), then whip forward over the
    head and straighten towards the target at head height (the impact at frame 8), then recover."""
    hit = IMPACT / ATTACK_FRAMES
    draw = K.smooth(t / 0.3) * (1 - K.smooth((t - 0.3) / (hit - 0.3)))
    lash = K.smooth((t - 0.3) / (hit - 0.3)) * (1 - K.smooth((t - hit - 0.1) / (0.9 - hit)))
    p = K.Pose(RIG, (0, 0.04 * draw - 0.06 * lash, -0.02 * draw + 0.01 * lash))
    p.set("Body", rx(-5 * draw + 6 * lash))
    p.set("Hips", rx(3 * draw - 2 * lash))
    p.set("Neck", rx(-6 * draw + 4 * lash))
    p.set("Head", rx(-4 * draw))
    p.set("Jaw", rx(-12 * max(draw, lash)))
    mandibles(p, 6 + 24 * max(draw, lash))
    for i, name in enumerate(TENDRILS):
        o = out_side(name)
        late = 1 - K.smooth((t - hit - 0.05 * i) / 0.4)  # a little out of step in the recovery
        lash_i = lash * late if t > hit else lash
        pitch = (-14 * draw + 50 * lash_i, -10 * draw - 12 * lash_i, -14 * draw - 36 * lash_i, -8 * draw - 30 * lash_i)
        roll = (-6 * o * lash_i, -3 * o * lash_i, 0, 0)
        stalk(p, name, pitch, roll)
    return p


def lift(leg: str, s: float, deg: float) -> Matrix:
    """Rotation raising a leg's outer end by deg (about the horizontal axis across the leg)."""
    hip, pad = K.mirror(LEGS[leg][0], s), K.mirror(LEGS[leg][3], s)
    h = Vector((pad.x - hip.x, pad.y - hip.y, 0)).normalized()
    return Matrix.Rotation(math.radians(-deg), 3, K.UP.cross(h))


def die(t: float) -> K.Pose:
    """The tendrils go limp at once and drop (the shoulder ones out over the sides, the middle one back over the
    rump), bouncing once; the legs buckle (to 0.35) and splay, it sinks onto its belly (0.65)."""
    k = K.smooth(t / 0.35)
    f = K.smooth((t - 0.15) / 0.5)
    g = K.smooth((t - 0.05) / 0.45)  # the legs fold ahead of the drop
    limp = K.smooth(t / 0.55)
    bounce = math.sin(math.pi * K.smooth((t - 0.45) / 0.35)) * (1 - K.smooth((t - 0.6) / 0.4))
    p = K.Pose(RIG, (0.0, 0.0, -0.03 * k - 0.23 * f))
    p.set("Body", ry(3 * f) @ rx(2 * f))
    p.set("Neck", rx(6 * f) @ rz(8 * f))
    p.set("Head", rx(1 * f))
    p.set("Jaw", rx(-8 * f))
    mandibles(p, 26 * f)
    drop = limp - 0.12 * bounce
    for name in TENDRILS:
        o = out_side(name)
        if o:
            roll = (o * 68 * drop, o * 26 * drop, o * 16 * drop, o * 10 * drop)
            stalk(p, name, (-8 * drop, -8 * drop, -6 * drop, 0), roll)
        else:  # the middle one back over the right flank
            stalk(p, name, (-6 * drop, -4 * drop, 0, 0), (-72 * drop, -40 * drop, -36 * drop, -20 * drop), -45 * drop)
    for side, s in K.SIDES:
        for leg, amp in (("Front", 1.1), ("Mid", 1.0), ("Hind", 0.9)):
            p.set(f"{leg}{side}UpperLeg", lift(leg, s, 12 * k * (1 - g) - 8 * g * amp))
            p.set(f"{leg}{side}LowerLeg", lift(leg, s, -12 * k * (1 - g) + 62 * g * amp))
            p.set(f"{leg}{side}Foot", lift(leg, s, -4 * k + 16 * g))
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (18, run),
    "Attack": (ATTACK_FRAMES, attack),
    "Die": (36, die),
}

# --- report -------------------------------------------------------------------------------------------


def mesh_points(name: str) -> list:
    obj = bpy.data.objects[name]
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    pts = [ev.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def fmt(v) -> tuple:
    return tuple(round(x, 3) for x in v)


def tips(arm: bpy.types.Object) -> list:
    return [fmt(arm.matrix_world @ arm.pose.bones[f"{n}Tip"].head) for n in TENDRILS]


def report(arm: bpy.types.Object) -> None:
    K.rest_pose(arm)
    body = mesh_points("Creature")
    glow = mesh_points("Glands")
    eyes = mesh_points("Eyes")
    allp = body + glow + eyes
    lo = Vector([min(p[i] for p in allp) for i in range(3)])
    hi = Vector([max(p[i] for p in allp) for i in range(3)])
    print("MEASURE bounds", fmt(lo), fmt(hi), "size", fmt(hi - lo))
    back = max((p for p in body + glow if abs(p.x) < 0.45 and p.y > 0.2 and p.z < 0.9), key=lambda p: p.z)
    print("MEASURE back", fmt(back))
    trunk = [p for p in body if p.z < 0.9 and abs(p.x) < 0.4]
    print(
        "MEASURE length",
        round(max(p.y for p in trunk) - min(p.y for p in trunk), 3),
        "front",
        fmt(min(trunk, key=lambda p: p.y)),
    )
    print("MEASURE tendril tips rest (Tip heads)", tips(arm))
    print(
        "MEASURE tendril tops",
        [round(max(p.z for p in body if abs(p.x - TENDRILS[n][2][3].x) < 0.12), 3) for n in TENDRILS],
    )
    c = sum(CLUSTER_CENTERS, Vector()) / len(CLUSTER_CENTERS)
    print("MEASURE gland cluster center", fmt(c), "clusters", [fmt(x) for x in CLUSTER_CENTERS])
    for name, (frames, fn) in CLIPS.items():
        zs = []
        for f in range(frames + 1):
            K.apply(arm, fn(f / frames))
            bpy.context.view_layer.update()
            pts = mesh_points("Glands")
            low = trunk_low(name != "Die")
            zs.append((min(low, min(p.z for p in pts)), max(max(p.z for p in pts), max_z("Creature"))))
        lowest = min(range(len(zs)), key=lambda i: zs[i][0])
        print(
            f"MEASURE {name} min z {zs[lowest][0]:.3f} (frame {lowest}) max z {max(z[1] for z in zs):.3f}"
            f" end min z {zs[-1][0]:.3f} end max z {zs[-1][1]:.3f}"
        )
        if name == "Attack":
            K.apply(arm, fn(IMPACT / frames))
            bpy.context.view_layer.update()
            print("MEASURE attack impact tips (frame", IMPACT, ")", tips(arm))
        if name == "Die":
            K.apply(arm, fn(lowest / frames))
            bpy.context.view_layer.update()
            print("MEASURE die lowest frame parts", lowest_parts(8))
            K.apply(arm, fn(1.0))
            bpy.context.view_layer.update()
            print("MEASURE die end parts", lowest_parts(8))
            for n in TENDRILS:
                print(
                    "MEASURE die end",
                    n,
                    [fmt(arm.matrix_world @ arm.pose.bones[f"{n}{b}"].head) for b in "ABC"],
                    tips(arm),
                )
    K.rest_pose(arm)


def max_z(name: str) -> float:
    return max(p.z for p in mesh_points(name))


def trunk_low(skip_legs: bool) -> float:
    """Lowest posed vertex of "Creature", without the legs (the game's IK keeps them on the ground) if skip_legs."""
    obj = bpy.data.objects["Creature"]
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    names = {g.index: g.name for g in obj.vertex_groups}
    low = 9.0
    for v, src in zip(me.vertices, obj.data.vertices):
        if skip_legs and src.groups:
            g = names[max(src.groups, key=lambda e: e.weight).group]
            if g.endswith(("UpperLeg", "LowerLeg", "Foot")):
                continue
        low = min(low, v.co.z)
    ev.to_mesh_clear()
    return low


def lowest_parts(count: int = 16) -> list:
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


# --- preview ----------------------------------------------------------------------------------------


def add_reference(x: float, strain: str = "spitter") -> list:
    """Another strain's rest-pose mesh beside the tender for a scale and silhouette check (wip only)."""
    src = ROOT / "tmp" / "assets" / strain / f"{strain}_procedural.blend"
    if not src.exists():
        return []
    with bpy.data.libraries.load(str(src)) as (data_from, data_to):
        data_to.meshes = [m for m in ("Creature", "Eyes", "Glands") if m in data_from.meshes]
    objs = []
    for me in data_to.meshes:
        obj = bpy.data.objects.new("Ref" + me.name, me)
        C.link(obj, None, "Preview")
        obj.location = (x, 0.6, 0)
        objs.append(obj)
    return objs


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.5, 1.1, 0))
    w = OUT / "wip"
    shots = []
    target = (0, -0.05, 0.75)
    K.rest_pose(arm)
    for view, zoom in (("iso", 0.32), ("hero", 0.4), ("back", 0.42), ("iso", 1.4)):
        path = w / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    for name, loc, aim in (
        ("side", (3.6, -0.1, 0.9), (0, -0.05, 0.75)),
        ("head", (0.9, -1.9, 0.9), (0, -0.55, 0.5)),
        ("top", (0.0, -0.05, 4.2), (0, -0.05, 0.0)),
    ):
        path = w / f"{tag}_{name}.png"
        C.render_from(path, Vector(loc), aim, 50, 32, 512)
        shots.append(path)
    for name, pose in (
        ("idle", idle(0.3)),
        ("run", run(0.25)),
        ("attack3", attack(0.3)),
        ("attack_hit", attack(IMPACT / ATTACK_FRAMES)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        path = w / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.42)
        shots.append(path)
    K.apply(arm, attack(IMPACT / ATTACK_FRAMES))
    bpy.context.view_layer.update()
    path = w / f"{tag}_attack_side.png"
    C.render_from(path, Vector((3.8, -0.5, 1.0)), (0, -0.5, 0.8), 50, 24, 512)
    shots.append(path)
    K.apply(arm, run(0.25))
    bpy.context.view_layer.update()
    path = w / f"{tag}_run_side.png"
    C.render_from(path, Vector((3.6, -0.1, 0.9)), (0, -0.05, 0.75), 50, 24, 512)
    shots.append(path)
    K.apply(arm, die(1.0))
    bpy.context.view_layer.update()
    path = w / f"{tag}_die_top.png"
    C.render_from(path, Vector((0.0, -0.05, 4.2)), (0, -0.05, 0.0), 50, 24, 512)
    shots.append(path)
    path = w / f"{tag}_die_side.png"
    C.render_from(path, Vector((3.6, -0.1, 0.5)), (0, 0.0, 0.25), 50, 24, 512)
    shots.append(path)
    K.rest_pose(arm)
    if MODE == "wip":
        ref = add_reference(-1.9)
        if ref:
            path = w / f"{tag}_scale.png"
            C.render(path, view="iso", samples=32, size=512, target=(-0.9, 0.3, 0.6), zoom=0.5)
            shots.append(path)
            for obj in ref:
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
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "tender_procedural.blend")
        C.export_glb(OUT / "tender_draft.glb")


main()
