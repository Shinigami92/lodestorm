"""Ash fields scatter kit: black basalt boulders and column clusters, porous scoria, charred dead trees, the vent's
cinder cone and basalt cliff chunks (concepts: batch11 ash, ash_props).

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/ash/source/ash_build.py wip a1                    # kit iso + hero
    tools/blender.sh assets/biomes/ash/source/ash_build.py wip a1 Vent_a,scatter
    tools/blender.sh assets/biomes/ash/source/ash_build.py final

Everything it writes goes to tmp/assets/ash/: "wip <tag> [views]" renders quick previews into wip/<tag>_*.png
(views: kit_iso, kit_hero, scatter, variants, back, sheet, save, or a part's name); "final" renders the kit, every
part (iso + hero), the cliffs' backs and a game-distance scatter, writes the contact sheet sheet.png and saves the
procedural ash_procedural.blend that ash_bake.py turns into the game asset. In the .blend the parts stand unrotated
in a row along X, 3 m apart (so the AO bake doesn't pick up neighbors); the bake zeroes their locations.

Game contract (game/locations/scatter_type.gd): a ScatterType draws ONE mesh many times (random scale, tilt, sink),
so every part is one closed mesh object, its origin at the ground contact point (bottom center), standing on z = 0
with extra geometry below ground (SINK) so tilted or sunk instances don't float. Cliffs face -Y (toward the camera
side) with a flat back at y = +CLIFF_BACK. Vent_a replaces the vent hazard's greybox cone (bottom radius 1.1, top
0.35, 0.5 high): its origin is the middle of its base, its mouth open upward. Budgets (TBD (playtest)): boulders,
scoria and the fallen trunk <= ~800 triangles; columns, stump, vent and cliffs <= ~2.5k.

Modeling: rocks are unions (boolean, manifold solver) of convex chunks (convex hulls of jittered points) shaved by
plane cuts (fracture facets), hexagonal prisms stacked in slightly turned segments (columnar basalt), notched by
thin crack cutters; the wood is swept tubes (fluted, splintered at the broken ends) unioned the same way; the vent is
a lathed cone with a crater, its crust cut by radial cracks. Every part has its own procedural material (basalt,
scoria, char, cinder crust); the bake merges them into one atlas. Mesh attributes for the materials: "facet" (random
per face: each fracture plane its own tone) and "inner" (1 on the broken ends of the wood: bare, less charred).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "ash"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Vector

import common as C
from common import T, rx, ry, rz, srgb
from rock_geo import (
    add_boolean,
    bm_to_obj,
    chip_cutter,
    chunk,
    crack_cutter,
    cut,
    hull,
    place,
    rand_dir,
    rand_rot,
    shave,
    support,
    uv_to_xy,
    work_collection,
)

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "a0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit_iso", "kit_hero"]

ASSET = "Ash"
# Geometry kept below z = 0 per part (m), so random tilt / sink in the game never shows the bottom.
SINK = {
    "Boulder_a": 0.18,
    "Boulder_b": 0.15,
    "Columns_a": 0.35,
    "Scoria_a": 0.08,
    "Stump_a": 0.3,
    "Stump_b": 0.08,
    "Vent_a": 0.12,
    "Cliff_a": 0.45,
    "Cliff_b": 0.45,
}
CLIFF_BACK = 1.0  # cliffs: flat back plane at y = +1 m, rock face toward -Y
SHARP_DEG = 32.0  # rock edges sharper than this split the shading (fracture ridges); softer ones shade smooth
WOOD_SHARP_DEG = 70.0  # the wood and the cone shade smooth except at splinters and crack walls
VARIANTS = list(SINK)


# --- convex chunks (fracture pieces) -------------------------------------------------------------------


def blob_points(rnd: random.Random, radius: float, count: int = 22, flat: float = 0.75, lumps: float = 0.3) -> list:
    """Points on a lumpy ellipsoid: a rounded, knobbly rock (scoria) once hulled and shaved."""
    pts = []
    for _ in range(count):
        d = rand_dir(rnd)
        r = radius * (1 + rnd.uniform(-lumps, lumps) * 0.6)
        pts.append(Vector((d.x * r, d.y * r * rnd.uniform(0.8, 1.0), d.z * r * flat)))
    return pts


def hex_prism(rnd: random.Random, r: float, h: float, jitter: float = 0.05, taper: float = 0.97) -> bmesh.types.BMesh:
    """A basalt column segment from z = 0 to h: a slightly irregular hexagon (r to its corners), barely tapered."""
    a0 = rnd.uniform(0, math.tau)
    pts = []
    for i in range(6):
        a = a0 + (i + rnd.uniform(-0.08, 0.08)) / 6 * math.tau
        k = r * (1 + rnd.uniform(-jitter, jitter))
        pts.append(Vector((math.cos(a) * k, math.sin(a) * k, 0.0)))
        pts.append(Vector((math.cos(a) * k * taper, math.sin(a) * k * taper, h)))
    return hull(pts)


def basalt_column(
    rnd: random.Random,
    r: float,
    h: float,
    base: Vector,
    segment: tuple = (0.6, 1.3),
    top_tilt: float = 0.5,
    lean: float = 2.0,
    chamfer: float = 0.06,
) -> list:
    """A column from base.z up to base.z + h, stacked from segments (each a little turned, shifted and narrower or
    wider, overlapping the one below so the joint shows as a step), the top one broken by a slanted fracture."""
    parts = []
    z = 0.0
    tilt = rx(rnd.uniform(-lean, lean)) @ ry(rnd.uniform(-lean, lean))
    while z < h - 0.05:
        seg_h = min(rnd.uniform(*segment), h - z)
        if h - z - seg_h < 0.3:
            seg_h = h - z
        rr = r * rnd.uniform(0.95, 1.04)
        bm = hex_prism(rnd, rr, seg_h + 0.03)
        if chamfer:  # worn joint: the segment's top corners knocked off a little
            for i in range(6):
                a = i / 6 * math.tau + rnd.uniform(0, 0.5)
                cut(bm, (math.cos(a), math.sin(a), 1.6), at=None, keep=1.0 - chamfer * rnd.uniform(0.5, 1.2))
        off = Vector((rnd.uniform(-0.02, 0.02), rnd.uniform(-0.02, 0.02), z))
        parts.append(place(bm, T(base, tilt) @ T(off, rz(rnd.uniform(-6, 6)))))
        z += seg_h
    top = parts[-1]
    a = rnd.uniform(0, math.tau)
    cut(top, (math.cos(a) * top_tilt, math.sin(a) * top_tilt, 1.0), rnd.uniform(0.9, 0.97))
    return parts


def pit_cutter(rnd: random.Random, center, radius: float) -> bmesh.types.BMesh:
    """A small lumpy ball: bites a round gas hole (vesicle) into a surface."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    for v in bm.verts:
        v.co *= rnd.uniform(0.85, 1.15)
    return place(bm, T(center))


# --- swept tubes (wood) -------------------------------------------------------------------------------


def tube(
    rnd: random.Random,
    path: list,
    radii: list,
    sides: int = 10,
    flutes: int = 7,
    flute: float = 0.12,
    twist: float = 0.4,
    jag: float = 0.0,
    caps: list | None = None,
) -> bmesh.types.BMesh:
    """Closed tube along `path` (Vectors) with `radii`: fluted (`flutes` grooves of depth `flute`, twisting along it)
    and lumpy; both ends capped, the end broken off by `jag` (m): a slanted break with a few long splinters (its
    ring's vertices pushed along the tube), the cap's middle sunk. Records each end (center, axis, radius) in `caps`
    for the "inner" attribute."""
    bm = bmesh.new()
    rings = []
    normal = None
    slant = rnd.uniform(0, math.tau)
    for i, p in enumerate(path):
        j, k = min(i + 1, len(path) - 1), max(i - 1, 0)
        t = (path[j] - path[k]).normalized()
        if normal is None:
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            normal = (ref - t * ref.dot(t)).normalized()
        else:
            normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        last = i == len(path) - 1
        ring = []
        for s in range(sides):
            a = s / sides * math.tau
            r = radii[i] * (1 - flute * (0.5 + 0.5 * math.sin(flutes * a + twist * i))) * rnd.uniform(0.93, 1.07)
            co = p + (normal * math.cos(a) + binormal * math.sin(a)) * r
            if last and jag:
                splinter = rnd.uniform(0.4, 1.0) if rnd.random() < 0.3 else rnd.uniform(-0.35, 0.1)
                co += t * jag * (0.45 * math.cos(a - slant) + splinter)
            ring.append(bm.verts.new(co))
        rings.append(ring)
    for a, b in itertools.pairwise(rings):
        for s in range(sides):
            bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
    t0 = (path[1] - path[0]).normalized()
    t1 = (path[-1] - path[-2]).normalized()
    start = bm.verts.new(path[0] - t0 * radii[0] * 0.1)
    end = bm.verts.new(path[-1] - t1 * (jag * 0.8 if jag else 0.0))
    for s in range(sides):
        bm.faces.new((rings[0][(s + 1) % sides], rings[0][s], start))
        bm.faces.new((rings[-1][s], rings[-1][(s + 1) % sides], end))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if caps is not None:
        caps.append((path[0].copy(), -t0, radii[0]))
        caps.append((path[-1].copy(), t1, radii[-1] + jag))
    return bm


def curve(points: list, steps: int) -> list:
    """Catmull-Rom path through `points`, `steps` samples per span (smooth wood bends)."""
    pts = [points[0], *points, points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(steps):
            t = s / steps
            out.append(
                0.5
                * (
                    2 * p1
                    + (p2 - p0) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                    + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t
                )
            )
    out.append(points[-1].copy())
    return out


# --- mesh assembly ------------------------------------------------------------------------------------


def solid(
    name: str,
    mat: bpy.types.Material,
    parts: list,
    cutters: list = (),
    center: bool = True,
    back_y: float | None = None,
    sharp_deg: float = SHARP_DEG,
    caps: list = (),
) -> bpy.types.Object:
    """Union of the parts minus the cutters, cleaned up, bottom cut flat at -SINK, origin at the bottom center
    (`center` False: kept where it was built, e.g. a trunk or a vent mouth at the origin); returns the finished part
    in the asset collection."""
    base = bm_to_obj(parts[0], name + "_base")
    if len(parts) > 1:
        coll = work_collection(name + "_union")
        for i, bm in enumerate(parts[1:]):
            bm_to_obj(bm, f"{name}_u{i}", coll.name)
        add_boolean(base, "UNION", coll)
    if cutters:
        coll = work_collection(name + "_cut")
        for i, bm in enumerate(cutters):
            bm_to_obj(bm, f"{name}_c{i}", coll.name)
        add_boolean(base, "DIFFERENCE", coll)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    finish_mesh(bm, name, center, back_y, sharp_deg)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    face_attributes(me, name, caps)
    obj = bpy.data.objects.new(name, me)
    C.link(obj, ROOT_OBJ)
    C.assign(obj, mat)
    return obj


def finish_mesh(bm: bmesh.types.BMesh, name: str, center: bool, back_y: float | None, sharp_deg: float) -> None:
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.004)
    bmesh.ops.dissolve_degenerate(bm, dist=0.003, edges=bm.edges[:])
    cut(bm, (0, 0, -1), at=SINK[name])  # flat bottom at z = -SINK (normal points down: keeps what's above)
    if back_y is not None:
        cut(bm, (0, 1, 0), at=back_y)
    # Merge the coplanar triangles the hulls and booleans leave on the big facets (fewer triangles).
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(2.0), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if center:
        lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), 0))
        hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), 0))
        shift = -(lo + hi) / 2
        if back_y is not None:
            shift.y = 0
        bmesh.ops.translate(bm, vec=shift, verts=bm.verts[:])
    sharp = math.radians(sharp_deg)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > sharp)
    for f in bm.faces:
        f.smooth = True


def face_attributes(me: bpy.types.Mesh, seed: str, caps: list) -> None:
    """ "facet": a random value per face (each fracture plane its own tone); "inner": 1 on the faces of the wood's
    broken ends (within a cap's radius of its center, facing along its axis)."""
    rnd = random.Random(seed)
    facet = me.attributes.new("facet", "FLOAT", "FACE")
    facet.data.foreach_set("value", [rnd.random() for _ in me.polygons])
    inner = me.attributes.new("inner", "FLOAT", "FACE")
    values = []
    for p in me.polygons:
        c, n = Vector(p.center), Vector(p.normal)
        hit = any((c - cc).length < r * 1.15 and n.dot(axis) > 0.35 for cc, axis, r in caps)
        values.append(1.0 if hit else 0.0)
    inner.data.foreach_set("value", values)


# --- parts --------------------------------------------------------------------------------------------


def boulder_a() -> bpy.types.Object:
    """Blocky basalt boulder: a big sharp-faceted block with a wedge split off its side and a slab leaning on it,
    chipped ridges, a crack and a few gas holes."""
    rnd = random.Random(101)
    main = chunk(
        rnd, (1.4, 1.2, 1.55), 9, T((0, 0, 0.6), rz(18) @ ry(8)), keep=(0.72, 0.9), jitter=0.22, extra=14, bulge=0.25
    )
    wedge = chunk(rnd, (0.7, 0.55, 0.7), 6, T((0.6, -0.4, 0.2), rz(-30) @ ry(22)), keep=(0.62, 0.86), jitter=0.2)
    slab = chunk(rnd, (0.8, 0.32, 0.65), 5, T((-0.5, 0.42, 0.15), rz(40) @ rx(-24)), keep=(0.66, 0.88))
    cutters = [
        chip_cutter(rnd, main, (0.6, -0.6, 0.9), 0.34),
        chip_cutter(rnd, main, (-0.8, 0.2, 0.7), 0.3),
        chip_cutter(rnd, main, (0.1, 0.8, 0.8), 0.28),
        crack_cutter(rnd, (-0.1, -0.6, 0.6), 1.3, 0.9, 0.05, rz(10) @ rx(-8) @ ry(28)),
    ]
    for _ in range(7):
        p = support(main, rand_dir(rnd, min_z=-0.1)) * 0.97
        cutters.append(pit_cutter(rnd, p, rnd.uniform(0.04, 0.08)))
    return solid("Boulder_a", MATS["basalt"], [main, wedge, slab], cutters)


def boulder_b() -> bpy.types.Object:
    """A fallen column piece: a thick hexagonal basalt segment lying on its side, both ends broken, a smaller
    fragment against it."""
    rnd = random.Random(202)
    log = hex_prism(rnd, 0.5, 1.5, jitter=0.1, taper=0.9)
    for _ in range(2):  # broken ends: oblique, stepped fractures
        a = rnd.uniform(-0.9, 0.9)
        cut(log, (math.sin(a), math.cos(a) * 0.5, 1.0), rnd.uniform(0.8, 0.92))
        cut(log, (math.sin(a), math.cos(a) * 0.5, -1.0), rnd.uniform(0.8, 0.92))
    shave(log, rnd, 2, keep=(0.86, 0.95))
    place(log, T((0, 0, 0.3), rz(8) @ ry(90) @ rz(rnd.uniform(0, 60))))
    frag = chunk(rnd, (0.55, 0.45, 0.4), 5, T((0.55, 0.52, 0.06), rz(35) @ ry(-12)), keep=(0.66, 0.88), jitter=0.2)
    cutters = [
        chip_cutter(rnd, log, (0.2, -0.7, 1.0), 0.34),
        chip_cutter(rnd, log, (-0.8, 0.5, 0.8), 0.3),
        chip_cutter(rnd, log, (0.9, 0.3, 0.6), 0.28),
        crack_cutter(rnd, (-0.25, -0.4, 0.45), 1.1, 0.9, 0.05, rz(84) @ ry(15)),
        crack_cutter(rnd, (0.3, 0.0, 0.6), 0.9, 1.2, 0.045, rz(-10) @ rx(70)),
    ]
    for _ in range(4):
        p = support(log, rand_dir(rnd, min_z=0.0)) * 0.97
        cutters.append(pit_cutter(rnd, p, rnd.uniform(0.04, 0.07)))
    return solid("Boulder_b", MATS["basalt"], [log, frag], cutters)


def columns_a() -> bpy.types.Object:
    """Cluster of hexagonal basalt columns on a hex grid, 1-4 m tall, broken tops, long segments with faint joints,
    a toppled piece at the foot (cover)."""
    rnd = random.Random(303)
    s = SINK["Columns_a"]
    r = 0.3
    pitch = r * 1.76
    cells = [(0, 0), (1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1), (1, 1)]
    heights = [4.0, 3.3, 3.7, 2.8, 2.4, 1.5, 2.1, 1.0]
    parts = []
    for (q, w), h in zip(cells, heights):
        x = pitch * (q + w * 0.5)
        y = pitch * w * math.sqrt(3) / 2
        parts += basalt_column(
            rnd,
            r * rnd.uniform(0.95, 1.03),
            h + s,
            Vector((x, y, -s)),
            segment=(1.0, 1.9),
            top_tilt=rnd.uniform(0.25, 0.9),
            lean=1.2,
            chamfer=0.025,
        )
    fallen = hex_prism(rnd, 0.27, 1.0)
    cut(fallen, (0.4, 0.2, 1.0), 0.9)
    parts.append(place(fallen, T((0.45, -1.0, 0.2), rz(-25) @ ry(84))))
    cutters = [
        chip_cutter(rnd, parts[rnd.randrange(len(parts) - 1)], (rnd.uniform(-1, 1), -0.8, 0.6), 0.26) for _ in range(4)
    ]
    cutters.append(crack_cutter(rnd, (0.0, -0.4, 2.3), 1.0, 0.8, 0.04, rz(-20) @ ry(8)))
    return solid("Columns_a", MATS["basalt"], parts, cutters)


def scoria_a() -> bpy.types.Object:
    """A cluster of porous scoria lumps (the biggest about 0.7 m across), knobbly and riddled with gas holes;
    walk-through."""
    rnd = random.Random(404)
    parts, spots = [], []
    sizes = [0.42, 0.27, 0.2, 0.14, 0.1]
    for i, size in enumerate(sizes):
        for _ in range(40):
            a = rnd.uniform(0, math.tau)
            d = 0.0 if i == 0 else rnd.uniform(0.35, 0.55)
            p = Vector((math.cos(a) * d, math.sin(a) * d, 0))
            if all((p - q).length > (size + t) * 0.85 for q, t in spots):
                break
        spots.append((p, size))
        bm = hull(blob_points(rnd, size, 30, rnd.uniform(0.8, 0.95), 0.45))
        parts.append(place(bm, T((p.x, p.y, size * rnd.uniform(0.45, 0.6)), rand_rot(rnd, 20))))
    cutters = []
    for bm, (_p, size) in zip(parts, spots):
        for _ in range(5 if size > 0.3 else (2 if size > 0.15 else 1)):
            q = support(bm, rand_dir(rnd, min_z=0.15)) * 0.97
            cutters.append(pit_cutter(rnd, q, size * rnd.uniform(0.25, 0.38)))
    return solid("Scoria_a", MATS["scoria"], parts, cutters)


def stump_a() -> bpy.types.Object:
    """A charred dead tree stump, about 2.3 m: a thick fluted, twisting trunk splintered at the top, two broken
    branch stubs and buttress roots spreading over the ground (cover)."""
    rnd = random.Random(505)
    caps: list = []
    trunk_pts = [Vector((0, 0, -0.3)), Vector((0.02, 0, 0.5)), Vector((-0.05, 0.04, 1.3)), Vector((0.06, 0.02, 2.1))]
    path = curve(trunk_pts, 3)
    radii = [0.4 - 0.15 * (i / (len(path) - 1)) ** 0.7 for i in range(len(path))]
    radii[0] = radii[1] = 0.46
    parts = [tube(rnd, path, radii, sides=14, flutes=7, flute=0.18, twist=0.25, jag=0.32, caps=caps)]
    for z, ang, length, up in ((1.3, 30, 0.7, 0.55), (1.65, 190, 0.5, 0.8)):
        d = Vector((math.cos(math.radians(ang)), math.sin(math.radians(ang)), up)).normalized()
        start = Vector((0, 0, z))
        bend = d * length * 0.55 + Vector((0, 0, length * 0.15))
        pts = curve([start, start + bend, start + d * length + Vector((0, 0, length * 0.25))], 2)
        r0 = 0.13
        parts.append(
            tube(rnd, pts, [r0 * (1 - 0.4 * i / (len(pts) - 1)) for i in range(len(pts))], 8, 4, 0.1, 0, 0.1, caps)
        )
    for k in range(7):
        ang = k / 7 * math.tau + rnd.uniform(-0.25, 0.25)
        swing = rnd.uniform(-0.35, 0.35)  # roots curl sideways as they run out
        reach = rnd.uniform(0.85, 1.3)

        def out(dist: float, z: float, ang=ang, swing=swing, reach=reach) -> Vector:
            a = ang + swing * dist / reach
            return Vector((math.cos(a) * dist, math.sin(a) * dist, z))

        path_r = curve([out(0.2, 0.6), out(0.5, 0.2), out(reach * 0.75, 0.04), out(reach, -0.12)], 2)
        r0 = rnd.uniform(0.17, 0.22)
        radii_r = [r0 * (1 - 0.75 * (i / (len(path_r) - 1)) ** 0.8) for i in range(len(path_r))]
        parts.append(tube(rnd, path_r, radii_r, sides=8, flutes=3, flute=0.15, twist=0.2))
    return solid("Stump_a", MATS["char_up"], parts, center=False, sharp_deg=WOOD_SHARP_DEG, caps=caps)


def stump_b() -> bpy.types.Object:
    """A fallen charred trunk, about 3 m long and 0.6 m high: broken at both ends, two snapped branch stubs, a
    split along its top (low cover)."""
    rnd = random.Random(606)
    caps: list = []
    pts = curve(
        [Vector((-1.5, 0.05, 0.27)), Vector((-0.4, -0.04, 0.25)), Vector((0.7, 0.04, 0.23)), Vector((1.5, 0.1, 0.2))], 3
    )
    radii = [0.31 - 0.08 * i / (len(pts) - 1) for i in range(len(pts))]
    parts = [tube(rnd, pts, radii, sides=12, flutes=6, flute=0.14, twist=0.15, jag=0.2, caps=caps)]
    # The far end splintered too: a jagged cap built as a second tube end, reversed.
    rev = [p.copy() for p in reversed(pts[:4])]
    parts.append(tube(rnd, rev, [radii[0] * 0.98] * 4, sides=12, flutes=6, flute=0.14, twist=0.15, jag=0.22, caps=caps))
    for x, ang, up, length in ((-0.55, 75, 0.45, 0.4), (0.75, -95, 0.3, 0.3)):
        d = Vector((0.3, math.sin(math.radians(ang)), up)).normalized()
        start = Vector((x, 0, 0.25))
        sp = curve([start, start + d * (0.3 + length * 0.5), start + d * (0.3 + length)], 2)
        parts.append(
            tube(rnd, sp, [0.11 * (1 - 0.35 * i / (len(sp) - 1)) for i in range(len(sp))], 8, 4, 0.1, 0, 0.08, caps)
        )
    cutters = [crack_cutter(rnd, (-0.2, 0.0, 0.5), 1.6, 0.3, 0.07, rx(-90))]  # a split along the top
    return solid("Stump_b", MATS["char_side"], parts, cutters, sharp_deg=WOOD_SHARP_DEG, caps=caps)


def vent_a() -> bpy.types.Object:
    """The vent: a low cinder cone, 2.2 m across and 0.5 m high, a crater mouth about 0.7 m across in its top, the
    crust cracked radially, loose cinders around its foot. Origin at the middle of its base."""
    rnd = random.Random(707)
    s = SINK["Vent_a"]
    # Lathe profile (radius, height): outer flank up to the rim, then down the crater wall to the throat's floor.
    profile = [
        (1.2, -s - 0.02),
        (1.12, 0.0),
        (0.98, 0.07),
        (0.8, 0.19),
        (0.62, 0.33),
        (0.47, 0.46),
        (0.38, 0.52),
        (0.32, 0.47),
        (0.26, 0.33),
        (0.18, 0.18),
        (0.09, 0.1),
    ]
    sides = 28
    bm = bmesh.new()
    rings = []
    phase = [rnd.uniform(0, math.tau) for _ in range(4)]
    for i, (r, z) in enumerate(profile):
        ring = []
        for k in range(sides):
            a = k / sides * math.tau
            wob = 1 + 0.07 * math.sin(3 * a + phase[0]) + 0.05 * math.sin(5 * a + phase[1])
            dz = 0.0
            if 4 <= i <= 7:  # a ragged rim
                dz = 0.05 * math.sin(4 * a + phase[2]) + rnd.uniform(-0.035, 0.035)
            rr = r * wob * (1 + rnd.uniform(-0.04, 0.04) if 0 < i < len(profile) - 1 else 1)
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z + dz)))
        rings.append(ring)
    for a, b in itertools.pairwise(rings):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    bottom = bm.verts.new((0, 0, -s - 0.02))
    floor = bm.verts.new((0, 0, 0.08))
    for k in range(sides):
        bm.faces.new((rings[0][(k + 1) % sides], rings[0][k], bottom))
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], floor))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    parts = [bm]
    # Cinders and clasts around the foot, half buried.
    for _ in range(9):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0.95, 1.3)
        size = rnd.uniform(0.1, 0.22)
        m = T((math.cos(a) * rr, math.sin(a) * rr, -0.02), rand_rot(rnd, 30))
        parts.append(chunk(rnd, (size, size * 0.8, size * 0.6), 4, m, keep=(0.6, 0.85), jitter=0.25, extra=5))
    cutters = []
    for k in range(6):  # radial cracks down the flank from the rim
        a = k / 6 * 360 + rnd.uniform(-20, 20)
        mid = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0)) * 0.62 + Vector((0, 0, 0.36))
        cutters.append(crack_cutter(rnd, mid, 0.7, 0.16, 0.06, rz(a) @ ry(30) @ rx(-90)))
    return solid("Vent_a", MATS["vent"], parts, cutters, center=False, sharp_deg=WOOD_SHARP_DEG)


def cliff_a() -> bpy.types.Object:
    """Columnar basalt cliff: packed hexagonal columns rising in steps to a jagged, broken crest (3-5.3 m), stacked
    segments, a few broken-off columns and fallen pieces at the foot; flat back."""
    rnd = random.Random(808)
    s = SINK["Cliff_a"]
    r = 0.38
    pitch = r * 1.75
    parts = []
    # Two rows of columns: the front one in stacked segments, the one behind (mostly seen from above, at the crest)
    # in one piece each; a core block fills the rest to the flat back.
    for row, (y, hmin, hmax, seg) in enumerate(((-0.62, 3.0, 4.6, (1.8, 3.2)), (0.0, 3.8, 5.3, (9.0, 9.0)))):
        x = -3.1 + row * pitch * 0.5
        while x < 3.15:
            h = rnd.uniform(hmin, hmax) * (0.85 if abs(x) > 2.6 else 1.0)
            parts += basalt_column(
                rnd, r * rnd.uniform(0.92, 1.06), h + s, Vector((x, y, -s)), seg, 0.9, 1.5, chamfer=0.0
            )
            x += pitch * rnd.uniform(0.97, 1.03)
    parts.append(chunk(rnd, (6.4, 0.9, 3.6), 0, T((0, 0.6, 1.3)), jitter=0.02, extra=0))
    for x in (rnd.uniform(-2.4, -1.4), rnd.uniform(0.2, 1.0), rnd.uniform(1.8, 2.6)):  # broken-off columns in front
        parts += basalt_column(
            rnd, r * 0.95, rnd.uniform(0.9, 1.9) + s, Vector((x, -1.2, -s)), (3.0, 3.0), 1.0, 2.0, chamfer=0.0
        )
    for _ in range(2):
        fallen = hex_prism(rnd, 0.3, rnd.uniform(0.7, 1.1))
        cut(fallen, (0.5, 0.2, 1.0), 0.9)
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.75, -1.5), 0.2)
        parts.append(place(fallen, T(p, rz(rnd.uniform(-40, 40)) @ ry(86))))
    cutters = []
    for z in (1.4, 2.6, 3.7):
        cutters.append(
            crack_cutter(
                rnd,
                (rnd.uniform(-2.2, 2.2), -1.0, z + rnd.uniform(-0.3, 0.3)),
                rnd.uniform(1.4, 2.2),
                0.9,
                0.07,
                rz(rnd.uniform(-6, 6)) @ ry(rnd.uniform(-10, 10)),
            )
        )
    return solid("Cliff_a", MATS["basalt"], parts, cutters, back_y=CLIFF_BACK)


def cliff_b() -> bpy.types.Object:
    """Sharp ridge cliff: a short colonnade at the foot under a chaotic, blocky upper flow that breaks into sharp
    jagged peaks (up to about 5.5 m), fallen blocks below; flat back."""
    rnd = random.Random(909)
    s = SINK["Cliff_b"]
    parts = []
    x = -3.1
    while x < 3.15:  # the colonnade
        h = rnd.uniform(1.6, 2.4)
        parts += basalt_column(rnd, 0.34, h + s, Vector((x, -0.7, -s)), (3.0, 3.0), 0.3, 1.0, 0.0)
        x += 0.6 * rnd.uniform(0.97, 1.05)
    parts.append(chunk(rnd, (6.4, 1.4, 2.3), 0, T((0, 0.3, 0.7)), jitter=0.02, extra=0))  # core behind it
    peaks = [(-2.5, 3.6), (-1.5, 4.8), (-0.6, 4.0), (0.4, 5.5), (1.3, 4.4), (2.3, 4.9), (3.0, 3.7)]
    for px, top in peaks:  # the upper flow: tall shards with steep fractured tops
        base_z = 1.6
        for _ in range(2):
            w = rnd.uniform(0.7, 1.1)
            h = top - base_z + rnd.uniform(-0.6, 0.0)
            pts = []
            for cx in (-1, 1):
                for cy in (-1, 1):
                    pts.append(Vector((cx * w / 2 * rnd.uniform(0.8, 1.1), cy * 0.75 * rnd.uniform(0.8, 1.1), 0)))
                    pts.append(
                        Vector(
                            (
                                cx * w / 2 * rnd.uniform(0.2, 0.55),
                                cy * 0.4 * rnd.uniform(0.6, 1.0),
                                h * rnd.uniform(0.75, 1.0),
                            )
                        )
                    )
            bm = hull(pts)
            a = rnd.uniform(-1.2, 1.2)
            cut(bm, (math.sin(a), -0.4, 1.0), rnd.uniform(0.86, 0.95))
            for _ in range(2):
                cut(bm, (rnd.uniform(-1, 1), -1.0, rnd.uniform(-0.4, 0.6)), rnd.uniform(0.85, 0.95))
            m = T(
                (px + rnd.uniform(-0.25, 0.25), rnd.uniform(-0.05, 0.4), base_z),
                rz(rnd.uniform(-8, 8)) @ ry(rnd.uniform(-7, 7)),
            )
            parts.append(place(bm, m))
    for _ in range(2):  # blocks of the upper flow jutting out over the colonnade
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-0.75, -0.55), rnd.uniform(1.9, 2.5))
        parts.append(chunk(rnd, (rnd.uniform(0.7, 1.1), 0.7, rnd.uniform(0.45, 0.7)), 4, T(p, rand_rot(rnd, 15))))
    for _ in range(2):
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.5, -1.2), 0.05)
        parts.append(chunk(rnd, (rnd.uniform(0.5, 0.85), 0.55, rnd.uniform(0.35, 0.55)), 4, T(p, rand_rot(rnd, 25))))
    cutters = [
        chip_cutter(rnd, parts[rnd.randrange(len(parts))], (rnd.uniform(-0.6, 0.6), -0.7, 0.8), rnd.uniform(0.35, 0.5))
        for _ in range(4)
    ]
    return solid("Cliff_b", MATS["basalt"], parts, cutters, back_y=CLIFF_BACK)


BUILDERS = {
    "Boulder_a": boulder_a,
    "Boulder_b": boulder_b,
    "Columns_a": columns_a,
    "Scoria_a": scoria_a,
    "Stump_a": stump_a,
    "Stump_b": stump_b,
    "Vent_a": vent_a,
    "Cliff_a": cliff_a,
    "Cliff_b": cliff_b,
}

# --- materials ----------------------------------------------------------------------------------------


class Mat:
    """Node helpers for one procedural material (numbers are set, sockets linked; colors are sRGB tuples)."""

    def __init__(self, name: str):
        self.mat, self.nt, self.bsdf = C._new_material(name)
        self.coord = self.nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        self.geo = self.nt.nodes.new("ShaderNodeNewGeometry")

    def math(self, op: str, a, b=None, c=None, clamp: bool = False) -> bpy.types.NodeSocket:
        return C._math(self.nt, op, a, b, c, clamp)

    def noise(self, scale: float, detail: float = 4.0, rough: float = 0.6, vector=None) -> bpy.types.NodeSocket:
        return C._noise(self.nt, scale, detail, rough, vector or self.coord).outputs["Fac"]

    def ramp(self, a: float, b: float, src) -> bpy.types.NodeSocket:
        return C._ramp(self.nt, a, b, src)

    def mix(self, fac, a, b) -> bpy.types.NodeSocket:
        a = srgb(*a) if isinstance(a, tuple) else a
        b = srgb(*b) if isinstance(b, tuple) else b
        return C._mix_color(self.nt, fac, a, b)

    def lerp(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_float(self.nt, fac, a, b)

    def attr(self, name: str) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeAttribute")
        node.attribute_type = "GEOMETRY"
        node.attribute_name = name
        return node.outputs["Fac"]

    def scaled(self, sx: float, sy: float, sz: float, vector=None) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = "MULTIPLY"
        self.nt.links.new(vector or self.coord, node.inputs[0])
        node.inputs[1].default_value = (sx, sy, sz)
        return node.outputs[0]

    def warped(self, scale: float, amount: float) -> bpy.types.NodeSocket:
        """Object coordinates bent by a noise (no straight Voronoi lines)."""
        warp = C._noise(self.nt, scale, 3.0, 0.5, vector=self.coord)
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = "MULTIPLY_ADD"
        self.nt.links.new(warp.outputs["Color"], node.inputs[0])
        node.inputs[1].default_value = (amount, amount, amount)
        self.nt.links.new(self.coord, node.inputs[2])
        return node.outputs[0]

    def pits(self, scale: float, radius: float, vector=None) -> bpy.types.NodeSocket:
        """1 inside round holes (vesicles) on a Voronoi grid of `scale` cells per meter, `radius` of a cell."""
        vor = self.nt.nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = scale
        self.nt.links.new(vector or self.coord, vor.inputs["Vector"])
        return self.math("SUBTRACT", 1.0, self.ramp(radius * 0.55, radius, vor.outputs["Distance"]), clamp=True)

    def lines(self, vector, scale: float, width: float) -> bpy.types.NodeSocket:
        return C._voronoi_lines(self.nt, vector, scale, width)

    def up(self, lo: float = 0.45, hi: float = 0.8) -> bpy.types.NodeSocket:
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.geo.outputs["Normal"], sep.inputs["Vector"])
        return self.ramp(lo, hi, sep.outputs["Z"])

    def cavity(self, distance: float, lo: float = 0.25, hi: float = 0.95) -> bpy.types.NodeSocket:
        """1 in occluded spots (cracks, crevices), 0 in the open (ray-traced AO, baked)."""
        ao = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = distance
        ao.samples = 16
        return self.math("SUBTRACT", 1.0, self.ramp(lo, hi, ao.outputs["AO"]), clamp=True)

    def edges(self, radius: float, lo: float, hi: float) -> bpy.types.NodeSocket:
        return self.ramp(lo, hi, C._bevel_edge(self.nt, radius, self.geo))

    def shade(self, col, fac) -> bpy.types.NodeSocket:
        """Color times a factor (socket or number)."""
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = "SCALE"
        self.nt.links.new(col, node.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, node.inputs["Scale"])
        else:
            node.inputs["Scale"].default_value = fac
        return node.outputs[0]

    def radius_xy(self) -> bpy.types.NodeSocket:
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.coord, sep.inputs["Vector"])
        return self.math(
            "SQRT",
            self.math("ADD", self.math("POWER", sep.outputs["X"], 2.0), self.math("POWER", sep.outputs["Y"], 2.0)),
        )

    def z(self) -> bpy.types.NodeSocket:
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.coord, sep.inputs["Vector"])
        return sep.outputs["Z"]

    def finish(
        self, color, rough, height, bump: float, distance: float, emit=None, emit_color=None
    ) -> bpy.types.Material:
        self.nt.links.new(color, self.bsdf.inputs["Base Color"])
        self.nt.links.new(rough, self.bsdf.inputs["Roughness"])
        self.bsdf.inputs["Metallic"].default_value = 0.0
        C._bump(self.nt, self.bsdf, height, bump, distance)
        if emit is not None:
            self.bsdf.inputs["Emission Color"].default_value = (*srgb(*emit_color), 1.0)
            self.nt.links.new(emit, self.bsdf.inputs["Emission Strength"])
        return self.mat


EMBER = (1.0, 0.36, 0.08)  # sRGB: dim glow in the deepest cracks and the vent's throat


def mat_basalt() -> bpy.types.Material:
    """Black-grey basalt: per-facet tone, faint flow banding, sharp lighter fracture edges, gas holes, dark cracks
    and crevices, a little rust, pale ash dust on the up-facing faces; rough with a slight glassy sheen."""
    m = Mat("AshBasalt")
    warped = m.warped(1.4, 0.35)
    breakup = m.noise(2.2, 4.0, 0.55)
    crack = m.math(
        "MAXIMUM",
        m.math("MULTIPLY", m.lines(warped, 0.9, 0.026), m.ramp(0.45, 0.6, breakup)),
        m.math("MULTIPLY", m.lines(warped, 3.2, 0.02), m.math("MULTIPLY", m.ramp(0.55, 0.7, breakup), 0.6)),
    )
    tone = m.noise(0.8, 5.0, 0.6)
    base = m.mix(m.ramp(0.3, 0.72, tone), (0.13, 0.13, 0.135), (0.2, 0.196, 0.192))
    base = m.shade(base, m.math("MULTIPLY_ADD", m.attr("facet"), 0.5, 0.75))
    grain = m.noise(42.0, 4.0, 0.7)
    base = m.shade(base, m.math("MULTIPLY_ADD", grain, 0.35, 0.83))
    rust = m.math("MULTIPLY", m.ramp(0.6, 0.75, m.noise(1.3, 4.0, 0.6)), 0.45)
    base = m.mix(rust, base, (0.2, 0.135, 0.105))
    holes = m.math("MAXIMUM", m.pits(9.0, 0.24), m.math("MULTIPLY", m.pits(22.0, 0.22), 0.8))
    holes = m.math("MULTIPLY", holes, m.ramp(0.35, 0.55, m.noise(1.7, 3.0, 0.6)))
    edge = m.math("MULTIPLY", m.edges(0.035, 0.015, 0.09), m.ramp(0.3, 0.6, m.noise(9.0, 3.0, 0.6)))
    col = m.mix(edge, base, m.shade(base, 1.6))
    col = m.mix(m.cavity(0.35), col, (0.035, 0.034, 0.033))
    col = m.mix(holes, col, (0.03, 0.029, 0.028))
    col = m.mix(crack, col, (0.025, 0.024, 0.023))
    dust = m.math("MULTIPLY", m.up(0.5, 0.85), m.ramp(0.42, 0.62, m.noise(3.5, 6.0, 0.65)))
    dust = m.math("MULTIPLY", dust, m.math("SUBTRACT", 1.0, m.math("MAXIMUM", crack, holes), clamp=True))
    col = m.mix(m.math("MULTIPLY", dust, 0.7), col, m.mix(grain, (0.24, 0.233, 0.225), (0.32, 0.31, 0.3)))
    rough = m.lerp(tone, 0.78, 0.9)
    rough = m.lerp(edge, rough, 0.62)
    rough = m.lerp(dust, rough, 0.97)
    lumps = m.nt.nodes.new("ShaderNodeTexVoronoi")
    lumps.feature = "SMOOTH_F1"
    lumps.inputs["Scale"].default_value = 3.0
    m.nt.links.new(warped, lumps.inputs["Vector"])
    height = m.math("MULTIPLY", lumps.outputs["Distance"], 0.5)
    height = m.math("ADD", height, m.math("MULTIPLY", grain, 0.25))
    height = m.math("SUBTRACT", height, m.math("MULTIPLY", m.math("MAXIMUM", crack, holes), 0.9))
    return m.finish(col, rough, height, 0.55, 0.03)


def mat_scoria() -> bpy.types.Material:
    """Porous scoria: dark red-brown to black, riddled with gas holes of two sizes (dark, sunk), a little ash in
    the hollows' rims on top; very rough."""
    m = Mat("AshScoria")
    tone = m.noise(1.6, 4.0, 0.6)
    base = m.mix(m.ramp(0.3, 0.7, tone), (0.12, 0.085, 0.078), (0.22, 0.135, 0.11))
    base = m.mix(m.ramp(0.55, 0.75, m.noise(3.0, 3.0, 0.6)), base, (0.09, 0.08, 0.078))
    base = m.shade(base, m.math("MULTIPLY_ADD", m.attr("facet"), 0.3, 0.85))
    grain = m.noise(55.0, 3.0, 0.7)
    base = m.shade(base, m.math("MULTIPLY_ADD", grain, 0.4, 0.8))
    holes = m.math("MAXIMUM", m.pits(7.0, 0.36), m.math("MULTIPLY", m.pits(20.0, 0.32), 0.85))
    col = m.mix(holes, base, (0.025, 0.018, 0.016))
    col = m.mix(m.cavity(0.2), col, (0.03, 0.022, 0.02))
    dust = m.math("MULTIPLY", m.up(0.55, 0.9), m.ramp(0.45, 0.7, m.noise(4.0, 4.0, 0.6)))
    dust = m.math("MULTIPLY", dust, m.math("SUBTRACT", 1.0, holes))
    col = m.mix(m.math("MULTIPLY", dust, 0.7), col, (0.27, 0.26, 0.25))
    rough = m.lerp(dust, 0.93, 0.98)
    height = m.math("SUBTRACT", m.math("MULTIPLY", grain, 0.3), holes)
    return m.finish(col, rough, height, 0.7, 0.02)


def mat_char(name: str, axis: str) -> bpy.types.Material:
    """Charred wood, the grain along `axis` ("Z" standing, "X" lying): black char broken into blocks by deep
    cracks (alligator char) with a very faint ember glow deep in a few of them, fibers along the grain, grey ash
    on the tops, the broken ends ("inner") bare dull brown-grey wood."""
    m = Mat(name)
    k = (8.0, 8.0, 3.5) if axis == "Z" else (3.5, 8.0, 8.0)
    blocks = m.scaled(*k)
    cracks = m.lines(blocks, 1.0, 0.07)
    big = m.lines(m.scaled(k[0] * 0.35, k[1] * 0.35, k[2] * 0.35), 1.0, 0.035)
    crack = m.math("MAXIMUM", cracks, big)
    wave = m.nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = axis
    wave.wave_type = "BANDS"
    wave.inputs["Scale"].default_value = 1.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 4.0
    fibers_vec = m.scaled(18.0, 18.0, 1.0) if axis == "Z" else m.scaled(1.0, 18.0, 18.0)
    m.nt.links.new(fibers_vec, wave.inputs["Vector"])
    fiber = wave.outputs["Fac"]
    tone = m.noise(1.5, 4.0, 0.6)
    char = m.mix(m.ramp(0.3, 0.7, tone), (0.065, 0.06, 0.056), (0.11, 0.098, 0.088))
    char = m.shade(char, m.math("MULTIPLY_ADD", fiber, 0.35, 0.82))
    sheen = m.ramp(0.5, 0.8, m.noise(6.0, 3.0, 0.6))  # glossy patches of fresh char
    col = m.mix(m.math("MULTIPLY", crack, 0.95), char, (0.02, 0.018, 0.017))
    col = m.mix(m.cavity(0.25), col, (0.025, 0.022, 0.02))
    inner = m.attr("inner")
    wood = m.mix(m.ramp(0.3, 0.7, m.noise(12.0, 3.0, 0.6)), (0.2, 0.165, 0.13), (0.27, 0.22, 0.17))
    col = m.mix(
        m.math("MULTIPLY", inner, m.math("SUBTRACT", 1.0, m.math("MULTIPLY", m.ramp(0.4, 0.7, tone), 0.6))), col, wood
    )
    ash = m.math("MULTIPLY", m.up(0.5, 0.85), m.ramp(0.35, 0.65, m.noise(4.0, 4.0, 0.6)))
    ash = m.math("MULTIPLY", m.math("MULTIPLY", ash, m.math("SUBTRACT", 1.0, crack, clamp=True)), 0.8)
    col = m.mix(ash, col, (0.3, 0.29, 0.28))
    rough = m.lerp(sheen, 0.9, 0.62)
    rough = m.lerp(m.math("MAXIMUM", ash, inner), rough, 0.95)
    # Embers: only in the crack lines, in rare patches, more in the deep (occluded) ones, never on bare wood or ash.
    patches = m.ramp(0.62, 0.72, m.noise(2.5, 3.0, 0.6))
    ember = m.math("MULTIPLY", m.math("MULTIPLY", cracks, patches), m.math("ADD", 0.35, m.cavity(0.2, 0.4, 0.9)))
    ember = m.math("MULTIPLY", ember, m.math("SUBTRACT", 1.0, m.math("MAXIMUM", inner, ash), clamp=True))
    ember = m.math("MULTIPLY", m.math("MULTIPLY", ember, m.up(-0.6, -0.1)), 0.6)  # none on the undersides
    height = m.math("ADD", m.math("MULTIPLY", fiber, 0.25), m.math("MULTIPLY", crack, -1.0))
    return m.finish(col, rough, height, 0.6, 0.02, emit=ember, emit_color=EMBER)


def mat_vent() -> bpy.types.Material:
    """The vent's cinder crust: black-grey cinder with gas holes, cracked into plates, baked rust-brown around the
    rim, pale ash on the lower flank; the throat dark with a faint ember glow at its bottom and in the cracks
    nearest the mouth."""
    m = Mat("AshVent")
    r = m.radius_xy()
    z = m.z()
    tone = m.noise(2.0, 4.0, 0.6)
    base = m.mix(m.ramp(0.3, 0.7, tone), (0.1, 0.095, 0.092), (0.17, 0.16, 0.152))
    base = m.shade(base, m.math("MULTIPLY_ADD", m.attr("facet"), 0.3, 0.85))
    grain = m.noise(45.0, 3.0, 0.7)
    base = m.shade(base, m.math("MULTIPLY_ADD", grain, 0.35, 0.82))
    near = m.math("SUBTRACT", 1.0, m.ramp(0.35, 0.75, r), clamp=True)  # 1 at the rim, 0 out on the flank
    baked = m.math("MULTIPLY", near, m.ramp(0.35, 0.65, m.noise(3.0, 4.0, 0.6)))
    base = m.mix(m.math("MULTIPLY", baked, 0.6), base, (0.22, 0.13, 0.095))
    plates = m.lines(m.warped(2.0, 0.25), 3.5, 0.03)
    holes = m.math("MULTIPLY", m.pits(16.0, 0.28), 0.9)
    col = m.mix(holes, base, (0.03, 0.028, 0.027))
    col = m.mix(plates, col, (0.025, 0.022, 0.02))
    col = m.mix(m.cavity(0.25), col, (0.02, 0.018, 0.017))
    throat = m.math(
        "MULTIPLY",
        m.math("SUBTRACT", 1.0, m.ramp(0.3, 0.36, r), clamp=True),
        m.math("SUBTRACT", 1.0, m.ramp(0.38, 0.48, z), clamp=True),
    )
    col = m.mix(throat, col, (0.035, 0.03, 0.028))
    ash = m.math(
        "MULTIPLY", m.up(0.4, 0.8), m.math("MULTIPLY", m.ramp(0.6, 1.0, r), m.ramp(0.35, 0.65, m.noise(3.5, 4.0, 0.6)))
    )
    col = m.mix(m.math("MULTIPLY", ash, 0.75), col, (0.3, 0.29, 0.28))
    rough = m.lerp(ash, m.lerp(tone, 0.85, 0.95), 0.98)
    # Glow: strongest at the throat's floor, fading up its wall; a trace in the plate cracks right by the mouth.
    deep = m.math("MULTIPLY", throat, m.math("SUBTRACT", 1.0, m.ramp(0.1, 0.24, z), clamp=True))
    flicker = m.ramp(0.4, 0.62, m.noise(7.0, 3.0, 0.6))  # embers in patches, not an even disc
    crack_glow = m.math("MULTIPLY", m.math("MULTIPLY", plates, near), m.cavity(0.15, 0.5, 0.95))
    glow = m.math("ADD", m.math("MULTIPLY", deep, 0.5), m.math("MULTIPLY", crack_glow, 0.2))
    glow = m.math("MULTIPLY", glow, flicker)
    height = m.math("SUBTRACT", m.math("MULTIPLY", grain, 0.3), m.math("MAXIMUM", holes, plates))
    return m.finish(col, rough, height, 0.6, 0.02, emit=glow, emit_color=EMBER)


# --- layout, preview, renders -------------------------------------------------------------------------

# Kit overview positions: (u along screen right, v toward the camera, z rotation). The iso camera looks from
# +X/-Y, so screen right is (+1, +1) and toward the camera is (+1, -1) in Blender XY.
LAYOUT = {
    "Cliff_a": (-3.4, -5.4, 45),
    "Cliff_b": (3.4, -5.4, 45),
    "Columns_a": (-5.6, -0.6, 0),
    "Boulder_a": (-2.6, -0.2, 0),
    "Boulder_b": (-0.2, -0.2, 0),
    "Stump_a": (2.4, -0.6, 0),
    "Vent_a": (5.6, -0.2, 0),
    "Scoria_a": (-1.8, 2.8, 0),
    "Stump_b": (1.0, 2.9, 30),
}
FIGURE_UV = (3.8, 2.8)


def apply_layout() -> None:
    for name, (u, v, rot) in LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.location = uv_to_xy(u, v)
        obj.rotation_euler = (0, 0, math.radians(rot))
    bpy.data.objects["PreviewFigure"].location = uv_to_xy(*FIGURE_UV)


def apply_bake_layout(gap: float = 3.0) -> None:
    """Saved .blend layout: every part unrotated in one row along X with `gap` m between them, so the AO bake
    never picks up a neighbor. The bake stage zeroes the locations before the export."""
    x = 0.0
    for name in VARIANTS:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


def setup_preview() -> None:
    C.preview_scene(crystals=False, pebbles=False)  # the pebbles would read as part of the kit
    # Ash-grey ground.
    C.tint_ground(srgb(0.17, 0.165, 0.16), srgb(0.23, 0.222, 0.214))


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in VARIANTS]


def render_kit(prefix: str, views, samples: int, size: int) -> list:
    apply_layout()
    center = uv_to_xy(0.3, -1.4) + Vector((0, 0, 0.9))
    out = []
    for view in views:
        path = OUT / f"{prefix}kit_{view}.png"
        C.render(
            path, view=view, samples=samples, size=size, target=tuple(center), zoom={"iso": 1.95, "hero": 2.5}[view]
        )
        out.append(path)
    return out


def render_variant(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The part alone at the origin, framed by its size, the scale figure beside it."""
    obj = bpy.data.objects[name]
    for o in kit_objects():
        o.hide_render = o is not obj
    loc, rot = obj.location.copy(), obj.rotation_euler.copy()
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    dx, dy, dz = obj.dimensions
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # screen right in the iso view
    fig.location = side * (max(dx, dy) / 2 + 0.55)
    w = max(dx, dy, dz * 1.1) * 1.3 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.5, dz * 0.42)))
    out = []
    for view in views:
        path = OUT / f"{prefix}{name}_{view}.png"
        zoom = w / (9.9 if view == "iso" else 6.3)
        C.render(path, view=view, samples=samples, size=size, target=tuple(target), zoom=zoom)
        out.append(path)
    obj.location, obj.rotation_euler = loc, rot
    for o in kit_objects():
        o.hide_render = False
    return out


def render_scatter(path: pathlib.Path, samples: int, size: int) -> pathlib.Path:
    """Game-distance check: instances with random scale / tilt / sink like the ScatterType draws them, seen from
    about the game camera's distance (~19 m)."""
    rnd = random.Random(5)
    for o in kit_objects():
        o.hide_render = True
    bpy.data.objects["PreviewFigure"].location = (0.6, -0.8, 0)
    dupes = []

    def put(name, x, y, scale, tilt, sink, rot=None):
        d = bpy.data.objects[name].copy()  # linked duplicate (shares the mesh)
        C.collection("Preview").objects.link(d)
        d.hide_render = False
        d.parent = None
        d.location = (x, y, -sink * scale)
        d.rotation_euler = (
            math.radians(rnd.uniform(-tilt, tilt)),
            math.radians(rnd.uniform(-tilt, tilt)),
            math.radians(rot if rot is not None else rnd.uniform(0, 360)),
        )
        d.scale = (scale,) * 3
        dupes.append(d)

    put("Cliff_a", -4.5, 5.2, 1.0, 0, 0, rot=0)
    put("Cliff_b", 1.8, 5.4, 1.0, 0, 0, rot=0)
    put("Columns_a", -6.4, -0.2, 0.9, 3, 0.1)
    put("Vent_a", 2.4, -2.6, 1.0, 0, 0, rot=0)
    put("Stump_a", 5.6, 0.6, 1.0, 5, 0.05)
    put("Stump_a", -3.2, -4.6, 0.85, 5, 0.05)
    put("Stump_b", -0.6, 1.9, 1.0, 3, 0.03)
    spots = [(-2.6, 1.0), (4.2, -3.8), (-4.6, -1.8), (6.5, -1.6), (-1.2, -5.6), (0.9, 3.4)]
    for i, (x, y) in enumerate(spots):
        put(("Boulder_a", "Boulder_b")[i % 2], x, y, rnd.uniform(0.6, 1.3), 12, 0.12)
    for _ in range(10):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.5, 8.0)
        put("Scoria_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.6, 1.3), 10, 0.04)
    C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.4)
    for d in dupes:
        bpy.data.objects.remove(d)
    for o in kit_objects():
        o.hide_render = False
    return path


# --- main -------------------------------------------------------------------------------------------


def build() -> None:
    global ROOT_OBJ, MATS
    ROOT_OBJ = C.asset_root(ASSET)
    MATS = {
        "basalt": mat_basalt(),
        "scoria": mat_scoria(),
        "char_up": mat_char("AshCharUp", "Z"),
        "char_side": mat_char("AshCharSide", "X"),
        "vent": mat_vent(),
    }
    work = bpy.data.collections.new("Work")
    bpy.context.scene.collection.children.link(work)
    for name in VARIANTS:
        BUILDERS[name]()
    # Drop the boolean operands.
    for coll in [work, *work.children_recursive]:
        for obj in list(coll.objects):
            me = obj.data
            bpy.data.objects.remove(obj)
            if me.users == 0:
                bpy.data.meshes.remove(me)
    for coll in [*work.children_recursive, work]:
        bpy.data.collections.remove(coll)


def report() -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for name in VARIANTS:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        zs = [v.co.z for v in me.vertices]
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(d, 2) for d in obj.dimensions)}"
            f" z=({min(zs):.2f}, {max(zs):.2f}) manifold={_is_manifold(obj)}"
        )
        obj.evaluated_get(dg).to_mesh_clear()
    print("STATS", C.stats())


def _is_manifold(obj: bpy.types.Object) -> bool:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = [e for e in bm.edges if not e.is_manifold]
    if bad:
        print(
            "NONMANIFOLD",
            obj.name,
            len(bad),
            [tuple(round(c, 2) for c in (e.verts[0].co + e.verts[1].co) / 2) for e in bad[:6]],
        )
    bm.free()
    return not bad


def main() -> None:
    C.reset(ASSET)
    build()
    report()
    setup_preview()
    apply_layout()
    if MODE == "final":
        sheet = []
        sheet += render_kit("final_", ("iso", "hero"), 64, 1024)
        sheet.append(render_scatter(OUT / "final_scatter_iso.png", 64, 1024))
        for name in VARIANTS:
            sheet += render_variant(name, "final_", ("iso", "hero"), 32, 640)
        for name in ("Cliff_a", "Cliff_b"):
            sheet += render_variant(name, "final_", ("back",), 32, 640)
        C.contact_sheet(sheet, OUT / "sheet.png", tile=384, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "ash_procedural.blend")
    else:
        wip = OUT / "wip"
        for view in VIEWS:
            if view in ("kit_iso", "kit_hero"):
                render_kit(f"wip/{TAG}_", (view[4:],), 24, 768)
            elif view == "scatter":
                render_scatter(wip / f"{TAG}_scatter.png", 24, 768)
            elif view == "variants":
                for name in VARIANTS:
                    render_variant(name, f"wip/{TAG}_", ("iso", "hero"), 20, 512)
            elif view == "back":
                for name in ("Cliff_a", "Cliff_b"):
                    render_variant(name, f"wip/{TAG}_", ("back",), 20, 512)
            elif view in BUILDERS:
                render_variant(view, f"wip/{TAG}_", ("iso", "hero"), 24, 640)
            elif view == "sheet":
                names = sorted(wip.glob(f"{TAG}_*.png"))
                C.contact_sheet(names, wip / f"{TAG}_sheet.png", tile=384, background=0.02)
            elif view == "save":
                apply_bake_layout()
                C.save_blend(OUT / "ash_procedural.blend")
                return


if __name__ == "__main__":
    main()
