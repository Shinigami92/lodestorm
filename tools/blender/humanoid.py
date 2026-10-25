"""Shared helpers for people (the player, the NPCs): a skeleton with Godot's humanoid bone names
(SkeletonProfileHumanoid), posed from world-space rotations per bone and two-bone IK for arms and legs, and the clips
everyone has ("Idle", the run directions, "Walk", "Die"); sit() poses sitting on a seat (the suit's "Sit", for the
colonists).

    import humanoid as H
    body = H.Body(bones, foot_x=0.17, wrist_x=0.4, wrist_z=0.93)  # bones: (name, head, tail, parent) at rest
    arm = H.build_skeleton(root, body)
    H.bake_clips(arm, {"Idle": (60, lambda t: H.idle(body, t)), "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t))})

Blender Z-up meters, the body faces -Y, its left is +X. A body's rest pose is its own (the player's is a T-pose):
each limb bone's rest direction is its head to the next joint, and its rest pole the side its joint bends towards
(the elbows back, the knees forward, given or measured where the limb is bent at rest); the hands' rest pole is the
way the palm faces. A Pose sets world rotations relative to the rest pose, so every clip plays on every body; the
measures that differ between bodies (where the feet stand, where the hanging hands are) come from the Body.
"""

import math

import bpy
from mathutils import Matrix, Vector

import common as C
from common import rx, ry, rz

FPS = 30
RUN_SPEED = 6.0  # m/s the locomotion clips are authored at (PlayerSettings.move_speed)
RUN_FRAMES = 20  # one stride (two steps) in 0.67 s
WALK_SPEED = 1.3  # m/s the walk clip is authored at (PlayerAnimator.walk_speed)
WALK_FRAMES = 32  # one stride (two steps) in 1.07 s
I3 = Matrix.Identity(3)
SIDES = (("Left", 1.0), ("Right", -1.0))
FINGERS = {  # Godot's humanoid finger bones, root to tip
    "Thumb": ("Metacarpal", "Proximal", "Distal"),
    **{f: ("Proximal", "Intermediate", "Distal") for f in ("Index", "Middle", "Ring", "Little")},
}
RELAXED_CURL = 12.0  # degrees per finger joint of a hand hanging loose
ARM_POLE = Vector((0, 1, 0))  # an arm straight at rest bends its elbow back
LEG_POLE = Vector((0, -1, 0))  # a leg straight at rest bends its knee forward
PALM = Vector((0, 0, -1))  # the way a palm faces at rest (T-pose: down)


def _pole(a: Vector, joint: Vector, end: Vector, default: Vector) -> Vector:
    """The side a two-bone chain bends towards: the joint's offset from the line a-end, or `default` if straight."""
    u = (end - a).normalized()
    off = (joint - a) - u * (joint - a).dot(u)
    return off.normalized() if off.length > 0.01 * (end - a).length else default


class Body:
    """One skeleton: its bones (name, head, tail, parent) at rest, the hands' rest poles per side (default: palms
    down), and the measures the clips stand it on: the feet's distance from the middle and the hanging wrists'
    sideways distance and height. `props` are bones holding things in the hands (a glass, a rag): a pose shows them
    by their scale (hidden unless it says otherwise). `forearm_twist`: the share of the hand's twist the forearm takes
    (a skeleton without twist bones: the wrist's skin would twist alone; the player's armored suit: 0);
    `wrist_bend`: how far (degrees) a hand bends away from its forearm's line at most."""

    def __init__(
        self,
        bones: list,
        *,
        foot_x: float,
        wrist_x: float,
        wrist_z: float,
        palm: dict | None = None,
        props: tuple = (),
        forearm_twist: float = 0.0,
        wrist_bend: float = 180.0,
    ):
        self.bones = bones
        self.head = {n: Vector(h) for n, h, _t, _p in bones}
        self.tail = {n: Vector(t) for n, _h, t, _p in bones}
        self.parent = {n: p for n, _h, _t, p in bones}
        self.foot_x, self.wrist_x, self.wrist_z = foot_x, wrist_x, wrist_z
        self.props = props
        self.forearm_twist = forearm_twist
        self.wrist_bend = math.radians(wrist_bend)
        self.ankle_z = self.head["LeftFoot"].z
        self.length = {}
        self.rest = {}  # bone: (direction, pole) at rest
        for side, _s in SIDES:
            shoulder, elbow, wrist = (self.head[f"{side}{n}"] for n in ("UpperArm", "LowerArm", "Hand"))
            hip, knee, ankle = (self.head[f"{side}{n}"] for n in ("UpperLeg", "LowerLeg", "Foot"))
            arm_pole = _pole(shoulder, elbow, wrist, ARM_POLE)
            leg_pole = _pole(hip, knee, ankle, LEG_POLE)
            for name, a, b, pole in (
                ("UpperArm", shoulder, elbow, arm_pole),
                ("LowerArm", elbow, wrist, arm_pole),
                ("UpperLeg", hip, knee, leg_pole),
                ("LowerLeg", knee, ankle, leg_pole),
            ):
                self.length[f"{side}{name}"] = (b - a).length
                self.rest[f"{side}{name}"] = ((b - a).normalized(), pole)
            hand = f"{side}Hand"
            self.rest[hand] = ((self.tail[hand] - wrist).normalized(), Vector((palm or {}).get(side, PALM)))


def build_skeleton(root: bpy.types.Object, body: Body) -> bpy.types.Object:
    data = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", data)
    C.link(arm, root)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in body.bones:
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
    """World-space rotations per bone (relative to the rest pose) plus the hips' offset; arms and legs by IK. A
    bone without its own (e.g. a finger) turns with its parent."""

    def __init__(self, body: Body, hips_offset=(0, 0, 0), hips=I3):
        self.body = body
        self.offset = Vector(hips_offset)
        self.show = {}  # prop bone: its scale (0: hidden)
        self.w = {"Root": I3.copy(), "Hips": hips}

    def spine(self, spine=None, chest=None, upper=None, neck=None, head=None) -> None:
        last = self.w["Hips"]
        for name, rot in (("Spine", spine), ("Chest", chest), ("UpperChest", upper), ("Neck", neck), ("Head", head)):
            last = rot if rot is not None else last
            self.w[name] = last
        for side, _s in SIDES:
            self.w[f"{side}Shoulder"] = self.w["UpperChest"]

    def world(self, bone: str) -> Matrix:
        """The bone's world rotation (its own, else its parent's)."""
        while bone not in self.w:
            bone = self.body.parent[bone]
        return self.w[bone]

    def pos(self, bone: str) -> Vector:
        head, parent = self.body.head, self.body.parent[bone]
        if parent is None:
            return head[bone].copy()
        p = self.pos(parent) + self.world(parent) @ (head[bone] - head[parent])
        return p + self.offset if bone == "Hips" else p

    def arm(self, side: str, wrist: Vector, pole: Vector, hand_dir: Vector, palm: Vector) -> None:
        rest, length = self.body.rest, self.body.length
        a = self.pos(f"{side}UpperArm")
        elbow, end = two_bone(a, Vector(wrist), length[f"{side}UpperArm"], length[f"{side}LowerArm"], Vector(pole))
        self.w[f"{side}UpperArm"] = turn_between(*rest[f"{side}UpperArm"], elbow - a, pole)
        lower = turn_between(*rest[f"{side}LowerArm"], end - elbow, pole)
        forearm = (end - elbow).normalized()
        hand_dir = Vector(hand_dir).normalized()
        bend = forearm.angle(hand_dir, 0.0)
        if bend > self.body.wrist_bend:  # no further than a wrist bends: towards the forearm's line
            hand_dir = forearm.slerp(hand_dir, self.body.wrist_bend / bend)
        hand = turn_between(*rest[f"{side}Hand"], hand_dir, Vector(palm))
        if self.body.forearm_twist:
            # The forearm rolls along with the hand (a share of the hand's twist about it), so the wrist's skin
            # doesn't twist alone.
            axis = rest[f"{side}LowerArm"][0]
            rel = (lower.transposed() @ hand).to_quaternion()
            twist = 2 * math.atan2(Vector((rel.x, rel.y, rel.z)).dot(axis), rel.w)
            twist = (twist + math.pi) % (2 * math.pi) - math.pi
            lower = lower @ Matrix.Rotation(twist * self.body.forearm_twist, 3, axis)
        self.w[f"{side}LowerArm"] = lower
        self.w[f"{side}Hand"] = hand

    def curl(self, side: str, fingers: float, thumb: float | None = None) -> None:
        """Bends the fingers towards the palm, `fingers` degrees at each joint (the thumb `thumb`, default half);
        nothing on a skeleton without fingers."""
        body = self.body
        if f"{side}IndexProximal" not in body.head:
            return
        thumb = fingers * 0.5 if thumb is None else thumb
        hand = self.world(f"{side}Hand")
        palm = body.rest[f"{side}Hand"][1]
        for finger, joints in FINGERS.items():
            names = [f"{side}{finger}{j}" for j in joints]
            first = body.head[names[0]]
            tip = body.tail[names[-1]]
            axis = (tip - first).cross(palm).normalized()
            angle = thumb if finger == "Thumb" else fingers
            for k, name in enumerate(names, 1):
                self.w[name] = hand @ Matrix.Rotation(math.radians(angle * k), 3, axis)

    def leg(self, side: str, ankle: Vector, pole: Vector, pitch: float = 0.0, yaw: float = 0.0) -> None:
        rest, length = self.body.rest, self.body.length
        a = self.pos(f"{side}UpperLeg")
        knee, end = two_bone(a, Vector(ankle), length[f"{side}UpperLeg"], length[f"{side}LowerLeg"], Vector(pole))
        self.w[f"{side}UpperLeg"] = turn_between(*rest[f"{side}UpperLeg"], knee - a, pole)
        self.w[f"{side}LowerLeg"] = turn_between(*rest[f"{side}LowerLeg"], end - knee, pole)
        self.w[f"{side}Foot"] = rz(yaw) @ rx(pitch)
        self.w[f"{side}Toes"] = self.w[f"{side}Foot"]


def apply(arm: bpy.types.Object, pose: Pose) -> None:
    """Set the armature's pose bones from a Pose (local rotation q = R^-1 W_parent^-1 W R)."""
    for name, _h, _t, parent in pose.body.bones:
        pb = arm.pose.bones[name]
        rest = arm.data.bones[name].matrix_local.to_3x3()
        w = pose.world(name)
        wp = pose.world(parent) if parent else I3
        q = (rest.transposed() @ wp.transposed() @ w @ rest).to_quaternion()
        if pb.rotation_quaternion.dot(q) < 0:  # keep keys on one hemisphere (no flips between frames)
            q.negate()
        pb.rotation_quaternion = q
        pb.location = rest.transposed() @ pose.offset if name == "Hips" else Vector()
        if name in pose.body.props:
            pb.scale = (pose.show.get(name, 0.0),) * 3


def rest_pose(arm: bpy.types.Object) -> None:
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()


# --- clips ------------------------------------------------------------------------------------------


def smooth(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t: float):
    return a + (b - a) * t


def relaxed_arms(p: Pose, swing: dict | None = None) -> None:
    body = p.body
    for side, s in SIDES:
        f = (swing or {}).get(side, 0.0)
        wrist = Vector((s * body.wrist_x, -0.02 - f, body.wrist_z + 0.12 * abs(f)))
        p.arm(side, wrist, Vector((s * 0.3, 1, 0)), Vector((s * 0.15, -0.25, -1)), Vector((-s, 0, 0)))
        p.curl(side, RELAXED_CURL)


def idle(body: Body, t: float, upper=None) -> Pose:
    """Standing and breathing at phase t (0..1); `upper(pose)` poses the arms (default: hanging relaxed)."""
    breath = math.sin(2 * math.pi * t)
    p = Pose(body, (0, 0, -0.035 - 0.004 * breath))
    p.spine(chest=rx(-1.2 * breath), upper=rx(-2.0 * breath), neck=I3, head=I3)
    if upper:
        upper(p)
    else:
        relaxed_arms(p)
    for side, s in SIDES:
        p.leg(side, Vector((s * body.foot_x, -0.01, body.ankle_z)), Vector((s * 0.15, -1, 0)), 0.0, s * 6)
    return p


def run(body: Body, t: float, move: Vector) -> Pose:
    """One stride at phase t (0..1) moving along `move` (unit, armature XY; forward is -Y)."""
    stance, stride = 0.27, 0.78
    fwd = -move.y  # forward share of the movement
    side_share = move.x
    bob = math.cos(2 * math.pi * 2 * (t - stance / 2))
    yaw = 7 * math.sin(2 * math.pi * t) * fwd
    lean_axis = Vector((0, 0, 1)).cross(Vector((move.x, move.y, 0)))
    lean = Matrix.Rotation(math.radians(9 if fwd >= -0.5 else 5), 3, lean_axis)
    p = Pose(body, move * 0.05 + Vector((0, 0, -0.085 - 0.03 * bob)), rz(yaw) @ ry(-3 * side_share))
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
        base = Vector((s * (body.foot_x - 0.01 + 0.04 * abs(side_share)), 0.03 * s * side_share, 0))
        pitch *= 1 if fwd >= -0.5 else -0.6
        # The foot rolls over its toes (heel up) or its heel (toes up), not around the ankle.
        lift += 0.14 * math.sin(math.radians(max(pitch, 0))) + 0.07 * math.sin(math.radians(max(-pitch, 0)))
        ankle = base + Vector((move.x, move.y, 0)) * x + Vector((0, 0, body.ankle_z + lift))
        p.leg(side, ankle, Vector((s * 0.15, -1, 0)), pitch)
        swing[side] = -0.5 * x * fwd
    swing = {"Left": swing["Right"], "Right": swing["Left"]}  # arms swing with the opposite leg
    relaxed_arms(p, swing)
    return p


def walk(body: Body, t: float) -> Pose:
    """One walking stride at phase t (0..1), forward at WALK_SPEED: each foot is down for 60 % of the stride
    (both down around each step), moving back under the body at the walking speed, so it stays planted; the
    heel strikes and the foot rolls off its toes, a low swing, a small bob (highest over the standing foot),
    upright, the arms swinging a little."""
    stance = 0.6
    stride = WALK_SPEED * stance * WALK_FRAMES / FPS  # the ground the body covers while a foot is down
    bob = math.cos(2 * math.pi * 2 * (t - stance / 2))
    yaw = 4 * math.sin(2 * math.pi * t)
    lean = Matrix.Rotation(math.radians(2), 3, Vector((1, 0, 0)))
    p = Pose(body, Vector((0, 0, -0.03 + 0.012 * bob)), rz(yaw))
    p.spine(spine=lean @ rz(yaw * 0.4), chest=rz(-yaw * 0.2), upper=rz(-yaw * 0.6), neck=rz(-yaw * 0.3), head=I3)
    swing = {}
    for side, s in SIDES:
        u = (t + (0.0 if side == "Left" else 0.5)) % 1.0
        if u < stance:
            w = u / stance
            x, lift = stride / 2 - stride * w, 0.0
            pitch = -10 * (1 - smooth(w / 0.15)) + 18 * smooth((w - 0.75) / 0.25)
        else:
            w = (u - stance) / (1 - stance)
            x = -stride / 2 + stride * (0.5 - 0.5 * math.cos(math.pi * w))
            lift = 0.08 * math.sin(math.pi * w)
            pitch = 18 * (1 - smooth(w / 0.3)) + 20 * math.sin(math.pi * w) * (1 - w) - 10 * smooth((w - 0.8) / 0.2)
        # The foot rolls over its toes (heel up) or its heel (toes up), not around the ankle.
        lift += 0.14 * math.sin(math.radians(max(pitch, 0))) + 0.07 * math.sin(math.radians(max(-pitch, 0)))
        ankle = Vector((s * (body.foot_x - 0.01), -x, body.ankle_z + lift))
        p.leg(side, ankle, Vector((s * 0.15, -1, 0)), pitch)
        swing[side] = -0.35 * x
    swing = {"Left": swing["Right"], "Right": swing["Left"]}  # arms swing with the opposite leg
    relaxed_arms(p, swing)
    return p


def die(body: Body, t: float) -> Pose:
    """Knees buckle (to 0.3), then the body tips forward and lies face down (1.0)."""
    k = smooth(t / 0.3)
    f = smooth((t - 0.25) / 0.6)
    lean = rx(20 * k + 70 * f)
    hips = Vector((0, -0.05 * k - 0.3 * f, -0.4 * k - 0.32 * f))
    p = Pose(body, hips, rx(10 * k + 70 * f))
    p.spine(spine=lean, chest=lean, upper=lean, neck=lean @ rz(25 * f), head=lean @ rz(40 * f))
    for side, s in SIDES:
        ankle = Vector((s * body.foot_x, -0.01 + 0.45 * f, body.ankle_z - 0.02 * f))
        p.leg(side, ankle, Vector((s * 0.2, -1 + 0.6 * f, -1.6 * f)), 165 * f)  # ends with the soles up
        wrist = Vector((s * (body.wrist_x + 0.12 * f), -0.05 - 0.75 * f, body.wrist_z - 0.85 * f))
        p.arm(
            side,
            wrist,
            Vector((s * 0.5, 1 - f, 0.5 * f)),
            Vector((s * 0.2, -0.3 - f, -1 + f)),
            Vector((-s * (1 - f), 0, -f)),
        )
    return p


SEAT_HEIGHT = 0.45  # m: the seats people sit on (Waypost Ostra's benches, game/space_station/ostra/ostra_build.py)
SIT_BACK = 0.4  # m: how far behind where it stood the hip joints sit down (a seat's spot is where its feet are)
HIP_ABOVE_SEAT = 0.08  # m: the hip joints above the seat (the flesh, or the suit, under them)


def sit(body: Body, t: float) -> Pose:
    """Sitting upright on a seat SEAT_HEIGHT high behind where it stood, breathing at phase t (0..1): the hip joints
    SIT_BACK back, the thighs forward, the feet on the floor where it stood, the hands resting on the thighs."""
    breath = math.sin(2 * math.pi * t)
    hip = body.head["LeftUpperLeg"]
    drop = SEAT_HEIGHT + HIP_ABOVE_SEAT - hip.z
    p = Pose(body, (0, SIT_BACK - hip.y, drop + 0.003 * breath))
    p.spine(spine=rx(4), chest=rx(4 - 1.2 * breath), upper=rx(4 - 2.0 * breath), neck=rx(-6), head=rx(-4))
    for side, s in SIDES:
        p.leg(side, Vector((s * (body.foot_x + 0.03), -0.02, body.ankle_z)), Vector((s * 0.2, -1, 0.4)), 0.0, s * 8)
        thigh = p.pos(f"{side}UpperLeg").lerp(p.pos(f"{side}LowerLeg"), 0.6)
        p.arm(side, thigh + Vector((s * 0.03, 0.04, 0.1)), Vector((s * 0.6, 1, -0.2)), Vector((0, -1, -0.5)), PALM)
        p.curl(side, RELAXED_CURL)
    return p


MOVES = {
    "Run": Vector((0, -1, 0)),
    "RunBack": Vector((0, 1, 0)),
    "StrafeLeft": Vector((1, 0, 0)),
    "StrafeRight": Vector((-1, 0, 0)),
}


def locomotion(body: Body) -> dict:
    """The clips everyone has: name: (frames, pose(t) for t in 0..1)."""
    return {
        "Idle": (60, lambda t: idle(body, t)),
        **{name: (RUN_FRAMES, lambda t, m=m: run(body, t, m)) for name, m in MOVES.items()},
        "Walk": (WALK_FRAMES, lambda t: walk(body, t)),
    }


def bake_clips(arm: bpy.types.Object, clips: dict, props: tuple = ()) -> None:
    """One action per clip (name: (frames, pose(t))), each in its own muted NLA track; `props` (the Body's prop
    bones) get their scale keyed too."""
    ad = arm.animation_data_create()
    for name, (frames, fn) in clips.items():
        ad.action = None
        for f in range(frames + 1):
            apply(arm, fn(f / frames if frames else 0.0))
            for pb in arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                if pb.name == "Hips":
                    pb.keyframe_insert("location", frame=f, group=pb.name)
                if pb.name in props:
                    pb.keyframe_insert("scale", frame=f, group=pb.name)
        act = ad.action
        act.name = name
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        track.mute = True
        ad.action = None
    rest_pose(arm)
