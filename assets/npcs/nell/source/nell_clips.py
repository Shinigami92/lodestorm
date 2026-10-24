"""Nell's work behind the bar (see nell_build.py): wiping the counter, polishing a glass, shelving a bottle. Each clip
starts and ends in the standing pose ("Idle" at its start), so the game blends it in and out over the idle.

Built from key poses (Key): the upper body's lean and turn, a crouch, where the head looks, and per arm the wrist's
target, the side the elbow bends to, where the hand points and which way its palm faces (humanoid.Pose.arm), blended
smoothly between keys. Places are where she stands at Waypost Ostra (armature space: she faces -Y): the bar counter's
edge `COUNTER_EDGE` in front of her, its top at `COUNTER_TOP`, the bottle shelf behind her right shoulder at `SHELF`
(game/space_station/ostra/ostra_build.py: "BarCounter", "BackBar"). Props: "PropRag" (right hand), "PropGlass"
(left hand), "PropBottle" (right hand), shown by the clips that use them.
"""

import itertools
import math

from mathutils import Vector

import humanoid as H
from common import rx, rz

COUNTER_EDGE = -0.28  # m in front of her (-Y): she stands 0.28 m behind it
COUNTER_TOP = 1.1
SHELF = Vector((-0.4, 0.36, 1.55))  # where a bottle goes on the shelf behind her right shoulder
UP = Vector((0, 0, 1))


def arm(wrist, pole, along, palm) -> tuple:
    return (Vector(wrist), Vector(pole), Vector(along).normalized(), Vector(palm).normalized())


def held_up(wrist, along) -> tuple:
    """A right hand holding something upright (thumb up): its palm faces across the way it points."""
    along = Vector(along).normalized()
    return arm(wrist, (-1, 0.5, -0.3), along, UP.cross(along))


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
        p.leg(side, Vector((s * body.foot_x, -0.01, body.ankle_z)), Vector((s * 0.15, -1, 0)), 0.0, s * 6)
    return p


def shown(t: float, spans: list) -> float:
    """1 within any (start, end) span, else 0."""
    return 1.0 if any(a <= t <= b for a, b in spans) else 0.0


def wipe(body: H.Body, t: float) -> H.Pose:
    """Wiping the counter: leaning over it, the rag circling three times under the right hand, the left on the
    counter's edge."""
    rest = standing(body)
    a = 2 * math.pi * 3 * t
    work = dict(rest)
    work.update(
        lean=16.0,
        pitch=18.0,
        Right=arm(
            (-0.08 + 0.1 * math.cos(a), COUNTER_EDGE - 0.24 + 0.07 * math.sin(a), COUNTER_TOP + 0.05),
            (-1, 0.6, -0.4),
            (0.1, -1, -0.45),
            (0, 0, -1),
        ),
        Left=arm((0.21, COUNTER_EDGE - 0.08, COUNTER_TOP + 0.04), (1, 0.6, -0.4), (-0.25, -1, -0.3), (0, 0, -1)),
    )
    k = mix(rest, work, H.smooth(min(t / 0.12, (1 - t) / 0.12, 1.0)))
    p = pose(body, k, t, 2)
    p.show["PropRag"] = shown(t, [(0.06, 0.94)])
    return p


def polish(body: H.Body, t: float) -> H.Pose:
    """Polishing a glass: held in the left hand in front of her chest, the rag in the right hand turning in it, her
    head down to look at it."""
    rest = standing(body)
    a = 2 * math.pi * 5 * t
    work = dict(rest)
    work.update(
        lean=5.0,
        pitch=26.0,
        Left=arm((0.07, -0.3, 1.1), (1, 0.4, -0.6), (-0.3, -1, 0.15), (-1, 0, 0.15)),
        Right=arm(
            (-0.02 + 0.025 * math.cos(a), -0.36 + 0.025 * math.sin(a), 1.24),
            (-1, 0.5, -0.4),
            (0.35, -0.5, -0.8),
            (0.8 * math.cos(0.4 * math.sin(a)), 0.3, -0.5),
        ),
    )
    k = mix(rest, work, H.smooth(min(t / 0.14, (1 - t) / 0.14, 1.0)))
    p = pose(body, k, t, 2)
    p.show["PropGlass"] = shown(t, [(0.08, 0.92)])
    p.show["PropRag"] = shown(t, [(0.08, 0.92)])
    return p


def shelve(body: H.Body, t: float) -> H.Pose:
    """Shelving a bottle: crouching for it under the counter, standing up to look at its label, turning to put it on
    the shelf behind her right shoulder, turning back."""
    rest = standing(body)
    down = dict(rest)
    down.update(
        crouch=0.36,
        lean=30.0,
        pitch=20.0,
        Right=held_up((-0.12, -0.26, 0.6), (0.2, -1, -0.6)),
    )
    look = dict(rest)
    look.update(pitch=-6.0, yaw=8.0, Right=held_up((-0.07, -0.3, 1.38), (0.35, -1, 0.15)))
    turned = dict(rest)
    turned.update(
        turn=-48.0, yaw=-35.0, pitch=-8.0, Right=held_up(SHELF + Vector((0.04, -0.06, -0.06)), (-0.5, 1, 0.1))
    )
    placed = dict(turned)
    placed.update(Right=arm(SHELF + Vector((0.08, -0.12, -0.1)), (-1, 0.5, -0.3), (-0.4, 1, -0.2), (0.4, 0.2, -1)))
    keys = [
        (0.0, rest),
        (0.2, down),
        (0.27, down),
        (0.45, look),
        (0.55, look),
        (0.72, turned),
        (0.78, placed),
        (1.0, rest),
    ]
    p = pose(body, sequence(keys, t), t, 3)
    p.show["PropBottle"] = shown(t, [(0.18, 0.75)])
    return p


CLIPS = {  # name: (frames, pose(body, t))
    "WipeCounter": (240, wipe),
    "PolishGlass": (210, polish),
    "ShelveBottle": (240, shelve),
}
