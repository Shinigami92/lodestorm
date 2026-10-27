"""Mite: a knee-high tick of the hive, tier 1, coming in packs. A swollen, slightly flattened abdomen under a few
chitin plates with glowing seams and blisters between them (the pack's glow on dark ground), a small armored head
shield with two glowing eyes and short hooked mandibles, six short jointed legs splayed out sideways like a tick's.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/mite/source/mite_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/mite/source/mite_build.py final      # renders + mite_procedural.blend

Everything it writes goes to tmp/assets/mite/; mite_bake.py turns mite_procedural.blend into the game asset.

Layout (Blender Z-up meters; the mite faces -Y, its left is +X; glTF turns -Y into Godot's +Z, so the game turns the
model by 180 degrees to face the alien's -Z). Feet on the ground at the origin, the origin under the middle of the
body; back 0.3 m high, mandibles to rump 0.55 m, 0.43 m wide over the splayed feet.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (the abdomen) with the hind legs,
Spine with the middle legs, Chest with the front legs, Neck, Head, Jaw with the two mandibles (<Side>Mandible, they
open sideways). Legs (<Front|Mid|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (two bones reaching
the ankle = the Foot bone's head, the Foot keeps its angle to the body), so the clips leave them at rest; only "Die"
curls them. Every knee stands high above the body's side, the foot reaches far out and down to its claw.
Meshes: "Creature" (one skinned object: the abdomen's flesh weighted to the nearest bones, plates, head, mandibles and
leg segments rigid), "Eyes" and "Glands" (constant emissive in the hive's yellow-green; the game flares them both).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop: twitchy, mandibles working,
small jerks of the body), "Run" (loop: a quick scuttle's bob and sway; the legs come from the game), "Attack" (once,
0.3 s: rears a little, lunges and pitches forward with the mandibles snapping shut) and "Die" (once: a spasm, then it
flips onto its back with the legs curling in, sunk into the ground).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "mite"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Mite"
FPS = 30
GLOW = 2.5  # emission strength of the glands (the eyes: 8)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.18))
WAIST = Vector((0, -0.07, 0.17))
NECK = Vector((0, -0.14, 0.165))
SKULL = Vector((0, -0.17, 0.16))
SNOUT = Vector((0, -0.25, 0.135))
JAW_PIVOT = Vector((0, -0.232, 0.125))
MANDIBLE = [Vector((0.022, -0.238, 0.124)), Vector((0.014, -0.298, 0.106))]
# Leg joints per row (x for the left side): hip, knee, ankle (the Foot bone's head), claw tip on the ground.
LEGS = {
    "Front": [
        Vector((0.05, -0.13, 0.145)),
        Vector((0.125, -0.195, 0.235)),
        Vector((0.16, -0.245, 0.05)),
        Vector((0.17, -0.285, 0.0)),
    ],
    "Mid": [
        Vector((0.062, -0.08, 0.14)),
        Vector((0.155, -0.1, 0.245)),
        Vector((0.193, -0.115, 0.05)),
        Vector((0.218, -0.128, 0.0)),
    ],
    "Hind": [
        Vector((0.07, -0.03, 0.14)),
        Vector((0.17, 0.0, 0.24)),
        Vector((0.205, 0.045, 0.05)),
        Vector((0.222, 0.075, 0.0)),
    ],
}
LEG_PARENT = {"Front": "Chest", "Mid": "Spine", "Hind": "Hips"}

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.1, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.06, 0)), "Root"),
    ("Hips", BODY, Vector((0, 0.22, 0.19)), "Body"),
    ("Spine", BODY, WAIST, "Body"),
    ("Chest", WAIST, NECK, "Spine"),
    ("Neck", NECK, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, Vector((0, -0.29, 0.11)), "Head"),
]
for _side, _s in K.SIDES:
    BONES.append((f"{_side}Mandible", K.mirror(MANDIBLE[0], _s), K.mirror(MANDIBLE[1], _s), "Jaw"))
    for _leg, _pts in LEGS.items():
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), LEG_PARENT[_leg]),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest", "Neck"]


# --- mesh -------------------------------------------------------------------------------------------

# Body profile from the rump forward (evenly spaced in y): y, center z, half-width, top, bottom. The abdomen is most
# of it (round, widest at y 0.13, the back 0.3 m high); in front of it the short waist where the legs sit.
TRUNK = [
    (0.28, 0.18, 0.03, 0.03, 0.025),
    (0.23, 0.185, 0.112, 0.094, 0.08),
    (0.18, 0.185, 0.138, 0.114, 0.095),
    (0.13, 0.185, 0.146, 0.12, 0.1),
    (0.08, 0.183, 0.144, 0.118, 0.098),
    (0.03, 0.18, 0.132, 0.108, 0.092),
    (-0.02, 0.175, 0.108, 0.09, 0.08),
    (-0.07, 0.17, 0.078, 0.065, 0.065),
    (-0.12, 0.165, 0.06, 0.048, 0.052),
    (-0.17, 0.16, 0.046, 0.038, 0.04),
]
TRUNK_SHAPE = K.Profile(TRUNK)
# Head (capitulum) from the waist to the mouth: y, center z, half-width, top, bottom.
HEAD = [
    (-0.15, 0.163, 0.046, 0.042, 0.038),
    (-0.175, 0.159, 0.05, 0.044, 0.036),
    (-0.2, 0.152, 0.047, 0.038, 0.033),
    (-0.225, 0.143, 0.038, 0.028, 0.026),
    (-0.25, 0.134, 0.022, 0.016, 0.016),
]
HEAD_SHAPE = K.Profile(HEAD)
# The abdomen's back: two rows of plates per side, split down the middle and across by glowing seams (the seams
# across curve back towards the sides like segment lines); a flank plate low on each side.
SEAMS = [(-0.04, 0.0), (0.07, 0.05), (0.17, 0.042), (0.262, 0.0)]  # y on the top, how far back at the sides
SEAM_GAP = 0.012  # half the gap across (m)
PLATE_ANGLES = (30, 83)  # left side (90 = the top); the right side mirrors around 90


def mirror_angle(a: float, s: float) -> float:
    return a if s > 0 else 180 - a


def seam_y(seam: tuple, a: float) -> float:
    """y of a seam across the back at angle a: on the top at its y, curving back towards the sides."""
    y, bend = seam
    return y + bend * ((90 - a) / 60) ** 2


def plate(sk: K.Skin, front: tuple, back: tuple, a0: float, a1: float, thick: float, nu: int = 4, nv: int = 3):
    """A chitin plate on the abdomen between two seams (front and back edge follow their curve), angles a0..a1."""
    top_rows, bot_rows = [], []
    for i in range(nv + 1):
        v = i / nv
        bulge = math.sin(math.pi * v) * 0.6 + 0.4
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            a = a0 + (a1 - a0) * u
            y0 = seam_y(front, a) + (SEAM_GAP if front[0] > -0.04 else 0.0)
            y1 = seam_y(back, a) - (SEAM_GAP if back[0] < 0.262 else 0.0)
            y = y0 + (y1 - y0) * v
            edge = math.sin(math.pi * u) ** 0.5
            o = 0.005 + 0.006 * v * edge
            row_t.append(sk.bm.verts.new(TRUNK_SHAPE.surface(y, a, o + thick * bulge * edge)))
            row_b.append(sk.bm.verts.new(TRUNK_SHAPE.surface(y, a, o)))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return K.close_grid(sk, top_rows, bot_rows, K.CHITIN)


def build_trunk(sk: K.Skin, glands: K.Skin) -> None:
    n = 14
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.004, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    for side, s in K.SIDES:
        a0, a1 = sorted((mirror_angle(PLATE_ANGLES[0], s), mirror_angle(PLATE_ANGLES[1], s)))
        for front, back in itertools.pairwise(SEAMS):
            sk.auto(plate(sk, front, back, a0, a1, 0.018), TRUNK_BONES, 8.0)
        b0, b1 = sorted((mirror_angle(-28, s), mirror_angle(22, s)))
        sk.auto(K.shell(sk, TRUNK_SHAPE, 0.0, 0.22, b0, b1, 0.005, 0.014, K.CHITIN, 3, 4, 0.004), TRUNK_BONES, 8.0)
    # Scutum: the shield over the waist, in front of the abdomen.
    sk.auto(K.shell(sk, TRUNK_SHAPE, -0.15, -0.05, 18, 162, 0.004, 0.016, K.CHITIN, 4, 3, 0.008), TRUNK_BONES, 8.0)
    # Glow: a seam down the middle of the back, two across it between the plate rows, swollen blisters where they
    # cross.
    pts = [TRUNK_SHAPE.surface(y, 90, 0.004) for y in (-0.04, 0.02, 0.1, 0.17, 0.235, 0.268)]
    glands.auto(K.tube_path(glands, pts, [0.008, 0.015, 0.017, 0.016, 0.011, 0.005], 6, 8, 0, 0.55), TRUNK_BONES)
    for seam in SEAMS[1:3]:
        pts = [TRUNK_SHAPE.surface(seam_y(seam, a), a, 0.004) for a in (26, 48, 70, 90, 110, 132, 154)]
        radii = [0.004, 0.009, 0.012, 0.013, 0.012, 0.009, 0.004]
        glands.auto(K.tube_path(glands, pts, radii, 6, 8, 0, 0.55), TRUNK_BONES)
    for y, r in ((0.07, 0.024), (0.17, 0.022), (0.12, 0.017), (0.02, 0.016)):
        p = TRUNK_SHAPE.surface(y, 90, 0.0)
        glands.auto(glands.sphere(p + Vector((0, 0, 0.004)), r, 6, 3, scale=(1, 1.2, 0.6)), TRUNK_BONES)


def build_head(sk: K.Skin, eyes: K.Skin) -> None:
    rings = []
    n = 6
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in HEAD], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 12, 0.002, 3 + i))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    # Mouth between the mandibles (the hypostome), raw red.
    sk.rigid(sk.sphere((0, -0.242, 0.117), 0.013, 6, 4, scale=(1.0, 1.3, 0.7), mi=K.MOUTH), "Jaw")
    for side, s in K.SIDES:
        # Mandibles: short, hooked inward, bone colored, on their own bones.
        base = K.mirror(MANDIBLE[0], s)
        pts = [
            base,
            base + Vector((s * 0.012, -0.03, -0.006)),
            base + Vector((s * 0.002, -0.058, -0.016)),
            base + Vector((s * -0.016, -0.068, -0.022)),
        ]
        sk.rigid(K.tube_path(sk, pts, [0.015, 0.013, 0.009, 0.004], 6, 5, K.BONE), f"{side}Mandible")
        # Palps beside them: short chitin feelers.
        p0 = Vector((s * 0.04, -0.215, 0.135))
        sk.rigid(
            K.tube_path(
                sk,
                [p0, p0 + Vector((s * 0.018, -0.03, -0.012)), p0 + Vector((s * 0.014, -0.055, -0.03))],
                [0.013, 0.012, 0.009],
                5,
                3,
                K.CHITIN,
            ),
            "Head",
        )
        # Eyes: two small glowing beads on the shield's front corners.
        eye = HEAD_SHAPE.surface(-0.2, mirror_angle(42, s), 0.008)
        eyes.rigid(eyes.sphere(eye, 0.013, 8, 4, scale=(1.0, 1.3, 0.85), rot=rz(s * 25)), "Head")
    # Head shield: a plate over the capitulum.
    sk.rigid(K.shell(sk, HEAD_SHAPE, -0.15, -0.225, 15, 165, 0.003, 0.012, K.CHITIN, 5, 2, 0.0), "Head")


def build_legs(sk: K.Skin) -> None:
    for leg, pts in LEGS.items():
        for side, s in K.SIDES:
            hip, knee, ankle, tip = (K.mirror(p, s) for p in pts)
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            # Femur from inside the body up to the knee, a joint of sinew there; tibia down to the ankle.
            start = hip - (knee - hip).normalized() * 0.03
            sk.rigid(K.tube_path(sk, [start, knee], [0.022, 0.018], 5, 2, K.CHITIN), up)
            sk.rigid(sk.sphere(knee, 0.02, 6, 3, mi=K.SINEW), low)
            mid = knee.lerp(ankle, 0.45) + Vector((s * 0.012, 0, 0))
            sk.rigid(K.tube_path(sk, [knee, mid, ankle], [0.017, 0.016, 0.015], 5, 3, K.CHITIN), low)
            # Tarsus out to a hooked bone claw on the ground.
            d = (tip - ankle).normalized()
            sk.rigid(K.tube_path(sk, [ankle, tip - d * 0.022], [0.015, 0.013], 5, 1, K.CHITIN), foot)
            sk.rigid(sk.cone(tip - d * 0.026 + Vector((0, 0, 0.006)), tip, 0.011, 5, K.BONE), foot)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    mats = K.materials()
    sk = K.Skin("Creature", mats, RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLOW)], RIG)
    build_trunk(sk, glands)
    build_head(sk, eyes)
    build_legs(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


def jerks(t: float, keys: list, snap: float = 0.035) -> float:
    """A twitch: holds each (time, value) of a looping key list and snaps to the next one within `snap`."""
    i = max((i for i, k in enumerate(keys) if k[0] <= t), default=len(keys) - 1)
    t1, v1 = keys[i]
    v0 = keys[i - 1][1]
    return v0 + (v1 - v0) * K.smooth(((t - t1) % 1.0) / snap)


def mandibles(p: K.Pose, opened: float) -> None:
    for side, s in K.SIDES:
        p.set(f"{side}Mandible", rz(s * opened))


def idle(t: float) -> K.Pose:
    a = math.tau * t
    yaw = jerks(t, [(0.05, 0), (0.22, 5), (0.4, 1), (0.58, -4), (0.7, -1), (0.86, 3)])
    pitch = jerks(t, [(0.12, 0), (0.33, 2.5), (0.5, -1.5), (0.78, 1)])
    p = K.Pose(RIG, (0, 0, 0.003 * math.sin(a) + 0.002 * jerks(t, [(0.3, 0), (0.62, 1), (0.9, 0)], 0.05)))
    p.set("Body", rz(yaw) @ rx(pitch))
    p.set("Hips", rx(-1.5 * math.sin(a)) @ rz(-0.4 * yaw))  # the abdomen breathes and lags behind
    p.set("Head", rz(jerks(t, [(0.0, 0), (0.15, -7), (0.47, 6), (0.7, 0), (0.8, 8)])) @ rx(2 * math.sin(2 * a)))
    p.set("Jaw", rx(-2 - 3 * max(0.0, math.sin(a * 3))))
    mandibles(p, 6 + 14 * max(0.0, math.sin(a * 6)) ** 0.5)
    return p


def run(t: float) -> K.Pose:
    """A fast scuttle (legs at rest, the game steps them): two quick bobs per stride, a slight sway, the abdomen
    bouncing a moment behind, the head low and steady."""
    a = math.tau * t
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0, 0, -0.012 + 0.01 * bob))
    p.set("Body", ry(3.5 * math.sin(a)) @ rz(2.5 * math.sin(a + 0.5)) @ rx(1.5 * math.sin(2 * a)))
    p.set("Hips", rx(-3 * math.sin(2 * a - 0.9)) @ rz(-2 * math.sin(a)))
    p.set("Head", rx(5 - 2 * math.sin(2 * a + 0.4)) @ rz(-2 * math.sin(a + 0.5)))
    p.set("Jaw", rx(-4))
    mandibles(p, 12 + 4 * math.sin(4 * a))
    return p


def attack(t: float) -> K.Pose:
    """Rears a little with the mandibles wide (to 0.3), lunges and pitches forward, snapping them shut (0.5), and
    settles back."""
    back = K.smooth(t / 0.3) * (1 - K.smooth((t - 0.3) / 0.15))
    strike = K.smooth((t - 0.3) / 0.2) * (1 - K.smooth((t - 0.6) / 0.4))
    p = K.Pose(RIG, (0, 0.03 * back - 0.1 * strike, 0.025 * back - 0.03 * strike))
    p.set("Body", rx(-9 * back + 14 * strike))
    p.set("Hips", rx(5 * back - 8 * strike))
    p.set("Head", rx(-8 * back + 10 * strike))
    p.set("Jaw", rx(-12 * back + 2 * strike))
    mandibles(p, 6 + 30 * back - 14 * strike)
    return p


def die(t: float) -> K.Pose:
    """A spasm (to 0.25), then it flips over onto its back (0.2 to 0.8) and sinks in, the legs curling in over the
    belly, the mandibles splayed."""
    k = K.smooth(t / 0.2)
    f = K.smooth((t - 0.15) / 0.65)
    c = K.smooth((t - 0.3) / 0.6)
    spasm = math.sin(t * 40) * (1 - K.smooth((t - 0.1) / 0.2)) * k
    lift = math.sin(math.pi * f) * 0.08  # rises while it rolls over, so its side clears the ground
    p = K.Pose(RIG, (0.06 * f, 0.0, -0.05 * k + lift - 0.135 * f))
    p.set("Body", ry(172 * f) @ rz(12 * f + 4 * spasm) @ rx(6 * spasm))
    p.set("Hips", rx(-8 * f))
    p.set("Head", rx(12 * c))
    p.set("Jaw", rx(-10 * c))
    mandibles(p, 6 + 22 * c)
    for side, s in K.SIDES:
        # The femurs swing down past the body's side (up in the air once it lies on its back), the knees fold
        # tight and the shins and feet curl in over the belly.
        for i, leg in enumerate(LEGS):
            jerk = 10 * spasm * (1 if i % 2 else -1)
            vary = (i - 1) * 8
            p.set(f"{leg}{side}UpperLeg", ry(s * (-15 * k + (78 + vary) * c)) @ rz(s * jerk))
            p.set(f"{leg}{side}LowerLeg", ry(s * (10 * k + (42 - vary) * c)))
            p.set(f"{leg}{side}Foot", ry(s * 45 * c))
    return p


CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (60, idle),
    "Run": (12, run),
    "Attack": (9, attack),
    "Die": (30, die),
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


def measures(arm: bpy.types.Object) -> None:
    K.rest_pose(arm)
    body = mesh_points("Creature")
    glow = mesh_points("Glands")
    eyes = mesh_points("Eyes")
    lo = Vector([min(p[i] for p in body + glow + eyes) for i in range(3)])
    hi = Vector([max(p[i] for p in body + glow + eyes) for i in range(3)])
    print("MEASURE bounds", tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi))
    back = max((p for p in body if abs(p.x) < 0.1 and p.y > -0.05), key=lambda p: p.z)
    print("MEASURE back (creature)", tuple(round(x, 3) for x in back))
    top = max(glow, key=lambda p: p.z)
    print("MEASURE glow top", tuple(round(x, 3) for x in top))
    front = min((p for p in body if abs(p.x) < 0.06), key=lambda p: p.y)
    print("MEASURE front", tuple(round(x, 3) for x in front))
    mouth = Vector((0, -0.262, 0.122))
    print("MEASURE mouth", tuple(round(x, 3) for x in mouth))
    for name, (frames, fn) in CLIPS.items():
        zs = []
        for f in range(frames + 1):
            K.apply(arm, fn(f / frames))
            bpy.context.view_layer.update()
            pts = mesh_points("Creature") + mesh_points("Glands")
            zs.append((min(p.z for p in pts), max(p.z for p in pts)))
        print(f"MEASURE {name} min z {min(z[0] for z in zs):.3f} end max z {zs[-1][1]:.3f} end min z {zs[-1][0]:.3f}")
    K.rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------


def add_swarmer(x: float) -> list:
    """The swarmer's rest-pose mesh beside the mite for a scale check (wip only, from its procedural .blend)."""
    src = ROOT / "tmp" / "assets" / "swarmer" / "swarmer_procedural.blend"
    if not src.exists():
        return []
    with bpy.data.libraries.load(str(src)) as (data_from, data_to):
        data_to.meshes = [m for m in ("Creature", "Eyes") if m in data_from.meshes]
    objs = []
    for me in data_to.meshes:
        obj = bpy.data.objects.new("Scale" + me.name, me)
        C.link(obj, None, "Preview")
        obj.location = (x, 0.3, 0)
        objs.append(obj)
    return objs


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(0.9, 0.8, 0))
    shots = []
    w = OUT / "wip"
    target = (0, -0.02, 0.14)
    K.rest_pose(arm)
    for view, zoom in (("iso", 0.13), ("hero", 0.15), ("back", 0.17), ("iso", 0.9)):
        path = w / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(w / f"{tag}_side.png", Vector((1.4, -0.02, 0.22)), (0, -0.01, 0.13), 50, 32, 512)
    C.render_from(w / f"{tag}_head.png", Vector((0.32, -0.72, 0.33)), (0, -0.22, 0.14), 50, 32, 512)
    C.render_from(w / f"{tag}_top.png", Vector((0.0, -0.01, 1.6)), (0, -0.01, 0.0), 50, 32, 512)
    shots += [w / f"{tag}_side.png", w / f"{tag}_head.png", w / f"{tag}_top.png"]
    for name, pose in (
        ("idle", idle(0.25)),
        ("run", run(0.25)),
        ("attack3", attack(0.3)),
        ("attack5", attack(0.5)),
        ("die5", die(0.5)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        path = w / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.15)
        shots.append(path)
    path = w / f"{tag}_die_close.png"
    C.render_from(path, Vector((0.55, -0.6, 0.55)), (0.03, 0.0, 0.05), 50, 24, 512)
    shots.append(path)
    K.rest_pose(arm)
    if MODE == "wip":
        scale = add_swarmer(-1.0)
        if scale:
            path = w / f"{tag}_scale.png"
            C.render(path, view="iso", samples=32, size=512, target=(-0.5, 0.1, 0.3), zoom=0.3)
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
    measures(arm)
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "mite_procedural.blend")
        C.export_glb(OUT / "mite_draft.glb")


main()
