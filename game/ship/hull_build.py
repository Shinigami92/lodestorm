"""Builds the ship's greybox hull, game/ship/hull.tscn: floors, walls with doors and windows, the
upper deck's slab, the roof, and the shapes of the nose and the landing legs (their look is the
hull's model, ShipExterior). Run it after changing the layout, from the repo root:

    python game/ship/hull_build.py           # writes it
    python game/ship/hull_build.py --check   # fails if it differs (tools/lint.sh python, CI)

Only hull.tscn is written; the rooms are scenes of their own (game/ship/rooms/), placed in
ship.tscn. They must match the layout (game/ship/hull_layout.py: ROOMS, position and size), so
moving a room means changing it there, rebuilding, and moving the room's scene and resizing its
floor by hand. Axes and sections: see hull_layout.py. Everything built must stay inside the skin of
the hull's model (hull_layout.inside_skin): the script fails otherwise.

Where the shell is the kit's model (hull_layout.SHELL_REGIONS), the pieces keep only their collision
shapes, and the model's part per group (assets/ship/shell/<group>.glb, built by
assets/ship/source/ship_shell_build.py, which imports this script for its pieces) is placed under the
group's node with ShipShell (game/ship/ship_shell.gd).

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
    COCKPIT_OUTLINE,
    COCKPIT_TOP,
    COCKPIT_WINDOWS,
    CREW_X,
    CW,
    GEAR,
    LAB_FLOOR,
    LAB_OUTLINE,
    LEG_PAD,
    LEG_X,
    LEG_Z,
    LOW,
    NICHE,
    NICHE_HEIGHT,
    NICHE_SIDE,
    RAMP_DOOR_HEIGHT,
    RAMP_WIDTH,
    RANGE_DOOR,
    SHELL_SPLITS,
    SLAB,
    TOP,
    UP,
    VENDORS,
    ZI,
    dressed,
    inside_skin,
    outer_windows,
    outline,
)

from greybox import Greybox, g, sid, vec, write, xform

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "ship" / "hull.tscn"

STUB = 1.0
GROUP_PARENT = {"hull": ".", "lower_cut": "LowerCut", "upper": "Upper", "upper_cut": "Upper/Cut"}
HULL_MATERIAL = ["albedo_color = Color(0.3, 0.31, 0.33, 1)", "metallic = 0.2", "roughness = 0.6"]
box_kit = Greybox(GROUP_PARENT, "hull", HULL_MATERIAL, stub=STUB, door=3.0, sill=1.0, window_height=2.0)
box_kit.splits = SHELL_SPLITS
box_kit.dressed = dressed
wall = box_kit.wall
box = box_kit.box
outer_wall = box_kit.outer_wall


LOWER_FRONT = ("lower_cut", "hull")
UPPER_FRONT = ("upper_cut", "upper")

# --- outer hull ---
box("Floor", (96, 1, 30), (-33, LOW - 0.5, 0))
# The tail wall with the ramp door.
JAMB = ZI - RAMP_WIDTH / 2
box("RightWallBack", (0.5, TOP - LOW, JAMB), (14.75, (LOW + TOP) / 2, -(ZI - JAMB / 2)))
box("RightWallFront", (0.5, TOP - LOW, JAMB), (14.75, (LOW + TOP) / 2, ZI - JAMB / 2), "lower_cut")
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

# --- the nose rooms: the specimen lab below, the cockpit above, past the box's nose wall ---
box_kit.prism("LabFloor", outline(LAB_OUTLINE), LOW - LAB_FLOOR, LOW)
box_kit.prism("CockpitSlab", outline(COCKPIT_OUTLINE), SLAB, UP, "upper")
box_kit.prism("CockpitRoof", outline(COCKPIT_OUTLINE), COCKPIT_TOP, COCKPIT_TOP + 0.5, "upper_cut")
for nose, half, y0, y1, cut, kept in [
    ("Lab", LAB_OUTLINE, LOW, UP, LOWER_FRONT, "hull"),
    ("Cockpit", COCKPIT_OUTLINE, UP, COCKPIT_TOP, UPPER_FRONT, "upper"),
]:
    (_, _), (x0, z0), (x1, z1) = half
    box_kit.segment(f"{nose}SideBack", (x0, z0), (x1, z1), y0, y1, kept)
    box_kit.segment(f"{nose}SideFront", (x1, -z1), (x0, -z0), y0, y1, *cut)
wall("LabFront", "z", LAB_OUTLINE[2][0], LAB_OUTLINE[2][1], -LAB_OUTLINE[2][1], LOW, UP)
x_front, z_front = COCKPIT_OUTLINE[2]
outer_wall("CockpitFront", "z", x_front, z_front, -z_front, UP, COCKPIT_TOP, COCKPIT_WINDOWS, "upper")

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
wall("NoseWallLower", "z", -80.75, -ZI, ZI, LOW, UP, doors=[(0, 3)], front=LOWER_FRONT)
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
wall("CockpitWall", "z", -80.75, -ZI, ZI, UP, TOP, doors=[(0, 3)], group="upper", front=UPPER_FRONT)
blocks = CABIN_X + CREW_X
for i, (_, b) in enumerate(blocks):
    name = "MessWall" if i == len(blocks) - 1 else f"CabinWall{i + 1}"
    wall(name + "Back", "z", b + 0.25, -ZI, -3, UP, TOP, group="upper")
    wall(name + "Front", "z", b + 0.25, 3, ZI, UP, TOP, group="upper", front=UPPER_FRONT)
cabin_doors = [((a + b) / 2, 1.5) for a, b in blocks]
wall("UpperCorridorBack", "x", -CW, -51.5, -19.5, UP, TOP, cabin_doors, "upper_cut", "upper")
wall("UpperCorridorFront", "x", CW, -51.5, -19.5, UP, TOP, cabin_doors, "upper_cut", "upper")

# --- outer walls, the windows in niches ---
# Along the box, and on into the nose rooms' straight stretch (the cockpit's under its lower ceiling;
# the lab's windows without niches, the belly rises under them).
for side, name, lower, upper in [(-1, "Back", ("hull",), ("upper",)), (1, "Front", LOWER_FRONT, UPPER_FRONT)]:
    z = side * (ZI + 0.25)
    for deck, y0, y1, x0, x1, groups, floor_group in [
        ("Lab", LOW, UP, LAB_OUTLINE[1][0], -81, lower, None),
        ("Lower", LOW, UP, -81, 15, lower, "hull"),
        ("Cockpit", UP, COCKPIT_TOP, COCKPIT_OUTLINE[1][0], -81, upper, "upper"),
        ("Upper", UP, TOP, -81, 15, upper, "upper"),
    ]:
        wins = [(c, w) for c, w in outer_windows("Upper" if y0 == UP else "Lower", side) if x0 < c < x1]
        niche = (side, NICHE, NICHE_SIDE, NICHE_HEIGHT, LAB_FLOOR, floor_group) if floor_group else None
        outer_wall(f"{name}Wall{deck}", "x", z, x0, x1, y0, y1, wins, *groups, niche=niche)


# --- the skin: everything stays inside the hull's model ---
outside = sorted(
    {name for name, (x, y, z) in box_kit.corners() if name != "Underside" and not inside_skin(x, z, y, 0.2)}
)
if outside:
    sys.exit("outside the hull's skin: " + ", ".join(outside))


def shell_parts():
    """The kit's model per group that exists: (group, path, ext_resource id)."""
    parts = []
    for group in GROUP_PARENT:
        path = ROOT / "assets" / "ship" / "shell" / f"{group}.glb"
        if path.exists():
            parts.append((group, f"res://assets/ship/shell/{group}.glb", f"shell_{group}"))
    return parts


def main():
    # --- sub-resources ---
    subs = box_kit.subresources()
    # The nose's shape keeps players out from under it, below the specimen lab's floor.
    nose_top = LOW - LAB_FLOOR
    subs += [
        '[sub_resource type="ConvexPolygonShape3D" id="ConvexPolygonShape3D_nose"]',
        f"points = PackedVector3Array(-81, {g(GEAR)}, -15, -81, {g(GEAR)}, 15, -81, {g(nose_top)}, -15, -81, {g(nose_top)}, 15, -91, {g(GEAR)}, 0, -91, {g(nose_top)}, 0)",
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

    # The kit's shell where it replaces the greybox.
    parts = shell_parts()
    ext = [("Script", "res://game/ship/ship_shell.gd", "shell_script")] if parts else []
    for group, path, rid in parts:
        ext.append(("PackedScene", path, rid))
        name = "Shell" + "".join(w.capitalize() for w in group.split("_"))
        nodes += [
            f'[node name="{name}" parent="{GROUP_PARENT[group]}" instance=ExtResource("{rid}")]',
            'script = ExtResource("shell_script")',
            "",
        ]

    out = write(OUT, ROOT, ext, subs, nodes, "hull_build.py")
    if out:
        print(len(box_kit.walls), "wall pieces,", len(box_kit.glass), "windows,", out.count("[node "), "nodes")


if __name__ == "__main__":
    main()
