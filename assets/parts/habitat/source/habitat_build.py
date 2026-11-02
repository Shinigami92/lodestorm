"""Overgrowth point of interest: a prefab habitat module the growth has taken over. The module broke in two at
its middle, both halves sagging into the split, a roof panel gone; giant fungal tubes grew up through the split, a giant
mushroom leans its cap over the roof, roots drape over the walls into the ground and bracket fungus grows on the
panels. Beside it lie the fallen roof panel and a mat of roots spreading over the ground.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/habitat/source/habitat_build.py wip r1                  # pieces + layout
    tools/blender.sh assets/parts/habitat/source/habitat_build.py wip r1 Habitat,layout
    tools/blender.sh assets/parts/habitat/source/habitat_build.py final

Everything it writes goes to tmp/assets/parts/habitat/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: a piece name, pieces, layout, save); "final" renders every piece (iso + hero), the part's
layout from the game's angle (both sides), writes the contact sheet sheet.png and saves the procedural
habitat_procedural.blend that habitat_bake.py turns into the game asset. In the .blend the pieces stand in a row
along X (no AO from a neighbor in the bake); the bake zeroes their locations for the export.

Game contract (game/locations/parts/, ModelParts): every piece is ONE mesh object at the kit's root (no parent),
named as in PIECES, origin at its ground contact (bottom center, z = 0), front (the torn wall) toward -Y, with
geometry reaching below z = 0 so it never floats on uneven ground. Budgets (TBD (playtest)): the habitat <= ~8k
triangles, the panel <= ~2k, the root mat <= ~1.5k.

Look: the colony's prefab module (bone-white panels, gunmetal frame, faded amber hazard bands, chipped paint, rust
streaks, grime; the shared colony paint of the parts kits), damp and grown over: dark olive moss and stains rising
from the ground and in the recesses. The growth is the Overgrowth kit's own (assets/biomes/overgrowth/source/
overgrowth_build.py, loaded without running it): its giant tubes, mushrooms, roots, bracket fungus and their
materials, with the faint teal glow of its bulbs and tube throats. Top-facing surfaces stay fairly clean: the game
lays the biome's moss and litter on them. Besides the bulbs, the only glow is the red status light over the door.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "habitat"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
# The overgrowth kit's build: its materials and shape helpers, so the part matches the biome's own pieces.
sys.path.insert(0, str(ROOT / "assets" / "biomes" / "overgrowth" / "source"))

import bpy
from mathutils import Matrix, Vector

import colony_part as P
import common as C
import overgrowth_build as OG
from colony_part import Mat, cut_below, join, mat_dark, srgb, stripes, transform_bm
from common import T, rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["pieces", "layout"]

ASSET = "Habitat"
PIECES = ["Habitat", "Habitat_panel", "Habitat_roots"]
BAKE_GAP = 5.0  # m between the pieces in the saved .blend's row
SINK = 0.45  # geometry kept below z = 0 (m)

# Approximate linear albedo of the Overgrowth's ground (overgrowth_build.py's GROUND: dark soil under olive moss).
GROUND = ((0.018, 0.019, 0.011), (0.045, 0.047, 0.026))
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
LAMP_STRENGTH = 3.0  # the bake's emission_strength (as the Overgrowth kit's): the lens bakes to its full color


# --- materials ------------------------------------------------------------------------------------------


def mat_paint(
    name: str,
    color,
    wear: float = 1.0,
    rust: float = 1.0,
    dust: float = 1.0,
    hazard: bool = False,
    roughness: float = 0.58,
    moss: float = 0.0,
) -> bpy.types.Material:
    """The colony's weathered paint on steel: a large, low-contrast tone drift, grime in the recesses, rust streaks
    running down the vertical faces, grey-brown dust on the lower part and on ledges, paint chipped to bare steel on
    the edges. hazard: faded amber / dark diagonal bands instead of the plain color. moss: dark olive growth and
    damp stains rising from the ground and in the recesses, in patches."""
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
    moss_m = None
    if moss:
        damp = m.math("ADD", m.math("MULTIPLY", m.low(0.2, 1.8), 0.8), m.math("MULTIPLY", cav, 0.6))
        damp = m.math("MULTIPLY", damp, m.ramp(0.38, 0.62, m.noise(1.6, 5.0, 0.62)))
        moss_m = m.math("MULTIPLY", damp, moss, clamp=True)
        col = m.mix(moss_m, col, m.mix(m.noise(9.0, 4.0, 0.6), srgb(0.1, 0.11, 0.06), srgb(0.17, 0.19, 0.1)))
    # Edge wear: paint chipped to steel on the convex edges, broken up.
    edge = m.ramp(0.03, 0.12, C._bevel_edge(m.nt, 0.025, m.geo))
    wear_m = m.math("MULTIPLY", m.math("MULTIPLY", edge, m.ramp(0.42, 0.6, m.noise(6.0, 3.0, 0.6))), wear, clamp=True)
    col = m.mix(wear_m, col, STEEL)
    rough = m.mixf(mid, roughness - 0.07, roughness + 0.07)
    rough = m.mixf(m.math("MULTIPLY", cav, 0.7), rough, 0.8)
    rough = m.mixf(dust_m, rough, 0.88)
    rough = m.mixf(wear_m, rough, 0.38)
    if moss:
        rough = m.mixf(moss_m, rough, 0.85)
    height = m.math("ADD", m.math("MULTIPLY", m.noise(40.0, 3.0, 0.5), 0.15), m.math("MULTIPLY", wear_m, -0.3))
    return m.out(col, rough, wear_m, height, 0.25, 0.01)


# --- mesh helpers ---------------------------------------------------------------------------------------


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


def finish_growth(g, mat: bpy.types.Material) -> bpy.types.Object:
    """An Overgrowth kit Growth as an object, cut SINK below ground."""
    cut_below(g.bm, -SINK)
    for f in g.bm.faces:
        f.smooth = True
    return g.finish(None, mat)


# --- pieces ---------------------------------------------------------------------------------------------

W = 3.5  # module width (Y)
FLOOR_Z = 0.5  # floor top
WALL_Z = 3.0  # wall top (the roof sits on it)
LEFT = (-3.5, -0.45)  # the module's two halves along X; the split between them
RIGHT = (0.55, 3.5)
ROOF_GAP = 1.95  # the right half's roof starts here: the panel between fell off (Habitat_panel)


def half_matrix(right: bool) -> Matrix:
    """Each half sags toward the split (a V), turned around its outer end's bottom edge."""
    pivot = Vector((RIGHT[1] if right else LEFT[0], 0, 0))
    return Matrix.Translation(pivot) @ ry(-6.0 if right else 4.0).to_4x4() @ Matrix.Translation(-pivot)


def module_half(p: C.Part, x0: float, x1: float, right: bool) -> None:
    """One half of the prefab module: skids, floor, bone wall panels with ribs and dark windows, the outer end wall
    (the left one with its hazard-framed door and a red status light), corner posts, the roof with its rim, and
    torn, bent panels at the split."""
    ln, cx = x1 - x0, (x0 + x1) / 2
    hy = W / 2
    wall_h = WALL_Z - FLOOR_Z
    wz = FLOOR_Z + wall_h / 2
    for y in (-1.2, 1.2):
        p.box((cx, y, (FLOOR_Z - 0.16 - SINK - 0.1) / 2), (ln, 0.22, FLOOR_Z - 0.16 + SINK + 0.1), mi=FRAME)
    p.box((cx, 0, FLOOR_Z - 0.08), (ln, W, 0.16), mi=FRAME)
    for y in (-hy + 0.05, hy - 0.05):
        p.box((cx, y, wz), (ln, 0.1, wall_h), mi=PANEL)
        x = x0 + 0.5
        while x < x1 - 0.3:  # panel ribs
            p.box((x, y + (0.04 if y > 0 else -0.04), wz), (0.08, 0.04, wall_h - 0.1), mi=PANEL)
            x += 1.0
        p.box((cx, y + (0.03 if y > 0 else -0.03), FLOOR_Z + 0.08), (ln, 0.06, 0.16), mi=HAZ)
    for wx in (x0 + 0.95, x1 - 1.1) if not right else (x1 - 1.0,):
        p.box((wx, -hy - 0.01, 2.05), (0.62, 0.04, 0.46), mi=DARK)
        p.box((wx, -hy - 0.02, 2.05), (0.72, 0.03, 0.06), mi=FRAME)
    end_x = x0 if not right else x1
    s = -1 if not right else 1
    p.box((end_x - s * 0.05, 0, wz), (0.1, W, wall_h), mi=PANEL)
    for y in (-hy, hy):
        p.box((end_x, y, wz), (0.18, 0.18, wall_h + 0.1), mi=FRAME)
        p.box((x1 if not right else x0, y, wz - 0.3), (0.16, 0.16, wall_h - 0.6), mi=FRAME)  # the split side's post
    if not right:
        dx = end_x - 0.11
        p.box((dx, 0.2, FLOOR_Z + 1.0), (0.04, 0.9, 2.0), mi=FRAME)  # door
        for y in (-0.3, 0.7):
            p.box((dx - 0.01, y, FLOOR_Z + 1.05), (0.05, 0.1, 2.1), mi=HAZ)
        p.box((dx - 0.01, 0.2, FLOOR_Z + 2.12), (0.05, 1.1, 0.1), mi=HAZ)
        p.box((dx - 0.03, -0.05, FLOOR_Z + 1.0), (0.04, 0.05, 0.2), mi=PIPE)  # handle
        p.cyl((dx - 0.02, 0.2, FLOOR_Z + 2.35), 0.05, 0.05, 8, rot=ry(90), mi=LAMP)
        # Steps to the door.
        p.box((end_x - 0.4, 0.2, 0.22), (0.5, 1.0, 0.08), mi=FRAME)
        # Stencil: an ID number on the front wall, an arrow to the door.
        for i, h in enumerate((0.36, 0.36, 0.22, 0.36)):
            p.box((x0 + 2.0 + i * 0.17, -hy - 0.012, 1.25 + (0.36 - h) / 2), (0.08, 0.01, h), mi=FRAME)
        arrow = [(-0.3, -0.06), (0.1, -0.06), (0.1, -0.16), (0.3, 0.0), (0.1, 0.16), (0.1, 0.06), (-0.3, 0.06)]
        p.prism(arrow, -0.005, 0.005, T((x0 + 1.0, -hy - 0.012, 1.3), rx(90) @ rz(180)), mi=HAZ)
    # Roof and rim.
    r0 = x0 if not right else ROOF_GAP
    r1 = x1
    p.box(((r0 + r1) / 2, 0, WALL_Z + 0.06), (r1 - r0, W + 0.1, 0.12), mi=PANEL)
    for y in (-hy - 0.05, hy + 0.05):
        p.box(((r0 + r1) / 2, y, WALL_Z + 0.08), (r1 - r0, 0.1, 0.18), mi=FRAME)
    p.box((end_x, 0, WALL_Z + 0.08), (0.1, W + 0.2, 0.18), mi=FRAME)
    p.box((x0 + 0.9 if not right else x1 - 0.9, 0.6, WALL_Z + 0.32), (0.8, 0.9, 0.4), mi=FRAME)  # roof unit
    # Torn panels at the split, bent outward.
    sx = x1 if not right else x0
    for y, ang in ((-hy + 0.05, -32), (hy - 0.05, 28)):
        p.box((sx + s * -0.25, y + (-0.18 if y < 0 else 0.18), 1.9), (0.6, 0.06, 1.6), rot=rz(ang * -s), mi=PANEL)
    if right:  # the roof panel left hanging into the module at the gap
        p.box((ROOF_GAP - 0.55, 0, WALL_Z - 0.35), (1.15, W - 0.4, 0.1), rot=ry(38), mi=PANEL)


def bracket(g, center, out: Vector, size: float) -> None:
    """A plated bracket fungus on a wall (the Overgrowth kit's shelves), facing `out`."""
    _, under, edge, top = OG.CAP_GRADS["cap"]
    rot = OG.axis_rot((Vector((0, 0, 1)) + out * 0.35).normalized())
    c = Vector(center) + out * size * 0.35
    prof = [
        (0.0, -size * 0.18, under, 0.0),
        (size * 0.9, -size * 0.12, under, 0.0),
        (size, 0.0, edge, 0.5),
        (size * 0.72, size * 0.16, top, 1.0),
        (0.0, size * 0.22, 1.0, 1.0),
    ]
    g.lathe(c, prof, 9, rot=rot, spin=g.rnd.uniform(0, 1), wobble=0.12, wfreq=2.5)
    g.bulb(c + rot @ Vector((0, 0, -size * 0.2)), max(0.04, size * 0.14), out=-Vector((0, 0, 1)), grad=under)


def habitat() -> bpy.types.Object:
    """Habitat: a prefab module (7 x 3.5 x 3 m) broken in two at its middle, both halves sagging into the split, a
    roof panel gone (Habitat_panel) and one hanging in; three giant tubes grown up through the split (to 6.5 m), a
    giant mushroom behind it leaning its cap over the roof, roots draped over the walls into the ground and spilling
    out of the split, bracket fungus on the panels."""
    parts = []
    for right, (x0, x1) in ((False, LEFT), (True, RIGHT)):
        p = part(f"Habitat_half_{int(right)}")
        module_half(p, x0, x1, right)
        parts.append(finish_part(p, half_matrix(right)))
    g = OG.Growth("Habitat_stalks", 301)
    OG.giant_tube(g, (0.05, 0.25, 0.25), 6.5, 0.45, Vector((0.4, 0.6, 0)), 0.05, 11, "mouth", 4, n_shelves=2, n_lumps=1)
    OG.giant_tube(g, (-0.05, -0.8, 0.25), 4.6, 0.36, Vector((0.3, -1, 0)), 0.1, 10, "trumpet", 2, cap_r=0.95)
    OG.giant_tube(g, (0.35, 1.15, 0.2), 3.0, 0.28, Vector((-0.4, 1, 0)), 0.1, 9, "pod", 0)
    OG.mound(g, (0.05, 0.0, 0.35), 1.15, 0.45)
    parts.append(finish_growth(g, M["stalk"]))
    c = OG.Growth("Habitat_caps", 311)
    OG.giant_mushroom(c, (2.7, 2.7, 0), 5.2, 1.9, 0.45, Vector((-0.6, -0.7, 0)), 0.09, 22, 8, n_shelves=1)
    OG.mound(c, (2.7, 2.7, 0), 1.0, 0.35)
    OG.foot_roots(c, Vector((2.7, 2.7, 0)), 0.8, 4, 0.9, 0.24, 0.45)
    for pos, out, size in (
        ((-2.7, -1.85, 1.0), (0, -1, 0), 0.32),
        ((-2.25, -1.85, 0.75), (0, -1, 0), 0.24),
        ((-1.05, -1.85, 1.55), (0, -1, 0), 0.28),
        ((2.5, -1.85, 0.75), (0, -1, 0), 0.3),
        ((-1.6, 1.85, 1.1), (0, 1, 0), 0.3),
        ((3.6, 0.6, 0.9), (1, 0, 0), 0.26),
    ):
        bracket(c, Vector(pos), Vector(out), size)
    parts.append(finish_growth(c, M["cap"]))
    r = OG.Growth("Habitat_roots_draped", 321)
    # (start, direction, length, radius, [(t, center height)]): two draped over the roof's edge and hugging the wall
    # down into the ground (front and back), one spilling out of the split low over the ground.
    over_front = [(0, 2.3), (0.1, 3.25), (0.72, 3.25), (0.82, 2.6), (0.9, 1.3), (1, -0.45)]
    over_back = [(0, 2.4), (0.1, 3.2), (0.62, 3.2), (0.73, 2.5), (0.84, 1.2), (1, -0.45)]
    for start, d, length, r0, keys in (
        ((-1.5, 0.6), (0.0, -1), 2.9, 0.3, over_front),
        ((2.4, -0.3), (0.0, 1), 2.9, 0.27, over_back),
        ((0.25, -0.4), (0.25, -1), 3.6, 0.25, [(0, 0.55), (0.3, 0.45), (0.6, 0.2), (1, -0.45)]),
    ):
        OG.root_run(r, start, d, length, r0, r0 * 0.55, keys, forks=1, n=14, seg=7)
    parts.append(finish_growth(r, M["root"]))
    return join("Habitat", parts)


def habitat_panel() -> bpy.types.Object:
    """Habitat_panel: the fallen roof panel (3.6 x 2 m), bent across its middle, lying on the ground: ribs and rim
    underneath on its raised half, a torn edge; two small mushrooms, a bracket and a root grown over it."""
    p = part("Habitat_panel_body")
    p.box((-0.5, 0, 0.06), (1.0, 3.6, 0.1), mi=PANEL)
    p.box((-0.5, 0, -0.2), (0.9, 3.4, 0.4), mi=FRAME)  # under it: keeps it from floating on uneven ground
    bend = T((0, 0, 0.01), ry(-14))
    p.box(bend @ Vector((0.48, 0, 0.06)), (0.96, 3.6, 0.1), rot=ry(-14), mi=PANEL)
    for y in (-1.8, 1.8):
        p.box((-0.5, y, 0.1), (1.0, 0.1, 0.16), mi=FRAME)
        p.box(bend @ Vector((0.48, y, 0.1)), (0.96, 0.1, 0.16), rot=ry(-14), mi=FRAME)
    for y in (-0.9, 0.0, 0.9):
        p.box((-0.5, y, 0.13), (1.0, 0.06, 0.05), mi=PANEL)
        p.box(bend @ Vector((0.48, y, 0.13)), (0.96, 0.06, 0.05), rot=ry(-14), mi=PANEL)
    for y, ang in ((-1.3, 12), (-0.4, -9), (0.5, 15), (1.35, -6)):  # torn edge: bent tabs
        p.box(bend @ Vector((1.02, y, 0.08)), (0.22, 0.5, 0.06), rot=ry(-14 + ang) @ rz(ang), mi=PANEL)
    p.box((-0.6, -0.8, 0.115), (0.6, 0.6, 0.012), mi=HAZ)
    body = finish_part(p)
    c = OG.Growth("Habitat_panel_caps", 331)
    OG.giant_mushroom(c, (-0.55, 0.9, 0.05), 0.75, 0.36, 0.08, Vector((0.3, 0.5, 0)), 0.1, 14, 3)
    OG.giant_mushroom(c, (-0.3, 1.35, 0.05), 0.45, 0.22, 0.06, Vector((1, 0.4, 0)), 0.12, 12, 2)
    bracket(c, Vector((0.6, -1.8, 0.2)), Vector((0, -1, 0)), 0.25)
    OG.root_run(
        c, (-1.6, -0.6), (1, 0.15), 3.0, 0.11, 0.05, [(0, -0.45), (0.2, 0.25), (0.75, 0.42), (1, -0.45)], n=10, seg=6
    )
    return join("Habitat_panel", [body, finish_growth(c, M["cap"])])


def habitat_roots() -> bpy.types.Object:
    """Habitat_roots: a low mat of roots (4.6 x 3.4 m, under 0.4 m) spreading from the habitat over the ground, in
    shallow arches in and out of it, bulbs on the thicker ones' crests (the Overgrowth kit's roots, kept low)."""
    g = OG.Growth("Habitat_roots_mat", 341)
    low = [(0.0, -0.45), (0.2, 0.18), (0.5, 0.3), (0.75, 0.12), (1.0, -0.45)]
    OG.root_bundle(
        g,
        [
            (0.0, 3, 4.6, 0.2, [(0.0, -0.45), (0.15, 0.3), (0.45, 0.36), (0.7, 0.2), (1.0, -0.45)], 2),
            (-0.75, -14, 3.9, 0.15, low, 1),
            (0.8, 12, 4.0, 0.15, low, 1),
            (-1.35, -24, 3.0, 0.11, [(0.0, -0.45), (0.4, 0.2), (1.0, -0.45)], 0),
            (1.4, 22, 3.2, 0.11, [(0.0, -0.45), (0.35, 0.22), (1.0, -0.45)], 0),
            (0.35, -6, 2.6, 0.09, [(0.0, -0.45), (0.5, 0.16), (1.0, -0.45)], 0),
        ],
    )
    return join("Habitat_roots", [finish_growth(g, M["root"])])


BUILDERS = {"Habitat": habitat, "Habitat_panel": habitat_panel, "Habitat_roots": habitat_roots}


# --- layout, preview, renders ---------------------------------------------------------------------------

# The part's layout (Blender: x, y, z rotation in degrees; the way into the area is +Y). Crate and ore spots are
# markers the game places (crate 1.2 x 0.8 m).
LAYOUT = {
    "Habitat": (0.0, 0.6, 15),
    "Habitat_panel": (-1.9, -3.6, -20),
    "Habitat_roots": (2.4, -3.0, -70),
}
CRATE = (-5.2, 2.5, 105)
ORE_SPOTS = [(5.6, 2.3), (-4.4, -5.2), (-1.8, 6.4)]
POLE = (1.4, -5.6)


# --- main -----------------------------------------------------------------------------------------------


def build() -> None:
    global MATS, MAT_LIST, M
    MATS = {
        "frame": mat_paint("HabFrame", GUNMETAL, moss=0.8),
        "hazard": mat_paint("HabHazard", HAZARD, hazard=True, wear=1.2, moss=0.8),
        "panel": mat_paint("HabPanel", BONE, wear=0.8, moss=1.0),
        "pipe": mat_paint("HabSteel", srgb(0.24, 0.23, 0.22), wear=0.6, rust=1.4, moss=0.6),
        "lamp": C.mat_emissive("HabLamp", LAMP_RED, LAMP_STRENGTH),
        "dark": mat_dark("HabDark"),
        "cargo": mat_paint("HabCargo", OLIVE, moss=0.8),
    }
    MAT_LIST = [MATS[k] for k in ("frame", "hazard", "panel", "pipe", "lamp", "dark", "cargo")]
    M = OG.make_materials()
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
        C.save_blend(OUT / "habitat_procedural.blend")
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
            C.save_blend(OUT / "habitat_procedural.blend")
            return
    if out:
        C.contact_sheet(out, wip / f"{TAG}_sheet.png", cols=4, tile=512, background=0.02)


if __name__ == "__main__":  # habitat_bake.py imports the renders
    main()
