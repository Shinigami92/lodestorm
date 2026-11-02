"""Builds Waypost Ostra's map, game/space_station/ostra/ostra.tscn (a SpaceStation, see
game/space_station/space_station.gd), from its layout (ostra_layout.py): the walls' collision shapes, the
station's own kit (the shell, the outside and the props, models built by assets/space_station/ostra/source/),
the rooms' lights and names, the painted guide lines on the big rooms' floors, the docking clamps, the people,
the ore exchange, who's inside and the rooms' plan. Run it after changing the layout, from the repo root:

    python game/space_station/ostra/ostra_build.py           # writes it
    python game/space_station/ostra/ostra_build.py --check   # fails if it differs (tools/lint.sh python, CI)

Groups (see SpaceStation): under `Walls` what always shows (the floors, the back walls, the cut walls' stubs, the
platform); under `Walls/Cut` the roofs, the outside and every wall facing the camera above its stub, which only
cast shadows while the viewer is inside or aboard the docked ship; the cut walls' window panes hide instead.
"""

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3] / "tools"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "ship"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import ostra_layout as L
from hull_layout import LOWER_SIDE

from greybox import g, sid, vec, write, xform

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "game" / "space_station" / "ostra" / "ostra.tscn"
SCRIPT = "res://game/space_station/space_station.gd"
LOOK = "res://game/space_station/ostra_look.gd"
MODELS = "res://assets/space_station/ostra/"
MATERIALS = "res://game/space_station/materials/"

CUT = "Walls/Cut"
# Where the clamps' pads hold the hull: against its lower sides, under the nacelles.
CLAMP_Z = LOWER_SIDE + 0.3
SEAT = 0.45  # the seats' height: the sitting clip's (SEAT_HEIGHT in tools/blender/humanoid.py)


def yaw(degrees):
    """A turn about the vertical axis (rows, as scenes store them): 0 faces +z, 90 faces +x."""
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return ", ".join(g(round(v, 6) + 0.0) for v in (c, 0, s, 0, 1, 0, -s, 0, c))


def turned(degrees, local):
    """`local` (x, z) turned like `yaw(degrees)` turns a node."""
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return (c * local[0] + s * local[1], -s * local[0] + c * local[1])


# --- the floors' tints per room (around 1: a hue, not a brightness) ---
FLOOR_TINTS = {
    "Hangar": (0.95, 0.97, 1.0),
    "Concourse": (1.06, 1.0, 0.92),
    "Depot": (1.04, 1.02, 0.9),
    "Council": (0.94, 0.97, 1.08),
    "Bar": (1.1, 0.96, 0.86),
    "Gallery": (0.94, 1.0, 1.06),
}

# --- the props: node name, model (assets/space_station/ostra/props/<model>.glb), where (x, z), facing (yaw),
# their collision boxes in their own space (center (x, y, z), size), none for what people walk through ---


def boxes(*items):
    return list(items)


def floor_box(size, at=(0.0, 0.0)):
    """A box standing on the floor at `at` (x, z) in the prop's space."""
    return ((at[0], size[1] / 2, at[1]), size)


STALL = boxes(floor_box((3.0, 1.0, 1.2)), floor_box((3.0, 2.2, 0.4), (0.0, -2.8)))
BOOTH = boxes(
    floor_box((1.6, 0.75, 1.0)),
    floor_box((1.8, SEAT, 0.8), (0.0, -1.3)),
    floor_box((1.8, SEAT, 0.8), (0.0, 1.3)),
    floor_box((1.8, 1.1, 0.15), (0.0, -1.775)),
    floor_box((1.8, 1.1, 0.15), (0.0, 1.775)),
)
CONTAINER = boxes(floor_box((6.0, 2.6, 2.44)))
# The depot: its counter (the exchange's hoppers on it) towards the hub's door, shelves along its side walls.
DEPOT_COUNTER = (53.0, -26.0)
COUNCIL_TABLE = (71.0, -33.25)
BAR_COUNTER = (47.0, 28.0)
BOOTHS = [(59.5, 24.5), (59.5, 31.0)]
STALLS = [(70.5, 25.0), (74.0, 25.0), (77.5, 25.0)]
SUIT_BENCH = (43.2, -17.0)
PROPS = [
    # The hangar: containers along its back wall (one stacked), crates and a spool in front, Wren's bench.
    ("ContainerOlive", "container_olive", (22.0, -24.6), 0, CONTAINER),
    ("ContainerRed", "container_red", (31.0, -24.6), 0, CONTAINER),
    ("ContainerBlueStacked", "container_blue", (31.0, -24.6), 0, [], 2.6),
    ("HangarStack", "crate_stack", (38.4, -25.0), 0, boxes(floor_box((2.4, 2.4, 2.4)))),
    ("HangarMachine", "machine_block", (18.0, -25.6), 0, boxes(floor_box((3.0, 3.0, 2.0)))),
    ("HangarPipes", "pipe_cluster", (26.5, -27.45), 0, boxes(floor_box((1.2, 4.0, 0.6)))),
    ("HangarBarrels", "barrels", (41.2, -26.0), 0, boxes(floor_box((1.2, 1.0, 1.2)))),
    ("HangarCrateLong", "crate_long", (29.0, 24.8), 0, boxes(floor_box((2.4, 1.2, 1.2)))),
    ("HangarCrate", "crate_small", (32.2, 25.0), 0, boxes(floor_box((1.2, 1.2, 1.2)))),
    ("HangarSpool", "cable_spool", (37.5, 24.6), 0, boxes(floor_box((1.2, 1.2, 1.0)))),
    ("HangarLifter", "lifter", (24.0, 23.0), 90, boxes(floor_box((1.4, 2.2, 2.6)))),
    ("WorkLightBack", "work_light", (18.5, -9.0), 0, []),
    ("WorkLightFront", "work_light", (18.5, 9.0), 0, []),
    ("SuitBench", "suit_bench", SUIT_BENCH, -90, boxes(floor_box((2.2, 0.95, 0.9)))),
    ("SuitFrame", "suit_frame", (43.4, -14.8), -90, boxes(floor_box((0.7, 1.9, 0.5)))),
    # The depot.
    ("DepotCounter", "depot_counter", DEPOT_COUNTER, 0, boxes(floor_box((6.0, 1.1, 0.9)))),
    ("DepotShelf1", "depot_shelf", (45.0, -37.2), 90, boxes(floor_box((5.0, 3.5, 1.2)))),
    ("DepotShelf2", "depot_shelf", (45.0, -32.0), 90, boxes(floor_box((5.0, 3.5, 1.2)))),
    ("DepotShelf3", "depot_shelf", (61.0, -37.2), -90, boxes(floor_box((5.0, 3.5, 1.2)))),
    ("DepotLifter", "lifter", (51.0, -36.6), 0, boxes(floor_box((1.4, 2.2, 2.6)))),
    ("DepotBarrels", "barrels", (55.0, -38.8), 0, boxes(floor_box((1.2, 1.0, 1.2)))),
    ("DepotStack", "crate_stack", (58.0, -38.4), 0, boxes(floor_box((2.4, 2.4, 2.4)))),
    ("DepotCart", "hand_cart", (49.0, -22.0), 90, []),
    # The council office: the long table with its chairs, Selin at its head under the big window.
    ("CouncilTable", "council_table", COUNCIL_TABLE, 0, boxes(floor_box((2.4, 0.8, 5.5)))),
    ("CouncilPlanter", "planter", (77.6, -20.0), 180, boxes(floor_box((2.4, 1.0, 0.8)))),
    (
        "CouncilChairLeft1",
        "council_chair",
        (COUNCIL_TABLE[0] + -1.7, COUNCIL_TABLE[1] + -1.75),
        90,
        boxes(floor_box((0.6, 0.9, 0.6))),
    ),
    (
        "CouncilChairRight1",
        "council_chair",
        (COUNCIL_TABLE[0] + 1.7, COUNCIL_TABLE[1] + -1.75),
        -90,
        boxes(floor_box((0.6, 0.9, 0.6))),
    ),
    (
        "CouncilChairLeft2",
        "council_chair",
        (COUNCIL_TABLE[0] + -1.7, COUNCIL_TABLE[1] + 0.0),
        90,
        boxes(floor_box((0.6, 0.9, 0.6))),
    ),
    (
        "CouncilChairRight2",
        "council_chair",
        (COUNCIL_TABLE[0] + 1.7, COUNCIL_TABLE[1] + 0.0),
        -90,
        boxes(floor_box((0.6, 0.9, 0.6))),
    ),
    (
        "CouncilChairLeft3",
        "council_chair",
        (COUNCIL_TABLE[0] + -1.7, COUNCIL_TABLE[1] + 1.75),
        90,
        boxes(floor_box((0.6, 0.9, 0.6))),
    ),
    (
        "CouncilChairRight3",
        "council_chair",
        (COUNCIL_TABLE[0] + 1.7, COUNCIL_TABLE[1] + 1.75),
        -90,
        boxes(floor_box((0.6, 0.9, 0.6))),
    ),
    # The bar: the counter along its left wall (Nell behind it), the back bar behind her, the booths.
    ("BarCounter", "bar_counter", BAR_COUNTER, 90, boxes(floor_box((9.0, 1.1, 0.9)))),
    ("BackBar", "back_bar", (45.85, 28.75), 90, boxes(floor_box((1.3, 1.38, 0.3)))),
    ("BarStool1", "bar_stool", (48.15, 23.9), 0, []),
    ("BarStool2", "bar_stool", (48.15, 32.2), 0, []),
    ("Booth1", "booth", BOOTHS[0], 0, BOOTH),
    ("Booth2", "booth", BOOTHS[1], 0, BOOTH),
    # The hub: the information pillar in its middle, benches either side behind it.
    ("HubBenchLeft", "gallery_bench", (55.0, -11.0), 0, boxes(floor_box((5.0, SEAT, 0.8)))),
    ("HubBenchRight", "gallery_bench", (69.0, -11.0), 0, boxes(floor_box((5.0, SEAT, 0.8)))),
    # The market: three stalls in a row (Dace's first), crates behind them, a planter by the arch.
    ("StallDace", "stall_dace", STALLS[0], 0, boxes(floor_box((3.0, 1.0, 1.2)))),
    ("DaceBench", "dace_bench", (STALLS[0][0], STALLS[0][1] - 3.0), 0, boxes(floor_box((3.0, 0.95, 0.8)))),
    ("StallParts", "stall_parts", STALLS[1], 0, STALL),
    ("StallTrade", "stall_trade", STALLS[2], 0, STALL),
    ("MarketCrates", "crate_stack", (77.0, 20.0), 0, boxes(floor_box((2.4, 2.4, 2.4)))),
    ("MarketBarrels", "barrels", (73.6, 19.6), 0, boxes(floor_box((1.2, 1.0, 1.2)))),
    ("MarketPlanter", "planter", (64.0, 32.6), 0, boxes(floor_box((2.4, 1.0, 0.8)))),
    # The gallery: two benches facing the windows, planters round its end.
    ("GalleryBench1", "gallery_bench", (88.0, -17.0), 0, boxes(floor_box((5.0, SEAT, 0.8)))),
    ("GalleryBench2", "gallery_bench", (104.0, -17.0), 0, boxes(floor_box((5.0, SEAT, 0.8)))),
    ("GalleryPlanter1", "planter", (117.5, -6.0), -90, boxes(floor_box((2.4, 1.0, 0.8)))),
    ("GalleryPlanter2", "planter", (117.5, 6.0), -90, boxes(floor_box((2.4, 1.0, 0.8)))),
]
# The information pillar: a round collision of its own.
KIOSK = (L.HUB, 1.5, 3.2)
# Screens on the walls that always show: where (x, y, z) on the wall's face, facing.
SCREENS = [
    ("DepotScreen", (53.0, 2.2, L.Z_BACK + 0.25), 0),
    ("CouncilScreenLeft", (64.0, 2.0, L.Z_BACK + 0.25), 0),
    ("CouncilScreenRight", (78.0, 2.0, L.Z_BACK + 0.25), 0),
    ("HangarScreen1", (16.0, 3.0, -L.Z_HANGAR + 0.25), 0),
    ("HangarScreen2", (40.0, 3.0, -L.Z_HANGAR + 0.25), 0),
    ("BarScreen", (L.X_HUB0 + 0.25, 2.2, 34.0), 90),
]
# Wall-mounted: the bar's bottle rack behind Nell (its back on the bar's left wall).
WALL_PROPS = [("BarShelf", "bar_wall_shelf", (L.X_HUB0 + 0.25, 28.0), 90)]

# --- the rooms' names: a neon sign on a wall that always shows where there is one (text, where, facing, size) ---
SIGNS = {
    "Hangar": ("Hangar", (26.0, 6.0, -L.Z_HANGAR + 0.6), 0, 96),
    "Concourse": ("Concourse", (47.6, 1.9, -13.8), 45, 56),
    "Depot": ("Supply depot", (53.0, 4.4, L.Z_BACK + 0.6), 0, 48),
    "Council": ("Council office", (71.0, 4.85, L.Z_BACK + 0.6), 0, 40),
    "Bar": ("Bar", (L.X_HUB0 + 0.6, 3.1, 28.0), 90, 56),
    "Gallery": ("Observation gallery", (90.0, 8.6, -L.GALLERY_RADIUS + 0.6), 0, 64),
}
SIGN_COLORS = {
    "Hangar": (1.0, 0.6, 0.16),
    "Concourse": (0.35, 0.95, 0.9),
    "Depot": (1.0, 0.78, 0.3),
    "Council": (0.45, 0.65, 1.0),
    "Bar": (1.0, 0.45, 0.3),
    "Gallery": (0.75, 0.9, 1.0),
}

# --- the guide lines, painted on the big rooms' floors like an airport's: one per place, in its own color,
# from the ramp's foot through the hangar and the hub to the place's door; each with its name painted at its
# start (an arrow along it). Where they share a way they run side by side. ---
LINE_WIDTH = 0.16
LINE_Y = 0.02
LINES = [
    ("Depot", "Supply depot", (0.95, 0.74, 0.18), [(27, -2), (49, -2), (58, -11), (58, -17.6)]),
    (
        "Council",
        "Council office",
        (0.35, 0.6, 1.0),
        [(27, -1), (50.4, -1), (56, -6.6), (62, -6.6), (66, -10.6), (66, -17.6)],
    ),
    (
        "Gallery",
        "Observation gallery",
        (0.86, 0.86, 0.84),
        [(27, 0.0), (56.8, 0.0)]
        + [(L.HUB[0] - 5.2 * math.cos(math.pi * i / 8), -5.2 * math.sin(math.pi * i / 8)) for i in range(1, 8)]
        + [(67.2, 0.0), (98.0, 0.0)],
    ),
    ("Market", "Market", (0.4, 0.85, 0.45), [(27, 1), (50.4, 1), (56, 6.6), (62, 6.6), (66, 10.6), (66, 24.5)]),
    ("Bar", "Bar", (1.0, 0.45, 0.25), [(27, 2), (49, 2), (58, 11), (58, 17.6)]),
]
# The names painted on the floor: at each line's start, and the way back from the hub and the gallery.
# Node name, room it's in, where (x, z), the arrow's direction, the text, its color.
GUIDES = [(f"To{name}", "Hangar", (23.0, line[0][1]), (1, 0), text, color) for name, text, color, line in LINES]
GUIDES += [
    ("ToHangar", "Concourse", (51.0, 3.0), (-1, 0), "Hangar · Ship", (1.0, 0.8, 0.45)),
    ("ToHangar", "Gallery", (94.0, 2.2), (-1, 0), "Concourse · Market · Bar · Hangar · Ship", (1.0, 0.8, 0.45)),
]
# Arrow directions on the floor (the arrow's basis: its head points along it).
ARROWS = {
    (1, 0): "0, 0, -1, 0, 1, 0, 1, 0, 0",
    (-1, 0): "0, 0, 1, 0, 1, 0, -1, 0, 0",
}
LIGHT_SPACING = 12.0

# --- the docking clamps: closed, their pads lie against the hull's sides; SpaceStation opens them. On the
# hull's lower sides under the nacelles: behind it two above each other, in front low along its lower edge ---
CLAMPS = [(11.5, 2.4, -1), (11.5, 4.8, -1), (9.75, 2.4, 1), (13.25, 2.4, 1)]

# --- the station's people: the named NPCs at their places (profile, where (x, z), facing yaw in degrees: 0
# towards the camera, 90 towards +x), then the ambient colonists, each with a profile of their own (profile,
# tint, where, yaw, route: the waypoints they walk in a loop, a waypoint with a yaw (x, z, yaw) the seat where
# they sit down for a while; none: they stand, or sit for good when in SEATED). A seat's spot is where the feet
# are: the hips sit 0.4 m behind it (SIT_BACK in tools/blender/humanoid.py), 0.25 m in from the seat's front
# edge ---
NPC_SCENE = "res://game/npcs/npc.tscn"
COLONIST_SCENE = "res://game/npcs/colonist.tscn"
EXCHANGE_SCENE = "res://game/stations/exchange/ore_exchange.tscn"
PROFILES = "res://game/npcs/ostra/"
CX, CZ = COUNCIL_TABLE
BX, BZ = BAR_COUNTER
PEOPLE = [
    # Beside the depot's counter (the exchange's hoppers on it).
    ("Kade", "depot_master", (DEPOT_COUNTER[0] + 4.1, DEPOT_COUNTER[1] - 1.1), 0),
    # At the head of the long table, the big window behind.
    ("Selin", "councillor", (CX, CZ - 4.05), 0),
    # Behind the bar's counter, close to it (her work reaches across it): used across it (see USE_ACROSS).
    ("Nell", "bartender", (BX - 0.73, BZ), 90),
    # At the booth further in.
    ("Rook", "rival_captain", (BOOTHS[1][0] - 2.3, BOOTHS[1][1]), -90),
]
# Used across their counter: the use point's offset towards the players (along the facing), the
# footprint around it (across, along the facing: from them to the counter's front) and the range
# from there (short, so the camera framing both stays close).
USE_ACROSS = {"Nell": (0.43, (9, 1.5), 1.0)}
# Where else each of them goes now and then (WorkSpot, see NpcRoutine): name, where (x, z), facing, what they do
# there, how likely (their own place: 1; the far ones now and then), and whether they're used there as at their place.
# Outside their own room they only look around, and only once their greeting is heard. TBD (playtest).
WORK_SPOTS = {
    "Kade": [
        ("Shelves", (46.8, -34.6), -90, ["LookAround", "CheckWrist"], 1, False),
        # By the depot's side door to the hangar, watching crates come in.
        ("Door", (46.5, L.SIDE_DOOR_Z), -90, ["LookAround"], 1, False),
    ],
    "Selin": [
        ("Window", (CX - 4.5, CZ - 5.55), 180, ["LookAround"], 1, False),
        ("Gallery", (95.0, -21.0), 180, ["LookAround"], 0.5, False),
        ("Concourse", (66.0, 6.0), 0, ["LookAround"], 0.5, False),
    ],
    "Nell": [
        ("Counter", (BX - 0.73, BZ - 3.0), 90, ["WipeCounter", "PolishGlass"], 1, True),
        # At the open end of the booth with the two guests (nell_clips.py: TABLE_EDGE, TABLE_TOP).
        ("Booth", (BOOTHS[0][0] - 1.1, BOOTHS[0][1]), 90, ["WipeTable", "ClearGlass", "LookAround"], 0.5, False),
    ],
    "Rook": [
        ("Counter", (BX + 1.6, BZ - 2.0), -90, ["LookAround"], 1, False),
        # Looking over the docked ship's tail.
        ("Hangar", (28.0, 9.0), -90, ["LookAround"], 0.5, False),
        ("Gallery", (108.0, 19.0), 0, ["LookAround"], 0.5, False),
    ],
}
# What they do at their own place, where it's not the shared clips' default (NpcRoutine.HOME_ACTIVITIES).
HOME_ACTIVITIES = {"Nell": ["WipeCounter", "PolishGlass", "ShelveBottle"]}
# The crew who join later, at their places until they do (Npc.waits_to_join; see
# docs/planned/crew.md): name, crew profile, where (x, z), facing yaw. Dace at his stall, Wren at her
# suit workbench, Fenna on the back bench of the booth further in (SEATED_CREW: sitting, feet as for a
# seated colonist). Once they join, they walk aboard and their place stays empty.
CREW_PROFILES = "res://game/npcs/crew/"
DACE_X, DACE_Z = STALLS[0]
JOINING = [
    ("Dace", "gunsmith", (DACE_X, DACE_Z - 1.6), 0),
    ("Wren", "suit_tech", (SUIT_BENCH[0] - 1.0, SUIT_BENCH[1]), 90),
    ("Fenna", "cook", (BOOTHS[1][0] - 0.2, BOOTHS[1][1] - 0.75), 0),
]
SEATED_CREW = {"Fenna"}
JOINING_SPOTS = {
    "Dace": [("Bench", (DACE_X, DACE_Z - 2.1), 180, ["LookAround", "CheckWrist"], 1, False)],
    "Wren": [("Frame", (SUIT_BENCH[0] - 0.7, -14.8), 90, ["LookAround", "CheckWrist"], 1, False)],
}
# Dace's stall once he's aboard: its shutter down over the counter (StoryShown), his sign above the
# stall either way. Where (x, z) and the join flag it follows.
DACE_STALL = (STALLS[0], "crew.gunsmith.joined")
B1X, B1Z = BOOTHS[0]
COLONISTS = [
    # At the other two stalls (the first one is Dace's).
    ("Mechanic", "mechanic", (0.95, 0.9, 0.8), (STALLS[1][0], STALLS[1][1] - 1.6), 0, []),
    ("BarterTrader", "barter_trader", (0.8, 0.85, 0.95), (STALLS[2][0], STALLS[2][1] - 1.6), 0, []),
    ("Gardener", "gardener", (0.9, 1, 0.85), (STALLS[1][0], STALLS[1][1] + 1.4), 180, []),
    ("DockHand", "dock_hand", (0.9, 0.95, 1), (BX + 1.4, BZ + 2.8), -90, []),
    # On the first gallery bench, looking out of the windows.
    ("HaulerPilot", "hauler_pilot", (0.85, 0.9, 1), (89.0, -17.55), 180, []),
    # Facing each other in the booth by the door (the other one is Rook's).
    ("WaterTechnician", "water_technician", (0.85, 0.95, 0.95), (B1X - 0.2, B1Z - 0.75), 0, []),
    ("Metalworker", "metalworker", (1, 0.9, 0.8), (B1X + 0.2, B1Z + 0.75), 180, []),
    ("DepotClerk", "depot_clerk", (1, 1, 1), (59.6, -36.4), 90, []),
    ("Loader", "loader", (1, 0.95, 0.85), (22.0, -20.0), 90, [(40.0, -20.0), (22.0, -20.0)]),
    ("Courier", "courier", (0.95, 1, 0.95), (24.0, 3.5), 90, [(98.0, 3.5), (24.0, 3.5)]),
    ("MaintenanceTech", "maintenance_tech", (0.9, 0.9, 1), (50.0, -6.0), 90, [(74.0, -6.0), (50.0, -6.0)]),
    # Around the gallery, sitting down on the second bench for a while (round its end, on the window side).
    (
        "Teacher",
        "teacher",
        (1, 0.9, 0.95),
        (82.0, -11.0),
        90,
        [
            (99.0, -19.0),
            (104.5, -17.55, 180),
            (108.0, -19.0),
            (112.0, -11.0),
            (112.0, 17.0),
            (82.0, 17.0),
            (82.0, -11.0),
        ],
    ),
]
SEATED = {"HaulerPilot", "WaterTechnician", "Metalworker"}

# ------------------------------------------------------------------------------------------------------------

subs = []
nodes = ['[node name="Ostra" type="Node3D"]', 'script = ExtResource("script")', ""]
ext = [
    ("Script", SCRIPT, "script"),
    ("Script", LOOK, "look"),
    ("Script", "res://game/world/room_plan.gd", "room_plan"),
    ("Script", "res://game/npcs/work_spot.gd", "work_spot"),
    ("Script", "res://game/ship/floor_guide.gd", "guide_script"),
    ("PackedScene", NPC_SCENE, "npc"),
    ("PackedScene", COLONIST_SCENE, "colonist"),
    ("PackedScene", EXCHANGE_SCENE, "exchange"),
    ("PackedScene", "res://game/ship/neon_sign.tscn", "neon_sign"),
    ("Script", "res://game/story/story_shown.gd", "story_shown"),
    ("Material", f"{MATERIALS}ostra_paint_dark.tres", "mat_dark"),
]
models = {}


def model(path):
    """The ext_resource id of a model (a .glb under MODELS)."""
    if path not in models:
        rid = "model_" + path.replace("/", "_")
        models[path] = rid
        ext.append(("PackedScene", f"{MODELS}{path}.glb", rid))
    return models[path]


shapes = {}


def box_shape(size):
    key = sid(size)
    if key not in shapes:
        shapes[key] = True
        subs.extend([f'[sub_resource type="BoxShape3D" id="BoxShape3D_{key}"]', f"size = {vec(size)}", ""])
    return f"BoxShape3D_{key}"


collision_count = 0


def collision(name, center, size, basis="1, 0, 0, 0, 1, 0, 0, 0, 1"):
    global collision_count
    collision_count += 1
    nodes.extend(
        [
            f'[node name="{name}" type="CollisionShape3D" parent="Walls"]',
            f"transform = {xform(center, basis)}",
            f'shape = SubResource("{box_shape(size)}")',
            "",
        ]
    )


def look(name, parent, path, transform=None, interior=True, tints=None, groups=None):
    """A model of the station's kit with its materials swapped in (OstraLook)."""
    head = f'[node name="{name}" parent="{parent}"'
    if groups:
        head += " groups=[" + ", ".join(f'"{gr}"' for gr in groups) + "]"
    lines = [head + f' instance=ExtResource("{model(path)}")]']
    if transform:
        lines.append(f"transform = {transform}")
    lines.append('script = ExtResource("look")')
    if not interior:
        lines.append("interior = false")
    if tints:
        pairs = ", ".join(f'&"{room}": Color({", ".join(g(c) for c in tint)}, 1)' for room, tint in tints.items())
        lines.append(f"floor_tints = Dictionary[StringName, Color]({{{pairs}}})")
    nodes.extend(lines + [""])


# --- the walls' bodies: every wall's solid stretches (doors left open), the columns, the machinery blocks, the
# deck under it all, the furniture ---
nodes += ['[node name="Walls" type="StaticBody3D" parent="."]', ""]
# The cut-away parts don't show in the navigator's hologram either: it shows the rooms from above.
nodes += ['[node name="Cut" type="Node3D" parent="Walls" groups=["hidden_in_hologram"]]', ""]
x_end = L.GALLERY_CENTER[0] + L.GALLERY_RADIUS
collision(
    "Deck",
    ((L.X_FRAME + x_end) / 2, -0.5, (L.Z_BACK + L.Z_BAR) / 2),
    (x_end - L.X_FRAME + 0.5, 1, L.Z_BAR - L.Z_BACK + 0.5),
)
for wall in L.WALLS:
    (x0, z0), (x1, z1) = wall["from"], wall["to"]
    length = math.hypot(x1 - x0, z1 - z0)
    ux, uz = (x1 - x0) / length, (z1 - z0) / length
    basis = yaw(math.degrees(math.atan2(-uz, ux)) - 90)
    spans, t = [], 0.0
    for d, w, _h in sorted(wall["doors"]):
        if d - w / 2 > t:
            spans.append((t, d - w / 2))
        t = d + w / 2
    if length > t:
        spans.append((t, length))
    for i, (a, b) in enumerate(spans):
        mid = (a + b) / 2
        center = (x0 + ux * mid, wall["height"] / 2, z0 + uz * mid)
        # The box's own z runs along the wall (yaw - 90 turns +z onto the wall's direction).
        collision(f"{wall['name']}{i + 1}", center, (L.WALL, wall["height"], b - a), basis)
corners = {}
for wall in L.WALLS:
    for p in (wall["from"], wall["to"]):
        corners[(round(p[0], 2), round(p[1], 2))] = max(
            corners.get((round(p[0], 2), round(p[1], 2)), 0), wall["height"]
        )
for i, ((x, z), height) in enumerate(sorted(corners.items())):
    collision(f"Column{i + 1}", (x, height / 2, z), (1.0, height, 1.0))
for name, poly in L.FILLS:
    points = ", ".join(f"{g(x)}, {g(y)}, {g(z)}" for x, z in poly for y in (0.0, L.FILL_HEIGHT))
    subs.extend([f'[sub_resource type="ConvexPolygonShape3D" id="ConvexPolygonShape3D_{name}"]'])
    subs.extend([f"points = PackedVector3Array({points})", ""])
    nodes.extend(
        [
            f'[node name="{name}" type="CollisionShape3D" parent="Walls"]',
            f'shape = SubResource("ConvexPolygonShape3D_{name}")',
            "",
        ]
    )
# The pressure frame's header and jambs, around the hull.
collision(
    "FrameHeader", (L.X_FRAME, (L.MOUTH_TOP + L.H_HANGAR) / 2, 0), (1.5, L.H_HANGAR - L.MOUTH_TOP, 2 * L.Z_HANGAR)
)
for s, name in ((-1, "Back"), (1, "Front")):
    collision(
        f"FrameJamb{name}", (L.X_FRAME + 0.5, L.MOUTH_TOP / 2, s * (L.MOUTH_HALF + 0.75)), (1.5, L.MOUTH_TOP, 1.5)
    )
for name, _model, (px, pz), facing, shapes_, *_rest in PROPS:
    for i, (center, size) in enumerate(shapes_):
        lx, lz = turned(facing, (center[0], center[2]))
        collision(
            f"{name}Shape{i + 1}" if len(shapes_) > 1 else f"{name}Shape",
            (px + lx, center[1], pz + lz),
            size,
            yaw(facing),
        )
(kx, kz), kr, kh = KIOSK
subs.extend(
    ['[sub_resource type="CylinderShape3D" id="CylinderShape3D_kiosk"]', f"height = {g(kh)}", f"radius = {g(kr)}", ""]
)
nodes.extend(
    [
        '[node name="KioskShape" type="CollisionShape3D" parent="Walls"]',
        f"transform = {xform((kx, kh / 2, kz))}",
        'shape = SubResource("CylinderShape3D_kiosk")',
        "",
    ]
)

# --- the models: the shell (its stubs, floors and back walls always, the rest cut away), the outside ---
tints = {room: FLOOR_TINTS[room] for room in FLOOR_TINTS}
look("Shell", "Walls", "shell/shell_station", tints=tints)
look("Glass", "Walls", "shell/glass_station")
look("Platform", "Walls", "exterior/exterior_platform", interior=False)
look("ShellCut", CUT, "shell/shell_cut")
look("GlassCut", CUT, "shell/glass_cut", groups=["cutaway_hide"])
look("Roofs", CUT, "exterior/exterior_roofs", interior=False)
look("Structures", CUT, "exterior/exterior_structures", interior=False)
# The clamps' mounts beside the hull, under the nacelles: machine blocks, low enough to keep the hull in view.
for side, name in [(-1, "Back"), (1, "Front")]:
    look(
        f"ClampMount{name}",
        CUT,
        "props/machine_block",
        xform((11.5, 0, side * (CLAMP_Z + 5.3)), yaw(0 if side < 0 else 180)),
    )
    collision(f"ClampMount{name}Shape", (11.5, 1.5, side * (CLAMP_Z + 5.3)), (3.0, 3.0, 2.0))

# --- the props ---
nodes += ['[node name="Props" type="Node3D" parent="."]', ""]
for name, path, (px, pz), facing, _shapes, *rest in PROPS:
    y = rest[0] if rest else 0.0
    look(name, "Props", f"props/{path}", xform((px, y, pz), yaw(facing)))
look("Kiosk", "Props", "props/kiosk", xform((kx, 0, kz)))
for name, (x, y, z), facing in SCREENS:
    look(name, "Props", "props/wall_screen", xform((x, y, z), yaw(facing)))
for name, path, (x, z), facing in WALL_PROPS:
    look(name, "Props", f"props/{path}", xform((x, 0, z), yaw(facing)))

# --- the rooms: lights, names ---
nodes += ['[node name="Rooms" type="Node3D" parent="."]', ""]
SPOT_DOWN = "1, 0, 0, 0, 0, 1, 0, -1, 0"
for name, _sign, _polys, height, areas in L.ROOMS:
    nodes += [f'[node name="{name}" type="Node3D" parent="Rooms"]', ""]
    count = 0
    for (x0, x1), (z0, z1) in areas:
        top = L.ROOM_HEIGHTS["Market"] if name == "Concourse" and z0 >= L.Z_HUB else height
        nx = max(1, round((x1 - x0) / LIGHT_SPACING))
        nz = max(1, round((z1 - z0) / LIGHT_SPACING))
        for ix in range(nx):
            for iz in range(nz):
                count += 1
                lx = x0 + (x1 - x0) * (ix + 0.5) / nx
                lz = z0 + (z1 - z0) * (iz + 0.5) / nz
                nodes += [
                    f'[node name="Light{count}" type="SpotLight3D" parent="Rooms/{name}"]',
                    f"transform = {xform((lx, top - 0.4, lz), SPOT_DOWN)}",
                    "light_color = Color(1, 0.84, 0.62, 1)",
                    f"light_energy = {g(5.0 + top * 0.4)}",
                    f"spot_range = {g(top + 2.0)}",
                    "spot_angle = 66.0",
                    "spot_angle_attenuation = 0.7",
                    "",
                    # A warm fill that reaches the walls.
                    f'[node name="Fill{count}" type="OmniLight3D" parent="Rooms/{name}"]',
                    f"transform = {xform((lx, min(top - 1.0, 5.0), lz))}",
                    "light_color = Color(1, 0.78, 0.55, 1)",
                    "light_energy = 0.9",
                    f"omni_range = {g(LIGHT_SPACING * 1.1)}",
                    "omni_attenuation = 1.4",
                    "",
                ]
    text, (sx, sy, sz), facing, size = SIGNS[name]
    color = SIGN_COLORS[name]
    nodes += [
        f'[node name="Sign" parent="Rooms/{name}" instance=ExtResource("neon_sign")]',
        f"transform = {xform((sx, sy, sz), yaw(facing))}",
        f'text = "{text}"',
        f"color = Color({', '.join(g(c) for c in color)}, 1)",
        f"font_size = {size}",
        "",
    ]

# --- the guide lines and their names on the floor ---
line_materials = {}
for name, _text, color, _points in LINES:
    rid = f"StandardMaterial3D_line_{name}"
    line_materials[name] = rid
    rgb = ", ".join(g(c) for c in color)
    subs += [
        f'[sub_resource type="StandardMaterial3D" id="{rid}"]',
        f"albedo_color = Color({rgb}, 1)",
        "roughness = 0.55",
        "emission_enabled = true",
        f"emission = Color({rgb}, 1)",
        "emission_energy_multiplier = 0.35",
        "",
    ]
subs += ['[sub_resource type="PrismMesh" id="PrismMesh_arrow"]', "size = Vector3(0.7, 0.55, 0.004)", ""]
subs += ['[sub_resource type="BoxMesh" id="BoxMesh_arrow_shaft"]', "size = Vector3(0.22, 0.45, 0.004)", ""]
segment_meshes = {}
nodes += ['[node name="GuideLines" type="Node3D" parent="Rooms"]', ""]
for name, _text, _color, points in LINES:
    nodes += [f'[node name="{name}" type="Node3D" parent="Rooms/GuideLines"]', ""]
    for i in range(len(points) - 1):
        (x0, z0), (x1, z1) = points[i], points[i + 1]
        length = math.hypot(x1 - x0, z1 - z0) + LINE_WIDTH
        key = (name, round(length, 3))
        if key not in segment_meshes:
            rid = f"BoxMesh_line_{name}_{sid((length,))}"
            segment_meshes[key] = rid
            subs += [
                f'[sub_resource type="BoxMesh" id="{rid}"]',
                f'material = SubResource("{line_materials[name]}")',
                f"size = Vector3({g(LINE_WIDTH)}, 0.004, {g(length)})",
                "",
            ]
        angle = math.degrees(math.atan2(x1 - x0, z1 - z0))
        nodes += [
            f'[node name="Segment{i + 1}" type="MeshInstance3D" parent="Rooms/GuideLines/{name}"]',
            "layers = 4",
            f"transform = {xform(((x0 + x1) / 2, LINE_Y, (z0 + z1) / 2), yaw(angle))}",
            "cast_shadow = 0",
            f'mesh = SubResource("{segment_meshes[key]}")',
            "",
        ]


def flat(origin):
    """A label or plane lying on the floor, readable from the camera."""
    return xform(origin, "1, 0, 0, 0, 0, 1, 0, -1, 0")


guide_materials = {}
for gname, room, (gx, gz), direction, text, color in GUIDES:
    rgb = ", ".join(g(c) for c in color)
    if rgb not in guide_materials:
        rid = f"StandardMaterial3D_guide_{len(guide_materials) + 1}"
        guide_materials[rgb] = rid
        subs += [
            f'[sub_resource type="StandardMaterial3D" id="{rid}"]',
            "shading_mode = 0",
            f"albedo_color = Color({rgb}, 1)",
            "",
        ]
    mat = guide_materials[rgb]
    guides = f"Rooms/{room}/Guides"
    if f'[node name="Guides" type="Node3D" parent="Rooms/{room}"]' not in nodes:
        nodes += [f'[node name="Guides" type="Node3D" parent="Rooms/{room}"]', ""]
    path = f"{guides}/{gname}"
    nodes += [
        f'[node name="{gname}" type="Node3D" parent="{guides}"]',
        f"transform = {xform((gx, 0, gz))}",
        'script = ExtResource("guide_script")',
        "",
        f'[node name="Arrow" type="Node3D" parent="{path}"]',
        f"transform = {xform((direction[0] * 1.2, LINE_Y + 0.004, 0), ARROWS[direction])}",
        "",
        f'[node name="Head" type="MeshInstance3D" parent="{path}/Arrow"]',
        f"transform = {flat((0, 0, -0.1))}",
        "cast_shadow = 0",
        f'material_override = SubResource("{mat}")',
        'mesh = SubResource("PrismMesh_arrow")',
        "",
        f'[node name="Shaft" type="MeshInstance3D" parent="{path}/Arrow"]',
        f"transform = {flat((0, 0, 0.3))}",
        "cast_shadow = 0",
        f'material_override = SubResource("{mat}")',
        'mesh = SubResource("BoxMesh_arrow_shaft")',
        "",
        f'[node name="Text" type="Label3D" parent="{path}"]',
        f"transform = {flat((0, LINE_Y + 0.004, 0))}",
        "pixel_size = 0.01",
        f"modulate = Color({rgb}, 1)",
        f'text = "{text}"',
        "font_size = 40",
        "outline_size = 10",
        "uppercase = true",
        "",
    ]

# --- the clamps ---
nodes += ['[node name="Clamps" type="Node3D" parent="."]', ""]
for i, (x, y, side) in enumerate(CLAMPS):
    # The model's arm reaches towards +z: the front ones as they are, the back ones turned round.
    nodes += [
        f'[node name="Clamp{i + 1}" type="Node3D" parent="Clamps"]',
        f"transform = {xform((x, y, side * CLAMP_Z))}",
        "",
    ]
    look("Model", f"Clamps/Clamp{i + 1}", "props/clamp", xform((0, 0, 0), yaw(0 if side > 0 else 180)), interior=False)

# --- the people ---
nodes += ['[node name="People" type="Node3D" parent="."]', ""]


def names(items):
    return ", ".join(f'&"{item}"' for item in items)


def spot_nodes(name, spots):
    out = []
    for spot, (sx, sz), sfacing, activities, weight, like_home in spots:
        out += [
            f'[node name="{name}{spot}" type="Marker3D" parent="People"]',
            f"transform = {xform((sx, 0, sz), yaw(sfacing))}",
            'script = ExtResource("work_spot")',
            f"activities = Array[StringName]([{names(activities)}])",
        ]
        out += [f"weight = {g(weight)}"] if weight != 1 else []
        out += ["use_like_home = true"] if like_home else []
        out += [""]
    return out


for name, profile, (px, pz), facing in PEOPLE:
    spots = WORK_SPOTS.get(name, [])
    paths = ", ".join(f'NodePath("../{name}{spot[0]}")' for spot in spots)
    nodes += [
        f'[node name="{name}" parent="People" node_paths=PackedStringArray("work_spots") instance=ExtResource("npc")]',
        f"transform = {xform((px, 0, pz), yaw(facing))}",
        f'profile = ExtResource("profile_{profile}")',
        f"work_spots = [{paths}]",
    ]
    if name in HOME_ACTIVITIES:
        nodes += [f"home_activities = Array[StringName]([{names(HOME_ACTIVITIES[name])}])"]
    nodes += [""]
    nodes += spot_nodes(name, spots)
    if name in USE_ACROSS:
        ahead, (across, along), reach = USE_ACROSS[name]
        nodes += [
            f'[node name="Use" parent="People/{name}"]',
            f"transform = {xform((0, 0, ahead))}",
            f"interact_range = {g(reach)}",
            f"footprint = Vector2({g(across)}, {g(along)})",
            "",
            f'[node name="Highlight" parent="People/{name}/Use"]',
            f"transform = {xform((0, 0.02, -ahead))}",
            "",
        ]
for name, profile, (px, pz), facing in JOINING:
    spots = JOINING_SPOTS.get(name, [])
    paths = ", ".join(f'NodePath("../{name}{spot[0]}")' for spot in spots)
    nodes += [
        f'[node name="{name}" parent="People" node_paths=PackedStringArray("work_spots") instance=ExtResource("npc")]',
        f"transform = {xform((px, 0, pz), yaw(facing))}",
        f'profile = ExtResource("crew_{profile}")',
        f"work_spots = [{paths}]",
    ]
    nodes += ["seated = true"] if name in SEATED_CREW else []
    nodes += ["waits_to_join = true", ""]
    nodes += spot_nodes(name, spots)
(stall_x, stall_z), stall_flag = DACE_STALL
nodes += [
    '[node name="DaceStall" type="Node3D" parent="."]',
    f"transform = {xform((stall_x, 0, stall_z))}",
    "",
    # Above his workbench behind him, under the awning's back, so it never covers him.
    '[node name="Sign" parent="DaceStall" instance=ExtResource("neon_sign")]',
    f"transform = {xform((0, 2.75, -1.9))}",
    'text = "Dace · Machinist"',
    "color = Color(0.45, 0.8, 1, 1)",
    "font_size = 32",
    "",
    '[node name="Shutter" type="Node3D" parent="DaceStall"]',
    'script = ExtResource("story_shown")',
    f'flag = &"{stall_flag}"',
    "",
    '[node name="Mesh" type="MeshInstance3D" parent="DaceStall/Shutter"]',
    f"transform = {xform((0, 1.15, 0.7))}",
    'mesh = SubResource("BoxMesh_shutter")',
    "",
]
subs += [
    '[sub_resource type="BoxMesh" id="BoxMesh_shutter"]',
    'material = ExtResource("mat_dark")',
    "size = Vector3(3.2, 2.3, 0.08)",
    "",
]
for name, profile, tint, (px, pz), facing, route in COLONISTS:
    nodes += [
        f'[node name="{name}" parent="People" instance=ExtResource("colonist")]',
        f"transform = {xform((px, 0, pz), yaw(facing))}",
        f'profile = ExtResource("colonist_{profile}")',
        f"tint = Color({', '.join(g(c) for c in tint)}, 1)",
    ]
    if route:
        nodes += ["route = PackedVector3Array(" + ", ".join(f"{g(w[0])}, 0, {g(w[1])}" for w in route) + ")"]
    for i, waypoint in enumerate(route):
        if len(waypoint) == 3:
            nodes += [f"seat_stop = {i}", f"seat_yaw = {g(waypoint[2])}"]
    if name in SEATED:
        nodes += ["seated = true"]
    nodes += [""]

# --- the ore exchange: its hoppers on the depot's counter (its origin: the counter's middle on the deck, see
# ExchangeStation) ---
nodes += [
    '[node name="OreExchange" parent="." instance=ExtResource("exchange")]',
    f"transform = {xform((DEPOT_COUNTER[0], 0, DEPOT_COUNTER[1]))}",
    "",
]

# --- who's inside: the cut-away and the indoor light follow it; the rooms' areas, for what people say where
# they stand (RoomPlan) ---
nodes += ['[node name="Interior" type="Area3D" parent="."]', "monitorable = false", ""]
plan_names, plan_areas = [], []
count = 0
for name, _sign, _polys, height, areas in L.ROOMS:
    for (x0, x1), (z0, z1) in areas:
        top = L.ROOM_HEIGHTS["Market"] if name == "Concourse" and z0 >= L.Z_HUB else height
        count += 1
        size = (x1 - x0, top, z1 - z0)
        key = sid(size)
        if f"BoxShape3D_inside_{key}" not in "".join(subs):
            subs += [f'[sub_resource type="BoxShape3D" id="BoxShape3D_inside_{key}"]', f"size = {vec(size)}", ""]
        nodes += [
            f'[node name="{name}{count}" type="CollisionShape3D" parent="Interior"]',
            f"transform = {xform(((x0 + x1) / 2, top / 2, (z0 + z1) / 2))}",
            f'shape = SubResource("BoxShape3D_inside_{key}")',
            "",
        ]
        plan_names.append(f'&"{name}"')
        plan_areas.append(f"AABB({g(x0)}, 0, {g(z0)}, {g(x1 - x0)}, {g(top)}, {g(z1 - z0)})")
nodes += [
    '[node name="RoomPlan" type="Node3D" parent="."]',
    'script = ExtResource("room_plan")',
    f"rooms = Array[StringName]([{', '.join(plan_names)}])",
    f"areas = Array[AABB]([{', '.join(plan_areas)}])",
    "",
]

for profile in sorted({p[1] for p in PEOPLE}):
    ext.append(("Resource", f"{PROFILES}{profile}.tres", f"profile_{profile}"))
for profile in sorted({j[1] for j in JOINING}):
    ext.append(("Resource", f"{CREW_PROFILES}{profile}.tres", f"crew_{profile}"))
for profile in sorted({c[1] for c in COLONISTS}):
    ext.append(("Resource", f"{PROFILES}colonists/{profile}.tres", f"colonist_{profile}"))
out = write(OUT, ROOT, ext, subs, nodes, "ostra_build.py")
if out:
    print(collision_count, "collision boxes,", len(models), "models,", out.count("[node "), "nodes")
