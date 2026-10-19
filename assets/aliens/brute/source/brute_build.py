"""Brute: the hive's heavy hunter (tier 3), a big, low rhino-beetle on four thick legs. Heavy layered chitin plates
armor its front: a big pronotum shield over the head, the shoulders and the chest sweeps back over the front half of
the body (hits from the front bounce), with a short thoracic horn on its crest and a long, forward-curving nose horn
under it (the horns are its silhouette from the game's camera). The back half is soft: the plates end in a ragged
edge, behind it sinewy flesh in swollen segments with glowing gland slits across them (its weak spot, readable from
above). Thick, short, pillar-like legs on broad pads with heavy claws; small eyes deep under the shield's rim.
Rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/brute/source/brute_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/brute/source/brute_build.py stats      # measures and pose bounds only
    tools/blender.sh assets/aliens/brute/source/brute_build.py final      # renders + brute_procedural.blend

Everything it writes goes to tmp/assets/brute/; brute_bake.py turns brute_procedural.blend into the game asset.

Layout (Blender Z-up meters; the brute faces -Y, its left is +X). Feet on the ground at the origin, the origin under
the middle of the body; the shield about 1.25 m high, the nose horn's tip to the rump about 2.3 m, about 1.2 m wide.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (the soft abdomen, to the rump) with
the hind legs, Spine, Chest (the shield and the thoracic horn) with the front legs, Neck, Head (the nose horn), Jaw
(the mandibles). Four legs (<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the front elbows bend back and out, the hind
knees forward and out, the Foot is the pad with its claws. The game moves the legs by IK (two bones reaching the
ankle = the Foot bone's head, the Foot keeps its angle), so Idle and Run leave them at rest; Attack keeps the feet
planted (solved by the same two-bone IK), Die folds them.
Meshes: "Creature" (one skinned object: the trunk, neck, head and limbs weighted to the nearest bones; plates, horns,
claws and mandibles rigid or nearly), "Eyes" (constant emissive) and "Glands" (constant emissive: the slits across
the soft back, skinned to Hips and Spine).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: heavy breathing, the head swinging
low from side to side, a scrape of the front), "Run" (loop: a heavy charging gallop of the trunk, the head low),
"Attack" (once, 0.6 s: the head drops, then hooks the horn up and forward, the impact at frame IMPACT_FRAME) and
"Die" (once: the front legs buckle, it rolls onto its left side, the legs fold).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "brute"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Matrix, Vector, noise

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Brute"
FPS = 30
GLAND_GLOW = 3.0  # the weak spot on its back (the eyes: 8)
I3 = Matrix.Identity(3)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.05, 0.8))
PELVIS = Vector((0, 0.84, 0.68))
SHOULDER = Vector((0, -0.32, 0.82))
WITHERS = Vector((0, -0.56, 0.8))
NECK_BASE = Vector((0, -0.56, 0.7))
SKULL = Vector((0, -0.7, 0.66))
SNOUT = Vector((0, -0.96, 0.6))
JAW_PIVOT = Vector((0, -0.76, 0.56))
# Leg joints per side (x for the left side): shoulder/hip, elbow/knee, ankle (the pad's top), the pad's front.
FRONT = [
    Vector((0.33, -0.36, 0.62)),
    Vector((0.48, -0.18, 0.4)),
    Vector((0.44, -0.44, 0.19)),
    Vector((0.44, -0.58, 0.02)),
]
HIND = [
    Vector((0.31, 0.52, 0.6)),
    Vector((0.46, 0.3, 0.4)),
    Vector((0.43, 0.6, 0.19)),
    Vector((0.43, 0.46, 0.02)),
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
    ("Jaw", JAW_PIVOT, Vector((0, -0.96, 0.5)), "Head"),
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

# Trunk profile from the rump forward: y, center z, half-width, top, bottom. A broad oval abdomen behind, the thorax
# under the shield in front (the shield hugs it a little bigger).
TRUNK = [
    (0.94, 0.66, 0.07, 0.05, 0.05),
    (0.88, 0.68, 0.22, 0.15, 0.14),
    (0.76, 0.71, 0.35, 0.24, 0.22),
    (0.6, 0.75, 0.43, 0.29, 0.26),
    (0.4, 0.78, 0.46, 0.32, 0.29),
    (0.2, 0.8, 0.47, 0.33, 0.3),
    (-0.04, 0.8, 0.47, 0.33, 0.31),
    (-0.28, 0.8, 0.46, 0.33, 0.3),
    (-0.48, 0.8, 0.4, 0.32, 0.27),
    (-0.62, 0.76, 0.3, 0.24, 0.2),
    (-0.7, 0.72, 0.15, 0.12, 0.11),
]
TRUNK_SHAPE = K.Profile(TRUNK)
# The pronotum shield from its front rim (low over the head) back to where it ends: y, center z, half-width, top,
# bottom.
SHIELD = [
    (-0.94, 0.72, 0.3, 0.12, 0.05),
    (-0.8, 0.76, 0.43, 0.26, 0.16),
    (-0.6, 0.79, 0.5, 0.34, 0.27),
    (-0.36, 0.8, 0.52, 0.37, 0.31),
    (-0.12, 0.81, 0.52, 0.37, 0.32),
    (0.12, 0.8, 0.5, 0.36, 0.31),
    (0.36, 0.8, 0.48, 0.34, 0.3),
]
SHIELD_SHAPE = K.Profile(SHIELD)
# The head from the back of the skull to the snout: y, center z, half-width, top, bottom. Broad, low and blunt.
HEAD = [
    (-0.64, 0.67, 0.14, 0.09, 0.09),
    (-0.72, 0.67, 0.17, 0.11, 0.1),
    (-0.82, 0.65, 0.16, 0.1, 0.09),
    (-0.9, 0.62, 0.12, 0.08, 0.07),
    (-0.96, 0.6, 0.07, 0.05, 0.045),
]
# The soft back: the seams between its swollen segments (y), each with a glowing slit.
SEAMS = (0.38, 0.5, 0.62, 0.73)
# The horns' paths (the nose horn on the Head, the thoracic horn on the Chest).
NOSE_HORN = [
    Vector((0, -0.86, 0.7)),
    Vector((0, -1.02, 0.73)),
    Vector((0, -1.18, 0.79)),
    Vector((0, -1.33, 0.9)),
    Vector((0, -1.41, 1.01)),
]
NOSE_TIP = Vector((0, -1.43, 1.1))
THORAX_HORN = [
    Vector((0, -0.3, 1.13)),
    Vector((0, -0.52, 1.24)),
    Vector((0, -0.78, 1.26)),
    Vector((0, -0.98, 1.18)),
]
THORAX_TIP = Vector((0, -1.06, 1.09))
POS: dict = {}  # positions measured while building (for the report)


# --- helpers ----------------------------------------------------------------------------------------


def slab(sk: K.Skin, top: list, bottom: list, mi: int) -> list:
    """A closed slab between two grids of points (rows of the same length)."""
    top_v = [[sk.bm.verts.new(p) for p in row] for row in top]
    bot_v = [[sk.bm.verts.new(p) for p in row] for row in bottom]
    return K.close_grid(sk, top_v, bot_v, mi)


def plate(
    sk: K.Skin,
    profile: K.Profile,
    y0: float,
    y1: float,
    a0: float,
    a1: float,
    thick: float,
    lift: float,
    nu: int = 8,
    nv: int = 3,
    rag: float = 0.0,
    seed: int = 0,
    out: float = 0.0,
    flare: float = 0.0,
) -> list:
    """A curved plate hugging `profile` between y0 (front) and y1 (rear) and the angles a0..a1 (0 = left, 90 = top);
    its rear edge lifts off over the next plate like a scale, its lower rim flares out by `flare`. rag > 0 tears the rear edge into ragged points (each
    column's rear end shifted by up to rag); the top surface gets a little noise so it isn't machined."""
    rnd = random.Random(seed)
    ends = []
    for k in range(nu + 1):
        jag = rnd.uniform(-0.5, 1.0) if k % 2 else rnd.uniform(-0.8, -0.2)
        ends.append(y1 + rag * jag if 0 < k < nu else y1 - rag * 0.5)
    top, bottom = [], []
    for i in range(nv + 1):
        v = i / nv
        bulge = math.sin(math.pi * v) * 0.6 + 0.4
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            y = y0 + (ends[k] - y0) * v
            a = a0 + (a1 - a0) * u
            edge = math.sin(math.pi * u) ** 0.5
            o = out + lift * v * edge + flare * max(0.0, -math.sin(math.radians(a))) ** 1.5
            b = profile.surface(y, a, o)
            n = profile.surface(y, a, o + 0.1) - b
            t = thick * bulge * (0.35 + 0.65 * edge)
            t *= 1.0 + 0.25 * noise.noise(b * 6.0 + Vector((seed, 0, 0)))
            row_b.append(b)
            row_t.append(b + n.normalized() * t)
        top.append(row_t)
        bottom.append(row_b)
    return slab(sk, top, bottom, K.CHITIN)


def rounded_ring(c: Vector, wx: float, wy: float, seg: int) -> list:
    """A horizontal rounded-rectangle ring (superellipse) around c."""
    pts = []
    for k in range(seg):
        a = math.tau * k / seg
        ca, sa = math.cos(a), math.sin(a)
        pts.append(c + Vector((math.copysign(abs(ca) ** 0.6, ca) * wx, math.copysign(abs(sa) ** 0.6, sa) * wy, 0)))
    return pts


def seam_pinch(y: float) -> float:
    """How much the soft back is pinched in at y (0..1, deepest at the seams)."""
    if y < SEAMS[0] - 0.08:
        return 0.0
    return max(0.0, 1 - min(abs(y - s) for s in SEAMS) / 0.05) ** 1.5


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: K.Skin, glands: K.Skin) -> None:
    n = 28
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        pinch = 1 - 0.06 * seam_pinch(c.y)
        wob = 0.008 + 0.014 * K.smooth((c.y - 0.2) / 0.3)
        rings.append(K.section(c, Vector((0, -1, 0)), w * pinch, top * pinch, bot, 18, wob, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # The soft back: across every seam a glowing slit between two swollen lips of sinew, curving a little forward
    # in the middle; the slits shorten towards the rump.
    for k, y in enumerate(SEAMS):
        reach = 60 - 7 * k
        lip_pts, slit_pts = [[], []], []
        for j in range(7):
            a = 90 - reach + 2 * reach * j / 6
            bow = -0.025 * math.cos(math.radians(a - 90) * 1.4)
            slit_pts.append(TRUNK_SHAPE.surface(y + bow, a, -0.012))
            lip_pts[0].append(TRUNK_SHAPE.surface(y + bow - 0.05, a, -0.004))
            lip_pts[1].append(TRUNK_SHAPE.surface(y + bow + 0.05, a, -0.004))
        radii = [0.016, 0.03, 0.036, 0.038, 0.036, 0.03, 0.016]
        glands.auto(K.tube_path(glands, slit_pts, radii, 8, 12, 0, 0.75), ["Hips", "Spine"])
        for pts in lip_pts:
            sk.auto(K.tube_path(sk, pts, [r * 1.05 for r in radii], 8, 12, K.MOUTH, 0.85, 0.004), TRUNK_BONES)
    # A row of short ribs down each flank of the soft back, between the seams.
    for _side, s in K.SIDES:
        for y in (0.49, 0.63, 0.77):
            pts = [TRUNK_SHAPE.surface(y, (28 - 24 * j) if s > 0 else (152 + 24 * j), 0.0) for j in range(4)]
            sk.auto(K.tube_path(sk, pts, [0.024, 0.03, 0.026, 0.014], 6, 4, K.SINEW), TRUNK_BONES)
    # Belly plates: three heavy sternites under the thorax.
    for y0, y1 in ((-0.6, -0.36), (-0.4, -0.14), (-0.18, 0.08)):
        sk.auto(plate(sk, TRUNK_SHAPE, y0, y1, 235, 305, 0.035, 0.02, 5, 2), TRUNK_BONES, 8.0)
    # The rump: a small blunt plate over the tip of the abdomen.
    sk.auto(plate(sk, TRUNK_SHAPE, 0.83, 0.95, 30, 150, 0.03, 0.0, 6, 2, seed=11), ["Hips"], 8.0)


def build_shield(sk: K.Skin) -> None:
    """The pronotum: four layered plates from the rim over the head back over the front half, each rear edge lifted
    over the next, the last one torn into a ragged edge; a few loose scutes behind it in the flesh. The thoracic horn
    on its crest, a short horn at each front corner."""
    layers = [  # y0, y1, a0, a1, thick, lift, rag
        (-0.96, -0.6, -30, 210, 0.06, 0.06, 0.0),
        (-0.68, -0.2, -40, 220, 0.075, 0.07, 0.0),
        (-0.28, 0.02, -34, 214, 0.06, 0.06, 0.0),
        (-0.06, 0.2, -26, 206, 0.05, 0.04, 0.1),
    ]
    for i, (y0, y1, a0, a1, thick, lift, rag) in enumerate(layers):
        nu, nv = (18 if rag else 12), (4 if i == 1 else 3)
        verts = plate(sk, SHIELD_SHAPE, y0, y1, a0, a1, thick, lift, nu, nv, rag, 3 + i, flare=0.12)
        sk.auto(verts, ["Spine", "Chest"] if i < 2 else TRUNK_BONES, 8.0)
        if i == 0:
            front = min(verts, key=lambda v: v.co.y - 0.5 * v.co.z)
            POS["shield_front"] = front.co.copy()
    # Loose scutes behind the ragged edge, getting smaller.
    for y, a, size in (
        (0.3, 62, 0.05),
        (0.31, 120, 0.045),
        (0.26, 34, 0.055),
        (0.27, 148, 0.055),
        (0.36, 14, 0.045),
        (0.37, 166, 0.045),
    ):
        sk.auto(
            plate(sk, TRUNK_SHAPE, y - size, y + size, a - size * 220, a + size * 220, 0.022, 0.01, 4, 2, seed=int(a)),
            TRUNK_BONES,
            8.0,
        )
    # Shoulder plates: two more layers low over each front leg's root.
    for _side, s in K.SIDES:
        for k, (a0, a1, y0, y1, out) in enumerate(((-30, 8, -0.6, -0.12, 0.02), (-46, -14, -0.54, -0.2, 0.05))):
            if s < 0:
                a0, a1 = 180 - a1, 180 - a0
            verts = plate(sk, SHIELD_SHAPE, y0, y1, a0, a1, 0.045 - 0.008 * k, 0.03, 5, 2, 0.0, 20 + k, out, 0.12)
            sk.auto(verts, ["Spine", "Chest"], 8.0)
    # The thoracic horn: out of the crest in a chitin sleeve, then bone, curving forward and down over the nose horn.
    sk.rigid(K.tube_path(sk, THORAX_HORN[:3], [0.16, 0.12, 0.09], 12, 4, K.CHITIN, 0.85), "Chest")
    sk.rigid(K.tube_path(sk, THORAX_HORN[1:], [0.1, 0.075, 0.048], 10, 7, K.BONE, 0.85), "Chest")
    sk.rigid(sk.cone(THORAX_HORN[-1] + Vector((0, 0.02, 0.02)), THORAX_TIP, 0.046, 6, K.BONE, 0.85), "Chest")


def build_neck_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Neck: short and thick, deep under the shield's rim.
    pts = [Vector((0, -0.5, 0.74)), Vector((0, -0.6, 0.7)), Vector((0, -0.7, 0.67))]
    sk.auto(K.tube_path(sk, pts, [0.24, 0.2, 0.15], 14, 5, K.SINEW), ["Chest", "Neck", "Head"])
    # Skull (chitin; the underside is the roof of the mouth).
    rings = []
    n = 10
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in HEAD], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 16, 0.004, 3 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        if f.normal.z < -0.5 and f.calc_center_median().y < -0.84:
            f.material_index = K.MOUTH
    # The nose horn: a chitin sleeve at its root, then bone, curving forward and up.
    sk.rigid(K.tube_path(sk, NOSE_HORN[:3], [0.11, 0.095, 0.08], 12, 4, K.CHITIN, 0.95), "Head")
    sk.rigid(K.tube_path(sk, NOSE_HORN[1:], [0.085, 0.072, 0.056, 0.04], 10, 8, K.BONE, 0.95), "Head")
    sk.rigid(sk.cone(NOSE_HORN[-1] + Vector((0, 0.01, -0.03)), NOSE_TIP, 0.04, 6, K.BONE, 0.9), "Head")
    POS["nose_tip"] = NOSE_TIP.copy()
    # Eyes: two small pairs set deep in the sides of the skull, under the rim, each in a socket of chitin.
    for _side, s in K.SIDES:
        for x, y, z, r in ((0.13, -0.78, 0.7, 0.024), (0.16, -0.7, 0.71, 0.018)):
            eyes.rigid(eyes.sphere((s * x, y, z), r, 8, 4, scale=(0.9, 1.3, 0.8), rot=rz(-s * 25)), "Head")
            sk.rigid(
                sk.sphere((s * (x - 0.008), y, z + 0.008), r * 1.4, 8, 4, scale=(1.0, 1.3, 0.9), mi=K.CHITIN), "Head"
            )
    # Lower jaw: a blunt scoop; two short, thick mandibles curving in under the snout.
    rings = []
    jaw = [(-0.76, 0.56, 0.12, 0.02, 0.05), (-0.86, 0.545, 0.11, 0.02, 0.05), (-0.95, 0.53, 0.07, 0.015, 0.035)]
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
            Vector((s * 0.11, -0.8, 0.55)),
            Vector((s * 0.15, -0.92, 0.53)),
            Vector((s * 0.11, -1.02, 0.52)),
            Vector((s * 0.05, -1.06, 0.53)),
        ]
        sk.rigid(K.tube_path(sk, pts, [0.04, 0.034, 0.025, 0.012], 7, 7, K.BONE, 0.8), "Jaw")


def build_pad(sk: K.Skin, j: list, s: float, low: str, foot: str, claws: int) -> None:
    """A broad pad under the ankle, flat on the ground, with heavy hooked claws over its front."""
    w = j[2]
    fwd = (j[3] - j[2]) * Vector((1, 1, 0))
    fwd = fwd.normalized() if fwd.length > 1e-4 else Vector((0, -1, 0))
    layers = [
        (w.z + 0.04, 0.1, 0.1, 0.0),
        (w.z - 0.04, 0.13, 0.14, 0.03),
        (0.06, 0.15, 0.16, 0.05),
        (0.0, 0.14, 0.15, 0.05),
    ]
    rings = []
    for z, wx, wy, f in layers:
        c = Vector((w.x, w.y, z)) + fwd * f
        rings.append(rounded_ring(c, wx, wy, 14))
    verts = sk.loft(rings, K.CHITIN)
    for v in verts:
        if v.co.z > w.z:
            sk.auto([v], [low, foot])
        else:
            sk.rigid([v], foot)
    # Claws: thick, hooked down at the tips, fanned around the front.
    spread = 26 if claws == 3 else 20
    for k in range(claws):
        ang = math.radians(spread * (k - (claws - 1) / 2))
        d = Vector((fwd.x * math.cos(ang) - fwd.y * math.sin(ang), fwd.x * math.sin(ang) + fwd.y * math.cos(ang), 0))
        base = Vector((w.x, w.y, 0.08)) + fwd * 0.05 + d * 0.12
        knuck = base + d * 0.07 + Vector((0, 0, 0.0))
        tip = base + d * 0.13 + Vector((0, 0, -0.07))
        sk.rigid(K.tube_path(sk, [base, knuck, tip], [0.042, 0.034, 0.016], 7, 5, K.BONE, 0.8), foot)


def build_front_leg(sk: K.Skin, j: list, s: float, side: str) -> None:
    up, low, foot = (f"Front{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
    # Upper arm: a massive muscle out of the shoulder under the shield, a plate on its outside.
    top = j[0] + Vector((s * -0.08, 0.0, 0.08))
    mid = j[0].lerp(j[1], 0.5) + Vector((s * 0.02, 0.0, 0.0))
    sk.auto(K.tube_path(sk, [top, mid, j[1]], [0.18, 0.17, 0.15, 0.13], 12, 6, K.SINEW, 1.0, 0.006), ["Chest", up, low])
    out = Vector((s, -0.4, 0.2)).normalized()
    sk.rigid(K.limb_plate(sk, j[0].lerp(j[1], 0.3), j[0].lerp(j[1], 0.95), 0.15, -75, 75, 0.035, K.CHITIN, out), up)
    # Elbow: a heavy knob.
    sk.rigid(sk.sphere(j[1] + Vector((s * 0.02, 0.03, 0)), 0.12, 8, 4, mi=K.CHITIN), low)
    # Forearm: a thick pillar down to the pad, armored in front by two layered plates.
    mid = j[1].lerp(j[2], 0.5)
    sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.13, 0.135, 0.12], 12, 6, K.SINEW, 1.0, 0.005), [up, low, foot])
    fwd = Vector((s * 0.4, -1, 0.1)).normalized()
    sk.rigid(K.limb_plate(sk, j[1].lerp(j[2], 0.05), j[1].lerp(j[2], 0.6), 0.135, -85, 85, 0.035, K.CHITIN, fwd), low)
    sk.rigid(K.limb_plate(sk, j[1].lerp(j[2], 0.45), j[1].lerp(j[2], 1.0), 0.14, -80, 80, 0.035, K.CHITIN, fwd), low)
    build_pad(sk, j, s, low, foot, 3)


def build_hind_leg(sk: K.Skin, j: list, s: float, side: str) -> None:
    up, low, foot = (f"Hind{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
    # Haunch: thick, bare sinew (the soft rear), a small plate on the outside of the thigh.
    top = j[0] + Vector((s * -0.05, 0.03, 0.08))
    mid = j[0].lerp(j[1], 0.5) + Vector((0, 0.03, 0))
    sk.auto(K.tube_path(sk, [top, mid, j[1]], [0.2, 0.18, 0.15, 0.12], 12, 6, K.SINEW, 1.0, 0.006), ["Hips", up, low])
    out = Vector((s, 0.2, 0.3)).normalized()
    sk.rigid(K.limb_plate(sk, j[0].lerp(j[1], 0.3), j[0].lerp(j[1], 0.85), 0.15, -55, 55, 0.025, K.CHITIN, out), up)
    # Knee knob and the shin back down to the pad, a greave on its front.
    sk.rigid(sk.sphere(j[1] + Vector((0, -0.02, 0)), 0.11, 8, 4, mi=K.CHITIN), low)
    mid = j[1].lerp(j[2], 0.5)
    sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.12, 0.115, 0.11], 12, 6, K.SINEW, 1.0, 0.005), [up, low, foot])
    fwd = Vector((s * 0.4, -1, 0.3)).normalized()
    sk.rigid(K.limb_plate(sk, j[1].lerp(j[2], 0.1), j[1].lerp(j[2], 0.85), 0.12, -70, 70, 0.03, K.CHITIN, fwd), low)
    build_pad(sk, j, s, low, foot, 3)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk, glands)
    build_shield(sk)
    build_neck_head(sk, eyes)
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


def rest_pole(leg: str) -> Vector:
    """The side the knee of `leg` (e.g. "HindLeft") bends to at rest, in rest space."""
    hip_r, knee_r, ankle_r = RIG.head[f"{leg}UpperLeg"], RIG.head[f"{leg}LowerLeg"], RIG.head[f"{leg}Foot"]
    axis = (ankle_r - hip_r).normalized()
    off = knee_r - hip_r
    return (off - axis * off.dot(axis)).normalized()


def leg_ik(p: K.Pose, leg: str, ankle: Vector, foot_world: Matrix | None = I3, pole: Vector | None = None) -> None:
    """Bends leg so its ankle reaches `ankle` (world), the knee towards its rest side (or `pole`); the Foot gets the
    world rotation foot_world (None: it keeps its angle to the lower leg)."""
    up, low, foot = f"{leg}UpperLeg", f"{leg}LowerLeg", f"{leg}Foot"
    hip_r, knee_r, ankle_r = RIG.head[up], RIG.head[low], RIG.head[foot]
    wp = p.world(RIG.parent[up])
    if pole is None:
        pole = wp @ rest_pole(leg)
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


def plant(p: K.Pose, rows=("Front", "Hind")) -> None:
    """Keeps the feet of `rows` where they stand at rest (flat on the ground)."""
    for leg, pts, _parent in LEGS:
        if leg in rows:
            for side, s in K.SIDES:
                leg_ik(p, f"{leg}{side}", K.mirror(pts[2], s))


def idle(t: float) -> K.Pose:
    """Heavy, slow breathing (the soft back pumping), the head swinging low from side to side, now and then a scrape
    of the front (the trunk shifting forward and back on one shoulder)."""
    a = math.tau * t
    breath = math.sin(2 * a)
    scrape = max(0.0, math.sin(3 * a + 0.4)) ** 4
    p = K.Pose(RIG, (0.0, -0.025 * scrape, 0.015 * breath - 0.01 * scrape))
    p.set("Body", ry(2.0 * scrape) @ rx(1.5 * scrape))
    p.set("Hips", rx(1.5 * breath))
    p.set("Spine", rx(-1.0 * breath)).set("Chest", rx(-1.2 * breath))
    p.set("Neck", rz(12 * math.sin(a)) @ rx(7 + 2 * math.sin(2 * a + 0.6)))
    p.set("Head", rz(5 * math.sin(a - 0.6)) @ rx(3 + 2 * math.sin(4 * a + 1.0)))
    p.set("Jaw", rx(2 + 6 * max(0.0, math.sin(2 * a + 2.0)) ** 2))
    return p


def run(t: float) -> K.Pose:
    """The trunk's motion while it charges (legs at rest, the game steps them): a heavy gallop, the front and the
    rear rising and falling in turn once per stride, the whole weight leaning forward, the head low and the horn
    held steady at the front."""
    a = math.tau * t
    rock = math.sin(a)
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0.012 * math.sin(a + 0.5), -0.04 * math.cos(a), -0.04 + 0.035 * bob))
    p.set("Body", rx(3 + 4 * rock) @ rz(1.5 * math.sin(a + 1.0)))
    p.set("Hips", rx(-3 * math.sin(a + 0.8)))
    p.set("Spine", rx(-1.5 * math.sin(a + 0.4)))
    p.set("Chest", rx(1.0 * math.sin(a + 0.6)))
    p.set("Neck", rx(10 - 4 * rock))
    p.set("Head", rx(2 - 1.5 * math.sin(a + 0.6)))
    p.set("Jaw", rx(3))
    return p


ATTACK_FRAMES = 18  # 0.6 s
IMPACT_FRAME = 11  # the hook's peak: the horn up and forward (t = 11 / 18, about 61 % of the clip)


def attack(t: float) -> K.Pose:
    """The head drops low (to 0.4, the front dipping, the weight back), then hooks the horn up and forward with a
    lunge of the whole body (the impact at IMPACT_FRAME), holds a moment and settles back. The feet stay planted."""
    impact = IMPACT_FRAME / ATTACK_FRAMES
    d = K.smooth(t / 0.4)
    h = min(max((t - 0.4) / (impact - 0.4), 0.0), 1.0) ** 1.4  # accelerating into the hook
    r = K.smooth((t - 0.72) / 0.28)
    drop, hook = d * (1 - h), h * (1 - r)
    body = rx(7 * drop - 7 * hook)
    p = K.Pose(RIG, Vector((0, 0.05 * drop - 0.2 * hook, -0.07 * drop + 0.05 * hook)))
    p.set("Body", body)
    p.set("Spine", rx(3 * drop - 3 * hook))
    p.set("Chest", rx(3 * drop - 4 * hook))
    p.set("Neck", rx(22 * drop - 12 * hook))
    p.set("Head", rx(12 * drop - 6 * hook))
    p.set("Jaw", rx(4 * drop + 14 * hook))
    plant(p)
    return p


HIP_PIVOT = Vector((0, HIND[0].y, HIND[0].z))  # the front buckles around the hind hips
DIE_ROLL = 72  # degrees onto its left side
DIE_DROP = Vector((0.28, 0.0, -0.15))  # where the Body ends up, so it rests on the ground
# Where the ankles fold to, in rest space (left side): tucked up under the belly.
FOLD = {"Front": Vector((0.24, -0.48, 0.4)), "Hind": Vector((0.24, 0.4, 0.4))}


def die(t: float) -> K.Pose:
    """The front legs buckle (the chest drops onto them, to 0.35), then it rolls onto its left side (1.0), the head
    sagging, the jaw slack, all four legs folding up under the belly. The legs are solved like AlienLegs does it (the
    game switches it off on death)."""
    k = K.smooth(t / 0.35)
    f = K.smooth((t - 0.25) / 0.65)
    buckle = rx(10 * k * (1 - f) + 4 * f)
    body = ry(DIE_ROLL * f) @ buckle
    sag = pivot(buckle, HIP_PIVOT) + Vector((0, -0.05, -0.2)) * k  # the chest drops onto the buckled front legs
    p = K.Pose(RIG, sag * (1 - f) + DIE_DROP * f)
    p.set("Body", body)
    p.set("Neck", rx(10 * k + 8 * f) @ rz(-12 * f))
    p.set("Head", rx(8 * f) @ ry(-10 * f))
    p.set("Jaw", rx(22 * k))
    for leg, pts, parent in LEGS:
        for side, s in K.SIDES:
            name = f"{leg}{side}"
            rest = K.mirror(pts[2], s)
            if leg == "Front":  # buckles first: the ankles stay on the ground, the elbows give
                stand = rest + Vector((s * 0.04, -0.08, 0.0)) * k
                fold = posed_point(p, parent, K.mirror(FOLD[leg], s))
                ankle = stand.lerp(fold, f)
            else:
                ankle = rest.lerp(posed_point(p, parent, K.mirror(FOLD[leg], s)), f)
            leg_ik(p, name, ankle, None, p.world(parent) @ rest_pole(name))
            p.set(f"{name}Foot", rx(-50 * f))
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (24, run),
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
    lo, hi = bounds()
    print("BOUNDS rest", (lo, hi), "size", tuple(round(b - a, 3) for a, b in zip(lo, hi)))
    trunk = bone_verts(TRUNK_BONES)
    print("TOP (thoracic horn)", max(trunk, key=lambda v: v.z), "length (horn tip to rump)", round(hi[1] - lo[1], 3))
    print("BACK top (shield crest behind the horn)", max((v for v in trunk if v.y > -0.25), key=lambda v: v.z))
    gl = bpy.data.objects["Glands"].data.vertices
    print("GLANDS center", sum((v.co for v in gl), Vector()) / len(gl))
    print("NOSE TIP (Head)", POS["nose_tip"], "SHIELD FRONT (Chest)", POS["shield_front"])
    for leg, _pts, _parent in LEGS:
        for side, _s in K.SIDES:
            feet = bone_verts([f"{leg}{side}Foot"])
            print("SOLE", leg, side, round(min(v.z for v in feet), 4))
    for name, pose in (
        ("attack_drop", attack(0.4)),
        ("attack_impact", attack(IMPACT_FRAME / ATTACK_FRAMES)),
        ("run0", run(0.0)),
        ("run25", run(0.25)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        print("BOUNDS", name, bounds())
        if name == "attack_impact":
            print("NOSE TIP impact", posed_point(pose, "Head", NOSE_TIP))
        if name == "die":
            low = {g: round(min((v.z for v in bone_verts([g])), default=9), 3) for g, *_r in BONES}
            print("LOWEST die", {g: z for g, z in low.items() if z < 0.1})
    K.rest_pose(arm)


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.9, 1.3, 0))
    shots = []
    target = (0, -0.1, 0.7)
    K.rest_pose(arm)
    for view, zoom in (("iso", 0.48), ("hero", 0.62), ("back", 0.6), ("iso", 1.6)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((5.6, -0.1, 0.95)), (0, -0.1, 0.65), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((1.1, -3.4, 1.1)), (0, -0.8, 0.75), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    C.render_from(OUT / "wip" / f"{tag}_top.png", Vector((0.0, -0.1, 7.0)), (0, -0.1, 0.0), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_top.png")
    for name, pose in (
        ("idle", idle(0.3)),
        ("run", run(0.25)),
        ("attack_drop", attack(0.4)),
        ("attack_hit", attack(IMPACT_FRAME / ATTACK_FRAMES)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.62)
        shots.append(path)
    K.apply(arm, attack(IMPACT_FRAME / ATTACK_FRAMES))
    bpy.context.view_layer.update()
    C.render_from(OUT / "wip" / f"{tag}_attack_side.png", Vector((5.6, -0.4, 1.1)), (0, -0.3, 0.7), 50, 24, 512)
    shots.append(OUT / "wip" / f"{tag}_attack_side.png")
    K.apply(arm, die(1.0))
    bpy.context.view_layer.update()
    C.render(OUT / "wip" / f"{tag}_die_iso.png", view="iso", samples=24, size=512, target=target, zoom=0.48)
    shots.append(OUT / "wip" / f"{tag}_die_iso.png")
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
    if MODE == "pose":  # pose <clip> <t>: one frame of a clip from the front, the side, the iso camera and above
        clip, t = ARGV[1], float(ARGV[2])
        C.preview_scene(crystals=False, figure_location=(1.9, 1.3, 0))
        K.apply(arm, CLIPS[clip][1](t))
        bpy.context.view_layer.update()
        print("BOUNDS", clip, t, bounds())
        stem = f"pose_{clip}_{t:.2f}"
        shots = [OUT / "wip" / f"{stem}_{v}.png" for v in ("front", "side", "iso", "top")]
        C.render_from(shots[0], Vector((0.0, -6.0, 1.3)), (0, -0.3, 0.8), 50, 24, 512)
        C.render_from(shots[1], Vector((6.0, -0.2, 1.1)), (0, -0.2, 0.8), 50, 24, 512)
        C.render(shots[2], view="iso", samples=24, size=512, target=(0, -0.1, 0.7), zoom=0.5)
        C.render_from(shots[3], Vector((0.0, -0.1, 7.0)), (0, -0.1, 0.0), 50, 24, 512)
        C.contact_sheet(shots, OUT / "wip" / f"{stem}_sheet.png", cols=4, tile=384)
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "brute_procedural.blend")
        C.export_glb(OUT / "brute_draft.glb")


main()
