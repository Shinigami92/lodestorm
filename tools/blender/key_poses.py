"""Clips built from key poses, for people's activities (Nell's work at the bar, the crew's shared activities): a key
is the upper body's lean and turn, a crouch, where the head looks, and per arm the wrist's target, the side the elbow
bends to, where the hand points and which way its palm faces (humanoid.Pose.arm), and how far its fingers curl. Keys
blend smoothly into each other (`sequence`), and `pose` stands the body on its feet under a key, breathing. Places are
in armature space: the body faces -Y, its left is +X.
"""

import itertools
import math

from mathutils import Vector

import humanoid as H
from common import rx, rz

UP = Vector((0, 0, 1))


def arm(wrist, pole, along, palm) -> tuple:
    return (Vector(wrist), Vector(pole), Vector(along).normalized(), Vector(palm).normalized())


def held_up(wrist, along) -> tuple:
    """A right hand holding something upright (thumb up): its palm faces across the way it points."""
    along = Vector(along).normalized()
    return arm(wrist, (-0.5, 0.3, -1), along, UP.cross(along))


def relaxed(body: H.Body, side: str) -> tuple:
    """The standing pose's arm (as humanoid.relaxed_arms)."""
    s = 1.0 if side == "Left" else -1.0
    return arm((s * body.wrist_x, -0.02, body.wrist_z), (s * 0.3, 1, 0), (s * 0.15, -0.25, -1), (-s, 0, 0))


def standing(body: H.Body) -> dict:
    return {
        "lean": 0.0,
        "turn": 0.0,
        "crouch": 0.0,
        "pitch": 0.0,
        "yaw": 0.0,
        "Left": relaxed(body, "Left"),
        "Right": relaxed(body, "Right"),
        "LeftCurl": H.RELAXED_CURL,
        "RightCurl": H.RELAXED_CURL,
    }


def mix(a: dict, b: dict, u: float) -> dict:
    out = {}
    for k, va in a.items():
        vb = b[k]
        if isinstance(va, tuple):
            parts = [x.lerp(y, u) for x, y in zip(va, vb, strict=True)]
            out[k] = (parts[0], parts[1], parts[2].normalized(), parts[3].normalized())
        else:
            out[k] = va + (vb - va) * u
    return out


def sequence(keys: list, t: float) -> dict:
    """The pose at t between keys ((time, key) in order, the first at 0, the last at 1), eased in and out."""
    for (t0, k0), (t1, k1) in itertools.pairwise(keys):
        if t <= t1:
            return mix(k0, k1, H.smooth((t - t0) / max(t1 - t0, 1e-6)))
    return keys[-1][1]


def pose(body: H.Body, k: dict, t: float, breaths: int) -> H.Pose:
    """The pose a key describes (breathing `breaths` times over the clip)."""
    breath = math.sin(2 * math.pi * breaths * t)
    lean, turn = k["lean"], k["turn"]
    p = H.Pose(body, (0, 0.003 * lean, -0.035 - 0.004 * breath - k["crouch"]))

    def tilt(share: float):
        return rz(turn * share) @ rx(lean * share)

    p.spine(
        spine=tilt(0.3),
        chest=tilt(0.6) @ rx(-1.2 * breath),
        upper=tilt(1.0) @ rx(-2.0 * breath),
        neck=rz(turn + 0.5 * k["yaw"]) @ rx(lean + 0.5 * k["pitch"]),
        head=rz(turn + k["yaw"]) @ rx(lean + k["pitch"]),
    )
    for side, s in H.SIDES:
        p.arm(side, *k[side])
        p.curl(side, k[f"{side}Curl"])
        p.leg(side, Vector((s * body.foot_x, -0.01, body.ankle_z)), Vector((s * 0.15, -1, 0)), 0.0, s * 6)
    return p


def shown(t: float, spans: list) -> float:
    """1 within any (start, end) span, else 0."""
    return 1.0 if any(a <= t <= b for a, b in spans) else 0.0
