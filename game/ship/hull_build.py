"""Builds the ship's greybox hull, game/ship/hull.tscn: floors, walls with doors and windows, the
upper deck's slab, the roof, and the shapes of the nose and the landing legs (their look is the
hull's model, ShipExterior). Run it after changing the layout, from the repo root:

    python game/ship/hull_build.py           # writes it
    python game/ship/hull_build.py --check   # fails if it differs (tools/lint.sh python, CI)

Only hull.tscn is written; the rooms are scenes of their own (game/ship/rooms/), placed in
ship.tscn. They must match the layout (game/ship/hull_layout.py: ROOMS, position and size), so
moving a room means changing it there, rebuilding, and moving the room's scene and resizing its
floor by hand. Axes and sections: see hull_layout.py.

Groups (see Ship): "hull" always shows; "lower_cut" only casts shadows while the viewer is on the
lower deck; "upper" only casts shadows while the viewer is on the lower deck; "upper_cut" (inside
upper) only casts shadows while the viewer is aboard. A wall in front of what the camera must see
is cut away, leaving a stub (STUB m high) in the always-visible group. The walls, windows and the
writing are the shared greybox helpers' (tools/greybox.py).
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from hull_layout import (
    ARMORY_X,
    CABIN_X,
    CREW_X,
    CW,
    GEAR,
    LEG_PAD,
    LEG_X,
    LEG_Z,
    LOW,
    RAMP_DOOR_HEIGHT,
    RAMP_WIDTH,
    RANGE_DOOR,
    SLAB,
    TOP,
    UP,
    VENDORS,
    ZI,
    outer_windows,
)

from greybox import Greybox, g, sid, vec, write, xform

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "ship" / "hull.tscn"

STUB = 1.0
GROUP_PARENT = {"hull": ".", "lower_cut": "LowerCut", "upper": "Upper", "upper_cut": "Upper/Cut"}
HULL_MATERIAL = ["albedo_color = Color(0.3, 0.31, 0.33, 1)", "metallic = 0.2", "roughness = 0.6"]
box_kit = Greybox(GROUP_PARENT, "hull", HULL_MATERIAL, stub=STUB, door=3.0, sill=1.0, window_height=2.0)
wall = box_kit.wall
box = box_kit.box
outer_wall = box_kit.outer_wall


LOWER_FRONT = ("lower_cut", "hull")
UPPER_FRONT = ("upper_cut", "upper")

# --- outer hull ---
box("Floor", (96, 1, 30), (-33, LOW - 0.5, 0))
# The tail wall with the ramp door.
JAMB = ZI - RAMP_WIDTH / 2
box("RightWallBack", (0.5, 8.5, JAMB), (14.75, (LOW + TOP) / 2, -(ZI - JAMB / 2)))
box("RightWallFront", (0.5, 8.5, JAMB), (14.75, (LOW + TOP) / 2, ZI - JAMB / 2), "lower_cut")
LINTEL = TOP - LOW - RAMP_DOOR_HEIGHT
box("DoorLintel", (0.5, LINTEL, RAMP_WIDTH), (14.75, TOP - LINTEL / 2, 0), "lower_cut")
# Keeps players and aliens from walking under the ship, between the legs.
box("Underside", (96, GEAR, 30), (-33, GEAR / 2, 0), kind="shape")
box("Roof", (96, 0.5, 30), (-33, TOP + 0.25, 0), "upper_cut")
# Upper floor, except over the lift shafts and the cargo bay.
box("SlabNose", (23, 0.5, 29), (-69, SLAB + 0.25, 0), "upper")
box("SlabLobbyBack", (5.5, 0.5, 6.5), (-54.75, SLAB + 0.25, -11.25), "upper")
box("SlabLobbyFront", (5.5, 0.5, 17.5), (-54.75, SLAB + 0.25, 5.75), "upper")
box("SlabMiddle", (49, 0.5, 29), (-27.5, SLAB + 0.25, 0), "upper")

# --- walls through both decks ---
for name, x in [("NoseSectionWall", -57.75), ("LobbyWall", -51.75)]:
    wall(name + "Lower", "z", x, -ZI, ZI, LOW, UP, doors=[(0, 3)], front=LOWER_FRONT)
    wall(name + "Upper", "z", x, -ZI, ZI, UP, TOP, doors=[(0, 3)], front=UPPER_FRONT)
wall("CargoWallLower", "z", -3.25, -ZI, ZI, LOW, UP, doors=[(0, 3)], front=LOWER_FRONT)
wall("CargoWallUpper", "z", -3.25, -ZI, ZI, UP, TOP, doors=[(-12, 3), (3, 0)], front=UPPER_FRONT)
# Lift shafts. By the lobby: behind the corridor, gates in the corridor wall on both decks.
wall("NoseShaftBack", "x", -8.25, -57.5, -52, LOW, TOP)
wall("LobbyCorridorBackLower", "x", -CW, -57.5, -52, LOW, UP, [(-54.75, 4)], "lower_cut", "hull")
wall("LobbyCorridorBackUpper", "x", -CW, -57.5, -52, UP, TOP, [(-54.75, 4)], "upper_cut", "upper")
# In the cargo bay's back corner: gate towards the cargo bay below, door into the mess hall above.
wall("CargoShaftFrontLower", "x", -9.25, -3, 2.5, LOW, UP, [(-0.5, 4)], "lower_cut", "hull")
wall("CargoShaftFrontUpper", "x", -9.25, -3, 2.5, UP, TOP, group="upper_cut", stub_group="upper")
wall("CargoShaftSide", "z", 2.25, -ZI, -9.5, LOW, TOP)

# --- lower deck ---
wall("NoseCorridorBack", "x", -CW, -80.5, -58, LOW, SLAB, [(-69.25, 3)], "lower_cut", "hull")
wall("NoseCorridorFront", "x", CW, -80.5, -58, LOW, SLAB, [(-69.25, 3)], "lower_cut", "hull")
range_doors = [(RANGE_DOOR, 2), ((ARMORY_X[0] + ARMORY_X[1]) / 2, 3)]
vendor_doors = [((a + b) / 2, 3) for _, a, b in VENDORS]
wall("LowerCorridorBack", "x", -CW, -51.5, -3.5, LOW, SLAB, range_doors, "lower_cut", "hull")
wall("LowerCorridorFront", "x", CW, -51.5, -3.5, LOW, SLAB, vendor_doors, "lower_cut", "hull")
wall("ArmoryWall", "z", -21.75, -ZI, -3, LOW, SLAB)
for i, (_, _, b) in enumerate(VENDORS[:-1]):
    wall(f"VendorWall{i + 1}", "z", b + 0.25, 3, ZI, LOW, SLAB, front=LOWER_FRONT)

# --- upper deck ---
wall("CockpitWall", "z", -72.25, -ZI, ZI, UP, TOP, doors=[(0, 3)], group="upper", front=UPPER_FRONT)
blocks = CABIN_X + CREW_X
for i, (_, b) in enumerate(blocks):
    name = "MessWall" if i == len(blocks) - 1 else f"CabinWall{i + 1}"
    wall(name + "Back", "z", b + 0.25, -ZI, -3, UP, TOP, group="upper")
    wall(name + "Front", "z", b + 0.25, 3, ZI, UP, TOP, group="upper", front=UPPER_FRONT)
cabin_doors = [((a + b) / 2, 1.5) for a, b in blocks]
wall("UpperCorridorBack", "x", -CW, -51.5, -19.5, UP, TOP, cabin_doors, "upper_cut", "upper")
wall("UpperCorridorFront", "x", CW, -51.5, -19.5, UP, TOP, cabin_doors, "upper_cut", "upper")

# --- outer walls with windows ---
outer_wall("BackWallLower", "x", -14.75, -81, 15, LOW, UP, outer_windows("Lower", -1))
outer_wall("BackWallUpper", "x", -14.75, -81, 15, UP, TOP, outer_windows("Upper", -1))
outer_wall("FrontWallLower", "x", 14.75, -81, 15, LOW, UP, outer_windows("Lower", 1), "lower_cut", "hull")
outer_wall("FrontWallUpper", "x", 14.75, -81, 15, UP, TOP, outer_windows("Upper", 1), "upper_cut", "upper")
# The nose cone sits in front of the lower deck; the cockpit looks out over it.
outer_wall("NoseWallLower", "z", -80.75, -ZI, ZI, LOW, UP, [])
outer_wall("NoseWallUpper", "z", -80.75, -ZI, ZI, UP, TOP, [(-4.5, 7), (4.5, 7)])


# --- sub-resources ---
subs = box_kit.subresources()
subs += [
    '[sub_resource type="ConvexPolygonShape3D" id="ConvexPolygonShape3D_nose"]',
    f"points = PackedVector3Array(-81, {g(GEAR)}, -15, -81, {g(GEAR)}, 15, -81, {g(UP)}, -15, -81, {g(UP)}, 15, -91, {g(GEAR)}, 0, -91, {g(UP)}, 0)",
    "",
]

shapes = {}


def shape(size):
    """Id of a BoxShape3D sub-resource of `size` (added to `subs` at the end)."""
    key = "BoxShape3D_n_" + sid(size)
    shapes[key] = size
    return key


# --- nodes ---
nodes = ['[node name="Hull" type="StaticBody3D"]', ""]
for parent, name in [(".", "LowerCut"), (".", "Upper"), ("Upper", "Cut")]:
    nodes += [f'[node name="{name}" type="Node3D" parent="{parent}"]', ""]
nodes += box_kit.nodes()

# The nose's and the legs' shapes (the model is ShipExterior's): the nose keeps players and aliens
# out from under it, each leg's pad blocks them where it stands.
nodes += [
    '[node name="NoseShape" type="CollisionShape3D" parent="."]',
    'shape = SubResource("ConvexPolygonShape3D_nose")',
    "",
]
for i, x in enumerate(LEG_X):
    for j, z in enumerate([-LEG_Z, LEG_Z]):
        nodes += [
            f'[node name="Leg{2 * i + j + 1}Shape" type="CollisionShape3D" parent="."]',
            f"transform = {xform((x, GEAR / 2, z))}",
            f'shape = SubResource("{shape((LEG_PAD[0], GEAR, LEG_PAD[1]))}")',
            "",
        ]

for key, size in sorted(shapes.items()):
    subs += [f'[sub_resource type="BoxShape3D" id="{key}"]', f"size = {vec(size)}", ""]

# --- write ---
out = write(OUT, ROOT, [], subs, nodes, "hull_build.py")
if out:
    print(len(box_kit.walls), "wall pieces,", len(box_kit.glass), "windows,", out.count("[node "), "nodes")
