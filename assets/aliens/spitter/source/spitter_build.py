"""Spitter: a beetle-bodied alien on six legs with a swollen, glowing acid sac on its rear back, which it squeezes to
lob acid from its puckered mouth (see docs/design/aliens.md, Alien look), rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/spitter/source/spitter_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/spitter/source/spitter_build.py final      # renders + spitter_procedural.blend

Everything it writes goes to tmp/assets/spitter/; spitter_bake.py turns spitter_procedural.blend into the game asset.

Layout (Blender Z-up meters; the spitter faces -Y, its left is +X; the game turns the model by 180 degrees). Feet on
the ground at the origin, the origin under the middle of the body; carapace 0.7 m high, the sac rising to 1.0 m, head
to rump 1.3 m (the mandibles a little more), the legs splayed wide with the knees out to the sides.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (the abdomen) with the hind legs and
Sac (the acid sac: clips scale it to swell and squeeze), Spine with the mid legs, Chest with the front legs, Neck,
Head (the mouth it spits from), Jaw (the mandibles' base) with LeftMandible and RightMandible. Legs
(<Front|Mid|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (the femur rising out to a high knee, the
tibia down to the ankle, the Foot is the short tarsus with its claws), so the clips leave them at rest; only "Die"
folds them. Meshes: "Creature" (one skinned object: organic parts weighted to the nearest bones; plates, ribs,
mandibles and claws rigid), "Eyes" (constant emissive, two pairs of small beads) and "Glands" (constant emissive: the
acid sac, skinned to Sac, and the glow in the throat; the game flares it with the eyes).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: slow breathing, the sac swelling),
"Run" (loop: a heavy rolling trot of the trunk, the sac wobbling behind; the legs come from the game), "Attack" (once,
0.6 s: rears its front up while the sac loads, squeezes it and thrusts the head forward and up, the acid leaving the
mouth at frame 10 = 55 %) and "Die" (once: the legs buckle, it drops onto its belly, the sac sags to one side).
The clips key every bone's rotation, the Body's location and the Sac's scale (own bake, the kit's keys no scale).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "spitter"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Matrix, Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Spitter"
FPS = 30
GLAND_GLOW = 2.0  # the strongest glow of the hive (eyes 8 in the previews, the nest 5)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.48))
NECK = Vector((0, -0.42, 0.47))
SKULL = Vector((0, -0.5, 0.46))
SNOUT = Vector((0, -0.66, 0.43))
JAW = Vector((0, -0.6, 0.39))
SAC_BASE = Vector((0, 0.33, 0.5))
# The acid sac: an ellipsoid on the rear back, its lower part sunk into the abdomen.
SAC_C = Vector((0, 0.33, 0.7))
SAC_R = (0.215, 0.27, 0.3, 0.17)  # half-width, half-length, top, bottom
SAC_BANDS = (0.15, 0.27, 0.39, 0.51)  # y of the ribs pinching it
# The mouth: a puckered tube in the lower front of the head, pointing forward and a little down.
MOUTH_BASE = Vector((0, -0.635, 0.405))
MOUTH_DIR = Vector((0, -1, -0.22)).normalized()
MOUTH_TIP = MOUTH_BASE + MOUTH_DIR * 0.06  # where the acid leaves
# Leg joints per side (x for the left side): hip, knee, ankle, pad (the claws' base on the ground).
LEGS = {
    "Front": [
        Vector((0.16, -0.3, 0.42)),
        Vector((0.32, -0.42, 0.54)),
        Vector((0.4, -0.58, 0.09)),
        Vector((0.43, -0.635, 0.028)),
    ],
    "Mid": [
        Vector((0.2, -0.1, 0.41)),
        Vector((0.4, -0.11, 0.54)),
        Vector((0.49, -0.13, 0.09)),
        Vector((0.535, -0.14, 0.028)),
    ],
    "Hind": [
        Vector((0.19, 0.1, 0.41)),
        Vector((0.36, 0.23, 0.54)),
        Vector((0.44, 0.41, 0.09)),
        Vector((0.48, 0.47, 0.028)),
    ],
}
LEG_PARENT = {"Front": "Chest", "Mid": "Spine", "Hind": "Hips"}
MANDIBLE = [Vector((0.075, -0.62, 0.385)), Vector((0.105, -0.7, 0.375)), Vector((0.075, -0.78, 0.36))]
MANDIBLE_TIP = Vector((0.025, -0.81, 0.355))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, Vector((0, 0.45, 0.47)), "Body"),
    ("Spine", BODY, Vector((0, -0.2, 0.48)), "Body"),
    ("Chest", Vector((0, -0.2, 0.48)), NECK, "Spine"),
    ("Neck", NECK, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW, Vector((0, -0.72, 0.375)), "Head"),
    ("Sac", SAC_BASE, SAC_BASE + Vector((0, 0, 0.45)), "Hips"),
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


# --- mesh -------------------------------------------------------------------------------------------

# Trunk profile from the rump forward (rows evenly spaced in y): y, center z, half-width, top, bottom.
TRUNK = [
    (0.66, 0.43, 0.04, 0.035, 0.035),
    (0.55, 0.44, 0.15, 0.11, 0.1),
    (0.44, 0.46, 0.22, 0.16, 0.14),
    (0.33, 0.475, 0.26, 0.18, 0.16),
    (0.22, 0.48, 0.275, 0.19, 0.17),
    (0.11, 0.48, 0.275, 0.19, 0.17),
    (0.0, 0.48, 0.262, 0.185, 0.16),
    (-0.11, 0.48, 0.25, 0.18, 0.15),
    (-0.22, 0.48, 0.24, 0.18, 0.15),
    (-0.33, 0.475, 0.2, 0.15, 0.13),
    (-0.44, 0.47, 0.11, 0.08, 0.08),
]
# Skull from the back of the head to its blunt front: y, center z, half-width, top, bottom.
SKULL_PROFILE = [
    (-0.42, 0.47, 0.07, 0.06, 0.06),
    (-0.46, 0.468, 0.105, 0.085, 0.075),
    (-0.5, 0.463, 0.125, 0.098, 0.088),
    (-0.54, 0.458, 0.13, 0.1, 0.09),
    (-0.58, 0.452, 0.125, 0.092, 0.085),
    (-0.62, 0.443, 0.105, 0.075, 0.07),
    (-0.66, 0.433, 0.06, 0.045, 0.045),
]
TRUNK_SHAPE = K.Profile(TRUNK)
SKULL_SHAPE = K.Profile(SKULL_PROFILE)


def sac_shape(y: float) -> tuple:
    """Center, half-width, top and bottom of the sac's cross-section at y, pinched where the ribs wrap it."""
    cx, cy, cz = SAC_C
    w, ry_, top, bot = SAC_R
    u = min(max((y - cy) / ry_, -1.0), 1.0)
    e = math.sqrt(max(1.0 - u * u, 0.0)) ** 0.9
    pinch = 1.0 - sum(0.12 * math.exp(-(((y - b) / 0.028) ** 2)) for b in SAC_BANDS)
    swell = 1.0 + 0.1 * u  # fuller toward the rear, like a filled bladder
    return Vector((cx, y, cz + 0.035 * u)), w * e * pinch * swell, top * e * pinch * swell, bot * e


def sac_point(y: float, a: float, out: float = 0.0) -> Vector:
    """Point on the sac at y and angle a (0 = left side, 90 = top), pushed out by `out`."""
    c, w, top, bot = sac_shape(y)
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    x = math.copysign(abs(ca) ** 0.9, ca) * (w + out)
    z = math.copysign(abs(sa) ** 0.95, sa) * ((top if sa > 0 else bot) + out)
    return c + Vector((x, 0, z))


def loft_open(sk: K.Skin, rings: list, mi: int, cap_end: bool = False) -> list:
    """Tube through rings without caps (cap_end closes only the last ring)."""
    verts = sk.loft(rings, mi, caps=False)
    if cap_end:
        n = len(rings[-1])
        sk.bm.faces.new(verts[-n:]).normal_update()
    return verts


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: K.Skin) -> None:
    n = 18
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.006, i * 0.9))
    trunk = ["Hips", "Spine", "Chest", "Neck"]
    sk.auto(sk.loft(rings, K.SINEW), trunk)
    # Carapace over the front half: a domed shield over the thorax, overlapping a pair of wing cases (split down the
    # middle like a beetle's) whose rear edges tuck under the front of the sac.
    sk.auto(K.shell(sk, TRUNK_SHAPE, -0.47, -0.06, 2, 178, 0.008, 0.045, K.CHITIN, 12, 4, 0.03), trunk, 8.0)
    for a0, a1 in ((-6, 84), (96, 186)):
        sk.auto(K.shell(sk, TRUNK_SHAPE, -0.14, 0.17, a0, a1, 0.012, 0.034, K.CHITIN, 6, 4, 0.03), trunk, 8.0)
    # Abdomen under the sac: overlapping segments wrapping the flanks and the belly.
    for y0, y1 in ((0.1, 0.25), (0.22, 0.37), (0.34, 0.49), (0.46, 0.6), (0.57, 0.69)):
        sk.rigid(K.shell(sk, TRUNK_SHAPE, y0, y1, 160, 380, 0.006, 0.02, K.CHITIN, 10, 2, 0.01), "Hips")
    # Thorax: a breast plate between the leg sockets and side plates above them.
    sk.auto(K.shell(sk, TRUNK_SHAPE, -0.42, 0.12, 240, 300, 0.006, 0.018, K.CHITIN, 4, 4, 0.0), trunk, 8.0)
    for _side, s in K.SIDES:
        a0, a1 = (-8, 14) if s > 0 else (166, 188)
        sk.auto(K.shell(sk, TRUNK_SHAPE, -0.38, 0.06, a0, a1, 0.01, 0.018, K.CHITIN, 2, 4, 0.006), trunk, 8.0)


def sac_shell(sk: K.Skin, y0: float, y1: float, a0, a1, out: float, thick: float, nu: int, nv: int) -> list:
    """Slab hugging the sac between y0..y1 and angles a0(v)..a1(v) (functions of v = 0..1 along y)."""
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
            row_t.append(sk.bm.verts.new(sac_point(y, a, out + thick * edge)))
            row_b.append(sk.bm.verts.new(sac_point(y, a, out)))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return K.close_grid(sk, top_rows, bot_rows, K.SINEW)


def cup_edge(v: float) -> float:
    """Upper edge of the fleshy cup around the sac (angle above its side at v = 0..1 along it), scalloped."""
    return 8 + 16 * abs(math.sin(math.pi * v * 4.4 + 0.3)) * math.sin(math.pi * v) ** 0.5


def build_sac(sk: K.Skin, glands: K.Skin) -> None:
    _w, ry_, _top, _bot = SAC_R
    y0, y1 = SAC_C.y - ry_, SAC_C.y + ry_
    rings = []
    n = 20
    for i in range(1, n):
        th = math.pi * i / n
        y = SAC_C.y - ry_ * math.cos(th)
        c, sw, top, bot = sac_shape(y)
        rings.append(K.section(c, Vector((0, -1, 0)), sw, top, bot, 18, 0.014, i * 1.3))
    glands.rigid(glands.loft(rings, 0), "Sac")
    # A fleshy cup it bulges out of: sinew over the lower flanks, its upper edge scalloped between the ribs.
    for lo, hi in ((lambda v: -60.0, cup_edge), (lambda v: 180 - cup_edge(v), lambda v: 240.0)):
        sk.rigid(sac_shell(sk, y0 + 0.015, y1 - 0.01, lo, hi, -0.002, 0.016, 5, 10), "Sac")
    # Dark chitin ribs wrapping over it in the pinches, thickest over the top, sunk into the abdomen at both ends.
    for k, yb in enumerate(SAC_BANDS):
        pts = [sac_point(yb + 0.01 * math.sin(math.radians(a) * 2 + k), a, 0.004) for a in range(-50, 231, 28)]
        radii = [0.012, 0.016, 0.02, 0.024, 0.026, 0.024, 0.02, 0.016, 0.012]
        sk.rigid(K.tube_path(sk, pts, radii, 6, 10, K.CHITIN, 1.5, 0.0, Vector((0, 1, 0))), "Sac")
        # A knob where each rib crosses the top, like a vertebra.
        sk.rigid(sk.sphere(sac_point(yb, 90, 0.018), 0.03, 8, 4, scale=(1.3, 1.0, 0.6), mi=K.CHITIN), "Sac")
    # Dark veins climbing from the cup over the lobes.
    for k, (y, a, dy) in enumerate(
        ((0.1, 20, 0.02), (0.21, 18, -0.015), (0.33, 22, 0.012), (0.45, 18, -0.02), (0.56, 24, 0.015))
    ):
        for _side, s in K.SIDES:
            if (k + (s > 0)) % 2:
                continue
            ang = [a, a + 22, a + 44, a + 60]
            pts = [
                sac_point(y + dy * t * (1 if s > 0 else -1), b if s > 0 else 180 - b, 0.002)
                for t, b in zip((0, 0.4, 0.8, 1), ang)
            ]
            sk.rigid(K.tube_path(sk, pts, [0.012, 0.01, 0.008, 0.006], 5, 5, K.SINEW), "Sac")


def build_neck_head(sk: K.Skin, eyes: K.Skin, glands: K.Skin) -> None:
    # Short neck from under the shield into the back of the head.
    pts = [Vector((0, -0.36, 0.47)), Vector((0, -0.42, 0.468)), Vector((0, -0.47, 0.465))]
    sk.auto(K.tube_path(sk, pts, [0.11, 0.095, 0.085], 14, 4, K.SINEW), ["Chest", "Neck", "Head"])
    # Blunt, armored head.
    rings = []
    n = 10
    for i in range(n + 1):
        c, w, top, bot = SKULL_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.003, 3 + i))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    # A brow plate over the eyes and the front, its edge lifting off.
    sk.rigid(K.shell(sk, SKULL_SHAPE, -0.47, -0.63, 20, 160, 0.006, 0.018, K.CHITIN, 8, 3, 0.008), "Head")
    # Puckered mouth: a fleshy ring of lips around the throat.
    rings = []
    for o, r in ((0.0, 0.05), (0.03, 0.048), (0.05, 0.043), (0.06, 0.034), (0.055, 0.024), (0.03, 0.018)):
        rings.append(K.section(MOUTH_BASE + MOUTH_DIR * o, MOUTH_DIR, r, r, r, 12, 0.004, o * 50))
    sk.rigid(loft_open(sk, rings[:4], K.SINEW), "Head")
    sk.rigid(loft_open(sk, rings[3:], K.MOUTH), "Head")
    glands.rigid(glands.sphere(MOUTH_BASE + MOUTH_DIR * 0.036, 0.022, 8, 4), "Head")
    # Mandibles: thick curved hooks closing in front of the mouth, two teeth on the inner edge.
    for side, s in K.SIDES:
        bone = f"{side}Mandible"
        pts = [K.mirror(p, s) for p in MANDIBLE] + [K.mirror(MANDIBLE_TIP, s)]
        sk.rigid(K.tube_path(sk, pts, [0.03, 0.028, 0.02, 0.006], 8, 8, K.BONE, 0.65), bone)
        for t in (0.45, 0.7):
            base = K.path_point(pts, t)
            inward = Vector((-s, -0.3, 0)).normalized()
            sk.rigid(sk.cone(base, base + inward * 0.03, 0.01, 4, K.BONE, 0.6), bone)
        # Socket of the mandible in the head.
        sk.rigid(sk.sphere(K.mirror(MANDIBLE[0], s), 0.032, 8, 4, mi=K.CHITIN), "Head")
        # Eyes: two pairs of small glowing beads on the sides of the head.
        for y, a, r in ((-0.575, 48, 0.02), (-0.605, 28, 0.014)):
            p = SKULL_SHAPE.surface(y, a if s > 0 else 180 - a, -0.004)
            eyes.rigid(eyes.sphere(p, r, 8, 4), "Head")


def build_legs(sk: K.Skin) -> None:
    for leg, pts in LEGS.items():
        body = LEG_PARENT[leg]
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            out = Vector((s, 0, 0))
            # Coxa: a fleshy socket where the leg leaves the body.
            sk.auto(sk.sphere(j[0] + out * 0.03, 0.085, 8, 5, scale=(1.0, 1.0, 0.85), mi=K.SINEW), [body, up])
            # Femur: a thick chitin segment rising out to the high knee, a ridge plate on top.
            mid = j[0].lerp(j[1], 0.5) + Vector((0, 0, 0.025))
            femur = K.tube_path(sk, [j[0], mid, j[1]], [0.078, 0.072, 0.054], 8, 6, K.CHITIN, 1.0, 0.003)
            sk.auto(femur, [body, up, low])
            a, b = j[0].lerp(j[1], 0.3), j[1].lerp(j[0], 0.12)
            sk.rigid(K.limb_plate(sk, a, b, 0.068, -60, 60, 0.016, K.CHITIN, Vector((s * 0.3, 0, 1))), up)
            # Knee: a chitin cap over the joint.
            cap = j[1] + Vector((s * 0.012, 0, 0.016))
            sk.rigid(sk.sphere(cap, 0.058, 8, 4, scale=(1.1, 1.1, 0.8), mi=K.CHITIN), low)
            # Tibia: down to the ankle, two spurs on its inner side.
            mid = j[1].lerp(j[2], 0.5) + out * 0.015
            sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.054, 0.044, 0.032], 8, 6, K.CHITIN), [up, low, foot])
            inner = Vector((j[0].x - j[1].x, j[0].y - j[1].y, 0)).normalized()
            for t in (0.4, 0.7):
                base = j[1].lerp(j[2], t)
                tip = base + (inner * 0.6 + Vector((0, 0, -0.5))).normalized() * 0.055
                sk.rigid(sk.cone(base, tip, 0.014, 4, K.BONE), low)
            # Tarsus to the pad, two hooked claws gripping the ground.
            tarsus = K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.032, 0.028, 0.03], 6, 3, K.SINEW)
            sk.auto(tarsus, [low, foot])
            sk.rigid(sk.sphere(j[3], 0.034, 8, 4, scale=(1.1, 1.2, 0.8), mi=K.CHITIN), foot)
            fwd = Vector((j[3].x - j[0].x, j[3].y - j[0].y, 0)).normalized()
            for k in (-1, 1):
                d = (fwd + Vector((-fwd.y, fwd.x, 0)) * 0.45 * k).normalized()
                tip = j[3] + d * 0.06 + Vector((0, 0, -0.028))
                sk.rigid(sk.cone(j[3] + Vector((0, 0, 0.004)), tip, 0.015, 5, K.BONE), foot)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk)
    build_sac(sk, glands)
    build_neck_head(sk, eyes, glands)
    build_legs(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


class Pose(K.Pose):
    """The kit's pose plus a scale per bone (the sac swelling and squeezing), as (width, height, length) in the
    bone's axes: for Sac (pointing up) x, z and y of the world."""

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


def mandibles(p: Pose, spread: float) -> None:
    for side, s in K.SIDES:
        p.set(f"{side}Mandible", rz(s * spread))


def idle(t: float) -> Pose:
    """Slow breathing: the sac swells as the trunk rises, the head turns a little, the mandibles work."""
    a = math.tau * t
    breath = math.sin(a)
    p = Pose(RIG, (0, 0, 0.008 * breath))
    p.set("Body", rx(-1.0 * breath))
    p.set("Chest", rx(1.0 * breath))
    p.set("Neck", rx(2 * math.sin(a + 0.6)) @ rz(7 * math.sin(a + 1.0)))
    p.set("Head", rx(-3 + 3 * math.sin(a + 1.2)) @ rz(-3 * math.sin(a + 1.0)))
    p.set("Jaw", rx(-2 * max(0.0, math.sin(a * 3))))
    mandibles(p, 6 + 6 * max(0.0, math.sin(a * 3 + 0.5)))
    swell = 1.0 + 0.04 * math.sin(a - 0.5)
    p.grow("Sac", swell, 1.0 + 0.055 * math.sin(a - 0.5), swell)
    return p


def run(t: float) -> Pose:
    """A heavy, rolling trot (legs at rest, the game steps them): two bobs per stride, the trunk rolling from side
    to side, the sac lagging behind and wobbling, the head low and steady."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = Pose(RIG, (0, 0, -0.025 + 0.022 * bob))
    p.set("Body", rx(2.5 * math.sin(2 * a + 0.4)) @ ry(5 * math.sin(a)) @ rz(2 * math.sin(a)))
    p.set("Hips", ry(-2 * math.sin(a - 0.6)) @ rz(-3 * math.sin(a - 0.5)))
    p.set("Chest", rz(-2 * math.sin(a)))
    p.set("Neck", rx(6 + 2 * math.sin(2 * a)) @ rz(-3 * math.sin(a)))
    p.set("Head", rx(2 - 3 * math.sin(2 * a)))
    mandibles(p, 4)
    lag = 2 * a - 1.2
    p.set("Sac", rx(4 * math.sin(lag)) @ ry(-6 * math.sin(a - 1.0)))
    p.grow("Sac", 1.0 + 0.03 * math.sin(lag + 1.0), 1.0 - 0.06 * math.sin(lag), 1.0 + 0.03 * math.sin(lag + 1.0))
    return p


ATTACK_FRAMES = 18
LAUNCH = 10 / ATTACK_FRAMES  # the acid leaves the mouth here (frame 10, 55 %)


def attack(t: float) -> Pose:
    """The spit (0.6 s): rears its front up and loads the sac (to 0.45), squeezes it and thrusts the head forward and
    up (the launch at 0.55), then settles."""
    rear = K.smooth(t / 0.45) * (1 - K.smooth((t - 0.65) / 0.35))
    load = K.smooth((t - 0.1) / 0.35) * (1 - K.smooth((t - 0.45) / 0.1))
    thrust = K.smooth((t - 0.42) / 0.13) * (1 - K.smooth((t - 0.62) / 0.38))
    squeeze = K.smooth((t - 0.45) / 0.1) * (1 - K.smooth((t - 0.6) / 0.4))
    p = Pose(RIG, (0, 0.06 * rear - 0.07 * thrust, 0.08 * rear))
    p.set("Body", rx(-18 * rear + 4 * thrust))
    p.set("Hips", rx(6 * rear))
    p.set("Chest", rx(-6 * rear))
    p.set("Neck", rx(-8 * rear - 14 * thrust))
    p.set("Head", rx(-6 * rear - 12 * thrust))
    p.set("Jaw", rx(-10 * thrust))
    mandibles(p, 6 + 22 * max(rear * 0.4, thrust))
    p.set("Sac", rx(4 * load - 8 * squeeze))
    w = 1.0 + 0.1 * load - 0.14 * squeeze
    p.grow("Sac", w, 1.0 + 0.12 * load - 0.22 * squeeze, w)
    return p


def lift(leg: str, s: float, deg: float) -> Matrix:
    """Rotation raising a leg's outer end by deg (about the horizontal axis across the leg)."""
    hip, pad = K.mirror(LEGS[leg][0], s), K.mirror(LEGS[leg][3], s)
    h = Vector((pad.x - hip.x, pad.y - hip.y, 0)).normalized()
    return Matrix.Rotation(math.radians(-deg), 3, K.UP.cross(h))


def die(t: float) -> Pose:
    """The legs buckle (to 0.35) and splay out flat, it drops onto its belly (0.6), the head droops onto the ground
    and the sac sags to one side."""
    k = K.smooth(t / 0.35)
    f = K.smooth((t - 0.15) / 0.5)
    sag = K.smooth((t - 0.3) / 0.7)
    p = Pose(RIG, (0.01 * f, 0.0, -0.05 * k - 0.23 * f))
    p.set("Body", ry(4 * f) @ rx(3 * f))
    p.set("Hips", rx(-3 * f))
    p.set("Neck", rx(4 * f) @ rz(10 * f))
    p.set("Head", rx(-4 * f))
    p.set("Jaw", rx(6 * f))
    mandibles(p, 28 * f)
    p.set("Sac", ry(14 * sag) @ rx(6 * sag))
    p.grow("Sac", 1.0 + 0.12 * sag, 1.0 - 0.3 * sag, 1.0 + 0.05 * sag)
    for side, s in K.SIDES:
        for leg, amp in (("Front", 1.1), ("Mid", 1.0), ("Hind", 0.9)):
            amp *= 1.12 if s > 0 else 1.0  # the body rolls onto its left side
            p.set(f"{leg}{side}UpperLeg", lift(leg, s, 12 * k * (1 - f) - 8 * f * amp))
            p.set(f"{leg}{side}LowerLeg", lift(leg, s, -18 * k * (1 - f) + 66 * f * amp))
            p.set(f"{leg}{side}Foot", lift(leg, s, -10 * k - 12 * f))
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (20, run),
    "Attack": (ATTACK_FRAMES, attack),
    "Die": (36, die),
}

# --- report -------------------------------------------------------------------------------------------


def posed_point(arm: bpy.types.Object, bone: str, p: Vector) -> Vector:
    pb = arm.pose.bones[bone]
    return arm.matrix_world @ pb.matrix @ arm.data.bones[bone].matrix_local.inverted() @ p


def report(arm: bpy.types.Object) -> None:
    rest_pose(arm)
    print("POINT mouth rest", tuple(round(x, 3) for x in posed_point(arm, "Head", MOUTH_TIP)))
    print("POINT mouth dir rest", tuple(round(x, 3) for x in MOUTH_DIR))
    print("POINT sac center rest", tuple(round(x, 3) for x in SAC_C))
    apply(arm, attack(LAUNCH))
    bpy.context.view_layer.update()
    m = posed_point(arm, "Head", MOUTH_TIP)
    d = posed_point(arm, "Head", MOUTH_TIP + MOUTH_DIR) - m
    print("POINT mouth launch", tuple(round(x, 3) for x in m), "dir", tuple(round(x, 3) for x in d.normalized()))
    print("POINT sac center launch", tuple(round(x, 3) for x in posed_point(arm, "Sac", SAC_C)))
    for name, pose in (("die", die(1.0)), ("idle", idle(0.25))):
        apply(arm, pose)
        bpy.context.view_layer.update()
        print("POINT", name, "stats", C.stats(), "lowest", lowest_parts())
    rest_pose(arm)


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


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.6, 1.2, 0))
    shots = []
    target = (0, 0, 0.55)
    rest_pose(arm)
    for view, zoom in (("iso", 0.3), ("hero", 0.36), ("back", 0.4), ("iso", 1.4)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((3.4, -0.05, 0.6)), (0, 0.0, 0.5), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.8, -1.7, 0.85)), (0, -0.6, 0.45), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    for name, pose in (
        ("idle", idle(0.25)),
        ("run", run(0.25)),
        ("attack4", attack(0.42)),
        ("attack55", attack(LAUNCH)),
        ("die", die(1.0)),
    ):
        apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.36)
        shots.append(path)
    # The death pose from the side, to check it lies on the ground.
    path = OUT / "wip" / f"{tag}_die_side.png"
    C.render_from(path, Vector((3.4, -0.05, 0.4)), (0, 0.0, 0.2), 50, 24, 512)
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
    if MODE != "stats":
        preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "spitter_procedural.blend")
        C.export_glb(OUT / "spitter_draft.glb")


main()
