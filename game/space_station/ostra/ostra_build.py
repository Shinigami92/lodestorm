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

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3] / "tools"))

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
H_HANGAR, H_HALL, H_ROOM = 18.0, 10.0, 6.0
# The pressure frame's opening: the ship's hull fills it (its sides at z +-15, its roof at 11.5).
MOUTH_HALF, MOUTH_TOP = 15.0, 12.0
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
# Clamp mounts beside the hull (the clamps themselves move and always show, see CLAMPS); low
# enough to keep the hull in view.
for side, name in [(-1, "Back"), (1, "Front")]:
    box(f"ClampMount{name}", (2.5, 10.5, 1.5), (10.75, 5.25, side * 21.0), "cut")

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
# Behind the hull two above each other; in front low along its lower edge, under the cut-away decks,
# so they don't cover the cargo bay while they take hold.
CLAMPS = [(10.75, 4.0, -1), (10.75, 9.0, -1), (9.75, 2.0, 1), (13.25, 2.0, 1)]
for i, (x, y, side) in enumerate(CLAMPS):
    nodes += [
        f'[node name="Clamp{i + 1}" type="Node3D" parent="Clamps"]',
        f"transform = {xform((x, y, side * (MOUTH_HALF + 0.3)))}",
        "",
        f'[node name="Pad" type="MeshInstance3D" parent="Clamps/Clamp{i + 1}"]',
        'mesh = SubResource("BoxMesh_clamp_pad")',
        "",
        f'[node name="Arm" type="MeshInstance3D" parent="Clamps/Clamp{i + 1}"]',
        f"transform = {xform((0, 0, side * 2.3))}",
        'mesh = SubResource("BoxMesh_clamp_arm")',
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

ext = [
    ("Script", SCRIPT, "script"),
    ("Script", GUIDE_SCRIPT, "guide_script"),
    ("StandardMaterial3D", GUIDE_MATERIAL, "mat_guide"),
    ("StandardMaterial3D", PROP_MATERIAL, "mat_prop"),
]
out = write(OUT, ROOT, ext, subs, nodes, "ostra_build.py")
if out:
    print(len(kit.walls), "wall pieces,", len(kit.glass), "windows,", out.count("[node "), "nodes")
