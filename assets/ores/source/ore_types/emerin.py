"""Emerin (signature, emerald green, sparkle): long slender double-pointed spindles (hexagonal bipyramids)
balanced on their lower point, mostly in crossed pairs leaning against each other (X shapes), a few standing
alone or lying low across the rock."""

import itertools
import math
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import OreSpec, T, append_bm, cut, finish_normals, rand_unit, tilted


def spindle(rnd: random.Random, length: float, width: float) -> bmesh.types.BMesh:
    """Hexagonal bipyramid along +Z from 0 to length: slightly convex flanks, widest a bit below the middle,
    sharp points at both ends."""
    bm = bmesh.new()
    angs = [i / 6 * math.tau + rnd.uniform(-0.1, 0.1) for i in range(6)]
    rads = [width * rnd.uniform(0.88, 1.08) for _ in range(6)]
    waist = rnd.uniform(0.42, 0.52)
    rings = []
    for t, s in (
        (waist * 0.5, 0.6),
        (waist, 1.0),
        (waist + (1 - waist) * 0.45, 0.64),
        (waist + (1 - waist) * 0.75, 0.32),
    ):
        rings.append([bm.verts.new((math.cos(a) * r * s, math.sin(a) * r * s, t * length)) for a, r in zip(angs, rads)])
    lo = bm.verts.new((rnd.uniform(-0.2, 0.2) * width, rnd.uniform(-0.2, 0.2) * width, 0.0))
    hi = bm.verts.new((rnd.uniform(-0.2, 0.2) * width, rnd.uniform(-0.2, 0.2) * width, length))
    for a, b in itertools.pairwise(rings):
        for i in range(6):
            bm.faces.new((a[i], a[(i + 1) % 6], b[(i + 1) % 6], b[i]))
    for i in range(6):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % 6], hi))
        bm.faces.new((rings[0][(i + 1) % 6], rings[0][i], lo))
    return bm


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Emerald: slender hexagonal spindles, widest a bit below the middle, the lower point just stuck in the rock so
    the lens outline shows. Mostly a crossed pair: two spindles leaning against each other and crossing above
    their middle (an X, like crossed blades); otherwise a single one standing, or lying low across the rock with
    both points free."""
    length = 0.32 + 0.8 * u
    width = length * rnd.uniform(0.065, 0.075) + 0.016
    bm = bmesh.new()
    mode = rnd.random()
    if mode < 0.55:  # crossed pair
        lean = rnd.uniform(22, 34)
        h = length * rnd.uniform(0.5, 0.62)  # crossing height
        dx = h * math.tan(math.radians(lean))
        for side in (-1, 1):
            ln = length * (1.0 if side < 0 else rnd.uniform(0.75, 0.95))
            axis = tilted(Vector((0, 0, 1)), Vector((-side, 0, 0)), lean + rnd.uniform(-4, 4))
            axis = tilted(axis, Vector((0, 1, 0)), rnd.uniform(-8, 8))
            sp = spindle(rnd, ln, width * (1.0 if side < 0 else 0.9))
            append_bm(bm, sp, T(Vector((side * dx, 0, 0)) - axis * ln * 0.04, axis.to_track_quat("Z", "Y").to_matrix()))
            sp.free()
    else:
        if mode < 0.8:  # standing
            axis = tilted(Vector((0, 0, 1)), Vector((1, 0, 0)), rnd.uniform(0, 15))
            start = -axis * length * 0.04
        else:  # lying: the root is under the spindle, a bit off its middle
            axis = tilted(Vector((0, 0, 1)), Vector((1, 0, 0)), rnd.uniform(64, 80))
            start = -axis * length * rnd.uniform(0.3, 0.45) + Vector((0, 0, width * 0.4))
        main = spindle(rnd, length, width)
        append_bm(bm, main, T(start, axis.to_track_quat("Z", "Y").to_matrix()))
        main.free()
        if rnd.random() < 0.2:  # broken upper point
            cut(bm, start + axis * length * rnd.uniform(0.8, 0.9), tilted(axis, rand_unit(rnd), rnd.uniform(15, 40)))
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="emerin",
    color=(0.1, 0.75, 0.35),
    crust=(0.03, 0.07, 0.045),
    shape=shape,
    spread=0.3,
    buddies=((0,), (0.35, 0.55)),
    wall_sizes=(0.35, 0.85),
    wall_tilt=25,
    variants={
        "a": dict(
            seed=109,
            groups=[(110, 0.55, 4, (0.6, 1.0), 12), (230, 0.62, 3, (0.45, 0.85), 15), (345, 0.66, 3, (0.35, 0.7), 15)],
        ),
        "b": dict(
            seed=223,
            groups=[(40, 0.58, 4, (0.55, 0.95), 12), (170, 0.6, 3, (0.5, 0.9), 15), (290, 0.66, 3, (0.35, 0.7), 15)],
        ),
        "wall": dict(seed=239, wall=True, count=7),
    },
)
