"""Shared geometry for the ore clusters (ores_build.py) and the ore type modules (ore_types/<id>.py).

Node space is Z-up with the origin at the ground contact point in the center of the ore node; crystal shapes are
local (root at the origin, growing along +Z).
"""

import math
import pathlib
import random
import sys
from collections.abc import Callable
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import itertools

import bmesh
from mathutils import Matrix, Vector

from common import T, basis, polar  # noqa: F401  (re-exported for the type modules)


@dataclass
class OreSpec:
    """One ore type's look in Blender. `shape(rnd, u)` makes one crystal (u: 0 smallest .. 1 biggest) as a bmesh,
    root at the origin, growing along +Z. Variants: "a", "b" (ground) and "wall", see ores_build.py."""

    name: str  # ore id, game/ores/types/ore_<id>.tres
    color: tuple  # ore color from the .tres, only for the preview renders (the game owns the crystal material)
    crust: tuple  # muted mineral crust on the rock around the crystal roots (baked into the base texture)
    shape: Callable
    spread: float  # how far a group's crystals root apart
    buddies: tuple  # small offshoots at a crystal's base: (count choices, size factor range)
    wall_sizes: tuple  # crystal size range on the wall cluster
    wall_tilt: float  # max tilt (deg) of the wall cluster's crystals
    variants: dict = field(default_factory=dict)
    # Optional: a dark crystal body with glowing veins in the previews (the game shader draws it, OreType.dark_body).
    dark_body: bool = False
    # Optional: smooth-shaded crystals (round shapes like grape clusters); the default is flat facets.
    smooth: bool = False


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
BASE_CLEARANCE = [
    (0.0, 0.08),
    (0.14, 0.2),
    (0.24, 0.38),
    (0.32, 0.48),
    (1.0, 0.5),
    (1.08, 0.24),
    (1.15, 0.1),
    (2.0, 0.1),
]
DISC_R = 1.33


# --- math helpers (T, basis, polar: common) ---------------------------------------------------------


def table(tab: list, r: float) -> float:
    if r <= tab[0][0]:
        return tab[0][1]
    for (r0, z0), (r1, z1) in itertools.pairwise(tab):
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
    inner = [
        bm.verts.new((cen.x + (p.x - cen.x) * k, cen.y + (p.y - cen.y) * k, h + rise + rnd.uniform(-0.008, 0.012)))
        for p, h in zip(poly, heights)
    ]
    top = [bm.verts.new((p.x, p.y, max(0.012, h - rnd.uniform(0.0, 0.03)))) for p, h in zip(poly, heights)]
    bot = [bm.verts.new((p.x, p.y, bottom)) for p in poly]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i])).smooth = False
        bm.faces.new((top[i], top[j], inner[j], inner[i])).smooth = False
    bm.faces.new(inner).smooth = False


def geode(
    bm: bmesh.types.BMesh, rnd: random.Random, center: Vector, radius: float, height: float, open_dir: float
) -> list:
    """Broken-open geode shell: thick jagged rim (lower on the open side), hollow inside. Returns the inner floor
    and wall points to grow shards from."""
    seg = 14
    profile = [
        (1.0, -0.05, 0.0),
        (1.08, 0.5, 0.03),
        (0.95, 1.0, 0.04),
        (0.72, 0.92, 0.03),
        (0.62, 0.45, 0.02),
        (0.32, 0.1, 0.01),
    ]
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
            ring.append(
                bm.verts.new(center + Vector((math.cos(a) * r, math.sin(a) * r, z + rnd.uniform(-0.015, 0.015))))
            )
        rings.append(ring)
    floor = bm.verts.new(center + Vector((0, 0, 0.07)))
    for a, b in itertools.pairwise(rings):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i])).smooth = False
    for i in range(seg):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % seg], floor)).smooth = False
    return [center + Vector((0, 0, 0.06))] + [v.co.copy() for v in rings[-1]] + [v.co.copy() for v in rings[-2]]
