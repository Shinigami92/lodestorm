"""Vyrel (mid, violet, slow pulse): thin sharp blade shards bursting out wide, some from broken-open geodes."""

import math  # noqa: F401
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import T, OreSpec, cut, finish_normals, rand_unit, tilted  # noqa: F401


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
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


ORE = OreSpec(
    name="vyrel",
    color=(0.7, 0.3, 0.95),
    crust=(0.065, 0.04, 0.085),
    shape=shape,
    spread=0.2,
    buddies=((1, 2, 2), (0.25, 0.5)),
    wall_sizes=(0.35, 0.85),
    wall_tilt=50,
    variants={
        "a": dict(seed=53, geodes=[(95, 0.56, 0.52, 8)], groups=[(230, 0.75, 4, (0.45, 0.85), 50), (335, 0.8, 3, (0.3, 0.6), 55)]),
        "b": dict(seed=67, geodes=[(30, 0.64, 0.4, 6), (200, 0.62, 0.42, 6)], groups=[(300, 0.82, 3, (0.35, 0.7), 55)]),
        "wall": dict(seed=97, wall=True, count=8),
    },
)
