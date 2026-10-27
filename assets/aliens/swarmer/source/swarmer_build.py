"""Swarmer: a lean, dog-sized alien runner on four clawed legs with a toothed jaw and two scythe-like bone blades
rising behind its head and sweeping back over its body, generated (TRELLIS.2, source/trellis/), rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/swarmer/source/swarmer_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/swarmer/source/swarmer_build.py final      # renders + swarmer_procedural.blend
    tools/blender.sh assets/aliens/swarmer/source/swarmer_build.py joints     # x-ray renders of the joints

Everything it writes goes to tmp/assets/swarmer/; swarmer_bake.py turns swarmer_procedural.blend into the game asset.

Layout (Blender Z-up meters; the swarmer faces -Y, its left is +X; glTF turns -Y into Godot's +Z, so the game turns
the model by 180 degrees to face the alien's -Z). Feet on the ground at the origin, the origin under the middle of
the body; back about 0.75 m high, nose to tail tip 1.65 m, the blades reach 1.25 m.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the pelvis) with the tail
(Tail1..3) and the hind legs, Spine, Chest with the front legs, Neck with the blades (<Side>Scythe, <Side>ScytheBlade),
Head, Jaw. Legs (<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (two bones reaching the
ankle = the Foot bone's head, the Foot keeps its angle to the body), so the clips leave them at rest; only "Die"
folds them. Front elbows bend back, hind knees forward (digitigrade hind legs: the Foot is the long metatarsal).
The joints are the generated mesh's, in its own standing pose (the rest pose). Meshes: "Creature" (the generated
mesh, skinned: each part weighted to its nearest bone, blended across the joints, the lower jaw cut from the skull)
and "Eyes" (constant emissive, where the texture's eyes glowed; the game shows the facing with them).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop), "Run" (loop, the body's motion
while running: spine flex, head low, tail streaming; the legs come from the game), "Attack" (once: rears back, then
snaps forward with the jaw open and the blades swinging forward over the head) and "Die" (once: legs buckle, it falls
on its side).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "swarmer"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
import numpy as np
from mathutils import Vector

import common as C
import creature as K
import generated as G
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Swarmer"
FPS = 30

# --- skeleton -------------------------------------------------------------------------------------
# The generated mesh's joints, measured on it normalized to 2.4 m from the nose to the tail's tip (centered, feet at
# 0; the left side, mirrored for the right), then fit() to the swarmer's size and place.

SOURCE = ROOT / "assets" / "aliens" / "swarmer" / "source" / "trellis" / "swarmer_trellis.glb"
MEASURED_LENGTH = 2.4
LENGTH = 1.65  # nose to tail tip: the back about 0.75 m high
SHIFT_Y = 0.1  # the middle of the body onto the origin


def fit(p) -> Vector:
    return Vector((p[0], p[1] + SHIFT_Y, p[2])) * (LENGTH / MEASURED_LENGTH)


BODY = fit((0, -0.1, 0.95))
PELVIS = fit((0, 0.42, 0.97))
MID = fit((0, -0.32, 0.97))  # spine to chest
WITHERS = fit((0, -0.62, 1.05))
SKULL = fit((0, -0.88, 1.42))
SNOUT = fit((0, -1.2, 1.36))
JAW_PIVOT = fit((0, -0.93, 1.34))
JAW_TIP = fit((0, -1.16, 1.28))
TAIL = [fit(p) for p in ((0, 0.42, 0.97), (0, 0.62, 0.82), (0, 0.82, 0.58), (0, 1.02, 0.44), (0, 1.2, 0.5))]
# Leg joints per side (x for the left side): hip/shoulder, knee/elbow, ankle, ball of the foot, toe tips.
FRONT = [
    fit(p)
    for p in ((0.17, -0.5, 0.85), (0.2, -0.42, 0.62), (0.21, -0.58, 0.17), (0.22, -0.66, 0.05), (0.22, -0.76, 0.0))
]
HIND = [
    fit(p) for p in ((0.18, 0.32, 0.88), (0.22, 0.2, 0.62), (0.25, 0.45, 0.43), (0.26, 0.4, 0.06), (0.26, 0.28, 0.0))
]
SCYTHE = [fit(p) for p in ((0.08, -0.86, 1.5), (0.2, -0.8, 1.66), (0.42, 0.08, 1.8))]

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, MID, "Body"),
    ("Chest", MID, WITHERS, "Spine"),
    ("Neck", WITHERS, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, JAW_TIP, "Head"),
    ("Tail1", TAIL[0], TAIL[1], "Hips"),
    ("Tail2", TAIL[1], TAIL[2], "Tail1"),
    ("Tail3", TAIL[2], TAIL[3], "Tail2"),
]
for _side, _s in K.SIDES:
    BONES += [
        (f"{_side}Scythe", K.mirror(SCYTHE[0], _s), K.mirror(SCYTHE[1], _s), "Neck"),
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
# The generated mesh in its own standing pose is the rest pose: every vertex belongs to the bone nearest to it
# (distance to the bone's segment minus the bone's radius), blended with the neighbor bone within a band across each
# joint; the faces between the skull and the lower jaw are cut (the mouth opens), except at the hinge.

WEIGHTED = [name for name, *_r in BONES if name not in ("Root", "Body")]
TIP = {  # where the bones without a child joint end for the weights
    "Head": SNOUT,
    "Jaw": JAW_TIP,
    "Tail3": TAIL[4],
    **{f"Front{side}Foot": K.mirror(FRONT[4], s) for side, s in K.SIDES},
    **{f"Hind{side}Foot": K.mirror(HIND[4], s) for side, s in K.SIDES},
}
BONE_RADIUS = {
    "Hips": 0.13,
    "Spine": 0.13,
    "Chest": 0.14,
    "Neck": 0.07,
    "Head": 0.06,
    "Jaw": 0.02,
    "Tail1": 0.045,
    "Tail2": 0.03,
    "Tail3": 0.02,
}
BLEND_BAND = {
    "Spine": 0.06,
    "Chest": 0.05,
    "Neck": 0.05,
    "Head": 0.04,
    "Jaw": 0.015,
    "Tail1": 0.05,
    "Tail2": 0.04,
    "Tail3": 0.04,
}
for _side, _s in K.SIDES:
    BONE_RADIUS |= {f"{_side}Scythe": 0.03, f"{_side}ScytheBlade": 0.03}
    BLEND_BAND |= {f"{_side}Scythe": 0.02, f"{_side}ScytheBlade": 0.02}
    for _leg, _hind in (("Front", False), ("Hind", True)):
        BONE_RADIUS |= {
            f"{_leg}{_side}UpperLeg": 0.07 if _hind else 0.06,
            f"{_leg}{_side}LowerLeg": 0.035,
            f"{_leg}{_side}Foot": 0.03,
        }
        BLEND_BAND |= {f"{_leg}{_side}UpperLeg": 0.05, f"{_leg}{_side}LowerLeg": 0.03, f"{_leg}{_side}Foot": 0.025}
BLEND_PARENT = RIG.parent | {"Spine": "Hips"}  # the trunk's two halves blend where they meet (both start at Body)
MOUTH = (["Head"], ["Jaw"])
EYE_SIZE = (0.012, 0.022, 0.009)  # half sizes: across, along the head, up


def eye_mask(rgb: np.ndarray) -> np.ndarray:
    """0..1 per pixel of how glowing yellow-green the (sRGB) base color is (saturated: the pale bone isn't)."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    yellow = np.clip((np.minimum(r, g) - b - 0.08) / 0.12, 0, 1)
    saturated = np.clip(((g - b) / np.maximum(g, 1e-3) - 0.3) / 0.1, 0, 1)
    bright = np.clip((g - 0.3) / 0.2, 0, 1)
    return yellow * saturated * bright


def load(root: bpy.types.Object) -> bpy.types.Object:
    """The generated mesh, normalized (centered, feet at 0) and fitted (fit())."""
    obj = G.load(SOURCE, root, "Creature")
    co = G.vertices(obj.data)
    lo, hi = co.min(0), co.max(0)
    co = (co - [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]) * (MEASURED_LENGTH / (hi[1] - lo[1]))
    co[:, 1] += SHIFT_Y
    G.set_vertices(obj.data, co * (LENGTH / MEASURED_LENGTH))
    return obj


def segments() -> dict:
    """Each weighted bone's segment: its head to its tail (the bones' tails are the next joints), or to the mesh's tip;
    the hips the other way round, so the trunk's halves meet at their ends."""
    seg = {name: (RIG.head[name], TIP.get(name, RIG.tail[name])) for name in WEIGHTED}
    seg["Hips"] = (PELVIS, BODY)
    return seg


def weights(co: np.ndarray, seg: dict) -> tuple:
    score, along = G.capsules(co, WEIGHTED, seg, BONE_RADIUS)
    # The blades own only what rises above the head; the jaw only what's below the mouth's line.
    for side, s in K.SIDES:
        for name in (f"{side}Scythe", f"{side}ScytheBlade"):
            score[co[:, 2] < SCYTHE[0].z - 0.01, WEIGHTED.index(name)] = np.inf
    # Neck and head own nothing behind their start (the chest's front), the hips give way to the tail past its start.
    for name in ("Chest", "Neck", "Head"):
        score[along[:, WEIGHTED.index(name)] < -BLEND_BAND[name], WEIGHTED.index(name)] = np.inf
    score[along[:, WEIGHTED.index("Tail1")] > 0.02, WEIGHTED.index("Hips")] = np.inf
    mouth = JAW_PIVOT.z + (co[:, 1] - JAW_PIVOT.y) * (JAW_TIP.z - JAW_PIVOT.z) / (JAW_TIP.y - JAW_PIVOT.y)
    score[co[:, 2] > mouth + 0.004, WEIGHTED.index("Jaw")] = np.inf
    return G.weights(score, along, WEIGHTED, seg, BLEND_BAND, BLEND_PARENT, co=co)


def eyes(creature: bpy.types.Object, w: np.ndarray, root: bpy.types.Object) -> bpy.types.Object:
    """ "Eyes": a slanted glowing slit per side where the texture's eyes glowed (painted over in the skin's dark
    there), weighted like the head under it."""
    me = creature.data
    bsdf = me.materials[0].node_tree.nodes["Principled BSDF"]
    base = G.base_color_image(me.materials[0])
    rgba = G.image_pixels(base)
    mask = eye_mask(rgba[..., :3])
    lit = G.face_values(me, mask) > 0.5
    co = G.vertices(me)
    centres = np.array([co[list(p.vertices)].mean(0) for p in me.polygons])
    head = (centres[:, 1] < SKULL.y + 0.02) & (centres[:, 2] > JAW_PIVOT.z)
    faces = [p for p in me.polygons if lit[p.index] and head[p.index]]
    cover = G.uv_cover(me, faces, base.size[0])
    dark = np.median(rgba[cover & (mask < 0.1), :3], axis=0) if (cover & (mask < 0.1)).any() else np.full(3, 0.05)
    painted = rgba.copy()
    k = (mask * cover)[..., None]
    painted[..., :3] = painted[..., :3] * (1 - k) + dark * k
    bsdf.inputs["Base Color"].links[0].from_node.image = G.packed_image("SwarmerBase", painted)
    eye = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    for side, s in K.SIDES:
        pts = centres[[p.index for p in faces if centres[p.index, 0] * s > 0]]
        if not len(pts):
            pts = np.array([[s * 0.05, SKULL.y - 0.08, SKULL.z]])
            print("EYES none found on the", side, "side")
        c = pts.mean(0)
        normal = Vector((s, -0.35, 0.2)).normalized()
        eye.rigid(
            eye.sphere(tuple(c + np.array(normal) * 0.004), 1.0, 10, 5, scale=EYE_SIZE, rot=rz(s * 18) @ rx(-10)),
            "Head",
        )
        print("EYES", side, len(pts), "faces at", c.round(3))
    obj = eye.finish(root)
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    G.set_weights(obj, WEIGHTED, G.nearest_weights(co, G.vertices(obj.data), w))
    return obj


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    body = load(root)
    co = G.vertices(body.data)
    owner, w = weights(co, segments())
    print("CREATURE owners", {b: int((owner == i).sum()) for i, b in enumerate(WEIGHTED)})
    hinge = np.linalg.norm(co - np.array(JAW_PIVOT), axis=1) > 0.03  # the mouth's corners stay closed
    print("CREATURE mouth cut", G.cut_bridges(body.data, owner, WEIGHTED, MOUTH, hinge), "faces")
    G.set_weights(body, WEIGHTED, w)
    G.smooth_shading(body)
    body.data.materials[0].name = "Creature"
    eye_obj = eyes(body, w, root)
    for obj in (body, eye_obj):
        obj.modifiers.new("Armature", "ARMATURE").object = arm
    C.shade_smooth(eye_obj)
    return body, eye_obj


def show_joints(arm: bpy.types.Object) -> None:
    """X-ray renders of the joints over the mesh, to check the joint table against it."""
    for name, head, tail, _p in BONES:
        for p, r in ((head, 0.012), (tail, 0.007)):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=p)
            bpy.context.active_object.color = (1, 0.15, 0.05, 1)
    C.preview_scene(crystals=False, figure_location=(3, 3, 0))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.show_xray = True
    scene.display.shading.xray_alpha = 0.35
    scene.display.shading.color_type = "OBJECT"
    bpy.data.objects["Creature"].color = (0.6, 0.62, 0.65, 1)
    shots = []
    for v, loc in (("side", (2.6, -0.1, 0.55)), ("front", (0, -2.6, 0.55)), ("top", (0, -0.1, 2.8))):
        cam = C._camera("custom")
        cam.data.lens = 50
        cam.location = Vector(loc)
        target = Vector((0, -0.1, 0.5))
        cam.rotation_euler = (target - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        scene.render.resolution_x = scene.render.resolution_y = 900
        path = OUT / "wip" / f"joints_{v}.png"
        C._write_render(path)
        shots.append(path)
    C.contact_sheet(shots, OUT / "wip" / "joints_sheet.png", cols=3, tile=600)


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
    for side, s in K.SIDES:  # the blades lean back, then swing forward over the head
        p.set(f"{side}Scythe", rx(-15 * back + 70 * strike) @ ry(s * 10 * strike))
        p.set(f"{side}ScytheBlade", rx(-10 * back + 45 * strike))
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
    if MODE == "joints":
        show_joints(arm)
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "swarmer_procedural.blend")
        C.export_glb(OUT / "swarmer_draft.glb")


main()
