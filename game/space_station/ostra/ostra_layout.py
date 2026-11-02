r"""Waypost Ostra's layout, shared by the map's builder (ostra_build.py: collisions, floors, lights, people)
and the asset scripts (assets/space_station/ostra/source/: the shell's kit, the outside, the props): one
deck around a round hub under a dome, the rooms set around it on a round platform.

Station-local axes are the ship's (the map stands where the ship stands, docked): +x = screen right,
+z = towards the camera, y 0 is the deck (where the ramp reaches down). The ship's tail reaches through the
open pressure frame in the hangar's left wall (x 8) up to its ramp door (x 15). Top view, camera at the
bottom:

              +--------+--------+
              | DEPOT  |COUNCIL |
    +---------+---=----+---=----+--------.
    |         |   /          \  |          `.
    |  HANGAR =  |  CONCOURSE |  = GALLERY   )
    |         |   \   (hub)  /  |          .'
    +---------+---=----+---=----+--------'
              |  BAR   | MARKET |
              +--------+--------+

The hub is an octagon (its diagonal faces closed by machinery blocks towards the rooms' corners); the
market is the concourse's part in front of it, with the stalls. Every wall stands on its center line,
WALL m thick.
"""

import math

WALL = 0.5
STUB = 1.0  # what's left of a wall cut away for the camera, in m
DOOR_HEIGHT = 3.0

# --- the sections (x, z between wall centers) ---
X_FRAME, X_HUB0, X_MID, X_HUB1 = 8.0, 44.0, 62.0, 80.0
Z_BACK, Z_HUB, Z_HANGAR = -40.0, 18.0, 28.0
Z_BAR, Z_MARKET = 38.0, 34.0
# The hub: an octagon around HUB, its faces HUB_APOTHEM m from it.
HUB = (62.0, 0.0)
HUB_APOTHEM = 18.0
HUB_SIDE = HUB_APOTHEM * math.tan(math.pi / 8)  # half a face, 7.456 m
# The gallery: a half-round end around GALLERY_CENTER.
GALLERY_CENTER = (100.0, 0.0)
GALLERY_RADIUS = 24.0
GALLERY_SEGMENTS = 12  # the round end's wall pieces (15° each)

# Heights of the rooms' ceilings (the walls between two rooms take the higher one).
H_HANGAR, H_HUB, H_ROOM, H_MARKET, H_GALLERY = 20.0, 12.0, 6.0, 7.0, 10.0
# The pressure frame's opening (game/ship/hull_layout.py: the ship's tail with its nacelles).
MOUTH_HALF, MOUTH_TOP = 27.3, 17.5
# The wide openings: hangar to hub, hub to gallery, hub to market.
CARGO_DOOR = (8.0, 7.0)
GALLERY_OPENING = (8.0, 8.0)
MARKET_ARCH = (6.4, 5.0)
# The side door between the hangar and the depot (in the hangar's right wall).
SIDE_DOOR_Z = -23.0


def hub_corners():
    """The hub's octagon, counter-clockwise from the top view's back left (x, z)."""
    cx, cz = HUB
    a, s = HUB_APOTHEM, HUB_SIDE
    return [
        (cx - s, cz - a),
        (cx - a, cz - s),
        (cx - a, cz + s),
        (cx - s, cz + a),
        (cx + s, cz + a),
        (cx + a, cz + s),
        (cx + a, cz - s),
        (cx + s, cz - a),
    ]


def gallery_arc():
    """The gallery's round end, from its back (z -R) round to its front (z +R), GALLERY_SEGMENTS + 1 points."""
    cx, cz = GALLERY_CENTER
    points = []
    for i in range(GALLERY_SEGMENTS + 1):
        a = -math.pi / 2 + math.pi * i / GALLERY_SEGMENTS
        points.append((cx + GALLERY_RADIUS * math.cos(a), cz + GALLERY_RADIUS * math.sin(a)))
    return points


def rect(x0, x1, z0, z1):
    return [(x0, z0), (x0, z1), (x1, z1), (x1, z0)]


# --- the rooms: node name, sign, floor polygons (x, z; convex), ceiling, RoomPlan boxes ((x0, x1), (z0, z1)) ---
_H = hub_corners()
ROOMS = [
    (
        "Hangar",
        "Hangar",
        [rect(X_FRAME, X_HUB0, -Z_HANGAR, Z_HANGAR)],
        H_HANGAR,
        [((X_FRAME, X_HUB0), (-Z_HANGAR, Z_HANGAR))],
    ),
    (
        "Concourse",
        "Concourse",
        [_H, rect(X_MID, X_HUB1, Z_HUB, Z_MARKET)],
        H_HUB,
        [((X_HUB0, X_HUB1), (-Z_HUB, Z_HUB)), ((X_MID, X_HUB1), (Z_HUB, Z_MARKET))],
    ),
    ("Depot", "Supply depot", [rect(X_HUB0, X_MID, Z_BACK, -Z_HUB)], H_ROOM, [((X_HUB0, X_MID), (Z_BACK, -Z_HUB))]),
    ("Council", "Council office", [rect(X_MID, X_HUB1, Z_BACK, -Z_HUB)], H_ROOM, [((X_MID, X_HUB1), (Z_BACK, -Z_HUB))]),
    ("Bar", "Bar", [rect(X_HUB0, X_MID, Z_HUB, Z_BAR)], H_ROOM, [((X_HUB0, X_MID), (Z_HUB, Z_BAR))]),
    (
        "Gallery",
        "Observation gallery",
        [rect(X_HUB1, GALLERY_CENTER[0], -GALLERY_RADIUS, GALLERY_RADIUS), [GALLERY_CENTER] + gallery_arc()[::-1]],
        H_GALLERY,
        [((X_HUB1, GALLERY_CENTER[0] + GALLERY_RADIUS), (-GALLERY_RADIUS, GALLERY_RADIUS))],
    ),
]
# The market's height (it's the concourse's, but lower than the hub).
ROOM_HEIGHTS = {"Market": H_MARKET}

# --- machinery blocks: the triangles between the hub's diagonal faces and the rooms' corners ---
FILLS = [
    ("FillBackLeft", [_H[1], _H[0], (X_HUB0, -Z_HUB)]),
    ("FillBackRight", [_H[7], _H[6], (X_HUB1, -Z_HUB)]),
    ("FillFrontLeft", [_H[2], (X_HUB0, Z_HUB), _H[3]]),
    ("FillFrontRight", [_H[4], (X_HUB1, Z_HUB), _H[5]]),
]
FILL_HEIGHT = H_HUB

# --- walls: name, from, to (x, z on the center line), height, shown ("station": always, the back walls;
# "cut": the roofs' and the walls facing the camera, cut away to a stub while the viewer is inside),
# doors (distance of the middle from `from`, width, height), windows (distance, width, sill, height) ---


def _along(p0, p1, point):
    """How far `point` (on the line) lies from p0."""
    return math.hypot(point[0] - p0[0], point[1] - p0[1])


def _wall(name, p0, p1, height, group, doors=(), windows=()):
    return {
        "name": name,
        "from": p0,
        "to": p1,
        "height": height,
        "group": group,
        "doors": list(doors),
        "windows": list(windows),
    }


def _evenly(length, count, width, sill, height, margin=0.0):
    """`count` windows spread along a wall `length` m long, `margin` m kept free at both ends."""
    usable = length - 2 * margin
    return [(margin + usable * (i + 0.5) / count, width, sill, height) for i in range(count)]


def _walls():
    walls = []
    hub = _H
    # The hangar: its back wall shows (high windows), its front and the pressure frame are cut.
    walls.append(
        _wall(
            "HangarBack",
            (X_FRAME, -Z_HANGAR),
            (X_HUB0, -Z_HANGAR),
            H_HANGAR,
            "station",
            windows=_evenly(36, 3, 5.0, 8.0, 5.0, 2.0),
        )
    )
    walls.append(
        _wall(
            "HangarFront",
            (X_FRAME, Z_HANGAR),
            (X_HUB0, Z_HANGAR),
            H_HANGAR,
            "cut",
            windows=_evenly(36, 3, 5.0, 8.0, 5.0, 2.0),
        )
    )
    # The line at x 44: the depot's outer wall, the hangar's right wall (the side door to the depot, the cargo
    # door to the hub), the bar's outer wall.
    walls.append(_wall("DepotLeft", (X_HUB0, Z_BACK), (X_HUB0, -Z_HANGAR), H_ROOM, "cut"))
    walls.append(
        _wall(
            "HangarRight",
            (X_HUB0, -Z_HANGAR),
            (X_HUB0, Z_HANGAR),
            H_HANGAR,
            "cut",
            doors=[(SIDE_DOOR_Z + Z_HANGAR, 3.0, DOOR_HEIGHT), (Z_HANGAR, *CARGO_DOOR)],
        )
    )
    walls.append(_wall("BarLeft", (X_HUB0, Z_HANGAR), (X_HUB0, Z_BAR), H_ROOM, "cut"))
    # The depot's and the council's back wall (shown, their windows onto the planet), the council's big one.
    walls.append(
        _wall(
            "DepotBack",
            (X_HUB0, Z_BACK),
            (X_MID, Z_BACK),
            H_ROOM,
            "station",
            windows=_evenly(18, 2, 3.0, 1.2, 2.4, 1.0),
        )
    )
    walls.append(
        _wall("CouncilBack", (X_MID, Z_BACK), (X_HUB1, Z_BACK), H_ROOM, "station", windows=[(9.0, 10.0, 0.9, 3.2)])
    )
    walls.append(_wall("DepotCouncil", (X_MID, Z_BACK), (X_MID, -Z_HUB), H_ROOM, "cut"))
    walls.append(_wall("CouncilRight", (X_HUB1, Z_BACK), (X_HUB1, -GALLERY_RADIUS), H_ROOM, "cut"))
    # The rooms' fronts towards the hub: the machinery blocks' backs and the hub's back face with the doors.
    walls.append(_wall("DepotFront", (X_HUB0, -Z_HUB), hub[0], H_HUB, "cut"))
    walls.append(
        _wall(
            "HubBack",
            hub[0],
            hub[7],
            H_HUB,
            "cut",
            doors=[(58.0 - hub[0][0], 3.0, DOOR_HEIGHT), (66.0 - hub[0][0], 3.0, DOOR_HEIGHT)],
        )
    )
    walls.append(_wall("CouncilFront", hub[7], (X_HUB1, -Z_HUB), H_HUB, "cut"))
    # The hub's diagonal faces (the machinery blocks behind them).
    walls.append(_wall("HubBackLeft", hub[1], hub[0], H_HUB, "cut"))
    walls.append(_wall("HubBackRight", hub[7], hub[6], H_HUB, "cut"))
    walls.append(_wall("HubFrontLeft", hub[2], hub[3], H_HUB, "cut"))
    walls.append(_wall("HubFrontRight", hub[4], hub[5], H_HUB, "cut"))
    # The hub's front face: the bar's door, the arch into the market.
    walls.append(_wall("BarBack", (X_HUB0, Z_HUB), hub[3], H_HUB, "cut"))
    arch = (X_MID + MARKET_ARCH[0] / 2 + 0.3) - hub[3][0]
    walls.append(
        _wall(
            "HubFront", hub[3], hub[4], H_HUB, "cut", doors=[(58.0 - hub[3][0], 3.0, DOOR_HEIGHT), (arch, *MARKET_ARCH)]
        )
    )
    walls.append(_wall("MarketBack", hub[4], (X_HUB1, Z_HUB), H_HUB, "cut"))
    # The bar and the market: partition, fronts with windows.
    walls.append(_wall("BarMarket", (X_MID, Z_HUB), (X_MID, Z_BAR), H_MARKET, "cut"))
    walls.append(
        _wall("BarFront", (X_HUB0, Z_BAR), (X_MID, Z_BAR), H_ROOM, "cut", windows=_evenly(18, 3, 2.6, 1.0, 1.8, 1.0))
    )
    walls.append(
        _wall(
            "MarketFront",
            (X_MID, Z_MARKET),
            (X_HUB1, Z_MARKET),
            H_MARKET,
            "cut",
            windows=_evenly(18, 3, 2.6, 1.0, 2.2, 1.0),
        )
    )
    walls.append(_wall("MarketRight", (X_HUB1, GALLERY_RADIUS), (X_HUB1, Z_MARKET), H_MARKET, "cut"))
    # The gallery: its left wall (the hub's east face, the wide opening), straight back and front, the round end.
    walls.append(
        _wall(
            "GalleryLeft",
            (X_HUB1, -GALLERY_RADIUS),
            (X_HUB1, GALLERY_RADIUS),
            H_HUB,
            "cut",
            doors=[(GALLERY_RADIUS, *GALLERY_OPENING)],
        )
    )
    panes = _evenly(GALLERY_CENTER[0] - X_HUB1, 4, 4.2, 0.6, 7.2, 0.4)
    walls.append(
        _wall(
            "GalleryBack",
            (X_HUB1, -GALLERY_RADIUS),
            (GALLERY_CENTER[0], -GALLERY_RADIUS),
            H_GALLERY,
            "station",
            windows=panes,
        )
    )
    walls.append(
        _wall(
            "GalleryFront",
            (X_HUB1, GALLERY_RADIUS),
            (GALLERY_CENTER[0], GALLERY_RADIUS),
            H_GALLERY,
            "cut",
            windows=panes,
        )
    )
    arc = gallery_arc()
    for i in range(GALLERY_SEGMENTS):
        p0, p1 = arc[i], arc[i + 1]
        mid_z = (p0[1] + p1[1]) / 2
        length = _along(p0, p1, p1)
        group = "station" if mid_z < -0.5 else "cut"
        walls.append(
            _wall(f"GalleryEnd{i + 1}", p0, p1, H_GALLERY, group, windows=[(length / 2, length - 1.4, 0.6, 7.2)])
        )
    return walls


WALLS = _walls()

# --- the platform under it all: a disc around the hub, its top just below the deck ---
PLATFORM_CENTER = (66.0, 0.0)
PLATFORM_RADIUS = 66.0
PLATFORM_TOP = -0.3
