"""The ship's layout: deck heights and each room's position and size. Shared by the greybox hull
(game/ship/hull_build.py) and the hull's model (assets/ship/source/ship_exterior_build.py), so both
put the windows and the ramp door in the same places.

Ship-local: +x = screen right (tail, ramp), -x = nose; +z = towards the camera; y 0 is the ground.
Inner space x -80.5..14.5, z -14.5..14.5. Lower deck floor LOW, ceiling SLAB; upper deck floor UP,
ceiling TOP; roof above. Corridors along z = 0 (inner z -2.5..2.5). Sections along x: nose rooms
-80.5..-58 | lift lobby -57.5..-52 | rooms -51.5..-3.5 | cargo bay -3..14.5 (double height). Lifts:
by the lobby and in the cargo bay's back corner.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "tools"))

from greybox import windows_for

# The hull stands on landing gear, GEAR m above the ground.
GEAR = 1.5
LOW, SLAB, UP, TOP = GEAR + 1.0, GEAR + 5.0, GEAR + 5.5, GEAR + 9.5
ZI = 14.5  # inner half depth
CW = 2.75  # corridor wall center (inner corridor half width 2.5)
# The outer walls' outside faces: the box the hull's model wraps (x, z; y from the floor's underside
# to the roof's top).
BOX_X = (-81.0, 15.0)
BOX_Z = 15.0
BOX_Y = (LOW - 1.0, TOP + 0.5)
# The ramp door in the tail wall (centered on z 0): its width and height above the lower deck.
RAMP_WIDTH = 10.0
RAMP_DOOR_HEIGHT = 3.5
RAMP_LENGTH = 5.0
# The landing legs: three pairs along the sides (x), their pads' centers z m out from the middle and
# their pads' size (x, z).
LEG_X = [-70.0, -33.0, 4.0]
LEG_Z = 19.7
LEG_PAD = (5.2, 4.6)

RANGE_X = (-51.5, -22)
ARMORY_X = (-21.5, -3.5)
RANGE_DOOR = -49.5
VENDOR_W = (48 - 1.5) / 4
VENDORS = [
    (n, -51.5 + i * (VENDOR_W + 0.5), -51.5 + i * (VENDOR_W + 0.5) + VENDOR_W)
    for i, n in enumerate(["Weapons", "Armor", "Skills", "Miners"])
]
CABIN_X = [(-51.5, -46), (-45.5, -40)]
CREW_X = [(-39.5 + i * 5, -35 + i * 5) for i in range(4)]
MESS_X = (-19.5, -3.5)

# --- rooms: name, deck (Lower/Upper/None = double height), x, z ---
# Each is a scene in game/ship/rooms/ at its floor center; the hull only places their windows.
BACK, FRONT, FULL, CORR = (-ZI, -3), (3, ZI), (-ZI, ZI), (-2.5, 2.5)
ROOMS = [
    ("Cockpit", "Upper", (-80.5, -72.5), FULL),
    ("Bridge", "Upper", (-72, -58), FULL),
    ("UpperLobby", "Upper", (-57.5, -52), (-2.5, ZI)),
    ("UpperCorridor", "Upper", (-51.5, -19.5), CORR),
    ("MessHall", "Upper", MESS_X, FULL),
]
for _i, _x in enumerate(CABIN_X):
    ROOMS += [(f"Cabin{2 * _i + 1}", "Upper", _x, BACK), (f"Cabin{2 * _i + 2}", "Upper", _x, FRONT)]
for _i, _x in enumerate(CREW_X):
    ROOMS += [(f"Crew{_i + 1}", "Upper", _x, BACK), (f"Crew{_i + 5}", "Upper", _x, FRONT)]
ROOMS += [
    ("MedicalBay", "Lower", (-80.5, -58), BACK),
    ("NoseCorridor", "Lower", (-80.5, -58), CORR),
    ("EngineRoom", "Lower", (-80.5, -58), FRONT),
    ("LowerLobby", "Lower", (-57.5, -52), (-2.5, ZI)),
    ("ShootingRange", "Lower", RANGE_X, BACK),
    ("Armory", "Lower", ARMORY_X, BACK),
    ("LowerCorridor", "Lower", (-51.5, -3.5), CORR),
]
ROOMS += [(name, "Lower", (a, b), FRONT) for name, a, b in VENDORS]
ROOMS += [("CargoBay", None, (-3, 14.5), FULL)]

# The cockpit's windows in the nose wall (z center, width).
COCKPIT_WINDOWS = [(-4.5, 7), (4.5, 7)]


def outer_windows(deck, side):
    """Windows (x center, width) of the rooms on `deck` (rooms of both decks count for both) along
    the back (-1) or front (+1) wall."""
    wins = []
    for _name, d, (x0, x1), (z0, z1) in ROOMS:
        if d not in (deck, None):
            continue
        if (side < 0 and z0 == -ZI) or (side > 0 and z1 == ZI):
            wins += windows_for(x0, x1)
    return wins
