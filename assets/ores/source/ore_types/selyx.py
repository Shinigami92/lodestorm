"""Selyx (signature, pale lavender, wave): tufts of very fine, curving hair-like fibers in soft fountains."""

import math  # noqa: F401
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import T, OreSpec, cut, finish_normals, rand_unit, tilted  # noqa: F401


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Pale lavender: one tuft of fine fibers (okenite-like) from a single root, rising nearly upright and arching
    over toward their tips, the outer ones further, like a fountain: a soft, spiky-fuzzy silhouette unlike any solid
    crystal. Each fiber is a thin tapering 3-sided strand bent in its vertical plane."""
    bm = bmesh.new()
    count = int(6 + 16 * u)
    length = 0.24 + 0.72 * u
    width = 0.014 + 0.012 * u
    steps = (0.0, 0.5, 1.0) if u < 0.3 else (0.0, 0.32, 0.58, 0.8, 1.0)
    lean = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * 0.15  # the whole tuft sways a little
    for i in range(count):
        t = (i + 0.5) / count  # 0: core, 1: rim of the fountain
        az = i * 2.39996 + rnd.uniform(-0.2, 0.2)
        tilt = math.radians(2 + 20 * t**0.8 + rnd.uniform(-3, 3))
        bend = math.radians(rnd.uniform(45, 65) + 55 * t)  # arching over toward the tip, stronger at the rim
        flen = length * 1.25 * (1.0 - 0.35 * t) * rnd.uniform(0.85, 1.03)
        out = Vector((math.cos(az), math.sin(az), 0))
        side = Vector((-math.sin(az), math.cos(az), 0))
        start = out * rnd.uniform(0.0, 0.03) + Vector((0, 0, -0.05))
        # Strand centerline: march along a direction that rotates outward and down.
        pts, segs = [start], []
        p = start.copy()
        for k in range(1, len(steps)):
            s = (steps[k - 1] + steps[k]) / 2
            a = tilt + bend * s**1.5
            d = (out * math.sin(a) + Vector((0, 0, math.cos(a))) + lean * s).normalized()
            p = p + d * flen * (steps[k] - steps[k - 1])
            pts.append(p.copy())
            segs.append(d)
        rings = []
        for k in range(len(pts) - 1):
            d = (segs[max(k - 1, 0)] + segs[k]).normalized()
            w = width * (1.0 - 0.6 * steps[k]) * rnd.uniform(0.85, 1.15)
            n = d.cross(side).normalized()
            rings.append([bm.verts.new(pts[k] + (side * math.cos(b) + n * math.sin(b)) * w) for b in (0.0, 2.094, 4.189)])
        apex = bm.verts.new(pts[-1])
        for ra, rb in zip(rings, rings[1:]):
            for j in range(3):
                bm.faces.new((ra[j], ra[(j + 1) % 3], rb[(j + 1) % 3], rb[j]))
        for j in range(3):
            bm.faces.new((rings[-1][j], rings[-1][(j + 1) % 3], apex))
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="selyx",
    color=(0.85, 0.75, 1.0),
    crust=(0.07, 0.06, 0.085),
    shape=shape,
    spread=0.22,
    buddies=((0,), (0.3, 0.5)),
    wall_sizes=(0.35, 0.8),
    wall_tilt=30,
    variants={
        "a": dict(seed=113, groups=[(110, 0.6, 1, (1.0, 1.0), 5), (195, 0.74, 1, (0.5, 0.5), 15), (250, 0.82, 1, (0.35, 0.35), 15), (320, 0.76, 1, (0.45, 0.45), 15), (30, 0.82, 1, (0.35, 0.35), 15)]),
        "b": dict(seed=127, groups=[(50, 0.6, 1, (1.0, 1.0), 5), (150, 0.76, 1, (0.5, 0.5), 15), (215, 0.82, 1, (0.35, 0.35), 15), (290, 0.74, 2, (0.4, 0.45), 20)]),
        "wall": dict(seed=139, wall=True, count=6),
    },
)
