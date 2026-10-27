"""Nell's work behind the bar (see nell_build.py): wiping the counter, polishing a glass, shelving a bottle; and at a
booth's table: wiping it, clearing a glass from it. Each clip starts and ends in the standing pose ("Idle" at its
start), so the game blends it in and out over the idle.

Built from key poses (tools/blender/key_poses.py). Places are where she stands at Waypost Ostra (armature space: she
faces -Y): the bar counter's edge `COUNTER_EDGE` in front of her, its top at `COUNTER_TOP`, the bottle shelf behind her
right shoulder at `SHELF` (game/space_station/ostra/ostra_build.py: "BarCounter", "BackBar"); at a booth the table's
edge `TABLE_EDGE` in front of her, its top at `TABLE_TOP` ("BoothTable1", WORK_SPOTS "NellBooth"). Props: "PropRag" (right
hand), "PropGlass" (left hand), "PropBottle" (right hand), shown by the clips that use them.
"""

import math

from mathutils import Vector

import humanoid as H
from key_poses import arm, held_up, mix, pose, sequence, shown, standing

COUNTER_EDGE = -0.28  # m in front of her (-Y): she stands 0.28 m behind it
COUNTER_TOP = 1.1
SHELF = Vector((-0.4, 0.36, 1.55))  # where a bottle goes on the shelf behind her right shoulder
TABLE_EDGE = -0.3  # m in front of her at a booth's table
TABLE_TOP = 0.75


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
        RightCurl=25.0,
        LeftCurl=20.0,
    )
    k = mix(rest, work, H.smooth(min(t / 0.12, (1 - t) / 0.12, 1.0)))
    p = pose(body, k, t, 2)
    p.show["PropRag"] = shown(t, [(0.06, 0.94)])
    return p


def wipe_table(body: H.Body, t: float) -> H.Pose:
    """Wiping a booth's table: bent over it, the rag circling three times under the right hand, the left on the
    table's edge."""
    rest = standing(body)
    a = 2 * math.pi * 3 * t
    work = dict(rest)
    work.update(
        lean=34.0,
        crouch=0.06,
        pitch=12.0,
        Right=arm(
            (-0.08 + 0.1 * math.cos(a), TABLE_EDGE - 0.26 + 0.07 * math.sin(a), TABLE_TOP + 0.05),
            (-1, 0.6, -0.2),
            (0.1, -1, -0.5),
            (0, 0, -1),
        ),
        Left=arm((0.22, TABLE_EDGE - 0.06, TABLE_TOP + 0.04), (1, 0.6, -0.2), (-0.25, -1, -0.35), (0, 0, -1)),
        RightCurl=25.0,
        LeftCurl=20.0,
    )
    k = mix(rest, work, H.smooth(min(t / 0.12, (1 - t) / 0.12, 1.0)))
    p = pose(body, k, t, 2)
    p.show["PropRag"] = shown(t, [(0.06, 0.94)])
    return p


def clear_glass(body: H.Body, t: float) -> H.Pose:
    """Clearing a glass from a booth's table: reaching for it with the left hand, picking it up and holding it in front
    of her for a moment (a look at the guests), then lowering it to her side."""
    rest = standing(body)
    reach = dict(rest)
    reach.update(
        lean=30.0,
        crouch=0.05,
        pitch=14.0,
        Left=arm((0.1, TABLE_EDGE - 0.2, TABLE_TOP + 0.07), (0.5, 0.3, -1), (0, -1, 0.1), (-1, 0, 0)),
        LeftCurl=15.0,
    )
    grab = dict(reach)
    grab.update(LeftCurl=50.0)
    held = dict(rest)
    held.update(
        lean=4.0,
        pitch=-4.0,
        yaw=-12.0,
        Left=arm((0.12, -0.24, 1.05), (0.5, 0.3, -1), (-0.2, -1, 0.1), (-1, 0, 0)),
        LeftCurl=50.0,
    )
    lowered = dict(rest)
    lowered.update(
        Left=arm((body.wrist_x, -0.08, body.wrist_z + 0.12), (0.5, 0.3, -1), (0, -1, 0), (-1, 0, 0)), LeftCurl=50.0
    )
    keys = [(0.0, rest), (0.25, reach), (0.33, grab), (0.5, held), (0.72, held), (0.86, lowered), (1.0, rest)]
    p = pose(body, sequence(keys, t), t, 2)
    p.show["PropGlass"] = shown(t, [(0.32, 0.9)])
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
        LeftCurl=50.0,
        RightCurl=40.0,
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
        RightCurl=50.0,
    )
    look = dict(rest)
    look.update(pitch=-6.0, yaw=8.0, Right=held_up((-0.07, -0.3, 1.38), (0.35, -1, 0.15)), RightCurl=50.0)
    turned = dict(rest)
    turned.update(
        turn=-48.0,
        yaw=-35.0,
        pitch=-8.0,
        Right=held_up(SHELF + Vector((0.04, -0.06, -0.06)), (-0.5, 1, 0.1)),
        RightCurl=50.0,
    )
    placed = dict(turned)
    placed.update(
        Right=arm(SHELF + Vector((0.08, -0.12, -0.1)), (-1, 0.5, -0.3), (-0.4, 1, -0.2), (0.4, 0.2, -1)), RightCurl=15.0
    )
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
    "WipeTable": (240, wipe_table),
    "ClearGlass": (210, clear_glass),
}
