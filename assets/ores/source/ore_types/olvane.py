"""Olvane (common, green, steady): chunky intergrown cubes and blocks with chipped corners, low and heavy."""

import math
import random

import bmesh
from mathutils import Matrix, Vector

from ore_geo import OreSpec, T, cut, finish_normals, rand_unit, tilted  # noqa: F401


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Green: chunky square block with a flat top (fluorite-like), sometimes intergrown with a second cube,
    a corner or two chipped off. Big flat faces keep it reading as blocky from the game camera."""
    edge = 0.14 + 0.3 * u
    bm = bmesh.new()
    sx, sy = edge * rnd.uniform(0.85, 1.15), edge * rnd.uniform(0.85, 1.15)
    sz = edge * rnd.uniform(1.1, 1.9)
    bmesh.ops.create_cube(bm, size=1.0, matrix=T((0, 0, sz / 2 - 0.25 * edge), None, (sx, sy, sz + 0.5 * edge)))
    if rnd.random() < 0.35:  # intergrown twin: a smaller cube on the same axes (or turned 45 deg) stepping out
        s = edge * rnd.uniform(0.5, 0.72)
        corner = Vector(
            (rnd.choice((-1, 1)) * sx * 0.42, rnd.choice((-1, 1)) * sy * 0.42, sz * rnd.uniform(0.25, 0.75))
        )
        rot = Matrix.Rotation(rnd.choice((0.0, 0.0, math.pi / 4)) + rnd.uniform(-0.08, 0.08), 3, "Z")
        bmesh.ops.create_cube(bm, size=1.0, matrix=T(corner, rot, (s, s, s * rnd.uniform(0.9, 1.25))))
    top = Vector((0, 0, sz))
    for _ in range(rnd.choice((0, 1, 1, 2))):  # chipped corners (octahedral cleavage)
        c = Vector((rnd.choice((-1, 1)) * sx / 2, rnd.choice((-1, 1)) * sy / 2, top.z))
        n = Vector((c.x / sx, c.y / sy, rnd.uniform(0.3, 0.7))).normalized()
        cut(bm, c - n * edge * rnd.uniform(0.12, 0.25), n)
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="olvane",
    color=(0.35, 0.9, 0.25),
    crust=(0.05, 0.075, 0.035),
    shape=shape,
    spread=0.27,
    buddies=((0, 1, 1), (0.25, 0.45)),
    wall_sizes=(0.15, 0.55),
    wall_tilt=35,
    variants={
        "a": dict(
            seed=31,
            groups=[(115, 0.55, 5, (0.55, 1.0), 18), (245, 0.72, 4, (0.35, 0.75), 22), (5, 0.74, 3, (0.25, 0.55), 22)],
        ),
        "b": dict(
            seed=43,
            groups=[(60, 0.6, 6, (0.5, 1.0), 20), (205, 0.66, 4, (0.35, 0.8), 22), (310, 0.8, 2, (0.2, 0.4), 22)],
        ),
        "wall": dict(seed=83, wall=True, count=7),
    },
)
