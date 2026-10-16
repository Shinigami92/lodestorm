"""Halcyne (mid, sky blue, flicker): tight bundles of thick flat-topped polygonal columns of different heights,
like basalt organ pipes in miniature."""

import math
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import OreSpec, T, clip_poly, cut, finish_normals, rand_unit, tilted  # noqa: F401


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Sky blue: a bundle of thick polygonal columns (jittered hex lattice cut into 5..7-sided cells with thin gaps),
    flat tops, the middle ones tallest and the rim stepping down, a few tops slanted or snapped off. Reads as one
    squat, flat-topped pillar mass from the game camera, never as single pointed crystals."""
    height = 0.26 + 0.6 * u
    d = rnd.uniform(0.1, 0.12) * (0.85 + 0.3 * u)  # column spacing
    rings = 1 if u < 0.55 else 2
    centers = []
    for q in range(-rings, rings + 1):
        for r in range(-rings, rings + 1):
            if abs(q + r) > rings:
                continue
            p = Vector(((q + r * 0.5) * d, r * math.sqrt(3) / 2 * d))
            centers.append(p + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * d * 0.14)
    if rings == 2:  # drop a few rim columns so the bundle outline is ragged
        rim = [c for c in centers if c.length > d * 1.5]
        for c in rnd.sample(rim, rnd.randint(5, 8)):
            centers.remove(c)
    rot = rnd.uniform(0, math.tau)
    bm = bmesh.new()
    reach = max(c.length for c in centers) + d * 0.5
    bottom = -0.1 * height - 0.04
    for i, c in enumerate(centers):
        poly = [c + Vector((math.cos(a), math.sin(a))) * d * 0.64 for a in (rot + k * math.tau / 6 for k in range(6))]
        for j, o in enumerate(centers):
            if i != j and (o - c).length < d * 1.6:
                n = (o - c).normalized()
                poly = clip_poly(poly, n, n.dot((c + o) / 2) - d * 0.035)
        if len(poly) < 3:
            continue
        h = height * (1.0 - 0.5 * (c.length / reach) ** 1.3) * rnd.uniform(0.6, 1.0)
        slope = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * (
            rnd.uniform(0.0, 0.12) if rnd.random() < 0.7 else rnd.uniform(0.25, 0.45)
        )
        top = [bm.verts.new((p.x, p.y, h + slope.dot(p - c))) for p in poly]
        bot = [bm.verts.new((p.x, p.y, bottom)) for p in poly]
        n = len(poly)
        for k in range(n):
            bm.faces.new((bot[k], bot[(k + 1) % n], top[(k + 1) % n], top[k]))
        bm.faces.new(top)  # open bottom (buried)
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="halcyne",
    color=(0.4, 0.7, 1.0),
    crust=(0.045, 0.065, 0.085),
    shape=shape,
    spread=0.3,
    buddies=((0,), (0.3, 0.5)),
    wall_sizes=(0.3, 0.75),
    wall_tilt=20,
    variants={
        "a": dict(
            seed=131,
            groups=[(110, 0.58, 3, (0.45, 1.0), 12), (240, 0.72, 2, (0.35, 0.7), 15), (355, 0.74, 2, (0.25, 0.5), 18)],
        ),
        "b": dict(
            seed=139,
            groups=[(50, 0.62, 3, (0.5, 0.95), 12), (180, 0.7, 2, (0.4, 0.75), 14), (300, 0.75, 2, (0.2, 0.45), 18)],
        ),
        "wall": dict(seed=149, wall=True, count=6),
    },
)
