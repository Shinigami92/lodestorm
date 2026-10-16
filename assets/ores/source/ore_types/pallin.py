"""Pallin (common, pale ice blue, slow pulse): sprays of thin frost needles bursting from a few points, like hoarfrost."""

import math
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import OreSpec, T, cut, finish_normals, rand_unit, tilted  # noqa: F401


def needle(bm: bmesh.types.BMesh, base: Vector, d: Vector, length: float, radius: float, spin: float) -> None:
    """Thin three-sided needle tapering straight to a sharp point (4 tris: many of them stay cheap)."""
    z = d.normalized()
    x = tilted(z, Vector((math.cos(spin), math.sin(spin), 0.3)), 90)
    y = z.cross(x)
    ring = [
        bm.verts.new(base + (x * math.cos(a) + y * math.sin(a)) * radius) for a in (0.0, math.tau / 3, math.tau * 2 / 3)
    ]
    apex = bm.verts.new(base + z * length)
    for i in range(3):
        bm.faces.new((ring[i], ring[(i + 1) % 3], apex))
    bm.faces.new(list(reversed(ring)))


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Ice blue: a dense burst of thin needles radiating from one point, an upright brush or a flat fan (some needles
    snapped short), around a small frosted knot. Reads as a spiky ball / fan, never as single prisms."""
    reach = 0.28 + 0.7 * u
    count = 14 + int(24 * u) + rnd.randint(0, 3)
    fan = rnd.random() < 0.35
    fan_n = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)).normalized() if fan else None
    bm = bmesh.new()
    for k in range(count):
        if k == 0:
            d = tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(0, 12))
        else:
            d = tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(6, 80 if fan else 62))
            if fan:  # squash into the fan plane
                d = (d - fan_n * d.dot(fan_n) * 0.85).normalized()
            if d.z < 0.12:
                d = (d + Vector((0, 0, 0.2))).normalized()
        steep = 0.6 + 0.4 * d.z  # the burst is taller than wide
        length = reach * steep * (1.0 if k == 0 else rnd.uniform(0.6, 1.0))
        if k and rnd.random() < 0.15:  # snapped short
            length *= rnd.uniform(0.35, 0.55)
        radius = length * rnd.uniform(0.045, 0.06) + 0.007
        base = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.015 + d * 0.01 - Vector((0, 0, 0.03))
        needle(bm, base, d, length, radius, rnd.uniform(0, math.tau))
    knot = 0.035 + 0.06 * u  # frosted knot where the needles meet
    bmesh.ops.create_icosphere(
        bm,
        subdivisions=1,
        radius=1.0,
        matrix=T((0, 0, knot * 0.2), None, (knot, knot * rnd.uniform(0.85, 1.15), knot * 0.8)),
    )
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="pallin",
    color=(0.7, 0.88, 1.0),
    crust=(0.06, 0.07, 0.085),
    shape=shape,
    spread=0.3,
    buddies=((0, 0, 1), (0.3, 0.5)),
    wall_sizes=(0.3, 0.8),
    wall_tilt=35,
    variants={
        "a": dict(
            seed=113,
            groups=[
                (100, 0.6, 3, (0.55, 1.0), 25),
                (230, 0.72, 2, (0.4, 0.7), 30),
                (345, 0.74, 2, (0.3, 0.55), 30),
                (30, 0.25, 1, (0.15, 0.25), 20),
            ],
        ),
        "b": dict(
            seed=127,
            groups=[(50, 0.64, 3, (0.5, 0.95), 25), (170, 0.7, 3, (0.4, 0.8), 28), (290, 0.66, 2, (0.3, 0.6), 30)],
        ),
        "wall": dict(seed=131, wall=True, count=6),
    },
)
