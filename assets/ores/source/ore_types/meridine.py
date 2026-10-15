"""Meridine (signature, magenta, heartbeat): twisted spiral crystals, three-ridged like a drill bit, screwing
around a winding axis as they grow and tapering to a point; some curl over into a hook."""

import math  # noqa: F401
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import T, OreSpec, cut, finish_normals, rand_unit, tilted  # noqa: F401


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Magenta: three ridges with deep grooves between them, screwed around the axis about one turn over the length
    (drill bit / twisted ram's-horn crystal), the axis itself winding on a tight helix so the silhouette wobbles
    side to side; tapers to a short point, some crystals curl over into a hook."""
    length = 0.3 + 0.78 * u
    radius = length * rnd.uniform(0.15, 0.17) + 0.03
    inner = rnd.uniform(0.36, 0.42)
    sec = []
    for i in range(6):
        a = i / 6 * math.tau
        r = 1.0 if i % 2 == 0 else inner
        sec.append((math.cos(a) * r, math.sin(a) * r))
    turns = rnd.uniform(1.1, 1.3)  # all the same hand, like one growth
    wobble = radius * rnd.uniform(0.22, 0.3)  # radius of the helical axis
    curl = rnd.uniform(0.6, 0.95) if rnd.random() < 0.3 else rnd.uniform(0.0, 0.2)  # total bend (rad)
    rings_n = 9 + round(9 * u)  # ~25 deg of twist per ring on the big ones (coarser reads jagged); small ones fewer
    bottom = -0.12 * length - 0.03
    body = length * rnd.uniform(0.86, 0.9) - bottom
    seg = body / (rings_n - 1)
    bm = bmesh.new()
    pos = Vector((0, 0, bottom))
    tan = Vector((0, 0, 1))
    side = Vector((0, 1, 0))
    rings = []
    for i in range(rings_n):
        t = i / (rings_n - 1)
        phi = curl * t**1.5
        tan = Vector((math.sin(phi), 0, math.cos(phi)))
        nor = Vector((math.cos(phi), 0, -math.sin(phi)))
        tw = turns * math.tau * t
        s = radius * (1.0 - 0.55 * t)
        w = wobble * min(1.0, t * 4) * (1.0 - 0.4 * t)
        c = pos + nor * math.cos(tw) * w + side * math.sin(tw) * w
        ring = []
        for x, y in sec:
            rx, ry = x * math.cos(tw) - y * math.sin(tw), x * math.sin(tw) + y * math.cos(tw)
            ring.append(bm.verts.new(c + nor * rx * s + side * ry * s))
        rings.append(ring)
        if i < rings_n - 1:
            pos = pos + tan * seg
    apex = bm.verts.new(pos + tan * (length - bottom - body + radius * 0.5))
    n = len(sec)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    for i in range(n):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % n], apex))
    bm.faces.new(list(reversed(rings[0])))
    if rnd.random() < 0.15:  # snapped tip
        cut(bm, Vector((0, 0, length * rnd.uniform(0.72, 0.88))), tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(20, 45)))
    bmesh.ops.rotate(bm, verts=bm.verts[:], cent=Vector(), matrix=Matrix.Rotation(rnd.uniform(0, math.tau), 3, "Z"))
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="meridine",
    color=(0.95, 0.25, 0.85),
    crust=(0.08, 0.035, 0.07),
    shape=shape,
    spread=0.2,
    buddies=((0, 0, 1), (0.35, 0.55)),
    wall_sizes=(0.35, 0.85),
    wall_tilt=35,
    variants={
        "a": dict(seed=449, groups=[(100, 0.6, 4, (0.6, 1.0), 24), (230, 0.72, 3, (0.4, 0.75), 30), (345, 0.74, 2, (0.35, 0.6), 30)]),
        "b": dict(seed=463, groups=[(50, 0.66, 3, (0.55, 0.95), 26), (170, 0.68, 3, (0.5, 0.85), 28), (290, 0.7, 3, (0.3, 0.65), 32)]),
        "wall": dict(seed=467, wall=True, count=7),
    },
)
