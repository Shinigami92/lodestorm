"""Ressa (mid, pink, breathing core): low botryoidal mounds, grape-like masses of fused round blobs."""

import math  # noqa: F401
import random

import bmesh
from mathutils import Matrix, Vector

from ore_geo import OreSpec, T, cut, finish_normals, polar, rand_unit, tilted


def ball(bm: bmesh.types.BMesh, center: Vector, r: float) -> None:
    """Low-poly ball (faceted is fine): fewer segments for small ones, the tiny grapes are icosahedra."""
    m = T(center, Matrix.Rotation(r * 40.0, 3, "Z"))
    if r < 0.045:
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r, matrix=m)
    elif r < 0.14:
        bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=r, matrix=m)
    else:
        bmesh.ops.create_uvsphere(bm, u_segments=7, v_segments=5, radius=r, matrix=m)


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Pink: a botryoidal mound, a ring of fused balls half sunk into the rock, one or two more on top and a few
    small grapes bulging from their flanks; the buried part cut off flat. Each ball stays a distinct bulge, so the
    mass reads as round grapes, low and wide: the only round ore among the angular ones."""
    r0 = 0.09 + 0.11 * u
    balls = []
    n = 2 + int(2.3 * u)
    a0 = rnd.uniform(0, 360)
    for k in range(n):
        r = r0 * rnd.uniform(0.8, 1.1)
        ring = r0 * rnd.uniform(0.85, 1.15) if n > 1 else 0.0
        balls.append((polar(a0 + k * 360 / n + rnd.uniform(-20, 20), ring, r * rnd.uniform(0.1, 0.35)), r))
    for _ in range(1 + (u > 0.5)):
        r = r0 * rnd.uniform(0.85, 1.15)
        balls.append((polar(rnd.uniform(0, 360), r0 * rnd.uniform(0.0, 0.35), r0 * rnd.uniform(0.8, 1.05)), r))
    for _ in range(rnd.randint(0, 1) + int(1.2 * u)):  # small grapes on the flanks
        c, pr = rnd.choice(balls)
        d = tilted(Vector((0, 0, 1)), Vector((c.x, c.y, 0)) + rand_unit(rnd) * 0.3, rnd.uniform(40, 80))
        r = pr * rnd.uniform(0.38, 0.5)
        balls.append((c + d * (pr + r * 0.3), r))
    bm = bmesh.new()
    for c, r in balls:
        ball(bm, c, r)
    cut(bm, Vector((0, 0, -0.05)), Vector((0, 0, -1)))  # buried part
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="ressa",
    color=(1.0, 0.45, 0.75),
    crust=(0.08, 0.04, 0.06),
    shape=shape,
    spread=0.3,
    buddies=((0,), (0.35, 0.5)),
    wall_sizes=(0.3, 0.75),
    wall_tilt=25,
    smooth=True,
    variants={
        "a": dict(
            seed=151,
            groups=[(115, 0.55, 3, (0.55, 1.0), 12), (245, 0.72, 2, (0.4, 0.7), 15), (0, 0.74, 2, (0.3, 0.5), 15)],
        ),
        "b": dict(
            seed=163,
            groups=[(55, 0.6, 3, (0.5, 0.95), 12), (190, 0.7, 2, (0.4, 0.75), 15), (310, 0.75, 2, (0.3, 0.5), 15)],
        ),
        "wall": dict(seed=173, wall=True, count=6),
    },
)
