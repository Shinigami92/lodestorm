"""Builds Waypost Ostra's greybox map, game/space_station/ostra/ostra.tscn (a SpaceStation, see
game/space_station/space_station.gd): one deck around the central hall, with its walls, doors,
windows, roofs, floors, lights, room names and floor guides, the docking clamps and a few shapes
outside (the real station comes with the art pass). Run it after changing the layout, from the repo
root:

    python game/space_station/ostra/ostra_build.py           # writes it
    python game/space_station/ostra/ostra_build.py --check   # fails if it differs (tools/lint.sh python, CI)

Station-local axes are the ship's (the map stands where the ship stands, docked): +x = screen right,
+z = towards the camera, y 0 is the deck (where the ramp reaches down). The ship's tail reaches
through the open pressure frame in the hangar's left wall (x 8) up to its ramp door (x 15); the
clamps take hold of the hull there. Top view, camera at the bottom:

    +---------+-----------+-----------+----------+
    |         |  DEPOT    |  COUNCIL  |          |
    |         +-----=-----+-----=-----+          |
    = HANGAR  =     CONCOURSE (hall)  = GALLERY  |
    |         +-----=-----+           |          |
    |         |   BAR     |  (hall)   |          |
    +---------+-----------+-----------+----------+

Groups (see SpaceStation): "station" always shows (the deck, the back walls with their windows,
the pressure frame); "cut" (the roofs, every other wall: the rooms are wide, so each stands between
the camera and a room; the shapes on the roofs) only casts shadows while the viewer is inside or
aboard the docked ship, the walls leaving a stub (STUB m high).
"""

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3] / "tools"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "ship"))

from hull_layout import LOWER_SIDE, TAIL_HALF_WIDTH, TAIL_TOP

from greybox import Greybox, g, sid, vec, windows_for, write, xform

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "game" / "space_station" / "ostra" / "ostra.tscn"
SCRIPT = "res://game/space_station/space_station.gd"
GUIDE_SCRIPT = "res://game/ship/floor_guide.gd"
GUIDE_MATERIAL = "res://game/ship/materials/guide.tres"
PROP_MATERIAL = "res://game/ship/materials/prop.tres"

STUB = 1.0
# Wall centers: the outer walls along z, the hangar's left wall (the pressure frame), the hall's
# walls and the far end.
ZO = 28.0
X_FRAME, X_HALL, X_MID, X_GALLERY, X_END = 8.0, 56.0, 91.0, 126.0, 170.0
Z_HALL = 12.0  # the hall's back (-) and front (+) walls
# Heights of the sections' ceilings.
H_HANGAR, H_HALL, H_ROOM = 20.0, 10.0, 6.0
# The pressure frame's opening: the ship's tail fills it, its nacelles too (game/ship/hull_layout.py).
MOUTH_HALF, MOUTH_TOP = TAIL_HALF_WIDTH + 0.2, TAIL_TOP + 0.8
assert MOUTH_HALF < ZO - 0.25 and MOUTH_TOP + 1.5 <= H_HANGAR, "the ship's tail doesn't fit the hangar"
# Where the clamps' pads hold the hull: against its lower sides, under the nacelles.
CLAMP_Z = LOWER_SIDE + 0.3
CARGO_DOOR = 8.0  # the wide doors between the hangar, the hall and the gallery

CUT = ("cut", "station")
GROUPS = {"station": "Walls", "cut": "Walls/Cut"}
WALL_MATERIAL = ["albedo_color = Color(0.33, 0.31, 0.29, 1)", "metallic = 0.2", "roughness = 0.65"]
kit = Greybox(GROUPS, "wall", WALL_MATERIAL, stub=STUB, door=3.0, sill=1.0, window_height=2.0)
wall, box, outer_wall = kit.wall, kit.box, kit.outer_wall

# --- rooms: node name, sign, floor areas ((x0, x1), (z0, z1)) between wall centers, ceiling, tint ---
DEPOT_X, COUNCIL_X, BAR_X = (X_HALL, X_MID), (X_MID, X_GALLERY), (X_HALL, X_MID)
BACK, HALL, FRONT, FULL = (-ZO, -Z_HALL), (-Z_HALL, Z_HALL), (Z_HALL, ZO), (-ZO, ZO)
ROOMS = [
    ("Hangar", "Hangar", [((X_FRAME, X_HALL), FULL)], H_HANGAR, (0.36, 0.36, 0.37)),
    ("Concourse", "Concourse", [((X_HALL, X_GALLERY), HALL), ((X_MID, X_GALLERY), FRONT)], H_HALL, (0.42, 0.39, 0.35)),
    ("Depot", "Supply depot", [(DEPOT_X, BACK)], H_ROOM, (0.38, 0.37, 0.32)),
    ("Council", "Council office", [(COUNCIL_X, BACK)], H_ROOM, (0.33, 0.33, 0.38)),
    ("Bar", "Bar", [(BAR_X, FRONT)], H_ROOM, (0.4, 0.33, 0.28)),
    ("Gallery", "Observation gallery", [((X_GALLERY, X_END), FULL)], H_HALL, (0.35, 0.38, 0.42)),
]

# --- the deck: one slab under everything ---
box("Deck", (X_END - X_FRAME + 0.5, 1, 2 * ZO + 0.5), ((X_FRAME + X_END) / 2, -0.5, 0))

# --- the hangar's left wall: the pressure frame the ship's tail reaches through ---
# Seen from the camera, it runs up the screen over the ship's tail: cut away like the walls.
wall("FrameWall", "z", X_FRAME, -ZO, ZO, 0, H_HANGAR, [(0, 2 * MOUTH_HALF)], *CUT, door_height=MOUTH_TOP)
# The frame's jambs and header, standing out of the wall around the hull.
box("FrameJambBack", (1.5, MOUTH_TOP, 1.5), (X_FRAME + 0.5, MOUTH_TOP / 2, -MOUTH_HALF - 0.75), "cut")
box("FrameJambFront", (1.5, MOUTH_TOP, 1.5), (X_FRAME + 0.5, MOUTH_TOP / 2, MOUTH_HALF + 0.75), "cut")
box("FrameHeader", (1.5, 1.5, 2 * MOUTH_HALF + 3), (X_FRAME + 0.5, MOUTH_TOP + 0.75, 0), "cut")
# Clamp mounts beside the hull, under the nacelles (the clamps themselves move and always show,
# see CLAMPS); low enough to keep the hull in view.
for side, name in [(-1, "Back"), (1, "Front")]:
    box(f"ClampMount{name}", (5.0, 6.0, 1.5), (11.5, 3.0, side * (CLAMP_Z + 6.3)), "cut")

# --- walls between the sections: the rooms are wide, so every inner wall stands between the camera
# and a room beside it (on its -x or -z side) and is cut away down to its stub ---
wall("HangarWall", "z", X_HALL, -ZO, ZO, 0, H_HANGAR, [(-20, 4), (0, CARGO_DOOR)], *CUT)
wall("GalleryWall", "z", X_GALLERY, -ZO, ZO, 0, H_HALL, [(0, CARGO_DOOR)], *CUT)
# The hall's back wall (the depot and the council behind it) and front wall (the bar in front).
room_doors = [((X_HALL + X_MID) / 2, 3), ((X_MID + X_GALLERY) / 2, 3)]
wall("HallBack", "x", -Z_HALL, X_HALL + 0.25, X_GALLERY - 0.25, 0, H_HALL, room_doors, *CUT)
wall("HallFront", "x", Z_HALL, X_HALL + 0.25, X_MID, 0, H_HALL, room_doors[:1], *CUT)
wall("DepotCouncilWall", "z", X_MID, -ZO + 0.25, -Z_HALL - 0.25, 0, H_ROOM, (), *CUT)
wall("BarWall", "z", X_MID, Z_HALL + 0.25, ZO - 0.25, 0, H_HALL, (), *CUT)

# --- outer walls with windows ---
sections = [
    ("Hangar", X_FRAME, X_HALL, H_HANGAR),
    ("Rooms", X_HALL, X_GALLERY, H_ROOM),
    ("Gallery", X_GALLERY, X_END, H_HALL),
]
# The hangar's windows sit high, the council's is one big pane, the gallery's are tall panes side
# by side onto the planet.
hangar_windows = windows_for(X_FRAME + 4, X_HALL - 4, spacing=10)
rooms_back = windows_for(*DEPOT_X) + [((COUNCIL_X[0] + COUNCIL_X[1]) / 2, 12.0)]
gallery_panes = windows_for(X_GALLERY + 1, X_END - 1, spacing=5.4, width=4.4, margin=0.7)
outer_wall("BackWallHangar", "x", -ZO, X_FRAME, X_HALL, 0, H_HANGAR, hangar_windows, sill=6, height=4)
outer_wall("BackWallRooms", "x", -ZO, X_HALL, X_GALLERY, 0, H_ROOM, rooms_back, height=3)
outer_wall("BackWallGallery", "x", -ZO, X_GALLERY, X_END, 0, H_HALL, gallery_panes, sill=0.6, height=8)
front = [
    ("FrontWallHangar", X_FRAME, X_HALL, H_HANGAR, windows_for(X_FRAME + 4, X_HALL - 4, spacing=10), 6, 4),
    ("FrontWallBar", X_HALL, X_MID, H_ROOM, windows_for(*BAR_X), 1, 2),
    ("FrontWallHall", X_MID, X_GALLERY, H_HALL, windows_for(X_MID, X_GALLERY), 1, 3),
    ("FrontWallGallery", X_GALLERY, X_END, H_HALL, windows_for(X_GALLERY, X_END, spacing=6), 0.6, 6),
]
for name, x0, x1, height, wins, sill, win_h in front:
    outer_wall(name, "x", ZO, x0, x1, 0, height, wins, "cut", "station", sill=sill, height=win_h)
# The far end stands between the camera and the gallery: cut away too.
outer_wall("EndWall", "z", X_END, -ZO, ZO, 0, H_HALL, [], *CUT)

# --- roofs (cut away while the viewer is inside) ---
for name, (x0, x1), (z0, z1), height in [
    ("RoofHangar", (X_FRAME, X_HALL), FULL, H_HANGAR),
    ("RoofHall", (X_HALL, X_GALLERY), HALL, H_HALL),
    ("RoofAlcove", (X_MID, X_GALLERY), FRONT, H_HALL),
    ("RoofDepot", DEPOT_X, BACK, H_ROOM),
    ("RoofCouncil", COUNCIL_X, BACK, H_ROOM),
    ("RoofBar", BAR_X, FRONT, H_ROOM),
    ("RoofGallery", (X_GALLERY, X_END), FULL, H_HALL),
]:
    box(name, (x1 - x0 + 0.5, 0.5, z1 - z0 + 0.5), ((x0 + x1) / 2, height + 0.25, (z0 + z1) / 2), "cut")

# --- props: crate stacks along the hangar's walls and shelving in the depot (greybox) ---
CRATES = [
    (14, -25),
    (18, -25.5),
    (30, -25),
    (42, -24.5),
    (50, -25),
    (16, 24.5),
    (34, 25),
    (38, 24.5),
    (52, 25),
]
for i, (x, z) in enumerate(CRATES):
    high = 2.4 if i % 3 == 0 else 1.2
    box(f"Crate{i + 1}", (2.4, high, 2.4), (x, high / 2, z))
for i, x in enumerate([62.0, 70.0, 78.0, 86.0]):
    box(f"Shelf{i + 1}", (5, 3.5, 1.2), (x, 1.75, -26.5))
# --- furniture for the station's people (see PEOPLE): the depot's counter, the council's long
# table with its chairs, the bar's counter and booths, stalls along the concourse (scenery: no
# shops), benches in the gallery facing the windows ---
SEAT = 0.45  # the seats' height: the sitting clip's (SEAT_HEIGHT in tools/blender/humanoid.py)
box("DepotCounter", (6, 1.1, 0.9), (73.5, 0.55, -20.5))
# It ends short of the room's name on the floor.
box("CouncilTable", (2.4, 0.8, 5.5), (108.5, 0.4, -21.25))
for i, z in enumerate([-23.0, -21.25, -19.5]):
    for side, sname in [(-1, "Left"), (1, "Right")]:
        box(f"CouncilChair{sname}{i + 1}", (0.6, 0.9, 0.6), (108.5 + side * 1.7, 0.45, z))
# The bar's counter along its left wall, the booths along its right one.
box("BarCounter", (0.9, 1.1, 9), (59, 0.55, 20))
# Behind the bartender's right shoulder: a low back bar with bottles, where she shelves one now and then
# (assets/npcs/nell/source/nell_clips.py: SHELF).
box("BackBar", (0.3, 1.38, 1.3), (57.85, 0.69, 20.75))
for i, z in enumerate([20.3, 20.55, 20.9, 21.2]):
    box(f"BackBarBottle{i + 1}", (0.07, 0.25, 0.07), (57.85, 1.505, z))
# A booth: a table between two benches (seats SEAT high, a backrest along the outer edge), room for
# sitting knees between the table and the seats.
for i, z in enumerate([16.5, 23.0]):
    box(f"BoothTable{i + 1}", (1.6, 0.75, 1.0), (88.5, 0.375, z))
    for side, sname in [(-1, "Back"), (1, "Front")]:
        box(f"BoothBench{i + 1}{sname}", (1.8, SEAT, 0.8), (88.5, SEAT / 2, z + side * 1.3))
        box(f"BoothBackrest{i + 1}{sname}", (1.8, 1.1, 0.15), (88.5, 0.55, z + side * 1.775))
# A stall: its counter towards the hall, a rack behind the one standing at it.
for i, x in enumerate([100.0, 110.0, 120.0]):
    box(f"Stall{i + 1}", (3, 1.0, 1.2), (x, 0.5, 18))
    box(f"StallRack{i + 1}", (3, 2.2, 0.4), (x, 1.1, 15.2))
for i, x in enumerate([140.0, 156.0]):
    box(f"Bench{i + 1}", (5, SEAT, 0.8), (x, SEAT / 2, -20))

# --- outside: solar wings behind the station, a mast on the council's roof ---
for i, x in enumerate([32.0, 148.0]):
    box(f"WingStrut{i + 1}", (1, 1, 8), (x, 9, -ZO - 4), kind="mesh")
    box(f"Wing{i + 1}", (34, 0.3, 12), (x, 9, -ZO - 14), kind="mesh")
box("Mast", (0.8, 16, 0.8), (118, H_ROOM + 8, -24), "cut", kind="mesh")


# --- the rooms' nodes: floors, lights, signs, floor guides ---
def flat(origin):
    """A label or plane lying on the floor, readable from the camera."""
    return xform(origin, "1, 0, 0, 0, 0, 1, 0, -1, 0")


SPOT_DOWN = "1, 0, 0, 0, 0, 1, 0, -1, 0"
# Where each room's name is painted on its floor (by its door), and its size.
SIGNS = {
    "Hangar": ((48, 6), 128),
    "Concourse": ((63, 5), 128),
    "Depot": ((73.5, -16.5), 96),
    "Council": ((108.5, -16.5), 96),
    "Bar": ((73.5, 16.5), 96),
    "Gallery": ((132, 6), 128),
}
# Arrow directions on the floor (the arrow's basis: its head points along it).
ARROWS = {
    (1, 0): "0, 0, -1, 0, 1, 0, 1, 0, 0",
    (-1, 0): "0, 0, 1, 0, 1, 0, -1, 0, 0",
    (0, -1): "1, 0, 0, 0, 1, 0, 0, 0, 1",
    (0, 1): "-1, 0, 0, 0, 1, 0, 0, 0, -1",
}
# Floor guides: node name, where (x, z), the arrow's direction, the text (the rooms further on).
GUIDES = [
    ("Hangar", "ToConcourse", (30, 1.5), (1, 0), "Concourse · Bar · Gallery\nDepot · Council"),
    ("Hangar", "ToDepot", (46, -17.5), (1, 0), "Supply depot"),
    ("Concourse", "ToDepot", (73.5, -7), (0, -1), "Supply depot"),
    ("Concourse", "ToCouncil", (108.5, -7), (0, -1), "Council office"),
    ("Concourse", "ToBar", (73.5, 7), (0, 1), "Bar"),
    ("Concourse", "ToGallery", (114, 1.5), (1, 0), "Observation gallery"),
    ("Concourse", "ToHangar", (66, -2.5), (-1, 0), "Hangar · Ship"),
    ("Gallery", "ToHangar", (134, -2.5), (-1, 0), "Concourse · Hangar"),
]
LIGHT_SPACING = 16.0

subs = kit.subresources()
for name, _sign, _areas, _height, tint in ROOMS:
    subs += [f'[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_floor_{name}"]']
    subs += [f"albedo_color = Color({', '.join(g(c) for c in tint)}, 1)", ""]
plane_sizes = {}
for name, _sign, areas, _height, _tint in ROOMS:
    for (x0, x1), (z0, z1) in areas:
        plane_sizes[(name, x1 - x0 - 0.5, z1 - z0 - 0.5)] = True
for name, w, d in plane_sizes:
    subs += [
        f'[sub_resource type="PlaneMesh" id="PlaneMesh_floor_{name}_{sid((w, d))}"]',
        f'material = SubResource("StandardMaterial3D_floor_{name}")',
        f"size = Vector2({g(w)}, {g(d)})",
        "",
    ]
subs += [
    '[sub_resource type="PrismMesh" id="PrismMesh_arrow"]',
    'material = ExtResource("mat_guide")',
    "size = Vector3(0.9, 0.7, 0.02)",
    "",
    '[sub_resource type="BoxMesh" id="BoxMesh_arrow_shaft"]',
    'material = ExtResource("mat_guide")',
    "size = Vector3(0.3, 0.6, 0.02)",
    "",
    '[sub_resource type="BoxMesh" id="BoxMesh_clamp_pad"]',
    'material = ExtResource("mat_prop")',
    "size = Vector3(2.5, 1.6, 0.6)",
    "",
    '[sub_resource type="BoxMesh" id="BoxMesh_clamp_arm"]',
    'material = ExtResource("mat_prop")',
    "size = Vector3(1.2, 0.8, 4)",
    "",
    '[sub_resource type="SphereMesh" id="SphereMesh_dome"]',
    f'material = SubResource("StandardMaterial3D_{kit.material_id}")',
    "radius = 11.0",
    "height = 8.0",
    "is_hemisphere = true",
    "",
]
interior = [
    ("Hangar", (X_FRAME, X_HALL), FULL, H_HANGAR),
    ("Middle", (X_HALL, X_GALLERY), FULL, H_HALL),
    ("Gallery", (X_GALLERY, X_END), FULL, H_HALL),
]
for _name, (x0, x1), (z0, z1), height in interior:
    subs += [f'[sub_resource type="BoxShape3D" id="BoxShape3D_inside_{sid((x1 - x0, height, z1 - z0))}"]']
    subs += [f"size = {vec((x1 - x0, height, z1 - z0))}", ""]

nodes = ['[node name="Ostra" type="Node3D"]', 'script = ExtResource("script")', ""]
nodes += ['[node name="Walls" type="StaticBody3D" parent="."]', ""]
# The cut-away parts don't show in the navigator's hologram either: it shows the rooms from above.
nodes += ['[node name="Cut" type="Node3D" parent="Walls" groups=["hidden_in_hologram"]]', ""]
nodes += kit.nodes(body="Walls")
nodes += [
    '[node name="Dome" type="MeshInstance3D" parent="Walls/Cut"]',
    f"transform = {xform((108.5, H_HALL + 0.5, 0), '1, 0, 0, 0, 0.6, 0, 0, 0, 1')}",
    'mesh = SubResource("SphereMesh_dome")',
    "",
]

nodes += ['[node name="Rooms" type="Node3D" parent="."]', ""]
for name, sign, areas, height, _tint in ROOMS:
    nodes += [f'[node name="{name}" type="Node3D" parent="Rooms"]', ""]
    for i, ((x0, x1), (z0, z1)) in enumerate(areas):
        suffix = "" if i == 0 else str(i + 1)
        w, d = x1 - x0 - 0.5, z1 - z0 - 0.5
        nodes += [
            f'[node name="Floor{suffix}" type="MeshInstance3D" parent="Rooms/{name}"]',
            f"transform = {xform(((x0 + x1) / 2, 0.005, (z0 + z1) / 2))}",
            "cast_shadow = 0",
            f'mesh = SubResource("PlaneMesh_floor_{name}_{sid((w, d))}")',
            "",
        ]
        nx = max(1, round((x1 - x0) / LIGHT_SPACING))
        nz = max(1, round((z1 - z0) / LIGHT_SPACING))
        for ix in range(nx):
            for iz in range(nz):
                lx = x0 + (x1 - x0) * (ix + 0.5) / nx
                lz = z0 + (z1 - z0) * (iz + 0.5) / nz
                nodes += [
                    f'[node name="Light{suffix}_{ix + 1}_{iz + 1}" type="SpotLight3D" parent="Rooms/{name}"]',
                    f"transform = {xform((lx, height - 0.4, lz), SPOT_DOWN)}",
                    "light_color = Color(1, 0.86, 0.66, 1)",
                    f"light_energy = {g(4.0 + height * 0.2)}",
                    f"spot_range = {g(height + 1.0)}",
                    "spot_angle = 62.0",
                    "spot_angle_attenuation = 0.5",
                    "",
                ]
    (sx, sz), size = SIGNS[name]
    nodes += [
        f'[node name="Sign" type="Label3D" parent="Rooms/{name}"]',
        "layers = 4",
        f"transform = {flat((sx, 0.02, sz))}",
        "pixel_size = 0.01",
        f'text = "{sign}"',
        f"font_size = {size}",
        f"outline_size = {size // 4}",
        "uppercase = true",
        "",
    ]
    guides = [gd for gd in GUIDES if gd[0] == name]
    if guides:
        nodes += [f'[node name="Guides" type="Node3D" parent="Rooms/{name}"]', ""]
    for _room, gname, (gx, gz), direction, text in guides:
        path = f"Rooms/{name}/Guides/{gname}"
        text = text.replace("\n", "\\n")
        nodes += [
            f'[node name="{gname}" type="Node3D" parent="Rooms/{name}/Guides"]',
            f"transform = {xform((gx, 0, gz))}",
            'script = ExtResource("guide_script")',
            "",
            f'[node name="Arrow" type="Node3D" parent="{path}"]',
            f"transform = {xform((direction[0] * 1.5, 0.02, direction[1] * 1.5), ARROWS[direction])}",
            "",
            f'[node name="Head" type="MeshInstance3D" parent="{path}/Arrow"]',
            f"transform = {flat((0, 0, -0.15))}",
            "cast_shadow = 0",
            'mesh = SubResource("PrismMesh_arrow")',
            "",
            f'[node name="Shaft" type="MeshInstance3D" parent="{path}/Arrow"]',
            f"transform = {flat((0, 0, 0.4))}",
            "cast_shadow = 0",
            'mesh = SubResource("BoxMesh_arrow_shaft")',
            "",
            f'[node name="Text" type="Label3D" parent="{path}"]',
            f"transform = {flat((0, 0.02, 0))}",
            "pixel_size = 0.01",
            "modulate = Color(1, 0.8, 0.45, 1)",
            f'text = "{text}"',
            "font_size = 48",
            "outline_size = 14",
            "uppercase = true",
            "",
        ]

# --- the clamps: closed, their pads lie against the hull's sides; SpaceStation opens them ---
nodes += ['[node name="Clamps" type="Node3D" parent="."]', ""]
# On the hull's lower sides under the nacelles: behind it two above each other, in front low along
# its lower edge, under the cut-away decks, so they don't cover the cargo bay while they take hold.
CLAMPS = [(11.5, 2.4, -1), (11.5, 4.8, -1), (9.75, 2.4, 1), (13.25, 2.4, 1)]
for i, (x, y, side) in enumerate(CLAMPS):
    nodes += [
        f'[node name="Clamp{i + 1}" type="Node3D" parent="Clamps"]',
        f"transform = {xform((x, y, side * CLAMP_Z))}",
        "",
        f'[node name="Pad" type="MeshInstance3D" parent="Clamps/Clamp{i + 1}"]',
        'mesh = SubResource("BoxMesh_clamp_pad")',
        "",
        f'[node name="Arm" type="MeshInstance3D" parent="Clamps/Clamp{i + 1}"]',
        f"transform = {xform((0, 0, side * 2.3))}",
        'mesh = SubResource("BoxMesh_clamp_arm")',
        "",
    ]


# --- the station's people: the named NPCs at their places (profile, where (x, z), facing yaw in
# degrees: 0 towards the camera, 90 towards +x), then the ambient colonists, each with a profile of
# their own (profile, tint, where, yaw, route: the waypoints they walk in a loop, a waypoint with a
# yaw (x, z, yaw) the seat where they sit down for a while; none: they stand, or sit for good when
# in SEATED). A seat's spot is where the feet are: the hips sit 0.4 m behind it (SIT_BACK in
# tools/blender/humanoid.py), 0.25 m in from the seat's front edge ---
NPC_SCENE = "res://game/npcs/npc.tscn"
COLONIST_SCENE = "res://game/npcs/colonist.tscn"
EXCHANGE_SCENE = "res://game/stations/exchange/ore_exchange.tscn"
PROFILES = "res://game/npcs/ostra/"
PEOPLE = [
    # Beside the depot's counter (the exchange's hoppers on it).
    ("Kade", "depot_master", (77.6, -21.6), 0),
    # At the head of the long table, the big window behind.
    ("Selin", "councillor", (108.5, -25.3), 0),
    # Behind the bar's counter, close to it (her work reaches across it): used across it (see USE_ACROSS).
    ("Nell", "bartender", (58.27, 20), 90),
    # At the booth by the bar's door.
    ("Rook", "rival_captain", (86.2, 23), -90),
]
# Used across their counter: the use point's offset towards the players (along the facing), the
# footprint around it (across, along the facing: from them to the counter's front) and the range
# from there (short, so the camera framing both stays close).
USE_ACROSS = {"Nell": (0.43, (9, 1.5), 1.0)}
COLONISTS = [
    ("Mechanic", "mechanic", (0.95, 0.9, 0.8), (100, 16.4), 0, []),
    ("BarterTrader", "barter_trader", (0.8, 0.85, 0.95), (120, 16.4), 0, []),
    ("Gardener", "gardener", (0.9, 1, 0.85), (110, 19.4), 180, []),
    ("DockHand", "dock_hand", (0.9, 0.95, 1), (60.4, 24), -90, []),
    # On the first gallery bench, looking out of the windows.
    ("HaulerPilot", "hauler_pilot", (0.85, 0.9, 1), (141, -20.55), 180, []),
    # Facing each other in the booth by the counter (the other one is Rook's).
    ("WaterTechnician", "water_technician", (0.85, 0.95, 0.95), (88.3, 15.75), 0, []),
    ("Metalworker", "metalworker", (1, 0.9, 0.8), (88.7, 17.25), 180, []),
    ("DepotClerk", "depot_clerk", (1, 1, 1), (86, -24.9), 180, []),
    ("Loader", "loader", (1, 0.95, 0.85), (28, -21), 90, [(48, -21), (28, -21)]),
    ("Courier", "courier", (0.95, 1, 0.95), (36, 2), 90, [(140, 2), (36, 2)]),
    ("MaintenanceTech", "maintenance_tech", (0.9, 0.9, 1), (80, -8), 90, [(112, -8), (80, -8)]),
    # Around the gallery, sitting down on the second bench for a while (round its end, on the window side).
    (
        "Teacher",
        "teacher",
        (1, 0.9, 0.95),
        (134, -14),
        90,
        [(151, -22), (156.5, -20.55, 180), (160, -22), (164, -14), (164, 14), (134, 14), (134, -14)],
    ),
]
SEATED = {"HaulerPilot", "WaterTechnician", "Metalworker"}


def yaw(degrees):
    """A turn about the vertical axis (rows, as scenes store them): 0 faces +z."""
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return ", ".join(g(round(v, 6) + 0.0) for v in (c, 0, s, 0, 1, 0, -s, 0, c))


nodes += ['[node name="People" type="Node3D" parent="."]', ""]
for name, profile, (px, pz), facing in PEOPLE:
    nodes += [
        f'[node name="{name}" parent="People" instance=ExtResource("npc")]',
        f"transform = {xform((px, 0, pz), yaw(facing))}",
        f'profile = ExtResource("profile_{profile}")',
        "",
    ]
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

# --- the ore exchange: its hoppers on the depot's counter (its origin: the counter's middle on the
# deck, see ExchangeStation) ---
nodes += [
    '[node name="OreExchange" parent="." instance=ExtResource("exchange")]',
    f"transform = {xform((73.5, 0, -20.5))}",
    "",
]

# --- who's inside: the cut-away and the indoor light follow it ---
nodes += ['[node name="Interior" type="Area3D" parent="."]', "monitorable = false", ""]
for name, (x0, x1), (z0, z1), height in interior:
    nodes += [
        f'[node name="{name}" type="CollisionShape3D" parent="Interior"]',
        f"transform = {xform(((x0 + x1) / 2, height / 2, (z0 + z1) / 2))}",
        f'shape = SubResource("BoxShape3D_inside_{sid((x1 - x0, height, z1 - z0))}")',
        "",
    ]

# --- the rooms' areas, for what people say where they stand (RoomPlan) ---
plan_names, plan_areas = [], []
for name, _sign, areas, height, _tint in ROOMS:
    for (x0, x1), (z0, z1) in areas:
        plan_names.append(f'&"{name}"')
        plan_areas.append(f"AABB({g(x0)}, 0, {g(z0)}, {g(x1 - x0)}, {g(height)}, {g(z1 - z0)})")
nodes += [
    '[node name="RoomPlan" type="Node3D" parent="."]',
    'script = ExtResource("room_plan")',
    f"rooms = Array[StringName]([{', '.join(plan_names)}])",
    f"areas = Array[AABB]([{', '.join(plan_areas)}])",
    "",
]

ext = [
    ("Script", SCRIPT, "script"),
    ("Script", "res://game/world/room_plan.gd", "room_plan"),
    ("Script", GUIDE_SCRIPT, "guide_script"),
    ("StandardMaterial3D", GUIDE_MATERIAL, "mat_guide"),
    ("StandardMaterial3D", PROP_MATERIAL, "mat_prop"),
    ("PackedScene", NPC_SCENE, "npc"),
    ("PackedScene", COLONIST_SCENE, "colonist"),
    ("PackedScene", EXCHANGE_SCENE, "exchange"),
]
for profile in sorted({p[1] for p in PEOPLE}):
    ext.append(("Resource", f"{PROFILES}{profile}.tres", f"profile_{profile}"))
for profile in sorted({c[1] for c in COLONISTS}):
    ext.append(("Resource", f"{PROFILES}colonists/{profile}.tres", f"colonist_{profile}"))
out = write(OUT, ROOT, ext, subs, nodes, "ostra_build.py")
if out:
    print(len(kit.walls), "wall pieces,", len(kit.glass), "windows,", out.count("[node "), "nodes")
