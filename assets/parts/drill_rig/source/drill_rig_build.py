"""Frost fields point of interest: a deep-core drill rig frozen in. A lattice derrick on a sled base, tilted a few
degrees toward its iced side, thick ice sheets and icicles built up on the side the wind comes from, the drill string
frozen into the bore; a rack of drill pipes with some spilled, and the frozen-over overflow at the rig's foot.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/drill_rig/source/drill_rig_build.py wip r1                     # pieces + layout
    tools/blender.sh assets/parts/drill_rig/source/drill_rig_build.py wip r1 Rig_tower,layout
    tools/blender.sh assets/parts/drill_rig/source/drill_rig_build.py final

Everything it writes goes to tmp/assets/parts/drill_rig/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: a piece name, pieces, layout, sheet, save); "final" renders every piece (iso + hero), the
part's layout from the game's angle (both sides), writes the contact sheet sheet.png and saves the procedural
drill_rig_procedural.blend that drill_rig_bake.py turns into the game asset. In the .blend the pieces stand in a row
along X (no AO from a neighbor in the bake); the bake zeroes their locations for the export.

Game contract (game/locations/parts/, ModelParts): every piece is ONE mesh object at the kit's root (no parent),
named as in PIECES, origin at its ground contact (bottom center, z = 0), front toward -Y, with geometry reaching
below z = 0 so it never floats on uneven ground. Budgets (TBD (playtest)): the tower <= ~8k triangles, the rack
<= ~3k, the ice mound <= ~1.5k.

Look: the colony's equipment (dark gunmetal frames and machinery, a bone-white power enclosure, faded amber hazard
stripes, chipped paint, rust streaks, grime and dust low down) with the Frost fields' ice on it: the ice is the
Frost kit's own material (assets/biomes/frost/source/frost_build.py, loaded without running it), so the rig's ice
matches the ice blocks around it. Top-facing surfaces stay fairly clean: the game lays the biome's snow on them.
The only glow is the red beacon lens on the crown block.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "drill_rig"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
# The frost kit's build: its materials and shape helpers, so the part matches the biome's own pieces.
sys.path.insert(0, str(ROOT / "assets" / "biomes" / "frost" / "source"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import colony_part as P
import common as C
import frost_build as FROST
from colony_part import Mat, cut_below, join, mat_dark, srgb, stripes, transform_bm
from common import T, rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["pieces", "layout"]

ASSET = "DrillRig"
PIECES = ["Rig_tower", "Rig_pipe_rack", "Rig_ice"]
BAKE_GAP = 4.0  # m between the pieces in the saved .blend's row
SINK = 0.45  # geometry kept below z = 0 (m)
TILT = 4.0  # the tower leans this many degrees toward +X (its iced side)
SHARP_DEG = 32.0  # ice: edges sharper than this split the shading

# Approximate linear albedo of the frost ground (frost_build.py's GROUND: blue-grey snow).
GROUND = ((0.16, 0.185, 0.225), (0.25, 0.28, 0.33))
FOOTPRINT = 12.0
PROP_RADIUS = 8.0


# The colony's look (shared with the other parts kits): paint, markings, weathering.
BONE = srgb(0.47, 0.46, 0.43)
OLIVE = srgb(0.30, 0.31, 0.27)
GUNMETAL = srgb(0.16, 0.16, 0.17)
HAZARD = srgb(0.70, 0.48, 0.14)
STRIPE_DARK = srgb(0.1, 0.1, 0.1)
DUST = srgb(0.36, 0.34, 0.31)
RUST = srgb(0.3, 0.17, 0.09)
STEEL = srgb(0.5, 0.5, 0.5)
GRIME = srgb(0.1, 0.09, 0.08)
LAMP_RED = (1.0, 0.07, 0.035)
LAMP_STRENGTH = 6.0  # the bake's emission_strength: the lens bakes to its full color


# --- materials ------------------------------------------------------------------------------------------


def mat_paint(
    name: str,
    color,
    wear: float = 1.0,
    rust: float = 1.0,
    dust: float = 1.0,
    hazard: bool = False,
    roughness: float = 0.58,
) -> bpy.types.Material:
    """The colony's weathered paint on steel: a large, low-contrast tone drift, grime in the recesses, rust streaks
    running down the vertical faces, grey-brown dust on the lower part and on ledges, paint chipped to bare steel on
    the edges. hazard: faded amber / dark diagonal bands instead of the plain color."""
    m = Mat(name)
    big = m.noise(0.45, 3.0, 0.5)
    mid = m.noise(2.2, 4.0, 0.55)
    if hazard:
        col = m.mix(stripes(m), STRIPE_DARK, HAZARD)
    else:
        rgb = m.nt.nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*color, 1.0)
        col = rgb.outputs[0]
    col = m.scale(col, m.math("MULTIPLY_ADD", big, 0.18, 0.91))
    cav = m.cavity(0.3)
    col = m.mix(m.math("MULTIPLY", cav, 0.7), col, GRIME)
    # Rust streaks: noise stretched along Z (thin vertical runs), in patches, only on the steep faces.
    streak = m.ramp(0.56, 0.7, m.noise(7.0, 3.0, 0.5, stretch=(1.0, 1.0, 0.12)))
    patch = m.ramp(0.45, 0.7, m.noise(1.1, 3.0, 0.5))
    steep = m.ramp(0.0, 0.5, m.math("SUBTRACT", 1.0, m.math("ABSOLUTE", m.nz)))
    run = m.math("MULTIPLY", m.math("MULTIPLY", streak, patch), m.math("MULTIPLY", steep, 0.5 * rust))
    col = m.mix(run, col, RUST)
    # Dust: low down (lower 1.5 m) and on ledges, broken up.
    ledge = m.math("MULTIPLY", m.ramp(0.75, 0.95, m.nz), 0.25)
    low = m.math("MULTIPLY", m.low(0.1, 1.6), 0.55)
    dust_m = m.math("MULTIPLY", m.math("ADD", low, ledge), m.ramp(0.3, 0.62, mid))
    dust_m = m.math("MULTIPLY", dust_m, dust, clamp=True)
    col = m.mix(dust_m, col, DUST)
    # Edge wear: paint chipped to steel on the convex edges, broken up.
    edge = m.ramp(0.03, 0.12, C._bevel_edge(m.nt, 0.025, m.geo))
    wear_m = m.math("MULTIPLY", m.math("MULTIPLY", edge, m.ramp(0.42, 0.6, m.noise(6.0, 3.0, 0.6))), wear, clamp=True)
    col = m.mix(wear_m, col, STEEL)
    rough = m.mixf(mid, roughness - 0.07, roughness + 0.07)
    rough = m.mixf(m.math("MULTIPLY", cav, 0.7), rough, 0.8)
    rough = m.mixf(dust_m, rough, 0.88)
    rough = m.mixf(wear_m, rough, 0.38)
    height = m.math("ADD", m.math("MULTIPLY", m.noise(40.0, 3.0, 0.5), 0.15), m.math("MULTIPLY", wear_m, -0.3))
    return m.out(col, rough, wear_m, height, 0.25, 0.01)


# --- mesh helpers ---------------------------------------------------------------------------------------


class Ice:
    """Ice in one bmesh (the Frost kit's ice material): convex sheets and lumps (the Frost kit's hulls) and
    icicles; finish() gives every face a random "facet" tone like the kit's ice blocks."""

    def __init__(self, name: str, seed: int):
        self.name = name
        self.bm = bmesh.new()
        self.rnd = random.Random(seed)

    def add(self, src: bmesh.types.BMesh) -> None:
        vmap = {v: self.bm.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            self.bm.faces.new([vmap[v] for v in f.verts])
        src.free()

    def blob(self, center, size, rot: Matrix | None = None, n: int = 14) -> None:
        """A rounded lump of rime: the hull of jittered points on an ellipsoid of `size` (full extents)."""
        pts = []
        for i in range(n):
            z = 1 - 2 * (i + 0.5) / n
            a = i * 2.39996 + self.rnd.uniform(-0.3, 0.3)
            r = math.sqrt(1 - z * z)
            j = self.rnd.uniform(0.85, 1.1)
            pts.append(Vector((math.cos(a) * r * size[0] / 2, math.sin(a) * r * size[1] / 2, z * size[2] / 2)) * j)
        bm = FROST.hull(pts)
        transform_bm(bm, T(center, rot or rz(self.rnd.uniform(0, 360))))
        self.add(bm)

    def mound(
        self, center, radius: float, height: float, stretch=(1.0, 1.0), turn: float = 0.0, seg: int = 28, rings: int = 7
    ) -> None:
        """A smooth, low mound of frozen overflow: a lobed outline, a domed top with faint flow terraces, a rounded
        edge meeting the ground, a skirt reaching SINK below it (a polar grid of rings x seg)."""
        rnd = self.rnd
        ph = [rnd.uniform(0, math.tau) for _ in range(4)]
        c = Vector(center)
        rot = rz(turn)

        def edge(a: float) -> float:
            return radius * (
                1 + 0.2 * math.sin(3 * a + ph[0]) + 0.1 * math.sin(5 * a + ph[1]) + 0.05 * math.sin(9 * a + ph[2])
            )

        def at(a: float, t: float, z: float) -> Vector:
            r = edge(a) * t
            return c + rot @ Vector((math.cos(a) * r * stretch[0], math.sin(a) * r * stretch[1], z))

        top = self.bm.verts.new(c + Vector((0, 0, height)))
        grid = []
        for i in range(1, rings + 1):
            t = i / rings
            row = []
            for k in range(seg):
                a = k / seg * math.tau
                z = height * (1 - t**2.4) ** 0.65
                z += 0.035 * height * math.sin(t * 14 + 2 * math.sin(a * 2 + ph[3]))  # flow terraces
                row.append(self.bm.verts.new(at(a, t, max(z, 0.015))))
            grid.append(row)
        grid.append([self.bm.verts.new(at(k / seg * math.tau, 1.04, -SINK)) for k in range(seg)])
        for k in range(seg):
            self.bm.faces.new((top, grid[0][k], grid[0][(k + 1) % seg]))
        for ra, rb in itertools.pairwise(grid):
            for k in range(seg):
                self.bm.faces.new((ra[k], rb[k], rb[(k + 1) % seg], ra[(k + 1) % seg]))

    def sheet(self, top_a, top_b, drop: float, thick: float, normal) -> None:
        """A sheet of ice hanging from the line top_a..top_b, `drop` m down, ragged at its bottom, `thick` m thick
        toward `normal` (it grows on the windward side of what it hangs from)."""
        a, b, n = Vector(top_a), Vector(top_b), Vector(normal).normalized()
        pts = []
        for i in range(6):
            t = i / 5
            p = a.lerp(b, t)
            d = drop * self.rnd.uniform(0.45, 1.0) * (0.55 + 0.45 * math.sin(t * math.pi))
            for side in (-0.3, 1.0):
                th = thick * self.rnd.uniform(0.6, 1.0) * side
                pts.append(p + n * th + Vector((0, 0, 0.06)))
                pts.append(p + n * th * 0.5 - Vector((0, 0, d)))
        self.add(FROST.hull(pts))

    def icicle(self, top, length: float, r: float) -> None:
        top = Vector(top)
        verts = bmesh.ops.create_cone(
            self.bm,
            cap_ends=True,
            cap_tris=False,
            segments=5,
            radius1=r,
            radius2=0.0,
            depth=length,
            matrix=T(top - Vector((0, 0, length / 2)), rx(180) @ rz(self.rnd.uniform(0, 72))),
        )["verts"]
        lean = Vector((self.rnd.uniform(-0.04, 0.04), self.rnd.uniform(-0.04, 0.04), 0))
        for v in verts:
            v.co += lean * (top.z - v.co.z)

    def icicles(self, a, b, count: int, length=(0.25, 0.9), r=(0.04, 0.09)) -> None:
        """A row of icicles hanging from the line a..b."""
        a, b = Vector(a), Vector(b)
        for i in range(count):
            t = (i + self.rnd.uniform(0.2, 0.8)) / count
            ln = self.rnd.uniform(*length)
            self.icicle(a.lerp(b, t) + Vector((0, 0, 0.02)), ln, self.rnd.uniform(*r) * (0.6 + 0.5 * ln))

    def finish(self, m: Matrix | None = None) -> bpy.types.Object:
        if m is not None:
            transform_bm(self.bm, m)
        cut_below(self.bm, -SINK)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        limit = math.radians(SHARP_DEG)
        for e in self.bm.edges:
            e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit)
        for f in self.bm.faces:
            f.smooth = True
            f.material_index = 0
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        attr = me.attributes.new("facet", "FLOAT", "FACE")
        attr.data.foreach_set("value", [self.rnd.random() for _ in me.polygons])
        me.materials.append(MATS["ice"])
        obj = bpy.data.objects.new(self.name, me)
        C.link(obj)
        return obj


def part(name: str, bevel=(0.02, 1)) -> C.Part:
    """A Part over the kit's material list (index constants below)."""
    return C.Part(name, MAT_LIST, bevel)


FRAME, HAZ, PANEL, PIPE, LAMP, DARK, CARGO = range(7)


def finish_part(p: C.Part, m: Matrix | None = None, cut: float | None = -SINK) -> bpy.types.Object:
    if m is not None:
        transform_bm(p.bm, m)
    if cut is not None:
        cut_below(p.bm, cut)
    return p.finish(None)


# --- pieces ---------------------------------------------------------------------------------------------

# Derrick: legs from the deck to the crown, girts at these heights, the crown block on top.
DECK_Z = 0.56
DERRICK_X = 0.95  # center of the derrick (and the bore) on the sled
BASE_HALF = 1.2
TOP_HALF = 0.42
TOP_Z = 9.0
LEVELS = [DECK_Z, 2.0, 3.4, 4.75, 6.05, 7.3, 8.3, TOP_Z]


def leg_point(sx: float, sy: float, z: float) -> Vector:
    """Point on the derrick's corner leg (sx, sy = +-1) at height z."""
    t = (z - DECK_Z) / (TOP_Z - DECK_Z)
    h = BASE_HALF + (TOP_HALF - BASE_HALF) * t
    return Vector((DERRICK_X + sx * h, sy * h, z))


def tilt_matrix() -> Matrix:
    """The tower's lean: TILT degrees toward +X around the -X runner's bottom end, so that end stays on the ground
    and the +X end sinks in."""
    pivot = Vector((-2.3, 0, 0))
    return Matrix.Translation(pivot) @ ry(TILT).to_4x4() @ Matrix.Translation(-pivot)


def sled(p: C.Part) -> None:
    """Sled base, 5.2 x 4 m: two runners with upturned ends (reaching below ground), cross-members, the deck and its
    hazard-striped kick plates."""
    prof = [
        (-2.25, -0.7), (2.25, -0.7), (2.25, 0.0), (2.62, 0.34), (2.62, 0.5), (2.3, 0.42),
        (-2.3, 0.42), (-2.62, 0.5), (-2.62, 0.34), (-2.25, 0.0),
    ]  # fmt: skip
    for y in (-1.6, 1.6):
        p.prism(prof, -0.17, 0.17, T((0, y, 0), rx(90)), mi=FRAME)
    for x in (-1.9, -0.95, 0.0, 0.95, 1.9):
        p.box((x, 0, 0.36), (0.2, 3.5, 0.16), mi=FRAME)
    p.box((0, 0, DECK_Z - 0.06), (5.0, 3.7, 0.12), mi=FRAME)
    p.box((0, -1.86, DECK_Z), (5.0, 0.05, 0.2), mi=HAZ)
    p.box((2.5, 0, DECK_Z), (0.05, 3.72, 0.2), mi=HAZ)
    p.box((-2.5, 0, DECK_Z), (0.05, 3.72, 0.2), mi=FRAME)
    p.box((0, 1.86, DECK_Z), (5.0, 0.05, 0.2), mi=FRAME)
    # Tow eyes on the runners' ends.
    for x in (-2.55, 2.55):
        for y in (-1.6, 1.6):
            p.cyl((x, y, 0.62), 0.11, 0.08, 8, rot=rx(90), mi=FRAME)


def machinery(p: C.Part) -> None:
    """On the deck's -X end: the drawworks (cable drum between flanges on a frame) and the power unit in a
    bone-white enclosure with louvres, an exhaust stack and a stenciled number and arrow."""
    # Drawworks.
    p.box((-0.75, 0, DECK_Z + 0.2), (0.95, 2.3, 0.4), mi=FRAME)
    p.cyl((-0.75, 0, DECK_Z + 0.85), 0.36, 1.7, 14, rot=rx(90), mi=PIPE)
    for y in (-0.9, 0.9):
        p.cyl((-0.75, y, DECK_Z + 0.85), 0.55, 0.1, 16, rot=rx(90), mi=FRAME)
        p.box((-0.75, y * 1.08, DECK_Z + 0.55), (0.8, 0.12, 0.75), mi=FRAME)
    # Power unit enclosure.
    cx, w, d, h = -1.85, 1.15, 2.9, 1.65
    z0 = DECK_Z
    p.box((cx, 0, z0 + h / 2), (w, d, h), mi=PANEL)
    p.box((cx, 0, z0 + h + 0.05), (w + 0.1, d + 0.1, 0.1), mi=FRAME)  # roof rim
    for y in (-0.95, 0.0, 0.95):  # panel seams as shallow ribs
        p.box((cx, y, z0 + h / 2), (w + 0.04, 0.05, h - 0.1), mi=PANEL)
    for i in range(4):  # louvres on the -Y end
        p.box((cx, -d / 2 - 0.02, z0 + 0.45 + i * 0.16), (0.7, 0.05, 0.07), rot=rx(-30), mi=FRAME)
    p.box((cx, -d / 2 + 0.005, z0 + 0.69), (0.74, 0.02, 0.6), mi=DARK)
    p.box((cx + w / 2 + 0.005, 0.6, z0 + 0.75), (0.02, 0.9, 1.25), mi=FRAME)  # access door on the +X side
    p.box((cx + w / 2 + 0.03, 0.22, z0 + 0.8), (0.04, 0.05, 0.22), mi=FRAME)  # its handle
    # Stencil on the -X side: a number (bars) and an arrow.
    sx = cx - w / 2 - 0.004
    for i, hgt in enumerate((0.34, 0.34, 0.2, 0.34)):
        p.box((sx, -0.75 + i * 0.16, z0 + 1.05 + (0.34 - hgt) / 2), (0.01, 0.07, hgt), mi=FRAME)
    arrow = [(-0.3, -0.06), (0.1, -0.06), (0.1, -0.16), (0.3, 0.0), (0.1, 0.16), (0.1, 0.06), (-0.3, 0.06)]
    p.prism(arrow, -0.005, 0.005, T((sx, 0.45, z0 + 1.2), rz(90) @ ry(90) @ rz(90)), mi=HAZ)
    # Hazard band along the enclosure's foot, the exhaust stack.
    p.box((cx, 0, z0 + 0.09), (w + 0.03, d + 0.03, 0.18), mi=HAZ)
    p.cyl((cx + 0.25, 0.9, z0 + h + 0.7), 0.1, 1.4, 10, mi=PIPE)
    p.cyl((cx + 0.25, 0.9, z0 + h + 1.45), 0.16, 0.08, 10, mi=FRAME)


def derrick(lat: C.Part, p: C.Part) -> None:
    """The lattice derrick (lat: no bevel, thin members), the crown block, the monkey board, the ladder, the drill
    string with its travelling block, and the rotary table (p)."""
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in corners:
        lat.beam(leg_point(sx, sy, DECK_Z - 0.05), leg_point(sx, sy, TOP_Z + 0.05), 0.24, 0.24, (sx, -sy, 0), FRAME)
        p.box(leg_point(sx, sy, DECK_Z + 0.06), (0.5, 0.5, 0.12), mi=FRAME)  # foot plates
    for i, z in enumerate(LEVELS[1:], 1):
        for k in range(4):
            a, b = corners[k], corners[(k + 1) % 4]
            pa, pb = leg_point(*a, z), leg_point(*b, z)
            lat.beam(pa, pb, 0.13, 0.13, (0, 0, 1), FRAME)
            # Zigzag bracing in the bay below, alternating per level and face.
            z0 = LEVELS[i - 1]
            if (i + k) % 2:
                lat.beam(leg_point(*a, z0), pb, 0.1, 0.1, (0, 0, 1), FRAME)
            else:
                lat.beam(leg_point(*b, z0), pa, 0.1, 0.1, (0, 0, 1), FRAME)
    # Crown block, its sheave and the beacon.
    p.box((DERRICK_X, 0, TOP_Z + 0.25), (1.3, 1.3, 0.5), mi=FRAME)
    p.box((DERRICK_X, 0, TOP_Z + 0.53), (1.36, 1.36, 0.06), mi=HAZ)
    p.cyl((DERRICK_X, 0, TOP_Z + 0.75), 0.42, 0.28, 14, rot=ry(90), mi=PIPE)
    p.box((DERRICK_X, 0, TOP_Z + 0.65), (0.5, 0.5, 0.3), mi=FRAME)
    p.cyl((DERRICK_X - 0.5, 0.5, TOP_Z + 0.75), 0.03, 0.4, 6, mi=FRAME)
    p.cyl((DERRICK_X - 0.5, 0.5, TOP_Z + 1.0), 0.09, 0.12, 10, mi=FRAME)
    p.cyl((DERRICK_X - 0.5, 0.5, TOP_Z + 1.12), 0.075, 0.13, 10, mi=LAMP)
    # Monkey board: a small platform with a rail on the -Y face.
    zb = 6.6
    fy = leg_point(1, -1, zb).y
    p.box((DERRICK_X, fy - 0.45, zb), (1.5, 0.9, 0.08), mi=FRAME)
    for x in (-0.72, 0.72):
        lat.beam((DERRICK_X + x, fy - 0.88, zb), (DERRICK_X + x, fy - 0.88, zb + 1.0), 0.06, 0.06, (1, 0, 0), FRAME)
        lat.beam((DERRICK_X + x, fy - 0.88, zb + 1.0), (DERRICK_X + x, fy, zb + 1.0), 0.06, 0.06, (0, 0, 1), FRAME)
    lat.beam(
        (DERRICK_X - 0.75, fy - 0.88, zb + 1.0), (DERRICK_X + 0.75, fy - 0.88, zb + 1.0), 0.06, 0.06, (0, 0, 1), HAZ
    )
    # Ladder up the -Y face to the board.
    zl = DECK_Z
    for x in (-0.22, 0.22):
        a = leg_point(0, -1, zl) + Vector((x, -0.18, 0))
        b = leg_point(0, -1, zb) + Vector((x, -0.18, 0))
        lat.beam(a, b, 0.05, 0.05, (1, 0, 0), FRAME)
    n = 11
    for i in range(1, n):
        z = zl + (zb - zl) * i / n
        a = leg_point(0, -1, z) + Vector((-0.22, -0.18, 0))
        lat.beam(a, a + Vector((0.44, 0, 0)), 0.035, 0.035, (0, 0, 1), FRAME)
    # Drill string: through the rotary table into the bore, the travelling block hanging on its cable.
    p.cyl((DERRICK_X, 0, (6.4 - 0.7) / 2), 0.1, 6.4 + 0.7, 10, mi=PIPE)
    p.box((DERRICK_X, 0, 6.85), (0.55, 0.42, 1.0), mi=FRAME)
    p.box((DERRICK_X, 0, 6.45), (0.6, 0.47, 0.12), mi=HAZ)
    p.cyl((DERRICK_X, 0, 6.3), 0.16, 0.25, 10, mi=PIPE)  # tool joint under the block
    for x in (-0.12, 0.12):
        lat.beam((DERRICK_X + x, 0, 7.35), (DERRICK_X + x, 0, TOP_Z + 0.02), 0.04, 0.04, (1, 0, 0), PIPE)
    p.cyl((DERRICK_X, 0, DECK_Z + 0.12), 0.62, 0.24, 18, mi=FRAME)  # rotary table
    p.cyl((DERRICK_X, 0, DECK_Z + 0.25), 0.3, 0.06, 12, mi=DARK)


def tower_ice(ice: Ice) -> None:
    """The windward (+X) side iced over: thick coats on the two +X legs, sheets hanging from the +X girts, rime
    on the crown, icicles from the girts, the board and the deck edge, the drill string frozen into the table and a
    bank of ice burying the sled's +X end."""
    rnd = ice.rnd
    for sy in (-1, 1):
        for i in range(len(LEVELS) - 1):
            z0, z1 = LEVELS[i], LEVELS[i + 1]
            a, b = leg_point(1, sy, z0), leg_point(1, sy, z1)
            th = 0.36 - 0.035 * i
            pts = []
            for p0 in (a, b):
                for k in range(5):
                    ang = k / 5 * math.tau + rnd.uniform(-0.3, 0.3)
                    off = Vector((math.cos(ang) * th * 0.7 + th * 0.5, math.sin(ang) * th * 0.65, 0))
                    pts.append(p0 + off + Vector((0, 0, rnd.uniform(-0.1, 0.1))))
            ice.add(FROST.hull(pts))
    n = Vector((1, 0, 0.13)).normalized()
    for i, z in enumerate(LEVELS[1:-1], 1):
        a, b = leg_point(1, -1, z), leg_point(1, 1, z)
        if i < 5:
            ice.sheet(a + Vector((0.08, 0.15, 0)), b + Vector((0.08, -0.15, 0)), rnd.uniform(0.6, 1.1), 0.22, n)
        ice.icicles(a + Vector((0.2, 0.2, -0.2)), b + Vector((0.2, -0.2, -0.2)), 6, (0.35, 1.1 - 0.08 * i))
        # Rime along the -Y and +Y face girts' windward ends.
        for sy in (-1, 1):
            c = leg_point(1, sy, z) + Vector((0, -sy * 0.45, 0.02))
            ice.blob(c, (0.75, 0.3, 0.24), rz(rnd.uniform(-10, 10)), n=10)
    ice.blob(Vector((DERRICK_X + 0.62, 0, TOP_Z + 0.3)), (0.45, 1.45, 0.55), rz(4))
    ice.icicles((DERRICK_X + 0.7, -0.6, TOP_Z), (DERRICK_X + 0.7, 0.6, TOP_Z), 4, (0.3, 0.7))
    zb = 6.6
    fy = leg_point(1, -1, zb).y
    ice.icicles((DERRICK_X + 0.2, fy - 0.88, zb - 0.05), (DERRICK_X + 0.75, fy - 0.88, zb - 0.05), 3, (0.25, 0.6))
    ice.icicles((2.55, -1.8, DECK_Z - 0.05), (2.55, 1.8, DECK_Z - 0.05), 9, (0.2, 0.55))
    # The drill string frozen into the rotary table: a collar of ice and a frozen drool down the pipe.
    for k in range(4):
        ang = k / 4 * math.tau + 0.4
        ice.blob(Vector((DERRICK_X + math.cos(ang) * 0.3, math.sin(ang) * 0.3, DECK_Z + 0.3)), (0.6, 0.5, 0.32), n=10)
    ice.add(FROST.hull([Vector((DERRICK_X + dx, dy, z)) for dx, dy, z in (
        (0.13, -0.08, DECK_Z + 0.3), (0.16, 0.06, DECK_Z + 0.3), (0.0, 0.14, DECK_Z + 0.3), (-0.12, 0.0, DECK_Z + 0.3),
        (0.12, 0.0, DECK_Z + 1.6), (0.03, 0.1, DECK_Z + 1.3), (0.12, -0.06, DECK_Z + 1.9),
    )]))  # fmt: skip
    # A bank of ice over the sled's +X end, in lobes, under the deck edge's icicles.
    ice.mound(Vector((2.7, 0.0, 0.0)), 1.25, 0.8, stretch=(0.85, 1.75))


def rig_tower() -> bpy.types.Object:
    """Rig_tower: the derrick (9.8 m to the beacon) on its 5.2 x 4 m sled, leaning TILT degrees toward its iced
    +X side; the -X runner's end on the ground, the +X end sunk in under a bank of ice."""
    m = tilt_matrix()
    p = part("Rig_tower_body")
    sled(p)
    machinery(p)
    lat = part("Rig_tower_lattice", bevel=None)
    derrick(lat, p)
    ice = Ice("Rig_tower_ice", 11)
    tower_ice(ice)
    objs = [finish_part(p, m), finish_part(lat, m), ice.finish(m)]
    obj = join("Rig_tower", objs)
    return obj


def rig_pipe_rack() -> bpy.types.Object:
    """Rig_pipe_rack: two trestles with end posts holding a stack of drill pipes (6.2 m, tool joints at the ends);
    three pipes spilled on the ground beside it, one leaning on the rack; icicles under the rack's beams and rime on
    the pipes' windward ends."""
    p = part("Rig_pipe_rack_body")
    pipes = part("Rig_pipe_rack_pipes", bevel=None)
    rnd = random.Random(21)
    for x in (-2.1, 2.1):  # trestles: a beam on two A-frames, posts at the ends
        p.box((x, 0, 0.82), (0.22, 2.6, 0.16), mi=FRAME)
        for y in (-1.15, 1.15):
            for dx in (-0.35, 0.35):
                p.beam((x + dx, y, -SINK), (x, y, 0.76), 0.1, 0.1, (0, 1, 0), FRAME)
            p.box((x, y, -0.1), (0.9, 0.14, 0.12), mi=FRAME)
        for y in (-1.25, 1.25):
            p.box((x, y, 1.15), (0.14, 0.14, 0.75), mi=HAZ)
    r, gap = 0.09, 0.205
    rows = [(6, 0.0), (5, 0.5), (4, 1.0)]
    for row, (count, shift) in enumerate(rows):
        for i in range(count):
            if row == 2 and i == 3:
                continue  # one missing from the top row: that's one of the spilled ones
            y = (i - (count - 1) / 2) * gap
            z = 0.9 + r + row * gap * 0.87
            x0 = rnd.uniform(-0.12, 0.12) + shift * 0.1
            drill_pipe(pipes, Vector((x0 - 3.1, y, z)), Vector((x0 + 3.1, y, z)), r)
    # Spilled pipes.
    drill_pipe(pipes, Vector((-2.7, -1.75, 0.09)), Vector((3.3, -2.35, 0.09)), r)
    drill_pipe(pipes, Vector((-1.6, -2.15, 0.09)), Vector((4.0, -3.0, 0.09)), r)
    drill_pipe(pipes, Vector((3.6, 1.6, 0.09)), Vector((-1.4, 1.38, 1.25)), r)  # leaning on the stack
    p_obj = finish_part(p, cut=-SINK)
    pipes_obj = finish_part(pipes, cut=-SINK)
    ice = Ice("Rig_pipe_rack_ice", 23)
    for x in (-2.1, 2.1):
        ice.icicles((x + 0.12, -1.0, 0.74), (x + 0.12, 1.0, 0.74), 5, (0.15, 0.4), (0.03, 0.06))
    for i in range(5):  # rime on the windward (+X) ends of the stack
        ice.blob(Vector((3.0, (i - 2) * 0.24, 1.0 + rnd.uniform(0, 0.35))), (0.45, 0.3, 0.26), n=10)
    ice.icicles((3.0, -0.6, 0.95), (3.0, 0.6, 0.95), 4, (0.2, 0.45), (0.03, 0.06))
    return join("Rig_pipe_rack", [p_obj, pipes_obj, ice.finish()])


def drill_pipe(p: C.Part, a: Vector, b: Vector, r: float) -> None:
    """A drill pipe from a to b: the tube (open: its ends hide in the joints) and a thicker tool joint at each end."""
    d = (b - a).normalized()
    p.cyl((a + b) / 2, r, (b - a).length - 0.7, 8, rot=C.basis(d, Vector((0, 0, 1))), mi=PIPE, caps=False)
    p.rod(a, a + d * 0.38, r * 1.35, 8, mi=PIPE)
    p.rod(b - d * 0.38, b, r * 1.35, 8, mi=PIPE)


def rig_ice() -> bpy.types.Object:
    """Rig_ice: the bore's overflow at the rig's foot frozen over, a low mound of ice in lobes (0.55 m) around a
    casing stub with its flange and a frozen valve wheel (0.95 m); a broken pipe stub poking out of a lobe."""
    p = part("Rig_ice_body")
    p.cyl((0, 0, (0.95 - SINK) / 2), 0.24, 0.95 + SINK, 14, mi=PIPE)
    p.cyl((0, 0, 0.92), 0.36, 0.1, 16, mi=FRAME)
    p.box((0, 0, 1.03), (0.26, 0.26, 0.14), mi=FRAME)
    p.cyl((0, 0, 1.15), 0.05, 0.12, 8, mi=PIPE)
    p.cyl((0, 0, 1.22), 0.24, 0.05, 14, mi=HAZ)  # valve wheel
    # A side outlet with a broken-off line, and a pipe stub frozen in the overflow.
    p.rod((0.2, 0, 0.62), (0.85, -0.05, 0.6), 0.08, 10, mi=PIPE)
    p.cyl((0.88, -0.05, 0.6), 0.14, 0.07, 12, rot=ry(90), mi=FRAME)
    p.rod((1.2, 0.7, 0.05), (1.75, 1.0, 0.42), 0.09, 8, mi=PIPE)
    body = finish_part(p, cut=-SINK)
    ice = Ice("Rig_ice_ice", 31)
    ice.mound(Vector((0.15, 0, 0)), 1.35, 0.5, stretch=(1.25, 0.95), turn=8, seg=24, rings=6)
    ice.mound(Vector((1.25, 0.55, 0)), 0.85, 0.24, stretch=(1.3, 0.9), turn=30, seg=16, rings=4)
    ice.mound(Vector((-0.6, -0.9, 0)), 0.7, 0.2, stretch=(1.2, 0.8), turn=-40, seg=16, rings=4)
    ice.blob(Vector((0, 0, 0.55)), (0.75, 0.7, 0.35), n=12)  # the collar frozen around the casing
    ice.icicles((0.5, -0.1, 0.55), (0.8, -0.05, 0.55), 3, (0.12, 0.3), (0.03, 0.05))
    return join("Rig_ice", [body, ice.finish()])


BUILDERS = {"Rig_tower": rig_tower, "Rig_pipe_rack": rig_pipe_rack, "Rig_ice": rig_ice}


# --- layout, preview, renders ---------------------------------------------------------------------------

# The part's layout (Blender: x, y, z rotation in degrees; the way into the area is +Y). Crate and ore spots are
# markers the game places (crate 1.2 x 0.8 m).
LAYOUT = {
    "Rig_tower": (0.2, 0.6, 0),
    "Rig_ice": (3.6, -0.2, 20),
    "Rig_pipe_rack": (-0.8, -3.6, 0),
}
CRATE = (-4.4, 2.6, 75)
ORE_SPOTS = [(5.4, -4.9), (-5.9, -1.4), (3.4, 5.6)]
POLE = (1.9, -2.6)


# --- main -----------------------------------------------------------------------------------------------


def build() -> None:
    global MATS, MAT_LIST
    MATS = {
        "frame": mat_paint("RigFrame", GUNMETAL, wear=1.0),
        "hazard": mat_paint("RigHazard", HAZARD, hazard=True, wear=1.2),
        "panel": mat_paint("RigPanel", BONE, wear=0.8, rust=1.2),
        "pipe": mat_paint("RigPipe", srgb(0.2, 0.19, 0.18), wear=0.6, rust=1.6, roughness=0.5),
        "lamp": C.mat_emissive("RigLamp", LAMP_RED, LAMP_STRENGTH),
        "dark": mat_dark("RigDark"),
        "cargo": mat_paint("RigCargo", OLIVE),
        "ice": FROST.mat_ice(),
    }
    MAT_LIST = [MATS[k] for k in ("frame", "hazard", "panel", "pipe", "lamp", "dark", "cargo")]
    for name in PIECES:
        obj = BUILDERS[name]()
        assert obj.name == name, obj.name


KIT = P.PartKit(
    pieces=PIECES,
    layout=LAYOUT,
    out=OUT,
    ground=GROUND,
    bake_gap=BAKE_GAP,
    footprint=FOOTPRINT,
    prop_radius=PROP_RADIUS,
    crate=CRATE,
    ore_spots=ORE_SPOTS,
    pole=POLE,
)


def main() -> None:
    C.reset(ASSET)
    build()
    P.report(KIT)
    P.setup_preview(KIT)
    if MODE == "final":
        sheet = []
        for name in PIECES:
            sheet += P.render_piece(KIT, name, "final_", ("iso", "hero"), 48, 768)
        sheet.append(P.render_layout(KIT, OUT / "final_layout_a.png", "a", 64, 1024))
        sheet.append(P.render_layout(KIT, OUT / "final_layout_b.png", "b", 64, 1024))
        C.contact_sheet(sheet, OUT / "sheet.png", cols=4, tile=512, background=0.02)
        P.apply_bake_layout(KIT)
        C.save_blend(OUT / "drill_rig_procedural.blend")
        return
    wip = OUT / "wip"
    out = []
    for view in VIEWS:
        if view == "pieces":
            for name in PIECES:
                out += P.render_piece(KIT, name, f"wip/{TAG}_", ("iso", "hero"), 20, 640)
        elif view in BUILDERS:
            out += P.render_piece(KIT, view, f"wip/{TAG}_", ("iso", "hero"), 24, 768)
        elif view == "layout":
            out.append(P.render_layout(KIT, wip / f"{TAG}_layout_a.png", "a", 32, 1024))
            out.append(P.render_layout(KIT, wip / f"{TAG}_layout_b.png", "b", 32, 1024))
        elif view == "save":
            P.apply_bake_layout(KIT)
            C.save_blend(OUT / "drill_rig_procedural.blend")
            return
    if out:
        C.contact_sheet(out, wip / f"{TAG}_sheet.png", cols=4, tile=512, background=0.02)


if __name__ == "__main__":  # drill_rig_bake.py imports the renders
    main()
