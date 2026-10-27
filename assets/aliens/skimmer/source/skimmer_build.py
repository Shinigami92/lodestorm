"""Skimmer: the hive's flying spitter (tier 6 hunter), a winged ray. A flat, broad, armored body carries two thick
fleshy wings (span about 2.8 m) with chitin plates along their leading edges and chitin ribs fanning back across
them, a row of glowing spots along each trailing edge; a long, segmented whip tail ends in a glowing barb. A blunt,
broad head with two curved horns flanking a wide maw, small glowing eyes and a glowing throat sac under it, which
swells before the spit. Small claws tucked under the body. Rigged and animated; it never walks.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/skimmer/source/skimmer_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/skimmer/source/skimmer_build.py stats      # measures and pose bounds, no renders
    tools/blender.sh assets/aliens/skimmer/source/skimmer_build.py final      # renders + skimmer_procedural.blend

Everything it writes goes to tmp/assets/skimmer/; skimmer_bake.py turns skimmer_procedural.blend into the game asset.

Layout (Blender Z-up meters; the skimmer faces -Y, its left is +X; the game turns the model by 180 degrees). It flies:
the origin is the center of the body in flight (not the ground), the body level in the air; the game holds it at its
flight height and drops it to the ground when it dies. The maw to the tail root 1.2 m (the horns reach 0.2 m
further), the whip tail 1.8 m to the barb's tip, the wing span 2.84 m.

Skeleton "Skeleton": Root, Body (center of the body: moves the whole body), Hips (the rear of the body) with the tail
chain Tail1..Tail6 (the barb on Tail6), Spine, Chest (the front of the body) with the wing chains
WingLeft1..WingLeft3 and WingRight1..WingRight3 (root to tip, each bone along the span, so a rotation about the
world's Y axis bends the wing up or down at that joint and the beat runs out along it as a wave), Neck with the Sac
(the throat sac, pointing down: the clips scale it), Head, Jaw (the lower jaw, hinged at its rear). No leg bones: the
tucked claws are rigid parts of the body (on Chest).
Meshes: "Creature" (one skinned object: the body, wings and tail weighted to their bones; plates, head, horns, claws
and the tail's segments rigid), "Eyes" and "Glands" (constant emissive in the hive's yellow-green: the throat sac, the
spots along the wings' trailing edges and the tail barb; the game flares them with the eyes).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop, 1.6 s: two slow, powerful wing
beats of 24 frames each, the wave running out to the tips, the body heaving against them, the tail undulating),
"Run" (loop, 1.2 s: two faster beats of 18 frames, the body pitched 10 degrees nose-down and banking a little, the tail
trailing), "Attack" (the spit, once, 0.4 s: the wings rise and the sac swells while the head draws back, then the head
jerks forward, the maw opens and the bolt leaves at frame 7, the wings beating down; the sac empties) and "Die" (once,
1 s: a last spasm of the wings, then they crumple, the outer parts curling up and back, the sac shrinks, the tail goes
limp; the game drops the origin to the ground, so the body rises by DIE_LIFT and the end pose lies flat on it). The
clips key every bone's rotation, the Body's location and the Sac's scale (own bake, the kit's keys no scale).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "skimmer"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Skimmer"
FPS = 30
GLOW = 3.5  # emission strength of the glands (the eyes: 8); TBD (playtest)
FLIGHT = 1.6  # height of the previews only (the model's origin is the body center)
DIE_LIFT = 0.15  # how far Die lifts the body over its origin, which the game drops to the ground

# --- shape ------------------------------------------------------------------------------------------

# The body from behind the head to the tail root: y, center z, half-width, top, bottom (flat and broad).
BODY = [
    (-0.5, 0.0, 0.15, 0.08, 0.065),
    (-0.42, 0.0, 0.2, 0.105, 0.08),
    (-0.3, 0.0, 0.24, 0.125, 0.09),
    (-0.15, 0.0, 0.26, 0.135, 0.095),
    (0.0, 0.0, 0.26, 0.135, 0.095),
    (0.15, 0.0, 0.24, 0.125, 0.09),
    (0.3, 0.0, 0.2, 0.105, 0.08),
    (0.45, 0.0, 0.14, 0.08, 0.062),
    (0.56, -0.004, 0.085, 0.058, 0.048),
    (0.64, -0.008, 0.055, 0.045, 0.04),
]
BODY_SHAPE = K.Profile(BODY)
# The head from the neck to the blunt front: y, z, half-width, top, bottom (broad, flat, a wide maw at the front).
HEAD = [
    (-0.43, 0.0, 0.15, 0.085, 0.068),
    (-0.5, 0.0, 0.175, 0.085, 0.072),
    (-0.58, -0.004, 0.185, 0.075, 0.07),
    (-0.645, -0.01, 0.17, 0.06, 0.06),
    (-0.69, -0.016, 0.13, 0.042, 0.045),
    (-0.71, -0.02, 0.07, 0.024, 0.028),
]
HEAD_SHAPE = K.Profile(HEAD)
# The lower jaw, a broad scoop under the head (rigid on Jaw): y, z, half-width, top, bottom.
JAW_ROWS = [
    (-0.47, -0.058, 0.09, 0.018, 0.02),
    (-0.54, -0.064, 0.13, 0.02, 0.03),
    (-0.62, -0.066, 0.15, 0.018, 0.032),
    (-0.68, -0.062, 0.135, 0.016, 0.026),
    (-0.715, -0.056, 0.08, 0.012, 0.018),
]
MOUTH_POINT = Vector((0, -0.715, -0.045))  # the front of the maw between the lips, where the bolt leaves

# The wing (left side) along its span u (0 = root inside the body, 1 = tip).
WING_X0, WING_XT = 0.1, 1.42
WING_U = [0.0, 0.06, 0.13, 0.2, 0.27, 0.34, 0.41, 0.48, 0.55, 0.62, 0.69, 0.76, 0.82, 0.87, 0.91, 0.945, 0.975, 1.0]
WING_SEG = 20


def wing_frame(u: float) -> tuple:
    """x, leading edge y, chord, half-thickness at the leading edge and the mid-plane's z of the wing at span u: the
    leading edge sweeps back in a curve to a pointed tip, the wing thinning and drooping a little towards it."""
    x = WING_X0 + (WING_XT - WING_X0) * u
    yle = -0.4 + 0.58 * u**1.6
    chord = 0.07 + 0.83 * (1 - u) ** 1.2
    thick = 0.075 * (1 - u) + 0.024 * u
    zm = 0.012 - 0.07 * u * u
    return x, yle, chord, thick, zm


def _airfoil(u: float, th: float) -> Vector:
    x, yle, chord, thick, zm = wing_frame(u)
    c, sn = math.cos(th), math.sin(th)
    xc = (1 - c) / 2  # 0 at the leading edge (th = 0), 1 at the trailing edge (th = pi); top for 0 < th < pi
    h = thick * (1 - 0.6 * xc)
    camber = 0.022 * (1 - u) * math.sin(math.pi * xc)
    return Vector((x, yle + chord * xc, zm + camber + math.copysign(abs(sn) ** 0.55, sn) * h))


def airfoil(u: float, th: float, s: float = 1.0, out: float = 0.0) -> Vector:
    """Point on the wing's surface at span u and angle th around its cross-section (0 = leading edge, pi/2 over
    the top, pi = trailing edge), pushed out by `out` along the section's normal."""
    p = _airfoil(u, th)
    if out:
        t = _airfoil(u, th + 0.01) - _airfoil(u, th - 0.01)
        p += Vector((0, -t.z, t.y)).normalized() * out
    return K.mirror(p, s)


def chord_angle(xc: float) -> float:
    """The angle th on the top surface at chord fraction xc (0 leading, 1 trailing edge)."""
    return math.acos(1 - 2 * min(max(xc, 0.0), 1.0))


def wing_mid(u: float, xc: float, s: float = 1.0) -> Vector:
    th = chord_angle(xc)
    return (airfoil(u, th, s) + airfoil(u, -th, s)) / 2


def wing_half(u: float, xc: float) -> float:
    th = chord_angle(xc)
    return (_airfoil(u, th).z - _airfoil(u, -th).z) / 2


# The whip tail: the bones' joints from the tail root to the barb's base, drooping a little.
TAIL = [
    Vector((0, 0.48, -0.005)),
    Vector((0, 0.76, -0.016)),
    Vector((0, 1.04, -0.03)),
    Vector((0, 1.32, -0.045)),
    Vector((0, 1.59, -0.06)),
    Vector((0, 1.85, -0.072)),
    Vector((0, 2.1, -0.082)),
]
TAIL_R = [0.075, 0.05, 0.04, 0.034, 0.029, 0.025, 0.022]
BARB_TIP = Vector((0, 2.3, -0.09))

# --- skeleton -------------------------------------------------------------------------------------

O = Vector((0, 0, 0))
CHEST = Vector((0, -0.2, 0))
NECK = Vector((0, -0.36, 0))
SKULL = Vector((0, -0.46, 0))
SNOUT = Vector((0, -0.7, -0.01))
JAW_PIVOT = Vector((0, -0.48, -0.058))
SAC_TOP = Vector((0, -0.44, -0.06))
SAC_C = Vector((0, -0.45, -0.115))
SAC_R = (0.115, 0.12, 0.075)  # half-width, half-length, half-height
WING_JOINTS = [0.22, 0.62, 1.02, 1.44]  # |x| of the wing bones' heads and the last tail
WING_Y = -0.12

BONES = [  # name, head, tail, parent
    ("Root", O, (0, -0.1, 0), None),
    ("Body", O, (0, -0.06, 0), "Root"),
    ("Hips", O, (0, 0.46, 0), "Body"),
    ("Spine", O, CHEST, "Body"),
    ("Chest", CHEST, NECK, "Spine"),
    ("Neck", NECK, SKULL, "Chest"),
    ("Sac", SAC_TOP, Vector((0, -0.46, -0.22)), "Neck"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -0.7, -0.062)), "Head"),
]
for _i in range(6):
    BONES.append((f"Tail{_i + 1}", TAIL[_i], TAIL[_i + 1], "Hips" if _i == 0 else f"Tail{_i}"))
for _side, _s in K.SIDES:
    for _i in range(3):
        _h = Vector((_s * WING_JOINTS[_i], WING_Y, 0.0))
        _t = Vector((_s * WING_JOINTS[_i + 1], WING_Y, 0.0))
        BONES.append((f"Wing{_side}{_i + 1}", _h, _t, "Chest" if _i == 0 else f"Wing{_side}{_i}"))
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest", "Neck"]
TAIL_BONES = ["Hips"] + [f"Tail{i}" for i in range(1, 7)]


# --- weights ----------------------------------------------------------------------------------------


def nearest_weights(p: Vector, bones: list, power: float = 4.0) -> dict:
    """The kit's auto weights for one point: the two nearest of `bones` by distance to their segments."""
    ds = sorted((max(K.seg_dist(p, RIG.head[b], RIG.tail[b]), 1e-4), b) for b in bones)[:2]
    w = [1.0 / d**power for d, _b in ds]
    return {b: wi / sum(w) for (_d, b), wi in zip(ds, w)}


def span_weights(p: Vector) -> dict:
    """Weights along a wing: the body's bones at the root, blending into Wing1, Wing2 and Wing3 across the joints."""
    side = "Left" if p.x > 0 else "Right"
    stages = [None, f"Wing{side}1", f"Wing{side}2", f"Wing{side}3"]
    progress = sum(K.smooth((abs(p.x) - (j - 0.09)) / 0.18) for j in WING_JOINTS[:3])
    i = min(int(progress), 3)
    f = progress - i
    out: dict = {}
    for stage, w in ((stages[i], 1 - f), (stages[min(i + 1, 3)], f)):
        if w <= 0:
            continue
        if stage is None:
            for b, bw in nearest_weights(Vector((0, p.y, p.z)), TRUNK_BONES).items():
                out[b] = out.get(b, 0.0) + w * bw
        else:
            out[stage] = out.get(stage, 0.0) + w
    return out


def weigh(sk: K.Skin, verts, fn) -> list:
    """Weights per vertex from fn(position) -> {bone: weight}."""
    for v in verts:
        v[sk.dl].clear()
        for b, w in fn(v.co).items():
            v[sk.dl][RIG.index[b]] = w
    return verts


# --- mesh -------------------------------------------------------------------------------------------


def mirror_angle(a: float, s: float) -> float:
    return a if s > 0 else 180 - a


def loft_profile(sk: K.Skin, rows: list, n: int, seg: int, mi: int, wobble: float = 0.004) -> list:
    rings = []
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in rows], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, seg, wobble, i * 0.9))
    return sk.loft(rings, mi)


def plate_bone(y: float) -> str:
    return "Chest" if y < -0.2 else "Spine" if y < 0.0 else "Hips"


def build_body(sk: K.Skin) -> None:
    sk.auto(loft_profile(sk, BODY, 22, 20, K.SINEW), TRUNK_BONES)
    # Overlapping armor plates down the back (their rear edges lift like scales), narrower towards the tail.
    for y0, y1, half in ((-0.47, -0.3, 52), (-0.33, -0.15, 56), (-0.18, 0.0, 58), (-0.03, 0.15, 56), (0.12, 0.3, 50)):
        sk.rigid(
            K.shell(sk, BODY_SHAPE, y0, y1, 90 - half, 90 + half, 0.003, 0.02, K.CHITIN, 6, 3, 0.012), plate_bone(y0)
        )
    sk.rigid(K.shell(sk, BODY_SHAPE, 0.27, 0.46, 50, 130, 0.003, 0.016, K.CHITIN, 4, 3, 0.01), "Hips")
    # Shoulder plates over the wing roots, a pair of flank plates behind them.
    for _side, s in K.SIDES:
        a0, a1 = sorted((mirror_angle(4, s), mirror_angle(36, s)))
        sk.rigid(K.shell(sk, BODY_SHAPE, -0.4, -0.18, a0, a1, 0.004, 0.018, K.CHITIN, 4, 3, 0.012), "Chest")
        sk.rigid(K.shell(sk, BODY_SHAPE, -0.16, 0.08, a0, a1, 0.004, 0.016, K.CHITIN, 4, 3, 0.01), "Spine")
    # A ridge of short spines down the middle of the back.
    for y, h in ((-0.38, 0.05), (-0.23, 0.065), (-0.08, 0.07), (0.07, 0.06), (0.22, 0.05), (0.37, 0.04)):
        p = BODY_SHAPE.surface(y, 90, 0.012)
        sk.rigid(sk.cone(p, p + Vector((0, 0.04, h)), 0.022, 6, K.CHITIN, 0.6), plate_bone(y))
    # Belly: a few broad, flat plates under the middle.
    for y0, y1 in ((-0.38, -0.2), (-0.2, -0.02), (-0.02, 0.16), (0.16, 0.34)):
        sk.rigid(K.shell(sk, BODY_SHAPE, y0, y1, 240, 300, 0.002, 0.01, K.CHITIN, 4, 2, 0.004), plate_bone(y0))


def build_head(sk: K.Skin, eyes: K.Skin, glands: K.Skin) -> None:
    sk.rigid(loft_profile(sk, HEAD, 10, 16, K.CHITIN, 0.003), "Head")
    # Armored crown with a low keel; the head's front edge (the upper lip) a thick bony rim.
    sk.rigid(K.shell(sk, HEAD_SHAPE, -0.44, -0.66, 30, 150, 0.003, 0.018, K.CHITIN, 6, 4, 0.004), "Head")
    lip = [HEAD_SHAPE.surface(-0.675, a, 0.0) + Vector((0, 0, -0.012)) for a in (-15, 10, 40, 90, 140, 170, 195)]
    sk.rigid(K.tube_path(sk, lip, [0.012, 0.016, 0.018, 0.018, 0.018, 0.016, 0.012], 6, 12, K.BONE), "Head")
    # The maw: a dark wide slit across the front, the gullet behind it (seen when the jaw drops).
    sk.rigid(sk.sphere((0, -0.672, -0.045), 1.0, 14, 6, scale=(0.15, 0.045, 0.024), mi=K.MOUTH), "Head")
    sk.rigid(sk.sphere((0, -0.6, -0.07), 1.0, 12, 6, scale=(0.12, 0.09, 0.03), mi=K.MOUTH), "Head")
    for k in range(7):
        x = -0.12 + 0.04 * k
        base = Vector((x, -0.675 + 0.6 * x * x, -0.05))
        sk.rigid(sk.cone(base, base + Vector((0, -0.008, -0.034)), 0.011, 5, K.BONE), "Head")
    # The lower jaw: a broad chitin scoop with a row of teeth along its front, gums inside.
    sk.rigid(loft_profile(sk, JAW_ROWS, 8, 14, K.CHITIN, 0.002), "Jaw")
    for k in range(6):
        x = -0.1 + 0.04 * k
        base = Vector((x, -0.69 + 0.04 * (x / 0.12) ** 2, -0.05))
        sk.rigid(sk.cone(base, base + Vector((0, -0.006, 0.03)), 0.01, 5, K.BONE), "Jaw")
    for side, s in K.SIDES:
        # Horns: two thick curved lobes flanking the maw, curling forward and in (the front of the silhouette).
        b = Vector((s * 0.15, -0.6, -0.01))
        pts = [
            b,
            b + Vector((s * 0.05, -0.1, -0.008)),
            b + Vector((s * 0.03, -0.21, -0.025)),
            b + Vector((-s * 0.03, -0.27, -0.04)),
        ]
        sk.rigid(K.tube_path(sk, pts, [0.05, 0.04, 0.028, 0.012], 8, 10, K.CHITIN, 0.75), "Head")
        sk.rigid(
            sk.cone(
                pts[-1] + Vector((s * 0.01, 0.02, 0.004)), pts[-1] + Vector((-s * 0.03, -0.04, -0.01)), 0.012, 5, K.BONE
            ),
            "Head",
        )
        # A short swept-back horn over each eye.
        base = HEAD_SHAPE.surface(-0.5, mirror_angle(55, s), 0.008)
        sk.rigid(sk.cone(base, base + Vector((s * 0.03, 0.09, 0.04)), 0.02, 6, K.BONE, 0.7), "Head")
        # Eyes: a pair of small glowing eyes on top of the head's sides, a smaller pair behind them.
        eyes.rigid(
            eyes.sphere(HEAD_SHAPE.surface(-0.6, mirror_angle(38, s), 0.0), 0.024, 10, 6, (1.0, 1.25, 0.8)), "Head"
        )
        eyes.rigid(
            eyes.sphere(HEAD_SHAPE.surface(-0.535, mirror_angle(58, s), 0.0), 0.016, 8, 5, (1.0, 1.2, 0.8)), "Head"
        )
    # The throat sac under the head, ribbed by two chitin bands.
    glands.rigid(glands.sphere(SAC_C, 1.0, 16, 10, scale=SAC_R), "Sac")
    for yb in (-0.41, -0.49):
        pts = []
        for a in range(-20, 201, 20):
            r = math.radians(a)
            dy = (yb - SAC_C.y) / SAC_R[1]
            k = math.sqrt(max(1 - dy * dy, 0.05))
            pts.append(Vector((math.cos(r) * SAC_R[0] * k, yb, SAC_C.z - math.sin(r) * SAC_R[2] * k)))
        pts = [p + (p - Vector((0, yb, SAC_C.z))).normalized() * 0.006 for p in pts]
        sk.rigid(K.tube_path(sk, pts, [0.013] * len(pts), 6, 14, K.CHITIN, 1.0, 0.0, Vector((0, 1, 0))), "Sac")
    # Neck folds over the sac's root.
    sk.auto(
        K.tube_path(sk, [Vector((0, -0.34, -0.03)), Vector((0, -0.46, -0.04))], [0.1, 0.1], 12, 3, K.SINEW, 0.6),
        ["Chest", "Neck"],
    )


def build_claws(sk: K.Skin) -> None:
    """Two pairs of small claws tucked under the front of the body, folded back with their hooks forward."""
    for y in (-0.3, -0.14):
        for _side, s in K.SIDES:
            hip = Vector((s * 0.1, y, -0.07))
            knee = Vector((s * 0.15, y + 0.08, -0.115))
            hand = Vector((s * 0.11, y - 0.03, -0.14))
            tip = Vector((s * 0.075, y - 0.08, -0.12))
            sk.rigid(K.tube_path(sk, [hip, knee], [0.03, 0.025], 6, 2, K.CHITIN), "Chest")
            sk.rigid(sk.sphere(knee, 0.026, 6, 4, mi=K.SINEW), "Chest")
            sk.rigid(K.tube_path(sk, [knee, hand], [0.023, 0.018], 6, 2, K.CHITIN), "Chest")
            sk.rigid(sk.cone(hand + (hand - tip).normalized() * 0.01, tip, 0.017, 5, K.BONE), "Chest")


def build_wings(sk: K.Skin, glands: K.Skin) -> None:
    for _side, s in K.SIDES:
        # The membrane: a thick, cambered, fleshy airfoil from inside the body out to the pointed tip.
        rings = [[airfoil(u, math.tau * k / WING_SEG, s) for k in range(WING_SEG)] for u in WING_U]
        weigh(sk, sk.loft(rings, K.SINEW), span_weights)
        # Overlapping chitin plates wrapping the leading edge, shingled out towards the tip.
        edges = [0.04, 0.17, 0.3, 0.43, 0.56, 0.68, 0.79, 0.89, 0.97]
        for u0, u1 in itertools.pairwise(edges):
            top_rows, bot_rows = [], []
            nv, nu = 3, 5
            for i in range(nv + 1):
                v = i / nv
                u = u0 + (u1 + 0.03 - u0) * v
                scale = 1.0 - 0.45 * u
                row_t, row_b = [], []
                for k in range(nu + 1):
                    w = k / nu
                    th = -0.85 + 2.15 * w
                    edge = math.sin(math.pi * w) ** 0.5
                    o = 0.003 + 0.01 * scale * v * edge
                    row_t.append(
                        sk.bm.verts.new(
                            airfoil(u, th, s, o + 0.016 * scale * edge * (0.4 + 0.6 * math.sin(math.pi * v)))
                        )
                    )
                    row_b.append(sk.bm.verts.new(airfoil(u, th, s, o)))
                top_rows.append(row_t)
                bot_rows.append(row_b)
            weigh(sk, K.close_grid(sk, top_rows, bot_rows, K.CHITIN), span_weights)
        # Chitin ribs fanning back across the top of the wing from the leading edge plates to the trailing edge.
        for k in range(5):
            u0 = 0.03 + 0.16 * k
            u1 = min(u0 + 0.22 + 0.04 * k, 0.95)
            pts = []
            for i in range(7):
                f = i / 6
                pts.append(airfoil(u0 + (u1 - u0) * f**1.2, chord_angle(0.2 + 0.68 * f), s, 0.006))
            r0 = 0.028 - 0.003 * k
            radii = [r0, r0, r0 * 0.95, r0 * 0.88, r0 * 0.8, r0 * 0.72, r0 * 0.62]
            weigh(sk, K.tube_path(sk, pts, radii, 6, 10, K.CHITIN, 0.5), span_weights)
        # Glowing spots along the trailing edge, poking out above and below it.
        for i in range(8):
            u = 0.1 + 0.1 * i
            c = wing_mid(u, 0.9, s)
            r = 0.044 * (1 - 0.4 * u)
            hz = wing_half(u, 0.9) + 0.012
            weigh(glands, glands.sphere(c, 1.0, 10, 6, scale=(r * 1.15, r, hz)), span_weights)


def build_tail(sk: K.Skin, glands: K.Skin) -> None:
    sk.auto(K.tube_path(sk, TAIL, TAIL_R, 10, 40, K.SINEW, 0.85), TAIL_BONES)
    # Chitin rings over each bone (gaps at the joints) with a short spine on top.
    for i in range(6):
        a, b = TAIL[i], TAIL[i + 1]
        r0, r1 = TAIL_R[i], TAIL_R[i + 1]
        for f0, f1 in ((0.1, 0.48), (0.55, 0.92)):
            p0, p1 = a.lerp(b, f0), a.lerp(b, f1)
            q0, q1 = r0 + (r1 - r0) * f0, r0 + (r1 - r0) * f1
            g = max(0.012, 0.25 * q0)
            sk.rigid(
                K.tube_path(sk, [p0, p1], [q0 * 0.85 + g, q1 * 0.85 + g * 1.3], 8, 2, K.CHITIN, 0.85), f"Tail{i + 1}"
            )
        top = a.lerp(b, 0.6) + Vector((0, 0, r0 * 0.85 + 0.008))
        h = 0.05 * (1 - i / 7)
        sk.rigid(sk.cone(top, top + Vector((0, h * 0.8, h)), max(0.012, r0 * 0.45), 5, K.CHITIN, 0.6), f"Tail{i + 1}")
    # The barb: a glowing blade at the end with a chitin collar and two bone hooks pointing back.
    end = TAIL[-1]
    d = (BARB_TIP - end).normalized()
    sk.rigid(K.tube_path(sk, [end - d * 0.05, end + d * 0.025], [0.03, 0.038], 8, 2, K.CHITIN), "Tail6")
    mid = end.lerp(BARB_TIP, 0.5)
    glands.rigid(glands.sphere(mid, 1.0, 12, 6, scale=(0.06, (BARB_TIP - end).length / 2, 0.026)), "Tail6")
    for _side, s in K.SIDES:
        base = end + d * 0.05 + Vector((s * 0.035, 0, 0))
        sk.rigid(sk.cone(base, base + Vector((s * 0.07, -0.05, 0.0)), 0.016, 5, K.BONE, 0.6), "Tail6")


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    sk = K.Skin("Creature", K.materials(), RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLOW)], RIG)
    build_body(sk)
    build_head(sk, eyes, glands)
    build_claws(sk)
    build_wings(sk, glands)
    build_tail(sk, glands)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


class Pose(K.Pose):
    """The kit's pose plus a scale per bone (the sac swelling and squeezing), as (width, length, depth) in the
    bone's axes: for Sac (pointing down) about x, -z and y of the world."""

    def __init__(self, rig: K.Rig, offset=(0, 0, 0)):
        super().__init__(rig, offset)
        self.scale: dict = {}

    def grow(self, bone: str, width: float, length: float, depth: float) -> "Pose":
        self.scale[bone] = Vector((width, length, depth))
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


def wings(p: Pose, phase: float, amp: tuple, mid: tuple, lag: float = 0.75, twist: float = 6.0) -> None:
    """Beat the wings: each joint bends up and down (positive = up) a little later than the one before it, so the
    wave runs out to the tips; the wing pitches its leading edge down on the down stroke."""
    for side, s in K.SIDES:
        for i in range(3):
            a = phase - i * lag
            bend = mid[i] + amp[i] * math.sin(a)
            p.set(f"Wing{side}{i + 1}", ry(-s * bend) @ rx(twist * math.cos(a) * (1 - 0.3 * i)))


def tail_wave(p: Pose, phase: float, slow: float, up: float, side: float, droop: float = 0.0) -> None:
    """The tail undulating: a wave up and down with the beat and a slower sway from side to side, both running out
    to the barb, growing towards it."""
    for i in range(6):
        g = 0.6 + 0.12 * i
        p.set(
            f"Tail{i + 1}",
            rx(-droop + up * g * math.sin(phase - 1.0 - 0.7 * i)) @ rz(side * g * math.sin(slow - 0.6 * i)),
        )


def idle(t: float) -> Pose:
    """Hovering: two slow, powerful beats (24 frames each), the body heaving against them, the head turning a little,
    the sac breathing, the tail undulating."""
    a = math.tau * t
    beat = 2 * a
    p = Pose(RIG, (0.01 * math.sin(a), 0.012 * math.sin(beat + 0.5), -0.045 * math.sin(beat - 0.5)))
    p.set("Body", rx(-2.5 * math.cos(beat - 0.3)) @ ry(2.5 * math.sin(a)))
    p.set("Head", rz(5 * math.sin(a + 1.0)) @ rx(2 * math.sin(beat - 0.8)))
    p.set("Jaw", rx(3 + 3 * max(0.0, math.sin(a - 0.4)) ** 2))
    p.set("Sac", rx(3 * math.sin(beat - 1.2)))
    breath = 1.0 + 0.05 * math.sin(a - 0.5)
    p.grow("Sac", breath, 1.0 + 0.06 * math.sin(a - 0.5), breath)
    wings(p, beat, (16, 13, 11), (3, 2, 0))
    tail_wave(p, beat, a, 4.0, 7.0)
    return p


def run(t: float) -> Pose:
    """Fast forward flight: two faster beats (18 frames each), the body pitched nose-down and banking a little, the
    head raised against the pitch, the tail trailing straight behind and flicking."""
    a = math.tau * t
    beat = 2 * a
    p = Pose(RIG, (0, 0, -0.035 * math.sin(beat - 0.5)))
    p.set("Body", rx(10 + 2 * math.cos(beat - 0.3)) @ ry(7 * math.sin(a)) @ rz(2.5 * math.sin(a + 0.6)))
    p.set("Head", rx(-6))
    p.set("Jaw", rx(2))
    p.set("Sac", rx(-6))
    p.grow("Sac", 0.96, 0.95, 0.96)
    wings(p, beat, (20, 16, 13), (2, 1, -1), lag=0.8, twist=8.0)
    tail_wave(p, beat, a, 2.5, 4.0, droop=-1.5)
    p.set("Tail1", rx(-6 + 2 * math.sin(beat - 1.0)) @ rz(4 * math.sin(a - 0.6)))
    return p


HIT = 7  # the spit's frame in "Attack": the bolt leaves the maw


def attack(t: float) -> Pose:
    """The spit (0.4 s): the wings rise and the sac swells while the head draws back (to the hit at frame 7), then the
    head jerks forward and down, the maw gapes and the bolt leaves; the wings beat down and the sac empties."""
    hit = HIT / CLIPS_FRAMES["Attack"]
    load = K.smooth(t / hit) * (1 - K.smooth((t - hit) / 0.12))
    jerk = K.smooth((t - hit + 0.14) / 0.14) * (1 - K.smooth((t - hit - 0.05) / (0.95 - hit)))
    empty = K.smooth((t - hit + 0.04) / 0.12) * (1 - K.smooth((t - 0.75) / 0.25))
    stroke = K.smooth((t - hit + 0.12) / 0.2)
    back = 1 - K.smooth((t - 0.7) / 0.3)
    p = Pose(RIG, (0, 0.05 * load - 0.06 * jerk, 0.02 * load - 0.03 * jerk))
    p.set("Body", rx(-8 * load + 7 * jerk))
    p.set("Head", rx(-14 * load + 16 * jerk))
    p.set("Jaw", rx(3 + 5 * load + 32 * jerk))
    p.set("Sac", rx(-6 * load + 10 * jerk))
    w = 1.0 + 0.35 * load - 0.2 * empty
    p.grow("Sac", w, 1.0 + 0.45 * load - 0.25 * empty, w)
    up = 22 * (1 - stroke) * K.smooth(t / 0.4) - 20 * stroke * back
    wings(p, 0.0, (0, 0, 0), (up, up * 0.6, up * 0.4), twist=0.0)
    for i in range(6):
        p.set(f"Tail{i + 1}", rx(5 * load - 8 * jerk * (0.6 + 0.12 * i)))
    return p


def die(t: float) -> Pose:
    """A last spasm of the wings, then they crumple: the inner wing sags, the outer parts curl up and fold back (one
    wing more than the other), the head and the slack jaw droop, the sac shrinks, the tail goes limp. The game drops
    the origin to the ground (in 0.4 s), so the end pose lies flat on it: the body rises by DIE_LIFT, the wings and
    the tail drape down to z = -DIE_LIFT and nothing hangs more than about 2 cm below that."""
    spasm = math.sin(t * 40) * (1 - K.smooth((t - 0.05) / 0.3))
    fold = K.smooth((t - 0.12) / 0.6)
    limp = K.smooth((t - 0.1) / 0.8)
    p = Pose(RIG, (0, 0, DIE_LIFT * K.smooth(t / 0.4)))
    p.set("Body", ry(4 * fold) @ rx(1 * fold + 4 * spasm))
    p.set("Head", rx(-2 * fold) @ rz(8 * spasm + 6 * fold))
    p.set("Jaw", rx(3 + 6 * fold))
    p.set("Sac", rx(-10 * fold))
    p.grow("Sac", 1.0 - 0.2 * fold, 1.0 - 0.5 * fold, 1.0 - 0.2 * fold)
    for side, s in K.SIDES:
        k = 1.0 if s > 0 else 0.75
        bends = (-7, 2 + 8 * k, 8 + 16 * k)
        sweeps = (6 * k, 14 * k, 18 * k)
        twists = (-4, 10 * k, 18 * k)
        for i in range(3):
            bend = 18 * spasm * (1 - 0.2 * i) * (1 - fold) + bends[i] * fold
            p.set(f"Wing{side}{i + 1}", rz(s * sweeps[i] * fold) @ ry(-s * bend) @ rx(twists[i] * fold))
    curl = (0, 9, 12, 10, 8, 6)
    for i in range(6):
        drape = (-6 if i == 0 else 1.2) * limp
        p.set(f"Tail{i + 1}", rx(drape + 6 * spasm) @ rz(curl[i] * limp))
    return p


CLIPS_FRAMES = {"Idle": 48, "Run": 36, "Attack": 12, "Die": 30}
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
    rest_pose(arm)
    body = mesh_points("Creature")
    allp = body + mesh_points("Glands") + mesh_points("Eyes")
    lo = Vector([min(p[i] for p in allp) for i in range(3)])
    hi = Vector([max(p[i] for p in allp) for i in range(3)])
    print("MEASURE bounds", fmt(lo), fmt(hi), "size", fmt(hi - lo))
    trunk = [p for p in body if abs(p.x) < 0.3 and p.y < 0.6]
    print("MEASURE trunk y", round(min(p.y for p in trunk), 3), "back top", fmt(max(trunk, key=lambda p: p.z)))
    print("MEASURE belly low", fmt(min(trunk, key=lambda p: p.z)))
    print("MEASURE wing tips", fmt(max(body, key=lambda p: p.x)), fmt(min(body, key=lambda p: p.x)))
    print("MEASURE wing tip bone tails", fmt(RIG.tail["WingLeft3"]), fmt(RIG.tail["WingRight3"]))
    print("MEASURE body center", fmt(RIG.head["Body"]))
    print("MEASURE tail barb tip rest", fmt(BARB_TIP), "barb center", fmt(TAIL[-1].lerp(BARB_TIP, 0.5)))
    print("MEASURE mouth rest", fmt(MOUTH_POINT), "sac center rest", fmt(SAC_C))
    frames = CLIPS_FRAMES["Attack"]
    for f in range(frames + 1):
        apply(arm, attack(f / frames))
        bpy.context.view_layer.update()
        m = posed(arm, "Head", MOUTH_POINT)
        print(
            f"MEASURE attack frame {f} mouth",
            fmt(m),
            "sac",
            fmt(posed(arm, "Sac", SAC_C)),
            "(spit)" if f == HIT else "",
        )
    for name, (frames, fn) in CLIPS.items():
        zs = []
        for f in range(frames + 1):
            apply(arm, fn(f / frames))
            bpy.context.view_layer.update()
            pts = mesh_points("Creature")
            zs.append((min(p.z for p in pts), max(p.z for p in pts), max(abs(p.x) for p in pts)))
        print(
            f"MEASURE {name} min z {min(z[0] for z in zs):.3f} max z {max(z[1] for z in zs):.3f}",
            f"max |x| {max(z[2] for z in zs):.3f}",
        )
    apply(arm, die(1.0))
    bpy.context.view_layer.update()
    for name in ("Creature", "Glands", "Eyes"):
        pts = mesh_points(name)
        low = min(pts, key=lambda p: p.z)
        below = sum(1 for p in pts if p.z < -0.02) / len(pts)
        print(f"MEASURE die end {name} (origin on the ground) lowest {fmt(low)}, {below:.1%} of the verts under -2 cm")
    rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------


def add_swarmer(x: float) -> list:
    """The swarmer's rest-pose mesh on the ground beside the skimmer for a scale check (wip only)."""
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


def shot(arm: bpy.types.Object, shots: list, name: str, pose: Pose | None, **kw) -> None:
    if pose is None:
        rest_pose(arm)
    else:
        apply(arm, pose)
    bpy.context.view_layer.update()
    path = OUT / "wip" / f"{TAG if MODE == 'wip' else 'final'}_{name}.png"
    if "location" in kw:
        C.render_from(path, Vector(kw["location"]), kw["target"], 50, 32, 512)
    else:
        C.render(path, view=kw.get("view", "iso"), samples=32, size=512, target=kw["target"], zoom=kw["zoom"])
    shots.append(path)


def preview(root: bpy.types.Object, arm: bpy.types.Object) -> list:
    """Renders with the skimmer lifted to FLIGHT (its shadow on the ground); the root goes back to the origin after."""
    C.preview_scene(crystals=False, figure_location=(2.3, 1.2, 0))
    root.location = (0, 0, FLIGHT)
    bpy.context.view_layer.update()
    shots = []
    up = FLIGHT
    tgt = (0, 0.55, up)
    side = (3.6, 0.6, up + 0.3)
    shot(arm, shots, "rest_iso", None, target=tgt, zoom=0.42)
    shot(arm, shots, "rest_hero", None, view="hero", target=tgt, zoom=0.5)
    shot(arm, shots, "rest_back", None, view="back", target=tgt, zoom=0.5)
    shot(arm, shots, "top", None, location=(0, 0.55, up + 6.0), target=tgt)
    shot(arm, shots, "side", None, location=side, target=(0, 0.6, up - 0.05))
    shot(arm, shots, "head", None, location=(0.7, -1.7, up + 0.35), target=(0, -0.5, up - 0.03))
    shot(arm, shots, "under", None, location=(1.3, -1.2, up - 1.4), target=(0, 0.0, up - 0.05))
    shot(arm, shots, "iso_far", None, target=tgt, zoom=1.4)
    shot(arm, shots, "idle_up", idle(18 / 48), target=tgt, zoom=0.42)
    shot(arm, shots, "idle_down", idle(6 / 48), target=tgt, zoom=0.42)
    shot(arm, shots, "run", run(0.2), view="hero", target=tgt, zoom=0.5)
    shot(arm, shots, "run_iso", run(0.6), target=tgt, zoom=0.42)
    shot(arm, shots, "attack_load", attack(5 / 12), location=(2.6, -1.4, up + 0.2), target=(0, -0.35, up - 0.05))
    shot(arm, shots, "attack_spit", attack(HIT / 12), location=(2.6, -1.4, up + 0.2), target=(0, -0.35, up - 0.05))
    shot(arm, shots, "attack_spit_hero", attack(HIT / 12), view="hero", target=tgt, zoom=0.5)
    shot(arm, shots, "die_mid", die(0.3), view="hero", target=tgt, zoom=0.5)
    # The end of Die on the ground, where the game has dropped the origin.
    root.location = (0, 0, 0)
    gnd = (0, 0.55, 0.1)
    shot(arm, shots, "die", die(1.0), view="hero", target=gnd, zoom=0.5)
    shot(arm, shots, "die_low", die(1.0), location=(3.0, -0.4, 0.25), target=(0, 0.2, 0.05))
    shot(arm, shots, "die_top", die(1.0), location=(0, 0.55, 6.0), target=gnd)
    root.location = (0, 0, FLIGHT)
    rest_pose(arm)
    if MODE == "wip":
        scale = add_swarmer(-2.0)
        if scale:
            shot(arm, shots, "scale", None, target=(-0.8, 0.5, 0.8), zoom=0.55)
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
        bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "skimmer_procedural.blend")
        C.export_glb(OUT / "skimmer_draft.glb")


main()
