"""Player: a bulky, dark armored suit with a glowing collar band (concept: player_batch2_rimlit), rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/player/source/player_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/player/source/player_build.py final      # renders + player_procedural.blend
    tools/blender.sh assets/player/source/player_build.py clips [Slash ...]  # workbench sheets of the melee clips

Everything it writes goes to tmp/assets/player/; player_bake.py turns player_procedural.blend into the game asset.

Layout (Blender Z-up meters; the character faces -Y, its left is +X; glTF turns -Y into Godot's +Z, so the game
turns the model by 180 degrees to face the player's -Z). T-pose rest, feet on the ground at the origin, 1.8 m.

Skeleton "Skeleton": Godot's humanoid bone names (SkeletonProfileHumanoid, without fingers), so the animations
could be retargeted later. Meshes: "Suit" (one skinned object, rigid parts weighted 100 % to their bone, the
undersuit limbs blended across the joints) and "SuitLight" (the collar band, constant emissive; the game drives its
color by health). Empties on bones: "WeaponGrip" (RightHand, Harl's origin in the aim pose; Godot axes:
-Z forward), "CargoRack" and "HosePort" (UpperChest, on the backpack).

Animations (one action per clip, each in its own NLA track, all at 30 fps): "Idle" (loop), "Run", "RunBack",
"StrafeLeft", "StrafeRight" (loops, authored at RUN_SPEED: the game scales their speed by the actual one),
"Aim" (upper-body pose holding Harl; the game layers it over the legs), "Die" (once, ends lying face
down) and the melee clips, upper body only too: the holds "ReadyBlade" (Riven), "ReadyHammer" (Dray) and "Brace"
(Jag, Auger: two-handed at the hip), the attacks "Slash", "SlashBack", "Overhead" and "Thrust" (wind-up, a stroke of
ATTACK_STROKE frames the game fits to the attack's time, staying at the end) and the braced tool's loops "Cut"
(leaning in, shaking) and "Drill" (out at the thrust's end, shaking). Poses are built from world-space rotations per bone and two-bone IK for arms and legs, then converted to
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
from mathutils import Matrix, Vector

import common as C
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

SHOULDER_X, ELBOW_X, WRIST_X, HAND_X, ARM_Z = 0.20, 0.52, 0.80, 0.93, 1.44
HIP_X, HIP_Z, KNEE_Z, ANKLE_Z = 0.11, 0.94, 0.52, 0.10
HIPS_Z = 0.96

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, 0.2, 0), None),
    ("Hips", (0, 0, HIPS_Z), (0, 0, 1.08), "Root"),
    ("Spine", (0, 0, 1.08), (0, 0, 1.20), "Hips"),
    ("Chest", (0, 0, 1.20), (0, 0, 1.32), "Spine"),
    ("UpperChest", (0, 0, 1.32), (0, 0, 1.50), "Chest"),
    ("Neck", (0, 0, 1.50), (0, 0, 1.58), "UpperChest"),
    ("Head", (0, 0, 1.58), (0, 0, 1.82), "Neck"),
]
SIDES = (("Left", 1.0), ("Right", -1.0))
for _side, _s in SIDES:
    BONES += [
        (f"{_side}Shoulder", (_s * 0.04, 0, ARM_Z), (_s * SHOULDER_X, 0, ARM_Z), "UpperChest"),
        (f"{_side}UpperArm", (_s * SHOULDER_X, 0, ARM_Z), (_s * ELBOW_X, 0, ARM_Z), f"{_side}Shoulder"),
        (f"{_side}LowerArm", (_s * ELBOW_X, 0, ARM_Z), (_s * WRIST_X, 0, ARM_Z), f"{_side}UpperArm"),
        (f"{_side}Hand", (_s * WRIST_X, 0, ARM_Z), (_s * HAND_X, 0, ARM_Z), f"{_side}LowerArm"),
        (f"{_side}UpperLeg", (_s * HIP_X, 0, HIP_Z), (_s * HIP_X, 0, KNEE_Z), "Hips"),
        (f"{_side}LowerLeg", (_s * HIP_X, 0, KNEE_Z), (_s * HIP_X, 0, ANKLE_Z), f"{_side}UpperLeg"),
        (f"{_side}Foot", (_s * HIP_X, 0, ANKLE_Z), (_s * HIP_X, -0.12, 0.03), f"{_side}LowerLeg"),
        (f"{_side}Toes", (_s * HIP_X, -0.12, 0.03), (_s * HIP_X, -0.21, 0.03), f"{_side}Foot"),
    ]
HEAD = {n: Vector(h) for n, h, _t, _p in BONES}
PARENT = {n: p for n, _h, _t, p in BONES}
BONE_INDEX = {n: i for i, (n, *_r) in enumerate(BONES)}
UPPER_ARM_LEN = ELBOW_X - SHOULDER_X
LOWER_ARM_LEN = WRIST_X - ELBOW_X
UPPER_LEG_LEN = HIP_Z - KNEE_Z
LOWER_LEG_LEN = KNEE_Z - ANKLE_Z


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


# --- mesh -------------------------------------------------------------------------------------------


class Skin(C.Part):
    """Part with vertex weights: rigid(verts, bone) or blend(verts, bone_a, bone_b, p0, p1) (bone_a at p0 fading
    to bone_b at p1, along the segment)."""

    def __init__(self, name: str, mats: list, bevel=(0.006, 2)):
        super().__init__(name, mats, bevel)
        self.dl = self.bm.verts.layers.deform.verify()

    def rigid(self, verts, bone: str):
        for v in verts:
            v[self.dl].clear()
            v[self.dl][BONE_INDEX[bone]] = 1.0
        return verts

    def blend(self, verts, a: str, b: str, p0, p1):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        for v in verts:
            t = min(max((v.co - p0).dot(d) / d.length_squared, 0.0), 1.0)
            t = t * t * (3 - 2 * t)
            v[self.dl].clear()
            v[self.dl][BONE_INDEX[a]] = 1.0 - t
            if t > 0:
                v[self.dl][BONE_INDEX[b]] = t
        return verts

    def tube(self, p0, p1, r0, r1, seg=12, rings=6, mi=0, squash=(1.0, 1.0), hint=(0, 0, 1)):
        """Capped tube from p0 (radius r0) to p1 (r1) with `rings` loops for smooth bending; squash scales the
        cross-section along the hint axis and the other one."""
        p0, p1 = Vector(p0), Vector(p1)
        m = C.basis(p1 - p0, Vector(hint))
        loops = []
        for i in range(rings + 1):
            t = i / rings
            c = p0.lerp(p1, t)
            r = r0 + (r1 - r0) * t
            loops.append(
                [
                    self.bm.verts.new(c + m @ Vector((math.cos(a) * r * squash[0], math.sin(a) * r * squash[1], 0)))
                    for a in (2 * math.pi * k / seg for k in range(seg))
                ]
            )
        faces = []
        for a, b in itertools.pairwise(loops):
            for k in range(seg):
                faces.append(self.bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k])))
        faces.append(self.bm.faces.new(list(reversed(loops[0]))))
        faces.append(self.bm.faces.new(loops[-1]))
        for f in faces:
            f.normal_update()
        return self._tag([v for lp in loops for v in lp], mi)

    def finish(self, parent) -> bpy.types.Object:
        obj = super().finish(parent)
        for name, *_r in BONES:
            obj.vertex_groups.new(name=name)
        return obj


def mat_fabric(name: str = "Undersuit") -> bpy.types.Material:
    """Dark padded fabric: fine ribbing in the bump, slight color variation."""
    mat, nt, bsdf = C._new_material(name)
    noise = C._noise(nt, 30.0, 4.0, 0.6)
    nt.links.new(
        C._mix_color(nt, noise.outputs["Fac"], (0.022, 0.024, 0.027), (0.045, 0.045, 0.048)), bsdf.inputs["Base Color"]
    )
    bsdf.inputs["Roughness"].default_value = 0.88
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 90.0
    nt.links.new(nt.nodes.new("ShaderNodeTexCoord").outputs["Object"], wave.inputs["Vector"])
    C._bump(nt, bsdf, wave.outputs["Fac"], 0.25, 0.002)
    return mat


def mat_visor(name: str = "Visor") -> bpy.types.Material:
    mat, _nt, bsdf = C._new_material(name)
    bsdf.inputs["Base Color"].default_value = (0.03, 0.022, 0.016, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.7
    bsdf.inputs["Roughness"].default_value = 0.08
    return mat


def build_suit(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    armor = C.mat_painted_metal("Armor", (0.07, 0.075, 0.082), wear=0.35, grime=0.55, roughness=0.5)
    C.bevel_wear(armor, lo=0.01, hi=0.05, radius=0.006)
    fabric = mat_fabric()
    rubber = C.mat_rubber("Rubber", (0.02, 0.02, 0.022))
    visor = mat_visor()
    trim = C.mat_bare_metal("Trim", (0.32, 0.2, 0.11), roughness=0.45)
    light = C.mat_emissive("ChestLight", (0.15, 0.45, 1.0), 6.0)
    ARMOR, FABRIC, RUBBER, VISOR, TRIM, LIGHT = range(6)
    sk = Skin("Suit", [armor, fabric, rubber, visor, trim, light])
    R = sk.rigid

    # Head: helmet shell, visor bulging out of the front, ear discs, crest.
    R(sk.sphere((0, 0.01, 1.67), 0.165, 20, 10, scale=(1.0, 1.05, 1.0)), "Head")
    R(sk.sphere((0, -0.045, 1.655), 0.14, 20, 10, scale=(0.98, 0.9, 0.82), mi=VISOR), "Head")
    R(sk.box((0, -0.005, 1.83), (0.05, 0.26, 0.025), rx(-8)), "Head")
    for s in (1, -1):
        R(sk.cyl((s * 0.16, 0.0, 1.66), 0.055, 0.05, 16, ry(90), mi=TRIM), "Head")
        R(sk.cyl((s * 0.18, 0.0, 1.66), 0.03, 0.03, 12, ry(90), mi=ARMOR), "Head")
    R(sk.cyl((0, 0.0, 1.565), 0.13, 0.06, 20), "Neck")  # neck seal under the collar

    # Collar ring (the light band is its own object), chest plate, abdomen plates, backpack.
    R(sk.cyl((0, 0.0, 1.52), 0.2, 0.07, 24, mi=ARMOR, r2=0.17), "UpperChest")
    R(sk.box((0, -0.02, 1.37), (0.46, 0.3, 0.24)), "UpperChest")
    R(sk.sphere((0, -0.07, 1.36), 0.22, 20, 10, scale=(1.0, 0.45, 0.6)), "UpperChest")
    R(sk.cyl((0.09, -0.175, 1.39), 0.05, 0.03, 16, rx(90), mi=TRIM), "UpperChest")
    R(sk.cyl((0.09, -0.19, 1.39), 0.032, 0.012, 16, rx(90), mi=LIGHT), "UpperChest")
    R(sk.box((-0.09, -0.165, 1.33), (0.12, 0.03, 0.06), mi=TRIM), "UpperChest")
    for s in (1, -1):  # straps over the shoulders
        R(sk.box((s * 0.13, -0.02, 1.47), (0.07, 0.33, 0.03), mi=TRIM), "UpperChest")
    R(sk.tube((0, 0, 1.19), (0, 0, 1.32), 0.165, 0.18, 16, 2, FABRIC, (1.15, 0.85), hint=(1, 0, 0)), "Chest")
    R(sk.box((0, -0.1, 1.27), (0.3, 0.06, 0.09)), "Chest")
    R(sk.box((0, -0.095, 1.18), (0.26, 0.06, 0.08)), "Spine")
    R(sk.tube((0, 0, 1.03), (0, 0, 1.19), 0.15, 0.16, 16, 2, FABRIC, (1.15, 0.85), hint=(1, 0, 0)), "Spine")
    # Backpack: shell, frame rails (the game hangs the cargo canisters below it), status lights.
    R(sk.box((0, 0.2, 1.32), (0.38, 0.16, 0.36)), "UpperChest")
    R(sk.box((0, 0.21, 1.52), (0.3, 0.12, 0.06), mi=RUBBER), "UpperChest")
    for s in (1, -1):
        R(sk.box((s * 0.17, 0.25, 1.17), (0.03, 0.05, 0.62), mi=TRIM), "UpperChest")
        R(sk.box((s * 0.12, 0.285, 1.42), (0.04, 0.012, 0.03), mi=LIGHT), "UpperChest")
    R(sk.box((0, 0.27, 0.9), (0.37, 0.07, 0.03), mi=TRIM), "UpperChest")

    # Belt and hips.
    R(sk.tube((0, 0, 0.97), (0, 0, 1.05), 0.185, 0.185, 20, 1, RUBBER, (1.05, 0.82), hint=(1, 0, 0)), "Hips")
    R(sk.box((0, -0.16, 1.01), (0.09, 0.03, 0.06), mi=TRIM), "Hips")
    R(sk.box((0, 0, 0.92), (0.32, 0.24, 0.12), mi=FABRIC), "Hips")
    for s in (1, -1):
        R(sk.box((s * 0.12, -0.15, 0.99), (0.08, 0.05, 0.09), mi=RUBBER), "Hips")  # pouches
        R(sk.box((s * 0.2, 0.0, 0.92), (0.06, 0.2, 0.17), ry(s * 12)), "Hips")  # hip plates

    for side, s in SIDES:
        b = lambda n, side=side: f"{side}{n}"
        # Shoulder: pauldron over the joint.
        R(sk.sphere((s * 0.27, 0.0, 1.47), 0.13, 16, 8, scale=(1.05, 1.0, 0.8)), b("UpperArm"))
        R(sk.cyl((s * 0.3, 0.0, 1.425), 0.13, 0.025, 16, ry(s * 18), mi=TRIM), b("UpperArm"))
        # Upper arm: undersuit (blends into the forearm across the elbow), bicep plate, elbow pad.
        sh, el, wr = Vector((s * 0.2, 0, ARM_Z)), Vector((s * ELBOW_X, 0, ARM_Z)), Vector((s * WRIST_X, 0, ARM_Z))
        sk.blend(
            sk.tube(sh, el + Vector((s * 0.06, 0, 0)), 0.07, 0.06, 12, 6, FABRIC),
            b("UpperArm"),
            b("LowerArm"),
            el - Vector((s * 0.05, 0, 0)),
            el + Vector((s * 0.04, 0, 0)),
        )
        R(sk.box((s * 0.4, 0, ARM_Z + 0.01), (0.16, 0.13, 0.1)), b("UpperArm"))
        R(sk.sphere(el + Vector((0, 0.05, 0)), 0.06, 12, 6, scale=(1, 0.8, 1)), b("LowerArm"))
        # Forearm: gauntlet with a trim band.
        R(
            sk.tube(
                el + Vector((s * 0.04, 0, 0)), wr - Vector((s * 0.01, 0, 0)), 0.075, 0.065, 14, 1, ARMOR, (1.0, 0.85)
            ),
            b("LowerArm"),
        )
        R(sk.cyl(wr - Vector((s * 0.06, 0, 0)), 0.071, 0.025, 14, ry(90), mi=TRIM), b("LowerArm"))
        # Hand: a fist in a heavy glove, thumb.
        R(sk.box((s * 0.865, 0, ARM_Z - 0.005), (0.12, 0.095, 0.07), mi=RUBBER), b("Hand"))
        R(sk.box((s * 0.84, -0.055, ARM_Z - 0.01), (0.06, 0.03, 0.04), rz(s * 20), mi=RUBBER), b("Hand"))
        R(sk.tube(wr - Vector((s * 0.02, 0, 0)), wr + Vector((s * 0.03, 0, 0)), 0.05, 0.05, 12, 1, RUBBER), b("Hand"))
        # Leg: thigh undersuit (blends into the shin across the knee), thigh plate, knee pad, greave, boot.
        hip, knee, ankle = (
            Vector((s * HIP_X, 0, HIP_Z)),
            Vector((s * HIP_X, 0, KNEE_Z)),
            Vector((s * HIP_X, 0, ANKLE_Z)),
        )
        sk.blend(
            sk.tube(hip + Vector((0, 0, 0.04)), knee - Vector((0, 0, 0.06)), 0.1, 0.08, 14, 6, FABRIC),
            b("UpperLeg"),
            b("LowerLeg"),
            knee + Vector((0, 0, 0.06)),
            knee - Vector((0, 0, 0.04)),
        )
        R(sk.box((s * HIP_X, -0.08, 0.74), (0.15, 0.06, 0.26), rx(-4)), b("UpperLeg"))
        R(sk.box((s * (HIP_X + 0.085), 0.0, 0.76), (0.04, 0.14, 0.22)), b("UpperLeg"))
        R(sk.sphere((s * HIP_X, -0.06, KNEE_Z), 0.08, 14, 7, scale=(1.0, 0.85, 1.05)), b("LowerLeg"))
        R(
            sk.tube(knee - Vector((0, 0, 0.04)), ankle + Vector((0, 0, 0.08)), 0.085, 0.072, 14, 1, ARMOR, (1.0, 0.9)),
            b("LowerLeg"),
        )
        R(sk.box((s * HIP_X, -0.07, 0.33), (0.1, 0.04, 0.24), rx(-3)), b("LowerLeg"))
        R(sk.tube(ankle + Vector((0, 0, 0.02)), ankle + Vector((0, 0, 0.12)), 0.088, 0.085, 14, 1, TRIM), b("LowerLeg"))
        R(sk.box((s * HIP_X, -0.03, 0.075), (0.13, 0.22, 0.12)), b("Foot"))
        R(sk.box((s * HIP_X, -0.03, 0.015), (0.14, 0.25, 0.03), mi=RUBBER), b("Foot"))
        R(sk.box((s * HIP_X, -0.17, 0.045), (0.125, 0.1, 0.08)), b("Toes"))
        R(sk.box((s * HIP_X, -0.175, 0.012), (0.135, 0.1, 0.025), mi=RUBBER), b("Toes"))
    suit = sk.finish(root)

    light = Skin("SuitLight", [C.mat_emissive("SuitLight", (0.3, 1.0, 0.45), 6.0)], bevel=None)
    light.rigid(light.cyl((0, 0.0, 1.548), 0.182, 0.022, 32), "UpperChest")
    band = light.finish(root)
    for obj in (suit, band):
        obj.modifiers.new("Armature", "ARMATURE").object = arm
    return suit, band


def markers(arm: bpy.types.Object) -> None:
    """Empties on bones the game attaches to (their Godot -Z = the player's forward, see docstring)."""
    turn = rz(180)
    for name, bone, loc in (
        ("CargoRack", "UpperChest", (0, 0.31, 0.95)),
        ("HosePort", "UpperChest", (0, 0.29, 1.08)),
        ("WeaponGrip", "RightHand", GRIP),  # placed in the aim pose
    ):
        if name == "WeaponGrip":
            apply(arm, idle(0.0, aim=True))
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

GRIP = Vector((-0.17, -0.25, 1.1))  # Harl's origin (pistol grip) in the aim pose; muzzle ~1.25 m up
FOREGRIP = GRIP + Vector((0, -0.35, 0.086))  # harl.glb "Foregrip"


def smooth(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def relaxed_arms(p: Pose, swing: dict | None = None) -> None:
    for side, s in SIDES:
        f = (swing or {}).get(side, 0.0)
        wrist = Vector((s * 0.3, -0.02 - f, 0.93 + 0.12 * abs(f)))
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
        p.leg(side, Vector((s * 0.13, -0.01, ANKLE_Z)), Vector((s * 0.15, -1, 0)), 0.0, s * 6)
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
        base = Vector((s * (0.12 + 0.04 * abs(side_share)), 0.03 * s * side_share, 0))
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
        ankle = Vector((s * 0.13, -0.01 + 0.45 * f, ANKLE_Z - 0.02 * f))
        p.leg(side, ankle, Vector((s * 0.2, -1 + 0.6 * f, -1.6 * f)), 165 * f)  # ends with the soles up
        wrist = Vector((s * (0.3 + 0.12 * f), -0.05 - 0.75 * f, 0.93 - 0.85 * f))
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
}


def stand_ins() -> dict:
    grip = bpy.data.objects["WeaponGrip"]
    out = {}
    for kind, boxes in STAND_INS.items():
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
    _suit, _band = build_suit(root, arm)
    markers(arm)
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
