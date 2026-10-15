"""Aethrine (signature, rarest, iridescent, shifting color): clean gem prisms radiating in a starburst crown."""

import math  # noqa: F401
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import T, OreSpec, basis, cut, finish_normals, rand_unit, tilted  # noqa: F401


def prism(bm: bmesh.types.BMesh, rnd: random.Random, length: float, m: Matrix) -> None:
    """One slim, flawless gem prism (topaz/tourmaline-like) into bm, transformed by m: ditrigonal section
    (alternating wide and narrow faces), a striation step on the long ones and a rhombohedral tip: three kite faces
    over a zigzag edge, unlike kyrite's six-sided pyramid."""
    radius = length * rnd.uniform(0.058, 0.068) + 0.016
    off = rnd.uniform(7, 11)
    angs = [math.radians(i * 60 + (off if i % 2 else -off)) for i in range(6)]
    tip = radius * rnd.uniform(1.5, 1.9)
    zig = radius * 0.55

    def ring(z: float, s: float, zz: float = 0.0) -> list:
        return [bm.verts.new(m @ Vector((math.cos(a) * radius * s, math.sin(a) * radius * s, z + (zz if i % 2 else 0.0)))) for i, a in enumerate(angs)]

    z0 = length - tip - zig
    rings = [ring(-0.1 * length - 0.04, 0.9)]
    if length > 0.45:  # striation step
        step = rnd.uniform(0.35, 0.6) * z0
        rings += [ring(step, 0.96), ring(step + 0.012, 1.0)]
    rings.append(ring(z0, 1.0, zig))
    apex = bm.verts.new(m @ Vector((0, 0, length)))
    for ra, rb in zip(rings, rings[1:]):
        for i in range(6):
            bm.faces.new((ra[i], ra[(i + 1) % 6], rb[(i + 1) % 6], rb[i]))
    top = rings[-1]
    for k in range(3):  # kite faces: high corner, low corner, high corner, apex
        i = 2 * k
        bm.faces.new((top[i - 1], top[i], top[i + 1], apex))
    bm.faces.new(list(reversed(rings[0])))


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Iridescent: a crown of gem prisms bursting from one point, a tall upright spire in the middle towering over an
    inner ring fanning up and an outer ring leaning out, evenly spaced: a symmetric starburst silhouette (kyrite
    grows in loose upright groups). Small ones are a single prism."""
    length = 0.32 + 0.72 * u
    bm = bmesh.new()
    prism(bm, rnd, length, T((0, 0, 0), basis(tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(0, 4)), rand_unit(rnd))))
    if u >= 0.15:
        spin = rnd.uniform(0, 360)
        rings = [(4 if u > 0.5 else 3, (13, 20), (0.5, 0.64)), (5 if u > 0.5 else 3, (34, 44), (0.3, 0.42))]
        for r, (n, tilt, size) in enumerate(rings):
            for k in range(n):
                az = math.radians(spin + (k + 0.5 * r) * 360 / n + rnd.uniform(-10, 10))
                d = tilted(Vector((0, 0, 1)), Vector((math.cos(az), math.sin(az), 0)), rnd.uniform(*tilt))
                prism(bm, rnd, length * rnd.uniform(*size), T(d * 0.02, basis(d, rand_unit(rnd))))
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="aethrine",
    color=(0.6, 1.0, 0.95),
    crust=(0.045, 0.075, 0.072),
    shape=shape,
    spread=0.3,
    buddies=((0,), (0.3, 0.5)),
    wall_sizes=(0.1, 0.8),
    wall_tilt=25,
    variants={
        "a": dict(seed=181, groups=[(110, 0.6, 1, (1.0, 1.0), 4), (235, 0.72, 1, (0.6, 0.7), 8), (350, 0.78, 2, (0.05, 0.4), 30), (25, 0.86, 1, (0.4, 0.5), 10)]),
        "b": dict(seed=193, groups=[(45, 0.62, 1, (1.0, 1.0), 4), (300, 0.72, 1, (0.5, 0.65), 8), (180, 0.76, 2, (0.05, 0.45), 30), (115, 0.84, 1, (0.4, 0.5), 10)]),
        "wall": dict(seed=199, wall=True, count=5),
    },
)
