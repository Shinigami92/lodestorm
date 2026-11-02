"""Waypost Ostra's shell, its own kit (an old, heavy industrial station rather than the ship's clean hull): every
wall of the layout (game/space_station/ostra/ostra_layout.py) as a painted steel core with heavy pilasters, a
kick plate, a rail and conduits on each side that faces a room, steel frames with hazard stripes round the doors,
framed windows, square columns where walls meet, the machinery blocks between the hub and the rooms' corners,
and the rooms' floors (one object per room, named after it, so the game can tint it) with gratings.

The camera's rules are the ship's: a wall in the "cut" group only casts shadows while the viewer is inside, down
to a STUB m high stub, which always shows with a capped top and an amber light line (so the rooms stay
outlined). So everything is split at the stub's height into two models, and the window glass goes apart (the
cut walls' glass is hidden with them):

    assets/space_station/ostra/shell/shell_station.glb   always shown: floors, back walls, stubs, columns' feet
    assets/space_station/ostra/shell/shell_cut.glb       the cut walls above their stubs
    assets/space_station/ostra/shell/glass_station.glb   the back walls' window panes
    assets/space_station/ostra/shell/glass_cut.glb       the cut walls' window panes

The materials are placeholders named for the game (OstraPaint, OstraPaintDark, OstraMetal, OstraFloor,
OstraGrating, OstraHazard, OstraAmber, OstraLamp, OstraGlass): OstraLook (game/space_station/ostra_look.gd)
swaps in the station's materials by name.

Run from the repo root:
    tools/blender.sh assets/space_station/ostra/source/ostra_shell_build.py           writes the models
    tools/blender.sh assets/space_station/ostra/source/ostra_shell_build.py preview   also renders to tmp/ostra_shell/

Godot axes (x right, y up, z towards the camera) become Blender's (x, -z, y).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "assets" / "space_station" / "ostra" / "shell"
TMP = ROOT / "tmp" / "ostra_shell"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))  # ostra_materials
sys.path.insert(0, str(ROOT / "game" / "space_station" / "ostra"))


import bpy
import ostra_layout as L
from mathutils import Vector

import common as C
from ostra_materials import material

ARGV = C.args()
C.reset("Shell")


MATS = [
    material(n)
    for n in (
        "OstraPaint",
        "OstraPaintDark",
        "OstraMetal",
        "OstraFloor",
        "OstraGrating",
        "OstraHazard",
        "OstraAmber",
        "OstraLamp",
        "OstraGlass",
    )
]
PAINT, DARK, METAL, FLOOR, GRATING, HAZARD, AMBER, LAMP, GLASS = range(len(MATS))

STUB = L.STUB
T = L.WALL / 2  # half a wall's thickness
FLOOR_TOP = 0.01
RIB_STEP = 3.6  # pilasters' spacing along a wall
GROUPS = {"station": "Station", "cut": "Cut", "glass_station": "GlassStation", "glass_cut": "GlassCut"}


def to_blender(p) -> tuple[float, float, float]:
    return (p[0], -p[2], p[1])


class Shell:
    """One object per (group, name)."""

    def __init__(self):
        self.parts: dict[tuple[str, str], C.Part] = {}

    def part(self, group: str, name: str = "Shell") -> C.Part:
        key = (group, name)
        if key not in self.parts:
            glass = group.startswith("glass")
            self.parts[key] = C.Part(name, MATS, bevel=None if glass or name in ROOM_NAMES else (0.02, 1))
        return self.parts[key]

    def finish(self) -> None:
        for (group, name), part in self.parts.items():
            obj = part.finish(None)
            obj.name = name if group in ("station", "cut") else GROUPS[group]
            for coll in obj.users_collection:
                coll.objects.unlink(obj)
            C.collection(GROUPS[group]).objects.link(obj)


ROOM_NAMES = {room[0] for room in L.ROOMS}


def gbox(part: C.Part, center, size, yaw: float = 0.0, mi: int = PAINT) -> None:
    """A box in Godot coordinates (center, size along its own x, y, z), turned by yaw (Blender's z rotation)."""
    if min(size) <= 0.0005:
        return
    part.box(to_blender(center), (size[0], size[2], size[1]), rot=C.rz(math.degrees(yaw)), mi=mi)


def inside(poly, x: float, z: float) -> bool:
    """Whether (x, z) lies inside the polygon (even-odd)."""
    hit = False
    n = len(poly)
    for i in range(n):
        (ax, az), (bx, bz) = poly[i], poly[(i + 1) % n]
        if (az > z) != (bz > z) and x < ax + (z - az) * (bx - ax) / (bz - az):
            hit = not hit
    return hit


def room_at(x: float, z: float):
    """The room (name, ceiling height) at (x, z), or None outside every room (or in a machinery block)."""
    for _name, poly in L.FILLS:
        if inside(poly, x, z):
            return None
    for name, _sign, polys, height, _boxes in L.ROOMS:
        for i, poly in enumerate(polys):
            if inside(poly, x, z):
                if name == "Concourse" and i == 1:
                    return name, L.ROOM_HEIGHTS["Market"]
                return name, height
    return None


class Wall:
    """A wall of the layout in its own frame: d along it from `from`, y up, w across (its normal)."""

    def __init__(self, data: dict, shell: Shell):
        self.data, self.shell = data, shell
        self.name, self.group, self.height = data["name"], data["group"], data["height"]
        p0, p1 = Vector((data["from"][0], data["from"][1])), Vector((data["to"][0], data["to"][1]))
        self.p0, self.length = p0, (p1 - p0).length
        self.u = (p1 - p0).normalized()
        self.n = Vector((-self.u.y, self.u.x))
        self.yaw = math.atan2(-self.u.y, self.u.x)
        self.doors = [(d - w / 2, d + w / 2, h) for d, w, h in data["doors"]]
        self.windows = []
        for d, w, sill, h in data["windows"]:
            # A cut wall's stub stays closed below its windows.
            low = max(sill, STUB) if self.group == "cut" else sill
            self.windows.append((d - w / 2, d + w / 2, low, sill + h))
        # The sides that face a room, with that room's ceiling.
        self.sides = {}
        mid = p0 + self.u * (self.length / 2)
        for s in (1, -1):
            probes = [p0 + self.u * (self.length * f) + self.n * (s * 1.2) for f in (0.1, 0.5, 0.9)]
            found = [room_at(p.x, p.y) for p in probes]
            found = [f for f in found if f]
            if found:
                self.sides[s] = max(h for _r, h in found)
        del mid

    def at(self, d: float, y: float, w: float) -> tuple[float, float, float]:
        p = self.p0 + self.u * d + self.n * w
        return (p.x, y, p.y)

    def box(self, d0: float, d1: float, y0: float, y1: float, w: float, thick: float, mi: int, split: bool = True):
        """A box from d0 to d1 along the wall, y0 to y1 high, centered w across, `thick` thick: split at the stub
        on a cut wall (below it always shown, above it cut away)."""
        if d1 - d0 <= 0.001 or y1 - y0 <= 0.001:
            return
        parts = [(y0, y1, "station")]
        if self.group == "cut":
            parts = [(y0, min(y1, STUB), "station"), (max(y0, STUB), y1, "cut")] if split else [(y0, y1, "cut")]
        for a, b, group in parts:
            if b - a > 0.001:
                center = self.at((d0 + d1) / 2, (a + b) / 2, w)
                gbox(self.shell.part(group), center, (d1 - d0, b - a, thick), self.yaw, mi)

    def openings(self):
        """Every opening (d0, d1, bottom, top), along the wall."""
        return sorted([(a, b, 0.0, h) for a, b, h in self.doors] + list(self.windows))

    def solid_spans(self, y: float):
        """The spans along the wall that are solid at height y."""
        spans, t = [], 0.0
        for a, b, bottom, top in self.openings():
            if bottom <= y <= top:
                if a > t:
                    spans.append((t, a))
                t = max(t, b)
        if self.length > t:
            spans.append((t, self.length))
        return spans

    def core(self) -> None:
        t = 0.0
        for a, b, bottom, top in self.openings():
            if a > t:
                self.box(t, a, 0, self.height, 0, L.WALL, PAINT)
            self.box(a, b, 0, bottom, 0, L.WALL, PAINT)
            self.box(a, b, top, self.height, 0, L.WALL, PAINT)
            t = max(t, b)
        if self.length > t:
            self.box(t, self.length, 0, self.height, 0, L.WALL, PAINT)

    def dress(self) -> None:
        """Each side facing a room: kick plate, rail, pilasters, conduits, lamps."""
        for s, ceiling in self.sides.items():
            top = min(self.height, ceiling)
            face = s * T
            for a, b in self.solid_spans(0.2):
                self.box(a, b, 0, 0.35, face + s * 0.03, 0.06, DARK)
            for a, b in self.solid_spans(1.25):
                self.box(a, b, 1.2, 1.3, face + s * 0.04, 0.08, METAL)
            # Pilasters on the solid stretches, away from the openings' frames.
            for a, b in self.solid_spans(top * 0.5):
                usable = b - a - 1.2
                if usable < 0.5:
                    continue
                count = max(1, round(usable / RIB_STEP))
                for i in range(count + 1):
                    d = a + 0.6 + usable * i / count
                    self.box(d - 0.18, d + 0.18, 0, top, face + s * 0.11, 0.22, DARK)
                    self.box(d - 0.24, d + 0.24, top - 0.5, top - 0.2, face + s * 0.16, 0.32, DARK)
                    if self.group == "station" and i % 2 == 1 and top >= 4.0:
                        self.box(d - 0.22, d + 0.22, top - 1.9, top - 1.65, face + s * 0.28, 0.12, LAMP)
            # Conduits under the ceiling.
            for y, r, mi in ((top - 0.75, 0.09, METAL), (top - 1.0, 0.06, DARK)):
                for a, b in self.solid_spans(y):
                    if b - a < 0.4:
                        continue
                    group = "cut" if self.group == "cut" else "station"
                    p, q = self.at(a, y, face + s * 0.3), self.at(b, y, face + s * 0.3)
                    self.shell.part(group).rod(to_blender(p), to_blender(q), r, seg=10, mi=mi)

    def frames(self) -> None:
        for a, b, height in self.doors:
            wide = b - a >= 6.0
            jamb = 0.6 if wide else 0.35
            depth = L.WALL + (0.5 if wide else 0.3)
            for d0, d1 in ((a - jamb, a), (b, b + jamb)):
                self.box(d0, d1, 0, height, 0, depth, DARK)
                for s in self.sides:
                    self.box(d0 + 0.04, d1 - 0.04, 0.1, 1.3, s * (depth / 2 + 0.01), 0.02, HAZARD)
            self.box(a - jamb, b + jamb, height, height + (0.8 if wide else 0.45), 0, depth, DARK)
            if wide:
                for s in self.sides:
                    for d in (a + 0.4, b - 0.4):
                        self.box(d - 0.15, d + 0.15, height - 0.25, height - 0.05, s * (depth / 2 + 0.05), 0.1, AMBER)
            # The threshold on the floor.
            center = self.at((a + b) / 2, FLOOR_TOP + 0.004, 0)
            gbox(self.shell.part("station"), center, (b - a, 0.008, L.WALL + 0.9), self.yaw, HAZARD)
        for a, b, bottom, top in self.windows:
            sides = list(self.sides) or [1, -1]
            for s in sides:
                w = s * (T + 0.05)
                self.box(a - 0.18, a, bottom - 0.18, top + 0.18, w, 0.12, DARK)
                self.box(b, b + 0.18, bottom - 0.18, top + 0.18, w, 0.12, DARK)
                self.box(a, b, top, top + 0.18, w, 0.12, DARK)
                self.box(a - 0.1, b + 0.1, bottom - 0.18, bottom, s * (T + 0.12), 0.26, METAL)
            # Mullions on wide panes, the glass in the middle.
            count = max(1, round((b - a) / 2.6))
            for i in range(1, count):
                d = a + (b - a) * i / count
                self.box(d - 0.06, d + 0.06, bottom, top, 0, L.WALL - 0.1, DARK, split=False)
            glass = self.shell.part("glass_" + ("cut" if self.group == "cut" else "station"), "Glass")
            gbox(glass, self.at((a + b) / 2, (bottom + top) / 2, 0), (b - a, top - bottom, 0.04), self.yaw, GLASS)

    def cap(self) -> None:
        """A cut wall's stub: a heavy cap with an amber light line along its top."""
        if self.group != "cut":
            return
        t = 0.0
        spans = []
        for a, b, _h in sorted(self.doors):
            if a > t:
                spans.append((t, a))
            t = max(t, b)
        if self.length > t:
            spans.append((t, self.length))
        for a, b in spans:
            self.box(a, b, STUB, STUB + 0.12, 0, L.WALL + 0.16, DARK, split=False)
            center = self.at((a + b) / 2, STUB + 0.13, 0)
            gbox(self.shell.part("station"), center, (max(0.05, b - a - 0.3), 0.02, 0.07), self.yaw, AMBER)

    def build(self) -> None:
        self.core()
        self.dress()
        self.frames()
        self.cap()


def box_station(part: C.Part, d_center, size, mi):
    gbox(part, d_center, size, 0.0, mi)


def stub_box(x0, x1, z0, z1, y0, y1, cut: bool, shell: Shell, mi=DARK) -> None:
    """An axis-aligned box, split at the stub when it stands in the cut."""
    parts = [(y0, min(y1, STUB), "station"), (max(y0, STUB), y1, "cut")] if cut else [(y0, y1, "station")]
    for a, b, group in parts:
        if b - a > 0.001:
            gbox(shell.part(group), ((x0 + x1) / 2, (a + b) / 2, (z0 + z1) / 2), (x1 - x0, b - a, z1 - z0), 0.0, mi)


def columns(shell: Shell) -> None:
    """A heavy square column where walls end or meet (shown full height where a back wall ends there)."""
    ends: dict[tuple[float, float], list] = {}
    for wall in L.WALLS:
        for p in (wall["from"], wall["to"]):
            ends.setdefault((round(p[0], 2), round(p[1], 2)), []).append(wall)
    for (x, z), walls in ends.items():
        if any(w["name"].startswith("GalleryEnd") for w in walls) and len(walls) < 3:
            continue  # the round end's joints
        height = max(w["height"] for w in walls)
        cut = all(w["group"] == "cut" for w in walls)
        s = 0.5
        stub_box(x - s, x + s, z - s, z + s, 0, height, cut, shell)
        stub_box(x - s - 0.08, x + s + 0.08, z - s - 0.08, z + s + 0.08, 0, 0.5, False, shell, METAL)
        if cut:
            gbox(shell.part("station"), (x, STUB + 0.06, z), (1.2, 0.12, 1.2), 0.0, DARK)


def prism(part: C.Part, poly, y0: float, y1: float, mi: int) -> None:
    """A polygon (Godot x, z points) from y0 up to y1."""
    pts = [(x, -z) for x, z in poly]
    # Blender's prism wants the points counter-clockwise seen from above (+Z).
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if area < 0:
        pts = pts[::-1]
    part.prism(pts, y0, y1, mi=mi)


def fills(shell: Shell) -> None:
    """The machinery blocks: a low grated top always shown, the block above it cut away."""
    for _name, poly in L.FILLS:
        prism(shell.part("station"), poly, 0, STUB, DARK)
        prism(shell.part("station"), poly, STUB, STUB + 0.02, GRATING)
        prism(shell.part("cut"), poly, STUB, L.FILL_HEIGHT, DARK)


def floors(shell: Shell) -> None:
    """Each room's floor (one object named after it), and gratings set into them."""
    for name, _sign, polys, _height, _boxes in L.ROOMS:
        part = shell.part("station", name)
        for poly in polys:
            prism(part, poly, -0.2, FLOOR_TOP, FLOOR)
    details = shell.part("station", "FloorDetail")
    y = FLOOR_TOP + 0.003
    # The hangar: trenches along it either side of the ramp's way, a grating under the ramp's foot.
    for z in (-14.0, 14.0):
        gbox(details, (27.0, y, z), (30.0, 0.006, 1.2), 0.0, GRATING)
        for s in (-1, 1):
            gbox(details, (27.0, y + 0.001, z + s * 0.68), (30.0, 0.006, 0.12), 0.0, HAZARD)
    # The hub: a grated ring round the kiosk.
    cx, cz = L.HUB
    steps = 32
    for i in range(steps):
        a0, a1 = math.tau * i / steps, math.tau * (i + 1) / steps
        ring = [
            (cx + 3.4 * math.cos(a0), cz + 3.4 * math.sin(a0)),
            (cx + 4.6 * math.cos(a0), cz + 4.6 * math.sin(a0)),
            (cx + 4.6 * math.cos(a1), cz + 4.6 * math.sin(a1)),
            (cx + 3.4 * math.cos(a1), cz + 3.4 * math.sin(a1)),
        ]
        prism(details, ring, FLOOR_TOP, FLOOR_TOP + 0.006, GRATING)
    # The depot: a grated strip in front of the shelves along its back wall.
    gbox(details, ((L.X_HUB0 + L.X_MID) / 2, y, L.Z_BACK + 3.3), (L.X_MID - L.X_HUB0 - 2.0, 0.006, 1.0), 0.0, GRATING)
    # The gallery: a dark band along the windows of its round end and its straight walls.
    arc = L.gallery_arc()
    for i in range(len(arc) - 1):
        (ax, az), (bx, bz) = arc[i], arc[i + 1]
        inner = []
        for px, pz in ((bx, bz), (ax, az)):
            dx, dz = px - L.GALLERY_CENTER[0], pz - L.GALLERY_CENTER[1]
            k = (L.GALLERY_RADIUS - 1.6) / L.GALLERY_RADIUS
            inner.append((L.GALLERY_CENTER[0] + dx * k, L.GALLERY_CENTER[1] + dz * k))
        prism(details, [(ax, az), (bx, bz)] + inner, FLOOR_TOP, FLOOR_TOP + 0.006, GRATING)
    for z in (-L.GALLERY_RADIUS + 0.8, L.GALLERY_RADIUS - 0.8):
        gbox(
            details,
            ((L.X_HUB1 + L.GALLERY_CENTER[0]) / 2, y, z),
            (L.GALLERY_CENTER[0] - L.X_HUB1, 0.006, 1.6),
            0.0,
            GRATING,
        )


def build() -> Shell:
    shell = Shell()
    for data in L.WALLS:
        Wall(data, shell).build()
    columns(shell)
    fills(shell)
    floors(shell)
    shell.finish()
    return shell


# --- preview ---------------------------------------------------------------------------------------


def preview() -> None:
    scene = bpy.context.scene
    for name in ("Cut", "GlassCut"):
        for obj in bpy.data.collections[name].objects:
            obj.visible_camera = False
    world = bpy.data.worlds.new("World")
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.022, 0.03, 1)
    scene.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 1.5
    sun_obj = bpy.data.objects.new("Sun", sun)
    sun_obj.rotation_euler = Vector((0.3, 0.6, -0.9)).to_track_quat("-Z", "Y").to_euler()
    C.collection("Preview").objects.link(sun_obj)
    for name, _sign, _polys, height, boxes in L.ROOMS:
        for (x0, x1), (z0, z1) in boxes:
            nx, nz = max(1, round((x1 - x0) / 12)), max(1, round((z1 - z0) / 12))
            for i in range(nx):
                for j in range(nz):
                    lamp = bpy.data.lights.new("Lamp", "POINT")
                    lamp.energy = 4000 if name == "Hangar" else 1500
                    lamp.color = (1.0, 0.82, 0.6)
                    lamp.use_shadow = False
                    obj = bpy.data.objects.new("Lamp", lamp)
                    x = x0 + (x1 - x0) * (i + 0.5) / nx
                    z = z0 + (z1 - z0) * (j + 0.5) / nz
                    obj.location = to_blender((x, min(height, 8.0) - 0.5, z))
                    C.collection("Preview").objects.link(obj)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    C.collection("Preview").objects.link(cam)
    scene.camera = cam
    cam_data.sensor_fit = "VERTICAL"
    shots = {
        "iso_hub": ((62.0, 0.0, 0.0), 40.0, 30.0),
        "iso_hangar": ((28.0, 0.0, 0.0), 40.0, 30.0),
        "iso_bar": ((53.0, 0.0, 28.0), 40.0, 30.0),
        "iso_gallery": ((102.0, 0.0, 0.0), 40.0, 30.0),
        "overview": ((66.0, 0.0, 0.0), 190.0, 40.0),
    }
    pitch = math.radians(35.0)
    for tag, (target, dist, fov) in shots.items():
        cam_data.angle_y = math.radians(fov)
        eye = Vector(target) + Vector((0.0, math.sin(pitch), math.cos(pitch))) * dist
        cam.location = Vector(to_blender(eye))
        look = Vector(to_blender(target)) - cam.location
        cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(TMP / f"{tag}.png")
        bpy.ops.render.render(write_still=True)


for coll in GROUPS.values():
    bpy.context.scene.collection.children.link(bpy.data.collections.new(coll))
build()
for group, coll in GROUPS.items():
    C.export_glb(OUT / f"{'shell_' if not group.startswith('glass') else ''}{group}.glb", coll)
    print(group, C.stats(coll))
if "preview" in ARGV:
    TMP.mkdir(parents=True, exist_ok=True)
    preview()
