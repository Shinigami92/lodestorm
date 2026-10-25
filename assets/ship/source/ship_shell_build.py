"""The ship's shell from the modular kit (docs/planned/ship-interior.md): the greybox hull's wall pieces
(game/ship/hull_build.py, imported for them) dressed where the layout says (hull_layout.SHELL_REGIONS),
plus the rooms' floors there.

Every wall piece keeps its size and place as a painted core. A ship's cross-section instead of a box's: on
every face the camera sees, a 45° chamfer up to the ceiling with a light line in it and a slanted foot on the
floor; along the top of each wall the camera cuts, a heavy round rim showing the hull's thickness (on the
stubs too, with a lamp line). Doors and window niches get heavy frames with rounded corners, doors a
hazard-striped threshold. Walls cut away for the camera only cast shadows, so they stay plain cores. Floors
are one plate with amber edge markings, the corridor's with a grating strip down its middle; a room on the
outer wall gets an accent strip along it.

The materials are placeholders named for the game: ShipShell (game/ship/ship_shell.gd) swaps in the
shell's shaders by name (ShellPaint, ShellDark, ShellPlate, ShellGrating, ShellHazard, ShellMarking,
ShellAccent, ShellLamp). Each group of the hull (hull, lower_cut, upper, upper_cut) is its own model,
placed under the group's node; a room's floor and its accents are objects of their own (named "<room>" and
"<room>Accent"), so the game can give them the room's look.

Run from the repo root:
    tools/blender.sh assets/ship/source/ship_shell_build.py wip <tag>   renders to tmp/ship_shell/ (with the
                                                                        game's textures)
    tools/blender.sh assets/ship/source/ship_shell_build.py final       writes assets/ship/shell/<group>.glb

Godot axes (x tail, y up, z towards the camera) become Blender's (x, -z, y).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "ship_shell"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "game" / "ship"))

import bmesh
import bpy
import hull_build as H
import hull_layout as L
from mathutils import Vector

import common as C

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "s0"
C.reset("Shell")


def flat(name: str, color, roughness: float = 0.6, metallic: float = 0.3, emission=None, strength: float = 0.0):
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def textured(name: str, texture: str, tile: float, tint, metallic: float):
    """For the renders: the game's texture set projected like the shell's shader does (from the axis
    a face looks along), tinted."""
    mat = bpy.data.materials.new(name)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coords = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1 / tile)
    nt.links.new(coords.outputs["Object"], mapping.inputs["Vector"])
    folder = ROOT / "assets" / "ship" / "textures"
    albedo = nt.nodes.new("ShaderNodeTexImage")
    albedo.image = bpy.data.images.load(str(folder / f"{texture}_albedo.png"))
    albedo.projection = "BOX"
    nra = nt.nodes.new("ShaderNodeTexImage")
    nra.image = bpy.data.images.load(str(folder / f"{texture}_nra.png"))
    nra.image.colorspace_settings.name = "Non-Color"
    nra.projection = "BOX"
    for node in (albedo, nra):
        nt.links.new(mapping.outputs["Vector"], node.inputs["Vector"])
    tinted = nt.nodes.new("ShaderNodeMix")
    tinted.data_type = "RGBA"
    tinted.blend_type = "MULTIPLY"
    tinted.inputs["Factor"].default_value = 1.0
    nt.links.new(albedo.outputs["Color"], tinted.inputs["A"])
    tinted.inputs["B"].default_value = (*tint, 1)
    nt.links.new(tinted.outputs["Result"], bsdf.inputs["Base Color"])
    split = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(nra.outputs["Color"], split.inputs["Color"])
    nt.links.new(split.outputs["Blue"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


if MODE == "wip":
    BASE = [
        textured("ShellPaint", "paint", 3.0, (1.0, 1.0, 1.0), 0.0),
        textured("ShellDark", "paint", 3.0, (0.32, 0.32, 0.34), 0.2),
        textured("ShellPlate", "epoxy", 3.0, (1.0, 1.0, 1.0), 0.0),
        textured("ShellGrating", "grating", 1.0, (1.0, 1.0, 1.0), 0.0),
    ]
else:
    BASE = [
        flat("ShellPaint", (0.27, 0.28, 0.27), 0.55, 0.4),
        flat("ShellDark", (0.07, 0.07, 0.075), 0.45, 0.6),
        flat("ShellPlate", (0.2, 0.2, 0.2), 0.5, 0.6),
        flat("ShellGrating", (0.1, 0.1, 0.1), 0.45, 0.7),
    ]
MATS = BASE + [
    flat("ShellHazard", (0.6, 0.45, 0.05), 0.6, 0.0),
    flat("ShellMarking", (0.55, 0.32, 0.05), 0.6, 0.0),
    flat("ShellAccent", (0.2, 0.2, 0.2), 0.4, 0.0, (1.0, 0.6, 0.2), 4.0),
    flat("ShellLamp", (0.3, 0.3, 0.3), 0.4, 0.0, (1.0, 0.9, 0.75), 4.0),
]
PAINT, DARK, PLATE, GRATING, HAZARD, MARKING, ACCENT, LAMP = range(len(MATS))

GROUPS = {"hull": "Hull", "lower_cut": "LowerCut", "upper": "Upper", "upper_cut": "UpperCut"}
CUT = ("lower_cut", "upper_cut")  # only cast shadows: plain cores
FLOOR_TOP = 0.008  # the floor plates' height over the deck (under the rooms' painted names)
MARK = 0.006  # the edge markings' height over the plates
CORNER = 0.8  # the radius rounding a room's corners in the plan


class Shell:
    """One object per (group, name): its Part and whether it's beveled."""

    def __init__(self):
        self.parts: dict[tuple[str, str], C.Part] = {}

    def part(self, group: str, name: str) -> C.Part:
        key = (group, name)
        if key not in self.parts:
            self.parts[key] = C.Part(f"{name}", MATS, bevel=(0.015, 1))
        return self.parts[key]

    def finish(self) -> dict[str, list]:
        made: dict[str, list] = {}
        for (group, name), part in self.parts.items():
            obj = part.finish(None)
            obj.name = name
            C.collection(GROUPS[group]).objects.link(obj)
            for coll in obj.users_collection:
                if coll.name == "Shell":
                    coll.objects.unlink(obj)
            made.setdefault(group, []).append(obj)
        return made


def to_blender(p) -> tuple[float, float, float]:
    return (p[0], -p[2], p[1])


def extrude(part: C.Part, ring, offset, mi: int) -> None:
    """A prism: the polygon `ring` (Godot points, in order) and its copy moved by `offset`."""
    bm = part.bm
    a = [bm.verts.new(to_blender(p)) for p in ring]
    b = [bm.verts.new(to_blender(Vector(p) + offset)) for p in ring]
    n = len(ring)
    faces = [bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i])) for i in range(n)]
    faces += [bm.faces.new(list(reversed(a))), bm.faces.new(b)]
    for f in faces:
        f.material_index = mi
        f.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def gbox(part: C.Part, center, size, yaw: float = 0.0, mi: int = PAINT) -> None:
    """A box in Godot coordinates (center, size along its own x, y, z), turned by yaw around y."""
    part.box(to_blender(center), (size[0], size[2], size[1]), rot=C.rz(math.degrees(yaw)), mi=mi)


class Piece:
    """A greybox wall piece in its own frame: length along u, height along v, thickness along w."""

    def __init__(self, wall):
        self.name, size, center, self.group, self.stub_group, self.kind, yaw = wall
        if yaw == 0.0 and size[2] > size[0]:  # a wall along z: turn it so its length runs along u
            size, yaw = (size[2], size[1], size[0]), -math.pi / 2
        self.length, self.height, self.thick = size
        self.center, self.yaw = Vector(center), yaw
        self.dir = Vector((math.cos(yaw), 0.0, -math.sin(yaw)))  # u in Godot coordinates
        self.normal = Vector((math.sin(yaw), 0.0, math.cos(yaw)))  # w
        self.y0 = center[1] - self.height / 2
        # The deck it stands on: what's seen of it lies between its floor and ceiling.
        upper = center[1] >= L.UP - 0.1
        self.floor, self.ceiling = (L.UP, L.TOP) if upper else (L.LOW, L.SLAB)
        if center[0] > L.ROOMS[-1][2][0] - 0.1:  # the cargo bay: one room through both decks
            self.floor, self.ceiling = L.LOW, L.TOP
        elif upper and center[0] < -81.0:  # the cockpit, under the nose's sloping top
            self.ceiling = L.COCKPIT_TOP
        # Floors, slabs, the roof, a niche's floor and lid: plain cores.
        self.flat = self.height < min(self.length, self.thick)

    def at(self, u: float, v: float, w: float) -> Vector:
        """Godot coordinates of (u, v, w); v from the piece's bottom."""
        return self.center + self.dir * u + Vector((0, self.y0 + v - self.center.y, 0)) + self.normal * w

    def faces(self) -> list[int]:
        """The sides (+1, -1 along w) facing into the ship: an outer wall only its inner one."""
        outer = abs(self.center.z) > L.ZI and abs(self.normal.z) > 0.9
        if outer:
            return [-1 if self.center.z > 0 else 1] if self.normal.z > 0 else [1 if self.center.z > 0 else -1]
        return [1, -1]

    def box(self, part, u, v, w, size, mi):
        """A box centered at (u, v, w) in the piece's frame, size along (u, v, w)."""
        gbox(part, self.at(u, v, w), size, self.yaw, mi)

    def along(self, part, side: int, u0: float, u1: float, profile, mi) -> None:
        """A profile (x into the room from the face, v) on the `side` face, run from u0 to u1."""
        t = self.thick / 2
        ring = [self.at(u0, v, side * (t + x)) for x, v in profile]
        extrude(part, ring, self.dir * (u1 - u0), mi)

    def across(self, part, outline, w0: float, w1: float, mi) -> None:
        """An outline (u, v) in the wall's plane, from w0 through to w1."""
        extrude(part, [self.at(u, v, w0) for u, v in outline], self.normal * (w1 - w0), mi)

    def reaches_ceiling(self) -> bool:
        return self.y0 + self.height >= self.ceiling - 0.01

    def stands_on_floor(self) -> bool:
        return self.y0 <= self.floor + 0.01


def dress_wall(shell: Shell, piece: Piece) -> None:
    """The wall's painted core (its chamfer, foot and rim: profile(), rim())."""
    part = shell.part(piece.group, "Shell")
    piece.box(part, 0, piece.height / 2, 0, (piece.length, piece.height, piece.thick), PAINT)


CHAMFER = 0.7  # the 45° slope between a wall and the ceiling
FOOT = 0.3  # the slanted foot between a wall and the floor
RIM = 0.12  # how far the rounded rim on a cut wall's top stands out of the wall


def profile(shell: Shell, piece: Piece) -> None:
    """A ship's cross-section instead of a box: on every face seen, a slope up to the ceiling with a light
    line in it, a slanted foot on the floor (pieces of any size, so doors and niches keep the line)."""
    if piece.group in CUT or piece.length < 0.3 or piece.flat:
        return
    part = shell.part(piece.group, "Shell")
    lo, hi = -piece.length / 2, piece.length / 2
    top = piece.ceiling - piece.y0
    c = CHAMFER
    for side in piece.faces():
        if piece.reaches_ceiling() and top >= c:
            piece.along(part, side, lo, hi, [(0, top - c), (c, top), (0, top)], DARK)
            a, b = 0.38 * c, 0.62 * c
            line = [
                (a, top - c + a),
                (b, top - c + b),
                (b - 0.035, top - c + b + 0.035),
                (a - 0.035, top - c + a + 0.035),
            ]
            piece.along(part, side, lo + 0.05, hi - 0.05, line, LAMP)
        if piece.stands_on_floor() and piece.height >= FOOT:
            piece.along(part, side, lo, hi, [(0, 0), (FOOT, 0), (0, FOOT)], DARK)


def rim(shell: Shell, piece: Piece) -> None:
    """The wall's thickness where the camera cuts it: a rounded rim along the top of a wall that reaches up
    to the deck above (heavy on the hull's outer walls)."""
    if piece.group in CUT or not piece.reaches_ceiling() or piece.length < 0.3 or piece.flat:
        return
    part = shell.part(piece.group, "Shell")
    # The hull's outer walls get the heavy rim, the walls between rooms a slim one.
    outer = abs(piece.center.z) > L.ZI
    radius = piece.thick / 2 + (RIM if outer else 0.03)
    v = piece.height - radius  # its top at the wall's: nothing pokes into the deck above
    a, b = piece.at(-piece.length / 2, v, 0), piece.at(piece.length / 2, v, 0)
    part.rod(to_blender(a), to_blender(b), radius, seg=16, mi=DARK)


def rounded_frame(part, piece: Piece, width: float, height: float, bottom: float, w0: float, w1: float) -> None:
    """A heavy frame with rounded top corners around an opening (u -width/2..width/2, v bottom..bottom +
    height), from w0 to w1: posts, a head, and corners that round the opening off."""
    margin, radius, steps = 0.32, 0.45, 8
    half, top = width / 2, bottom + height
    r = min(radius, half - 0.05, height / 2)
    for s in (-1, 1):
        post = [(s * half, bottom), (s * (half + margin), bottom), (s * (half + margin), top - r), (s * half, top - r)]
        piece.across(part, post, w0, w1, DARK)
        cu, cv = s * (half - r), top - r
        angles = [math.radians((0 if s > 0 else 90) + 90 * i / steps) for i in range(steps + 1)]
        outer = [(cu + (r + margin) * math.cos(a), cv + (r + margin) * math.sin(a)) for a in angles]
        inner = [(cu + r * math.cos(a), cv + r * math.sin(a)) for a in angles]
        piece.across(part, outer + inner[::-1], w0, w1, DARK)
        piece.across(part, [(s * half, top)] + (inner if s > 0 else inner[::-1]), w0, w1, DARK)
    head = [(-half + r, top), (half - r, top), (half - r, top + margin), (-half + r, top + margin)]
    piece.across(part, head, w0, w1, DARK)


def dress_stub(shell: Shell, piece: Piece) -> None:
    """A cut wall's stub: STUB high, its kick plates, a round rim showing the wall's thickness, a lamp line."""
    part = shell.part(piece.stub_group, "Shell")
    stub = H.STUB
    piece.box(part, 0, stub / 2, 0, (piece.length, stub, piece.thick - 0.02), PAINT)
    for side in (1, -1):
        piece.box(part, 0, 0.15, side * (piece.thick / 2 + 0.01), (piece.length, 0.3, 0.04), DARK)
    radius = piece.thick / 2 + RIM * 0.6
    a, b = piece.at(-piece.length / 2, stub, 0), piece.at(piece.length / 2, stub, 0)
    part.rod(to_blender(a), to_blender(b), radius, seg=16, mi=DARK)
    piece.box(part, 0, stub + radius, 0, (max(0.1, piece.length - 0.2), 0.012, 0.05), LAMP)


def dress_door(shell: Shell, piece: Piece) -> None:
    """A lintel over a door: the frame around the opening and the threshold (the frame goes with its
    wall; the threshold stays on the floor)."""
    floor_group = "upper" if piece.floor == L.UP else "hull"
    door_h = piece.y0 - piece.floor
    lo, hi = -piece.length / 2, piece.length / 2
    t = piece.thick / 2
    if piece.group not in CUT:
        part = shell.part(piece.group, "Shell")
        rounded_frame(part, piece, hi - lo, door_h, -door_h, -(t + 0.1), t + 0.1)
    floor = shell.part(floor_group, "Shell")
    piece.box(floor, 0, -door_h + FLOOR_TOP / 2 + 0.005, 0, (piece.length, FLOOR_TOP + 0.01, t * 2 + 0.8), HAZARD)


def dress_niche(shell: Shell, piece: Piece) -> None:
    """The wall over a niche's opening: a frame around the opening on the room's side."""
    if piece.group in CUT:
        return
    part = shell.part(piece.group, "Shell")
    side = piece.faces()[0]
    t = piece.thick / 2
    rounded_frame(part, piece, piece.length - 0.5, L.NICHE_HEIGHT, -L.NICHE_HEIGHT, side * t, side * (t + 0.16))


def deck_group(deck) -> str:
    return "upper" if deck == "Upper" else "hull"


def floors(shell: Shell) -> None:
    """The rooms' floors: one plate with amber edge markings (the corridors' with a grating strip down their
    middle, the nose rooms' following their outline), and a room on the back outer wall gets an accent strip
    along it."""
    for name, deck, xs, zs in L.ROOMS:
        floor, ceiling, (x0, x1, z0, z1) = H.room_box(name, deck, xs, zs)
        part = shell.part(deck_group(deck), name)
        outline = {"Cockpit": L.COCKPIT_OUTLINE, "SpecimenLab": L.LAB_OUTLINE}.get(name)
        if outline:
            ring = [(x, floor, z) for x, z in L.outline(outline)]
            extrude(part, ring, Vector((0, FLOOR_TOP, 0)), PLATE)
            continue
        mid = ((x0 + x1) / 2, floor + FLOOR_TOP / 2, (z0 + z1) / 2)
        gbox(part, mid, (x1 - x0, FLOOR_TOP, z1 - z0), mi=PLATE)
        y = floor + FLOOR_TOP + MARK / 2
        if name.endswith("Corridor"):
            gbox(part, (mid[0], y, mid[2]), (x1 - x0, MARK, 1.6), mi=GRATING)
            for s in (-1, 1):
                gbox(part, (mid[0], y, mid[2] + s * 0.95), (x1 - x0, MARK, 0.1), mi=MARKING)
            continue
        inset = 0.45
        for z in (z0 + inset, z1 - inset):
            gbox(part, (mid[0], y, z), (x1 - x0 - 2 * inset, MARK, 0.1), mi=MARKING)
        for x in (x0 + inset, x1 - inset):
            gbox(part, (x, y, mid[2]), (0.1, MARK, z1 - z0 - 2 * inset), mi=MARKING)
        if z0 == -L.ZI:
            # An object of its own: instance shader parameters share slots across one object's materials.
            accent = shell.part(deck_group(deck), name + "Accent")
            gbox(accent, (mid[0], ceiling - 0.35, z0 + 0.06), (x1 - x0 - 1.0, 0.07, 0.06), mi=ACCENT)


def corners(shell: Shell) -> None:
    """Rounded room corners in the plan: a fillet from the floor to the ceiling in each corner of a room (not
    the corridors, lobbies or the nose rooms). Only the corners on the back outer wall stay standing; the
    others are on walls cut away for the camera and go with them."""
    steps = 8
    for name, deck, xs, zs in L.ROOMS:
        if name.endswith(("Corridor", "Lobby")) or name in ("Cockpit", "SpecimenLab"):
            continue
        floor, ceiling, (x0, x1, z0, z1) = H.room_box(name, deck, xs, zs)
        r = min(CORNER, (x1 - x0) / 4, (z1 - z0) / 4)
        for cx, sx in ((x0, 1), (x1, -1)):
            for cz, sz in ((z0, 1), (z1, -1)):
                seen = cz == -L.ZI
                group = deck_group(deck) if seen else ("upper_cut" if deck == "Upper" else "lower_cut")
                # The corner, then the arc from one wall to the other around (cx + r, cz + r).
                ring = [(cx, floor, cz)]
                for i in range(steps + 1):
                    a = math.pi / 2 * i / steps
                    ring.append((cx + sx * r * (1 - math.cos(a)), floor, cz + sz * r * (1 - math.sin(a))))
                extrude(shell.part(group, "Shell"), ring, Vector((0, ceiling - floor, 0)), PAINT)


def conduit(shell: Shell) -> None:
    """The drive core's conduits from the engine room to the cargo bay: two pipes along the lower deck's back
    outer wall under its chamfer, held by brackets."""
    part = shell.part("hull", "Shell")
    z = -L.ZI + 0.35
    x0, x1 = -80.5, L.ROOMS[-1][2][1]
    for y, radius in ((L.SLAB - 0.95, 0.11), (L.SLAB - 1.25, 0.07)):
        part.rod(to_blender((x0, y, z)), to_blender((x1, y, z)), radius, seg=12, mi=DARK)
    x = x0 + 1.0
    while x < x1:
        gbox(part, (x, L.SLAB - 1.1, -L.ZI + 0.2), (0.12, 0.55, 0.4), mi=DARK)
        x += 2.5


def fixtures(shell: Shell) -> None:
    """A lamp housing in the ceiling over each of the rooms' lamps (hull_build.room_lights), with its glowing
    panel; with the ceiling's group (cut away aboard, seen when the head looks up in VR)."""
    for name, deck, xs, zs in L.ROOMS:
        _floor, ceiling, (x0, x1, z0, z1) = H.room_box(name, deck, xs, zs)
        group = "upper_cut" if deck in ("Upper", None) else "upper"
        part = shell.part(group, "Shell")
        for x in H.spread(x0, x1, H.LAMP_STEP):
            gbox(part, (x, ceiling - 0.06, (z0 + z1) / 2), (1.4, 0.12, 0.5), mi=DARK)
            gbox(part, (x, ceiling - 0.125, (z0 + z1) / 2), (1.2, 0.01, 0.35), mi=LAMP)


def build() -> dict[str, list]:
    shell = Shell()
    for wall in H.box_kit.walls:
        if not L.dressed(wall[2]) or wall[5] == "shape":
            continue
        piece = Piece(wall)
        if "Lintel" in piece.name:
            dress_wall(shell, piece)
            dress_door(shell, piece)
        elif "Over" in piece.name:
            dress_wall(shell, piece)
            dress_niche(shell, piece)
        else:
            dress_wall(shell, piece)
        profile(shell, piece)
        rim(shell, piece)
        if piece.stub_group:
            dress_stub(shell, piece)
    floors(shell)
    corners(shell)
    conduit(shell)
    fixtures(shell)
    return shell.finish()


# --- preview ---------------------------------------------------------------------------------------


def preview() -> None:
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 2.0
    sun_obj = bpy.data.objects.new("Sun", sun)
    sun_obj.rotation_euler = Vector((0.4, 0.8, -0.9)).to_track_quat("-Z", "Y").to_euler()
    bpy.data.collections["Preview"].objects.link(sun_obj)
    for x in (-17.0, -8.0):  # the armory's work lights
        lamp = bpy.data.lights.new("Lamp", "POINT")
        lamp.energy = 900
        lamp.color = (1.0, 0.85, 0.6)
        obj = bpy.data.objects.new("Lamp", lamp)
        obj.location = to_blender((x, L.SLAB - 0.6, -9.0))
        bpy.data.collections["Preview"].objects.link(obj)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.35, depth=1.85, location=to_blender((-12.0, L.LOW + 0.93, -7.0)))
    fig = bpy.context.active_object
    fig.data.materials.append(flat("Figure", (0.8, 0.4, 0.1), 0.5, 0.0, (1.0, 0.5, 0.1), 1.0))
    for c in fig.users_collection:
        c.objects.unlink(fig)
    bpy.data.collections["Preview"].objects.link(fig)
    world = bpy.data.worlds.new("World")
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.01, 0.012, 0.016, 1)
    bpy.context.scene.world = world


def render(view: str) -> None:
    scene = bpy.context.scene
    for group in CUT:  # aboard, cut walls only cast shadows
        for obj in bpy.data.collections[GROUPS[group]].objects:
            obj.visible_camera = False
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    target = Vector(to_blender((-12.0, L.LOW + 1.0, -6.0)))
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.data.collections["Preview"].objects.link(cam)
    if view == "iso":  # the game's camera: yaw 45° (from +x +z), 35.264° down, 40 m, 30° field of view
        pitch, yaw = math.radians(35.264), math.radians(45)
        d = (math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
        cam.location = target + Vector(to_blender(d)) * 40.0
        cam_data.angle_y = math.radians(30)
    else:  # close: the lockers from the room
        cam.location = Vector(to_blender((-12.0, L.LOW + 1.7, -3.0)))
        target = Vector(to_blender((-12.0, L.LOW + 1.8, -14.0)))
        cam_data.angle_y = math.radians(60)
    cam_data.sensor_fit = "VERTICAL"
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    path = OUT / f"{TAG}_{view}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


for coll in GROUPS.values():
    bpy.context.scene.collection.children.link(bpy.data.collections.new(coll))
made = build()
if MODE == "wip":
    preview()
    for v in ("iso", "close"):
        render(v)
    C.save_blend(OUT / f"{TAG}.blend")
elif MODE == "final":
    for group in made:
        C.export_glb(ROOT / "assets" / "ship" / "shell" / f"{group}.glb", GROUPS[group])
        print(group, C.stats(GROUPS[group]))
