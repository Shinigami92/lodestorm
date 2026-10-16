"""Kyrite (common, cyan, steady): long hexagonal prisms with pyramid tips (some broken), in tall upright groups."""

import itertools
import math
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import OreSpec, T, cut, finish_normals, rand_unit, tilted  # noqa: F401


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Cyan: long hexagonal prism with uneven face widths, slightly tapered, pyramid tip; tips often broken."""
    length = 0.28 + 0.82 * u
    radius = length * rnd.uniform(0.085, 0.11) + 0.022
    bm = bmesh.new()
    angs = [i / 6 * math.tau + rnd.uniform(-0.13, 0.13) for i in range(6)]
    rads = [radius * rnd.uniform(0.85, 1.1) for _ in range(6)]
    tip = min(radius * rnd.uniform(1.2, 1.8), length * 0.4)

    def ring(z: float, s: float) -> list:
        return [bm.verts.new((math.cos(a) * r * s, math.sin(a) * r * s, z)) for a, r in zip(angs, rads)]

    rings = [
        ring(-0.12 * length - 0.04, 1.0),
        ring(length * 0.5, rnd.uniform(0.94, 1.02)),
        ring(length - tip, rnd.uniform(0.82, 0.92)),
    ]
    apex = bm.verts.new((rnd.uniform(-0.25, 0.25) * radius, rnd.uniform(-0.25, 0.25) * radius, length))
    for a, b in itertools.pairwise(rings):
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


ORE = OreSpec(
    name="kyrite",
    color=(0.2, 0.85, 0.95),
    crust=(0.035, 0.075, 0.08),
    shape=shape,
    spread=0.17,
    buddies=((0, 1, 1, 2), (0.18, 0.35)),
    wall_sizes=(0.3, 0.8),
    wall_tilt=30,
    variants={
        "a": dict(
            seed=11,
            groups=[
                (105, 0.62, 6, (0.5, 1.0), 22),
                (225, 0.72, 3, (0.35, 0.7), 28),
                (340, 0.72, 3, (0.25, 0.55), 30),
                (20, 0.2, 2, (0.1, 0.25), 25),
            ],
        ),
        "b": dict(
            seed=23,
            groups=[(45, 0.64, 5, (0.5, 0.95), 24), (165, 0.7, 4, (0.45, 0.85), 26), (280, 0.62, 3, (0.3, 0.6), 30)],
        ),
        "wall": dict(seed=71, wall=True, count=7),
    },
)
