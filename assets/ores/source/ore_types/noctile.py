"""Noctile (signature, mint-white veins, breathing core): rough near-black orbs, some broken open to a crystal-lined hollow."""

import math
import random

import bmesh
from mathutils import Matrix, Vector  # noqa: F401

from ore_geo import OreSpec, T, basis, cut, finish_normals, rand_unit, tilted


def shape(rnd: random.Random, u: float) -> bmesh.types.BMesh:
    """Near-black (dark body, glowing veins drawn by the game): a rough, lumpy round nodule like a thunder egg,
    half sunk into the rock. Bigger ones are often cracked open by a flat fracture: a thick rind around a hollow
    lined with tiny pointed crystals."""
    radius = 0.1 + 0.2 * u
    center = Vector((0, 0, radius * rnd.uniform(0.45, 0.6)))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2 if u > 0.2 else 1, radius=1.0)
    squash = rnd.uniform(0.8, 0.95)
    lumps = [(rand_unit(rnd), rnd.uniform(0.06, 0.14)) for _ in range(4)]  # knobby bulges
    for v in bm.verts:
        d = v.co.normalized()
        bump = rnd.uniform(0.92, 1.03) + sum(h * max(0.0, d.dot(c)) ** 4 for c, h in lumps)
        v.co = center + Vector((d.x, d.y, d.z * squash)) * radius * bump
    if u > 0.4 and rnd.random() < 0.8 * u:  # broken open
        n = tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(35, 65))
        plane = center + n * radius * rnd.uniform(0.05, 0.3)
        res = bmesh.ops.bisect_plane(
            bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=plane, plane_no=n, clear_outer=True
        )
        rim = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
        rind = rnd.uniform(0.7, 0.78)
        inner = {}
        for v in list(bm.verts):  # the cavity: the shell shrunk toward the center, rim verts kept on the fracture plane
            co = center + (v.co - center) * rind * rnd.uniform(0.95, 1.03)
            if any(v in e.verts for e in rim):
                co = co + n * (plane - co).dot(n)
            inner[v] = bm.verts.new(co)
        for f in list(bm.faces):
            bm.faces.new([inner[v] for v in reversed(f.verts)])
        for e in rim:
            a, b = e.verts
            bm.faces.new((a, b, inner[b], inner[a]))
        finish_normals(bm)
        # Tiny crystals lining the hollow, pointing into it.
        sites = [inner[v].co.copy() for v in inner if (plane - inner[v].co).dot(n) > radius * 0.18]
        rnd.shuffle(sites)
        for p in sites[: int(10 + 8 * u)]:
            d = (center - p).normalized()
            d = (d + n * 0.6).normalized()
            s = radius * rnd.uniform(0.15, 0.26)
            m = T(p - d * s * 0.3, basis(d, rand_unit(rnd)))
            base = [
                bm.verts.new(m @ Vector((math.cos(a) * s * 0.45, math.sin(a) * s * 0.45, 0)))
                for a in (0.0, 2.094, 4.189)
            ]
            apex = bm.verts.new(m @ Vector((0, 0, s * 1.6)))
            for j in range(3):
                bm.faces.new((base[j], base[(j + 1) % 3], apex))
            bm.faces.new(list(reversed(base)))
    elif rnd.random() < 0.4:  # chipped rind
        n = tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(40, 80))
        cut(bm, center + n * radius * rnd.uniform(0.7, 0.85), n)
    finish_normals(bm)
    return bm


ORE = OreSpec(
    name="noctile",
    color=(0.7, 1.0, 0.85),
    crust=(0.04, 0.055, 0.05),
    shape=shape,
    spread=0.32,
    buddies=((0, 0, 1), (0.3, 0.5)),
    wall_sizes=(0.3, 0.75),
    wall_tilt=35,
    variants={
        "a": dict(
            seed=151,
            groups=[(110, 0.64, 4, (0.6, 1.0), 30), (235, 0.74, 3, (0.4, 0.75), 30), (350, 0.74, 3, (0.3, 0.6), 30)],
        ),
        "b": dict(
            seed=163,
            geodes=[(200, 0.64, 0.42, 4)],
            groups=[(60, 0.64, 4, (0.55, 1.0), 30), (320, 0.76, 3, (0.35, 0.65), 30)],
        ),
        "wall": dict(seed=173, wall=True, count=7),
    },
    dark_body=True,
)
