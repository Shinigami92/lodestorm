"""Ravager: the hive's apex (rare, at most one per mission), a walking fortress. A huge, low, heavy trunk under
overlapping bands of thick chitin armor, a skirt of plates over the roots of six massive, short, pillar-like legs
(elephant/crab columns on broad padded feet with blunt nails), a broad, low-slung armored head with huge crushing
mandibles, and a crest of backward-curving bone horns: a crown on the back of the skull and two more pairs rising out
of the shoulder plates (its silhouette from above). In a gap of the dorsal armor, mid-back, sits a cluster of glowing,
swollen brood pods in sleeves of sinew, where swarmers ride and climb out; deep glowing seams show between some of the
plates. A short, thick, armored tail with a few blunt bone spikes. Rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/ravager/source/ravager_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/ravager/source/ravager_build.py stats      # measures and pose bounds only
    tools/blender.sh assets/aliens/ravager/source/ravager_build.py pose Attack 0.71   # one frame from four sides
    tools/blender.sh assets/aliens/ravager/source/ravager_build.py final      # renders + ravager_procedural.blend

Everything it writes goes to tmp/assets/ravager/; ravager_bake.py turns ravager_procedural.blend into the game asset.

Layout (Blender Z-up meters; the ravager faces -Y, its left is +X). Feet on the ground at the origin, the origin under
the middle of the body; the back about 2.5 m high, the mandibles' tips to the tail's end about 5.5 m, about 2.6 m
wide over the feet.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rump) with the hind legs
and the tail (Tail1, Tail2, Tail3), Spine with the mid legs and Pods (the brood pods: clips scale it to pulse),
Chest (the shoulders and their horns) with the front legs, Neck, Head with Crest (the crown of horns) and Jaw (the
lower jaw) with LeftMandible and RightMandible. Six legs (<Front|Mid|Hind><Side>UpperLeg, LowerLeg, Foot): a short,
massive thigh out of the flank to a knee out at the side (every knee clearly out of the hip-ankle line), the pillar
straight down to the ankle, the Foot is the padded foot. The game moves the legs by IK (two bones reaching the
ankle = the Foot bone's head, the Foot keeps its angle), so Idle and Run leave them at rest; Attack keys all six
(the mid and hind feet stay where they stand, solved by the same two-bone IK, the front feet rise and slam), Die
folds them.
Meshes: "Creature" (one skinned object: the trunk, neck, tail and limbs weighted to the nearest bones; plates, horns,
claws, mandibles and the pods' sleeves rigid or nearly), "Eyes" (constant emissive) and "Glands" (constant emissive:
the brood pods, skinned to Pods, and the seams between the dorsal plates, skinned to Spine and Hips).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: a slow heavy breath, the head
swinging, the pods pulsing), "Run" (loop: a heavy lumbering stride of the trunk, the head low, the tail swaying; the
legs come from the game), "Attack" (once, 1.4 s, the slam: the game starts it as the telegraph, so it moves the legs
itself: the front rears up from the start with both front feet lifted high, they slam down at IMPACT_FRAME = 30
(1.0 s), then it settles; the mid and hind feet stay planted) and "Die" (once, 1.5 s: it sags down, the legs buckle
outwards, the head hits the ground). The clips key every bone's rotation, the Body's location and the Pods' scale
(own bake, the kit's keys no scale).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "ravager"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Matrix, Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Ravager"
FPS = 30
GLAND_GLOW = 3.0  # the brood pods and the seams (the eyes: 8)
I3 = Matrix.Identity(3)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 1.5))
PELVIS = Vector((0, 1.35, 1.45))
SHOULDER = Vector((0, -0.9, 1.5))
WITHERS = Vector((0, -1.5, 1.4))
NECK_BASE = Vector((0, -1.45, 1.32))
SKULL = Vector((0, -1.85, 1.22))
SNOUT = Vector((0, -2.5, 1.0))
JAW_PIVOT = Vector((0, -1.98, 0.98))
CREST = Vector((0, -1.86, 1.28))  # the crown's center, on the back of the skull
PODS = Vector((0, 0.05, 2.0))  # the Pods bone's head (it points up)
TAIL = [PELVIS, Vector((0, 1.75, 1.33)), Vector((0, 2.07, 1.16)), Vector((0, 2.38, 0.97))]
MANDIBLE = Vector((0.38, -2.1, 0.97))  # the left mandible's hinge
# Leg joints per side (x for the left side): hip, knee, ankle (the Foot bone's head), the Foot's tail (the sole).
LEGS = (
    (
        "Front",
        [
            Vector((0.62, -1.05, 1.12)),
            Vector((0.95, -1.12, 1.06)),
            Vector((0.98, -1.24, 0.32)),
            Vector((0.98, -1.4, 0.03)),
        ],
        "Chest",
    ),
    (
        "Mid",
        [Vector((0.7, -0.02, 1.1)), Vector((1.0, -0.02, 1.05)), Vector((1.0, -0.04, 0.32)), Vector((1.0, -0.2, 0.03))],
        "Spine",
    ),
    (
        "Hind",
        [
            Vector((0.64, 0.98, 1.12)),
            Vector((0.96, 1.05, 1.06)),
            Vector((0.98, 1.14, 0.32)),
            Vector((0.98, 0.98, 0.03)),
        ],
        "Hips",
    ),
)
LEG = {name: pts for name, pts, _parent in LEGS}

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.3, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.25, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, SHOULDER, "Body"),
    ("Chest", SHOULDER, WITHERS, "Spine"),
    ("Neck", NECK_BASE, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -2.5, 0.82)), "Head"),
    ("Crest", CREST, CREST + Vector((0, 0.15, 0.45)), "Head"),
    ("Pods", PODS, PODS + Vector((0, 0, 0.6)), "Spine"),
    ("Tail1", TAIL[0], TAIL[1], "Hips"),
    ("Tail2", TAIL[1], TAIL[2], "Tail1"),
    ("Tail3", TAIL[2], TAIL[3], "Tail2"),
]
for _side, _s in K.SIDES:
    BONES.append((f"{_side}Mandible", K.mirror(MANDIBLE, _s), K.mirror(Vector((0.34, -2.6, 0.9)), _s), "Jaw"))
    for _leg, _pts, _parent in LEGS:
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), _parent),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest"]

# --- shapes -----------------------------------------------------------------------------------------

# Trunk profile from the rump forward (rows evenly spaced in y): y, center z, half-width, top, bottom. The back
# highest mid-body over the pods, the shoulders lower toward the neck.
TRUNK = [
    (1.62, 1.4, 0.14, 0.12, 0.12),
    (1.29, 1.45, 0.62, 0.56, 0.5),
    (0.96, 1.5, 0.82, 0.74, 0.7),
    (0.63, 1.53, 0.9, 0.8, 0.77),
    (0.3, 1.55, 0.93, 0.82, 0.79),
    (-0.03, 1.55, 0.93, 0.82, 0.79),
    (-0.36, 1.54, 0.92, 0.81, 0.78),
    (-0.69, 1.52, 0.89, 0.79, 0.76),
    (-1.02, 1.47, 0.83, 0.71, 0.7),
    (-1.35, 1.4, 0.68, 0.57, 0.56),
    (-1.68, 1.3, 0.3, 0.26, 0.26),
]
TRUNK_SHAPE = K.Profile(TRUNK)
# The head from the back of the skull to the snout (rows evenly spaced in y): y, center z, half-width, top, bottom.
# Broad, low and blunt.
HEAD = [
    (-1.72, 1.24, 0.36, 0.3, 0.3),
    (-1.896, 1.2, 0.5, 0.29, 0.33),
    (-2.072, 1.14, 0.53, 0.26, 0.3),
    (-2.248, 1.08, 0.47, 0.22, 0.25),
    (-2.424, 1.02, 0.35, 0.16, 0.18),
    (-2.6, 0.97, 0.14, 0.08, 0.08),
]
HEAD_SHAPE = K.Profile(HEAD)
# The armor: rows of scutes from the front of the shoulders to the rump, their lengths from BANDS (the upper row
# staggered by half a scute); a glowing seam shows in the gap between the lateral and the upper row.
BANDS = [-1.74, -1.44, -1.12, -0.8, -0.46, -0.12, 0.22, 0.56, 0.9, 1.22, 1.56]
LATERAL, UPPER, DORSAL = (-30, 29), (36, 74), (68, 112)  # the rows' angles (0 = the left side, 90 = the top)
POD_Y = (-0.52, 0.66)  # the gap for the pods along the back: no dorsal scutes, the upper ones end at POD_GAP
POD_GAP = 60
# The crown of horns on the back of the skull: an arc in a plane leaning back, horns growing out of it.
CROWN_X = Vector((1, 0, 0))
CROWN_U = Vector((0, 0.35, 0.94)).normalized()
CROWN_RX, CROWN_RU = 0.5, 0.42
# Horns (left side; x mirrored): base, then the bend points as offsets from it, and the radii along it.
HORNS_CROWN = [  # (angle on the crown's arc, offsets, radii)
    (72, [(0, 0, 0), (0.05, 0.06, 0.32), (0.13, 0.3, 0.6), (0.2, 0.62, 0.72)], [0.13, 0.11, 0.08, 0.05]),
    (40, [(0, 0, 0), (0.13, 0.04, 0.24), (0.3, 0.28, 0.42), (0.42, 0.62, 0.48)], [0.11, 0.095, 0.07, 0.045]),
    (8, [(0, 0, 0), (0.17, 0.03, 0.1), (0.35, 0.26, 0.17), (0.47, 0.56, 0.15)], [0.1, 0.085, 0.065, 0.04]),
]
HORNS_SHOULDER = [  # (y, angle on the trunk, offsets, radii)
    (-1.22, 68, [(0, 0, 0), (0.03, 0.06, 0.26), (0.08, 0.25, 0.44), (0.13, 0.5, 0.5)], [0.12, 0.1, 0.075, 0.045]),
    (-0.9, 45, [(0, 0, 0), (0.08, 0.06, 0.22), (0.18, 0.26, 0.36), (0.27, 0.52, 0.38)], [0.11, 0.09, 0.07, 0.04]),
]
# The brood pods: x, y, radius, (scale x, y, z); they sit in the gap of the dorsal armor, half sunk into the back.
PODS_LIST = [
    (0.0, 0.06, 0.27, (1.0, 1.1, 0.85)),
    (0.25, -0.2, 0.21, (1.0, 1.05, 0.9)),
    (-0.25, -0.17, 0.2, (1.0, 1.1, 0.9)),
    (0.24, 0.34, 0.22, (1.0, 1.1, 0.9)),
    (-0.23, 0.32, 0.23, (1.0, 1.05, 0.88)),
    (0.0, -0.36, 0.19, (1.0, 1.0, 0.9)),
    (0.0, 0.5, 0.2, (1.05, 1.0, 0.88)),
    (0.33, 0.07, 0.15, (0.9, 1.1, 0.95)),
    (-0.33, 0.05, 0.16, (0.9, 1.1, 0.95)),
]


# --- helpers ----------------------------------------------------------------------------------------


def trunk_t(y: float) -> float:
    return (TRUNK[0][0] - y) / (TRUNK[0][0] - TRUNK[-1][0])


def top_z(x: float, y: float) -> float:
    """Height of the trunk's upper surface at x, y."""
    c, w, top, _bot = TRUNK_SHAPE.at(trunk_t(y))
    ca = min(abs(x) / w, 1.0) ** (1 / 0.85)
    sa = math.sqrt(max(1.0 - ca * ca, 0.0))
    return c.z + top * sa**0.9


def crown_point(phi: float, r: float = 1.0) -> Vector:
    a = math.radians(phi)
    return CREST + CROWN_X * (math.cos(a) * CROWN_RX * r) + CROWN_U * (math.sin(a) * CROWN_RU * r)


def rounded_ring(c: Vector, wx: float, wy: float, seg: int, power: float = 0.75) -> list:
    """A horizontal rounded ring (superellipse) around c."""
    pts = []
    for k in range(seg):
        a = math.tau * k / seg
        ca, sa = math.cos(a), math.sin(a)
        pts.append(c + Vector((math.copysign(abs(ca) ** power, ca) * wx, math.copysign(abs(sa) ** power, sa) * wy, 0)))
    return pts


def wrap_plate(
    sk: K.Skin,
    a: Vector,
    b: Vector,
    r0: float,
    r1: float,
    a0: float,
    a1: float,
    thick: float,
    facing: Vector,
    lift: float = 0.0,
    nu: int = 8,
    nv: int = 2,
    mi: int = K.CHITIN,
) -> list:
    """Curved plate wrapped around a limb segment a..b (radius r0 at a, r1 at b) on the side `facing`, angles a0..a1
    around it; its edge at b flares out by `lift` (plates overlapping downward). The kit's limb_plate, finer and
    tapered."""
    d = (b - a).normalized()
    side = facing - d * facing.dot(d)
    side.normalize()
    other = d.cross(side)
    top_rows, bot_rows = [], []
    for i in range(nv + 1):
        v = i / nv
        c = a.lerp(b, v)
        r = r0 + (r1 - r0) * v
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            ang = math.radians(a0 + (a1 - a0) * u)
            n = side * math.cos(ang) + other * math.sin(ang)
            edge = math.sin(math.pi * u) ** 0.5
            o = r + lift * v * edge
            row_t.append(sk.bm.verts.new(c + n * (o + thick * (0.45 + 0.55 * edge))))
            row_b.append(sk.bm.verts.new(c + n * o))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return K.close_grid(sk, top_rows, bot_rows, mi)


def horn(sk: K.Skin, base: Vector, offsets: list, radii: list, s: float, bone: str) -> None:
    """A curved bone horn from base through the offsets (left side; x mirrored by s), a sharp tip at its end."""
    pts = [base + K.mirror(Vector(o), s) for o in offsets]
    root = base + (base - pts[1]).normalized() * 0.06
    sk.rigid(K.tube_path(sk, [root] + pts, [radii[0] * 1.1] + radii, 8, 10, K.BONE), bone)
    d = (pts[-1] - pts[-2]).normalized()
    sk.rigid(sk.cone(pts[-1] - d * 0.03, pts[-1] + d * 0.16, radii[-1] * 1.05, 6, K.BONE), bone)


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: K.Skin, glands: K.Skin) -> None:
    n = 22
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 22, 0.012, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # The armor: three rows of heavy scutes a side, overlapping backward (their rear edges lift): big ones in the
    # lateral row over the flanks, the upper row staggered by half a scute with a blunt keel spike on each, and the
    # dorsal row over the spine, which leaves the gap for the pods.
    rows = (
        ("lateral", LATERAL, BANDS[::2]),
        ("upper", UPPER, [BANDS[0]] + [(y + b) / 2 for y, b in itertools.pairwise(BANDS)][1:] + [BANDS[-1]]),
        ("dorsal", DORSAL, BANDS),
    )
    for row, (a0, a1), ys in rows:
        for i, (y0, y1) in enumerate(itertools.pairwise(ys)):
            yc = (y0 + y1) / 2
            in_gap = POD_Y[0] < yc < POD_Y[1]
            if row == "dorsal" and in_gap:
                continue
            thick = 0.085 if row == "lateral" or yc < -0.9 else 0.07
            for _side, s in K.SIDES if row != "dorsal" else (("", 1.0),):
                lo, hi = (a0, POD_GAP) if row == "upper" and in_gap else (a0, a1)
                if s < 0:
                    lo, hi = 180 - hi, 180 - lo
                out = 0.03 if row == "dorsal" else 0.012
                verts = K.shell(sk, TRUNK_SHAPE, y0 - 0.04, y1 + 0.05, lo, hi, out, thick, K.CHITIN, 5, 2, 0.05)
                sk.auto(verts, TRUNK_BONES, 8.0)
                mid = (lo + hi) / 2
                if row == "upper" and 0 < i < len(ys) - 2:
                    base = TRUNK_SHAPE.surface(yc, mid, 0.07)
                    tip = base + Vector((s * 0.1, 0.17, 0.15))
                    sk.auto(sk.cone(base, tip, 0.085, 6, K.CHITIN), TRUNK_BONES, 8.0)
                elif row == "dorsal" and 0 < i < len(ys) - 1:
                    p = TRUNK_SHAPE.surface(yc + 0.03, 90, 0.09)
                    sk.auto(sk.sphere(p, 0.08, 8, 4, scale=(0.8, 1.6, 0.6), mi=K.CHITIN), TRUNK_BONES, 8.0)
    # The seams: glowing flesh deep in the gap between the lateral and the upper row, broken where the scutes meet.
    for _side, s in K.SIDES:
        a = (LATERAL[1] + UPPER[0]) / 2
        for y0, y1 in ((-1.25, -0.9), (-0.78, -0.3), (-0.18, 0.3), (0.42, 0.9), (1.0, 1.25)):
            pts = [TRUNK_SHAPE.surface(y0 + (y1 - y0) * t, a if s > 0 else 180 - a, -0.012) for t in (0, 0.5, 1)]
            bones = ["Spine", "Chest"] if y1 < -0.5 else ["Hips", "Spine"]
            glands.auto(K.tube_path(glands, pts, [0.02, 0.04, 0.02], 6, 6, 0, 1.0, 0.008), bones)
    # Skirt: a heavy plate over each leg's root, below the bands, and plates over the belly.
    for _leg, pts, _parent in LEGS:
        y = pts[0].y
        for _side, s in K.SIDES:
            a0, a1 = (-62, -14) if s > 0 else (194, 242)
            verts = K.shell(sk, TRUNK_SHAPE, y - 0.42, y + 0.4, a0, a1, 0.06, 0.07, K.CHITIN, 4, 2, 0.06)
            sk.auto(verts, TRUNK_BONES, 8.0)
    for y0, y1 in ((-1.3, -0.7), (-0.75, -0.15), (-0.2, 0.4), (0.35, 0.95), (0.9, 1.4)):
        sk.auto(K.shell(sk, TRUNK_SHAPE, y0, y1, 238, 302, 0.01, 0.045, K.CHITIN, 4, 2, 0.02), TRUNK_BONES, 8.0)
    # Raw flesh in the gap of the armor, the bed of the pods.
    bed = K.shell(sk, TRUNK_SHAPE, POD_Y[0], POD_Y[1], POD_GAP - 8, 188 - POD_GAP, 0.0, 0.03, K.MOUTH, 6, 4, 0.0)
    sk.auto(bed, ["Spine", "Hips"])


def build_shoulder_horns(sk: K.Skin) -> None:
    for y, a, offsets, radii in HORNS_SHOULDER:
        for _side, s in K.SIDES:
            base = TRUNK_SHAPE.surface(y, a if s > 0 else 180 - a, 0.04)
            horn(sk, base, offsets, radii, s, "Chest")
            sk.rigid(sk.sphere(base, radii[0] * 1.5, 10, 5, scale=(1.0, 1.2, 0.5), mi=K.CHITIN), "Chest")


def build_pods(sk: K.Skin, glands: K.Skin) -> Vector:
    """The brood pods: swollen glowing ellipsoids (Glands) bulging out of sleeves of sinew, a dark crease over each
    (where it splits open), all on Pods. Returns their center."""
    center = Vector()
    for k, (x, y, r, scale) in enumerate(PODS_LIST):
        c = pod_center(x, y, r)
        center += c
        sx, sy, sz = (r * f for f in scale)
        glands.rigid(glands.sphere(c, 1.0, 14, 8, scale=(sx, sy, sz)), "Pods")

        def at(theta: float, phi: float, grow: float, c=c, sx=sx, sy=sy, sz=sz) -> Vector:
            t, p = math.radians(theta), math.radians(phi)
            return c + Vector(
                (math.sin(t) * math.cos(p) * sx * grow, math.sin(t) * math.sin(p) * sy * grow, math.cos(t) * sz * grow)
            )

        # The sleeve: from deep in the back up to just over the pod's middle, its rim tucked against it.
        rings = [
            [at(theta, 360 * j / 12, g) for j in range(12)] for theta, g in ((165, 1.06), (130, 1.09), (112, 1.08))
        ]
        rings.append([at(104, 360 * j / 12, 1.04) for j in range(12)])
        rings.append([at(100, 360 * j / 12, 0.96) for j in range(12)])
        sk.rigid(sk.loft(rings, K.SINEW, caps=False), "Pods")
        # A dark crease over its top, where it splits open.
        phi = 70 * k
        pts = [at(theta, phi, 1.0) + (at(theta, phi, 1.0) - c).normalized() * 0.008 for theta in range(-70, 71, 35)]
        sk.rigid(K.tube_path(sk, pts, [0.022, 0.032, 0.022], 6, 8, K.SINEW, 0.7), "Pods")
    return center / len(PODS_LIST)


def build_neck_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Neck: short and very thick, out of the front of the shoulders into the back of the skull, a collar of plates.
    pts = [Vector((0, -1.3, 1.38)), Vector((0, -1.52, 1.3)), Vector((0, -1.74, 1.25))]
    sk.auto(K.tube_path(sk, pts, [0.48, 0.42, 0.36], 16, 5, K.SINEW, 1.0, 0.01), ["Chest", "Neck", "Head"])
    for t0, t1 in ((0.0, 0.55), (0.4, 0.95)):
        a, b = K.path_point(pts, t0), K.path_point(pts, t1)
        sk.rigid(wrap_plate(sk, a, b, 0.44, 0.38, -80, 80, 0.06, Vector((0, 0, 1)), 0.03, 8, 2), "Neck")
    # Skull (chitin; the underside in front is the roof of the mouth).
    rings = []
    n = 12
    for i in range(n + 1):
        c, w, top, bot = HEAD_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 20, 0.008, 3 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        if f.normal.z < -0.6 and -2.4 < f.calc_center_median().y < -2.05:
            f.material_index = K.MOUTH
    # Armor: a visor plate down the middle, its front edge lifting, heavy brows over the eyes on each side, cheek
    # plates under them, and a ridge of bosses down the snout.
    sk.rigid(K.shell(sk, HEAD_SHAPE, -1.76, -2.56, 58, 122, 0.035, 0.07, K.CHITIN, 5, 3, 0.05), "Head")
    for a0, a1, b0, b1 in ((22, 64, -4, 24), (116, 158, 156, 184)):
        sk.rigid(K.shell(sk, HEAD_SHAPE, -1.8, -2.42, a0, a1, 0.012, 0.075, K.CHITIN, 4, 3, 0.06), "Head")
        sk.rigid(K.shell(sk, HEAD_SHAPE, -1.86, -2.36, b0 - 36, b1 - 30, 0.01, 0.06, K.CHITIN, 4, 2, 0.04), "Head")
    for y in (-2.0, -2.18, -2.36):
        p = HEAD_SHAPE.surface(y, 90, 0.08)
        sk.rigid(sk.sphere(p, 0.07, 8, 4, scale=(0.9, 1.3, 0.7), mi=K.CHITIN), "Head")
    # Eyes: three a side in a row low on the flank of the head, under the brow's rim.
    for _side, s in K.SIDES:
        for y, a, r in ((-2.3, 13, 0.065), (-2.15, 11, 0.058), (-2.0, 9, 0.05)):
            p = HEAD_SHAPE.surface(y, a if s > 0 else 180 - a, 0.0)
            eyes.rigid(eyes.sphere(p, r, 10, 5, scale=(1.0, 1.3, 0.9)), "Head")
            lid = HEAD_SHAPE.surface(y, (a + 11) if s > 0 else 169 - a, 0.015)
            sk.rigid(sk.sphere(lid, r * 1.2, 8, 4, scale=(1.0, 1.4, 0.55), mi=K.CHITIN), "Head")
    # Teeth: heavy pegs along the front of the upper jaw.
    for a in (205, 222, 240, 258, 282, 300, 318, 335):
        base = HEAD_SHAPE.surface(-2.4, a, -0.03)
        sk.rigid(sk.cone(base, base + Vector((0, -0.03, -0.13)), 0.04, 5, K.BONE), "Head")
    # Lower jaw: a broad scoop.
    jaw = [
        (-1.98, 0.9, 0.34, 0.06, 0.12),
        (-2.15, 0.87, 0.36, 0.06, 0.12),
        (-2.32, 0.85, 0.3, 0.05, 0.1),
        (-2.49, 0.84, 0.16, 0.04, 0.06),
    ]
    rings = []
    for i in range(7):
        y, z, w, top, bot = K.catmull([list(r) for r in jaw], i / 6)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 14, 0.004, 9 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Jaw")
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        if f.normal.z > 0.5 and f.calc_center_median().y > -2.4:
            f.material_index = K.MOUTH
    # Mandibles: huge, thick crushing hooks closing in front of the mouth, blunt crushing teeth on the inner edge.
    for side, s in K.SIDES:
        bone = f"{side}Mandible"
        pts = [
            K.mirror(p, s)
            for p in (
                Vector((0.38, -2.08, 0.98)),
                Vector((0.53, -2.32, 0.95)),
                Vector((0.48, -2.58, 0.9)),
                Vector((0.3, -2.76, 0.87)),
                Vector((0.12, -2.82, 0.85)),
            )
        ]
        sk.rigid(K.tube_path(sk, pts, [0.15, 0.14, 0.11, 0.075, 0.04], 10, 12, K.CHITIN, 0.75), bone)
        d = (pts[-1] - pts[-2]).normalized()
        sk.rigid(sk.cone(pts[-1] - d * 0.03, pts[-1] + d * 0.1, 0.04, 6, K.BONE), bone)
        for t in (0.42, 0.6, 0.76):
            base = K.path_point(pts, t)
            inward = (Vector((0, base.y, base.z)) - base).normalized()
            sk.rigid(sk.cone(base, base + inward * 0.13, 0.05, 5, K.BONE, 0.7), bone)
        sk.rigid(sk.sphere(K.mirror(MANDIBLE, s), 0.17, 10, 5, mi=K.CHITIN), "Head")


def build_crest(sk: K.Skin) -> None:
    """The crown: a thick bony ridge arching over the back of the skull, three pairs of horns out of it curving
    back over the shoulders."""
    pts = [crown_point(phi) for phi in range(-14, 195, 26)]
    sk.rigid(K.tube_path(sk, pts, [0.11, 0.14, 0.15, 0.14, 0.11], 10, 16, K.CHITIN), "Crest")
    for phi, offsets, radii in HORNS_CROWN:
        for _side, s in K.SIDES:
            horn(sk, crown_point(phi if s > 0 else 180 - phi), offsets, radii, s, "Crest")


def build_tail(sk: K.Skin) -> None:
    pts = [Vector((0, 1.2, 1.47)), Vector((0, 1.52, 1.39)), Vector((0, 1.82, 1.27)), Vector((0, 2.1, 1.12))]
    pts.append(Vector((0, 2.38, 0.95)))
    tail_bones = ["Hips", "Tail1", "Tail2", "Tail3"]
    sk.auto(K.tube_path(sk, pts, [0.5, 0.44, 0.34, 0.25, 0.15], 16, 10, K.SINEW, 0.9, 0.008), tail_bones)
    # Armor rings over its top and flanks, overlapping backward, one bone each.
    for (t0, t1), bone, r in (
        ((0.12, 0.38), "Tail1", 0.43),
        ((0.33, 0.6), "Tail2", 0.36),
        ((0.55, 0.8), "Tail2", 0.29),
        ((0.75, 0.98), "Tail3", 0.21),
    ):
        a, b = K.path_point(pts, t0), K.path_point(pts, t1)
        sk.rigid(wrap_plate(sk, a, b, r, r * 0.85, -120, 120, 0.05, Vector((0, 0, 1)), 0.03, 10, 2), bone)
    # Blunt bone spikes at its end.
    end = pts[-1]
    for d in (Vector((0, 1, 0.15)), Vector((0.6, 0.8, 0.25)), Vector((-0.6, 0.8, 0.25)), Vector((0.0, 0.6, 0.8))):
        d.normalize()
        sk.rigid(sk.cone(end + d * 0.05, end + d * 0.24, 0.07, 6, K.BONE), "Tail3")


def build_leg(sk: K.Skin, row: str, j: list, s: float, side: str, parent: str) -> None:
    up, low, foot = (f"{row}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
    out = Vector((s, 0, 0))
    # Socket and thigh: a short, massive limb out of the flank to the knee.
    sk.auto(sk.sphere(j[0] + out * 0.02, 0.3, 12, 6, scale=(1.0, 1.15, 0.95), mi=K.SINEW), [parent, up])
    mid = j[0].lerp(j[1], 0.5) + Vector((0, 0, 0.04))
    sk.auto(
        K.tube_path(sk, [j[0] - out * 0.1, mid, j[1]], [0.3, 0.29, 0.26], 14, 5, K.SINEW, 1.0, 0.01), [parent, up, low]
    )
    sk.rigid(wrap_plate(sk, j[0].lerp(j[1], 0.1), j[1], 0.29, 0.26, -75, 75, 0.06, Vector((s * 0.4, 0, 1))), up)
    # Knee: a massive chitin cap, a blunt horn out to the side.
    sk.rigid(sk.sphere(j[1] + out * 0.04 + Vector((0, 0, 0.02)), 0.25, 12, 6, mi=K.CHITIN), low)
    base = j[1] + out * 0.14 + Vector((0, 0, 0.14))
    sk.rigid(sk.cone(base, base + Vector((s * 0.07, 0.06, 0.17)), 0.075, 6, K.CHITIN), low)
    # The pillar: thick and straight down to the ankle, armored by two long greaves overlapping downward.
    sk.auto(
        K.tube_path(sk, [j[1], j[1].lerp(j[2], 0.5), j[2]], [0.24, 0.215, 0.23], 14, 6, K.SINEW, 1.0, 0.006),
        [up, low, foot],
    )
    facing = Vector((s, -0.35 if row == "Front" else 0.35 if row == "Hind" else 0.0, 0)).normalized()
    for k, (t0, t1) in enumerate(((0.0, 0.58), (0.48, 1.0))):
        r = 0.235 + 0.01 * k
        verts = wrap_plate(sk, j[1].lerp(j[2], t0), j[1].lerp(j[2], t1), r, r + 0.015, -105, 105, 0.05, facing, 0.04)
        sk.rigid(verts, low)
    build_foot(sk, j, s, low, foot)


def build_foot(sk: K.Skin, j: list, s: float, low: str, foot: str) -> None:
    """An elephant-like padded foot flat on the ground, blunt bone nails around its front."""
    w = j[2]
    fwd = (j[3] - j[2]) * Vector((1, 1, 0))
    fwd = fwd.normalized() if fwd.length > 1e-4 else Vector((0, -1, 0))
    layers = [  # z, half-width x, half-depth y, forward shift
        (w.z + 0.08, 0.2, 0.2, 0.0),
        (0.22, 0.24, 0.24, 0.02),
        (0.1, 0.27, 0.27, 0.04),
        (0.03, 0.28, 0.28, 0.05),
        (0.0, 0.26, 0.26, 0.05),
    ]
    rings = [rounded_ring(Vector((w.x, w.y, z)) + fwd * f, wx, wy, 16) for z, wx, wy, f in layers]
    verts = sk.loft(rings, K.CHITIN)
    for v in verts:
        if v.co.z > w.z:
            sk.auto([v], [low, foot])
        else:
            sk.rigid([v], foot)
    # The nails: five blunt, broad bone hooves around the front of the pad.
    for k in range(5):
        ang = math.radians(-60 + 30 * k)
        d = Vector((fwd.x * math.cos(ang) - fwd.y * math.sin(ang), fwd.x * math.sin(ang) + fwd.y * math.cos(ang), 0))
        base = Vector((w.x, w.y, 0.11)) + fwd * 0.05 + d * 0.22
        sk.rigid(sk.cone(base, base + d * 0.08 + Vector((0, 0, -0.09)), 0.065, 6, K.BONE, 0.6), foot)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk, glands)
    build_shoulder_horns(sk)
    build_pods(sk, glands)
    build_neck_head(sk, eyes)
    build_crest(sk)
    build_tail(sk)
    for row, pts, parent in LEGS:
        for side, s in K.SIDES:
            build_leg(sk, row, [K.mirror(p, s) for p in pts], s, side, parent)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


def pod_center(x: float, y: float, r: float) -> Vector:
    """A pod sits about half out of the back."""
    return Vector((x, y, top_z(x, y) - 0.06 + 0.1 * r))


def pods_center() -> Vector:
    return sum((pod_center(x, y, r) for x, y, r, _scale in PODS_LIST), Vector()) / len(PODS_LIST)


# --- posing -----------------------------------------------------------------------------------------


class Pose(K.Pose):
    """The kit's pose plus a scale per bone (the pods pulsing), as (width, height, length) in the bone's axes: for
    Pods (pointing up) x, z and y of the world."""

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
    """K.bake_clips with the Pods' scale keyed too."""
    ad = arm.animation_data_create()
    for name, (frames, fn) in clips.items():
        ad.action = None
        for f in range(frames + 1):
            apply(arm, fn(f / frames))
            for pb in arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                if pb.name == "Body":
                    pb.keyframe_insert("location", frame=f, group=pb.name)
                if pb.name == "Pods":
                    pb.keyframe_insert("scale", frame=f, group=pb.name)
        act = ad.action
        act.name = name
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        track.mute = True
        ad.action = None
    rest_pose(arm)


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


REACH: dict = {}  # leg: the largest hip-ankle distance a clip asked for, as a share of the leg's length


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
    a, b = (knee_r - hip_r).length, (ankle_r - knee_r).length
    REACH[leg] = max(REACH.get(leg, 0.0), (ankle - hip).length / (a + b))
    knee, end = two_bone(hip, ankle, a, b, pole)
    w_up = arc(wp @ (knee_r - hip_r), knee - hip) @ wp
    w_low = arc(w_up @ (ankle_r - knee_r), end - knee) @ w_up
    p.set(up, wp.transposed() @ w_up)
    p.set(low, w_up.transposed() @ w_low)
    if foot_world is not None:
        p.set(foot, w_low.transposed() @ foot_world)


def pivot(rot: Matrix, at: Vector) -> Vector:
    """The Body offset that turns the body by `rot` around the point `at` instead of around the Body bone's head."""
    return (at - BODY) - rot @ (at - BODY)


def plant(p: K.Pose, rows=("Mid", "Hind")) -> None:
    """Keeps the feet of `rows` where they stand at rest (flat on the ground)."""
    for row in rows:
        for side, s in K.SIDES:
            leg_ik(p, f"{row}{side}", K.mirror(LEG[row][2], s))


def mandibles(p: K.Pose, spread: float) -> None:
    for side, s in K.SIDES:
        p.set(f"{side}Mandible", rz(s * spread))


def tail(p: K.Pose, swing: float, phase: float, lift: float = 0.0) -> None:
    """The tail sways from side to side (swing in degrees, a wave running down it) and lifts (lift in degrees)."""
    for k, bone in enumerate(("Tail1", "Tail2", "Tail3")):
        p.set(bone, rz(swing * (0.7 + 0.25 * k) * math.sin(phase - 0.6 * k)) @ rx(lift * (0.6 - 0.15 * k)))


def idle(t: float) -> Pose:
    """A slow, heavy breath, the head swinging from side to side, the jaws working, the pods pulsing twice."""
    a = math.tau * t
    breath = math.sin(a)
    p = Pose(RIG, (0, 0, 0.025 * breath))
    p.set("Spine", rx(-1.0 * breath)).set("Chest", rx(-1.2 * breath))
    p.set("Neck", rz(10 * math.sin(a)) @ rx(2 * math.sin(2 * a + 0.6)))
    p.set("Head", rz(5 * math.sin(a - 0.7)) @ rx(-2 + 2 * math.sin(2 * a + 1.0)))
    p.set("Jaw", rx(3 + 5 * max(0.0, math.sin(2 * a + 2.0)) ** 2))
    p.set("Crest", rx(1.5 * math.sin(a + 1.0)))
    mandibles(p, 4 + 8 * max(0.0, math.sin(3 * a)) ** 2)
    tail(p, 5, a + 0.5, 2 * breath)
    pulse = 0.5 + 0.5 * math.sin(2 * a)
    p.grow("Pods", 1.0 + 0.05 * pulse, 1.0 + 0.08 * pulse, 1.0 + 0.05 * pulse)
    return p


def run(t: float) -> Pose:
    """The trunk's motion while it lumbers (legs at rest, the game steps them): two heavy bobs per stride, the trunk
    rolling onto the side that bears its weight, the head low and swinging against it, the tail swaying behind, the
    pods jiggling."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = Pose(RIG, (0.03 * math.sin(a), -0.04 * math.sin(2 * a), -0.05 + 0.04 * bob))
    p.set("Body", rx(2 * math.sin(2 * a + 0.6)) @ ry(4 * math.sin(a)) @ rz(-2.5 * math.sin(a)))
    p.set("Hips", ry(-2 * math.sin(a)) @ rz(3 * math.sin(a)))
    p.set("Spine", rx(-1.2 * math.sin(2 * a)))
    p.set("Chest", ry(-1.5 * math.sin(a)))
    p.set("Neck", rx(7 + 2 * math.sin(2 * a + 1.2)) @ rz(-5 * math.sin(a)))
    p.set("Head", rx(-3 - 2 * math.sin(2 * a + 1.4)))
    p.set("Jaw", rx(5))
    mandibles(p, 6)
    tail(p, -6, a - 0.6, 2 * math.sin(2 * a - 0.8))
    lag = 2 * a - 1.2
    p.set("Pods", rx(2 * math.sin(lag)))
    p.grow("Pods", 1.0 + 0.03 * math.sin(lag + 1.0), 1.0 - 0.05 * math.sin(lag), 1.0 + 0.03 * math.sin(lag + 1.0))
    return p


ATTACK_FRAMES = 42  # 1.4 s
IMPACT_FRAME = 30  # both front feet hit the ground (1.0 s)
PIVOT = Vector((0, 0.25, 1.12))  # it rears up around a point between the mid and hind hips
FOOT_RAISED = Vector((1.1, -1.68, 1.6))  # the left front ankle at the top of the rear-up
FOOT_IMPACT = Vector((1.0, -1.74, 0.32))  # the left front ankle at the impact: the foot flat on the ground ahead


def attack(t: float) -> Pose:
    """The slam: rears up its front with both front feet lifted high and the crest raised (to 0.42), holds, slams
    both feet down ahead of it (accelerating, the impact at IMPACT_FRAME), stays down a moment with a shudder, then
    settles back to rest (the front feet stepping back to where they stood). The mid and hind feet stay planted."""
    impact = IMPACT_FRAME / ATTACK_FRAMES
    a = K.smooth(t / 0.42)
    s = min(max((t - 0.52) / (impact - 0.52), 0.0), 1.0) ** 1.7
    r = K.smooth((t - 0.8) / 0.2)
    shudder = math.exp(-(((t - impact - 0.03) / 0.04) ** 2))
    body = rx((-18 * a + 23 * s) * (1 - r))
    p = Pose(RIG, pivot(body, PIVOT) + Vector((0, -0.12 * s, 0.06 * a * (1 - s) - 0.05 * s - 0.03 * shudder)) * (1 - r))
    p.set("Body", body)
    p.set("Spine", rx((-4 * a + 5 * s) * (1 - r)))
    p.set("Chest", rx((-10 * a + 10 * s) * (1 - r)))
    p.set("Neck", rx((-8 * a + 14 * s) * (1 - r)))
    p.set("Head", rx((-6 * a + 8 * s) * (1 - r)))
    p.set("Jaw", rx((22 * a * (1 - s) + 8 * s) * (1 - r)))
    p.set("Crest", rx((12 * a - 6 * s) * (1 - r)))
    mandibles(p, (24 * a * (1 - s) + 12 * s) * (1 - r))
    tail(p, 0, 0, (22 * a - 14 * s) * (1 - r))
    p.grow("Pods", 1.0 + 0.06 * a * (1 - r) + 0.05 * shudder, 1.0 + 0.1 * a * (1 - r) - 0.06 * shudder, 1.0)
    plant(p)
    for side, sg in K.SIDES:
        rest = K.mirror(LEG["Front"][2], sg)
        raised, hit = K.mirror(FOOT_RAISED, sg), K.mirror(FOOT_IMPACT, sg)
        target = rest.lerp(raised, a)
        target = target.lerp(hit, s) + Vector((0, -0.15, 0.25)) * math.sin(math.pi * s)
        target = target.lerp(rest, r) + Vector((0, 0, 0.16)) * math.sin(math.pi * r)
        # The feet hang from the pillars while raised and land flat.
        flat = 1 - a * (1 - s) * (1 - r)
        leg_ik(p, f"Front{side}", target, None)
        w_low = p.world(f"Front{side}LowerLeg")
        p.set(
            f"Front{side}Foot", w_low.transposed() @ w_low.to_quaternion().slerp(I3.to_quaternion(), flat).to_matrix()
        )
    return p


DIE_DROP = Vector((0.05, -0.04, -0.675))  # where the Body ends up, so the belly rests on the ground
DIE_FOOT = Vector((0.45, 0.0, 0.08))  # how far each ankle slides out (left side; x mirrored)
DIE_TILT = 24  # degrees the feet tip over outward


def die(t: float) -> Pose:
    """The legs buckle outwards (to 0.4) and the whole weight sags down onto the belly (0.85), leaning a little onto
    its left side; the head drops and hits the ground (0.85), the tail droops, the pods sag. The legs are solved like
    AlienLegs does it (the game switches it off on death)."""
    k = K.smooth(t / 0.4)
    f = K.smooth((t - 0.12) / 0.73)
    h = K.smooth((t - 0.4) / 0.45)
    p = Pose(RIG, DIE_DROP * f + Vector((0, 0, -0.04)) * k * (1 - f))
    p.set("Body", ry(4 * f) @ rx(1.5 * f))
    p.set("Neck", rx(-1 * h) @ rz(-8 * h))
    p.set("Head", rx(1 * h) @ ry(-6 * h))
    p.set("Jaw", rx(20 * k * (1 - h)))
    p.set("Crest", rx(-3 * h))
    mandibles(p, 22 * k)
    tail(p, 4, 1.5, -10 * f)
    p.grow("Pods", 1.0 + 0.06 * f, 1.0 - 0.18 * f, 1.0 + 0.04 * f)
    for row, pts, _parent in LEGS:
        for side, s in K.SIDES:
            ankle = K.mirror(pts[2], s) + K.mirror(DIE_FOOT, s) * f
            pole = Vector((s * 0.6, 0, 1)).normalized()
            leg_ik(p, f"{row}{side}", ankle, ry(s * DIE_TILT * f), pole)
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (36, run),
    "Attack": (ATTACK_FRAMES, attack),
    "Die": (45, die),
}

# --- measures ---------------------------------------------------------------------------------------


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


def lowest() -> dict:
    """The lowest posed vertex per bone, for the bones reaching below 0.1 m."""
    low = {g: min((v.z for v in bone_verts([g])), default=9.0) for g, *_r in BONES}
    return {g: round(z, 3) for g, z in sorted(low.items(), key=lambda kv: kv[1]) if z < 0.1}


def vec(v: Vector) -> tuple:
    return tuple(round(x, 3) for x in v)


def measures(arm: bpy.types.Object) -> None:
    rest_pose(arm)
    print("BOUNDS rest", bounds())
    trunk = bone_verts(TRUNK_BONES)
    print("BACK top", vec(max(trunk, key=lambda v: v.z)))
    print("LOWEST rest", lowest())
    for _leg, pts, _parent in LEGS:
        hip, knee, ankle = pts[0], pts[1], pts[2]
        axis = (ankle - hip).normalized()
        off = knee - hip
        print("KNEE", _leg, "out of the hip-ankle line", round((off - axis * off.dot(axis)).length, 3))
    print("POINT pods center rest (Pods)", vec(pods_center()))
    print("POINT head rest (Head, skull center)", vec(HEAD_SHAPE.at(0.4)[0]))
    tips = [min(bone_verts([f"{side}Mandible"]), key=lambda v: v.y) for side in ("Left", "Right")]
    print("POINT jaws rest (Jaw, between the mandibles' tips)", vec((tips[0] + tips[1]) / 2), "tips", vec(tips[0]))
    print("POINT mouth rest (Head, behind the teeth)", vec(Vector((0, -2.38, 0.88))))
    for t in [i / ATTACK_FRAMES for i in range(ATTACK_FRAMES + 1)]:
        attack(t)
    print("REACH attack", {k: round(v, 3) for k, v in REACH.items()})
    REACH.clear()
    for name, pose in (
        ("attack_raised", attack(0.45)),
        ("attack_impact", attack(IMPACT_FRAME / ATTACK_FRAMES)),
        ("die", die(1.0)),
        ("run", run(0.25)),
        ("idle", idle(0.25)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        print("BOUNDS", name, bounds())
        print("LOWEST", name, lowest())
        if name == "attack_impact":
            soles = []
            for side in ("Left", "Right"):
                foot = bone_verts([f"Front{side}Foot"])
                low = min(v.z for v in foot)
                sole = [v for v in foot if v.z < low + 0.03]
                soles.append(sum(sole, Vector()) / len(sole))
                print("FOOT", side, "lowest", round(low, 3), "sole center", vec(soles[-1]))
            print(
                "POINT slam impact (between the front feet, frame 30)",
                vec((soles[0] + soles[1]) / 2 * Vector((1, 1, 0))),
            )
            print("POINT pods center at impact", vec(posed_point(pose, "Pods", pods_center())))
        if name == "attack_raised":
            for side in ("Left", "Right"):
                print("FOOT raised", side, "lowest", round(min(v.z for v in bone_verts([f"Front{side}Foot"])), 3))
    print("REACH die", {k: round(v, 3) for k, v in REACH.items()})
    rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------

TARGET = (0, -0.2, 1.2)
FIGURE = (2.3, -1.4, 0)  # the 1.8 m scale figure, beside the front left foot


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=FIGURE)
    shots = []
    rest_pose(arm)
    for view, zoom in (("iso", 0.75), ("hero", 0.95), ("back", 0.95), ("iso", 1.45)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=TARGET, zoom=zoom)
        shots.append(path)
    for name, loc, target in (
        ("side", Vector((11.0, -0.3, 1.6)), (0, -0.1, 1.2)),
        ("head", Vector((2.2, -6.2, 2.2)), (0, -2.0, 1.2)),
        ("top", Vector((0.0, -0.1, 14.0)), (0, -0.1, 0.0)),
    ):
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render_from(path, loc, target, 50, 32, 512)
        shots.append(path)
    for name, pose in (
        ("idle", idle(0.3)),
        ("run", run(0.25)),
        ("attack_raised", attack(0.45)),
        ("attack_impact", attack(IMPACT_FRAME / ATTACK_FRAMES)),
        ("die", die(1.0)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=(0, -0.4, 1.4), zoom=1.0)
        shots.append(path)
        if name in ("attack_raised", "die"):
            path = OUT / "wip" / f"{tag}_{name}_side.png"
            C.render_from(path, Vector((11.0, -0.8, 1.6)), (0, -0.6, 1.1), 50, 24, 512)
            shots.append(path)
    rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def pose_shots(arm: bpy.types.Object, clip: str, t: float) -> None:
    """One frame of a clip from the front, the side, the iso camera and above."""
    C.preview_scene(crystals=False, figure_location=FIGURE)
    apply(arm, CLIPS[clip][1](t))
    bpy.context.view_layer.update()
    print("BOUNDS", clip, t, bounds())
    print("LOWEST", clip, t, lowest())
    stem = f"pose_{clip}_{t:.2f}"
    shots = [OUT / "wip" / f"{stem}_{v}.png" for v in ("front", "side", "iso", "top")]
    C.render_from(shots[0], Vector((0.0, -10.0, 2.0)), (0, -0.5, 1.2), 50, 24, 512)
    C.render_from(shots[1], Vector((11.0, -0.5, 1.6)), (0, -0.5, 1.2), 50, 24, 512)
    C.render(shots[2], view="iso", samples=24, size=512, target=TARGET, zoom=0.75)
    C.render_from(shots[3], Vector((0.0, -0.1, 14.0)), (0, -0.1, 0.0), 50, 24, 512)
    C.contact_sheet(shots, OUT / "wip" / f"{stem}_sheet.png", cols=4, tile=384)


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    measures(arm)
    if MODE == "stats":
        return
    if MODE == "pose":  # pose <clip> <t>
        pose_shots(arm, ARGV[1], float(ARGV[2]))
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "ravager_procedural.blend")
        C.export_glb(OUT / "ravager_draft.glb")


main()
