"""The little things every crew member does now and then at their post or a work spot (see docs/planned/crew.md, Crew
life aboard): looking around over the shoulders, stretching with the hands behind the head, checking something on the left wrist,
tapping at a console in front. Built from key poses (key_poses.py) on any body; each clip starts and ends in the
standing pose ("Idle" at its start), so the game blends it in and out over the idle.

    import fidgets
    clips.update(fidgets.clips(body))      # in a person's clips(body)
    shots = fidgets.work(body)             # their check renders
"""

import math

import humanoid as H
from key_poses import arm, mix, pose, sequence, standing

# The console a "Tap" works at: its top this high, its front edge this far in front of the feet (-Y), in m (the holo
# table's top is at 0.9, the flight console's at 1.1).
CONSOLE_TOP = 1.0
CONSOLE_EDGE = -0.35


def look_around(body: H.Body, t: float) -> H.Pose:
    """Looking over the left shoulder, then over the right, the upper body turning along a little."""
    rest = standing(body)
    left = dict(rest)
    left.update(turn=16.0, yaw=42.0, pitch=-3.0)
    right = dict(rest)
    right.update(turn=-16.0, yaw=-46.0, pitch=2.0)
    keys = [(0.0, rest), (0.2, left), (0.4, left), (0.62, right), (0.8, right), (1.0, rest)]
    return pose(body, sequence(keys, t), t, 2)


def stretch(body: H.Body, t: float) -> H.Pose:
    """Stretching: both hands behind the head, elbows out, leaning back a little, then letting them down again."""
    rest = standing(body)
    shoulder = body.head["LeftUpperArm"].z
    up = dict(rest)
    up.update(
        lean=-5.0,
        pitch=-6.0,
        Left=arm((0.07, 0.1, shoulder + 0.36), (1, 0.2, 0.3), (-0.6, 0.3, 0.6), (0, 1, 0)),
        Right=arm((-0.07, 0.1, shoulder + 0.36), (-1, 0.2, 0.3), (0.6, 0.3, 0.6), (0, 1, 0)),
        LeftCurl=30.0,
        RightCurl=30.0,
    )
    held = dict(up)
    held.update(lean=-9.0, pitch=-10.0)
    keys = [(0.0, rest), (0.3, up), (0.58, held), (1.0, rest)]
    return pose(body, sequence(keys, t), t, 2)


def check_wrist(body: H.Body, t: float) -> H.Pose:
    """Raising the left forearm in front of the chest and looking at something on its wrist, the right hand tapping
    it twice."""
    rest = standing(body)
    raised = body.wrist_z + 0.32
    look = dict(rest)
    look.update(
        lean=5.0,
        pitch=26.0,
        yaw=8.0,
        Left=arm((0.08, -0.3, raised), (1, 0.3, -0.6), (-1, -0.35, 0.05), (0, 0, -1)),
        LeftCurl=25.0,
    )
    tap = dict(look)
    tap.update(Right=arm((0.0, -0.34, raised + 0.06), (-1, 0.3, -0.5), (1, -0.5, -0.4), (0, 0, -1)), RightCurl=30.0)
    pressed = dict(tap)
    pressed["Right"] = arm((0.02, -0.33, raised + 0.025), (-1, 0.3, -0.5), (1, -0.5, -0.6), (0, 0, -1))
    keys = [
        (0.0, rest),
        (0.2, look),
        (0.32, tap),
        (0.37, pressed),
        (0.42, tap),
        (0.47, pressed),
        (0.52, tap),
        (0.62, look),
        (0.8, look),
        (1.0, rest),
    ]
    return pose(body, sequence(keys, t), t, 2)


def tap(body: H.Body, t: float) -> H.Pose:
    """Working at the console in front: leaning over it, the left hand on its edge, the right tapping here and there
    along it."""
    rest = standing(body)
    reach = min(t / 0.15, (1 - t) / 0.15, 1.0)
    a = 2 * math.pi * 7 * t
    across = -0.1 + 0.08 * math.sin(2 * math.pi * 1.5 * t)
    press = 0.025 * max(0.0, math.sin(a))
    work = dict(rest)
    work.update(
        lean=14.0,
        pitch=22.0,
        Left=arm((0.2, CONSOLE_EDGE - 0.04, CONSOLE_TOP + 0.03), (1, 0.6, -0.4), (-0.2, -1, -0.3), (0, 0, -1)),
        Right=arm(
            (across, CONSOLE_EDGE - 0.12, CONSOLE_TOP + 0.03 + press), (-1, 0.6, -0.4), (0.05, -1, -0.5), (0, 0, -1)
        ),
        LeftCurl=15.0,
        RightCurl=30.0,
    )
    return pose(body, mix(rest, work, H.smooth(reach)), t, 2)


CLIPS = {  # name: (frames, pose(body, t))
    "LookAround": (180, look_around),
    "Stretch": (150, stretch),
    "CheckWrist": (150, check_wrist),
    "Tap": (210, tap),
}


def clips(body: H.Body) -> dict:
    """The clips for a person's clips(body): name: (frames, pose(t))."""
    return {name: (frames, lambda t, fn=fn: fn(body, t)) for name, (frames, fn) in CLIPS.items()}


def work(body: H.Body) -> list:
    """The poses to render as checks: each clip at its fullest."""
    return [
        ("look", look_around(body, 0.3)),
        ("stretch", stretch(body, 0.5)),
        ("wrist", check_wrist(body, 0.37)),
        ("tap", tap(body, 0.5)),
    ]
