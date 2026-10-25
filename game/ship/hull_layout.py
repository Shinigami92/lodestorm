"""The ship's layout: deck heights, each room's position and size, and the skin of the hull's model
around them. Shared by the greybox hull (game/ship/hull_build.py) and the hull's model
(assets/ship/source/ship_exterior_build.py), so both put the windows and the ramp door in the same
places and the rooms stay inside the skin.

Ship-local: +x = screen right (tail, ramp), -x = nose; +z = towards the camera; y 0 is the ground.
Inner space x -80.5..14.5, z -14.5..14.5 (the box), plus the nose rooms reaching into the nose. Lower
deck floor LOW, ceiling SLAB; upper deck floor UP, ceiling TOP; roof above. Corridors along z = 0
(inner z -2.5..2.5). Sections along x: nose rooms (cockpit above, specimen lab below) ..-81 | bridge
above, medical bay and engine room below -80.5..-58 | lift lobby -57.5..-52 | rooms -51.5..-3.5 | cargo
bay -3..14.5 (double height). Lifts: by the lobby and in the cargo bay's back corner. Windows sit in
niches reaching out towards the skin.
"""

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "tools"))

from greybox import windows_for

# The hull stands on landing gear, GEAR m above the ground.
GEAR = 1.5
LOW, SLAB, UP, TOP = GEAR + 1.0, GEAR + 5.0, GEAR + 5.5, GEAR + 11.0
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
# The hull's model at the tail, where it reaches into a station's hangar: its half width with the
# nacelles (z), its top (y), and the half width of its lower sides under the nacelles (z), where the
# docking clamps hold it (the exterior's build script checks its model against these).
TAIL_HALF_WIDTH = 27.1
TAIL_TOP = 16.7
LOWER_SIDE = 17.5

# The nose rooms reach past the box into the nose, their outer walls following its taper: wall
# centers (x, z) of the -z half from the box's nose wall to the front wall (mirrored for +z). The
# cockpit on the upper deck under a lower ceiling (the nose's top slopes down), the specimen lab
# below it on a thinner floor (the belly rises).
COCKPIT_OUTLINE = [(-81.0, -14.75), (-88.0, -14.75), (-99.0, -7.0)]
COCKPIT_TOP = UP + 4.0
LAB_OUTLINE = [(-81.0, -14.75), (-86.0, -14.75), (-89.5, -11.0)]
LAB_FLOOR = 0.3  # the lab floor's thickness (the box's floor is 1 m)
# The cockpit's windows in its front wall (z center, width).
COCKPIT_WINDOWS = [(-3.6, 5.5), (3.6, 5.5)]
# Window niches in the outer walls: the glass NICHE m further out than the wall's center, the niche
# NICHE_SIDE m wider than the glass on each side and NICHE_HEIGHT m high.
NICHE = 1.0
NICHE_SIDE = 0.5
NICHE_HEIGHT = 3.1

# Where the shell is the kit's model (assets/ship/source/ship_shell_build.py) instead of greybox boxes:
# regions (x0, x1, y0, y1, z0, z1) a wall piece's center lies in, and the x positions where walls along x
# are split so their pieces end at a region's edge. So far the armory with its stretch of the lower
# corridor (the test room); the rest follows.
SHELL_REGIONS = [(-21.8, -3.2, LOW - 1.0, UP - 0.4, -ZI - 2.0, 0.0)]
SHELL_SPLITS = [-21.75, -3.25]


def dressed(center):
    """Whether the wall piece centered at `center` (x, y, z) is the kit's."""
    x, y, z = center
    return any(x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1 for x0, x1, y0, y1, z0, z1 in SHELL_REGIONS)


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
NOSE_X = (-80.5, -58)

# --- rooms: name, deck (Lower/Upper/None = double height), x, z ---
# Each is a scene in game/ship/rooms/ at its floor center; the hull only places their windows. The
# nose rooms' x is the straight stretch of their outer walls (where their windows are); their floor
# follows their outline.
BACK, FRONT, FULL, CORR = (-ZI, -3), (3, ZI), (-ZI, ZI), (-2.5, 2.5)
ROOMS = [
    ("Cockpit", "Upper", (COCKPIT_OUTLINE[1][0], -81.0), FULL),
    ("Bridge", "Upper", NOSE_X, FULL),
    ("UpperLobby", "Upper", (-57.5, -52), (-2.5, ZI)),
    ("UpperCorridor", "Upper", (-51.5, -19.5), CORR),
    ("MessHall", "Upper", MESS_X, FULL),
]
for _i, _x in enumerate(CABIN_X):
    ROOMS += [(f"Cabin{2 * _i + 1}", "Upper", _x, BACK), (f"Cabin{2 * _i + 2}", "Upper", _x, FRONT)]
for _i, _x in enumerate(CREW_X):
    ROOMS += [(f"Crew{_i + 1}", "Upper", _x, BACK), (f"Crew{_i + 5}", "Upper", _x, FRONT)]
ROOMS += [
    ("SpecimenLab", "Lower", (LAB_OUTLINE[1][0], -81.0), FULL),
    ("MedicalBay", "Lower", NOSE_X, BACK),
    ("NoseCorridor", "Lower", NOSE_X, CORR),
    ("EngineRoom", "Lower", NOSE_X, FRONT),
    ("LowerLobby", "Lower", (-57.5, -52), (-2.5, ZI)),
    ("ShootingRange", "Lower", RANGE_X, BACK),
    ("Armory", "Lower", ARMORY_X, BACK),
    ("LowerCorridor", "Lower", (-51.5, -3.5), CORR),
]
ROOMS += [(name, "Lower", (a, b), FRONT) for name, a, b in VENDORS]
ROOMS += [("CargoBay", None, (-3, 14.5), FULL)]


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


def outline(half):
    """A nose room's whole outline (x, z) from its -z half: around from the box's nose wall at -z to
    the one at +z."""
    return half + [(x, -z) for x, z in reversed(half)]


# --- the skin ---------------------------------------------------------------------------------------
# The hull's model wraps the box with a skin SKIN_MARGIN thick: a half section from the belly's middle
# round to the top's middle (w across, h up, and what the stretch up to the next point is: "hull",
# "hull2" (the belly's darker panels) or "dark" (window belts, the trench)), mirrored for the other
# side; towards the nose the section shrinks to the nose's tip.

SKIN_MARGIN = 0.3
BELLY = BOX_Y[0] - SKIN_MARGIN
# Window belts: dark recessed bands along each deck, the windows in them.
BELTS = [(LOW + 0.7, LOW + 3.3), (UP + 0.8, UP + 3.2)]
BELT_DEPTH = 0.45
# Round and taller than the box, with a flat belly and a trench along the top between two rounded
# ridges.
SKIN = [
    (0.0, BELLY, "hull2"),
    (12.5, BELLY, "hull2"),
    (15.6, BELLY + 0.1, "hull"),
    (16.9, 2.6, "hull"),
    (17.3, BELTS[0][0] - 0.2, "dark"),
    (17.3 - BELT_DEPTH, BELTS[0][0], "dark"),
    (17.4 - BELT_DEPTH, BELTS[0][1], "dark"),
    (17.5, BELTS[0][1] + 0.2, "hull"),
    (17.4, BELTS[1][0] - 0.2, "dark"),
    (17.4 - BELT_DEPTH, BELTS[1][0], "dark"),
    (17.2 - BELT_DEPTH, BELTS[1][1], "dark"),
    (17.2, BELTS[1][1] + 0.2, "hull"),
    (16.6, 12.6, "hull"),
    (15.3, 14.4, "hull"),
    (12.8, 16.0, "dark"),
    (10.8, 16.6, "dark"),
    (10.1, 15.9, "dark"),
    (0.0, 15.9, "dark"),
]
NOSE_X0 = BOX_X[0] - 0.4  # the taper starts in front of the box's nose wall
NOSE_TIP = BOX_X[0] - 25.0
NOSE_HC = 5.6  # the height the nose closes towards (the sensor eye's center)
NOSE_MIN = (0.28, 0.4)  # the tip's section, as a share of the full one (across, up)
TAIL_X = BOX_X[1] + SKIN_MARGIN


def nose_scale(x):
    """The section's scale (across, up) at x: in the nose, rounded in the top view, the top sloping down
    to the eye in the side view."""
    if x >= NOSE_X0:
        return 1.0, 1.0
    t = min(1.0, (NOSE_X0 - x) / (NOSE_X0 - NOSE_TIP))
    across = math.sqrt(max(0.0, 1 - t**2.2))
    up = 1 - t**1.25
    return NOSE_MIN[0] + (1 - NOSE_MIN[0]) * across, NOSE_MIN[1] + (1 - NOSE_MIN[1]) * up


def skin_section(x, profile=None):
    """The skin's half section at x."""
    sw, sh = nose_scale(x)
    return [(w * sw, NOSE_HC + (h - NOSE_HC) * sh, m) for w, h, m in (profile or SKIN)]


def inside_skin(x, w, h, clearance=SKIN_MARGIN):
    """Whether the point (x, |z| = w, y = h) stays `clearance` m inside the skin's outer surface (at
    least the skin's thickness, so nothing pokes into it)."""
    if not NOSE_TIP <= x <= TAIL_X:
        return False
    poly = [(sw, sh) for sw, sh, _ in skin_section(x)]
    poly += [(-sw, sh) for sw, sh in reversed(poly)]
    px, py = abs(w), h
    hit = False
    nearest = math.inf
    for i in range(len(poly)):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
        if (y0 > py) != (y1 > py) and px < x0 + (py - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
        dx, dy = x1 - x0, y1 - y0
        k = max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy or 1.0)))
        nearest = min(nearest, math.hypot(px - x0 - k * dx, py - y0 - k * dy))
    return hit and nearest >= clearance
