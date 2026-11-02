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

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "habitat"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
# The overgrowth kit's build: its materials and shape helpers, so the part matches the biome's own pieces.
sys.path.insert(0, str(ROOT / "assets" / "biomes" / "overgrowth" / "source"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
import overgrowth_build as OG
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


def srgb(r: float, g: float, b: float) -> tuple:
    """Linear color from sRGB values (the brief's colors are sRGB; node colors are linear)."""

    def lin(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin(r), lin(g), lin(b))


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


class Mat:
    """Node helpers around one procedural material (object coordinates, world normal)."""

    def __init__(self, name: str):
        self.mat, self.nt, self.bsdf = C._new_material(name)
        self.geo = self.nt.nodes.new("ShaderNodeNewGeometry")
        self.obj = self.nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        pos = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.obj, pos.inputs["Vector"])
        self.x, self.y, self.z = pos.outputs["X"], pos.outputs["Y"], pos.outputs["Z"]
        nrm = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.geo.outputs["Normal"], nrm.inputs["Vector"])
        self.nz = nrm.outputs["Z"]

    def math(self, op, a, b=None, c=None, clamp=False):
        return C._math(self.nt, op, a, b, c, clamp)

    def noise(self, scale, detail=4.0, rough=0.55, stretch=None):
        vec = self.obj
        if stretch is not None:
            mp = self.nt.nodes.new("ShaderNodeMapping")
            mp.inputs["Scale"].default_value = stretch
            self.nt.links.new(self.obj, mp.inputs["Vector"])
            vec = mp.outputs["Vector"]
        return C._noise(self.nt, scale, detail, rough, vector=vec).outputs["Fac"]

    def ramp(self, a, b, src):
        return C._ramp(self.nt, a, b, src)

    def mix(self, fac, a, b):
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b):
        return C._mix_float(self.nt, fac, a, b)

    def scale(self, col, fac):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = "SCALE"
        self.nt.links.new(col, n.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, n.inputs["Scale"])
        else:
            n.inputs["Scale"].default_value = fac
        return n.outputs[0]

    def cavity(self, distance: float):
        """1 in cavities, 0 in the open (from AO)."""
        ao = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = distance
        ao.samples = 16
        return self.math("SUBTRACT", 1.0, self.ramp(0.3, 0.95, ao.outputs["AO"]), clamp=True)

    def low(self, z0: float, z1: float):
        """1 below z0, fading to 0 at z1 (object Z)."""
        n = self.nt.nodes.new("ShaderNodeMapRange")
        self.nt.links.new(self.z, n.inputs["Value"])
        n.inputs["From Min"].default_value = z0
        n.inputs["From Max"].default_value = z1
        n.inputs["To Min"].default_value = 1.0
        n.inputs["To Max"].default_value = 0.0
        return n.outputs["Result"]

    def out(self, color, rough, metallic, height, strength: float, distance: float) -> bpy.types.Material:
        self.nt.links.new(color, self.bsdf.inputs["Base Color"])
        for sock, val in ((self.bsdf.inputs["Roughness"], rough), (self.bsdf.inputs["Metallic"], metallic)):
            if isinstance(val, bpy.types.NodeSocket):
                self.nt.links.new(val, sock)
            else:
                sock.default_value = val
        C._bump(self.nt, self.bsdf, height, strength, distance)
        return self.mat


def stripes(m: Mat, period: float = 0.42):
    """1 on diagonal hazard bands, 0 between them (object coordinates, along X + Y - Z)."""
    d = m.nt.nodes.new("ShaderNodeVectorMath")
    d.operation = "DOT_PRODUCT"
    m.nt.links.new(m.obj, d.inputs[0])
    d.inputs[1].default_value = (0.7, 0.7, -0.7)
    frac = m.math("FRACT", m.math("DIVIDE", d.outputs["Value"], period))
    return m.math("MULTIPLY", m.ramp(0.47, 0.5, frac), m.ramp(0.0, 0.03, frac))


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


def mat_dark(name: str) -> bpy.types.Material:
    """Shadowed openings and recesses (inside a housing, a grille): near black, dull."""
    m = Mat(name)
    col = m.mix(m.noise(3.0), (0.008, 0.008, 0.009), (0.016, 0.015, 0.015))
    return m.out(col, 0.75, 0.0, m.noise(20.0), 0.1, 0.01)


# --- mesh helpers ---------------------------------------------------------------------------------------


def apply_modifiers(obj: bpy.types.Object) -> None:
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old = obj.data
    mats = list(old.materials)
    obj.modifiers.clear()
    obj.data = me
    if not me.materials:
        for mt in mats:
            me.materials.append(mt)
    bpy.data.meshes.remove(old)


def join(name: str, objs: list) -> bpy.types.Object:
    """Apply the objects' modifiers and join them into one mesh object `name` (asset collection, no parent)."""
    for o in objs:
        apply_modifiers(o)
        print(f"TRIS {name} / {o.name}: {sum(len(pl.vertices) - 2 for pl in o.data.polygons)}")
    # One at a time, in order: joining all at once takes them in an order of Blender's (it changes between runs),
    # so the vertex order (and with it the unwrap and the bake) would too.
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs[1:]:
        bpy.ops.object.select_all(action="DESELECT")
        objs[0].select_set(True)
        o.select_set(True)
        bpy.ops.object.join()
    obj = objs[0]
    obj.name = name
    obj.data.name = name
    obj.parent = None
    return obj


def transform_bm(bm: bmesh.types.BMesh, m: Matrix) -> None:
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])


def cut_below(bm: bmesh.types.BMesh, z: float) -> None:
    """Drop everything below z and close the cut."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=(0, 0, z), plane_no=(0, 0, -1), clear_outer=True)
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)


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


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in PIECES]


def ground_color() -> None:
    lo, hi = GROUND
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*lo, 1.0)
            node.inputs[7].default_value = (*hi, 1.0)


def setup_preview() -> None:
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # the preview's pebbles would read as part of the kit
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    bpy.data.objects["PreviewGround"].scale = (3, 3, 1)
    ground_color()
    build_layout_scene()


def light_rig(scale: float) -> None:
    """Scale the studio lights (set up for ~2 m props) around the origin for bigger pieces."""
    for o in C.collection("Preview").objects:
        if o.type != "LIGHT":
            continue
        base = o.get("base")
        if base is None:
            o["base"] = (*o.location, o.data.energy)
            base = o["base"]
        o.location = Vector(base[:3]) * scale
        o.data.energy = base[3] * scale * scale
        o.rotation_euler = (Vector((0, 0, 1.6 * scale)) - o.location).to_track_quat("-Z", "Y").to_euler()


def render_piece(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The piece alone at the origin, framed by its size, the 1.8 m figure beside it, studio light."""
    obj = bpy.data.objects[name]
    for o in kit_objects():
        o.hide_render = o is not obj
    obj.location = (0, 0, 0)
    dx, dy, dz = obj.dimensions
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # screen right in the iso view
    fig.location = side * (max(dx, dy) / 2 + 0.6)
    w = max(dx, dy, dz * 1.1) * 1.2 + 1.2
    light_rig(max(1.0, w / 5.0))
    target = side * 0.3 + Vector((0, 0, max(0.5, dz * 0.42)))
    out = []
    for view in views:
        path = OUT / f"{prefix}{name}_{view}.png"
        C.render(
            path, view=view, samples=samples, size=size, target=tuple(target), zoom=w / (9.9 if view == "iso" else 6.3)
        )
        out.append(path)
    for o in kit_objects():
        o.hide_render = False
    light_rig(1.0)
    return out


def build_layout_scene() -> None:
    """The game-angle layout's own props in a "Layout" collection (hidden in the studio renders): a big ground in
    the biome's tone, the 1.89 m pole, prop_radius and footprint rings, the crate and ore spot markers, a weak low
    sun and a little cool sky."""
    coll = bpy.data.collections.new("Layout")
    bpy.context.scene.collection.children.link(coll)

    def add(obj):
        coll.objects.link(obj)
        return obj

    def mat(name, color, rough=0.9, emit=0.0):
        mt, _nt, bsdf = C._new_material(name)
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        if emit:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emit
        return mt

    def mesh_obj(name, bm, material):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(material)
        for poly in me.polygons:
            poly.use_smooth = True
        return add(bpy.data.objects.new(name, me))

    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=45)
    ground = mesh_obj("LayoutGround", bm, bpy.data.materials["PreviewGround"])
    ground.location.z = -0.002
    for r, w, name in ((PROP_RADIUS, 0.05, "LayoutRingProps"), (FOOTPRINT, 0.035, "LayoutRingFootprint")):
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=False, segments=128, radius=r)
        geom = bmesh.ops.extrude_edge_only(bm, edges=bm.edges[:])["geom"]
        for v in [g for g in geom if isinstance(g, bmesh.types.BMVert)]:
            v.co *= (r + w) / r
        mesh_obj(name, bm, mat(name, (0.6, 0.6, 0.55) if r == PROP_RADIUS else (0.2, 0.2, 0.19), 0.8, 0.4))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.05, radius2=0.05, depth=1.89,
                          matrix=Matrix.Translation((0, 0, 0.945)))  # fmt: skip
    pole = mesh_obj("LayoutPole", bm, mat("LayoutPole", (0.7, 0.32, 0.05), 0.6, 0.6))
    pole.location = (*POLE, 0)
    crate_m = mat("LayoutCrate", OLIVE, 0.6)
    band_m = mat("LayoutCrateBand", (1.0, 0.55, 0.12), 0.5, 3.0)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((1.2, 0.8, 0.7, 1)) @ Matrix.Translation((0, 0, 0.5)))
    crate = mesh_obj("LayoutCrate", bm, crate_m)
    bm = bmesh.new()
    bmesh.ops.create_cube(
        bm, size=1.0, matrix=Matrix.Translation((0, 0, 0.45)) @ Matrix.Diagonal((1.22, 0.82, 0.06, 1))
    )
    band = mesh_obj("LayoutCrateBand", bm, band_m)
    for o in (crate, band):
        o.location = (CRATE[0], CRATE[1], 0)
        o.rotation_euler = (0, 0, math.radians(CRATE[2]))
    ore_m = mat("LayoutOre", (0.12, 0.9, 0.85), 0.3, 4.0)
    rnd = random.Random(3)
    for i, (x, y) in enumerate(ORE_SPOTS):
        bm = bmesh.new()
        for k in range(6):
            a = k / 6 * math.tau + rnd.uniform(-0.3, 0.3)
            r = rnd.uniform(0.3, 0.8)
            h = rnd.uniform(0.5, 1.0)
            m = T((math.cos(a) * r, math.sin(a) * r, h * 0.4), rx(-math.sin(a) * 25) @ ry(math.cos(a) * 25))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.13, radius2=0.0, depth=h, matrix=m)
        mesh_obj(f"LayoutOre{i}", bm, ore_m).location = (x, y, 0)
    sun = bpy.data.lights.new("LayoutSun", "SUN")
    sun.energy = 3.5
    sun.color = (0.85, 0.9, 1.0)
    sun.angle = math.radians(1.5)
    sun_obj = add(bpy.data.objects.new("LayoutSun", sun))
    sun_obj.rotation_euler = (math.radians(90 - 30), 0, math.radians(10))
    world = bpy.data.worlds.new("LayoutWorld")
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.05, 0.06, 0.08, 1.0)
    coll.hide_render = True


def render_layout(path: pathlib.Path, view: str, samples: int, size: int) -> pathlib.Path:
    """The part as the game places it (LAYOUT), from the game's angle: pitched 50 degrees down, 45 degrees around
    (view "a": from +X/-Y like the game camera; "b": from the other side), dim cool light."""
    scene = bpy.context.scene
    coll = bpy.data.collections["Layout"]
    preview = C.collection("Preview")
    studio_world = scene.world
    coll.hide_render = False
    hidden = [o for o in preview.objects if not o.hide_render and o.type != "CAMERA"]
    for o in hidden:
        o.hide_render = True
    for name, (x, y, rot) in LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.location = (x, y, 0)
        obj.rotation_euler = (0, 0, math.radians(rot))
        obj.hide_render = False
    scene.world = bpy.data.worlds["LayoutWorld"]
    yaw = math.radians(-45 if view == "a" else 135)
    pitch = math.radians(50)
    dist = 38.0
    target = Vector((0, 0, 1.0))
    loc = (
        target
        + Vector((-math.sin(yaw), -math.cos(yaw), 0)) * dist * math.cos(pitch)
        + Vector((0, 0, dist * math.sin(pitch)))
    )
    C.render_from(path, tuple(loc), tuple(target), lens=42, samples=samples, size=size)
    scene.world = studio_world
    for o in hidden:
        o.hide_render = False
    coll.hide_render = True
    for obj in kit_objects():
        obj.location = (0, 0, 0)
        obj.rotation_euler = (0, 0, 0)
    return path


def apply_bake_layout() -> None:
    """Saved .blend: the pieces unrotated in a row along X, BAKE_GAP apart (no AO from a neighbor in the bake)."""
    x = 0.0
    for name in PIECES:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + BAKE_GAP
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


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


def report() -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for name in PIECES:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        xs, ys, zs = ([v.co[i] for v in me.vertices] for i in range(3))
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} x=({min(xs):.2f}, {max(xs):.2f})"
            f" y=({min(ys):.2f}, {max(ys):.2f}) z=({min(zs):.2f}, {max(zs):.2f})"
            f" mats={[m.name for m in me.materials]}"
        )
        obj.evaluated_get(dg).to_mesh_clear()


def main() -> None:
    C.reset(ASSET)
    build()
    report()
    setup_preview()
    if MODE == "final":
        sheet = []
        for name in PIECES:
            sheet += render_piece(name, "final_", ("iso", "hero"), 48, 768)
        sheet.append(render_layout(OUT / "final_layout_a.png", "a", 64, 1024))
        sheet.append(render_layout(OUT / "final_layout_b.png", "b", 64, 1024))
        C.contact_sheet(sheet, OUT / "sheet.png", cols=4, tile=512, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "habitat_procedural.blend")
        return
    wip = OUT / "wip"
    out = []
    for view in VIEWS:
        if view == "pieces":
            for name in PIECES:
                out += render_piece(name, f"wip/{TAG}_", ("iso", "hero"), 20, 640)
        elif view in BUILDERS:
            out += render_piece(view, f"wip/{TAG}_", ("iso", "hero"), 24, 768)
        elif view == "layout":
            out.append(render_layout(wip / f"{TAG}_layout_a.png", "a", 32, 1024))
            out.append(render_layout(wip / f"{TAG}_layout_b.png", "b", 32, 1024))
        elif view == "save":
            apply_bake_layout()
            C.save_blend(OUT / "habitat_procedural.blend")
            return
    if out:
        C.contact_sheet(out, wip / f"{TAG}_sheet.png", cols=4, tile=512, background=0.02)


if __name__ == "__main__":  # habitat_bake.py imports the renders
    main()
