"""Tessar (common, teal, wave rising up): leaning stacks of thin hexagonal plates fanned open like books, layered edges."""

import math  # noqa: F401
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import T, OreSpec, cut, finish_normals, rand_unit, tilted  # noqa: F401


def plate(bm: bmesh.types.BMesh, rnd: random.Random, m: Matrix, radius: float, thick: float) -> None:
    """Hexagonal plate in the local XZ plane (normal +Y), centered at the origin; the rim is a little thinner than
    the middle so the faces catch the light differently from the edges."""
    angs = [i / 6 * math.tau + rnd.uniform(-0.1, 0.1) for i in range(6)]
    rads = [radius * rnd.uniform(0.88, 1.06) for _ in range(6)]
    rim = [(math.cos(a) * r, math.sin(a) * r) for a, r in zip(angs, rads)]
    front = [bm.verts.new(m @ Vector((x, thick * 0.35, z))) for x, z in rim]
    back = [bm.verts.new(m @ Vector((x, -thick * 0.35, z))) for x, z in rim]
    fc = bm.verts.new(m @ Vector((0, thick * 0.5, 0)))
    bc = bm.verts.new(m @ Vector((0, -thick * 0.5, 0)))
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((front[j], front[i], back[i], back[j]))
        bm.faces.new((front[i], front[j], fc))
        bm.faces.new((back[j], back[i], bc))


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Teal: a leaning stack of thin hexagonal plates with gaps between them, fanned open like the pages of a book
    (each plate tilted a bit more than the one below, slightly twisted, the top ones smaller), held together by a
    thin core. Reads as a stepped pile of discs with layered edges, never as prisms, blocks or blades."""
    big = 0.1 + 0.16 * u
    thick = 0.024 + 0.022 * u
    n = 3 + int(4 * u) + rnd.randint(0, 1)
    pitch = thick * rnd.uniform(2.3, 2.7) + big * rnd.uniform(0.13, 0.18)
    lean = math.radians(rnd.uniform(5, 18))  # the spine leans toward +X
    fan = math.radians(rnd.uniform(10, 30))  # the plates open up like pages
    bm = bmesh.new()
    flat = Matrix.Rotation(math.radians(90), 3, "X")  # plate normal (+Y) -> +Z
    top = Vector()
    for k in range(n):
        t = k / max(1, n - 1)
        h = pitch * k + thick
        c = Vector((math.tan(lean) * h + rnd.uniform(-0.08, 0.08) * big, rnd.uniform(-0.08, 0.08) * big, h))
        r = big * (1.0 - 0.25 * t) * rnd.uniform(0.9, 1.08) * (0.85 if k == 0 else 1.0)
        tilt = (t - 0.3) * fan + rnd.uniform(-0.06, 0.06)
        rot = Matrix.Rotation(tilt, 3, "Y") @ Matrix.Rotation(rnd.uniform(-0.12, 0.12), 3, "X") @ Matrix.Rotation(rnd.uniform(0, math.pi / 3), 3, "Z") @ flat
        plate(bm, rnd, T(c, rot), r, thick)
        top = c
    core = big * 0.18  # thin hexagonal core through the stack
    ring0 = [bm.verts.new((math.cos(i / 6 * math.tau) * core, math.sin(i / 6 * math.tau) * core, -0.05)) for i in range(6)]
    ring1 = [bm.verts.new(top + Vector((math.cos(i / 6 * math.tau) * core * 0.7, math.sin(i / 6 * math.tau) * core * 0.7, 0))) for i in range(6)]
    for i in range(6):
        bm.faces.new((ring0[i], ring0[(i + 1) % 6], ring1[(i + 1) % 6], ring1[i]))
    if rnd.random() < 0.3:  # a plate edge chipped off
        d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.2, 0.6))).normalized()
        cut(bm, top * 0.6 + d * big * rnd.uniform(0.75, 0.95), d)
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="tessar",
    color=(0.1, 0.85, 0.6),
    crust=(0.03, 0.075, 0.06),
    shape=shape,
    spread=0.3,
    buddies=((0, 0, 0, 1), (0.35, 0.5)),
    wall_sizes=(0.3, 0.75),
    wall_tilt=18,
    variants={
        "a": dict(seed=137, groups=[(110, 0.62, 1, (1.0, 1.0), 8), (190, 0.72, 2, (0.5, 0.75), 18), (260, 0.74, 2, (0.4, 0.65), 20), (350, 0.74, 2, (0.3, 0.55), 20), (40, 0.28, 1, (0.15, 0.3), 15)]),
        "b": dict(seed=149, groups=[(40, 0.64, 3, (0.55, 1.0), 18), (160, 0.7, 2, (0.45, 0.8), 20), (285, 0.68, 2, (0.3, 0.6), 20)]),
        "wall": dict(seed=151, wall=True, count=6),
    },
)
