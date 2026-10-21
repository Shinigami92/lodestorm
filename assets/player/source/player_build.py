"""Player: a bulky, dark armored suit with a glowing collar band, generated (TRELLIS.2, source/trellis/), rigged
and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/player/source/player_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/player/source/player_build.py final      # renders + player_procedural.blend
    tools/blender.sh assets/player/source/player_build.py clips [Slash ...]  # workbench sheets of the melee clips

Everything it writes goes to tmp/assets/player/; player_bake.py turns player_procedural.blend into the game asset.

Layout (Blender Z-up meters; the character faces -Y, its left is +X; glTF turns -Y into Godot's +Z, so the game
turns the model by 180 degrees to face the player's -Z). T-pose rest, feet on the ground at the origin, 1.89 m.

Skeleton "Skeleton": Godot's humanoid bone names (SkeletonProfileHumanoid, without fingers), so the animations
could be retargeted later; its joints and bone lengths are the generated suit's. Meshes: "Suit" (the generated
mesh, skinned: each part weighted to its nearest bone, blended across the joints, see "suit" below) and
"SuitLight" (the collar band cut out of it, constant emissive; the game drives its color by health). Empties on bones: "WeaponGrip" (RightHand, Harl's origin in the aim pose; Godot axes:
-Z forward), "ShieldGrip" (LeftLowerArm, Mantle's plate on the forearm, facing forward in "ReadyShield"),
"CargoRack" and "HosePort" (UpperChest, on the backpack).

Animations (one action per clip, each in its own NLA track, all at 30 fps): "Idle" (loop), "Run", "RunBack",
"StrafeLeft", "StrafeRight" (loops, authored at RUN_SPEED: the game scales their speed by the actual one),
"Aim" (upper-body pose holding Harl; the game layers it over the legs), "Die" (once, ends lying face
down) and the melee clips, upper body only too: the holds "ReadyBlade" (Riven), "ReadyHammer" (Dray), "Brace"
(Jag, Auger: two-handed at the hip), "ReadyFist" (Clout: the gauntlet raised) and "ReadyShield" (Mantle: the left
forearm across the chest), the attacks "Slash", "SlashBack", "Overhead", "Thrust", "Punch" and "Bash" (wind-up, a
stroke of ATTACK_STROKE frames the game fits to the attack's time, staying at the end), the braced tool's loops "Cut"
(leaning in, shaking) and "Drill" (out at the thrust's end, shaking) and the gauntlet's "Cock" (drawn back for a
charged punch, trembling). Poses are built from world-space rotations per bone and two-bone IK for arms and legs, then converted to
the bones' local rotations (pose_of()).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "player"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import itertools

import bpy
import numpy as np
from mathutils import Matrix, Vector

import common as C
import generated as G
from common import T, rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Player"
FPS = 30
RUN_SPEED = 6.0  # m/s the locomotion clips are authored at (PlayerSettings.move_speed)
RUN_FRAMES = 20  # one stride (two steps) in 0.67 s
I3 = Matrix.Identity(3)

# --- skeleton -------------------------------------------------------------------------------------
# Fitted to the generated suit (see "suit" below): its joints in its A-pose, measured on the mesh normalized to
# 1.8 m (centered, feet at 0; left side, the right mirrors it), then fit() to the skeleton's size and place.

SUIT_SOURCE = ROOT / "assets" / "player" / "source" / "trellis" / "player_trellis.glb"
SUIT_SCALE = 1.05  # at this size the suit's body matches the clips' proportions (1.89 m to the helmet's top)
SUIT_SHIFT_Y = 0.03  # moves the normalized mesh's spine onto the skeleton's (y = 0)
SUIT_SPINE = {
    "Hips": (0, -0.03, 0.95),
    "Spine": (0, -0.03, 1.07),
    "Chest": (0, -0.03, 1.19),
    "UpperChest": (0, -0.03, 1.31),
    "Neck": (0, -0.04, 1.46),
    "Head": (0, -0.05, 1.54),
    "HeadTop": (0, -0.05, 1.80),
}
SUIT_LIMBS = {
    "Shoulder": (0.05, -0.03, 1.42),
    "UpperArm": (0.26, 0.0, 1.40),
    "LowerArm": (0.41, 0.03, 1.15),
    "Hand": (0.50, -0.05, 0.93),
    "HandTip": (0.52, -0.10, 0.74),
    "UpperLeg": (0.12, -0.05, 0.88),
    "LowerLeg": (0.21, -0.05, 0.46),
    "Foot": (0.25, -0.02, 0.14),
    "Toes": (0.28, -0.13, 0.05),
    "ToesTip": (0.29, -0.22, 0.04),
}
SIDES = (("Left", 1.0), ("Right", -1.0))


def fit(p) -> Vector:
    return Vector((p[0], p[1] + SUIT_SHIFT_Y, p[2])) * SUIT_SCALE


J = {name: fit(p) for name, p in SUIT_SPINE.items()}  # the suit's joints (A-pose), skeleton space
for _side, _s in SIDES:
    J |= {f"{_side}{name}": fit((_s * x, y, z)) for name, (x, y, z) in SUIT_LIMBS.items()}

# The T rest pose: arms along X at the shoulders' height, legs straight down, bone lengths the suit's.
UPPER_ARM_LEN = (J["LeftLowerArm"] - J["LeftUpperArm"]).length
LOWER_ARM_LEN = (J["LeftHand"] - J["LeftLowerArm"]).length
UPPER_LEG_LEN = (J["LeftLowerLeg"] - J["LeftUpperLeg"]).length
LOWER_LEG_LEN = (J["LeftFoot"] - J["LeftLowerLeg"]).length
SHOULDER_X, ARM_Z = J["LeftUpperArm"].x, J["LeftUpperArm"].z
ELBOW_X = SHOULDER_X + UPPER_ARM_LEN
WRIST_X = ELBOW_X + LOWER_ARM_LEN
HAND_X = WRIST_X + 0.13
HIP_X, ANKLE_Z = J["LeftUpperLeg"].x, J["LeftFoot"].z  # the ankle as high as in the suit: soles on the ground
KNEE_Z = ANKLE_Z + LOWER_LEG_LEN
HIP_Z = KNEE_Z + UPPER_LEG_LEN
HIPS_Z = HIP_Z + 0.02
TOES = J["LeftToes"] - J["LeftFoot"]  # the feet keep the suit's shape (without turning out)
TOES_TIP = J["LeftToesTip"] - J["LeftToes"]
SPINE_Z = {name: J[name].z for name in ("Spine", "Chest", "UpperChest", "Neck", "Head", "HeadTop")}

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, 0.2, 0), None),
    ("Hips", (0, 0, HIPS_Z), (0, 0, SPINE_Z["Spine"]), "Root"),
    ("Spine", (0, 0, SPINE_Z["Spine"]), (0, 0, SPINE_Z["Chest"]), "Hips"),
    ("Chest", (0, 0, SPINE_Z["Chest"]), (0, 0, SPINE_Z["UpperChest"]), "Spine"),
    ("UpperChest", (0, 0, SPINE_Z["UpperChest"]), (0, 0, SPINE_Z["Neck"]), "Chest"),
    ("Neck", (0, 0, SPINE_Z["Neck"]), (0, 0, SPINE_Z["Head"]), "UpperChest"),
    ("Head", (0, 0, SPINE_Z["Head"]), (0, 0, SPINE_Z["HeadTop"]), "Neck"),
]
for _side, _s in SIDES:
    _ankle = Vector((_s * HIP_X, 0, ANKLE_Z))
    _toes = _ankle + Vector((0, TOES.y, TOES.z))
    BONES += [
        (f"{_side}Shoulder", (_s * 0.04, 0, ARM_Z), (_s * SHOULDER_X, 0, ARM_Z), "UpperChest"),
        (f"{_side}UpperArm", (_s * SHOULDER_X, 0, ARM_Z), (_s * ELBOW_X, 0, ARM_Z), f"{_side}Shoulder"),
        (f"{_side}LowerArm", (_s * ELBOW_X, 0, ARM_Z), (_s * WRIST_X, 0, ARM_Z), f"{_side}UpperArm"),
        (f"{_side}Hand", (_s * WRIST_X, 0, ARM_Z), (_s * HAND_X, 0, ARM_Z), f"{_side}LowerArm"),
        (f"{_side}UpperLeg", (_s * HIP_X, 0, HIP_Z), (_s * HIP_X, 0, KNEE_Z), "Hips"),
        (f"{_side}LowerLeg", (_s * HIP_X, 0, KNEE_Z), tuple(_ankle), f"{_side}UpperLeg"),
        (f"{_side}Foot", tuple(_ankle), tuple(_toes), f"{_side}LowerLeg"),
        (f"{_side}Toes", tuple(_toes), tuple(_toes + Vector((0, TOES_TIP.y, TOES_TIP.z))), f"{_side}Foot"),
    ]
HEAD = {n: Vector(h) for n, h, _t, _p in BONES}
PARENT = {n: p for n, _h, _t, p in BONES}
NEXT_JOINT = {"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head"}
NEXT_JOINT["Head"] = "HeadTop"
for _side, _s in SIDES:
    for _a, _b in itertools.pairwise(("Shoulder", "UpperArm", "LowerArm", "Hand", "HandTip")):
        NEXT_JOINT[f"{_side}{_a}"] = f"{_side}{_b}"
    for _a, _b in itertools.pairwise(("UpperLeg", "LowerLeg", "Foot", "Toes", "ToesTip")):
        NEXT_JOINT[f"{_side}{_a}"] = f"{_side}{_b}"


def build_skeleton(root: bpy.types.Object) -> bpy.types.Object:
    data = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", data)
    C.link(arm, root)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        eb.roll = 0.0
        if parent:
            eb.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    data.display_type = "STICK"
    return arm


# --- suit -------------------------------------------------------------------------------------------
# The suit is generated (source/trellis/: the concept image, the mesh TRELLIS.2 made of it, trellis.json with how):
# one textured mesh in an A-pose. It's fitted to the skeleton here: the skeleton is posed into the mesh's A-pose,
# every vertex belongs to the bone nearest to it (distance to the bone's segment minus the bone's radius), blended
# with the neighbor bone within a band across each joint, faces joining parts that move apart are cut, and the
# mesh is moved into the T rest pose (the inverse of the skinning). The collar's glowing band becomes "SuitLight";
# the other glowing cyan parts (backpack panel, lamps) get an emission map from the base color.

WEIGHTED = [name for name, *_r in BONES if name != "Root"]
BONE_RADIUS = {"Hips": 0.17, "Spine": 0.19, "Chest": 0.21, "UpperChest": 0.21, "Neck": 0.08, "Head": 0.2}
BLEND_BAND = {"Spine": 0.06, "Chest": 0.06, "UpperChest": 0.06, "Neck": 0.03, "Head": 0.03}  # half-width at the head
for _side, _s in SIDES:
    BONE_RADIUS |= {
        f"{_side}Shoulder": 0.07,
        f"{_side}UpperArm": 0.08,
        f"{_side}LowerArm": 0.07,
        f"{_side}Hand": 0.05,
        f"{_side}UpperLeg": 0.10,
        f"{_side}LowerLeg": 0.08,
        f"{_side}Foot": 0.06,
        f"{_side}Toes": 0.05,
    }
    BLEND_BAND |= {
        f"{_side}UpperArm": 0.05,
        f"{_side}LowerArm": 0.04,
        f"{_side}Hand": 0.03,
        f"{_side}UpperLeg": 0.05,
        f"{_side}LowerLeg": 0.04,
        f"{_side}Foot": 0.03,
        f"{_side}Toes": 0.02,
    }
TORSO = ("Hips", "Spine", "Chest", "UpperChest")
BACKPACK_Y = fit((0, 0.17, 0)).y  # behind this and above the hips only the torso owns vertices
CUT = (  # faces joining a bone of one group to one of the other are cut: they would stretch
    [f"{s}{n}" for s, _ in SIDES for n in ("UpperArm", "LowerArm", "Hand")],
    ["Hips", "Spine", "Chest"] + [f"{s}{n}" for s, _ in SIDES for n in ("UpperLeg", "LowerLeg")],
)
SUIT_LIGHT_Z = (1.5, 1.68)  # the collar's glowing ring: glowing faces in this height, in front of the backpack
SUIT_LIGHT_Y = 0.16
SUIT_LIGHT_HEIGHT = 0.03  # the band lighting it
GLOW_STRENGTH = 4.0


def glow_mask(rgb: np.ndarray) -> np.ndarray:
    """0..1 per pixel of how glowing-cyan the (sRGB) base color is (saturated: pale blue-grey paint doesn't glow)."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hi = np.maximum(g, b)
    cyan = np.clip((np.minimum(g, b) - r - 0.1) / 0.12, 0, 1)
    saturated = np.clip(((hi - r) / np.maximum(hi, 1e-3) - 0.3) / 0.15, 0, 1)
    bright = np.clip((hi - 0.2) / 0.2, 0, 1)
    return cyan * saturated * bright


def load_suit(root: bpy.types.Object) -> bpy.types.Object:
    """The generated mesh, normalized (1.8 m, centered, feet at 0) and fitted (fit()); still in its A-pose."""
    obj = G.load(SUIT_SOURCE, root, "Suit")
    co = G.vertices(obj.data)
    lo, hi = co.min(0), co.max(0)
    co = (co - [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]) * (1.8 / (hi[2] - lo[2]))
    co[:, 1] += SUIT_SHIFT_Y
    G.set_vertices(obj.data, co * SUIT_SCALE)
    return obj


def pose_a(arm: bpy.types.Object) -> None:
    """Lower the hips onto the suit's (its legs are spread, the rest pose's straight), turn the arms and legs, each
    bone about its head, parents first, to point at the suit's joints (the shoulders along the suit's own), and the
    feet flat, only turned out like the suit's (the toes follow)."""
    hips = arm.pose.bones["Hips"]
    hips.location = hips.bone.matrix_local.to_3x3().transposed() @ Vector((0, 0, J["LeftUpperLeg"].z - HIP_Z))
    bpy.context.view_layer.update()
    for side, _s in SIDES:
        for n in ("Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"):
            pb = arm.pose.bones[f"{side}{n}"]
            head = pb.head.copy()
            want = J[NEXT_JOINT[pb.name]] - (J[pb.name] if n == "Shoulder" else head)
            if n == "Foot":
                rest = pb.bone.matrix_local.to_3x3()
                d = rest.col[1]
                yaw = math.atan2(want.y, want.x) - math.atan2(d.y, d.x)
                m = (Matrix.Rotation(yaw, 3, "Z") @ rest).to_4x4()
                m.translation = head
                pb.matrix = m
            else:
                turn = (pb.tail - pb.head).rotation_difference(want).to_matrix().to_4x4()
                pb.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ pb.matrix
            bpy.context.view_layer.update()


def segments(arm: bpy.types.Object) -> dict:
    """Each weighted bone's segment in the posed armature: its head to the next joint (or the mesh's tip)."""
    seg = {}
    for name in WEIGHTED:
        pb = arm.pose.bones[name]
        nxt = NEXT_JOINT[name]
        end = (
            arm.pose.bones[nxt].head
            if nxt in arm.pose.bones
            else pb.head + (pb.tail - pb.head).normalized() * (J[nxt] - J[name]).length
        )
        seg[name] = (pb.head[:], end[:])
    return seg


def weights(co: np.ndarray, seg: dict) -> tuple:
    """The owning bone per vertex and the weights (vertices x WEIGHTED)."""
    score, along = G.capsules(co, WEIGHTED, seg, BONE_RADIUS)
    behind = (co[:, 1] > BACKPACK_Y) & (co[:, 2] > HIP_Z)
    for i, name in enumerate(WEIGHTED):
        if name not in TORSO:
            score[behind, i] = np.inf
        if name in ("Spine", "Chest", "UpperChest", "Neck", "Head"):  # nothing below its blend band (the collar)
            score[along[:, i] < -BLEND_BAND[name], i] = np.inf
    # The upper chest's end is the neck: only its middle blends there.
    return G.weights(score, along, WEIGHTED, seg, BLEND_BAND, PARENT, {"UpperChest": np.abs(co[:, 0]) < 0.1})


def unskin(obj: bpy.types.Object, arm: bpy.types.Object, w: np.ndarray) -> None:
    """Move the A-pose mesh into the rest pose: each vertex by the inverse of its blended bone matrices."""
    co = G.vertices(obj.data)
    mats = np.array([np.array(arm.pose.bones[b].matrix @ arm.data.bones[b].matrix_local.inverted()) for b in WEIGHTED])
    blend = np.einsum("nb,bij->nij", w, mats)
    rest = np.einsum("nij,nj->ni", np.linalg.inv(blend), np.column_stack((co, np.ones(len(co)))))[:, :3]
    G.set_vertices(obj.data, rest)
    print("SUIT soles at", round(float(rest[:, 2].min()), 3))
    G.set_weights(obj, WEIGHTED, w)


def add_glow(suit: bpy.types.Object) -> list:
    """The glowing cyan of the base color becomes emission (packed images, so the .blend keeps them), except on
    the collar, which "SuitLight" lights: there it's painted over in the collar's dark. Returns the collar's faces
    (the glowing ones in its height, in front of the backpack)."""
    me = suit.data
    bsdf = me.materials[0].node_tree.nodes["Principled BSDF"]
    base = G.base_color_image(me.materials[0])
    rgba = G.image_pixels(base)
    glow = glow_mask(rgba[..., :3])
    lit = G.face_values(me, glow) > 0.5
    co = G.vertices(me)
    collar = []
    for p in me.polygons:
        c = co[list(p.vertices)].mean(0)
        if lit[p.index] and SUIT_LIGHT_Z[0] < c[2] < SUIT_LIGHT_Z[1] and c[1] < SUIT_LIGHT_Y:
            collar.append(p)
    cover = G.uv_cover(me, collar, base.size[0])
    unlit = cover & (glow < 0.1)
    grey = float(np.median(rgba[unlit, :3])) if unlit.any() else 0.08
    painted = rgba.copy()
    k = (glow * cover)[..., None]
    painted[..., :3] = painted[..., :3] * (1 - k) + grey * k  # neutral: the collar's own paint is tinted by the glow
    bsdf.inputs["Base Color"].links[0].from_node.image = G.packed_image("SuitBase", painted)
    tex = me.materials[0].node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = G.packed_image("SuitGlow", rgba * (glow * ~cover)[..., None])
    me.materials[0].node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = GLOW_STRENGTH
    return collar


def collar_band(suit: bpy.types.Object, collar: list, w: np.ndarray, root: bpy.types.Object) -> bpy.types.Object:
    """ "SuitLight": a thin band hugging the collar where its glowing ring was (radius and height per direction
    around the neck, from the collar's faces: the ring tilts), weighted like the suit under it."""
    co = G.vertices(suit.data)
    pts = np.array([co[list(p.vertices)].mean(0) for p in collar])
    centre = np.array([0.0, J["Neck"].y])
    rel = pts[:, :2] - centre
    ang = np.arctan2(rel[:, 1], rel[:, 0])
    rad = np.linalg.norm(rel, axis=1)
    bins = 24
    radius, height = np.full(bins, np.nan), np.full(bins, np.nan)
    which = ((ang + np.pi) * bins / (2 * np.pi)).astype(int) % bins
    for i in range(bins):
        m = which == i
        if m.sum() >= 3:
            radius[i] = np.percentile(rad[m], 80)
            height[i] = np.percentile(pts[m, 2], 60)
    known = np.flatnonzero(~np.isnan(radius))
    radius = np.interp(np.arange(bins), known, radius[known], period=bins)
    height = np.interp(np.arange(bins), known, height[known], period=bins)
    # Smooth both around the ring (a few passes of neighbour averaging).
    for _ in range(3):
        radius = (np.roll(radius, 1) + 2 * radius + np.roll(radius, -1)) / 4
        height = (np.roll(height, 1) + 2 * height + np.roll(height, -1)) / 4
    seg = 64
    verts = []
    for half, dr in ((-1, 0.012), (1, -0.004)):  # bottom ring out, top ring in: slanted like the collar's top
        for k in range(seg):
            a = -np.pi + 2 * np.pi * k / seg
            x = (a + np.pi) * bins / (2 * np.pi)
            r = np.interp(x, np.arange(bins + 1), np.append(radius, radius[0])) + 0.006 + dr
            z = np.interp(x, np.arange(bins + 1), np.append(height, height[0]))
            verts.append((centre[0] + r * np.cos(a), centre[1] + r * np.sin(a), z + half * SUIT_LIGHT_HEIGHT / 2))
    faces = [(k, (k + 1) % seg, seg + (k + 1) % seg, seg + k) for k in range(seg)]
    me = bpy.data.meshes.new("SuitLight")
    me.from_pydata(verts, [], faces)
    me.update()
    band = C.link(bpy.data.objects.new("SuitLight", me), root)
    me.materials.append(C.mat_emissive("SuitLight", (0.3, 1.0, 0.45), 6.0))
    G.set_weights(band, WEIGHTED, G.nearest_weights(co, verts, w))
    print("SUIT light from", len(collar), "collar faces, height", height.round(3).tolist())
    return band


def build_suit(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    suit = load_suit(root)
    pose_a(arm)
    owner, w = weights(G.vertices(suit.data), segments(arm))
    print("SUIT owners", {b: int((owner == i).sum()) for i, b in enumerate(WEIGHTED)})
    print("SUIT cut", G.cut_bridges(suit.data, owner, WEIGHTED, CUT), "faces")
    unskin(suit, arm, w)
    rest_pose(arm)
    G.smooth_shading(suit)
    suit.data.materials[0].name = "Suit"
    band = collar_band(suit, add_glow(suit), w, root)
    for obj in (suit, band):
        obj.modifiers.new("Armature", "ARMATURE").object = arm
    return suit, band


def backpack(suit: bpy.types.Object) -> tuple:
    """The backpack's back face (y) and bottom (z), measured on the rest mesh's middle."""
    co = G.vertices(suit.data)
    pack = co[(np.abs(co[:, 0]) < 0.15) & (co[:, 1] > BACKPACK_Y) & (co[:, 2] > HIP_Z)]
    return float(np.percentile(pack[:, 1], 95)), float(pack[:, 2].min())


def markers(arm: bpy.types.Object, suit: bpy.types.Object) -> None:
    """Empties on bones the game attaches to (their Godot -Z = the player's forward, see docstring)."""
    turn = rz(180)
    back, bottom = backpack(suit)
    print("BACKPACK back", round(back, 3), "bottom", round(bottom, 3))
    for name, bone, loc in (
        ("CargoRack", "UpperChest", (0, back + 0.03, bottom)),  # the tubes stand on it, up the backpack's back
        ("HosePort", "UpperChest", (0, back + 0.01, bottom + 0.13)),
        ("WeaponGrip", "RightHand", GRIP),  # placed in the aim pose
        ("ShieldGrip", "LeftLowerArm", _shield_grip()),  # placed in the shield's hold
    ):
        if name == "WeaponGrip":
            apply(arm, idle(0.0, aim=True))
        elif name == "ShieldGrip":
            apply(arm, ready_shield())
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "ARROWS"
        e.empty_display_size = 0.15
        C.link(e)
        e.parent = arm
        e.parent_type = "BONE"
        e.parent_bone = bone
        bpy.context.view_layer.update()
        e.matrix_world = T(loc, turn)
    rest_pose(arm)


# --- posing -----------------------------------------------------------------------------------------


def frame(direction: Vector, pole: Vector) -> Matrix:
    y = direction.normalized()
    z = (pole - y * pole.dot(y)).normalized()
    return Matrix((y.cross(z), y, z)).transposed()


def turn_between(rest_dir, rest_pole, dir_, pole) -> Matrix:
    """World rotation taking a bone from its rest direction (and pole side) to the given ones."""
    return frame(dir_, pole) @ frame(Vector(rest_dir), Vector(rest_pole)).transposed()


def two_bone(a: Vector, target: Vector, l1: float, l2: float, pole: Vector) -> tuple:
    """Joint and end positions of a two-bone chain from a reaching for target, bending towards pole."""
    d = target - a
    dist = min(max(d.length, 1e-4), (l1 + l2) * 0.999)
    u = d.normalized()
    w = (pole - u * pole.dot(u)).normalized()
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
    joint = a + (u * cos_a + w * sin_a) * l1
    return joint, a + u * dist


class Pose:
    """World-space rotations per bone (relative to the rest pose) plus the hips' offset; arms and legs by IK."""

    def __init__(self, hips_offset=(0, 0, 0), hips=I3):
        self.offset = Vector(hips_offset)
        self.w = {"Root": I3.copy(), "Hips": hips}

    def spine(self, spine=None, chest=None, upper=None, neck=None, head=None) -> None:
        last = self.w["Hips"]
        for name, rot in (("Spine", spine), ("Chest", chest), ("UpperChest", upper), ("Neck", neck), ("Head", head)):
            last = rot if rot is not None else last
            self.w[name] = last
        for side, _s in SIDES:
            self.w[f"{side}Shoulder"] = self.w["UpperChest"]

    def pos(self, bone: str) -> Vector:
        parent = PARENT[bone]
        if parent is None:
            return HEAD[bone].copy()
        p = self.pos(parent) + self.w[parent] @ (HEAD[bone] - HEAD[parent])
        return p + self.offset if bone == "Hips" else p

    def arm(self, side: str, wrist: Vector, pole: Vector, hand_dir: Vector, palm: Vector) -> None:
        s = 1.0 if side == "Left" else -1.0
        a = self.pos(f"{side}UpperArm")
        elbow, end = two_bone(a, Vector(wrist), UPPER_ARM_LEN, LOWER_ARM_LEN, Vector(pole))
        rest = (s, 0, 0)
        self.w[f"{side}UpperArm"] = turn_between(rest, (0, 1, 0), elbow - a, pole)
        self.w[f"{side}LowerArm"] = turn_between(rest, (0, 1, 0), end - elbow, pole)
        self.w[f"{side}Hand"] = turn_between(rest, (0, 0, -1), Vector(hand_dir), Vector(palm))

    def leg(self, side: str, ankle: Vector, pole: Vector, pitch: float = 0.0, yaw: float = 0.0) -> None:
        a = self.pos(f"{side}UpperLeg")
        knee, end = two_bone(a, Vector(ankle), UPPER_LEG_LEN, LOWER_LEG_LEN, Vector(pole))
        rest = (0, 0, -1)
        self.w[f"{side}UpperLeg"] = turn_between(rest, (0, -1, 0), knee - a, pole)
        self.w[f"{side}LowerLeg"] = turn_between(rest, (0, -1, 0), end - knee, pole)
        self.w[f"{side}Foot"] = rz(yaw) @ rx(pitch)
        self.w[f"{side}Toes"] = self.w[f"{side}Foot"]


def apply(arm: bpy.types.Object, pose: Pose) -> None:
    """Set the armature's pose bones from a Pose (local rotation q = R^-1 W_parent^-1 W R)."""
    for name, _h, _t, parent in BONES:
        pb = arm.pose.bones[name]
        rest = arm.data.bones[name].matrix_local.to_3x3()
        w = pose.w.get(name, I3)
        wp = pose.w.get(parent, I3) if parent else I3
        q = (rest.transposed() @ wp.transposed() @ w @ rest).to_quaternion()
        if pb.rotation_quaternion.dot(q) < 0:  # keep keys on one hemisphere (no flips between frames)
            q.negate()
        pb.rotation_quaternion = q
        pb.location = rest.transposed() @ pose.offset if name == "Hips" else Vector()


def rest_pose(arm: bpy.types.Object) -> None:
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


# --- clips ------------------------------------------------------------------------------------------

GRIP = Vector((-0.17, -0.3, 1.1))  # Harl's origin (pistol grip) in the aim pose; muzzle ~1.25 m up
FOREGRIP = GRIP + Vector((0, -0.35, 0.086))  # harl.glb "Foregrip"


def smooth(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


FOOT_X = 0.17  # the feet's distance from the middle when standing (the boots are wide)
WRIST_X_HANGING = 0.4  # the hanging arms' wrists, clear of the bulky hips


def relaxed_arms(p: Pose, swing: dict | None = None) -> None:
    for side, s in SIDES:
        f = (swing or {}).get(side, 0.0)
        wrist = Vector((s * WRIST_X_HANGING, -0.02 - f, 0.93 + 0.12 * abs(f)))
        p.arm(side, wrist, Vector((s * 0.3, 1, 0)), Vector((s * 0.15, -0.25, -1)), Vector((-s, 0, 0)))


def aim_upper(p: Pose) -> None:
    p.spine(chest=rz(-14), upper=rz(-34), neck=rz(-16), head=rz(-4))
    p.arm(
        "Right", GRIP + Vector((0, 0.04, 0.03)), Vector((-0.6, 0.4, -1)), Vector((0, -0.75, -0.65)), Vector((1, 0, 0))
    )
    p.arm(
        "Left",
        FOREGRIP + Vector((0.04, 0.05, -0.02)),
        Vector((0.5, 0.2, -1)),
        Vector((-0.45, -0.9, 0.1)),
        Vector((0, 0, 1)),
    )


def idle(t: float, aim: bool = False) -> Pose:
    breath = math.sin(2 * math.pi * t)
    p = Pose((0, 0, -0.035 - 0.004 * breath))
    p.spine(chest=rx(-1.2 * breath), upper=rx(-2.0 * breath), neck=I3, head=I3)
    if aim:
        aim_upper(p)
    else:
        relaxed_arms(p)
    for side, s in SIDES:
        p.leg(side, Vector((s * FOOT_X, -0.01, ANKLE_Z)), Vector((s * 0.15, -1, 0)), 0.0, s * 6)
    return p


def run(t: float, move: Vector) -> Pose:
    """One stride at phase t (0..1) moving along `move` (unit, armature XY; forward is -Y)."""
    stance, stride = 0.27, 0.78
    fwd = -move.y  # forward share of the movement
    side_share = move.x
    bob = math.cos(2 * math.pi * 2 * (t - stance / 2))
    yaw = 7 * math.sin(2 * math.pi * t) * fwd
    lean_axis = Vector((0, 0, 1)).cross(Vector((move.x, move.y, 0)))
    lean = Matrix.Rotation(math.radians(9 if fwd >= -0.5 else 5), 3, lean_axis)
    p = Pose(move * 0.05 + Vector((0, 0, -0.085 - 0.03 * bob)), rz(yaw) @ ry(-3 * side_share))
    p.spine(
        spine=lean @ rz(yaw * 0.4),
        chest=lean @ rz(-yaw * 0.2),
        upper=lean @ rz(-yaw * 0.6),
        neck=rz(-yaw * 0.3),
        head=I3,
    )
    swing = {}
    for side, s in SIDES:
        u = (t + (0.0 if side == "Left" else 0.5)) % 1.0
        if u < stance:
            w = u / stance
            x, lift, pitch = stride / 2 - stride * w, 0.0, 22 * smooth((w - 0.6) / 0.4)
        else:
            w = (u - stance) / (1 - stance)
            x = -stride / 2 + stride * (0.5 - 0.5 * math.cos(math.pi * w)) - 0.14 * math.sin(math.pi * w) * (1 - w)
            lift = 0.3 * math.sin(math.pi * min(w * 1.15, 1.0))
            pitch = 50 * math.sin(math.pi * w) * (1 - w) - 12 * smooth((w - 0.75) / 0.25)
        # Keep the feet apart when stepping sideways.
        base = Vector((s * (FOOT_X - 0.01 + 0.04 * abs(side_share)), 0.03 * s * side_share, 0))
        pitch *= 1 if fwd >= -0.5 else -0.6
        # The foot rolls over its toes (heel up) or its heel (toes up), not around the ankle.
        lift += 0.14 * math.sin(math.radians(max(pitch, 0))) + 0.07 * math.sin(math.radians(max(-pitch, 0)))
        ankle = base + Vector((move.x, move.y, 0)) * x + Vector((0, 0, ANKLE_Z + lift))
        p.leg(side, ankle, Vector((s * 0.15, -1, 0)), pitch)
        swing[side] = -0.5 * x * fwd
    swing = {"Left": swing["Right"], "Right": swing["Left"]}  # arms swing with the opposite leg
    relaxed_arms(p, swing)
    return p


def die(t: float) -> Pose:
    """Knees buckle (to 0.3), then the body tips forward and lies face down (1.0)."""
    k = smooth(t / 0.3)
    f = smooth((t - 0.25) / 0.6)
    lean = rx(20 * k + 70 * f)
    hips = Vector((0, -0.05 * k - 0.3 * f, -0.4 * k - 0.32 * f))
    p = Pose(hips, rx(10 * k + 70 * f))
    p.spine(spine=lean, chest=lean, upper=lean, neck=lean @ rz(25 * f), head=lean @ rz(40 * f))
    for side, s in SIDES:
        ankle = Vector((s * FOOT_X, -0.01 + 0.45 * f, ANKLE_Z - 0.02 * f))
        p.leg(side, ankle, Vector((s * 0.2, -1 + 0.6 * f, -1.6 * f)), 165 * f)  # ends with the soles up
        wrist = Vector((s * (WRIST_X_HANGING + 0.12 * f), -0.05 - 0.75 * f, 0.93 - 0.85 * f))
        p.arm(
            side,
            wrist,
            Vector((s * 0.5, 1 - f, 0.5 * f)),
            Vector((s * 0.2, -0.3 - f, -1 + f)),
            Vector((-s * (1 - f), 0, -f)),
        )
    return p


# --- melee ------------------------------------------------------------------------------------------
# A weapon is placed by its grip (the WeaponGrip marker): hold() puts the right hand there, turned so the weapon
# points along `forward` with its top along `up` (armature space). Points on a weapon are given in its scene's axes
# (Godot: x right, y up, -z forward) and turned into the armature's by weapon_point().

GRIP_TURN = rz(180)  # the marker's rotation (its +Y is the weapon's forward, its +Z its top)
FIST = 0.065  # wrist to the middle of the fist
ATTACK_WIND, ATTACK_STROKE, ATTACK_HOLD = 2, 6, 6  # frames of an attack clip: wind-up, stroke, staying at the end
ATTACK_FRAMES = ATTACK_WIND + ATTACK_STROKE + ATTACK_HOLD
SHAKE_FRAMES = 12  # one loop of a braced tool's tremor
HAMMER_LOWER_HAND = (0.0, 0.0, 0.11)  # Dray's haft, behind the right hand
SIDE_HANDLE = (-0.2, 0.04, -0.06)  # Jag's and Auger's handle for the left hand


def _grip_in_hand() -> tuple:
    """The grip's offset and rotation in the right hand's rest frame (the marker is placed in the aim pose)."""
    p = idle(0.0, aim=True)
    h = p.w["RightHand"]
    return h.transposed() @ (GRIP - p.pos("RightHand")), h.transposed() @ GRIP_TURN


GRIP_OFFSET, GRIP_REST = _grip_in_hand()


def weapon_frame(forward, up) -> Matrix:
    f = Vector(forward).normalized()
    u = Vector(up)
    u = (u - f * u.dot(f)).normalized()
    return Matrix((f.cross(u), f, u)).transposed()


def weapon_point(grip: Vector, frame_: Matrix, local) -> Vector:
    gx, gy, gz = local
    return grip + frame_ @ Vector((gx, -gz, gy))


def hold(p: Pose, grip, forward, up, pole) -> Matrix:
    """Puts the right hand on the weapon's grip at `grip`; returns the weapon's frame."""
    g = weapon_frame(forward, up)
    h = g @ GRIP_REST.transposed()
    p.arm("Right", Vector(grip) - h @ GRIP_OFFSET, Vector(pole), Vector((-1, 0, 0)), Vector((0, 0, -1)))
    p.w["RightHand"] = h
    return g


def left_on(p: Pose, point: Vector, hand_dir, palm, pole) -> None:
    """Puts the left fist around `point`, the hand pointing along hand_dir."""
    d = Vector(hand_dir).normalized()
    p.arm("Left", point - d * FIST, Vector(pole), d, Vector(palm))


def stance(lean: float = 0.0, turn: float = 0.0) -> Pose:
    """The idle legs with the upper body leaning forward and turned left (degrees, spread over the spine)."""
    p = idle(0.0)
    tilt = lambda share: rz(turn * share) @ rx(lean * share)
    p.spine(spine=tilt(0.3), chest=tilt(0.6), upper=tilt(1.0), neck=rz(-turn * 0.6), head=I3)
    return p


def lerp(a, b, t: float):
    return a + (b - a) * t


def guard(p: Pose, raise_: float = 1.0) -> None:
    """The free left arm up in front of the chest."""
    wrist = lerp(Vector((0.3, -0.06, 1.0)), Vector((0.2, -0.3, 1.28)), raise_)
    p.arm("Left", wrist, Vector((1, 0.4, -1)), Vector((-0.2, -0.3, 1)), Vector((-1, -0.2, 0)))


def ready_blade() -> Pose:
    """Riven: one-handed, the blade low in front pointing forward and up, the left arm up as a guard."""
    p = stance(4, -12)
    hold(p, (-0.24, -0.34, 1.0), (0.12, -0.75, 0.6), (-1, 0, 0), (-0.6, 0.6, -1))
    guard(p)
    return p


def slash(t: float, back: bool = False) -> Pose:
    """Riven's slash across the front, from the right to the left (back: the other way), edge first."""
    w, s = ATTACK_WIND, ATTACK_STROKE
    f = t * (w + s + ATTACK_HOLD)
    a0, a1 = (-65.0, 45.0) if not back else (45.0, -65.0)
    if f < w:  # cocked a little further back
        deg = lerp(a0, a0 - 0.1 * (a1 - a0), smooth(f / w))
        u = 0.0
    else:
        u = 1 - (1 - min((f - w) / s, 1.0)) ** 3  # fast out of the wind-up, slowing at the end
        deg = lerp(a0 - 0.1 * (a1 - a0), a1, u)
    a = math.radians(deg)
    p = stance(8 + 6 * u, deg * 0.4)
    side = Vector((math.sin(a), -math.cos(a), 0))
    grip = Vector((-0.08, -0.08, 1.16)) + side * 0.48 + Vector((0, 0, 0.1 - 0.16 * u))
    edge_up = 1.0 if back else -1.0
    hold(p, grip, side + Vector((0, 0, -0.12)), (0, 0, edge_up), (-0.5 * edge_up - 0.2, 0.5, -1))
    guard(p, 0.6)
    return p


def ready_hammer() -> Pose:
    """Dray: two-handed, the haft across the body, the head up by the right shoulder."""
    p = stance(4, -10)
    g = hold(p, (-0.08, -0.3, 1.02), (-0.55, 0.3, 0.75), (0.1, -1, 0.2), (-0.6, 0.6, -1))
    left_on(
        p,
        weapon_point(Vector((-0.08, -0.3, 1.02)), g, HAMMER_LOWER_HAND),
        (-0.6, 0.1, -0.1),
        (0, 0.4, -1),
        (1, 0.3, -1),
    )
    return p


def overhead(t: float) -> Pose:
    """Dray's blow: raised over the right shoulder, then down in front, both hands on the haft."""
    w, s = ATTACK_WIND, ATTACK_STROKE
    total = w + s + ATTACK_HOLD
    f = t * total
    if f < w:  # raise
        u = smooth(f / w)
        phi, lean = lerp(-15.0, -40.0, u), lerp(4.0, -8.0, u)
    else:
        u = 1 - (1 - min((f - w) / s, 1.0)) ** 2  # down at once: the hit lands as the attack starts
        phi, lean = lerp(-40.0, 145.0, u), lerp(-8.0, 24.0, u)
    r = math.radians(phi)
    p = stance(lean, -10 + 6 * max(phi, 0) / 145)
    forward = Vector((-0.12, -math.sin(r), math.cos(r)))
    up = Vector((0, -math.cos(r), -math.sin(r)))
    grip = Vector((-0.1, -0.06, 1.3)) + Vector((0, -math.sin(r), math.cos(r))) * 0.32 + Vector((0, -0.12, 0))
    g = hold(p, grip, forward, up, (-0.8, 0.3, -1))
    left_on(p, weapon_point(grip, g, HAMMER_LOWER_HAND), (-1, 0, 0), up, (1, 0.4, -1))
    return p


def brace(push: float = 0.0, lean: float = 0.0, shake: Vector | None = None) -> Pose:
    """Jag and Auger: two-handed at the hip, the left hand on the side handle; push moves it forward (m)."""
    p = stance(6 + lean, -14 + 0.25 * lean)
    grip = Vector((-0.2, -0.32 - push, 0.98 + 0.4 * push)) + (shake or Vector())
    g = hold(p, grip, (0.02, -1, -0.04), (0, 0, 1), (-0.8, 0.5, -1))
    left_on(p, weapon_point(grip, g, SIDE_HANDLE), (0, -0.4, -1), (-1, 0, 0), (1, 0.3, -1))
    return p


def thrust(t: float) -> Pose:
    """Auger's thrust: pulled back a little, pushed out with the body leaning in, staying out."""
    w, s = ATTACK_WIND, ATTACK_STROKE
    f = t * (w + s + ATTACK_HOLD)
    if f < w:
        return brace(-0.06 * smooth(f / w))
    u = 1 - (1 - min((f - w) / s, 1.0)) ** 2
    return brace(lerp(-0.06, 0.4, u), 16 * u)


# Clout: the hand grips the gauntlet like a pistol grip, so the weapon's forward is the fist's direction turned up
# by the grip's angle (the hand points 41 degrees below a gun's forward, see aim_upper()).
FIST_TILT = math.radians(41)


def fist(p: Pose, wrist_at, punch, pole) -> Matrix:
    """Puts Clout's grip at `wrist_at` with the fist (and the forearm behind it) pointing along `punch`."""
    d = Vector(punch).normalized()
    side = d.cross(Vector((0, 0, 1))).normalized()
    up = side.cross(d).normalized()
    forward = d * math.cos(FIST_TILT) + up * math.sin(FIST_TILT)
    top = up * math.cos(FIST_TILT) - d * math.sin(FIST_TILT)
    return hold(p, wrist_at, forward, top, pole)


def ready_fist() -> Pose:
    """Clout: the gauntlet raised in front of the chest, the left hand open in front as a guard."""
    p = stance(6, -12)
    fist(p, (-0.16, -0.34, 1.26), (0.1, -1, 0.12), (-0.8, 0.2, -1))
    guard(p, 0.9)
    return p


def cocked(shake: Vector | None = None) -> Pose:
    """Clout drawn back for a charged punch: the fist by the right shoulder, the body turned away."""
    p = stance(2, -32)
    fist(p, Vector((-0.26, 0.02, 1.24)) + (shake or Vector()), (0.25, -1, 0.1), (-0.9, 0.6, -1))
    guard(p, 1.0)
    return p


def punch(t: float) -> Pose:
    """Clout's punch: a short pull back, then straight out with the body turning in, staying out."""
    w, s = ATTACK_WIND, ATTACK_STROKE
    f = t * (w + s + ATTACK_HOLD)
    start, back, out = Vector((-0.16, -0.34, 1.26)), Vector((-0.2, -0.22, 1.25)), Vector((-0.06, -0.66, 1.32))
    if f < w:
        u = smooth(f / w)
        at, lean, turn = lerp(start, back, u), 6.0, lerp(-12.0, -18.0, u)
    else:
        u = 1 - (1 - min((f - w) / s, 1.0)) ** 3  # out at once: the hit lands as the attack starts
        at, lean, turn = lerp(back, out, u), lerp(6.0, 14.0, u), lerp(-18.0, 16.0, u)
    p = stance(lean, turn)
    fist(p, at, (0.04, -1, 0.06), (-0.7, 0.3, -1))
    guard(p, 1.0 - 0.4 * u if f >= w else 1.0)
    return p


# Mantle: the plate on the left forearm, the forearm across the chest; the right fist behind it.
SHIELD_WRIST = Vector((-0.04, -0.42, 1.22))


def ready_shield(push: float = 0.0, lean: float = 0.0, turn: float = 0.0) -> Pose:
    """Mantle: the left forearm across the chest with the plate facing out, the right fist behind it; push moves
    both forward (m)."""
    p = stance(6 + lean, 10 + turn)
    ahead = Vector((0, -push, 0.04 * push))
    p.arm("Left", SHIELD_WRIST + ahead, Vector((1, 0.4, -0.5)), Vector((-1, -0.1, 0.1)), Vector((0, 1, 0)))
    p.arm(
        "Right",
        Vector((-0.14, -0.3, 1.14)) + ahead * 0.8,
        Vector((-1, 0.4, -1)),
        Vector((0.3, -0.8, 0.3)),
        Vector((1, 0, 0)),
    )
    return p


def _shield_grip() -> Vector:
    """The plate's middle on the forearm in the shield's hold, a little in front of it."""
    p = ready_shield()
    elbow, wrist = p.pos("LeftLowerArm"), p.pos("LeftHand")
    return elbow.lerp(wrist, 0.55) + Vector((0, -0.06, 0))


def bash(t: float) -> Pose:
    """Mantle's bash: pulled in a little, then a shove forward with the shoulder, staying out."""
    w, s = ATTACK_WIND, ATTACK_STROKE
    f = t * (w + s + ATTACK_HOLD)
    if f < w:
        return ready_shield(-0.06 * smooth(f / w), 0.0, 4 * smooth(f / w))
    u = 1 - (1 - min((f - w) / s, 1.0)) ** 3
    return ready_shield(lerp(-0.06, 0.28, u), 14 * u, lerp(4.0, 14.0, u))


def tremor(t: float) -> Vector:
    """A loop of small jolts (m), the same at 0 and 1."""
    a = 2 * math.pi * t
    return Vector((0.006 * math.sin(3 * a) + 0.003 * math.sin(7 * a), 0.006 * math.sin(5 * a), 0.008 * math.cos(4 * a)))


MOVES = {
    "Run": Vector((0, -1, 0)),
    "RunBack": Vector((0, 1, 0)),
    "StrafeLeft": Vector((1, 0, 0)),
    "StrafeRight": Vector((-1, 0, 0)),
}
CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (60, lambda t: idle(t)),
    **{name: (RUN_FRAMES, lambda t, m=m: run(t, m)) for name, m in MOVES.items()},
    "Aim": (1, lambda t: idle(0.0, aim=True)),
    "Die": (36, die),
    "ReadyBlade": (1, lambda t: ready_blade()),
    "ReadyHammer": (1, lambda t: ready_hammer()),
    "Brace": (1, lambda t: brace()),
    "Slash": (ATTACK_FRAMES, slash),
    "SlashBack": (ATTACK_FRAMES, lambda t: slash(t, back=True)),
    "Overhead": (ATTACK_FRAMES, overhead),
    "Thrust": (ATTACK_FRAMES, thrust),
    "Cut": (SHAKE_FRAMES, lambda t: brace(0.05, 8, tremor(t))),
    "Drill": (SHAKE_FRAMES, lambda t: brace(0.4, 16, tremor(t))),
    "ReadyFist": (1, lambda t: ready_fist()),
    "ReadyShield": (1, lambda t: ready_shield()),
    "Punch": (ATTACK_FRAMES, punch),
    "Bash": (ATTACK_FRAMES, bash),
    "Cock": (SHAKE_FRAMES, lambda t: cocked(tremor(t) * 0.6)),
}


def bake_clips(arm: bpy.types.Object) -> None:
    ad = arm.animation_data_create()
    for name, (frames, fn) in CLIPS.items():
        ad.action = None
        for f in range(frames + 1):
            apply(arm, fn(f / frames if frames else 0.0))
            for pb in arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                if pb.name == "Hips":
                    pb.keyframe_insert("location", frame=f, group=pb.name)
        act = ad.action
        act.name = name
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        track.mute = True
        ad.action = None
    rest_pose(arm)


# --- preview ----------------------------------------------------------------------------------------


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(30, 30, 0))
    shots = []
    poses = [("aim", idle(0.0, aim=True)), ("idle", idle(0.25))]
    poses += [(f"run{i}", run(i / 4, MOVES["Run"])) for i in range(4)]
    poses += [
        ("back", run(0.1, MOVES["RunBack"])),
        ("strafeL", run(0.1, MOVES["StrafeLeft"])),
        ("strafeR", run(0.6, MOVES["StrafeRight"])),
    ]
    poses += [("die3", die(0.35)), ("die10", die(1.0))]
    target = (0, 0, 0.95)
    for name, pose in poses:
        apply(arm, pose)
        bpy.context.view_layer.update()
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.62)
        shots.append(path)
    apply(arm, idle(0.0, aim=True))
    for view, zoom in (("iso", 0.42), ("back", 0.6)):
        path = OUT / "wip" / f"{tag}_aim_{view}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_front.png", Vector((0, -3.2, 1.2)), (0, 0, 0.95), 40, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_front.png")
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=5, tile=384)
    rest_pose(arm)
    return shots


STAND_INS = {  # rough weapons for the clip previews: boxes (center, size) in the weapon scenes' axes
    "blade": [
        ((0, 0, 0.02), (0.05, 0.05, 0.3)),
        ((0, 0, -0.16), (0.18, 0.06, 0.06)),
        ((0, 0, -0.69), (0.095, 0.014, 1)),
    ],
    "hammer": [((0, 0.05, -0.3), (0.056, 0.056, 0.85)), ((0, 0.05, -0.72), (0.18, 0.4, 0.18))],
    # Clout's gauntlet: the fist's block along the hand (41 degrees below the weapon's forward), the sleeve behind it.
    "fist": [((0, -0.04, -0.05), (0.13, 0.12, 0.12)), ((0, 0.12, 0.14), (0.14, 0.14, 0.24))],
    "shield": [((0, 0, 0), (0.42, 0.52, 0.05))],
    "tool": [
        ((0, 0, 0.12), (0.05, 0.05, 0.22)),
        ((0, 0.04, -0.06), (0.17, 0.17, 0.26)),
        ((0, 0.04, -0.5), (0.14, 0.14, 0.5)),
        (SIDE_HANDLE, (0.2, 0.04, 0.04)),
    ],
}
STAND_IN_EDGE = ((0.052, 0, -0.7), (0.012, 0.018, 0.98))  # Riven's edge, bright
PREVIEW_CLIPS = {  # clip: stand-in
    "ReadyBlade": "blade",
    "Slash": "blade",
    "SlashBack": "blade",
    "ReadyHammer": "hammer",
    "Overhead": "hammer",
    "Brace": "tool",
    "Thrust": "tool",
    "Cut": "tool",
    "Drill": "tool",
    "ReadyFist": "fist",
    "Punch": "fist",
    "Cock": "fist",
    "ReadyShield": "shield",
    "Bash": "shield",
}


def stand_ins() -> dict:
    out = {}
    for kind, boxes in STAND_INS.items():
        grip = bpy.data.objects["ShieldGrip" if kind == "shield" else "WeaponGrip"]
        parts = boxes + ([STAND_IN_EDGE] if kind == "blade" else [])
        objs = []
        for i, ((x, y, z), (sx, sy, sz)) in enumerate(parts):
            obj = bpy.data.objects.new(f"StandIn_{kind}{i}", _box((sx, sz, sy)))
            C.link(obj)
            obj.parent = grip
            obj.location = (x, -z, y)
            obj.color = (1.0, 0.85, 0.3, 1) if (kind == "blade" and i == len(parts) - 1) else (0.75, 0.35, 0.1, 1)
            objs.append(obj)
        out[kind] = objs
    return out


def _box(size) -> bpy.types.Mesh:
    sx, sy, sz = (v / 2 for v in size)
    verts = [(x * sx, y * sy, z * sz) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh = bpy.data.meshes.new("StandIn")
    mesh.from_pydata(verts, [], faces)
    return mesh


def preview_clips(arm: bpy.types.Object, only: list) -> None:
    """Workbench contact sheets of the melee clips (rows: a view each, columns: frames)."""
    C.preview_scene(crystals=False, figure_location=(30, 30, 0))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x = scene.render.resolution_y = 320
    for name in ("Suit", "SuitLight"):
        bpy.data.objects[name].color = (0.35, 0.38, 0.42, 1) if name == "Suit" else (0.3, 1, 0.45, 1)
    weapons = stand_ins()
    views = (("hero", 0.62), ("iso", 0.42), ("top", 0.0))
    close = (("hero", 0.3), ("back", 0.3), ("iso", 0.22))
    for clip, kind in PREVIEW_CLIPS.items():
        if only and clip not in only:
            continue
        for k, objs in weapons.items():
            for obj in objs:
                obj.hide_render = k != kind
        frames, fn = CLIPS[clip]
        steps = list(range(0, frames + 1, max(1, frames // 7))) if frames > 1 else [0]
        shots = []
        for view, zoom in views if frames > 1 else close:
            for f in steps:
                apply(arm, fn(f / frames if frames else 0.0))
                bpy.context.view_layer.update()
                path = OUT / "clips" / f"{clip}_{view}{zoom}_{f:02d}.png"
                if view == "top":
                    cam = C._camera("custom")
                    cam.data.lens = 40
                    cam.location = Vector((0, -0.4, 6.5))
                    cam.rotation_euler = (0, 0, 0)
                    scene.camera = cam
                else:
                    C._camera(view, (0, -0.2, 1.1), zoom)
                C._write_render(path)
                shots.append(path)
        C.contact_sheet(shots, OUT / "clips" / f"sheet_{clip}.png", cols=len(steps) if frames > 1 else 3, tile=320)
    rest_pose(arm)


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = build_skeleton(root)
    suit, _band = build_suit(root, arm)
    markers(arm, suit)
    print("STATS", C.stats(), C.tris_per_object())
    if MODE == "clips":
        preview_clips(arm, ARGV[1:])
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        bake_clips(arm)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "player_procedural.blend")
        C.export_glb(OUT / "player_draft.glb")


main()
