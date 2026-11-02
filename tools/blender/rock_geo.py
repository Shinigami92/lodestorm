"""Geometry helpers of the faceted rock kits (rocks, the ash, frost, glass and salt kits, meteor, vein, lairs): convex
chunks from jittered points (`hull`, `chunk`, `column`), planar cuts and shaving, chip and crack cutters, and the
boolean union/difference through modifiers on objects in the "Work" collection. Every random choice draws from the
`random.Random` passed in, so a kit's pieces come out the same in every run.

A kit imports what it uses (`from rock_geo import chunk, cut, hull`); a kit that changes one of them (its own `place`,
say) keeps its own copy of every helper that calls it too, since a helper here calls the others in this module.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
from common import T, rx, rz


def rand_rot(rnd: random.Random, tilt: float, spin: float = 180.0) -> Matrix:
    """Random spin around Z, then a lean of up to `tilt` degrees in a random direction."""
    return rz(rnd.uniform(0, 360)) @ rx(rnd.uniform(-tilt, tilt)) @ rz(rnd.uniform(-spin, spin))


def rand_dir(rnd: random.Random, min_z: float = -1.0, max_z: float = 1.0) -> Vector:
    while True:
        v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1)))
        if v.length > 1e-3:
            v.normalize()
            if min_z <= v.z <= max_z:
                return v


def box_points(rnd: random.Random, size, jitter: float = 0.14, extra: int = 6, bulge: float = 0.12) -> list:
    """Corners of a box (centered) jittered, plus a few points pushed out of its faces (extra facets)."""
    sx, sy, sz = size
    pts = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            for cz in (-1, 1):
                j = Vector((rnd.uniform(-1, 1) * sx, rnd.uniform(-1, 1) * sy, rnd.uniform(-1, 1) * sz)) * jitter
                pts.append(Vector((cx * sx / 2, cy * sy / 2, cz * sz / 2)) + j)
    for _ in range(extra):
        axis = rnd.randrange(3)
        p = [rnd.uniform(-0.4, 0.4) * s for s in size]
        p[axis] = rnd.choice((-1, 1)) * size[axis] / 2 * (1 + rnd.uniform(0, bulge))
        pts.append(Vector(p))
    return pts


def prism_points(
    rnd: random.Random, rx_: float, ry_: float, h: float, sides: int = 6, taper: float = 0.85, jitter: float = 0.12
) -> list:
    """Column from z = 0 to h with an irregular polygon cross-section (top scaled by taper)."""
    a0 = rnd.uniform(0, math.tau)
    pts = []
    for i in range(sides):
        a = a0 + (i + rnd.uniform(-0.25, 0.25)) / sides * math.tau
        r = 1 + rnd.uniform(-jitter, jitter)
        pts.append(Vector((math.cos(a) * rx_ * r, math.sin(a) * ry_ * r, 0.0)))
        t = taper * (1 + rnd.uniform(-jitter, jitter))
        pts.append(Vector((math.cos(a) * rx_ * r * t, math.sin(a) * ry_ * r * t, h * (1 + rnd.uniform(-0.04, 0.04)))))
    return pts


def hull(points: list) -> bmesh.types.BMesh:
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in points]
    res = bmesh.ops.convex_hull(bm, input=verts, use_existing_faces=False)
    kill = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def place(bm: bmesh.types.BMesh, m: Matrix) -> bmesh.types.BMesh:
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    return bm


def support(bm: bmesh.types.BMesh, direction) -> Vector:
    d = Vector(direction).normalized()
    return max((v.co.copy() for v in bm.verts), key=lambda p: p.dot(d))


def fill_holes(bm: bmesh.types.BMesh) -> None:
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)


def cut(bm: bmesh.types.BMesh, normal, keep: float = 0.8, at: float | None = None) -> None:
    """Shave off everything beyond a plane: a fracture facet. The plane sits at `keep` (0..1) of the extent
    along `normal`, or at the absolute offset `at`."""
    n = Vector(normal).normalized()
    ds = [v.co.dot(n) for v in bm.verts]
    off = at if at is not None else min(ds) + (max(ds) - min(ds)) * keep
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=n * off, plane_no=n, clear_outer=True)
    fill_holes(bm)


def shave(bm: bmesh.types.BMesh, rnd: random.Random, n: int, keep=(0.72, 0.9), min_z: float = -0.25) -> None:
    for _ in range(n):
        cut(bm, rand_dir(rnd, min_z=min_z), rnd.uniform(*keep))


def chunk(
    rnd: random.Random, size, cuts: int = 3, m: Matrix | None = None, keep=(0.72, 0.9), **kw
) -> bmesh.types.BMesh:
    bm = hull(box_points(rnd, size, **kw))
    shave(bm, rnd, cuts, keep)
    return place(bm, m) if m is not None else bm


def column(
    rnd: random.Random,
    r: float,
    h: float,
    sides: int = 6,
    depth: float | None = None,
    taper: float = 0.85,
    top_tilt: float = 0.5,
    cuts: int = 1,
    m: Matrix | None = None,
) -> bmesh.types.BMesh:
    """Columnar block with a slanted, fractured top."""
    bm = hull(prism_points(rnd, r, depth if depth is not None else r * rnd.uniform(0.75, 1.0), h, sides, taper))
    a = rnd.uniform(0, math.tau)
    cut(bm, (math.cos(a) * top_tilt, math.sin(a) * top_tilt, 1.0), rnd.uniform(0.86, 0.95))
    for _ in range(cuts):
        a = rnd.uniform(0, math.tau)
        cut(bm, (math.cos(a), math.sin(a), rnd.uniform(-0.2, 0.6)), rnd.uniform(0.8, 0.92))
    return place(bm, m) if m is not None else bm


def chip_cutter(rnd: random.Random, target: bmesh.types.BMesh, direction, size: float) -> bmesh.types.BMesh:
    """A small rotated block centered on the target's outermost point in `direction`: bites a chip out of a ridge."""
    p = support(target, direction)
    return chunk(rnd, (size, size * rnd.uniform(0.7, 1.1), size * rnd.uniform(0.6, 1.0)), 1, T(p, rand_rot(rnd, 60)))


def crack_cutter(
    rnd: random.Random, center, length: float, depth: float, width: float = 0.05, rot: Matrix | None = None
) -> bmesh.types.BMesh:
    """Thin slab (length along X, depth along Y, width along Z) that notches a crack into a face."""
    pts = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            for cz in (-1, 1):
                w = width * (rnd.uniform(0.4, 1.0) if cy > 0 else rnd.uniform(1.0, 1.8))  # wider at the mouth (-Y)
                pts.append(Vector((cx * length / 2 * rnd.uniform(0.85, 1.0), cy * depth / 2, cz * w / 2)))
    return place(hull(pts), T(center, rot))


def work_collection(name: str) -> bpy.types.Collection:
    coll = bpy.data.collections.new(name)
    C.collection("Work").children.link(coll)
    return coll


def bm_to_obj(bm: bmesh.types.BMesh, name: str, coll: str = "Work") -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    C.collection(coll).objects.link(obj)
    return obj


def add_boolean(base: bpy.types.Object, op: str, coll: bpy.types.Collection) -> None:
    mod = base.modifiers.new(op.title(), "BOOLEAN")
    mod.operation = op
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    try:
        mod.solver = "MANIFOLD"
    except TypeError:
        mod.solver = "EXACT"


def uv_to_xy(u: float, v: float) -> Vector:
    s = math.sqrt(0.5)
    return Vector((u * s + v * s, u * s - v * s, 0.0))
