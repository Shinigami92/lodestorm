"""Darter: the hive's small flying hunter (tier 5, comes in packs), a slender, armored wasp-/dragonfly-like beast. An
armored thorax carries two pairs of large translucent wings (span about 1.7 m, so the shape reads from above) and six
short legs tucked under it like a flying insect's; a long, segmented abdomen hangs back from a thin waist and ends in a
glowing sting, with glowing slits across its back between the plates. A narrow armored head with big glowing compound
eyes and short hooked mandibles. Rigged and animated; it never walks.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/darter/source/darter_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/darter/source/darter_build.py stats      # measures and pose bounds, no renders
    tools/blender.sh assets/aliens/darter/source/darter_build.py final      # renders + darter_procedural.blend

Everything it writes goes to tmp/assets/darter/; darter_bake.py turns darter_procedural.blend into the game asset.

Layout (Blender Z-up meters; the darter faces -Y, its left is +X; the game turns the model by 180 degrees). It flies:
the origin is the center of the thorax in flight (not the ground), the body level in the air; the game holds it at
its flight height and drops it to the ground when it dies. Mandibles to sting tip about 1.0 m, wing span about 1.7 m.

Skeleton "Skeleton": Root, Body (center of the thorax: moves the whole body), Hips (the rear of the thorax) with the
abdomen chain Tail1, Tail2, Tail3 and Sting, Spine, Chest (the front of the thorax) with the four wings
(Wing<Front|Hind><Left|Right>: hinged at the wing root, the bone along the wing out to its tip, so a rotation about
the bone's local X axis beats it, positive = up), Neck, Head, Jaw with the two mandibles (<Side>Mandible, they open
sideways). No leg bones: the legs are rigid parts of the thorax (on Chest).
Meshes: "Creature" (one skinned object: the thorax and abdomen weighted to the nearest bones; plates, head, legs and
the wings' chitin leading edges rigid), "Eyes" and "Glands" (constant emissive in the hive's yellow-green, the
sting's tip and the slits along the abdomen; the game flares them both) and "Wings" (the membranes: one plain
translucent material "Wing", constant, not baked, double-sided).

Animations (one action per clip, each in its own NLA track, 30 fps; the wings beat once every 6 frames in every clip,
in step, so Idle and Run blend without the beats cancelling out): "Idle" (loop, 2 s: hovering, the front and hind
pairs a quarter beat apart, the abdomen bobbing), "Run" (loop, 1 s: fast forward flight, the body pitched 18 degrees
nose-down, the abdomen trailing), "Attack" (the sting, once, 0.5 s: it rears back while the abdomen curls forward
under the body, the sting thrusts forward and down, the hit at frame 9 = 0.3 s, then back) and "Die" (once, 1 s: the
wings stop and fold back over the abdomen, the abdomen curls, the body rolls; the game drops it).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "darter"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Darter"
FPS = 30
GLOW = 3.0  # emission strength of the glands (the eyes: 8); TBD (playtest)
FLIGHT = 1.3  # height of the previews only (the model's origin is the thorax center)
BEAT = 6  # frames per wing beat in every clip
WING_COLOR = (0.07, 0.08, 0.048)  # linear: dark grey with a yellow-green tint
WING_ALPHA = 0.38

# --- shape ------------------------------------------------------------------------------------------

# Thorax from the neck back to the waist (evenly spaced in y): y, center z, half-width, top, bottom.
THORAX = [
    (-0.225, 0.016, 0.026, 0.024, 0.024),
    (-0.191, 0.016, 0.05, 0.046, 0.044),
    (-0.157, 0.014, 0.068, 0.064, 0.056),
    (-0.123, 0.012, 0.08, 0.077, 0.066),
    (-0.089, 0.01, 0.088, 0.086, 0.074),
    (-0.055, 0.008, 0.092, 0.09, 0.078),
    (-0.021, 0.006, 0.092, 0.089, 0.078),
    (0.013, 0.005, 0.087, 0.083, 0.073),
    (0.047, 0.004, 0.075, 0.07, 0.062),
    (0.081, 0.002, 0.054, 0.05, 0.045),
    (0.115, 0.0, 0.024, 0.022, 0.02),
]
THORAX_SHAPE = K.Profile(THORAX)
# Abdomen from the thin waist (inside the thorax's rear) to its end, drooping slightly: y, z, half-width, top, bottom.
ABDOMEN = [
    (0.1, 0.0, 0.018, 0.017, 0.016),
    (0.135, -0.002, 0.024, 0.023, 0.021),
    (0.17, -0.006, 0.042, 0.04, 0.037),
    (0.205, -0.012, 0.054, 0.052, 0.048),
    (0.24, -0.019, 0.058, 0.056, 0.052),
    (0.275, -0.027, 0.058, 0.056, 0.052),
    (0.31, -0.036, 0.055, 0.053, 0.049),
    (0.345, -0.046, 0.051, 0.049, 0.045),
    (0.38, -0.057, 0.046, 0.044, 0.04),
    (0.415, -0.068, 0.04, 0.038, 0.035),
    (0.45, -0.08, 0.033, 0.031, 0.029),
    (0.485, -0.091, 0.025, 0.024, 0.022),
    (0.52, -0.1, 0.014, 0.013, 0.012),
]
ABDOMEN_SHAPE = K.Profile(ABDOMEN)
# Head from the neck to the mouth: y, z, half-width, top, bottom (narrow; the compound eyes bulge out at the sides).
HEAD = [
    (-0.215, 0.02, 0.026, 0.026, 0.026),
    (-0.25, 0.024, 0.038, 0.046, 0.04),
    (-0.285, 0.02, 0.041, 0.05, 0.044),
    (-0.32, 0.01, 0.036, 0.042, 0.04),
    (-0.355, -0.005, 0.026, 0.03, 0.03),
    (-0.385, -0.018, 0.013, 0.014, 0.014),
]
HEAD_SHAPE = K.Profile(HEAD)


def abd_center(y: float) -> Vector:
    t = (ABDOMEN[0][0] - y) / (ABDOMEN[0][0] - ABDOMEN[-1][0])
    return ABDOMEN_SHAPE.at(t)[0]


# Abdominal segments (y of the joints between the plates); the bones bend at 0.25 and 0.38.
SEGMENTS = [0.15, 0.2, 0.25, 0.315, 0.38, 0.44, 0.5]
SLITS = [0.25, 0.315, 0.38, 0.44]  # glowing slits across the back in these joints
SEG_GAP = 0.012
STING_BASE = Vector((0, 0.495, -0.092))
STING_TIP = Vector((0, 0.625, -0.142))

# Wings (left side): root on the thorax's upper flank, span length, widest chord, how far the tip sweeps back.
WINGS = {
    "Front": (THORAX_SHAPE.surface(-0.085, 46, 0.004), 0.79, 0.18, 0.035),
    "Hind": (THORAX_SHAPE.surface(0.02, 46, 0.004), 0.74, 0.205, 0.11),
}
# Tucked legs (left side), all rigid on Chest: hip, knee, ankle, claw tip. The front pair folds forward like a
# basket, the others fold back under the waist.
LEGS = {
    "Front": [
        Vector((0.035, -0.175, -0.035)),
        Vector((0.078, -0.235, -0.085)),
        Vector((0.058, -0.17, -0.132)),
        Vector((0.04, -0.125, -0.14)),
    ],
    "Mid": [
        Vector((0.05, -0.095, -0.055)),
        Vector((0.1, -0.085, -0.11)),
        Vector((0.07, 0.0, -0.142)),
        Vector((0.05, 0.05, -0.138)),
    ],
    "Hind": [
        Vector((0.055, -0.01, -0.055)),
        Vector((0.102, 0.03, -0.1)),
        Vector((0.068, 0.118, -0.128)),
        Vector((0.048, 0.168, -0.12)),
    ],
}

# --- skeleton -------------------------------------------------------------------------------------

O = Vector((0, 0, 0))
WAIST = Vector((0, -0.1, 0.008))
NECK = Vector((0, -0.2, 0.015))
SKULL = Vector((0, -0.245, 0.018))
SNOUT = Vector((0, -0.375, -0.005))
JAW_PIVOT = Vector((0, -0.35, -0.022))
MANDIBLE = [Vector((0.022, -0.355, -0.024)), Vector((0.01, -0.42, -0.04))]
TAIL = [abd_center(0.11), abd_center(0.25), abd_center(0.38), STING_BASE]

BONES = [  # name, head, tail, parent
    ("Root", O, (0, -0.1, 0), None),
    ("Body", O, (0, -0.06, 0), "Root"),
    ("Hips", O, TAIL[0], "Body"),
    ("Spine", O, WAIST, "Body"),
    ("Chest", WAIST, NECK, "Spine"),
    ("Neck", NECK, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -0.395, -0.035)), "Head"),
    ("Tail1", TAIL[0], TAIL[1], "Hips"),
    ("Tail2", TAIL[1], TAIL[2], "Tail1"),
    ("Tail3", TAIL[2], TAIL[3], "Tail2"),
    ("Sting", STING_BASE, STING_TIP, "Tail3"),
]
for _side, _s in K.SIDES:
    BONES.append((f"{_side}Mandible", K.mirror(MANDIBLE[0], _s), K.mirror(MANDIBLE[1], _s), "Jaw"))
for _wing, (_root, _len, _c, _sw) in WINGS.items():
    for _side, _s in K.SIDES:
        _r = K.mirror(_root, _s)
        BONES.append((f"Wing{_wing}{_side}", _r, _r + Vector((_s * (_len + 0.02), 0, 0)), "Chest"))
RIG = K.Rig(BONES)
THORAX_BONES = ["Hips", "Spine", "Chest", "Neck"]
ABDOMEN_BONES = ["Hips", "Tail1", "Tail2", "Tail3", "Sting"]


# --- mesh -------------------------------------------------------------------------------------------


def mirror_angle(a: float, s: float) -> float:
    return a if s > 0 else 180 - a


def loft_profile(sk: K.Skin, rows: list, n: int, seg: int, mi: int, wobble: float = 0.003) -> list:
    rings = []
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in rows], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, seg, wobble, i * 0.9))
    return sk.loft(rings, mi)


def build_thorax(sk: K.Skin) -> None:
    sk.auto(loft_profile(sk, THORAX, 18, 16, K.SINEW), THORAX_BONES)
    shape = THORAX_SHAPE
    # Collar (pronotum), the big shield over the front wings' base, the rear shield; the wing roots stay free.
    sk.rigid(K.shell(sk, shape, -0.218, -0.165, 8, 172, 0.003, 0.014, K.CHITIN, 6, 2, 0.006), "Chest")
    sk.rigid(K.shell(sk, shape, -0.16, -0.035, 58, 122, 0.003, 0.016, K.CHITIN, 4, 4, 0.008), "Chest")
    sk.rigid(K.shell(sk, shape, -0.03, 0.09, 60, 120, 0.003, 0.014, K.CHITIN, 4, 3, 0.008), "Hips")
    for _side, s in K.SIDES:
        # Side plates (pleura) below the wing roots, front and rear; a ventral plate under each half.
        a0, a1 = sorted((mirror_angle(-48, s), mirror_angle(34, s)))
        sk.rigid(K.shell(sk, shape, -0.16, -0.045, a0, a1, 0.003, 0.013, K.CHITIN, 4, 3, 0.006), "Chest")
        sk.rigid(K.shell(sk, shape, -0.04, 0.085, a0, a1, 0.003, 0.013, K.CHITIN, 4, 3, 0.006), "Hips")
        b0, b1 = sorted((mirror_angle(-58, s), mirror_angle(-88, s)))
        sk.rigid(K.shell(sk, shape, -0.17, 0.06, b0, b1, 0.002, 0.01, K.CHITIN, 2, 4, 0.0), "Spine")
    # A low ridge of short spines down the middle of the back.
    for y, h in ((-0.15, 0.03), (-0.1, 0.038), (-0.05, 0.036), (0.0, 0.03), (0.05, 0.024)):
        p = shape.surface(y, 90, 0.008)
        sk.rigid(sk.cone(p, p + Vector((0, 0.022, h)), 0.014, 5, K.CHITIN, 0.6), "Chest" if y < -0.04 else "Hips")
    # Neck: sinew from the collar into the head.
    sk.auto(
        K.tube_path(sk, [Vector((0, -0.19, 0.016)), NECK, SKULL], [0.03, 0.027, 0.028], 10, 4, K.SINEW),
        THORAX_BONES + ["Head"],
    )


def tergite(sk: K.Skin, y0: float, y1: float, a0: float, a1: float, thick: float, mi: int = K.CHITIN):
    return K.shell(sk, ABDOMEN_SHAPE, y0, y1, a0, a1, 0.003, thick, mi, 6, 3, 0.007)


def segment_bone(y: float) -> str:
    return "Tail1" if y < 0.25 else "Tail2" if y < 0.38 else "Tail3"


def build_abdomen(sk: K.Skin, glands: K.Skin) -> None:
    sk.auto(loft_profile(sk, ABDOMEN, 26, 14, K.SINEW), ABDOMEN_BONES)
    for y0, y1 in itertools.pairwise(SEGMENTS):
        bone = segment_bone((y0 + y1) / 2)
        # Back plate (tergite) over the top and flanks, belly plate (sternite) underneath; their rear edges lift
        # like scales.
        sk.rigid(tergite(sk, y0 + SEG_GAP, y1, 14, 166, 0.012), bone)
        sk.rigid(tergite(sk, y0 + SEG_GAP, y1, 206, 334, 0.008), bone)
    # Glowing slits across the back in the joints (wasp bands, in glow), visible from above.
    for y in SLITS:
        yc = y + SEG_GAP * 0.45
        pts = [ABDOMEN_SHAPE.surface(yc, a, 0.003) for a in (22, 45, 68, 90, 112, 135, 158)]
        radii = [0.006, 0.009, 0.011, 0.011, 0.011, 0.009, 0.006]
        glands.rigid(K.tube_path(glands, pts, radii, 6, 10, 0, 0.6), segment_bone(y))
    # The sting: a bone spike out of the abdomen's end, its tip glowing; a glowing venom bulb under its base.
    d = (STING_TIP - STING_BASE).normalized()
    sk.rigid(sk.cone(STING_BASE - d * 0.02, STING_TIP, 0.022, 8, K.BONE), "Sting")
    sk.rigid(K.tube_path(sk, [abd_center(0.47), STING_BASE + d * 0.01], [0.026, 0.02], 8, 2, K.CHITIN), "Sting")
    tip0 = STING_BASE.lerp(STING_TIP, 0.6)
    glands.rigid(glands.cone(tip0, STING_TIP + d * 0.008, 0.012, 8), "Sting")
    glands.rigid(glands.sphere(abd_center(0.47) + Vector((0, 0.005, -0.022)), 0.018, 8, 4, (1, 1.4, 0.7)), "Tail3")


def build_head(sk: K.Skin, eyes: K.Skin) -> None:
    sk.rigid(loft_profile(sk, HEAD, 8, 12, K.CHITIN, 0.002), "Head")
    # Armored crown between the eyes, a ridge down its middle and two short horns swept back.
    sk.rigid(K.shell(sk, HEAD_SHAPE, -0.22, -0.345, 55, 125, 0.003, 0.012, K.CHITIN, 4, 4, 0.004), "Head")
    for side, s in K.SIDES:
        base = HEAD_SHAPE.surface(-0.255, mirror_angle(70, s), 0.01)
        sk.rigid(sk.cone(base, base + Vector((s * 0.018, 0.06, 0.035)), 0.014, 5, K.BONE, 0.7), "Head")
        # Compound eyes: big glowing domes on the sides of the head.
        eye = HEAD_SHAPE.surface(-0.29, mirror_angle(20, s), 0.004)
        eyes.rigid(eyes.sphere(eye, 0.03, 12, 7, scale=(0.8, 1.3, 1.05), rot=rz(s * 14)), "Head")
        # Mandibles: short, hooked inward, bone colored.
        b = K.mirror(MANDIBLE[0], s)
        pts = [
            b,
            b + Vector((s * 0.012, -0.03, -0.006)),
            b + Vector((s * 0.0, -0.058, -0.014)),
            b + Vector((s * -0.018, -0.07, -0.018)),
        ]
        sk.rigid(K.tube_path(sk, pts, [0.016, 0.013, 0.009, 0.004], 6, 5, K.BONE), f"{side}Mandible")
    sk.rigid(sk.sphere((0, -0.365, -0.03), 0.016, 6, 4, scale=(1.0, 1.2, 0.7), mi=K.MOUTH), "Jaw")


def build_legs(sk: K.Skin) -> None:
    for pts in LEGS.values():
        for _side, s in K.SIDES:
            hip, knee, ankle, tip = (K.mirror(p, s) for p in pts)
            start = hip - (knee - hip).normalized() * 0.03
            sk.rigid(K.tube_path(sk, [start, knee], [0.021, 0.019], 6, 2, K.CHITIN), "Chest")
            sk.rigid(sk.sphere(knee, 0.019, 6, 3, mi=K.SINEW), "Chest")
            sk.rigid(K.tube_path(sk, [knee, ankle], [0.018, 0.015], 6, 2, K.CHITIN), "Chest")
            d = (tip - ankle).normalized()
            sk.rigid(K.tube_path(sk, [ankle, tip - d * 0.018], [0.014, 0.012], 5, 1, K.CHITIN), "Chest")
            sk.rigid(sk.cone(tip - d * 0.022, tip, 0.011, 5, K.BONE), "Chest")


def chord(u: float, cmax: float) -> float:
    """The wing's chord along its span (u 0 = root, 1 = tip): narrow at the root, widest a little past the middle
    of the span, a rounded tip."""
    body = 0.42 + 0.58 * math.sin(math.pi / 2 * min(u / 0.55, 1.0))
    return cmax * body * math.sqrt(max(1.0 - u**3, 0.0))


def wing_point(kind: str, s: float, u: float, v: float, lift: float = 0.0) -> Vector:
    """Point on a wing (u along the span, v across from the leading edge 0 to the trailing edge 1)."""
    root, length, cmax, sweep = WINGS[kind]
    c = chord(u, cmax)
    yc = root.y + sweep * max(u, 0.0) ** 1.5
    camber = 0.01 * math.sin(math.pi * v) * (1 - u)
    p = Vector((root.x + 0.012 + length * u, yc - 0.38 * c + c * v, root.z + camber + lift))
    return K.mirror(p, s)


WING_U = [0.0, 0.08, 0.17, 0.27, 0.37, 0.47, 0.57, 0.66, 0.75, 0.83, 0.9, 0.95, 0.985]


def build_wings(sk: K.Skin, wings: K.Skin) -> None:
    nv = 5
    for kind in WINGS:
        for side, s in K.SIDES:
            bone = f"Wing{kind}{side}"
            # Membrane: a cambered grid closed by a tip vertex (single surface, the material is double-sided).
            rows = [[wings.bm.verts.new(wing_point(kind, s, u, k / nv)) for k in range(nv + 1)] for u in WING_U]
            tip = wings.bm.verts.new(wing_point(kind, s, 1.0, 0.38))
            faces = []
            for a, b in itertools.pairwise(rows):
                for k in range(nv):
                    faces.append(wings.bm.faces.new((a[k], a[k + 1], b[k + 1], b[k])))
            for k in range(nv):
                faces.append(wings.bm.faces.new((rows[-1][k], rows[-1][k + 1], tip)))
            verts = [v for r in rows for v in r] + [tip]
            wings.rigid(wings._tag(verts, 0), bone)
            # Veins: strips just above the membrane (two layers of the same translucent color read darker): two
            # along the span, a frame along the trailing edge, one across at the node.
            for v0, u1 in ((0.42, 0.9), (0.72, 0.9), (None, 0.95)):
                strip = []
                for i in range(11):
                    u = 0.04 + (u1 - 0.04) * i / 10
                    dv = 0.011 / max(chord(u, WINGS[kind][2]), 0.03)
                    lo, hi = (1 - 2 * dv, 1.0) if v0 is None else (v0 - dv, v0 + dv)
                    strip.append((wing_point(kind, s, u, lo, 0.002), wing_point(kind, s, u, hi, 0.002)))
                vs = [(wings.bm.verts.new(a), wings.bm.verts.new(b)) for a, b in strip]
                for (a0, b0), (a1, b1) in itertools.pairwise(vs):
                    wings.bm.faces.new((a0, b0, b1, a1))
                wings.rigid(wings._tag([v for p in vs for v in p], 0), bone)
            node = []
            for k in range(6):
                v = 0.05 + 0.9 * k / 5
                node.append((wing_point(kind, s, 0.5 - 0.014, v, 0.002), wing_point(kind, s, 0.5 + 0.014, v, 0.002)))
            vs = [(wings.bm.verts.new(a), wings.bm.verts.new(b)) for a, b in node]
            for (a0, b0), (a1, b1) in itertools.pairwise(vs):
                wings.bm.faces.new((a0, a1, b1, b0))
            wings.rigid(wings._tag([v for p in vs for v in p], 0), bone)
            # Chitin leading edge (costa) out to the tip, a hinge knob at the root and a pale spot near the tip.
            pts = [wing_point(kind, s, u, 0.02) for u in (-0.02, 0.2, 0.45, 0.7, 0.88, 0.97)]
            sk.rigid(K.tube_path(sk, pts, [0.018, 0.016, 0.014, 0.013, 0.012, 0.011], 6, 14, K.CHITIN, 0.6), bone)
            sk.rigid(sk.sphere(K.mirror(WINGS[kind][0], s), 0.022, 8, 4, scale=(1.2, 1.0, 0.8), mi=K.CHITIN), bone)
            spot = wing_point(kind, s, 0.84, 0.12, 0.002)
            sk.rigid(sk.sphere(spot, 0.02, 8, 3, scale=(1.8, 0.9, 0.3), mi=K.BONE), bone)


def mat_wing() -> bpy.types.Material:
    """The wings' membrane: one plain Principled material (constant, exported as it is): dark grey with a yellow-green
    tint, mostly see-through, alpha blended, both sides."""
    mat, _nt, bsdf = C._new_material("Wing")
    bsdf.inputs["Base Color"].default_value = (*WING_COLOR, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.25
    bsdf.inputs["Alpha"].default_value = WING_ALPHA
    mat.use_backface_culling = False
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "BLENDED"
    if hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    return mat


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    sk = K.Skin("Creature", K.materials(), RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLOW)], RIG)
    wings = K.Skin("Wings", [mat_wing()], RIG)
    build_thorax(sk)
    build_abdomen(sk, glands)
    build_head(sk, eyes)
    build_legs(sk)
    build_wings(sk, wings)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root), wings.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


def mandibles(p: K.Pose, opened: float) -> None:
    for side, s in K.SIDES:
        p.set(f"{side}Mandible", rz(s * opened))


def wings(p: K.Pose, t: float, frames: int, amp: float = 34.0, mid: float = 8.0, fold: float = 0.0) -> None:
    """Beat the wings (one beat every BEAT frames, the hind pair a quarter beat ahead), twisting them on the down and
    up strokes; fold (0..1) sweeps them back over the abdomen."""
    phase = math.tau * t * frames / BEAT
    for kind, lead, sweep in (("Front", 0.0, 76), ("Hind", math.pi / 2, 70)):
        a = phase + lead
        beat = mid + amp * math.sin(a)
        twist = -18 * math.cos(a) * (amp / 34.0)
        rest_up = 4 if kind == "Front" else -3
        for side, s in K.SIDES:
            beat_f = beat * (1 - fold) + rest_up * fold
            p.set(f"Wing{kind}{side}", rz(s * sweep * fold) @ ry(-s * beat_f) @ rx(twist * (1 - fold)))


def idle(t: float) -> K.Pose:
    """Hovering: the body bobs and drifts a little, the head turns, the abdomen bobs a beat behind."""
    a = math.tau * t
    p = K.Pose(RIG, (0.012 * math.sin(a), 0.01 * math.sin(2 * a + 0.4), 0.022 * math.sin(2 * a)))
    p.set("Body", rz(4 * math.sin(a + 0.6)) @ rx(-3 + 2.5 * math.sin(2 * a - 0.5)) @ ry(3 * math.sin(a)))
    p.set("Tail1", rx(-3 + 3 * math.sin(2 * a - 1.0)))
    p.set("Tail2", rx(-2 + 4 * math.sin(2 * a - 1.6)))
    p.set("Tail3", rx(-2 + 5 * math.sin(2 * a - 2.2)))
    p.set("Sting", rx(4 * math.sin(2 * a - 2.8)))
    p.set("Head", rz(12 * math.sin(a + 1.2)) @ rx(3 + 3 * math.sin(2 * a)))
    p.set("Jaw", rx(-2))
    mandibles(p, 5 + 10 * max(0.0, math.sin(4 * a)) ** 0.5)
    wings(p, t, CLIPS_FRAMES["Idle"])
    return p


def run(t: float) -> K.Pose:
    """Fast forward flight: the body pitched nose-down, a slight roll from side to side, the abdomen trailing and
    weaving behind, the head raised against the pitch to look ahead, bigger wing beats."""
    a = math.tau * t
    p = K.Pose(RIG, (0, 0, 0.012 * math.sin(2 * a)))
    p.set("Body", rx(18 + 2 * math.sin(2 * a)) @ ry(5 * math.sin(a)))
    p.set("Tail1", rx(3 + 2 * math.sin(2 * a - 1.0)) @ rz(3 * math.sin(a - 0.8)))
    p.set("Tail2", rx(2 + 3 * math.sin(2 * a - 1.6)) @ rz(4 * math.sin(a - 1.4)))
    p.set("Tail3", rx(2 + 3 * math.sin(2 * a - 2.2)) @ rz(4 * math.sin(a - 2.0)))
    p.set("Head", rx(-14))
    p.set("Jaw", rx(-3))
    mandibles(p, 12)
    wings(p, t, CLIPS_FRAMES["Run"], amp=40.0, mid=6.0)
    return p


HIT = 9  # the sting's hit frame in "Attack"


def attack(t: float) -> K.Pose:
    """The sting: rears back nose-up while the abdomen curls forward under the body (to 0.4), thrusts forward and down
    with the sting (the hit at frame 9 = 0.6), then back."""
    hit = HIT / CLIPS_FRAMES["Attack"]
    rear = K.smooth(t / 0.4) * (1 - K.smooth((t - hit) / (1 - hit)))
    curl = K.smooth(t / 0.45) * (1 - K.smooth((t - 0.7) / 0.3))
    thrust = K.smooth((t - 0.4) / (hit - 0.4)) * (1 - K.smooth((t - hit - 0.05) / (0.95 - hit)))
    p = K.Pose(RIG, (0, 0.06 * rear - 0.2 * thrust, 0.04 * rear - 0.04 * thrust))
    p.set("Body", rx(-30 * rear + 10 * thrust))
    p.set("Tail1", rx(-50 * curl - 10 * thrust))
    p.set("Tail2", rx(-40 * curl - 5 * thrust))
    p.set("Tail3", rx(5 * curl - 15 * thrust))
    p.set("Sting", rx(20 * curl - 10 * thrust))
    p.set("Head", rx(16 * rear))
    p.set("Jaw", rx(-10 * rear))
    mandibles(p, 6 + 22 * rear)
    wings(p, t, CLIPS_FRAMES["Attack"], amp=36.0 + 6 * rear)
    return p


def die(t: float) -> K.Pose:
    """The wings beat on weakly and stop, then fold back over the abdomen; a spasm, the abdomen curls under, the body
    rolls onto its side and the head droops (the game drops it to the ground)."""
    stop = K.smooth(t / 0.35)
    fold = K.smooth((t - 0.15) / 0.6)
    curl = K.smooth((t - 0.1) / 0.75)
    spasm = math.sin(t * 38) * (1 - K.smooth((t - 0.05) / 0.3))
    p = K.Pose(RIG, (0, 0, -0.03 * curl))
    p.set("Body", ry(34 * curl) @ rx(12 * curl + 5 * spasm))
    p.set("Tail1", rx(-22 * curl + 8 * spasm))
    p.set("Tail2", rx(-32 * curl - 6 * spasm))
    p.set("Tail3", rx(-36 * curl))
    p.set("Sting", rx(-25 * curl))
    p.set("Head", rx(28 * curl) @ rz(10 * spasm))
    p.set("Jaw", rx(-12 * curl))
    mandibles(p, 6 + 24 * curl)
    wings(p, t, CLIPS_FRAMES["Die"], amp=34.0 * (1 - stop), mid=8.0 * (1 - stop), fold=fold)
    return p


CLIPS_FRAMES = {"Idle": 60, "Run": 30, "Attack": 15, "Die": 30}
CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (CLIPS_FRAMES["Idle"], idle),
    "Run": (CLIPS_FRAMES["Run"], run),
    "Attack": (CLIPS_FRAMES["Attack"], attack),
    "Die": (CLIPS_FRAMES["Die"], die),
}

# --- measures ---------------------------------------------------------------------------------------


def mesh_points(name: str) -> list:
    obj = bpy.data.objects[name]
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [ev.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def posed(arm: bpy.types.Object, bone: str, point: Vector) -> Vector:
    """A rest-pose point carried by `bone` in the current pose (world space)."""
    pb = arm.pose.bones[bone]
    return arm.matrix_world @ (pb.matrix @ arm.data.bones[bone].matrix_local.inverted() @ point)


def fmt(v: Vector) -> tuple:
    return tuple(round(x, 3) for x in v)


def measures(arm: bpy.types.Object) -> None:
    K.rest_pose(arm)
    body = mesh_points("Creature")
    allp = body + mesh_points("Glands") + mesh_points("Eyes") + mesh_points("Wings")
    lo = Vector([min(p[i] for p in allp) for i in range(3)])
    hi = Vector([max(p[i] for p in allp) for i in range(3)])
    print("MEASURE bounds", fmt(lo), fmt(hi), "size", fmt(hi - lo))
    trunk = [p for p in body if abs(p.x) < 0.12]
    print("MEASURE trunk y", round(min(p.y for p in trunk), 3), round(max(p.y for p in trunk), 3))
    print("MEASURE back top", fmt(max(trunk, key=lambda p: p.z)), "belly/legs low", fmt(min(trunk, key=lambda p: p.z)))
    wing = mesh_points("Wings")
    print("MEASURE wing tips", fmt(max(wing, key=lambda p: p.x)), fmt(min(wing, key=lambda p: p.x)))
    for kind in WINGS:
        tip = wing_point(kind, 1.0, 1.0, 0.38)
        print(f"MEASURE wing tip {kind}Left", fmt(tip), "bone tail", fmt(Vector(RIG.tail[f"Wing{kind}Left"])))
    print("MEASURE thorax center", fmt(Vector(RIG.head["Body"])))
    print("MEASURE sting tip rest", fmt(STING_TIP + (STING_TIP - STING_BASE).normalized() * 0.008))
    frames = CLIPS_FRAMES["Attack"]
    for f in range(frames + 1):
        K.apply(arm, attack(f / frames))
        bpy.context.view_layer.update()
        tip = posed(arm, "Sting", STING_TIP)
        print(f"MEASURE attack frame {f} sting tip", fmt(tip), "(hit)" if f == HIT else "")
    for f in (0, 6, 12, 18, 30):
        K.apply(arm, die(f / 30))
        bpy.context.view_layer.update()
        tips = [fmt(posed(arm, f"Wing{k}{sd}", Vector(RIG.tail[f"Wing{k}{sd}"]))) for k in WINGS for sd, _s in K.SIDES]
        print(f"MEASURE die frame {f} wing tips (FL, FR, HL, HR)", tips)
    for name, (frames, fn) in CLIPS.items():
        zs = []
        for f in range(frames + 1):
            K.apply(arm, fn(f / frames))
            bpy.context.view_layer.update()
            pts = mesh_points("Creature")
            zs.append((min(p.z for p in pts), max(p.z for p in pts)))
        print(f"MEASURE {name} min z {min(z[0] for z in zs):.3f} max z {max(z[1] for z in zs):.3f}")
    K.rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------


def add_swarmer(x: float) -> list:
    """The swarmer's rest-pose mesh on the ground beside the darter for a scale check (wip only)."""
    src = ROOT / "tmp" / "assets" / "swarmer" / "swarmer_procedural.blend"
    if not src.exists():
        return []
    with bpy.data.libraries.load(str(src)) as (data_from, data_to):
        data_to.meshes = [m for m in ("Creature", "Eyes") if m in data_from.meshes]
    objs = []
    for me in data_to.meshes:
        obj = bpy.data.objects.new("Scale" + me.name, me)
        C.link(obj, None, "Preview")
        obj.location = (x, 0.6, 0)
        objs.append(obj)
    return objs


def shot(arm: bpy.types.Object, shots: list, name: str, pose: K.Pose | None, **kw) -> None:
    if pose is None:
        K.rest_pose(arm)
    else:
        K.apply(arm, pose)
    bpy.context.view_layer.update()
    path = OUT / "wip" / f"{TAG if MODE == 'wip' else 'final'}_{name}.png"
    if "location" in kw:
        C.render_from(path, Vector(kw["location"]), kw["target"], 50, 32, 512)
    else:
        C.render(path, view=kw.get("view", "iso"), samples=32, size=512, target=kw["target"], zoom=kw["zoom"])
    shots.append(path)


def preview(root: bpy.types.Object, arm: bpy.types.Object) -> list:
    """Renders with the darter lifted to FLIGHT (its shadow on the ground); the root goes back to the origin after."""
    C.preview_scene(crystals=False, figure_location=(1.0, 1.0, 0))
    root.location = (0, 0, FLIGHT)
    bpy.context.view_layer.update()
    shots = []
    tgt = (0, 0.08, FLIGHT)
    up = FLIGHT
    shot(arm, shots, "rest_iso", None, target=tgt, zoom=0.22)
    shot(arm, shots, "rest_hero", None, view="hero", target=tgt, zoom=0.26)
    shot(arm, shots, "rest_back", None, view="back", target=tgt, zoom=0.26)
    shot(arm, shots, "top", None, location=(0, 0.08, up + 3.2), target=tgt)
    shot(arm, shots, "side", None, location=(2.0, 0.1, up + 0.15), target=(0, 0.1, up - 0.02))
    shot(arm, shots, "head", None, location=(0.45, -0.95, up + 0.25), target=(0, -0.28, up))
    shot(arm, shots, "under", None, location=(0.9, -0.6, up - 0.9), target=(0, 0.0, up - 0.05))
    shot(arm, shots, "iso_far", None, target=tgt, zoom=1.4)
    shot(arm, shots, "idle_up", idle(1.5 / 60), target=tgt, zoom=0.22)
    shot(arm, shots, "idle_down", idle(4.5 / 60), target=tgt, zoom=0.22)
    shot(arm, shots, "run", run(0.2), view="hero", target=tgt, zoom=0.26)
    shot(arm, shots, "run_iso", run(0.05), target=tgt, zoom=0.22)
    shot(arm, shots, "attack_rear", attack(0.4), location=(2.0, -0.2, up + 0.1), target=(0, -0.05, up - 0.05))
    shot(arm, shots, "attack_hit", attack(HIT / 15), location=(2.0, -0.2, up + 0.1), target=(0, -0.05, up - 0.05))
    shot(arm, shots, "attack_hit_hero", attack(HIT / 15), view="hero", target=tgt, zoom=0.26)
    shot(arm, shots, "die_mid", die(0.4), view="hero", target=tgt, zoom=0.26)
    shot(arm, shots, "die", die(1.0), view="hero", target=tgt, zoom=0.26)
    shot(arm, shots, "die_top", die(1.0), location=(0, 0.2, up + 3.0), target=(0, 0.2, up))
    K.rest_pose(arm)
    if MODE == "wip":
        scale = add_swarmer(-1.4)
        if scale:
            shot(arm, shots, "scale", None, target=(-0.6, 0.3, 0.7), zoom=0.36)
            for obj in scale:
                bpy.data.objects.remove(obj)
    C.contact_sheet(shots, OUT / "wip" / f"{TAG if MODE == 'wip' else 'final'}_sheet.png", cols=5, tile=384)
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    measures(arm)
    if MODE != "stats":
        preview(root, arm)
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "darter_procedural.blend")
        C.export_glb(OUT / "darter_draft.glb")


main()
