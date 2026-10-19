"""Swarmer: a lean, dog-sized alien runner on four clawed legs with a long toothed jaw and two scythe-like bone
blades rising from its back (concept: swarmer_v1..v4), rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/swarmer/source/swarmer_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/swarmer/source/swarmer_build.py final      # renders + swarmer_procedural.blend

Everything it writes goes to tmp/assets/swarmer/; swarmer_bake.py turns swarmer_procedural.blend into the game asset.

Layout (Blender Z-up meters; the swarmer faces -Y, its left is +X; glTF turns -Y into Godot's +Z, so the game turns
the model by 180 degrees to face the alien's -Z). Feet on the ground at the origin, the origin under the middle of
the body; back 0.72 m high, the blades reach 1.5 m, nose to rump 1.5 m plus a 0.9 m tail.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the pelvis) with the tail
(Tail1..3) and the hind legs, Spine, Chest with the front legs and the blades (<Side>Scythe, <Side>ScytheBlade),
Neck, Head, Jaw. Legs (<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (two bones reaching
the ankle = the Foot bone's head, the Foot keeps its angle to the body), so the clips leave them at rest; only "Die"
folds them. Front elbows bend back, hind knees forward (digitigrade hind legs: the Foot is the long metatarsal).
Meshes: "Creature" (one skinned object, organic parts weighted to the nearest bones, chitin plates, teeth, claws and
blades rigid) and "Eyes" (constant emissive; the game shows the facing with them).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop), "Run" (loop, the body's motion
while running: spine flex, head low, tail streaming; the legs come from the game), "Attack" (once: rears back, then
snaps forward with the jaw open and the blades striking) and "Die" (once: legs buckle, it falls on its side).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "swarmer"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Swarmer"
FPS = 30

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.66))
PELVIS = Vector((0, 0.44, 0.66))
WITHERS = Vector((0, -0.42, 0.7))
SKULL = Vector((0, -0.6, 0.72))
JAW_PIVOT = Vector((0, -0.63, 0.665))
SNOUT = Vector((0, -1.02, 0.64))
TAIL = [PELVIS, Vector((0, 0.76, 0.69)), Vector((0, 1.05, 0.77)), Vector((0, 1.32, 0.9))]
# Leg joints per side (x for the left side): hip/shoulder, knee/elbow, ankle, ball of the foot, toe tips.
FRONT = [
    Vector((0.13, -0.26, 0.6)),
    Vector((0.145, -0.15, 0.36)),
    Vector((0.14, -0.27, 0.11)),
    Vector((0.14, -0.33, 0.035)),
    Vector((0.14, -0.42, 0.0)),
]
HIND = [
    Vector((0.125, 0.42, 0.6)),
    Vector((0.145, 0.22, 0.39)),
    Vector((0.14, 0.5, 0.2)),
    Vector((0.14, 0.42, 0.035)),
    Vector((0.14, 0.32, 0.0)),
]
SCYTHE = [Vector((0.1, -0.18, 0.8)), Vector((0.19, 0.2, 1.1)), Vector((0.24, -0.3, 1.42))]


BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, Vector((0, -0.2, 0.67)), "Body"),
    ("Chest", Vector((0, -0.2, 0.67)), WITHERS, "Spine"),
    ("Neck", WITHERS, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -1.0, 0.585)), "Head"),
    ("Tail1", TAIL[0], TAIL[1], "Hips"),
    ("Tail2", TAIL[1], TAIL[2], "Tail1"),
    ("Tail3", TAIL[2], TAIL[3], "Tail2"),
]
for _side, _s in K.SIDES:
    BONES += [
        (f"{_side}Scythe", K.mirror(SCYTHE[0], _s), K.mirror(SCYTHE[1], _s), "Chest"),
        (f"{_side}ScytheBlade", K.mirror(SCYTHE[1], _s), K.mirror(SCYTHE[2], _s), f"{_side}Scythe"),
    ]
    for _leg, _pts, _parent in (("Front", FRONT, "Chest"), ("Hind", HIND, "Hips")):
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), _parent),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)


# --- mesh -------------------------------------------------------------------------------------------


# Body profile along the spine, from the rump forward: y, center z, half-width, top, bottom.
TRUNK = [
    (0.62, 0.64, 0.06, 0.06, 0.06),
    (0.54, 0.665, 0.13, 0.09, 0.11),
    (0.4, 0.68, 0.155, 0.1, 0.14),
    (0.25, 0.67, 0.14, 0.095, 0.12),
    (0.08, 0.66, 0.12, 0.085, 0.11),
    (-0.08, 0.665, 0.15, 0.1, 0.19),
    (-0.22, 0.67, 0.175, 0.11, 0.245),
    (-0.34, 0.685, 0.16, 0.105, 0.2),
    (-0.44, 0.705, 0.115, 0.09, 0.11),
    (-0.54, 0.715, 0.085, 0.07, 0.075),
    (-0.6, 0.72, 0.08, 0.065, 0.07),
]
# Skull from the back of the head to the snout: y, center z, half-width, top, bottom.
SKULL_PROFILE = [
    (-0.55, 0.735, 0.05, 0.04, 0.03),
    (-0.6, 0.74, 0.075, 0.065, 0.035),
    (-0.68, 0.735, 0.085, 0.07, 0.04),
    (-0.78, 0.715, 0.068, 0.05, 0.035),
    (-0.88, 0.69, 0.052, 0.04, 0.03),
    (-0.97, 0.665, 0.04, 0.032, 0.025),
    (-1.03, 0.65, 0.022, 0.02, 0.016),
]
JAW_PROFILE = [
    (-0.6, 0.66, 0.055, 0.012, 0.03),
    (-0.7, 0.648, 0.06, 0.012, 0.035),
    (-0.82, 0.632, 0.048, 0.01, 0.03),
    (-0.93, 0.615, 0.036, 0.01, 0.024),
    (-1.0, 0.603, 0.02, 0.008, 0.014),
]

TRUNK_SHAPE = K.Profile(TRUNK)


# --- parts ------------------------------------------------------------------------------------------


def build_trunk(sk: K.Skin) -> None:
    n = 22
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 18, 0.006, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), ["Hips", "Spine", "Chest", "Neck"])
    # Ribs on the flanks: thin ridges curving down over the chest.
    for side, s in K.SIDES:
        for y in (-0.3, -0.24, -0.18, -0.12, -0.06, 0.0):
            pts = [TRUNK_SHAPE.surface(y + 0.012 * k, 25 - 24 * k if s > 0 else 155 + 24 * k, 0.004) for k in range(5)]
            sk.auto(K.tube_path(sk, pts, [0.012, 0.013, 0.012, 0.01, 0.006], 6, 6, K.SINEW), ["Spine", "Chest"])
    # Dorsal plates: overlapping shields from the neck to the rump, the rear edge of each lifting off.
    ys = [-0.6, -0.5, -0.4, -0.29, -0.18, -0.07, 0.04, 0.15, 0.26, 0.37, 0.48]
    for i, (y0, y1) in enumerate(itertools.pairwise(ys)):
        width = 38 + 14 * math.sin(math.pi * i / (len(ys) - 2))
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0 - 0.02, y1 + 0.035, 90 - width, 90 + width, 0.006, 0.02, K.CHITIN, 6, 3, 0.015),
            ["Hips", "Spine", "Chest", "Neck"],
            8.0,
        )
    # Side plates over the ribs and the haunches.
    for side, s in K.SIDES:
        a0, a1 = (5, 40) if s > 0 else (140, 175)
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, -0.32, -0.12, a0 - 30, a1 - 20, 0.012, 0.016, K.CHITIN, 5, 3, 0.012),
            ["Spine", "Chest"],
            8.0,
        )
        a0, a1 = (-30, 45) if s > 0 else (135, 210)
        sk.rigid(K.shell(sk, TRUNK_SHAPE, 0.3, 0.52, a0, a1, 0.008, 0.02, K.CHITIN, 6, 3, 0.01), "Hips")


def build_neck_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Neck: from the withers into the back of the skull.
    pts = [Vector((0, -0.48, 0.705)), Vector((0, -0.54, 0.715)), Vector((0, -0.6, 0.72))]
    sk.auto(K.tube_path(sk, pts, [0.095, 0.08, 0.065], 14, 4, K.SINEW), ["Chest", "Neck", "Head"])
    # Skull (the underside is the roof of the mouth).
    rings = []
    n = 12
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in SKULL_PROFILE], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 16, 0.003, 3 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    _mouth_faces(sk, verts, below=True)
    # Lower jaw.
    rings = []
    for i in range(9):
        y, z, w, top, bot = K.catmull([list(r) for r in JAW_PROFILE], i / 8)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 14, 0.002, 9 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Jaw")
    _mouth_faces(sk, verts, below=False)
    # Teeth along both jaws (longer fangs in front), bone colored.
    rnd = random.Random(7)
    for side, s in K.SIDES:
        for k in range(9):
            t = k / 8
            y = -0.66 - 0.33 * t
            _y, z, w, _top, bot = K.catmull([list(r) for r in SKULL_PROFILE], (-0.55 - y) / 0.48)
            length = 0.03 + 0.02 * (1 - abs(t - 0.75) * 2) + rnd.uniform(-0.005, 0.008)
            base = Vector((s * w * 0.8, y, z - bot * 0.75))
            sk.rigid(sk.cone(base, base + Vector((s * 0.004, -0.006, -length)), 0.008, 5, K.BONE), "Head")
            _y, zj, wj, topj, _b = K.catmull([list(r) for r in JAW_PROFILE], (-0.6 - y) / 0.4)
            if -1.0 < y < -0.62:
                base = Vector((s * wj * 0.8, y - 0.01, zj + topj * 0.5))
                sk.rigid(sk.cone(base, base + Vector((s * 0.003, -0.004, length * 0.8)), 0.007, 5, K.BONE), "Jaw")
    # Brow ridges over the eyes and two horns sweeping back from the skull.
    for side, s in K.SIDES:
        sk.rigid(
            sk.sphere(
                (s * 0.06, -0.7, 0.78), 0.04, 10, 5, scale=(0.9, 2.0, 0.45), rot=ry(s * 25) @ rx(-8), mi=K.CHITIN
            ),
            "Head",
        )
        horn = [Vector((s * 0.045, -0.6, 0.78)), Vector((s * 0.06, -0.52, 0.83)), Vector((s * 0.07, -0.42, 0.86))]
        sk.rigid(K.tube_path(sk, horn, [0.025, 0.016, 0.004], 6, 5, K.BONE), "Head")
        # Eyes: slanted glowing slits on the sides of the skull.
        eyes.rigid(
            eyes.sphere((s * 0.068, -0.735, 0.752), 0.022, 10, 5, scale=(0.5, 1.4, 0.6), rot=rz(s * 20) @ rx(-12)),
            "Head",
        )


def _mouth_faces(sk: K.Skin, verts: list, below: bool) -> None:
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        n = f.normal
        if ((n.z < -0.6) if below else (n.z > 0.6)) and f.calc_center_median().y < -0.62:
            f.material_index = K.MOUTH


def build_tail(sk: K.Skin) -> None:
    pts = TAIL + [Vector((0, 1.42, 0.98))]
    sk.auto(
        K.tube_path(sk, pts, [0.055, 0.04, 0.026, 0.014, 0.006], 10, 18, K.SINEW), ["Hips", "Tail1", "Tail2", "Tail3"]
    )
    # Chitin rings along the tail and a spike at the tip.
    for k in range(10):
        t = 0.08 + 0.8 * k / 9
        c = K.path_point(pts, t)
        d = K.path_point(pts, t + 0.02) - K.path_point(pts, t - 0.02)
        r = K.catmull([[x] for x in [0.055, 0.04, 0.026, 0.014, 0.006]], t)[0]
        bone = "Tail1" if t < 0.33 else "Tail2" if t < 0.66 else "Tail3"
        rings = [
            K.section(c + d.normalized() * o, d, r + 0.006 + o * 0.15, r + 0.008, r + 0.002, 10)
            for o in (-0.012, 0.012)
        ]
        sk.rigid(sk.loft(rings, K.CHITIN), bone)
    end = K.path_point(pts, 1.0)
    sk.rigid(sk.cone(end - Vector((0, 0.03, 0.02)), end + Vector((0, 0.08, 0.03)), 0.012, 6, K.BONE), "Tail3")


def build_legs(sk: K.Skin) -> None:
    for leg, pts in (("Front", FRONT), ("Hind", HIND)):
        hind = leg == "Hind"
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            body = "Hips" if hind else "Chest"
            # Upper leg: thick haunch / shoulder muscle, into the body.
            top = j[0] + Vector((s * -0.03, 0.0, 0.07))
            radii = [0.115, 0.12, 0.085, 0.055] if hind else [0.1, 0.095, 0.068, 0.048]
            mid = j[0].lerp(j[1], 0.45) + (Vector((0, 0.03, 0)) if hind else Vector((0, -0.02, 0)))
            sk.auto(K.tube_path(sk, [top, mid, j[1]], radii, 12, 6, K.SINEW, 1.0, 0.004), [body, up, low])
            # Lower leg: lean, a chitin greave on the front (hind: the shin points back).
            mid = j[1].lerp(j[2], 0.5)
            sk.auto(
                K.tube_path(
                    sk, [j[1], mid, j[2]], [0.055, 0.04, 0.032] if hind else [0.052, 0.038, 0.032], 10, 6, K.SINEW
                ),
                [up, low, foot],
            )
            facing = Vector((0, -1, 0.2)) if hind else Vector((0, 1, 0.1))
            sk.rigid(
                K.limb_plate(
                    sk,
                    j[1].lerp(j[2], 0.15),
                    j[1].lerp(j[2], 0.8),
                    0.04,
                    -70,
                    70,
                    0.014,
                    K.CHITIN,
                    -facing if hind else facing,
                ),
                low,
            )
            # Knee / elbow knob.
            sk.rigid(
                sk.sphere(j[1] + (Vector((0, -0.015, 0)) if hind else Vector((0, 0.02, 0))), 0.035, 10, 5, mi=K.CHITIN),
                low,
            )
            # Foot: metatarsal (hind: long) to the ball, then three long toes with hooked claws.
            sk.auto(
                K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.03, 0.027, 0.03], 8, 4, K.SINEW), [low, foot]
            )
            sk.rigid(sk.sphere(j[3], 0.032, 10, 5, scale=(1.0, 1.2, 0.7), mi=K.SINEW), foot)
            for k, ang in enumerate((-22, 0, 22)):
                toe_dir = Vector((math.sin(math.radians(ang)) * s * -1, -1, 0)).normalized()
                knuckle = j[3] + toe_dir * 0.06 + Vector((0, 0, 0.012))
                tip = j[3] + toe_dir * (0.11 if k == 1 else 0.09) + Vector((0, 0, -0.025))
                sk.rigid(
                    K.tube_path(sk, [j[3], knuckle, tip - toe_dir * 0.02], [0.016, 0.013, 0.01], 6, 4, K.SINEW), foot
                )
                sk.rigid(
                    sk.cone(
                        tip - toe_dir * 0.025 + Vector((0, 0, 0.012)), tip + Vector((0, 0, -0.012)), 0.009, 5, K.BONE
                    ),
                    foot,
                )
            # Dewclaw spur at the back of the ankle.
            back = Vector((0, 0.05, 0.03)) if not hind else Vector((0, 0.06, 0.02))
            sk.rigid(sk.cone(j[2] + Vector((0, 0.01, -0.02)), j[2] + back, 0.012, 5, K.BONE), low if hind else foot)


def build_scythes(sk: K.Skin) -> None:
    for side, s in K.SIDES:
        base, joint, _tip = (K.mirror(p, s) for p in SCYTHE)
        arm, blade = f"{side}Scythe", f"{side}ScytheBlade"
        # Mount: a knob of chitin on the shoulder.
        sk.auto(
            sk.sphere(base + Vector((0, 0, -0.02)), 0.055, 12, 6, scale=(1.0, 1.3, 0.8), mi=K.CHITIN), ["Chest", arm]
        )
        # Arm: bony, knuckled, rising backward.
        mid = base.lerp(joint, 0.5) + Vector((s * 0.01, 0.02, 0))
        sk.rigid(K.tube_path(sk, [base, mid, joint], [0.045, 0.036, 0.042], 8, 6, K.BONE, 1.0, 0.003), arm)
        for t in (0.3, 0.65):
            sk.rigid(sk.sphere(base.lerp(joint, t), 0.046, 8, 4, scale=(1, 1, 0.7), mi=K.BONE), arm)
        sk.rigid(sk.sphere(joint, 0.06, 10, 5, mi=K.BONE), blade)
        # Blade: a long flat curved scythe sweeping forward, sharp lower edge, a row of spurs on its back.
        n = 14
        ctrl = [
            joint,
            joint + Vector((s * 0.02, -0.05, 0.2)),
            joint + Vector((s * 0.04, -0.3, 0.33)),
            joint + Vector((s * 0.05, -0.6, 0.27)),
            joint + Vector((s * 0.055, -0.8, 0.12)),
        ]
        top_rows, bot_rows = [], []
        spurs = []
        for i in range(n + 1):
            t = i / n
            c = K.path_point(ctrl, t)
            d = (K.path_point(ctrl, min(t + 0.03, 1)) - K.path_point(ctrl, max(t - 0.03, 0))).normalized()
            side_n = Vector((s, 0, 0))
            inner = d.cross(side_n).normalized()  # toward the sharp (inner) edge
            if inner.z > 0:
                inner = -inner
            width = 0.12 * math.sin(math.pi * min(0.15 + t, 1.0)) ** 0.6 * (1 - t) ** 0.35 + 0.006
            thick = 0.02 * (1 - t) + 0.003
            back = c - inner * width * 0.35
            edge = c + inner * width * 0.65
            top_rows.append([back + side_n * thick * 0.6, c + side_n * thick, edge + side_n * 0.001])
            bot_rows.append([back - side_n * thick * 0.6, c - side_n * thick, edge - side_n * 0.001])
            if 0.15 < t < 0.75 and i % 2 == 0:
                spurs.append((back, -inner, d))
        top_v = [[sk.bm.verts.new(p) for p in row] for row in top_rows]
        bot_v = [[sk.bm.verts.new(p) for p in row] for row in bot_rows]
        sk.rigid(K.close_grid(sk, top_v, bot_v, K.BONE), blade)
        for back, out, d in spurs:
            sk.rigid(sk.cone(back, back + out * 0.035 - d * 0.015, 0.009, 4, K.BONE, 0.5), blade)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    build_trunk(sk)
    build_neck_head(sk, eyes)
    build_tail(sk)
    build_legs(sk)
    build_scythes(sk)
    body = sk.finish(root)
    eye_obj = eyes.finish(root)
    for obj in (body, eye_obj):
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return body, eye_obj


# --- posing -----------------------------------------------------------------------------------------


def tail_wave(p: K.Pose, phase: float, amp: float, lift: float) -> None:
    for i, bone in enumerate(("Tail1", "Tail2", "Tail3")):
        p.set(bone, rz(amp * math.sin(phase - i * 0.9)) @ rx(lift))


def idle(t: float) -> K.Pose:
    a = math.tau * t
    breath = math.sin(a)
    p = K.Pose(RIG, (0, 0, 0.006 * breath))
    p.set("Spine", rx(-1.0 * breath)).set("Chest", rx(-1.5 * breath))
    p.set("Neck", rx(4 + 2 * math.sin(a + 0.6)) @ rz(6 * math.sin(a * 2 + 1.0)))
    p.set("Head", rx(-6 + 3 * math.sin(a + 1.2)) @ rz(-4 * math.sin(a * 2 + 1.0)))
    p.set("Jaw", rx(-3 - 3 * max(0.0, math.sin(a * 2 + 2.0))))
    tail_wave(p, a, 9, -6)
    for side, s in K.SIDES:
        p.set(f"{side}Scythe", rx(2 * math.sin(a + s)))
        p.set(f"{side}ScytheBlade", rx(-3 * math.sin(a * 2 + s)))
    return p


def run(t: float) -> K.Pose:
    """The trunk's motion while running (legs at rest, the game steps them): two bobs per stride, the spine flexing,
    the head low and steady, the tail streaming back."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0, 0, -0.02 + 0.018 * bob))
    p.set("Body", rx(2.5 * math.sin(2 * a)) @ ry(3 * math.sin(a)))
    p.set("Spine", rx(3 * math.sin(2 * a + 0.8)) @ rz(4 * math.sin(a)))
    p.set("Chest", rx(-2 * math.sin(2 * a + 0.8)))
    p.set("Neck", rx(-10 - 2.5 * math.sin(2 * a)) @ rz(-3 * math.sin(a)))
    p.set("Head", rx(-4 + 4 * math.sin(2 * a)))
    p.set("Jaw", rx(-10))
    for i, bone in enumerate(("Tail1", "Tail2", "Tail3")):
        p.set(bone, rz(10 * math.sin(a - i * 1.1)) @ rx(-9 + 4 * math.sin(2 * a - i)))
    for side, s in K.SIDES:
        p.set(f"{side}Scythe", rx(10 + 4 * math.sin(2 * a + 0.5)) @ ry(s * -4))
        p.set(f"{side}ScytheBlade", rx(6 * math.sin(2 * a + 1.2)))
    return p


def attack(t: float) -> K.Pose:
    """Rears back (to 0.35), snaps forward with the jaw open and both blades striking down (0.5), recovers."""
    back = K.smooth(t / 0.35) * (1 - K.smooth((t - 0.35) / 0.12))
    strike = K.smooth((t - 0.35) / 0.15) * (1 - K.smooth((t - 0.6) / 0.4))
    p = K.Pose(RIG, (0, 0.08 * back - 0.22 * strike, 0.03 * back - 0.05 * strike))
    p.set("Body", rx(6 * back - 8 * strike))
    p.set("Chest", rx(5 * back - 4 * strike))
    p.set("Neck", rx(18 * back - 22 * strike))
    p.set("Head", rx(10 * back - 6 * strike))
    p.set("Jaw", rx(-6 - 30 * back - 18 * strike))
    tail_wave(p, 0.0, 0, 15 * back - 10 * strike)
    for side, s in K.SIDES:
        p.set(f"{side}Scythe", rx(-25 * back + 55 * strike) @ ry(s * 10 * strike))
        p.set(f"{side}ScytheBlade", rx(-20 * back + 45 * strike))
    return p


def die(t: float) -> K.Pose:
    """Legs buckle (to 0.35), it rolls onto its left side (1.0) with the jaw open and the blades splayed."""
    k = K.smooth(t / 0.35)
    f = K.smooth((t - 0.2) / 0.65)
    p = K.Pose(RIG, (0.12 * f, 0.0, -0.32 * k - 0.16 * f))
    p.set("Body", ry(78 * f) @ rx(-4 * k))
    p.set("Neck", rx(-14 * k) @ rz(15 * f))
    p.set("Head", rx(-10 * k) @ ry(-20 * f))
    p.set("Jaw", rx(-28 * k))
    tail_wave(p, 1.0, 14 * f, -10 * k)
    for side, s in K.SIDES:
        p.set(f"{side}Scythe", rx(35 * f) @ ry(s * 30 * f))
        p.set(f"{side}ScytheBlade", rx(25 * f))
        # Front: elbows fold back, paws tuck; hind: knees fold forward under the body.
        p.set(f"Front{side}UpperLeg", rx(-50 * k) @ ry(s * 10 * f))
        p.set(f"Front{side}LowerLeg", rx(95 * k))
        p.set(f"Front{side}Foot", rx(-40 * k))
        p.set(f"Hind{side}UpperLeg", rx(45 * k) @ ry(s * 10 * f))
        p.set(f"Hind{side}LowerLeg", rx(-80 * k))
        p.set(f"Hind{side}Foot", rx(50 * k))
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (60, idle),
    "Run": (20, run),
    "Attack": (15, attack),
    "Die": (30, die),
}

# --- preview ----------------------------------------------------------------------------------------


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.4, 1.2, 0))
    shots = []
    target = (0, -0.2, 0.7)
    K.rest_pose(arm)
    for view, zoom in (("iso", 0.3), ("hero", 0.36), ("back", 0.4), ("iso", 0.9)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((3.4, -0.25, 0.75)), (0, -0.05, 0.62), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.9, -1.7, 0.9)), (0, -0.8, 0.68), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    for name, pose in (
        ("idle", idle(0.25)),
        ("run", run(0.25)),
        ("attack3", attack(0.3)),
        ("attack5", attack(0.5)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.36)
        shots.append(path)
    K.rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "swarmer_procedural.blend")
        C.export_glb(OUT / "swarmer_draft.glb")


main()
