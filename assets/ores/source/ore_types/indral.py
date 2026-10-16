"""Indral (signature, indigo, fast pulse): chunky gem-like rhombic dodecahedra (garnet habit, edges bevelled by
small trapezohedron faces), half sunk into the rock in clusters of very different sizes."""

import math
import random

import bmesh
from mathutils import Matrix, Vector

from ore_geo import OreSpec, T, append_bm, cut, finish_normals, rand_unit, tilted  # noqa: F401

# Garnet habit: rhombic dodecahedron {110} with its edges bevelled by trapezohedron {211} faces. The gem is the
# intersection of those half-spaces; its corners are precomputed per bevel amount.
FACES = [Vector(v).normalized() for v in ((1, 1, 0), (1, -1, 0), (1, 0, 1), (1, 0, -1), (0, 1, 1), (0, 1, -1))]
FACES += [-n for n in FACES]
BEVELS = [
    Vector((sx * a, sy * b, sz * c)).normalized()
    for a, b, c in ((2, 1, 1), (1, 2, 1), (1, 1, 2))
    for sx in (-1, 1)
    for sy in (-1, 1)
    for sz in (-1, 1)
]
FACE_DIST = 1.0  # {110} faces at distance 1: corners of the plain dodecahedron at sqrt(2) (4-fold) and sqrt(1.5)
EDGE_DIST = 2 / math.sqrt(3)  # where a {211} plane touches the dodecahedron's edge
CORNER_CACHE: dict = {}


def corners(bevel: float) -> list:
    """Corners of the {110} + {211} solid, {211} planes at bevel * EDGE_DIST (1.0: no bevel)."""
    key = round(bevel, 3)
    if key not in CORNER_CACHE:
        planes = [(n, FACE_DIST) for n in FACES] + [(n, EDGE_DIST * key) for n in BEVELS]
        pts = []
        for i in range(len(planes)):
            for j in range(i + 1, len(planes)):
                for k in range(j + 1, len(planes)):
                    (n1, d1), (n2, d2), (n3, d3) = planes[i], planes[j], planes[k]
                    det = n1.dot(n2.cross(n3))
                    if abs(det) < 1e-6:
                        continue
                    p = (n2.cross(n3) * d1 + n3.cross(n1) * d2 + n1.cross(n2) * d3) / det
                    if all(p.dot(n) <= d + 1e-5 for n, d in planes) and all((p - q).length > 1e-4 for q in pts):
                        pts.append(p)
        CORNER_CACHE[key] = pts
    return CORNER_CACHE[key]


def gem(rnd: random.Random, radius: float) -> bmesh.types.BMesh:
    """Garnet gem, about `radius` to its 4-fold corners: twelve big rhombic faces, on the bigger gems the edges
    bevelled into narrow facets, so it reads round from afar but clearly faceted up close."""
    bm = bmesh.new()
    bevel = rnd.choice((0.9, 0.92, 0.94)) if radius > 0.17 else 1.0
    for p in corners(bevel):
        bm.verts.new(p * (radius / math.sqrt(2)))
    bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(2), verts=bm.verts[:], edges=bm.edges[:])
    return bm


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Indigo: one gem ball at a random orientation, sunk a third to a half into the rock; sometimes a smaller gem
    intergrown on its flank."""
    radius = 0.1 + 0.24 * u
    bm = bmesh.new()
    rot = rand_unit(rnd).to_track_quat("Z", "Y").to_matrix() @ Matrix.Rotation(rnd.uniform(0, math.tau), 3, "Z")
    g = gem(rnd, radius)
    append_bm(bm, g, T((0, 0, radius * rnd.uniform(0.15, 0.45)), rot))
    g.free()
    if rnd.random() < 0.25:  # intergrown smaller gem
        r2 = radius * rnd.uniform(0.45, 0.65)
        d = tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(45, 80))
        g = gem(rnd, r2)
        append_bm(
            bm,
            g,
            T(d * radius * 0.85 + Vector((0, 0, radius * 0.1)), rand_unit(rnd).to_track_quat("Z", "Y").to_matrix()),
        )
        g.free()
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="indral",
    color=(0.45, 0.3, 1.0),
    crust=(0.05, 0.04, 0.09),
    shape=shape,
    spread=0.3,
    buddies=((0, 0, 1), (0.3, 0.5)),
    wall_sizes=(0.25, 0.8),
    wall_tilt=40,
    variants={
        "a": dict(
            seed=311,
            groups=[(110, 0.6, 6, (0.25, 1.0), 30), (240, 0.72, 5, (0.2, 0.7), 30), (355, 0.76, 4, (0.1, 0.5), 30)],
        ),
        "b": dict(
            seed=331,
            groups=[(55, 0.64, 5, (0.3, 0.95), 30), (185, 0.68, 6, (0.2, 0.85), 30), (300, 0.76, 4, (0.1, 0.5), 30)],
        ),
        "wall": dict(seed=347, wall=True, count=7),
    },
)
