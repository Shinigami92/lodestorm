"""Glass plains point of interest: a small survey lander caught by the heat that made the plains. It stands in pools of
fused glass on three legs, the fourth broken off (it slumped onto that corner, which sank into a mound of melt), glass
drips on its lower body, the paint blistered and heat-blued on its +X side, its hatch open. Beside it lie the broken
leg and loose pools of glass.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/lander/source/lander_build.py wip r1                   # pieces + layout
    tools/blender.sh assets/parts/lander/source/lander_build.py wip r1 Lander,layout
    tools/blender.sh assets/parts/lander/source/lander_build.py final

Everything it writes goes to tmp/assets/parts/lander/: "wip <tag> [views]" renders quick previews into wip/<tag>_*.png
(views: a piece name, pieces, layout, save); "final" renders every piece (iso + hero), the part's layout from the
game's angle (both sides), writes the contact sheet sheet.png and saves the procedural lander_procedural.blend that
lander_bake.py turns into the game asset. In the .blend the pieces stand in a row along X (no AO from a neighbor in
the bake); the bake zeroes their locations for the export.

Game contract (game/locations/parts/, ModelParts): every piece is ONE mesh object at the kit's root (no parent),
named as in PIECES, origin at its ground contact (bottom center, z = 0), front (the hatch) toward -Y, with geometry
reaching below z = 0 so it never floats on uneven ground. Budgets (TBD (playtest)): the lander <= ~8k triangles, the
leg <= ~1.5k, the pool <= ~800.

Look: the colony's equipment (gunmetal frame and legs, bone-white crew module, olive tanks, faded amber hazard bands,
chipped paint, rust streaks, grime and dust low down; the shared colony paint of the parts kits), scorched on the side
the flare came from: paint blistered, darkened and burnt off to steel tempered bronze, violet and blue (muted). The
glass is the Glass plains' smoky grey-teal (assets/biomes/glass/source/glass_build.py, the terrain layer's pools),
darker and glossier in the thick pools. Top-facing surfaces stay fairly clean: the game lays the biome's grit on them.
The only glow is the red beacon lens on the mast.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "lander"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
from common import T, rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["pieces", "layout"]

ASSET = "Lander"
PIECES = ["Lander", "Lander_leg", "Lander_pool"]
BAKE_GAP = 4.0  # m between the pieces in the saved .blend's row
SINK = 0.45  # geometry kept below z = 0 (m)
SLUMP = 8.0  # degrees the lander leans onto its broken leg's corner

# Approximate linear albedo of the glass plains' ground (the terrain layer's grit and pools, sRGB about 0.3).
GROUND = ((0.062, 0.07, 0.072), (0.11, 0.12, 0.12))
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
LAMP_STRENGTH = 6.0  # the bake's emission_strength: the lens bakes to its full color


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
    heat: float = 0.0,
) -> bpy.types.Material:
    """The colony's weathered paint on steel: a large, low-contrast tone drift, grime in the recesses, rust streaks
    running down the vertical faces, grey-brown dust on the lower part and on ledges, paint chipped to bare steel on
    the edges. hazard: faded amber / dark diagonal bands instead of the plain color. heat: the +X side scorched
    (see heat_scorch)."""
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
    burnt, blister = heat_scorch(m, heat) if heat else (None, None)
    if heat:
        col = m.mix(m.math("MULTIPLY", blister, 0.55), col, m.scale(col, 0.45))
        col = m.mix(burnt, col, temper(m))
    # Edge wear: paint chipped to steel on the convex edges, broken up.
    edge = m.ramp(0.03, 0.12, C._bevel_edge(m.nt, 0.025, m.geo))
    wear_m = m.math("MULTIPLY", m.math("MULTIPLY", edge, m.ramp(0.42, 0.6, m.noise(6.0, 3.0, 0.6))), wear, clamp=True)
    col = m.mix(wear_m, col, STEEL)
    rough = m.mixf(mid, roughness - 0.07, roughness + 0.07)
    rough = m.mixf(m.math("MULTIPLY", cav, 0.7), rough, 0.8)
    rough = m.mixf(dust_m, rough, 0.88)
    rough = m.mixf(wear_m, rough, 0.38)
    height = m.math("ADD", m.math("MULTIPLY", m.noise(40.0, 3.0, 0.5), 0.15), m.math("MULTIPLY", wear_m, -0.3))
    metal = wear_m
    if heat:
        rough = m.mixf(burnt, rough, 0.42)
        metal = m.math("MAXIMUM", wear_m, m.math("MULTIPLY", burnt, 0.85))
        cells = m.nt.nodes.new("ShaderNodeTexVoronoi")
        cells.feature = "SMOOTH_F1"
        cells.inputs["Scale"].default_value = 14.0
        m.nt.links.new(m.obj, cells.inputs["Vector"])
        bumps = m.math("SUBTRACT", 1.0, m.ramp(0.0, 0.35, cells.outputs["Distance"]))
        height = m.math("ADD", height, m.math("MULTIPLY", bumps, m.math("MULTIPLY", blister, 0.8)))
    return m.out(col, rough, metal, height, 0.25, 0.01)


def heat_scorch(m: Mat, heat: float):
    """The flare's side (+X in the piece's frame): `burnt` 1 where the paint burnt off to steel (in ragged patches
    deep on that side), `blister` 1 on the blistered, darkened band around them."""
    ragged = m.math("MULTIPLY", m.math("SUBTRACT", m.noise(1.4, 4.0, 0.6), 0.5), 1.4)
    side = m.ramp(-0.4, 1.3, m.math("ADD", m.x, ragged))
    side = m.math("MULTIPLY", side, heat, clamp=True)
    burnt = m.ramp(0.62, 0.72, side)
    blister = m.math("MULTIPLY", m.ramp(0.3, 0.55, side), m.math("SUBTRACT", 1.0, burnt))
    return burnt, blister


def temper(m: Mat):
    """Heat-tempered steel, muted: straw-bronze through violet to blue and back to grey, in broad bands."""
    n = m.nt.nodes.new("ShaderNodeValToRGB")
    els = n.color_ramp.elements
    stops = [
        (0.2, srgb(0.36, 0.3, 0.22)),
        (0.4, srgb(0.3, 0.22, 0.26)),
        (0.58, srgb(0.2, 0.22, 0.33)),
        (0.8, srgb(0.3, 0.32, 0.36)),
    ]
    while len(els) < len(stops):
        els.new(0.5)
    for el, (pos, c) in zip(els, stops):
        el.position = pos
        el.color = (*c, 1.0)
    m.nt.links.new(m.noise(0.9, 3.0, 0.5, stretch=(1.0, 1.0, 1.6)), n.inputs["Fac"])
    return n.outputs["Color"]


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


def mat_glass(name: str) -> bpy.types.Material:
    """Fused glass, the Glass plains' melt (glass_build.py's smoky grey-teal, darker: these are thick pools): dark and
    glossy in its depth, a little paler where it thins at the edges and on the steep faces, faint crazing, a few
    frozen bubbles, a dull film of grit in patches; ripples of the frozen flow in the bump. Opaque (the game
    imports no transmission), no glow."""
    m = Mat(name)
    smoke = m.noise(1.6, 4.0, 0.6)
    col = m.mix(m.ramp(0.35, 0.68, smoke), srgb(0.1, 0.125, 0.13), srgb(0.16, 0.2, 0.205))
    steep = m.ramp(0.15, 0.75, m.math("SUBTRACT", 1.0, m.nz))
    thin = m.low(0.0, 0.07)
    col = m.mix(m.math("MULTIPLY", m.math("MAXIMUM", steep, thin), 0.55), col, srgb(0.26, 0.32, 0.33))
    warp = m.nt.nodes.new("ShaderNodeVectorMath")
    warp.operation = "MULTIPLY_ADD"
    m.nt.links.new(C._noise(m.nt, 1.3, 3.0, 0.5, vector=m.obj).outputs["Color"], warp.inputs[0])
    warp.inputs[1].default_value = (0.3, 0.3, 0.3)
    m.nt.links.new(m.obj, warp.inputs[2])
    craze = m.math(
        "MULTIPLY", C._voronoi_lines(m.nt, warp.outputs[0], 2.4, 0.012), m.ramp(0.45, 0.65, m.noise(2.5, 2.0))
    )
    col = m.mix(m.math("MULTIPLY", craze, 0.35), col, srgb(0.3, 0.36, 0.37))
    bubbles = m.ramp(0.66, 0.72, m.noise(30.0, 2.0, 0.5))
    col = m.mix(m.math("MULTIPLY", bubbles, 0.3), col, srgb(0.28, 0.33, 0.34))
    film = m.math("MULTIPLY", m.ramp(0.55, 0.75, m.noise(2.0, 5.0, 0.6)), m.ramp(0.5, 0.9, m.nz))
    film = m.math("MULTIPLY", film, 0.6)
    col = m.mix(film, col, srgb(0.3, 0.31, 0.3))
    rough = m.mixf(m.noise(12.0, 3.0), 0.1, 0.18)
    rough = m.mixf(film, rough, 0.65)
    wave = m.nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 2.5
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 2.0
    m.nt.links.new(m.obj, wave.inputs["Vector"])
    height = m.math("ADD", m.math("MULTIPLY", wave.outputs["Fac"], 0.2), m.math("MULTIPLY", craze, -0.3))
    return m.out(col, rough, 0.0, height, 0.25, 0.01)


class Glass:
    """Fused glass in one bmesh (smooth): pools and mounds, sheaths flowing up a strut, drips and runs."""

    def __init__(self, name: str, seed: int):
        self.name = name
        self.bm = bmesh.new()
        self.rnd = random.Random(seed)

    def mound(
        self,
        center,
        radius: float,
        height: float,
        stretch=(1.0, 1.0),
        turn: float = 0.0,
        seg: int = 24,
        rings: int = 6,
        flat: float = 0.65,
        lobes: float = 1.0,
    ) -> None:
        """A pool or mound of melt: a lobed outline, a top flat for `flat` (0..1: higher keeps it level longer), a
        rounded edge meeting the ground, a skirt reaching SINK below it (a polar grid of rings x seg)."""
        rnd = self.rnd
        ph = [rnd.uniform(0, math.tau) for _ in range(3)]
        c = Vector(center)
        rot = rz(turn)

        def edge(a: float) -> float:
            w = 0.2 * math.sin(3 * a + ph[0]) + 0.1 * math.sin(5 * a + ph[1]) + 0.05 * math.sin(9 * a + ph[2])
            return radius * (1 + lobes * w)

        def at(a: float, t: float, z: float) -> Vector:
            r = edge(a) * t
            return c + rot @ Vector((math.cos(a) * r * stretch[0], math.sin(a) * r * stretch[1], z))

        top = self.bm.verts.new(c + Vector((0, 0, height)))
        grid = []
        for i in range(1, rings + 1):
            t = i / rings
            z = height * (1 - t ** (2 + 6 * flat)) ** 0.5
            grid.append([self.bm.verts.new(at(k / seg * math.tau, t, max(z, 0.006))) for k in range(seg)])
        grid.append([self.bm.verts.new(at(k / seg * math.tau, 1.03, -SINK)) for k in range(seg)])
        for k in range(seg):
            self.bm.faces.new((top, grid[0][k], grid[0][(k + 1) % seg]))
        for ra, rb in itertools.pairwise(grid):
            for k in range(seg):
                self.bm.faces.new((ra[k], rb[k], rb[(k + 1) % seg], ra[(k + 1) % seg]))

    def sheath(self, p0, p1, r0: float, r1: float, seg: int = 8) -> None:
        """Melt that ran up a strut and froze: a tapered, lumpy tube from p0 (r0) to p1 (r1)."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        m = T((p0 + p1) / 2, C.basis(d, Vector((0, 0, 1)) if abs(d.normalized().z) < 0.9 else Vector((1, 0, 0))))
        verts = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=d.length, matrix=m
        )["verts"]
        for v in verts:
            v.co += C.noise_vector(v.co * 3.0) * r0 * 0.15

    def drip(self, top, length: float, r: float) -> None:
        """A drip hanging from `top`: a tapering run ending in a bead."""
        top = Vector(top)
        bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=6, radius1=r * 0.45, radius2=r, depth=length,
            matrix=Matrix.Translation(top - Vector((0, 0, length / 2))),
        )  # fmt: skip
        C.uv_sphere(
            self.bm, u_segments=6, v_segments=4, radius=r * 0.75,
            matrix=T(top - Vector((0, 0, length)), None, (1, 1, 1.3)),
        )  # fmt: skip

    def drips(self, center, radius: float, a0: float, a1: float, z: float, count: int, length=(0.15, 0.5)) -> None:
        """A row of drips hanging from a ring edge (radius around center, azimuths a0..a1 in degrees, at z)."""
        c = Vector(center)
        for i in range(count):
            a = math.radians(a0 + (a1 - a0) * (i + self.rnd.uniform(0.2, 0.8)) / count)
            ln = self.rnd.uniform(*length)
            self.drip(c + Vector((math.cos(a) * radius, math.sin(a) * radius, z)), ln, self.rnd.uniform(0.035, 0.06))

    def finish(self, m: Matrix | None = None) -> bpy.types.Object:
        if m is not None:
            transform_bm(self.bm, m)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        cut_below(self.bm, -SINK)
        for f in self.bm.faces:
            f.smooth = True
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        me.materials.append(MATS["glass"])
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

LEG_AZ = (45.0, 135.0, 225.0, 315.0)
BROKEN_AZ = 135.0  # this leg broke off (Lander_leg); the lander slumped onto that corner
FOOT_R = 2.4  # footpads' distance from the middle
STAGE_Z = (0.7, 1.55)  # the descent stage's bottom and top
MODULE_Z = (1.55, 2.6)  # the crew module on it


def slump_matrix() -> Matrix:
    """The slump: SLUMP degrees around the line through the two feet beside the broken leg, so its corner drops."""
    axis = Vector((math.cos(math.radians(BROKEN_AZ - 90)), math.sin(math.radians(BROKEN_AZ - 90)), 0))
    return Matrix.Rotation(math.radians(-SLUMP), 4, axis)


def leg_points(az: float):
    """A leg's mount on the body, its footpad, and the mounts of its two side struts."""
    d = Vector((math.cos(math.radians(az)), math.sin(math.radians(az)), 0))
    side = Vector((-d.y, d.x, 0))
    top = d * 1.2 + Vector((0, 0, 1.45))
    foot = d * FOOT_R + Vector((0, 0, 0.16))
    lows = [d * 1.05 + side * s + Vector((0, 0, 0.78)) for s in (-0.5, 0.5)]
    return d, top, foot, lows


def leg(p: C.Part, top: Vector, foot: Vector, lows: list, broken: float = 1.0) -> None:
    """A landing leg: the primary strut with its shock absorber, two side struts to its middle, the footpad.
    broken < 1: snapped at that fraction of the strut, a jagged stub, the side struts torn short."""
    d = foot - top
    knee = top + d * 0.55
    if broken < 1.0:
        end = top + d * broken
        p.rod(top, end, 0.13, 10, mi=PIPE)
        p.cyl(end + d.normalized() * 0.08, 0.13, 0.16, 6, rot=C.basis(d, Vector((0, 0, 1))), mi=PIPE, r2=0.03)
        for lo in lows:
            p.rod(lo, lo.lerp(knee, 0.3), 0.05, 6, mi=FRAME)
        return
    p.rod(top, top + d * 0.45, 0.13, 10, mi=PIPE)  # shock absorber
    p.rod(top + d * 0.4, foot + Vector((0, 0, 0.05)), 0.085, 10, mi=FRAME)
    p.cyl(top + d * 0.45, 0.16, 0.12, 10, rot=C.basis(d, Vector((0, 0, 1))), mi=HAZ)
    for lo in lows:
        p.rod(lo, knee, 0.05, 6, mi=FRAME)
    p.cyl(foot, 0.4, 0.12, 14, mi=FRAME, r2=0.32)


def lander_body(p: C.Part) -> None:
    """Descent stage (an octagon with four olive tanks between the legs, the engine bell under it), the crew module
    (bone panels, bands, the open hatch on -Y, a stenciled number) with its roof, the mast, dish and beacon."""
    z0, z1 = STAGE_Z
    p.cyl((0, 0, (z0 + z1) / 2), 1.35, z1 - z0, 8, spin=math.radians(22.5), mi=FRAME)
    p.cyl((0, 0, z1 - 0.04), 1.38, 0.08, 8, spin=math.radians(22.5), mi=HAZ)
    for az in (0, 90, 180, 270):
        c = C.polar(az, 1.18, (z0 + z1) / 2 - 0.05)
        p.sphere(c, 0.42, 12, 6, mi=CARGO)
        p.cyl(c, 0.44, 0.06, 12, rot=C.basis(Vector((0, 0, 1)), Vector((1, 0, 0))), mi=FRAME)
    p.cyl((0, 0, z0 - 0.22), 0.52, 0.45, 14, mi=PIPE, r2=0.3, caps=False)  # engine bell
    p.cyl((0, 0, z0 - 0.02), 0.32, 0.06, 12, mi=FRAME)
    m0, m1 = MODULE_Z
    sp = math.radians(22.5)
    p.cyl((0, 0, (m0 + m1) / 2), 1.0, m1 - m0, 8, spin=sp, mi=PANEL)
    for z in (m0 + 0.08, m1 - 0.1):
        p.cyl((0, 0, z), 1.03, 0.07, 8, spin=sp, mi=FRAME)
    p.cyl((0, 0, m1 + 0.17), 1.0, 0.34, 8, spin=sp, mi=PANEL, r2=0.55)
    p.cyl((0, 0, m1 + 0.37), 0.56, 0.06, 8, spin=sp, mi=FRAME)
    # Hatch on the -Y face (apothem 0.924): the dark opening in a hazard frame, the door swung open.
    ap = 1.0 * math.cos(sp)
    hz = (m0 + m1) / 2 - 0.02
    p.box((0, -ap + 0.02, hz), (0.62, 0.06, 0.8), mi=DARK)
    for x in (-0.36, 0.36):
        p.box((x, -ap - 0.01, hz), (0.1, 0.05, 0.92), mi=HAZ)
    for z in (hz - 0.45, hz + 0.45):
        p.box((0, -ap - 0.01, z), (0.82, 0.05, 0.08), mi=HAZ)
    hinge = Vector((-0.4, -ap - 0.05, hz))
    swing = rz(-105)
    p.box(hinge + swing @ Vector((0.33, 0, 0)), (0.66, 0.06, 0.82), rot=swing, mi=PANEL)
    p.box(hinge + swing @ Vector((0.52, -0.05, 0)), (0.06, 0.06, 0.18), rot=swing, mi=FRAME)  # handle
    # A step under the hatch.
    p.box((0, -1.18, z1 - 0.12), (0.7, 0.35, 0.06), mi=FRAME)
    # Stencil: an ID number (bars) on the +X face and an arrow on the -X face.
    for i, h in enumerate((0.3, 0.3, 0.18, 0.3)):
        p.box((ap + 0.006, -0.3 + i * 0.15, hz + 0.1 + (0.3 - h) / 2), (0.01, 0.07, h), mi=FRAME)
    arrow = [(-0.25, -0.05), (0.08, -0.05), (0.08, -0.13), (0.25, 0.0), (0.08, 0.13), (0.08, 0.05), (-0.25, 0.05)]
    p.prism(arrow, -0.005, 0.005, T((-ap - 0.006, 0.0, hz), rz(90) @ ry(90) @ rz(90)), mi=FRAME)
    # Mast, dish and beacon on the roof.
    top = m1 + 0.4
    p.cyl((0.25, 0.2, top + 0.4), 0.05, 0.8, 8, mi=PIPE)
    p.cyl((0.25, 0.2, top + 0.82), 0.08, 0.08, 10, mi=FRAME)
    p.cyl((0.25, 0.2, top + 0.9), 0.065, 0.1, 10, mi=LAMP)
    p.cyl((-0.25, 0.15, top + 0.25), 0.06, 0.4, 8, mi=FRAME)
    dish = C.basis(Vector((-0.5, 0.3, 0.8)), Vector((1, 0, 0)))
    p.cyl(Vector((-0.25, 0.15, top + 0.5)) + dish @ Vector((0, 0, 0.06)), 0.38, 0.14, 14, rot=dish, mi=PANEL, r2=0.08)
    p.box((0.45, -0.35, top + 0.05), (0.3, 0.3, 0.12), mi=FRAME)  # instrument box


def lander() -> bpy.types.Object:
    """Lander: a small survey lander (5 m across its feet, 3.9 m to the beacon) slumped SLUMP degrees onto the corner
    of its broken leg; its feet fused into pools of glass, the broken leg's stub and the corner in a mound of melt,
    one foot lifted on a column of glass, drips of glass on the heat side's lower body and engine bell; the paint
    blistered and heat-blued on +X (the material), the hatch open on -Y."""
    m = slump_matrix()
    p = part("Lander_body")
    lander_body(p)
    for az in LEG_AZ:
        _, top, foot, lows = leg_points(az)
        leg(p, top, foot, lows, 0.32 if az == BROKEN_AZ else 1.0)
    drips = Glass("Lander_drips", 42)
    drips.drips((0, 0, 0), 1.33, -70, 60, STAGE_Z[0] + 0.02, 9, (0.12, 0.45))
    drips.drips((0, 0, 0), 0.5, -60, 70, STAGE_Z[0] - 0.42, 4, (0.08, 0.2))
    body = finish_part(p, m)
    glass = Glass("Lander_glass", 41)
    for az in LEG_AZ:
        _, top, foot, _ = leg_points(az)
        if az == BROKEN_AZ:
            continue
        f = m @ foot
        r = glass.rnd
        # Raise the pool so it reaches the slumped foot: the lifted one stands on a column of glass.
        h = max(0.22, f.z + 0.1)
        glass.mound((f.x, f.y, 0), 0.75 * r.uniform(0.9, 1.15), h, stretch=(1.1, 0.9), turn=r.uniform(0, 180), flat=0.3)
        mt = m @ (top + (foot - top) * 0.8)
        glass.sheath(Vector((f.x, f.y, f.z)), mt, 0.16, 0.1)
    corner = m @ (Vector((math.cos(math.radians(BROKEN_AZ)), math.sin(math.radians(BROKEN_AZ)), 0)) * 1.3)
    stub = m @ leg_points(BROKEN_AZ)[1].lerp(leg_points(BROKEN_AZ)[2], 0.32)
    lift = m @ Vector((corner.x, corner.y, STAGE_Z[0]))
    glass.mound(
        (corner.x * 1.05, corner.y * 1.05, 0), 1.15, lift.z + 0.08, stretch=(1.0, 0.85), turn=BROKEN_AZ, flat=0.25
    )
    glass.sheath((stub.x, stub.y, 0.1), stub, 0.25, 0.14)
    glass.mound((0, 0, 0), 2.6, 0.04, stretch=(1.0, 0.9), turn=20, seg=28, rings=4, flat=0.7, lobes=0.9)
    return join("Lander", [body, drips.finish(m), glass.finish()])


def lander_leg() -> bpy.types.Object:
    """Lander_leg: the broken-off leg lying on the ground (2.6 m): the snapped primary strut with its shock absorber,
    a torn side strut and the footpad, a lump of glass still fused to it."""
    p = part("Lander_leg_body")
    a = Vector((-1.35, 0.0, 0.14))
    b = Vector((1.05, 0.05, 0.2))
    d = b - a
    p.rod(a, a + d * 0.42, 0.13, 10, mi=PIPE)
    p.cyl(a - d.normalized() * 0.06, 0.13, 0.14, 6, rot=C.basis(-d, Vector((0, 0, 1))), mi=PIPE, r2=0.03)
    p.rod(a + d * 0.38, b, 0.085, 10, mi=FRAME)
    p.cyl(a + d * 0.42, 0.16, 0.12, 10, rot=C.basis(d, Vector((0, 0, 1))), mi=HAZ)
    knee = a + d * 0.55
    p.rod(knee, knee + Vector((-0.55, 0.45, 0.1)), 0.05, 6, mi=FRAME)
    p.rod(knee, knee + Vector((-0.35, -0.5, -0.05)), 0.05, 6, mi=FRAME)
    foot = b + Vector((0.12, 0, 0.0))
    p.cyl(foot, 0.4, 0.12, 14, rot=ry(-75), mi=FRAME, r2=0.32)
    body = finish_part(p)
    glass = Glass("Lander_leg_glass", 51)
    glass.mound((foot.x + 0.15, foot.y, 0.0), 0.5, 0.42, stretch=(0.8, 1.2), turn=10, flat=0.2, seg=16, rings=4)
    glass.sheath(foot + Vector((0.05, 0, -0.05)), a + d * 0.75, 0.17, 0.1)
    return join("Lander_leg", [body, glass.finish()])


def lander_pool() -> bpy.types.Object:
    """Lander_pool: a low pool of fused glass (3.6 x 3 m, 5 cm high), glossy and dark, lobed, with a few drops
    beside it. Only looks (no collision)."""
    glass = Glass("Lander_pool_glass", 61)
    glass.mound((0, 0, 0), 1.6, 0.05, stretch=(1.12, 0.92), seg=32, rings=5, flat=0.7, lobes=0.8)
    for x, y, r in ((1.95, 0.9, 0.3), (-1.7, -1.05, 0.22), (0.6, -1.55, 0.18)):
        glass.mound((x, y, 0), r, 0.035, seg=10, rings=2, flat=0.8)
    return join("Lander_pool", [glass.finish()])


BUILDERS = {"Lander": lander, "Lander_leg": lander_leg, "Lander_pool": lander_pool}


# --- layout, preview, renders ---------------------------------------------------------------------------

# The part's layout (Blender: x, y, z rotation in degrees; the way into the area is +Y). Crate and ore spots are
# markers the game places (crate 1.2 x 0.8 m).
LAYOUT = {
    "Lander": (0.4, 0.4, 20),
    "Lander_leg": (-3.6, 2.9, -35),
    "Lander_pool": (2.9, -3.4, 10),
}
CRATE = (-3.9, -2.6, 30)
ORE_SPOTS = [(5.6, 0.9), (-1.2, -6.1), (1.6, 6.2)]
POLE = (1.4, -4.6)


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
    global MATS, MAT_LIST
    MATS = {
        "frame": mat_paint("LanderFrame", GUNMETAL, heat=1.0),
        "hazard": mat_paint("LanderHazard", HAZARD, hazard=True, wear=1.2, heat=1.0),
        "panel": mat_paint("LanderPanel", BONE, wear=0.8, heat=1.0),
        "pipe": mat_paint("LanderSteel", srgb(0.24, 0.23, 0.22), wear=0.6, rust=1.2, roughness=0.45, heat=1.0),
        "lamp": C.mat_emissive("LanderLamp", LAMP_RED, LAMP_STRENGTH),
        "dark": mat_dark("LanderDark"),
        "cargo": mat_paint("LanderCargo", OLIVE, heat=1.0),
        "glass": mat_glass("LanderGlass"),
    }
    MAT_LIST = [MATS[k] for k in ("frame", "hazard", "panel", "pipe", "lamp", "dark", "cargo")]
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
        C.save_blend(OUT / "lander_procedural.blend")
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
            C.save_blend(OUT / "lander_procedural.blend")
            return
    if out:
        C.contact_sheet(out, wip / f"{TAG}_sheet.png", cols=4, tile=512, background=0.02)


if __name__ == "__main__":  # lander_bake.py imports the renders
    main()
