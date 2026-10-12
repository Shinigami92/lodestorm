"""Ore crystal clusters: per ore type two ground variants and one wall cluster (concept: ores_v1..v4).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/ores/source/ores_build.py wip r1                       # all variants, iso + hero
    tools/blender.sh assets/ores/source/ores_build.py wip r2 cyan_a,green_b iso,miner
    tools/blender.sh assets/ores/source/ores_build.py final
    tools/blender.sh assets/ores/source/ores_build.py sheet                        # only lineups, grid, sheet

Everything it writes goes to tmp/assets/ores/: "wip <tag> [variants] [views]" renders quick previews into
wip/<tag>_<variant>_<view>.png; "final" saves the procedural ores_procedural.blend (that ores_bake.py turns into the
game asset), renders the final previews and a contact sheet (sheet.png).

Each variant is a root empty Ore_<type>_<a|b|wall> holding one rocky base mesh Base_<type>_<variant> (baked later
into a shared texture atlas) and the crystals as separate meshes Crystal_<type>_<n> (numbered per type across its
variants). The crystals only carry geometry: they share the neutral placeholder material "OreCrystal", the game
puts the ore type's glowing material on them (OreType.get_material()). Every crystal mesh has its origin at its
root, so it can be scaled down from there (e.g. when mined out).

Ground variants: origin at the ground contact point in the center of the ore node (deposit radius ~1.35 m). The
miner stands on the node (MinerMount 0.08 m up) with its drill in the center and four legs around it; ore nodes are
rotated randomly while the miner always faces the camera, so the crystals have to clear the legs at every angle:
CLEARANCE is the worst case over all leg angles (from miner_glow_build.py), crystals are scaled down until they fit.
Wall variants: crystals grow toward -Y out of a rock chunk whose flat back lies on the wall plane y = 0; origin at
the bottom center of that back face.

The game camera looks from the +X/-Y diagonal: each type has its own silhouette there.
- cyan: long hexagonal prisms with pyramid tips (some broken), in tall upright groups
- green: chunky intergrown cubes and blocks with chipped corners, low and heavy
- violet: thin sharp blade shards bursting out wide, some from broken-open geodes
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "ores"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import common as C  # noqa: E402
from common import T, basis, polar  # noqa: E402

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
ONLY = ARGV[2].split(",") if len(ARGV) > 2 and ARGV[2] != "all" else None
VIEWS = ARGV[3].split(",") if len(ARGV) > 3 else ["iso", "hero"]

ASSET = "Ores"
TYPES = ("cyan", "green", "violet")
# Ore colors from scenes/mining/ores/*.tres, only for the preview renders (the game owns the crystal material).
ORE_COLOR = {"cyan": (0.2, 0.85, 0.95), "green": (0.35, 0.9, 0.25), "violet": (0.7, 0.3, 0.95)}
# Muted mineral crust on the rock around the crystal roots (baked into the base texture).
CRUST = {"cyan": (0.035, 0.075, 0.08), "green": (0.05, 0.075, 0.035), "violet": (0.065, 0.04, 0.085)}

# --- miner clearance (node space, Z-up, includes the 0.08 m MinerMount) ----------------------------------
# (radius, max height): drill cone in the center, motor and hip ring, upper legs, then the inner edge of the
# lower legs coming down to the feet at r 1.16..1.76. A few cm margin. TBD (playtest) with the final miner.
CLEARANCE = [
    (0.00, 0.10),
    (0.12, 0.30),
    (0.20, 0.47),
    (0.28, 0.55),
    (0.34, 0.66),
    (0.45, 0.78),
    (0.55, 0.86),
    (0.75, 1.00),
    (0.92, 1.10),
    (1.00, 1.03),
    (1.10, 0.79),
    (1.20, 0.55),
    (1.30, 0.31),
]
MAX_HEIGHT = 1.08  # tallest crystal (brief: under ~1.1 m)
MAX_RADIUS = 1.10  # crystals stay inside this radius
# The rock base: low under the drill, low at the rim where the miner's feet stand (top of the deposit disc).
BASE_CLEARANCE = [(0.0, 0.08), (0.14, 0.2), (0.24, 0.38), (0.32, 0.48), (1.0, 0.5), (1.08, 0.24), (1.15, 0.1), (2.0, 0.1)]
DISC_R = 1.33

# --- variants ---------------------------------------------------------------------------------------
# Ground groups: (angle deg, radius, crystal count, size range 0..1, max tilt deg). Angles: 0 = +X, 90 = +Y.
VARIANTS = {
    "cyan_a": dict(seed=11, groups=[(105, 0.62, 6, (0.5, 1.0), 22), (225, 0.72, 3, (0.35, 0.7), 28), (340, 0.72, 3, (0.25, 0.55), 30), (20, 0.2, 2, (0.1, 0.25), 25)]),
    "cyan_b": dict(seed=23, groups=[(45, 0.64, 5, (0.5, 0.95), 24), (165, 0.7, 4, (0.45, 0.85), 26), (280, 0.62, 3, (0.3, 0.6), 30)]),
    "green_a": dict(seed=31, groups=[(115, 0.55, 5, (0.55, 1.0), 18), (245, 0.72, 4, (0.35, 0.75), 22), (5, 0.74, 3, (0.25, 0.55), 22)]),
    "green_b": dict(seed=43, groups=[(60, 0.6, 6, (0.5, 1.0), 20), (205, 0.66, 4, (0.35, 0.8), 22), (310, 0.8, 2, (0.2, 0.4), 22)]),
    "violet_a": dict(seed=53, geodes=[(95, 0.56, 0.52, 8)], groups=[(230, 0.75, 4, (0.45, 0.85), 50), (335, 0.8, 3, (0.3, 0.6), 55)]),
    "violet_b": dict(seed=67, geodes=[(30, 0.64, 0.4, 6), (200, 0.62, 0.42, 6)], groups=[(300, 0.82, 3, (0.35, 0.7), 55)]),
    "cyan_wall": dict(seed=71, wall=True, count=7),
    "green_wall": dict(seed=83, wall=True, count=7),
    "violet_wall": dict(seed=97, wall=True, count=8),
}
LAYOUT_SPACING = 3.4
PREVIEW_GLOW = 1.0
LINEUP_ZOOM = 0.9  # roots are laid out on a grid in the .blend (no cross-occlusion in the AO bake)


def variant_names() -> list[str]:
    return [n for n in VARIANTS if ONLY is None or n in ONLY]


# --- math helpers (T, basis, polar: common) ---------------------------------------------------------


def table(tab: list, r: float) -> float:
    if r <= tab[0][0]:
        return tab[0][1]
    for (r0, z0), (r1, z1) in zip(tab, tab[1:]):
        if r <= r1:
            return z0 + (z1 - z0) * (r - r0) / (r1 - r0)
    return tab[-1][1]


def rand_unit(rnd: random.Random) -> Vector:
    while True:
        v = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))
        if 0.05 < v.length <= 1.0:
            return v.normalized()


def tilted(axis: Vector, away: Vector, deg: float) -> Vector:
    """axis rotated by deg toward the direction `away` (projected perpendicular to axis)."""
    axis = axis.normalized()
    side = away - axis * away.dot(axis)
    if side.length < 1e-4:
        side = Vector((1, 0, 0)) - axis * axis.x
    side.normalize()
    a = math.radians(deg)
    return (axis * math.cos(a) + side * math.sin(a)).normalized()


# --- bmesh helpers ----------------------------------------------------------------------------------


def append_bm(dst: bmesh.types.BMesh, src: bmesh.types.BMesh, m: Matrix | None = None, smooth: bool = False) -> list:
    m = m or Matrix.Identity(4)
    vmap = {v: dst.verts.new(m @ v.co) for v in src.verts}
    new = []
    for f in src.faces:
        nf = dst.faces.new([vmap[v] for v in f.verts])
        nf.smooth = smooth
        new.append(nf)
    return list(vmap.values())


def cut(bm: bmesh.types.BMesh, co: Vector, no: Vector) -> None:
    """Cleave off everything on the +no side of the plane and cap the hole (broken tips, chipped corners)."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=co, plane_no=no, clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)


def max_along(bm: bmesh.types.BMesh, n: Vector) -> float:
    return max(v.co.dot(n) for v in bm.verts)


def finish_normals(bm: bmesh.types.BMesh) -> None:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = False


# --- crystal shapes (local: root at the origin, growing along +Z) ------------------------------------


def shape_prism(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Cyan: long hexagonal prism with uneven face widths, slightly tapered, pyramid tip; tips often broken."""
    length = 0.28 + 0.82 * u
    radius = length * rnd.uniform(0.085, 0.11) + 0.022
    bm = bmesh.new()
    angs = [i / 6 * math.tau + rnd.uniform(-0.13, 0.13) for i in range(6)]
    rads = [radius * rnd.uniform(0.85, 1.1) for _ in range(6)]
    tip = min(radius * rnd.uniform(1.2, 1.8), length * 0.4)

    def ring(z: float, s: float) -> list:
        return [bm.verts.new((math.cos(a) * r * s, math.sin(a) * r * s, z)) for a, r in zip(angs, rads)]

    rings = [ring(-0.12 * length - 0.04, 1.0), ring(length * 0.5, rnd.uniform(0.94, 1.02)), ring(length - tip, rnd.uniform(0.82, 0.92))]
    apex = bm.verts.new((rnd.uniform(-0.25, 0.25) * radius, rnd.uniform(-0.25, 0.25) * radius, length))
    for a, b in zip(rings, rings[1:]):
        for i in range(6):
            bm.faces.new((a[i], a[(i + 1) % 6], b[(i + 1) % 6], b[i]))
    for i in range(6):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % 6], apex))
    bm.faces.new(list(reversed(rings[0])))
    if rnd.random() < 0.45:  # broken tip: slanted fracture below the pyramid
        z = length - tip * rnd.uniform(0.3, 1.6)
        cut(bm, Vector((0, 0, z)), tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(15, 45)))
    if rnd.random() < 0.5:  # chipped edge
        a = rnd.choice(angs)
        d = Vector((math.cos(a), math.sin(a), 0))
        z = rnd.uniform(0.3, 0.8) * (length - tip)
        cut(bm, d * radius * 0.78 + Vector((0, 0, z)), (d + Vector((0, 0, rnd.uniform(-0.4, 0.6)))).normalized())
    finish_normals(bm)
    return bm


def shape_block(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Green: chunky square block with a flat top (fluorite-like), sometimes intergrown with a second cube,
    a corner or two chipped off. Big flat faces keep it reading as blocky from the game camera."""
    edge = 0.14 + 0.3 * u
    bm = bmesh.new()
    sx, sy = edge * rnd.uniform(0.85, 1.15), edge * rnd.uniform(0.85, 1.15)
    sz = edge * rnd.uniform(1.1, 1.9)
    bmesh.ops.create_cube(bm, size=1.0, matrix=T((0, 0, sz / 2 - 0.25 * edge), None, (sx, sy, sz + 0.5 * edge)))
    if rnd.random() < 0.35:  # intergrown twin: a smaller cube on the same axes (or turned 45 deg) stepping out
        s = edge * rnd.uniform(0.5, 0.72)
        corner = Vector((rnd.choice((-1, 1)) * sx * 0.42, rnd.choice((-1, 1)) * sy * 0.42, sz * rnd.uniform(0.25, 0.75)))
        rot = Matrix.Rotation(rnd.choice((0.0, 0.0, math.pi / 4)) + rnd.uniform(-0.08, 0.08), 3, "Z")
        bmesh.ops.create_cube(bm, size=1.0, matrix=T(corner, rot, (s, s, s * rnd.uniform(0.9, 1.25))))
    top = Vector((0, 0, sz))
    for _ in range(rnd.choice((0, 1, 1, 2))):  # chipped corners (octahedral cleavage)
        c = Vector((rnd.choice((-1, 1)) * sx / 2, rnd.choice((-1, 1)) * sy / 2, top.z))
        n = Vector((c.x / sx, c.y / sy, rnd.uniform(0.3, 0.7))).normalized()
        cut(bm, c - n * edge * rnd.uniform(0.12, 0.25), n)
    finish_normals(bm)
    return bm


def shape_shard(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Violet: thin, sharp blade-like shard (rhombic section), slightly bent, needle tip; sometimes snapped."""
    length = 0.25 + 0.8 * u
    width = length * rnd.uniform(0.075, 0.1) + 0.018
    flat = rnd.uniform(0.35, 0.55)
    bm = bmesh.new()
    sec = [(width, 0), (0, width * flat), (-width, 0), (0, -width * flat)]
    bend = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * width * 0.6

    def ring(z: float, s: float, off: Vector) -> list:
        return [bm.verts.new((x * s + off.x, y * s + off.y, z)) for x, y in sec]

    rings = [ring(-0.12 * length - 0.03, 1.0, Vector()), ring(length * 0.4, rnd.uniform(0.85, 1.0), bend), ring(length * 0.78, rnd.uniform(0.45, 0.6), bend * 1.6)]
    apex = bm.verts.new((bend.x * 2.4, bend.y * 2.4, length))
    n = len(sec)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    for i in range(n):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % n], apex))
    bm.faces.new(list(reversed(rings[0])))
    if rnd.random() < 0.25:  # snapped blade
        cut(bm, Vector((0, 0, length * rnd.uniform(0.6, 0.85))), tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(25, 55)))
    finish_normals(bm)
    return bm


SPREAD = {"cyan": 0.17, "green": 0.27, "violet": 0.2}  # how far a group's crystals root apart
SHAPES = {"cyan": shape_prism, "green": shape_block, "violet": shape_shard}
# Small offshoots at the base of a crystal (same object): (count choices, size factor).
BUDDIES = {"cyan": ((0, 1, 1, 2), (0.18, 0.35)), "green": ((0, 1, 1), (0.25, 0.45)), "violet": ((1, 2, 2), (0.25, 0.5))}


# --- rock shapes ------------------------------------------------------------------------------------


def rock_hull(rnd: random.Random, size: Vector, cuts: int = 2, points: int = 16) -> bmesh.types.BMesh:
    """Angular rock: convex hull of jittered points, cleaved by a few flat fracture planes."""
    bm = bmesh.new()
    for _ in range(points):
        d = rand_unit(rnd)
        bm.verts.new(Vector((d.x * size.x, d.y * size.y, d.z * size.z)) * rnd.uniform(0.75, 1.0))
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    loose = list({v for v in res["geom_interior"] + res["geom_unused"] if isinstance(v, bmesh.types.BMVert)})
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    for _ in range(cuts):
        n = rand_unit(rnd)
        cut(bm, n * max_along(bm, n) * rnd.uniform(0.45, 0.8), n)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(4), verts=bm.verts[:], edges=bm.edges[:])
    finish_normals(bm)
    return bm


def clip_poly(poly: list, n: Vector, d: float) -> list:
    """Keep the part of a convex 2D polygon with p.n <= d."""
    out = []
    for i, a in enumerate(poly):
        b = poly[(i + 1) % len(poly)]
        da, db = a.dot(n) - d, b.dot(n) - d
        if da <= 0:
            out.append(a)
        if da * db < 0:
            out.append(a + (b - a) * (da / (da - db)))
    return out


def slab(bm: bmesh.types.BMesh, rnd: random.Random, poly: list, heights: list, bottom: float = -0.05) -> None:
    """Prism from a CCW polygon: top vertices at the given heights, open bottom (buried). The top is a
    faceted dome: an inset inner polygon raised a little, with uneven broken-down edges around it."""
    n = len(poly)
    cen = sum(poly, Vector((0, 0))) / n
    k = rnd.uniform(0.62, 0.8)
    rise = rnd.uniform(0.01, 0.035)
    inner = [bm.verts.new((cen.x + (p.x - cen.x) * k, cen.y + (p.y - cen.y) * k, h + rise + rnd.uniform(-0.008, 0.012))) for p, h in zip(poly, heights)]
    top = [bm.verts.new((p.x, p.y, max(0.012, h - rnd.uniform(0.0, 0.03)))) for p, h in zip(poly, heights)]
    bot = [bm.verts.new((p.x, p.y, bottom)) for p in poly]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i])).smooth = False
        bm.faces.new((top[i], top[j], inner[j], inner[i])).smooth = False
    bm.faces.new(inner).smooth = False


def geode(bm: bmesh.types.BMesh, rnd: random.Random, center: Vector, radius: float, height: float, open_dir: float) -> list:
    """Broken-open geode shell: thick jagged rim (lower on the open side), hollow inside. Returns the inner floor
    and wall points to grow shards from."""
    seg = 14
    profile = [(1.0, -0.05, 0.0), (1.08, 0.5, 0.03), (0.95, 1.0, 0.04), (0.72, 0.92, 0.03), (0.62, 0.45, 0.02), (0.32, 0.1, 0.01)]
    rim = []
    for i in range(seg):
        a = i / seg * 360
        gap = math.cos(math.radians(a - open_dir))  # 1 on the open side
        h = height * (rnd.uniform(0.7, 1.0) - 0.45 * max(0.0, gap) ** 2)
        rim.append(max(h, height * 0.3))
    rings = []
    for pr, pz, jit in profile:
        ring = []
        for i in range(seg):
            a = math.radians(i / seg * 360 + rnd.uniform(-6, 6))
            r = radius * pr + rnd.uniform(-jit, jit) * radius * 2
            z = pz * rim[i] if pz > 0 else pz
            ring.append(bm.verts.new(center + Vector((math.cos(a) * r, math.sin(a) * r, z + rnd.uniform(-0.015, 0.015)))))
        rings.append(ring)
    floor = bm.verts.new(center + Vector((0, 0, 0.07)))
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i])).smooth = False
    for i in range(seg):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % seg], floor)).smooth = False
    return [center + Vector((0, 0, 0.06))] + [v.co.copy() for v in rings[-1]] + [v.co.copy() for v in rings[-2]]


# --- materials --------------------------------------------------------------------------------------


def mat_rock() -> bpy.types.Material:
    """Dark, cracked rock: grey-brown blotches and grain, mineral crust near the crystals (color attribute
    "Crust": rgb = crust color, alpha = amount), dust on top faces, lighter chipped edges (Bevel node),
    dark cracks (Voronoi edges) and cavities (AO)."""
    mat, nt, bsdf = C._new_material("OreRock")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    big = C._noise(nt, 1.4, 6.0, 0.55)
    grain = C._noise(nt, 16.0, 8.0, 0.7)
    col = C._mix_color(nt, big.outputs["Fac"], (0.017, 0.016, 0.015), (0.048, 0.043, 0.038))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", C._ramp(nt, 0.35, 0.7, grain.outputs["Fac"]), 0.35), col, (0.068, 0.062, 0.055))
    # Mineral crust around the crystal roots.
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_type = "GEOMETRY"
    attr.attribute_name = "Crust"
    crust_noise = C._noise(nt, 7.0, 5.0, 0.6)
    crust = C._math(nt, "MULTIPLY", attr.outputs["Alpha"], C._ramp(nt, 0.3, 0.6, crust_noise.outputs["Fac"]))
    col = C._mix_color(nt, crust, col, attr.outputs["Color"])
    # Dust on up-facing surfaces, broken up.
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    dust_noise = C._noise(nt, 3.5, 6.0, 0.6)
    dust = C._math(nt, "MULTIPLY", C._ramp(nt, 0.55, 0.95, sep.outputs["Z"]), C._ramp(nt, 0.4, 0.7, dust_noise.outputs["Fac"]))
    dust = C._math(nt, "MULTIPLY", dust, C._math(nt, "SUBTRACT", 1.0, crust, clamp=True))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", dust, 0.75), col, (0.078, 0.07, 0.06))
    # Chipped edges: convex edges found with the Bevel node (works on low-poly facets, unlike Pointiness).
    edge = C._ramp(nt, 0.015, 0.1, C._bevel_edge(nt, 0.02, geo))
    edge_noise = C._noise(nt, 12.0, 6.0, 0.6)
    edge = C._math(nt, "MULTIPLY", edge, C._ramp(nt, 0.4, 0.6, edge_noise.outputs["Fac"]))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", edge, 0.7), col, (0.105, 0.1, 0.094))
    # Cracks: two layers of Voronoi cell edges, slightly warped.
    warp = nt.nodes.new("ShaderNodeVectorMath")
    warp.operation = "MULTIPLY_ADD"
    warp_noise = C._noise(nt, 2.0, 3.0, 0.5)
    nt.links.new(warp_noise.outputs["Color"], warp.inputs[0])
    warp.inputs[1].default_value = (0.25, 0.25, 0.25)
    nt.links.new(coord.outputs["Object"], warp.inputs[2])
    cracks = None
    for scale, width, weight in ((2.6, 0.025, 1.0), (7.0, 0.02, 0.35)):
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = scale
        nt.links.new(warp.outputs["Vector"], vor.inputs["Vector"])
        c = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.0, width, vor.outputs["Distance"]))
        cracks = c if cracks is None else C._math(nt, "MAXIMUM", cracks, C._math(nt, "MULTIPLY", c, weight))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cracks, 0.85), col, (0.008, 0.007, 0.006))
    # Cavities.
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.2
    cavity = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.3, 0.95, ao.outputs["AO"]))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cavity, 0.75), col, (0.01, 0.009, 0.008))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, grain.outputs["Fac"], 0.74, 0.92)
    rough = C._mix_float(nt, crust, rough, 0.42)
    rough = C._mix_float(nt, dust, rough, 0.95)
    rough = C._mix_float(nt, cracks, rough, 1.0)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bump1 = nt.nodes.new("ShaderNodeBump")
    bump1.inputs["Strength"].default_value = 0.7
    bump1.inputs["Distance"].default_value = 0.015
    nt.links.new(C._math(nt, "SUBTRACT", 1.0, cracks), bump1.inputs["Height"])
    fine = C._noise(nt, 45.0, 6.0, 0.7)
    bump2 = nt.nodes.new("ShaderNodeBump")
    bump2.inputs["Strength"].default_value = 0.3
    bump2.inputs["Distance"].default_value = 0.004
    nt.links.new(fine.outputs["Fac"], bump2.inputs["Height"])
    nt.links.new(bump1.outputs["Normal"], bump2.inputs["Normal"])
    nt.links.new(bump2.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def mat_crystal_placeholder() -> bpy.types.Material:
    """Neutral stand-in on every crystal; the game replaces it (material_override)."""
    mat, _nt, bsdf = C._new_material("OreCrystal")
    bsdf.inputs["Base Color"].default_value = (0.55, 0.57, 0.6, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.25
    return mat


def mat_crystal_preview(typ: str) -> bpy.types.Material:
    """Like OreType.get_material() (albedo = emission = ore color, roughness 0.2), but dimmer than its energy 2.5:
    Cycles + AgX burns that to white and hides the facets (renders only)."""
    mat = C.mat_emissive(f"PreviewOre_{typ}", ORE_COLOR[typ], PREVIEW_GLOW)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Base Color"].default_value = (*(c * 0.3 for c in ORE_COLOR[typ]), 1.0)
    return mat


# --- assembly ---------------------------------------------------------------------------------------

COUNTERS = {t: 0 for t in TYPES}


class Variant:
    def __init__(self, name: str, spec: dict, root: bpy.types.Object):
        self.name, self.spec, self.root = name, spec, root
        self.typ, self.var = name.split("_")
        self.rnd = random.Random(spec["seed"])
        self.base = bmesh.new()
        self.roots: list[Vector] = []  # crystal roots, for the crust and the rubble
        self.crystals: list[bpy.types.Object] = []
        self.ground = not spec.get("wall")

    # Crystals.

    def crystal(self, root: Vector, direction: Vector, u: float) -> bpy.types.Object | None:
        rnd, typ = self.rnd, self.typ
        bm = bmesh.new()
        spin = rand_unit(rnd)
        append_bm(bm, SHAPES[typ](rnd, u), T(root, basis(direction, spin)))
        counts, (f0, f1) = BUDDIES[typ]
        for _ in range(rnd.choice(counts)):
            off = tilted(direction, rand_unit(rnd), 90) * rnd.uniform(0.04, 0.12) * (0.5 + u)
            d = tilted(direction, off, rnd.uniform(25, 55))
            append_bm(bm, SHAPES[typ](rnd, u * rnd.uniform(f0, f1)), T(root + off - direction * 0.02, basis(d, rand_unit(rnd))))
        if self.ground and not self.fit(bm, root):
            bm.free()
            return None
        COUNTERS[typ] += 1
        name = f"Crystal_{typ}_{COUNTERS[typ]}"
        bmesh.ops.translate(bm, verts=bm.verts[:], vec=-root)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(name, me)
        obj.location = root
        C.link(obj, self.root)
        C.assign(obj, CRYSTAL)
        self.crystals.append(obj)
        self.roots.append(root)
        return obj

    def fit(self, bm: bmesh.types.BMesh, root: Vector) -> bool:
        """Scale the crystal down around its root until it clears the miner (CLEARANCE, MAX_*)."""
        orig = [v.co.copy() for v in bm.verts]
        s = 1.0
        while s > 0.3:
            ok = True
            for v, co in zip(bm.verts, orig):
                p = root + (co - root) * s
                r = math.hypot(p.x, p.y)
                if p.z > 0.04 and (r > MAX_RADIUS or p.z > min(MAX_HEIGHT, table(CLEARANCE, r))):
                    ok = False
                    break
            if ok:
                for v, co in zip(bm.verts, orig):
                    v.co = root + (co - root) * s
                return True
            s *= 0.94
        return False

    def surface(self, x: float, y: float) -> float:
        bvh = BVHTree.FromBMesh(self.base)
        hit = bvh.ray_cast(Vector((x, y, 3.0)), Vector((0, 0, -1)))
        return hit[0].z if hit[0] is not None else 0.0

    def on_surface(self, p: Vector) -> Vector:
        """Crystal root slightly inside the rock under (ground) or behind (wall) p."""
        if self.ground:
            return Vector((p.x, p.y, self.surface(p.x, p.y) - 0.04))
        hit = BVHTree.FromBMesh(self.base).ray_cast(Vector((p.x, -3.0, p.z)), Vector((0, 1, 0)))
        return hit[0] + Vector((0, 0.05, 0)) if hit[0] is not None else p

    def group(self, center: Vector, n: int, size: tuple, tilt: float, spread: float = 0.2, up: Vector | None = None) -> None:
        rnd = self.rnd
        up = up or Vector((0, 0, 1))
        sizes = sorted((rnd.uniform(*size) for _ in range(n - 1)), reverse=True)
        sizes = [size[1]] + sizes
        outward = Vector((center.x, center.y, 0))
        for k, u in enumerate(sizes):
            if k == 0:
                off = Vector()
            else:
                off = tilted(up, rand_unit(rnd), 90) * rnd.uniform(0.35, 1.0) * spread
            root = center + off
            root = self.on_surface(root)
            away = off if off.length > 1e-3 else rand_unit(rnd)
            t = rnd.uniform(0, 8) if k == 0 else rnd.uniform(0.35, 1.0) * tilt
            d = tilted(up, away, t)
            if self.ground and outward.length > 0.05:
                d = tilted(d, outward, rnd.uniform(3, 9))
            self.crystal(root, d, u)

    # Rock.

    def rock(self, center: Vector, size: Vector, cuts: int = 2, clamp: bool = True, tilt: float = 0.35, points: int = 16) -> None:
        rnd = self.rnd
        bm = rock_hull(rnd, size, cuts, points)
        m = T(center, Matrix.Rotation(rnd.uniform(0, math.tau), 3, "Z") @ Matrix.Rotation(rnd.uniform(-tilt, tilt), 3, "X"))
        verts = append_bm(self.base, bm, m)
        bm.free()
        if clamp and self.ground:  # squash vertically until it clears the miner
            s = 1.0
            for v in verts:
                if v.co.z > 0.02:
                    lim = table(BASE_CLEARANCE, math.hypot(v.co.x, v.co.y))
                    s = min(s, lim / v.co.z)
            for v in verts:
                v.co.z = v.co.z * s if v.co.z > 0 else v.co.z

    def foundation(self, heave: list) -> None:
        """Cracked rock pad over the deposit disc: Voronoi cells as low slabs with gaps, heaved up and tilted
        where crystals push through (heave: list of (center, strength))."""
        rnd = self.rnd
        seeds: list[Vector] = []
        while len(seeds) < 15:
            p = Vector((rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2)))
            if p.length < 1.2 and all((p - q).length > 0.42 for q in seeds):
                seeds.append(p)
        disc = [Vector((math.cos(a) * DISC_R, math.sin(a) * DISC_R)) for a in (i / 22 * math.tau for i in range(22))]
        for i, s in enumerate(seeds):
            poly = disc[:]
            for j, q in enumerate(seeds):
                if i != j:
                    n = (q - s).normalized()
                    poly = clip_poly(poly, n, n.dot((s + q) / 2) - rnd.uniform(0.012, 0.03))
            if len(poly) < 3:
                continue
            poly = [p * rnd.uniform(0.9, 1.03) if p.length > DISC_R - 0.1 else p for p in poly]
            cen = sum(poly, Vector((0, 0))) / len(poly)
            near = min(((cen - hc.xy).length for hc, _hs in heave), default=9.0)
            if cen.length > 0.55 and near > 0.5 and rnd.random() < 0.3:
                continue  # missing plate: the ground shows through
            h0 = rnd.uniform(0.03, 0.09)
            grad = Vector((rnd.uniform(-0.1, 0.1), rnd.uniform(-0.1, 0.1)))
            for hc, hs in heave:
                d = (cen - hc.xy).length
                if d < 0.75:
                    w = (1 - d / 0.75) ** 2
                    h0 += 0.16 * hs * w
                    grad += (hc.xy - cen).normalized() * 0.45 * hs * w
            heights = []
            for p in poly:
                h = h0 + grad.dot(p - cen) + rnd.uniform(-0.01, 0.01)
                heights.append(max(0.02, min(h, table(BASE_CLEARANCE, p.length))))
            slab(self.base, rnd, poly, heights)

    def rubble(self) -> None:
        """Rock chunks hiding the crystal roots, and loose bits over the pad."""
        rnd = self.rnd
        for root in self.roots:
            for _ in range(rnd.choice((0, 1, 1, 2))):
                off = tilted(Vector((0, 0, 1)), rand_unit(rnd), 90) * rnd.uniform(0.05, 0.14)
                s = rnd.uniform(0.07, 0.15)
                self.rock(root + off + Vector((0, 0, rnd.uniform(0.0, 0.04))), Vector((s, s * rnd.uniform(0.7, 1.2), s * rnd.uniform(0.5, 0.9))), 1, points=11)
        if not self.ground:
            return
        for _ in range(9):
            p = polar(rnd.uniform(0, 360), rnd.uniform(0.35, 1.2))
            s = rnd.uniform(0.035, 0.09)
            self.rock(p + Vector((0, 0, self.surface(p.x, p.y) - s * 0.2)), Vector((s, s * rnd.uniform(0.7, 1.3), s * rnd.uniform(0.4, 0.8))), 1, points=9)

    def mound(self, center: Vector, spread: float) -> None:
        """Upheaved angular blocks around a crystal group: the crystals burst out of jagged rock."""
        rnd = self.rnd
        for k in range(rnd.choice((3, 4, 5))):
            p = center + polar(k * 360 / 4.5 + rnd.uniform(-30, 30), rnd.uniform(0.6, 1.3) * spread + 0.08)
            s = rnd.uniform(0.14, 0.28)
            p.z = self.surface(p.x, p.y) + s * rnd.uniform(-0.1, 0.25)
            self.rock(p, Vector((s, s * rnd.uniform(0.6, 1.1), s * rnd.uniform(0.45, 0.85))), 2, tilt=0.6, points=13)

    def crust(self) -> None:
        """Color attribute "Crust" on the base: mineral color near the crystal roots and inside geodes."""
        me = self.base_obj.data
        attr = me.color_attributes.new("Crust", "FLOAT_COLOR", "POINT")
        col = CRUST[self.typ]
        loc = self.base_obj.location
        for i, v in enumerate(me.vertices):
            p = v.co + loc
            d = min(((p - r).length for r in self.roots), default=9.0)
            w = max(0.0, 1.0 - d / 0.45) ** 1.5
            for c, gr in self.geodes:  # inside the geode
                if (p.xy - c.xy).length < gr * 0.8 and p.z > 0.0:
                    w = max(w, 0.9)
            attr.data[i].color = (*col, min(1.0, w))

    def finish_base(self) -> None:
        name = f"Base_{self.typ}_{self.var}"
        me = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.base, verts=self.base.verts[:], dist=1e-5)
        self.base.to_mesh(me)
        self.base.free()
        for p in me.polygons:
            p.use_smooth = False
        obj = bpy.data.objects.new(name, me)
        C.link(obj, self.root)
        C.assign(obj, ROCK)
        self.base_obj = obj

    # Builders.

    def build_ground(self) -> None:
        spec, rnd = self.spec, self.rnd
        geodes = spec.get("geodes", [])
        heave = [(polar(a, r), 1.0) for a, r, *_ in spec["groups"]] + [(polar(a, r), 0.6) for a, r, *_ in geodes]
        self.foundation(heave)
        shard_sites = []
        for a, r, gr, n in geodes:
            c = polar(a, r, 0.02)
            height = min(table(BASE_CLEARANCE, r) * 0.85, 0.42)
            pts = geode(self.base, rnd, c, gr, height, a + 180 + rnd.uniform(-40, 40))  # open toward the node center
            shard_sites.append((c, gr, n, pts))
        self.geodes = [(c, gr) for c, gr, _n, _pts in shard_sites]
        for a, r, n, size, tilt in spec["groups"]:
            center = polar(a, r)
            center.z = self.surface(center.x, center.y)
            self.group(center, n, size, tilt, spread=SPREAD[self.typ])
            self.mound(center, SPREAD[self.typ])
        for c, gr, n, pts in shard_sites:
            sizes = sorted((rnd.uniform(0.4, 0.95) for _ in range(n)), reverse=True)
            for k, u in enumerate(sizes):
                p = pts[0] if k == 0 else rnd.choice(pts[1:])
                root = p + (c - p) * 0.15 - Vector((0, 0, 0.03))
                away = (p - c) if (p - c).length > 0.02 else rand_unit(rnd)
                d = tilted(Vector((0, 0, 1)), away, rnd.uniform(10, 42) if k else rnd.uniform(0, 12))
                self.crystal(root, d, u)
        self.chips()
        self.rubble()
        self.finish_base()
        self.crust()

    def chips(self) -> None:
        """A few tiny loose crystals lying around the pad (one object)."""
        rnd = self.rnd
        bm = bmesh.new()
        first = None
        for _ in range(5):
            p = polar(rnd.uniform(0, 360), rnd.uniform(0.75, 1.0))
            p.z = self.surface(p.x, p.y) - 0.01
            if first is None:
                first = p.copy()
            d = tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(40, 75))
            append_bm(bm, SHAPES[self.typ](rnd, 0.0), T(p, basis(d, rand_unit(rnd)), (0.35, 0.35, 0.35)))
        COUNTERS[self.typ] += 1
        name = f"Crystal_{self.typ}_{COUNTERS[self.typ]}"
        bmesh.ops.translate(bm, verts=bm.verts[:], vec=-first)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(name, me)
        obj.location = first
        C.link(obj, self.root)
        C.assign(obj, CRYSTAL)
        self.crystals.append(obj)

    def build_wall(self) -> None:
        """Rock chunk with a flat back on the wall plane (y = 0) and a flat bottom; crystals grow out of its
        front toward -Y, fanning up and sideways."""
        rnd = self.rnd
        chunks = [((0.0, -0.26, 0.68), (0.85, 0.45, 0.7)), ((-0.6, -0.16, 0.32), (0.48, 0.34, 0.4)), ((0.55, -0.18, 1.05), (0.45, 0.32, 0.4)), ((0.45, -0.2, 0.3), (0.4, 0.32, 0.33))]
        for c, s in chunks:
            bm = rock_hull(rnd, Vector(s), 2, 18)
            append_bm(self.base, bm, T(c, Matrix.Rotation(rnd.uniform(-0.3, 0.3), 3, "Y")))
            bm.free()
        cut(self.base, Vector((0, 0, 0)), Vector((0, 1, 0)))  # flat back on the wall
        cut(self.base, Vector((0, 0, 0)), Vector((0, 0, -1)))  # flat bottom
        bmesh.ops.dissolve_limit(self.base, angle_limit=math.radians(2), verts=self.base.verts[:], edges=self.base.edges[:])
        finish_normals(self.base)
        bvh = BVHTree.FromBMesh(self.base)
        self.geodes = []
        sizes = {"cyan": (0.3, 0.8), "green": (0.15, 0.55), "violet": (0.35, 0.85)}[self.typ]
        tilt = {"cyan": 30, "green": 35, "violet": 50}[self.typ]
        # One big group in the middle, a few smaller around it.
        sites = [(0.05, 0.62, self.spec["count"] - 3, sizes[1]), (-0.5, 0.35, 2, sizes[0] + 0.15), (0.48, 0.98, 1, sizes[0])]
        for x, z, n, umax in sites:
            hit = bvh.ray_cast(Vector((x, -3, z)), Vector((0, 1, 0)))
            if hit[0] is None:
                continue
            center = hit[0] + Vector((0, 0.05, 0))
            out = (hit[1] * 0.3 + Vector((0, -0.45, 0.85))).normalized()  # out of the face, mostly upward
            self.group(center, n, (sizes[0], umax), tilt, spread=SPREAD[self.typ] + 0.05, up=out)
        self.rubble()
        self.finish_base()
        self.crust()


def build_variant(name: str, index: int) -> Variant:
    typ, var = name.split("_")
    root = C.asset_root(f"Ore_{typ}_{var}")
    col = TYPES.index(typ)
    row = ("a", "b", "wall").index(var)
    root.location = ((col - 1) * LAYOUT_SPACING, (row - 1) * LAYOUT_SPACING, 0)
    root["layout_offset"] = list(root.location)  # zero it before export
    v = Variant(name, VARIANTS[name], root)
    if v.ground:
        v.build_ground()
    else:
        v.build_wall()
    return v


def tri_count(obj: bpy.types.Object) -> int:
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def report(variants: list[Variant]) -> None:
    for v in variants:
        crys = sum(tri_count(o) for o in v.crystals)
        base = tri_count(v.base_obj)
        top = 0.0
        rad = 0.0
        for o in v.crystals:
            for vert in o.data.vertices:
                p = vert.co + o.location
                if p.z > 0.04:
                    top = max(top, p.z)
                    rad = max(rad, math.hypot(p.x, p.y))
        dims = v.base_obj.dimensions
        print(
            f"STATS {v.root.name}: base {base} tris, {len(v.crystals)} crystal objects {crys} tris, total {base + crys}; "
            f"crystal top {top:.2f} m, crystal radius {rad:.2f} m, base dims {dims.x:.2f} x {dims.y:.2f} x {dims.z:.2f}"
        )


# --- previews ---------------------------------------------------------------------------------------


def variant_objects(v: Variant) -> list:
    return [v.root] + list(v.root.children_recursive)


def solo(variants: list[Variant], keep: Variant | None) -> None:
    """Show only `keep` (moved to the origin for the shared preview lights), or all at their layout spots."""
    for v in variants:
        hide = keep is not None and v is not keep
        for o in variant_objects(v):
            o.hide_render = hide
        v.root.location = (0, 0, 0) if v is keep else Vector(v.root["layout_offset"])


def set_preview_materials(variants: list[Variant], preview: bool) -> None:
    for v in variants:
        for o in v.crystals:
            C.assign(o, mat_crystal_preview(v.typ) if preview else CRYSTAL)


def backdrop(show: bool) -> None:
    """Cliff stand-in behind the wall clusters (preview only)."""
    obj = bpy.data.objects.get("PreviewCliff")
    if obj is None:
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        for c in obj.users_collection:
            c.objects.unlink(obj)
        C.link(obj, None, "Preview")
        obj.name = "PreviewCliff"
        obj.scale = (5.0, 1.0, 3.2)
        obj.location = (0, 0.5, 1.6)
        C.assign(obj, bpy.data.materials["PreviewRock"])
    obj.hide_render = not show


def import_miner(yaw_deg: float) -> list:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets" / "miners" / "miner_glow.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        C.collection("Preview").objects.link(o)
    top = [o for o in new if o.parent is None]
    for o in top:
        o.location = (0, 0, 0.08)  # MinerMount
        o.rotation_mode = "XYZ"
        o.rotation_euler = (0, 0, math.radians(yaw_deg))
    return new


def render_view(path: pathlib.Path, v: Variant, view: str, samples: int, size: int) -> None:
    tz = 0.35 if v.ground else 0.65
    if view == "iso":
        C.render(path, "iso", samples, size, target=(0, -0.3 * (not v.ground), tz), zoom=0.4)
    elif view == "hero":
        C.render(path, "hero", samples, size, target=(0, -0.3 * (not v.ground), tz + 0.07), zoom=0.48)
    elif view == "top":
        C.render(path, "iso", samples, size, target=(0, 0, 0.3), zoom=0.4)
        cam = bpy.context.scene.camera
        cam.location = (0, 0, 7)
        cam.rotation_euler = (0, 0, 0)
        bpy.ops.render.render(write_still=True)
    elif view in ("miner", "minerhero"):
        new = import_miner(25.0 if v.var == "a" else 70.0)
        if view == "miner":
            C.render(path, "iso", samples, size, target=(0, 0, 1.0), zoom=0.62)
        else:
            C.render(path, "hero", samples, size, target=(0, 0, 0.9), zoom=0.75)
        for o in new:
            bpy.data.objects.remove(o)
    else:
        raise ValueError(view)


def lineup(variants: list[Variant], shown: list[Variant], path: pathlib.Path, samples: int, size: int, zoom: float, target_z: float = 0.4) -> None:
    """The `shown` variants side by side along the screen's horizontal (same depth), iso camera."""
    right = Vector((1, 1, 0)).normalized()
    solo(variants, None)
    for v in variants:
        for o in variant_objects(v):
            o.hide_render = v not in shown
    variants = shown
    n = len(variants)
    for k, v in enumerate(variants):
        v.root.location = right * (k - (n - 1) / 2) * 3.0
    C.render(path, "iso", samples, size, target=(0, 0, target_z), zoom=zoom)


def grid_view(variants: list[Variant], path: pathlib.Path, samples: int, size: int) -> None:
    """All nine at their layout spots from roughly the game's camera distance."""
    solo(variants, None)
    C.render(path, "iso", samples, size, target=(0, 0, 0.3), zoom=1.45)


# --- main -------------------------------------------------------------------------------------------


def main() -> None:
    global ROCK, CRYSTAL
    C.reset(ASSET)
    ROCK = mat_rock()
    CRYSTAL = mat_crystal_placeholder()
    variants = [build_variant(n, i) for i, n in enumerate(variant_names())]
    report(variants)
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(1.7, 1.7, 0.0))
    backdrop(False)
    if MODE in ("final", "sheet"):
        if MODE == "final":
            bpy.context.preferences.filepaths.save_version = 0
            C.save_blend(OUT / "ores_procedural.blend")
        set_preview_materials(variants, True)
        shots = []
        for v in variants if MODE == "final" else []:
            solo(variants, v)
            backdrop(not v.ground)
            views = ["iso", "hero", "miner"] if v.ground else ["iso", "hero"]
            for view in views:
                p = OUT / f"render_{v.name}_{view}.png"
                render_view(p, v, view, 64, 768)
                shots.append(p)
        backdrop(False)
        bpy.data.objects["PreviewFigure"].location = (4.6, 4.6, 0)
        for t in TYPES:
            vs = [v for v in variants if v.typ == t]
            lineup(variants, vs, OUT / f"render_lineup_{t}.png", 64, 1024, LINEUP_ZOOM)
        grid_view(variants, OUT / "render_game_distance.png", 64, 1024)
        order = []
        for t in TYPES:
            order += [OUT / f"render_{t}_{x}.png" for x in ("a_iso", "b_iso", "wall_iso", "a_hero", "b_hero", "wall_hero", "a_miner", "b_miner")]
        order += [OUT / f"render_lineup_{t}.png" for t in TYPES] + [OUT / "render_game_distance.png"]
        C.contact_sheet(order, OUT / "sheet.png", 8, 384)
    else:
        set_preview_materials(variants, True)
        for v in variants:
            solo(variants, v)
            backdrop(not v.ground)
            for view in VIEWS:
                if view in ("lineup", "grid"):
                    continue
                if view.startswith("miner") and not v.ground:
                    continue
                render_view(OUT / "wip" / f"{TAG}_{v.name}_{view}.png", v, view, 24, 512)
        backdrop(False)
        if "lineup" in VIEWS:
            for t in TYPES:
                vs = [v for v in variants if v.typ == t]
                if vs:
                    lineup(variants, vs, OUT / "wip" / f"{TAG}_lineup_{t}.png", 24, 768, LINEUP_ZOOM)
        if "grid" in VIEWS:
            grid_view(variants, OUT / "wip" / f"{TAG}_grid.png", 24, 768)


main()
