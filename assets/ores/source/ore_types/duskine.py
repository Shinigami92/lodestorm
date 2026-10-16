"""Duskine (mid, deep blue, sparkle): sharp octahedra (double pyramids) sitting at angles, some twinned, small ones
clustering around the big ones."""

import math
import random

import bmesh
from mathutils import Matrix, Vector

from ore_geo import OreSpec, T, cut, finish_normals, rand_unit, tilted  # noqa: F401


def octahedron(bm: bmesh.types.BMesh, rnd: random.Random, s: float, h: float, m: Matrix) -> None:
    """Closed double pyramid: square girdle of half-width s with a thin vertical belt (it catches the light apart from
    the pyramid faces, so the two points read separately), apexes at +-h, corners jittered a little."""
    belt = h * rnd.uniform(0.06, 0.12)
    corners = [
        Vector(
            (
                math.cos(a) * s * rnd.uniform(0.95, 1.05),
                math.sin(a) * s * rnd.uniform(0.95, 1.05),
                rnd.uniform(-0.03, 0.03) * s,
            )
        )
        for a in (i * math.pi / 2 for i in range(4))
    ]
    upper = [bm.verts.new(m @ (c + Vector((0, 0, belt)))) for c in corners]
    lower = [bm.verts.new(m @ (c - Vector((0, 0, belt)))) for c in corners]
    top = bm.verts.new(m @ Vector((rnd.uniform(-0.06, 0.06) * s, rnd.uniform(-0.06, 0.06) * s, h)))
    bot = bm.verts.new(m @ Vector((0, 0, -h)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((upper[i], upper[j], top))
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
        bm.faces.new((lower[j], lower[i], bot))


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Deep blue: sharp octahedron (spinel-like double pyramid), slightly stretched, set into the rock at an angle with
    its lower point buried; sometimes a contact twin (a second octahedron turned and tipped through the first), sometimes
    a point chipped off. Diamond silhouettes instead of prisms or blocks."""
    s = 0.085 + 0.22 * u
    h = s * rnd.uniform(1.65, 1.9)
    bm = bmesh.new()
    lean = Matrix.Rotation(rnd.uniform(0.0, 0.2), 4, "X") @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, "Z")
    lift = Matrix.Translation((0, 0, h * rnd.uniform(0.9, 1.0)))
    octahedron(bm, rnd, s, h, lift @ lean)
    if rnd.random() < 0.22:  # twin: smaller octahedron through the same center, turned 45 deg and tipped
        k = rnd.uniform(0.6, 0.85)
        twist = Matrix.Rotation(math.pi / 4 + rnd.uniform(-0.15, 0.15), 4, "Z") @ Matrix.Rotation(
            rnd.uniform(0.5, 0.9), 4, "Y"
        )
        off = Matrix.Translation(
            (rnd.uniform(-0.15, 0.15) * s, rnd.uniform(-0.15, 0.15) * s, rnd.uniform(0.0, 0.2) * h)
        )
        octahedron(bm, rnd, s * k, s * k * rnd.uniform(1.4, 1.6), lift @ off @ lean @ twist)
    elif rnd.random() < 0.3:  # chipped point
        top = max(v.co.z for v in bm.verts)
        cut(
            bm,
            Vector((0, 0, top - h * rnd.uniform(0.15, 0.3))),
            tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(10, 40)),
        )
    a0 = rnd.uniform(0, math.tau)
    n = int(0.6 + 3.0 * u)
    for k in range(n):  # small octahedra crowding around the foot of the big one
        a = a0 + k * math.tau / max(n, 1) + rnd.uniform(-0.4, 0.4)
        d = Vector((math.cos(a), math.sin(a), 0))
        ks = s * rnd.uniform(0.22, 0.36)
        tip = Matrix.Rotation(rnd.uniform(0.3, 0.7), 4, d.cross(Vector((0, 0, -1))))  # leaning outward
        octahedron(
            bm,
            rnd,
            ks,
            ks * rnd.uniform(1.5, 1.8),
            Matrix.Translation(d * s * rnd.uniform(0.85, 1.15) + Vector((0, 0, ks * 0.7))) @ tip,
        )
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="duskine",
    color=(0.25, 0.35, 1.0),
    crust=(0.035, 0.045, 0.09),
    shape=shape,
    spread=0.27,
    buddies=((0, 0, 1), (0.3, 0.45)),
    wall_sizes=(0.3, 0.75),
    wall_tilt=25,
    variants={
        "a": dict(
            seed=101,
            groups=[(110, 0.6, 3, (0.4, 1.0), 14), (235, 0.72, 3, (0.3, 0.65), 18), (350, 0.74, 2, (0.25, 0.55), 18)],
        ),
        "b": dict(
            seed=113,
            groups=[(40, 0.66, 3, (0.4, 0.95), 14), (170, 0.7, 3, (0.35, 0.8), 16), (290, 0.7, 2, (0.25, 0.55), 18)],
        ),
        "wall": dict(seed=127, wall=True, count=7),
    },
)
