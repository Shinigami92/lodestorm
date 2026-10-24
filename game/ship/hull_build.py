"""Builds the ship's greybox hull, game/ship/hull.tscn: floors, walls with doors and windows, the
upper deck's slab, the roof, the nose cone, the landing gear and the thrusters (the real hull comes
with the art pass). Run it after changing the layout, from the repo root:

    python game/ship/hull_build.py           # writes it
    python game/ship/hull_build.py --check   # fails if it differs (tools/lint.sh python, CI)

Only hull.tscn is written; the rooms are scenes of their own (game/ship/rooms/), placed in
ship.tscn. They must match the layout here (ROOMS: position and size), so moving a room means
changing it here, rebuilding, and moving the room's scene and resizing its floor by hand.

Ship-local: +x = screen right (tail, ramp), -x = nose; +z = towards the camera; y 0 is the ground.
Inner space x -80.5..14.5, z -14.5..14.5. Lower deck floor LOW, ceiling SLAB; upper deck floor UP,
ceiling TOP; roof above. Corridors along z = 0 (inner z -2.5..2.5). Sections along x: nose rooms
-80.5..-58 | lift lobby -57.5..-52 | rooms -51.5..-3.5 | cargo bay -3..14.5 (double height). Lifts:
by the lobby and in the cargo bay's back corner.

Groups (see Ship): "hull" always shows; "lower_cut" only casts shadows while the viewer is on the
lower deck; "upper" only casts shadows while the viewer is on the lower deck; "upper_cut" (inside
upper) only casts shadows while the viewer is aboard. A wall in front of what the camera must see
is cut away, leaving a stub (STUB m high) in the always-visible group. The walls, windows and the
writing are the shared greybox helpers' (tools/greybox.py).
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "tools"))

from greybox import Greybox, g, scaled, sid, vec, windows_for, write, xform

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "ship" / "hull.tscn"
PROP_MATERIAL = "res://game/ship/materials/prop.tres"

# The hull stands on landing gear, GEAR m above the ground.
GEAR = 1.5
LOW, SLAB, UP, TOP = GEAR + 1.0, GEAR + 5.0, GEAR + 5.5, GEAR + 9.5
STUB = 1.0
ZI = 14.5  # inner half depth
CW = 2.75  # corridor wall center (inner corridor half width 2.5)

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
box("RightWallBack", (0.5, 8.5, 12.5), (14.75, (LOW + TOP) / 2, -8.25))
box("RightWallFront", (0.5, 8.5, 12.5), (14.75, (LOW + TOP) / 2, 8.25), "lower_cut")
box("DoorLintel", (0.5, 5, 4), (14.75, TOP - 2.5, 0), "lower_cut")
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
RANGE_X = (-51.5, -22)
ARMORY_X = (-21.5, -3.5)
RANGE_DOOR = -49.5
VENDOR_W = (48 - 1.5) / 4
VENDORS = [
    (n, -51.5 + i * (VENDOR_W + 0.5), -51.5 + i * (VENDOR_W + 0.5) + VENDOR_W)
    for i, n in enumerate(["Weapons", "Armor", "Skills", "Miners"])
]
range_doors = [(RANGE_DOOR, 2), ((ARMORY_X[0] + ARMORY_X[1]) / 2, 3)]
vendor_doors = [((a + b) / 2, 3) for _, a, b in VENDORS]
wall("LowerCorridorBack", "x", -CW, -51.5, -3.5, LOW, SLAB, range_doors, "lower_cut", "hull")
wall("LowerCorridorFront", "x", CW, -51.5, -3.5, LOW, SLAB, vendor_doors, "lower_cut", "hull")
wall("ArmoryWall", "z", -21.75, -ZI, -3, LOW, SLAB)
for i, (_, _, b) in enumerate(VENDORS[:-1]):
    wall(f"VendorWall{i + 1}", "z", b + 0.25, 3, ZI, LOW, SLAB, front=LOWER_FRONT)

# --- upper deck ---
wall("CockpitWall", "z", -72.25, -ZI, ZI, UP, TOP, doors=[(0, 3)], group="upper", front=UPPER_FRONT)
CABIN_X = [(-51.5, -46), (-45.5, -40)]
CREW_X = [(-39.5 + i * 5, -35 + i * 5) for i in range(4)]
MESS_X = (-19.5, -3.5)
blocks = CABIN_X + CREW_X
for i, (_, b) in enumerate(blocks):
    name = "MessWall" if i == len(blocks) - 1 else f"CabinWall{i + 1}"
    wall(name + "Back", "z", b + 0.25, -ZI, -3, UP, TOP, group="upper")
    wall(name + "Front", "z", b + 0.25, 3, ZI, UP, TOP, group="upper", front=UPPER_FRONT)
cabin_doors = [((a + b) / 2, 1.5) for a, b in blocks]
wall("UpperCorridorBack", "x", -CW, -51.5, -19.5, UP, TOP, cabin_doors, "upper_cut", "upper")
wall("UpperCorridorFront", "x", CW, -51.5, -19.5, UP, TOP, cabin_doors, "upper_cut", "upper")

# --- rooms: name, deck (Lower/Upper/None = double height), x, z ---
# Each is a scene in game/ship/rooms/ at its floor center; here they only place the windows.
BACK, FRONT, FULL, CORR = (-ZI, -3), (3, ZI), (-ZI, ZI), (-2.5, 2.5)
ROOMS = [
    ("Cockpit", "Upper", (-80.5, -72.5), FULL),
    ("Bridge", "Upper", (-72, -58), FULL),
    ("UpperLobby", "Upper", (-57.5, -52), (-2.5, ZI)),
    ("UpperCorridor", "Upper", (-51.5, -19.5), CORR),
    ("MessHall", "Upper", MESS_X, FULL),
]
for i, x in enumerate(CABIN_X):
    ROOMS += [(f"Cabin{2 * i + 1}", "Upper", x, BACK), (f"Cabin{2 * i + 2}", "Upper", x, FRONT)]
for i, x in enumerate(CREW_X):
    ROOMS += [(f"Crew{i + 1}", "Upper", x, BACK), (f"Crew{i + 5}", "Upper", x, FRONT)]
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


# --- outer walls with windows ---
def outer_windows(deck, side):
    """Windows of the rooms on `deck` (rooms of both decks count for both) along the back (-1) or
    front (+1) wall."""
    wins = []
    for _name, d, (x0, x1), (z0, z1) in ROOMS:
        if d not in (deck, None):
            continue
        if (side < 0 and z0 == -ZI) or (side > 0 and z1 == ZI):
            wins += windows_for(x0, x1)
    return wins


outer_wall("BackWallLower", "x", -14.75, -81, 15, LOW, UP, outer_windows("Lower", -1))
outer_wall("BackWallUpper", "x", -14.75, -81, 15, UP, TOP, outer_windows("Upper", -1))
outer_wall("FrontWallLower", "x", 14.75, -81, 15, LOW, UP, outer_windows("Lower", 1), "lower_cut", "hull")
outer_wall("FrontWallUpper", "x", 14.75, -81, 15, UP, TOP, outer_windows("Upper", 1), "upper_cut", "upper")
# The nose cone sits in front of the lower deck; the cockpit looks out over it.
outer_wall("NoseWallLower", "z", -80.75, -ZI, ZI, LOW, UP, [])
outer_wall("NoseWallUpper", "z", -80.75, -ZI, ZI, UP, TOP, [(-4.5, 7), (4.5, 7)])


# --- sub-resources ---
def material(mid, color, emission=None):
    lines = [f'[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_{mid}"]', f"albedo_color = {color}"]
    if emission:
        lines += ["emission_enabled = true", f"emission = {color}", f"emission_energy_multiplier = {g(emission)}"]
    return lines + [""]


def cylinder(mid, material_id, top, bottom, height, segments):
    return [
        f'[sub_resource type="CylinderMesh" id="CylinderMesh_{mid}"]',
        f'material = SubResource("StandardMaterial3D_{material_id}")',
        f"top_radius = {g(top)}",
        f"bottom_radius = {g(bottom)}",
        f"height = {height}",
        f"radial_segments = {segments}",
        "rings = 1",
        "",
    ]


subs = box_kit.subresources()
subs += material("thruster", "Color(0.32, 0.34, 0.38, 1)")
subs += material("exhaust", "Color(0.4, 0.75, 1, 1)", 2.0)
subs += ['[sub_resource type="BoxMesh" id="BoxMesh_prop"]', 'material = ExtResource("mat_prop")', ""]
subs += [
    '[sub_resource type="PrismMesh" id="PrismMesh_nose"]',
    'material = SubResource("StandardMaterial3D_hull")',
    f"size = Vector3(30, 10, {g(UP - GEAR)})",
    "",
    '[sub_resource type="ConvexPolygonShape3D" id="ConvexPolygonShape3D_nose"]',
    f"points = PackedVector3Array(-81, {g(GEAR)}, -15, -81, {g(GEAR)}, 15, -81, {g(UP)}, -15, -81, {g(UP)}, 15, -91, {g(GEAR)}, 0, -91, {g(UP)}, 0)",
    "",
]
subs += cylinder("thruster", "thruster", 1.4, 1.7, "7.0", 24)
subs += cylinder("exhaust", "exhaust", 1.2, 1.2, "0.05", 24)
subs += cylinder("leg", "thruster", 0.35, 0.35, "1.0", 12)
subs += cylinder("leg_housing", "thruster", 0.7, 0.55, "0.7", 16)
subs += cylinder("foot", "thruster", 0.8, 1.1, "0.25", 16)

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

# Exterior: a nose cone and two thrusters on the roof at the tail.
nodes += [
    '[node name="NoseShape" type="CollisionShape3D" parent="."]',
    'shape = SubResource("ConvexPolygonShape3D_nose")',
]
nodes += ["", '[node name="Nose" type="MeshInstance3D" parent="."]']
nodes += ["transform = {}".format(xform((-86, (GEAR + UP) / 2, 0), "0, -1, 0, 0, 0, 1, -1, 0, 0"))]
nodes += ['mesh = SubResource("PrismMesh_nose")', ""]
ALONG_X = "0, -1, 0, 1, 0, 0, 0, 0, 1"  # cylinder axis along x
# Landing gear: three pairs of legs on brackets along the hull's sides (under it, the camera
# wouldn't see them), each a strut with a housing and a foot.
for i, x in enumerate([-70, -33, 4]):
    for j, z in enumerate([-15.9, 15.9]):
        leg = f"Leg{2 * i + j + 1}"
        side = -1 if z < 0 else 1
        nodes += [
            f'[node name="{leg}Shape" type="CollisionShape3D" parent="."]',
            f"transform = {xform((x, GEAR / 2, z))}",
            f'shape = SubResource("{shape((1.4, GEAR, 1.4))}")',
            "",
            f'[node name="{leg}" type="Node3D" parent="."]',
            f"transform = {xform((x, 0, z))}",
            "",
        ]
        for part, transform, mesh in [
            ("Bracket", scaled((0.7, 0.6, 1.2), (0, GEAR + 0.3, -side * 0.6)), "BoxMesh_prop"),
            ("Strut", scaled((1, GEAR, 1), (0, GEAR / 2, 0)), "CylinderMesh_leg"),
            ("Housing", xform((0, GEAR - 0.3, 0)), "CylinderMesh_leg_housing"),
            ("Foot", xform((0, 0.125, 0)), "CylinderMesh_foot"),
        ]:
            nodes += [
                f'[node name="{part}" type="MeshInstance3D" parent="{leg}"]',
                f"transform = {transform}",
                f'mesh = SubResource("{mesh}")',
                "",
            ]
for i, z in enumerate([-7, 7]):
    nodes += [
        f'[node name="Thruster{i + 1}" type="MeshInstance3D" parent="Upper/Cut"]',
        f"transform = {xform((13.5, TOP + 2.2, z), ALONG_X)}",
        'mesh = SubResource("CylinderMesh_thruster")',
        "",
        f'[node name="Exhaust{i + 1}" type="MeshInstance3D" parent="Upper/Cut"]',
        f"transform = {xform((17.03, TOP + 2.2, z), ALONG_X)}",
        "cast_shadow = 0",
        'mesh = SubResource("CylinderMesh_exhaust")',
        "",
    ]

for key, size in sorted(shapes.items()):
    subs += [f'[sub_resource type="BoxShape3D" id="{key}"]', f"size = {vec(size)}", ""]

# --- write ---
out = write(OUT, ROOT, [("StandardMaterial3D", PROP_MATERIAL, "mat_prop")], subs, nodes, "hull_build.py")
if out:
    print(len(box_kit.walls), "wall pieces,", len(box_kit.glass), "windows,", out.count("[node "), "nodes")
