"""Lairs kit: the two places where a quest's Ravager sleeps. The Den (its resting place in the open: rock slabs
pushed over and heaped into a rough ring, gouged by its claws, the bones and a cracked carapace of its prey, a
trampled, churned ground disc in the middle) and the Hive hollow (a hollow the hive has grown over: rock slabs
crusted with chitin plates, resin and sinew, curved chitin ribs rising out of the ground like the bones of a huge
growth, sealed brood pods with a faint glow and a glossy dark-red resin layer with tendrils reaching out at its edge).

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/lairs/source/lairs_build.py wip l1                  # kit overview
    tools/blender.sh assets/parts/lairs/source/lairs_build.py wip l1 pieces,den,hive
    tools/blender.sh assets/parts/lairs/source/lairs_build.py final

Everything it writes goes to tmp/assets/parts/lairs/: "wip <tag> [views]" renders previews into wip/<tag>_*.png
(views: kit, pieces, a piece name, den, hive (the parts' layouts from the game's angle), sheet, save); "final"
renders the kit, every piece (iso + hero), both layouts, writes the contact sheet sheet.png and saves the procedural
lairs_procedural.blend that lairs_bake.py turns into the game asset. The den ground's fine relief (footprints, claw
drags, clods) is a float map, maps/den_ground.exr, that the procedural soil material reads.

Game contract (game/locations/parts/den.tscn, hive_hollow.tscn; ModelParts reads a piece's mesh by name): every
piece is one mesh object under the root empty "Lairs", origin at its ground contact (bottom center; a rib's origin
at its root), front towards -Y (the slabs' inner face, the side that faces the lair's middle; the ribs curve towards
-Y), extra geometry below z = 0 (SINK) so nothing floats on uneven ground. Den_ground and Hive_slime are low discs
(under 10 cm) whose rims dip below the ground, without collision. Budgets (TBD (playtest)): small pieces <= ~800
triangles, medium <= ~3k, big <= ~8k. One shared atlas after the bake; the hive's glands and pods glow in the
aliens' yellow-green (emission map).

Modeling: rock is a union (boolean, manifold solver) of convex chunks shaved by plane cuts, minus chips, cracks and
claw gouges (sets of parallel grooves, their faces flagged "fresh": pale freshly broken rock). The hive's growth (its
plates, tubes and materials) comes from the nest's build (assets/aliens/nest/source/nest_build.py), so it reads as
the same species.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "lairs"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "assets" / "aliens" / "nest" / "source"))

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, geometry, noise
from mathutils.bvhtree import BVHTree

import common as C
import nest_build as NB
import nodes as N
from common import T, rx, ry, rz
from rock_geo import add_boolean, bm_to_obj, cut, hull, rand_dir, support

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "l0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit"]

ASSET = "Lairs"
Z = Vector((0, 0, 1))
SINK = {"slab": 0.5, "rib": 0.5, "pod": 0.25, "bones": 0.12}
SHARP_DEG = 32.0  # rock edges sharper than this split the shading (fracture ridges)
ROCK, ROCK_HIVE, BONE, SHELL, SOIL, CHITIN, FLESH, RESIN, SAC, SLIME, GLOW = range(11)  # material slots
SHARP_SLOTS = {ROCK, ROCK_HIVE, SHELL}
DEN = ["Den_slab_a", "Den_slab_b", "Den_slab_c", "Den_bones", "Den_ground"]
HIVE = ["Hive_slab_a", "Hive_slab_b", "Hive_rib_a", "Hive_rib_b", "Hive_pod", "Hive_slime"]
PIECES = DEN + HIVE
GLOW_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)
DEN_E = 13.2  # extent of the den ground map (m), centered on the piece's origin
DEN_HRANGE = (-0.1, 0.06)  # height range stored in the map (m)
COLLISION: dict = {}  # piece -> collision primitives in Blender space (reported in Godot axes)

# --- small math helpers -----------------------------------------------------------------------------------


def smooth(a: float, b: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def rand_rot(rnd: random.Random, tilt: float) -> Matrix:
    return rz(rnd.uniform(0, 360)) @ rx(rnd.uniform(-tilt, tilt)) @ rz(rnd.uniform(-180, 180))


def outline(rnd: random.Random, r0: float, amp: float):
    """Radius of an irregular outline by angle: r0 plus a few smooth harmonics."""
    harm = [(k, amp * rnd.uniform(0.5, 1.0) / k**0.6, rnd.uniform(0, math.tau)) for k in range(2, 10)]

    def r_of(th: float) -> float:
        return r0 + sum(a * math.sin(k * th + p) for k, a, p in harm)

    return r_of


# --- convex rock chunks and booleans (as the biome kits' rocks) ------------------------------------------


def place(bm: bmesh.types.BMesh, m: Matrix) -> bmesh.types.BMesh:
    bmesh.ops.transform(bm, matrix=m.to_4x4(), verts=bm.verts[:])
    return bm


def box_points(rnd: random.Random, size, jitter: float = 0.14, extra: int = 6, bulge: float = 0.12) -> list:
    sx, sy, sz = size
    pts = []
    for cx, cy, cz in itertools.product((-1, 1), repeat=3):
        j = Vector((rnd.uniform(-1, 1) * sx, rnd.uniform(-1, 1) * sy, rnd.uniform(-1, 1) * sz)) * jitter
        pts.append(Vector((cx * sx / 2, cy * sy / 2, cz * sz / 2)) + j)
    for _ in range(extra):
        axis = rnd.randrange(3)
        p = [rnd.uniform(-0.4, 0.4) * s for s in size]
        p[axis] = rnd.choice((-1, 1)) * size[axis] / 2 * (1 + rnd.uniform(0, bulge))
        pts.append(Vector(p))
    return pts


def chunk(rnd: random.Random, size, cuts: int = 3, m: Matrix | None = None, keep=(0.72, 0.9), **kw):
    bm = hull(box_points(rnd, size, **kw))
    for _ in range(cuts):
        cut(bm, rand_dir(rnd, min_z=-0.25), rnd.uniform(*keep))
    return place(bm, m) if m is not None else bm


def standing(rnd: random.Random, size, cuts: int, top, m: Matrix, **kw) -> bmesh.types.BMesh:
    """A slab from z = -sink up to its height (size z includes the sink), its top broken along `top`, then placed."""
    w, d, h = size
    bm = chunk(rnd, (w, d, h), cuts, T((0, 0, h / 2 - SINK["slab"])), keep=(0.8, 0.93), jitter=0.12, extra=12)
    cut(bm, top, rnd.uniform(0.88, 0.93))
    # Broken vertical edges and a stepped crest: chamfers at the corners and a few facets on the upper half.
    for sx, sy in itertools.product((-1, 1), repeat=2):
        cut(bm, (sx * rnd.uniform(0.6, 1.0), sy, rnd.uniform(-0.3, 0.4)), rnd.uniform(0.9, 0.96))
    for _ in range(3):
        a = rnd.uniform(0, math.tau)
        cut(bm, (math.cos(a), math.sin(a) * 0.6, rnd.uniform(0.6, 1.4)), rnd.uniform(0.9, 0.96))
    return place(bm, m)


def chip_cutter(rnd: random.Random, target: bmesh.types.BMesh, direction, size: float) -> bmesh.types.BMesh:
    """A rotated block centered on the target's outermost point in `direction`: bites a chip out of a ridge."""
    p = support(target, direction)
    return chunk(rnd, (size, size * rnd.uniform(0.7, 1.1), size * rnd.uniform(0.6, 1.0)), 1, T(p, rand_rot(rnd, 60)))


def crack_cutter(rnd: random.Random, center, length: float, depth: float, width: float, rot: Matrix):
    """Thin slab (length along X, depth along Y, width along Z) that notches a crack into a face."""
    pts = []
    for cx, cy, cz in itertools.product((-1, 1), repeat=3):
        w = width * (rnd.uniform(0.4, 1.0) if cy > 0 else rnd.uniform(1.0, 1.8))
        pts.append(Vector((cx * length / 2 * rnd.uniform(0.85, 1.0), cy * depth / 2, cz * w / 2)))
    return place(hull(pts), T(center, rot))


def shell(name: str, parts: list, cutters: list = ()) -> bmesh.types.BMesh:
    """Union of the convex parts minus the cutters (booleans), as a cleaned-up bmesh."""
    base = bm_to_obj(parts[0], name + "_base")
    for op, bms in (("UNION", parts[1:]), ("DIFFERENCE", cutters)):
        if bms:
            coll = bpy.data.collections.new(f"{name}_{op.lower()}")
            C.collection("Work").children.link(coll)
            for i, bm in enumerate(bms):
                bm_to_obj(bm, f"{name}_{op.lower()}{i}", coll.name)
            add_boolean(base, op, coll)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.004)
    bmesh.ops.dissolve_degenerate(bm, dist=0.003, edges=bm.edges[:])
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(2.0), verts=bm.verts[:], edges=bm.edges[:])
    return C.canonical(bm)  # the boolean's order changes between runs for an open part (the carapace)


# --- claw gouges --------------------------------------------------------------------------------------------


def ray(bvh: BVHTree, origin, direction) -> tuple:
    loc, nor, _i, _d = bvh.ray_cast(Vector(origin), Vector(direction).normalized())
    return loc, nor


def groove(a: Vector, b: Vector, nrm: Vector, w: float, d: float) -> tuple:
    """A claw groove from a to b on a surface with normal nrm: a convex cutter, narrow and shallow at both ends,
    deepest in its first half; returns (bmesh, its planes) for flagging the gouge's faces."""
    x = b - a
    length = x.length
    x.normalize()
    y = (nrm - x * nrm.dot(x)).normalized()
    zz = x.cross(y)
    pts = []
    for t in (0.0, 0.1, 0.4, 0.75, 1.0):
        taper = 0.35 + 0.65 * math.sin(math.pi * t) ** 0.4
        dep = d * (0.2 + 0.8 * math.sin(math.pi * min(1.0, t * 1.25)) ** 0.6)
        p = a + x * (length * t)
        ww = w * taper
        pts += [p + y * 0.1 + zz * ww, p + y * 0.1 - zz * ww, p - y * dep * 0.5 + zz * ww * 0.6]
        pts += [p - y * dep * 0.5 - zz * ww * 0.6, p - y * dep]
    bm = hull(pts)
    planes = [(f.normal.copy(), f.normal.dot(f.verts[0].co)) for f in bm.faces]
    return bm, planes


def claw_sets(bvh: BVHTree, rnd: random.Random, sets: list) -> tuple[list, list]:
    """Parallel grooves: each set (start near the face, direction into the rock, groove direction, claws, length)."""
    cutters, planes = [], []
    for start, into, gdir, n, length in sets:
        d, g = Vector(into).normalized(), Vector(gdir).normalized()
        across = d.cross(g).normalized()
        for i in range(n):
            off = (i - (n - 1) / 2) * 0.24 * rnd.uniform(0.9, 1.1)
            s0 = Vector(start) + across * off + g * rnd.uniform(-0.12, 0.15)
            ln = length * rnd.uniform(0.8, 1.05)
            a, na = ray(bvh, s0 - d * 3, d)
            b, nb = ray(bvh, s0 + g * ln - d * 3, d)
            if a is None or b is None:
                print("CLAW miss", start, i, tuple(s0), a, b)
                continue
            bm, pl = groove(a, b, (na + nb).normalized(), 0.06 * rnd.uniform(0.85, 1.15), 0.08 * rnd.uniform(0.8, 1.1))
            cutters.append(bm)
            planes.append(pl)
    return cutters, planes


def gouged(name: str, body: bmesh.types.BMesh, rnd: random.Random, sets: list) -> tuple:
    """The rock body minus claw gouges; returns (bmesh, indices of the gouge faces)."""
    bvh = BVHTree.FromBMesh(body)
    cutters, planes = claw_sets(bvh, rnd, sets)
    out = shell(name + "_gouged", [body], cutters)
    out.faces.index_update()
    fresh = set()
    for f in out.faces:
        c = f.calc_center_median()
        if any(all(n.dot(c) - d <= 0.012 for n, d in pl) for pl in planes):
            fresh.add(f.index)
    return out, fresh


# --- pieces --------------------------------------------------------------------------------------------------


class Piece(NB.Part):
    """One kit piece: a bmesh with the nest's point layers ("flow" for tube ribbing, "glow") and a face layer
    "fresh" (freshly broken rock, a shell's pale inside)."""

    def __init__(self, name: str):
        super().__init__(name, [])
        self.fresh = self.bm.faces.layers.float.new("fresh")
        self.edge = self.bm.verts.layers.float.new("edge")


def merge(piece: Piece, src: bmesh.types.BMesh, slot: int, fresh: set = frozenset()) -> None:
    src.faces.index_update()
    vmap = {v: piece.bm.verts.new(v.co) for v in src.verts}
    for f in src.faces:
        try:
            nf = piece.bm.faces.new([vmap[v] for v in f.verts])
        except ValueError:
            continue
        nf.material_index = slot
        nf.smooth = True
        nf[piece.fresh] = 1.0 if f.index in fresh else 0.0
    src.free()


def blob(piece: Piece, loc, r: float, scale=(1, 1, 1), rot=None, slot: int = RESIN, seg=10, rings=6, glow=0.0):
    """Smooth ellipsoid (resin, glands, flesh lumps)."""
    m = T(loc, rot, scale)
    verts = C.uv_sphere(piece.bm, u_segments=seg, v_segments=rings, radius=r, matrix=m)["verts"]
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = slot
        f.smooth = True
    for v in verts:
        v[piece.glow] = glow
    return verts


def ring_tube(piece: Piece, center, axis, radius: float, r: float, seg=16, sides=6, slot=CHITIN) -> None:
    """Closed torus around `axis` (chitin bands round a pod)."""
    z = Vector(axis).normalized()
    x = z.orthogonal().normalized()
    y = z.cross(x)
    center = Vector(center)
    rows = []
    for i in range(seg):
        a = i / seg * math.tau
        radial = x * math.cos(a) + y * math.sin(a)
        c = center + radial * radius
        rows.append(
            [
                piece.bm.verts.new(c + (radial * math.cos(b) + z * math.sin(b)) * r)
                for b in (k / sides * math.tau for k in range(sides))
            ]
        )
    faces = piece.faces([*rows, rows[0]], slot, closed_u=True)
    f = faces[0]
    f.normal_update()
    if f.normal.dot(f.calc_center_median() - (center + x * radius)) < 0:
        bmesh.ops.reverse_faces(piece.bm, faces=faces)


def tube(piece: Piece, pts: list, radii: list, refs: list, sides: int, flat: float, slot: int, kind: float = 1.0):
    return NB.tube(piece, pts, radii, refs, sides, flat, mi_fn=lambda _u: slot, kind=kind)


def finish(piece: Piece, sink: float | None = None, center_xy: bool = False) -> bpy.types.Object:
    """Flat bottom at z = -sink (holes filled), sharp rock edges split, optional bottom-center origin; returns the
    object under the kit's root with every kit material and a random per-face "facet" tone."""
    bm = piece.bm
    if sink is not None:
        cut(bm, (0, 0, -1), at=sink)
    if center_xy:
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        bmesh.ops.translate(bm, vec=(-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, 0), verts=bm.verts[:])
    bm.normal_update()
    limit = math.radians(SHARP_DEG)
    for e in bm.edges:
        lf = e.link_faces
        e.smooth = not (
            len(lf) == 2
            and lf[0].material_index in SHARP_SLOTS
            and lf[1].material_index in SHARP_SLOTS
            and e.calc_face_angle(0.0) > limit
        )
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(piece.name)
    bm.to_mesh(me)
    bm.free()
    rnd = random.Random(piece.name)
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", [rnd.random() for _ in me.polygons])
    for mat in MATS:
        me.materials.append(mat)
    obj = bpy.data.objects.new(piece.name, me)
    C.link(obj, ROOT_OBJ)
    return obj


def collide(name: str, *prims) -> None:
    COLLISION[name] = list(prims)


def box(center, size, axis: str = "Z", deg: float = 0.0) -> dict:
    return {"box": (Vector(center), Vector(size), axis, deg)}


def cyl(center, r: float, h: float) -> dict:
    return {"cyl": (Vector(center), r, h)}


# --- crust (the hive's growth over rock) ----------------------------------------------------------------------


def plate_on(piece: Piece, bvh: BVHTree, c: Vector, n: Vector, hw: float, hh: float, lift: float, thick: float):
    """Shield-shaped chitin plate following the rock under it (the nest's plate, cast onto any surface); the
    pointed lower end lifts off like a scale."""
    n = n.normalized()
    right = Z.cross(n)
    if right.length < 1e-3:
        right = Vector((1, 0, 0))
    right.normalize()
    up = n.cross(right).normalized()
    nu = nv = 5
    top, bot = [], []
    for j in range(nv):
        v = j / (nv - 1)
        w = NB.plate_width(v)
        rt, rb = [], []
        for i in range(nu):
            uu = -1 + 2 * i / (nu - 1)
            q = c + right * (uu * hw * w) + up * ((v - 0.4) * hh)
            loc, nor = ray(bvh, q + n * 1.5, -n)
            if loc is None or (loc - q).length > 1.2:
                loc, nor = q, n
            off = 0.015 + lift * (1 - v) ** 1.6 + 0.035 * (1 - uu * uu) * (0.3 + 0.7 * v)
            tk = thick * (0.35 + 0.65 * (1 - uu * uu))
            rt.append(piece.bm.verts.new(loc + nor * off))
            rb.append(piece.bm.verts.new(loc + nor * (off - tk)))
        top.append(rt)
        bot.append(rb)
    faces = piece.faces(top, CHITIN, closed_u=False) + piece.faces(bot, CHITIN, closed_u=False, flip=True)
    ring_t = top[0] + [r[-1] for r in top[1:]] + top[-1][-2::-1] + [r[0] for r in top[-2:0:-1]]
    ring_b = bot[0] + [r[-1] for r in bot[1:]] + bot[-1][-2::-1] + [r[0] for r in bot[-2:0:-1]]
    faces += piece.faces([ring_t, ring_b], CHITIN, closed_u=True)
    bmesh.ops.recalc_face_normals(piece.bm, faces=faces)


def crust_rows(piece: Piece, bvh: BVHTree, rnd: random.Random, into: Vector, xs: tuple, rows: list, front) -> None:
    """The hive's crust on a face seen along `into` (-into is out of the rock): a mat of flesh lumps pressed onto
    the rock with chitin plates of uneven sizes on it, in loose rows [(z, plate height)] along the face's horizontal
    axis within xs, up to the growth front front(u) (a height); plates thin out and shrink towards the front."""
    into = into.normalized()
    side = Z.cross(into).normalized()

    def hit(u: float, z: float):
        return ray(bvh, side * u + Vector((0, 0, z)) - into * 4, into)

    # Flesh mat: flattened lumps along the surface, denser low down.
    u = xs[0]
    while u < xs[1]:
        top = front(u)
        z = rnd.uniform(-0.05, 0.25)
        while z < top - 0.1:
            loc, nor = hit(u + rnd.uniform(-0.1, 0.1), z)
            if loc is not None:
                r = rnd.uniform(0.32, 0.45) * (1.0 - 0.35 * z / max(top, 0.5))
                rot = C.basis(nor, Z.cross(nor) if Z.cross(nor).length > 1e-3 else Vector((1, 0, 0)))
                blob(piece, loc - nor * r * 0.05, r, (1.4, 1.0, 0.22), rot, FLESH, 8, 5)
            z += rnd.uniform(0.5, 0.65)
        u += rnd.uniform(0.5, 0.62)
    # Plates.
    for z, hh in rows:
        u = xs[0] + rnd.uniform(0, 0.35)
        while u < xs[1]:
            zz = z + rnd.uniform(-0.18, 0.18)
            room = front(u) - zz
            if room > 0 and rnd.random() < 0.85:
                shrink = min(1.0, 0.45 + room / 1.2)
                loc, nor = hit(u, zz)
                if loc is not None:
                    hw = rnd.uniform(0.18, 0.4) * shrink
                    plate_on(piece, bvh, loc, nor, hw, hh * rnd.uniform(0.7, 1.15) * shrink, 0.08, 0.06)
            u += rnd.uniform(0.38, 0.62)


def wrap_path(bvh: BVHTree, x: float, yc: float, zc: float, a0: float, a1: float, n: int, rad: float):
    """Points on the rock surface in the plane x = const, swept by angle around (yc, zc) from a0 to a1 (deg; 0 = +Y,
    90 = up, 180 = -Y): a tendril over the top of a slab."""
    pts, refs = [], []
    for i in range(n):
        a = math.radians(a0 + (a1 - a0) * i / (n - 1))
        d = Vector((0, math.cos(a), math.sin(a)))
        loc, nor = ray(bvh, Vector((x, yc, zc)) + d * 6, -d)
        if loc is None:
            continue
        pts.append(loc + nor * rad * 0.35)
        refs.append(nor)
    NB.smooth_path(pts, refs, 3)
    return pts, refs


def tendril_over(piece: Piece, bvh: BVHTree, x: float, yc: float, zc: float, a0, a1, r: float) -> None:
    pts, refs = wrap_path(bvh, x, yc, zc, a0, a1, 24, r)
    if len(pts) < 4:
        return
    n = len(pts)
    radii = [r * (0.8 + 0.2 * math.sin(i * 0.9)) * min(1.0, (n - 1 - i) / 6) for i in range(n)]
    radii[-1] = 0.0
    tube(piece, pts, radii, refs, 6, 0.55, FLESH)


def glands_on(piece: Piece, bvh: BVHTree, rnd: random.Random, into: Vector, spots: list) -> None:
    """Small glowing pustules half sunk in the rock between the plates."""
    into = into.normalized()
    side = Z.cross(into).normalized()
    for u, z, r in spots:
        loc, nor = ray(bvh, side * u + Vector((0, 0, z)) - into * 4, into)
        if loc is not None:
            blob(piece, loc + nor * r * 0.25, r, (1, 1, 0.85), slot=GLOW, seg=8, rings=5, glow=1.0)


def resin_foot(piece: Piece, bvh: BVHTree, rnd: random.Random, into: Vector, us: list) -> None:
    """Glossy resin heaped along the foot of a face."""
    into = into.normalized()
    side = Z.cross(into).normalized()
    for u, r in us:
        loc, nor = ray(bvh, side * u + Vector((0, 0, 0.15)) - into * 4, into)
        if loc is not None:
            blob(piece, loc + nor * r * 0.2 - Z * r * 0.15, r, (1.5, 1.0, 0.55), rz(rnd.uniform(0, 180)), RESIN)


def resin_drips(piece: Piece, bvh: BVHTree, rnd: random.Random, into: Vector, spots: list) -> None:
    """Resin run down a face from the crest: thin streaks on the surface ending in a drop."""
    into = into.normalized()
    side = Z.cross(into).normalized()
    for u, z, ln in spots:
        pts, refs = [], []
        for i in range(10):
            zz = z - ln * i / 9
            loc, nor = ray(bvh, side * (u + 0.04 * math.sin(i)) + Vector((0, 0, zz)) - into * 4, into)
            if loc is not None:
                pts.append(loc + nor * 0.015)
                refs.append(nor)
        if len(pts) < 4:
            continue
        n = len(pts)
        radii = [0.035 + 0.03 * math.sin(math.pi * i / (n - 1)) ** 2 for i in range(n)]
        radii[0] = 0.0
        radii[-2] = 0.075
        radii[-1] = 0.0
        tube(piece, pts, radii, refs, 6, 0.45, RESIN, kind=0.0)


# --- den ----------------------------------------------------------------------------------------------------


def den_slab_a() -> bpy.types.Object:
    """Tall slab pushed over towards the middle (13 degrees), its top broken off slanting, a broken block at its
    foot and a buttress heaped behind it; two sets of claw gouges down its inner face."""
    rnd = random.Random(1101)
    s = SINK["slab"]
    main = standing(rnd, (3.3, 1.25, 4.5 + s), 5, (0.45, -0.15, 1.0), rx(13) @ rz(4))
    foot = chunk(rnd, (1.5, 1.0, 0.95), 4, T((0.95, -1.25, 0.05), rz(24) @ ry(-12)))
    back = chunk(rnd, (1.7, 1.0, 1.5), 4, T((-0.6, 1.0, 0.15), rz(-12) @ rx(15)))
    cutters = [
        chip_cutter(rnd, main, (0.7, -0.5, 0.8), 0.45),
        chip_cutter(rnd, main, (-0.8, 0.3, 0.7), 0.42),
        chip_cutter(rnd, main, (0.2, -0.6, 1.0), 0.5),
    ]
    body = shell("Den_slab_a", [main, foot, back], cutters)
    rock, fresh = gouged(
        "Den_slab_a",
        body,
        rnd,
        [((-0.75, -3, 3.3), (0, 1, 0), (0.42, 0, -1), 4, 1.7), ((0.75, -3, 2.0), (0, 1, 0), (-0.25, 0, -1), 3, 1.2)],
    )
    piece = Piece("Den_slab_a")
    merge(piece, rock, ROCK, fresh)
    lean = rx(13) @ rz(4)
    collide(
        "Den_slab_a",
        box(lean @ Vector((0, 0, 2.1)), (2.9, 1.0, 4.2), "X", 13),
        box((0.95, -1.2, 0.3), (1.2, 0.8, 0.6)),
    )
    return finish(piece, s)


def den_slab_b() -> bpy.types.Object:
    """Two slabs fallen against each other: a wide one leaning to the right and a narrower one in front of it,
    leaning back onto it, rubble at their feet; claw gouges on both."""
    rnd = random.Random(1202)
    s = SINK["slab"]
    left = standing(rnd, (2.9, 1.15, 3.7 + s), 5, (0.2, 0.0, 1.0), T((-0.85, 0.2, 0), ry(16) @ rz(-6) @ rx(6)))
    right = standing(rnd, (2.3, 1.0, 3.0 + s), 5, (-0.5, -0.1, 1.0), T((1.15, -0.55, 0), ry(-20) @ rz(14) @ rx(10)))
    rubble = chunk(rnd, (1.0, 0.8, 0.6), 4, T((-0.4, -1.15, 0.0), rz(35) @ ry(10)))
    cutters = [
        chip_cutter(rnd, left, (-0.7, -0.4, 0.8), 0.4),
        chip_cutter(rnd, right, (0.6, -0.6, 0.7), 0.35),
        chip_cutter(rnd, left, (0.3, -0.5, 1.0), 0.45),
    ]
    body = shell("Den_slab_b", [left, right, rubble], cutters)
    rock, fresh = gouged(
        "Den_slab_b",
        body,
        rnd,
        [((-1.05, -3, 2.8), (0, 1, 0), (0.45, 0, -1), 4, 1.5), ((1.3, -3, 2.2), (0, 1, 0), (-0.35, 0, -1), 3, 1.1)],
    )
    piece = Piece("Den_slab_b")
    merge(piece, rock, ROCK, fresh)
    collide(
        "Den_slab_b",
        box((-0.55, 0.2, 1.75), (2.6, 1.0, 3.5), "Y", 16),
        box((0.9, -0.55, 1.4), (2.0, 0.85, 2.8), "Y", -20),
    )
    return finish(piece, s)


def den_slab_c() -> bpy.types.Object:
    """A slab toppled flat and broken in two, the halves tilted apart; claw gouges across their tops (they read
    best from above)."""
    rnd = random.Random(1303)
    s = SINK["slab"]
    a = chunk(rnd, (2.3, 2.2, 1.25 + s), 5, T((-1.0, 0.0, (1.25 + s) / 2 - s), ry(4)), keep=(0.8, 0.93), jitter=0.1)
    cut(a, (0.15, -0.1, 1.0), 0.93)
    b = chunk(
        rnd, (1.7, 2.0, 1.0 + s), 5, T((1.12, -0.15, (1.0 + s) / 2 - s - 0.05), ry(-9) @ rz(10)), keep=(0.8, 0.93)
    )
    cut(b, (-0.2, 0.15, 1.0), 0.92)
    cutters = [
        chip_cutter(rnd, a, (-0.6, -0.6, 0.6), 0.4),
        chip_cutter(rnd, b, (0.7, 0.5, 0.6), 0.35),
    ]
    body = shell("Den_slab_c", [a, b], cutters)
    rock, fresh = gouged(
        "Den_slab_c",
        body,
        rnd,
        [((-1.75, 0.55, 3.0), (0, 0, -1), (1, -0.4, 0), 4, 1.7), ((0.95, 0.3, 3.0), (0, 0, -1), (0.3, -1, 0), 3, 0.9)],
    )
    piece = Piece("Den_slab_c")
    merge(piece, rock, ROCK, fresh)
    collide("Den_slab_c", box((-1.0, 0.0, 0.55), (2.1, 2.0, 1.1)), box((1.12, -0.15, 0.45), (1.5, 1.8, 0.9), "Z", 10))
    return finish(piece, s)


def femur(piece: Piece, p0, p1, r: float, knobs=(True, True), bend: float = 0.08) -> None:
    """Long bone lying on the ground: a shaft between two knobbed ends (a broken end is a splintered point)."""
    p0, p1 = Vector(p0), Vector(p1)
    mid = (p0 + p1) / 2 + (p1 - p0).cross(Z).normalized() * bend
    pts = NB.catmull([p0, mid, p1], 26)
    radii = []
    for i in range(26):
        t = i / 25
        k0 = 1.0 if knobs[0] else 0.0
        k1 = 1.0 if knobs[1] else 0.0
        bump = k0 * math.exp(-(((t - 0.06) / 0.06) ** 2)) + k1 * math.exp(-(((t - 0.94) / 0.06) ** 2))
        radii.append(r * (1.0 + 0.9 * bump))
    radii[0] = 0.0 if knobs[0] else r * 0.3
    radii[-1] = 0.0
    radii[1] *= 0.75 if knobs[0] else 1.0
    radii[-2] *= 0.75
    tube(piece, pts, radii, [Z] * 26, 9, 0.9, BONE, kind=0.0)


def den_bones() -> bpy.types.Object:
    """What's left of the Ravager's prey: a big cracked carapace lying askew, two long bones (one snapped), the
    arcs of a half-buried ribcage and a few splinters; low, about 3 x 2 m."""
    rnd = random.Random(1404)
    piece = Piece("Den_bones")
    # Carapace: a segmented dome shell, solidified, broken open at one end and cracked.
    bm = bmesh.new()
    C.uv_sphere(bm, u_segments=22, v_segments=12, radius=1.0)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.25], context="VERTS")
    for v in bm.verts:
        band = ((v.co.x + 1.0) / 0.26) % 1.0
        v.co *= 1.0 + 0.06 * band
        v.co = Vector((v.co.x * 0.88, v.co.y * 0.68, v.co.z * 0.46))
    bm.normal_update()
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.05)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    place(bm, T((0.45, 0.1, 0.02), rz(-20) @ ry(-12) @ rx(6)))
    cutters = [
        chunk(rnd, (0.9, 1.2, 0.9), 2, T((1.25, -0.35, 0.3), rz(30) @ ry(20))),
        crack_cutter(rnd, (0.2, 0.0, 0.45), 1.4, 0.8, 0.035, rz(75) @ rx(80)),
        crack_cutter(rnd, (0.6, 0.4, 0.4), 0.9, 0.8, 0.03, rz(-20) @ rx(70)),
    ]
    shell_planes = [[(f.normal.copy(), f.normal.dot(f.verts[0].co)) for f in c.faces] for c in cutters]
    carapace = shell("Den_bones_shell", [bm], cutters)
    center = Vector((0.45, 0.1, -0.1))
    fresh = set()
    carapace.faces.index_update()
    for f in carapace.faces:
        c = f.calc_center_median()
        inner = f.normal.dot(c - center) < 0
        broken = any(all(n.dot(c) - d <= 0.012 for n, d in pl) for pl in shell_planes)
        if inner or broken:
            fresh.add(f.index)
    merge(piece, carapace, SHELL, fresh)
    # Long bones.
    femur(piece, (-1.45, -0.55, 0.06), (0.25, -0.85, 0.08), 0.07)
    femur(piece, (-0.2, 0.75, 0.05), (0.9, 0.95, 0.06), 0.06, knobs=(True, False))
    # What's left of a ribcage: three uneven arcs rising out of the ground, the last one snapped.
    for x, h, span, lean, broken in (
        (-1.3, 0.42, 1.05, 0.06, False),
        (-0.95, 0.55, 1.3, -0.04, False),
        (-0.52, 0.47, 1.1, 0.1, True),
    ):
        y0 = rnd.uniform(-0.05, 0.12)
        ctrl = [
            Vector((x - 0.05, y0, -0.1)),
            Vector((x + lean * 0.5, y0 + span * 0.22, h * 0.8)),
            Vector((x + lean, y0 + span * 0.55, h)),
            Vector((x + lean * 1.4, y0 + span, -0.1)),
        ]
        pts = NB.catmull(ctrl, 16)
        if broken:
            pts = pts[:11]
        radii = [0.05 * (1.0 - 0.35 * j / 15) for j in range(len(pts))]
        if broken:
            radii[-1] = 0.0
        tube(piece, pts, radii, [Vector((1, 0, 0))] * len(pts), 7, 0.6, BONE, kind=0.0)
    # Splinters and shell shards.
    for k in range(6):
        a = rnd.uniform(0, math.tau)
        p = Vector((0.2 + math.cos(a) * rnd.uniform(1.0, 1.4), math.sin(a) * rnd.uniform(0.6, 0.95), 0.0))
        sz = rnd.uniform(0.14, 0.26)
        chip = chunk(rnd, (sz, sz * 0.6, sz * 0.35), 2, T(p, rand_rot(rnd, 25)))
        merge(piece, chip, BONE if k % 2 else SHELL)
    collide("Den_bones", box((0.45, 0.1, 0.22), (1.5, 1.1, 0.44), "Z", -20))
    return finish(piece, SINK["bones"])


def fbm_map(n: int, rnd: random.Random, cells: int, octaves: int = 4) -> np.ndarray:
    """Smooth value noise on an n x n grid (standardized: mean 0, std 1)."""
    out = np.zeros((n, n), dtype=np.float64)
    amp = 1.0
    for o in range(octaves):
        c = cells * 2**o
        g = np.array([[rnd.random() for _ in range(c + 2)] for _ in range(c + 2)])
        x = (np.arange(n) + 0.5) / n * c
        i = np.floor(x).astype(int)
        f = x - i
        f = f * f * (3 - 2 * f)
        rows, cols = i[:, None], i[None, :]
        fy, fx = f[:, None], f[None, :]
        v = (
            g[rows, cols] * (1 - fx) * (1 - fy)
            + g[rows, cols + 1] * fx * (1 - fy)
            + g[rows + 1, cols] * (1 - fx) * fy
            + g[rows + 1, cols + 1] * fx * fy
        )
        out += v * amp
        amp *= 0.5
    return (out - out.mean()) / out.std()


def _sstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def den_maps(r_of) -> pathlib.Path:
    """The den ground's fine relief as a float map over DEN_E x DEN_E m (rows from -y up, columns from -x): R height
    (DEN_HRANGE mapped to 0..1), G churned (fresh soil thrown up), B dark stains, A packed (pressed by the feet).
    The beast lay in the middle (a shallow body print), circled it (two loops of pillar footprints with blunt nail
    dents) and dragged its claws (sets of parallel furrows with spoil heaped beside them); clods everywhere and a
    churned band along the rim."""
    n = 1024
    rnd = random.Random(1505)
    xs = (np.arange(n) + 0.5) / n * DEN_E - DEN_E / 2
    X, Y = np.meshgrid(xs, xs)
    Rr = np.hypot(X, Y)
    TH = np.arctan2(Y, X)
    edge_r = np.vectorize(r_of)(TH)
    H = np.zeros((n, n))
    fresh = np.zeros((n, n))
    packed = np.zeros((n, n))
    rough = fbm_map(n, rnd, 6)
    H += 0.006 * fbm_map(n, rnd, 20, 3)
    # Body print: a shallow, smoothed hollow where it lay.
    ca, sa = math.cos(math.radians(25)), math.sin(math.radians(25))
    u, v = X * ca + Y * sa, -X * sa + Y * ca
    e = np.hypot(u / 2.8, (v - 0.15) / 1.45)
    H -= 0.028 * (1 - _sstep(0.55, 1.1, e))
    packed += 0.6 * (1 - _sstep(0.7, 1.05, e))
    # Footprints along two loops around it: broad, uneven pads pressed in (smeared where the foot slid), the soil
    # pushed up in a ragged ring; one blunt nail dent in front of some. Irregular so they don't read as a pattern.
    wobble = fbm_map(n, rnd, 14, 3)
    for loop, (ra, rb, count, a0) in enumerate(((3.9, 3.1, 9, 0.3), (4.6, 3.8, 7, 1.9))):
        for k in range(count):
            a = a0 + k / count * math.tau * 0.85 + rnd.uniform(-0.2, 0.2)
            side = rnd.uniform(-0.6, 0.6)
            cx, cy = math.cos(a) * (ra + side), math.sin(a) * (rb + side)
            heading = a + math.pi / 2 * (1 if loop == 0 else -1) + rnd.uniform(-0.6, 0.6)
            ch, sh = math.cos(heading), math.sin(heading)
            pu, pv = (X - cx) * ch + (Y - cy) * sh, -(X - cx) * sh + (Y - cy) * ch
            smear = rnd.uniform(1.0, 1.7)
            size = rnd.uniform(0.3, 0.4)
            d = np.hypot(pu / smear, pv) / size + 0.18 * wobble
            depth = rnd.uniform(0.02, 0.04)
            H += -depth * (1 - _sstep(0.6, 1.1, d)) + depth * 0.4 * np.exp(-(((d - 1.25) / 0.25) ** 2))
            packed += 0.7 * (1 - _sstep(0.7, 1.1, d))
            fresh += 0.4 * np.exp(-(((d - 1.3) / 0.3) ** 2))
            if rnd.random() < 0.5:
                dn = np.hypot((pu - size * smear * 1.1) / 0.13, pv / 0.09)
                H -= 0.02 * (1 - _sstep(0.5, 1.0, dn))
    # Claw drags: fanned furrows of different lengths, slightly bent, spoil beside them and clods where they end.
    for _ in range(6):
        a = rnd.uniform(0, math.tau)
        r0 = rnd.uniform(1.2, 4.2)
        p0 = np.array((math.cos(a) * r0, math.sin(a) * r0))
        ang0 = a + rnd.uniform(-1.4, 1.4)
        length = rnd.uniform(1.4, 2.8)
        claws = rnd.choice((2, 3, 3, 4))
        for c in range(claws):
            ang = ang0 + (c - (claws - 1) / 2) * rnd.uniform(0.04, 0.1)
            g = np.array((math.cos(ang), math.sin(ang)))
            across = np.array((-g[1], g[0]))
            a_pt = p0 + across * (c - (claws - 1) / 2) * rnd.uniform(0.2, 0.3) + g * rnd.uniform(-0.3, 0.3)
            ln = length * rnd.uniform(0.55, 1.05)
            bend = rnd.uniform(-0.15, 0.15)
            px, py = X - a_pt[0], Y - a_pt[1]
            t = np.clip((px * g[0] + py * g[1]) / ln, 0, 1)
            off = bend * np.sin(np.pi * t)
            dist = np.hypot(px - g[0] * t * ln - across[0] * off, py - g[1] * t * ln - across[1] * off)
            w = rnd.uniform(0.05, 0.08) * (0.4 + 0.6 * np.sin(np.pi * t) ** 0.4)
            dep = rnd.uniform(0.03, 0.05)
            H += -dep * np.clip(1 - (dist / w) ** 2, 0, 1) * (0.3 + 0.7 * np.sin(np.pi * np.minimum(1, t * 1.2)))
            H += 0.012 * np.exp(-(((dist - 1.7 * w) / (0.7 * w)) ** 2))
            fresh += 0.6 * np.clip(1 - dist / (2.4 * w), 0, 1)
            end = a_pt + g * ln
            de = np.hypot(X - end[0], Y - end[1])
            H += 0.025 * np.exp(-((de / 0.16) ** 2))
            fresh += 0.6 * np.exp(-((de / 0.22) ** 2))
    # Clods: small lumps thrown up, most in the churned band along the rim and around the furrows.
    d_rim = edge_r - Rr
    band = np.exp(-(((d_rim - 0.5) / 0.45) ** 2)) * (0.6 + 0.4 * _sstep(-0.5, 1.0, rough))
    H += 0.03 * band * _sstep(-0.2, 1.4, fbm_map(n, rnd, 26, 2))
    fresh += band
    px_per_m = n / DEN_E
    for _ in range(420):
        a = rnd.uniform(0, math.tau)
        r = min(rnd.uniform(0.5, 1.0) ** 0.5 * 6.0, r_of(a) - 0.05)
        cx, cy = math.cos(a) * r, math.sin(a) * r
        rad = rnd.uniform(0.03, 0.09)
        hgt = rnd.uniform(0.012, 0.03)
        i0 = int((cy + DEN_E / 2) * px_per_m)
        j0 = int((cx + DEN_E / 2) * px_per_m)
        k = int(rad * px_per_m * 2.5) + 1
        sl = (slice(max(0, i0 - k), min(n, i0 + k)), slice(max(0, j0 - k), min(n, j0 + k)))
        dd = np.hypot(X[sl] - cx, Y[sl] - cy) / rad
        H[sl] += hgt * np.exp(-(dd**2) * 1.6)
        fresh[sl] += 0.8 * np.exp(-(dd**2))
    # Dark stains (old, dried), a few patches near the middle.
    stain = _sstep(0.9, 1.5, fbm_map(n, rnd, 5, 3)) * (1 - _sstep(3.0, 4.5, Rr))
    lo, hi = DEN_HRANGE
    rgba = np.ones((n, n, 4), dtype=np.float32)
    rgba[..., 0] = np.clip((H - lo) / (hi - lo), 0, 1)
    rgba[..., 1] = np.clip(fresh, 0, 1)
    rgba[..., 2] = np.clip(stain, 0, 1)
    rgba[..., 3] = np.clip(packed, 0, 1)
    path = OUT / "maps" / "den_ground.exr"
    path.parent.mkdir(parents=True, exist_ok=True)
    img = bpy.data.images.new("den_ground_map", n, n, alpha=True, float_buffer=True)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = str(path)
    img.file_format = "OPEN_EXR"
    img.save()
    bpy.data.images.remove(img)
    print("MAP", path, "height", round(float(H.min()), 3), round(float(H.max()), 3))
    return path


def disc(piece: Piece, r_of, zfun, slot: int, grid: float, step: float, skirt: float, rings=(), dist=None) -> None:
    """A low ground disc inside the outline r_of(angle): constrained Delaunay triangulation of the skirt's outer
    edge (r + skirt), vertex rings at r - d (d in rings) and a jittered grid inside; z = zfun(x, y). With `dist`
    (a function (x, y) -> distance inside the visible outline) the vertices get the "edge" layer (1 at the rim)."""
    rnd = random.Random(piece.name)
    m = int(math.tau * 6.0 / step)
    angles = [i / m * math.tau for i in range(m)]
    outer = [Vector((math.cos(a) * (r_of(a) + skirt), math.sin(a) * (r_of(a) + skirt))) for a in angles]
    pts = list(outer)
    for d in (0.0, *rings):
        pts += [
            Vector((math.cos(a) * (r_of(a) - d), math.sin(a) * (r_of(a) - d))) for a in angles[:: 1 if d < 0.2 else 2]
        ]
    inner_limit = max(rings, default=0.0) + 0.12
    k = int(7.5 / grid)
    for i, j in itertools.product(range(-k, k + 1), repeat=2):
        p = Vector((i * grid + rnd.uniform(-0.3, 0.3) * grid, j * grid + rnd.uniform(-0.3, 0.3) * grid))
        if p.length < r_of(math.atan2(p.y, p.x)) - inner_limit:
            pts.append(p)
    res = geometry.delaunay_2d_cdt(pts, [], [list(range(m))], 1, 1e-5)
    verts = []
    for p in res[0]:
        v = piece.bm.verts.new((p.x, p.y, zfun(p.x, p.y)))
        if dist is not None:
            v[piece.edge] = 1.0 - smooth(0.0, 0.7, dist(p.x, p.y))
        verts.append(v)
    faces = []
    for f in res[2]:
        try:
            nf = piece.bm.faces.new([verts[i] for i in f])
        except ValueError:
            continue
        nf.material_index = slot
        nf.smooth = True
        faces.append(nf)
    for f in faces:
        f.normal_update()
    if sum(f.normal.z for f in faces) < 0:
        bmesh.ops.reverse_faces(piece.bm, faces=faces)


def den_ground() -> bpy.types.Object:
    """The trampled middle: a churned ground disc about 11.5 m across, 2 cm above the ground, its ragged rim
    dipping below it; the relief (footprints, claw furrows, clods, the body print) is in the soil material's map."""
    rnd = random.Random(1505)
    r_of = outline(rnd, 5.6, 0.28)
    global DEN_MAP
    DEN_MAP = den_maps(r_of)

    def zfun(x: float, y: float) -> float:
        d = r_of(math.atan2(y, x)) - math.hypot(x, y)
        wob = 0.008 * noise.noise(Vector((x * 0.9, y * 0.9, 3.0)))
        if d >= 0:
            return 0.02 + wob * 0.5 - 0.045 * (1 - smooth(0.0, 0.5, d)) + wob * (1 - smooth(0.0, 0.5, d)) * 2
        return -0.025 + d * 0.2

    piece = Piece("Den_ground")
    disc(piece, r_of, zfun, SOIL, grid=0.3, step=0.13, skirt=0.22, rings=(0.2, 0.45))
    return finish(piece)


# --- hive ---------------------------------------------------------------------------------------------------


def hive_slab_a() -> bpy.types.Object:
    """Tall slab overgrown by the hive: rows of chitin plates creeping up its inner face and round its sides,
    resin heaped at its foot and running down from its crest, sinew tendrils over its top, a few glowing glands
    between the plates."""
    rnd = random.Random(2101)
    s = SINK["slab"]
    main = standing(rnd, (3.5, 1.35, 4.3 + s), 5, (-0.4, -0.1, 1.0), rx(10) @ rz(-5))
    back = chunk(rnd, (1.8, 1.0, 1.4), 4, T((0.7, 1.0, 0.1), rz(15) @ rx(14)))
    cutters = [
        chip_cutter(rnd, main, (0.8, -0.3, 0.8), 0.45),
        chip_cutter(rnd, main, (-0.6, -0.4, 1.0), 0.45),
    ]
    body = shell("Hive_slab_a", [main, back], cutters)
    bvh = BVHTree.FromBMesh(body)
    piece = Piece("Hive_slab_a")
    merge(piece, body, ROCK_HIVE)
    front = Vector((0, 1, 0))  # looking at the inner face (-Y side) means rays along +Y

    def growth(u: float) -> float:
        return 2.0 + 0.7 * math.sin(u * 1.7 + 0.4)

    crust_rows(piece, bvh, rnd, front, (-1.6, 1.6), [(0.3, 0.75), (0.85, 0.7), (1.4, 0.65), (1.95, 0.6)], growth)
    for into in (Vector((1, 0, 0)), Vector((-1, 0, 0))):
        crust_rows(piece, bvh, rnd, into, (-0.7, 0.7), [(0.3, 0.7), (0.85, 0.65)], lambda _u: 1.3)
    resin_foot(piece, bvh, rnd, front, [(-1.4, 0.32), (-0.7, 0.38), (0.1, 0.3), (0.8, 0.4), (1.5, 0.3)])
    resin_drips(piece, bvh, rnd, front, [(-0.9, 3.7, 0.9), (0.4, 3.5, 1.1), (1.2, 3.2, 0.7)])
    for x in (-0.85, 0.75):
        tendril_over(piece, bvh, x, 0.0, 1.6, -25, 196, 0.075 + 0.015 * rnd.random())
    glands_on(piece, bvh, rnd, front, [(-1.0, 0.65, 0.08), (0.3, 1.15, 0.09), (0.95, 0.5, 0.07)])
    collide("Hive_slab_a", box(rx(10) @ rz(-5) @ Vector((0, -0.05, 2.0)), (3.1, 1.3, 4.0), "X", 10))
    return finish(piece, s)


def hive_slab_b() -> bpy.types.Object:
    """Lower, broad slab with a smaller block fallen against its front, the hive's crust over most of both, a big
    heap of resin at its foot, tendrils and glands."""
    rnd = random.Random(2202)
    s = SINK["slab"]
    main = standing(rnd, (3.9, 1.5, 3.0 + s), 5, (0.3, 0.1, 1.0), rx(-5) @ rz(6))
    block = chunk(rnd, (1.6, 1.1, 1.5), 4, T((-1.0, -1.0, 0.3), rz(-20) @ rx(-14)))
    cutters = [chip_cutter(rnd, main, (-0.8, -0.4, 0.8), 0.4), chip_cutter(rnd, main, (0.7, 0.4, 0.9), 0.4)]
    body = shell("Hive_slab_b", [main, block], cutters)
    bvh = BVHTree.FromBMesh(body)
    piece = Piece("Hive_slab_b")
    merge(piece, body, ROCK_HIVE)
    front = Vector((0, 1, 0))

    def growth(u: float) -> float:
        return 2.2 + 0.5 * math.sin(u * 2.1 - 0.5)

    crust_rows(piece, bvh, rnd, front, (-1.9, 1.9), [(0.3, 0.75), (0.85, 0.7), (1.4, 0.65), (1.95, 0.6)], growth)
    for into in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, -1, 0))):
        crust_rows(piece, bvh, rnd, into, (-0.9, 0.9), [(0.3, 0.7)], lambda _u: 1.0)
    resin_foot(piece, bvh, rnd, front, [(0.3, 0.45), (0.9, 0.5), (1.5, 0.38), (1.1, 0.3), (-0.2, 0.3)])
    resin_drips(piece, bvh, rnd, front, [(-0.3, 2.7, 0.8), (1.3, 2.6, 0.7)])
    for x in (-1.2, 0.35, 1.45):
        tendril_over(piece, bvh, x, 0.0, 1.0, -25, 200, 0.075 + 0.015 * rnd.random())
    glands_on(piece, bvh, rnd, front, [(-1.3, 1.05, 0.08), (0.2, 0.6, 0.09), (1.1, 1.3, 0.07)])
    collide(
        "Hive_slab_b",
        box(rx(-5) @ rz(6) @ Vector((0, 0, 1.35)), (3.6, 1.35, 2.7), "Z", 6),
        box((-1.0, -1.0, 0.55), (1.3, 0.9, 1.1), "Z", -20),
    )
    return finish(piece, s)


def rib(piece: Piece, ctrl: list, r0: float, n: int, band: float, sides: int = 10, phase: float = 0.0) -> None:
    """A curved chitin rib from below the ground to a pale point: armored bands (each widening towards its upper
    rim, the next stepping in), flattened sideways."""
    pts = NB.catmull([Vector(c) for c in ctrl], n)
    s, acc = [0.0], 0.0
    for a, b in itertools.pairwise(pts):
        acc += (b - a).length
        s.append(acc)
    radii = []
    for si in s:
        u = si / acc
        frac = ((si + phase) / band) % 1.0
        radii.append(r0 * (1 - u) ** 0.7 * (0.8 + 0.26 * frac**2))
    radii[-1] = 0.0
    tube(piece, pts, radii, [Vector((1, 0, 0))] * n, sides, 0.62, CHITIN)


def rib_root(piece: Piece, rnd: random.Random, r: float, roots: int, glands: int) -> None:
    """Where a rib grows out of the ground: sinew roots spreading over the ground, resin and a few glands."""
    for k in range(roots):
        a = k / roots * math.tau + rnd.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        length = rnd.uniform(0.9, 1.7)
        pts, refs, radii = [], [], []
        for i in range(12):
            t = i / 11
            w = math.sin(t * 5 + k) * 0.12 * t
            p = d * (r * 0.5 + t * length) + side * w
            p.z = 0.35 * (1 - t) ** 2 + 0.02
            pts.append(p)
            refs.append(Z)
            radii.append(0.12 * (1 - t) ** 0.8 + 0.01)
        radii[-1] = 0.0
        tube(piece, pts, radii, refs, 6, 0.6, FLESH)
    for _k in range(4):
        a = rnd.uniform(0, math.tau)
        p = Vector((math.cos(a), math.sin(a), 0)) * r * 0.8
        blob(piece, p, rnd.uniform(0.18, 0.26), (1.3, 1.0, 0.5), rz(math.degrees(a)), RESIN)
    for _k in range(glands):
        a = rnd.uniform(0, math.tau)
        p = Vector((math.cos(a), math.sin(a), 0)) * r * 1.15 + Vector((0, 0, 0.05))
        blob(piece, p, rnd.uniform(0.06, 0.09), slot=GLOW, seg=8, rings=5, glow=1.0)


def hive_rib_a() -> bpy.types.Object:
    """A huge chitin rib rising out of the ground and curving over towards the middle (about 4 m up, its pale
    point 3.3 m in), sinew roots and resin at its foot."""
    rnd = random.Random(2303)
    piece = Piece("Hive_rib_a")
    ctrl = [(0, 0.25, -0.6), (0, 0.12, 0.6), (0, -0.15, 1.7), (0, -0.75, 2.8), (0, -1.6, 3.6), (0, -2.5, 3.95)]
    rib(piece, [*ctrl, (0.05, -3.3, 3.7)], 0.46, 70, 0.42)
    rib_root(piece, rnd, 0.46, 5, 1)
    collide("Hive_rib_a", cyl((0, 0.1, 1.0), 0.36, 2.0), cyl((0, -0.4, 2.3), 0.3, 1.0))
    return finish(piece, SINK["rib"])


def hive_rib_b() -> bpy.types.Object:
    """A forked rib: a main tine curving over towards the middle (3.2 m up) and a thinner one splitting off to the
    side, from a swollen root of flesh."""
    rnd = random.Random(2404)
    piece = Piece("Hive_rib_b")
    main = [(0, 0.2, -0.6), (0, 0.08, 0.6), (0, -0.25, 1.6), (0, -0.85, 2.5), (0, -1.6, 3.05), (0.05, -2.35, 3.1)]
    rib(piece, main, 0.4, 60, 0.38)
    fork = [(0.05, 0.05, 0.4), (0.25, 0.0, 1.1), (0.7, -0.25, 1.85), (1.1, -0.75, 2.3), (1.35, -1.4, 2.4)]
    rib(piece, fork, 0.22, 40, 0.3, sides=8, phase=0.15)
    blob(piece, (0.1, 0.05, 0.1), 0.55, (1.0, 0.85, 0.6), rz(20), FLESH, 14, 8)
    rib_root(piece, rnd, 0.5, 4, 1)
    collide("Hive_rib_b", cyl((0.05, 0.05, 0.9), 0.4, 1.8), cyl((0.0, -0.4, 2.1), 0.27, 1.0))
    return finish(piece, SINK["rib"])


def hive_pod() -> bpy.types.Object:
    """A cluster of five sealed brood pods fused on a base of flesh, chitin bands round two of them, sinew strands
    over them; the membranes glow faintly from inside, a few glands at the base."""
    rnd = random.Random(2505)
    piece = Piece("Hive_pod")
    blob(piece, (0, 0, -0.05), 0.8, (1.0, 0.9, 0.38), None, FLESH, 18, 9)
    sacs = [(0.0, 0.0, 1.1, 0.34, 0), (60, 0.42, 0.85, 0.3, 14), (150, 0.45, 0.75, 0.28, 16)]
    sacs += [(230, 0.4, 0.95, 0.3, 12), (310, 0.46, 0.65, 0.25, 18)]
    for k, (ang, dist, h, r, tilt) in enumerate(sacs):
        a = math.radians(ang)
        base = Vector((math.cos(a) * dist, math.sin(a) * dist, 0.12))
        rot = rz(ang) @ ry(tilt)
        center = base + rot @ Vector((0, 0, h * 0.5))
        verts = blob(piece, (0, 0, 0), 1.0, (1, 1, 1), None, SAC, 16, 10)
        for v in verts:
            zn = v.co.z
            taper = 1.0 - 0.22 * max(0.0, zn)
            local = Vector((v.co.x * r * taper, v.co.y * r * taper, zn * h * 0.5))
            local += Vector((0.02 * math.sin(zn * 7 + k), 0, 0))
            v.co = center + rot @ local
            v[piece.glow] = smooth(-0.7, 0.1, zn) * (1.0 - 0.35 * smooth(0.5, 1.0, zn))
        if k in (0, 3):
            for zb in (0.15, -0.2):
                ring_tube(piece, center + rot @ Vector((0, 0, zb * h)), rot @ Z, r * (1.02 - 0.1 * zb), 0.045)
    for k in range(3):
        a = math.radians(30 + k * 120)
        d = Vector((math.cos(a), math.sin(a), 0))
        ctrl = [d * 0.75 + Vector((0, 0, -0.05)), d * 0.6 + Vector((0, 0, 0.35)), d * 0.25 + Vector((0, 0, 0.85))]
        pts = NB.catmull([*ctrl, d * 0.05 + Vector((0, 0, 1.0))], 14)
        radii = [0.055 * (1 - i / 13) + 0.01 for i in range(14)]
        radii[-1] = 0.0
        tube(piece, pts, radii, [d] * 14, 6, 0.7, FLESH)
    for k in range(3):
        a = math.radians(100 + k * 110 + rnd.uniform(-20, 20))
        p = Vector((math.cos(a) * 0.72, math.sin(a) * 0.72, 0.12))
        blob(piece, p, 0.07, slot=GLOW, seg=8, rings=5, glow=1.0)
    collide("Hive_pod", cyl((0, 0, 0.55), 0.62, 1.1))
    return finish(piece, SINK["pod"], center_xy=True)


def hive_slime() -> bpy.types.Object:
    """The hive's resin layer over the hollow: a glossy dark-red sheet about 12 m across with a rounded lip, its
    edge drawn out in fingers along sinew tendrils that reach out over the ground; the middle stays smooth."""
    rnd = random.Random(2606)
    tendrils = []
    for k in range(11):
        a = k / 11 * math.tau + rnd.uniform(-0.18, 0.18)
        tendrils.append((a, rnd.uniform(3.6, 4.6), rnd.uniform(6.6, 7.6)))
    base = outline(rnd, 5.7, 0.3)
    lobes = [(a, (r1 - 0.45) - base(a), 0.05) for a, _r0, r1 in tendrils]

    def r_of(th: float) -> float:
        """The base outline drawn out in a finger along every tendril."""
        r = base(th)
        for a0, reach, width in lobes:
            d = (th - a0 + math.pi) % math.tau - math.pi
            r += reach * math.exp(-((d / width) ** 2))
        return r

    m = 720
    ring = np.array([(math.cos(a) * r_of(a), math.sin(a) * r_of(a)) for a in (i / m * math.tau for i in range(m))])
    seg_a, seg_b = ring, np.roll(ring, -1, axis=0)

    def dist(x: float, y: float) -> float:
        """Signed distance to the outline (positive inside)."""
        p = np.array((x, y))
        ab = seg_b - seg_a
        t = np.clip(((p - seg_a) * ab).sum(1) / (ab * ab).sum(1), 0, 1)
        d = float(np.min(np.hypot(*(p - (seg_a + ab * t[:, None])).T)))
        return d if math.hypot(x, y) < r_of(math.atan2(y, x)) else -d

    def zfun(x: float, y: float) -> float:
        d = dist(x, y)
        if d >= 0:
            wob = 0.004 * noise.noise(Vector((x * 0.7, y * 0.7, 7.0)))
            return 0.022 * smooth(0.0, 0.14, d) + 0.012 * math.exp(-(((d - 0.16) / 0.08) ** 2)) - 0.004 + wob
        return -0.004 + d * 0.3

    piece = Piece("Hive_slime")
    disc(piece, r_of, zfun, SLIME, grid=0.32, step=0.1, skirt=0.2, rings=(0.1, 0.22, 0.4), dist=dist)
    for k, (a, r0, r1) in enumerate(tendrils):
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        n = int((r1 - r0) / 0.2) + 2
        pts, radii = [], []
        for i in range(n):
            t = i / (n - 1)
            p = d * (r0 + (r1 - r0) * t) + side * (0.22 * math.sin(t * 6 + k) * t)
            rad = 0.11 * smooth(0.0, 0.15, t) * (1 - t) ** 0.6 + 0.012
            p.z = max(zfun(p.x, p.y), 0.0) + rad * 0.2 - 0.03 * (1 - smooth(0.0, 0.12, t))
            pts.append(p)
            radii.append(rad)
        radii[-1] = 0.0
        tube(piece, pts, radii, [Z] * n, 6, 0.5, FLESH)
        # One branch off the outer half.
        i0 = int(n * rnd.uniform(0.45, 0.6))
        b_dir = (d + side * rnd.choice((-0.8, 0.8))).normalized()
        b_len = rnd.uniform(0.8, 1.3)
        bpts, bradii = [], []
        for i in range(7):
            t = i / 6
            p = pts[i0] + b_dir * (b_len * t)
            rad = radii[i0] * 0.6 * (1 - t) + 0.008
            p.z = max(zfun(p.x, p.y), 0.0) + rad * 0.2
            bpts.append(p)
            bradii.append(rad)
        bradii[-1] = 0.0
        tube(piece, bpts, bradii, [Z] * 7, 5, 0.5, FLESH)
    return finish(piece)


BUILDERS = {
    "Den_slab_a": den_slab_a,
    "Den_slab_b": den_slab_b,
    "Den_slab_c": den_slab_c,
    "Den_bones": den_bones,
    "Den_ground": den_ground,
    "Hive_slab_a": hive_slab_a,
    "Hive_slab_b": hive_slab_b,
    "Hive_rib_a": hive_rib_a,
    "Hive_rib_b": hive_rib_b,
    "Hive_pod": hive_pod,
    "Hive_slime": hive_slime,
}

# --- materials ----------------------------------------------------------------------------------------------


class Mat(N.MatNodes):
    """Node helpers around one procedural material."""

    def ramp(self, a, b, src):
        return C._bw(self.nt, C._ramp(self.nt, a, b, src))

    def attr(self, name: str):
        n = self.nt.nodes.new("ShaderNodeAttribute")
        n.attribute_type = "GEOMETRY"
        n.attribute_name = name
        return n.outputs["Fac"]

    def height_z(self):
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.obj, sep.inputs["Vector"])
        return sep.outputs["Z"]

    def cavity(self, distance: float, lo: float = 0.25, hi: float = 0.95):
        """1 in cavities, 0 in the open."""
        ao = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = distance
        ao.samples = 16
        return self.math("SUBTRACT", 1.0, self.ramp(lo, hi, ao.outputs["AO"]), clamp=True)

    def image(self, path: pathlib.Path, extent: float):
        """Channels (R, G, B, A) of a map laid over extent x extent m of the object's XY, centered."""
        img = bpy.data.images.load(str(path), check_existing=True)
        img.colorspace_settings.name = "Non-Color"
        img.alpha_mode = "CHANNEL_PACKED"
        vm = self.nt.nodes.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY_ADD"
        self.nt.links.new(self.obj, vm.inputs[0])
        vm.inputs[1].default_value = (1 / extent, 1 / extent, 0.0)
        vm.inputs[2].default_value = (0.5, 0.5, 0.0)
        tex = self.nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.interpolation = "Cubic"
        tex.extension = "EXTEND"
        self.nt.links.new(vm.outputs[0], tex.inputs["Vector"])
        sep = self.nt.nodes.new("ShaderNodeSeparateColor")
        self.nt.links.new(tex.outputs["Color"], sep.inputs["Color"])
        return sep.outputs["Red"], sep.outputs["Green"], sep.outputs["Blue"], tex.outputs["Alpha"]


def mat_rock(name: str, hive: bool) -> bpy.types.Material:
    """Dark neutral grey-brown rock (fits every biome): per-facet tone, faint strata, chipped lighter ridges, fine
    cracks, cavity grime, dust at the foot; claw gouges pale fresh rock. The hive's slabs are stained dark red where
    resin seeped in (lower half) and glossier there."""
    m = Mat(name)
    warped = m.warped(1.2, 0.35)
    breakup = m.noise(2.0, 4.0, 0.55)
    crack = m.math("MULTIPLY", C._voronoi_lines(m.nt, warped, 2.4, 0.022), m.ramp(0.55, 0.7, breakup))
    tone = m.noise(0.6, 5.0, 0.6)
    base = m.mix(m.ramp(0.3, 0.72, tone), (0.034, 0.031, 0.028), (0.068, 0.062, 0.054))
    base = m.scale(base, m.math("MULTIPLY_ADD", m.attr("facet"), 0.6, 0.7))
    base = m.scale(base, m.math("MULTIPLY_ADD", m.noise(3.0, 3.0, 0.5), 0.35, 0.83))
    wave = m.nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 0.8
    wave.inputs["Distortion"].default_value = 5.0
    m.nt.links.new(m.obj, wave.inputs["Vector"])
    base = m.scale(base, m.math("MULTIPLY_ADD", wave.outputs["Fac"], 0.18, 0.9))
    grain = m.noise(34.0, 4.0, 0.7)
    base = m.scale(base, m.math("MULTIPLY_ADD", grain, 0.25, 0.87))
    edge = m.math("MULTIPLY", m.ramp(0.015, 0.09, C._bevel_edge(m.nt, 0.04, m.geo)), m.ramp(0.3, 0.6, m.noise(8.0)))
    col = m.mix(edge, base, m.scale(base, 1.6))
    fresh = m.attr("fresh")
    fresh_col = m.mix(grain, (0.1, 0.094, 0.086), (0.15, 0.142, 0.128))
    col = m.mix(fresh, col, fresh_col)
    cavity = m.cavity(0.35)
    col = m.mix(cavity, col, (0.008, 0.007, 0.007))
    col = m.mix(m.math("MULTIPLY", crack, 0.8), col, (0.01, 0.009, 0.009))
    low = m.math("SUBTRACT", 1.0, m.ramp(0.0, 0.7, m.height_z()), clamp=True)
    dust = m.math("MULTIPLY", low, m.ramp(0.35, 0.65, m.noise(3.0)))
    col = m.mix(m.math("MULTIPLY", dust, 0.55), col, (0.07, 0.064, 0.056))
    rough = m.mixf(tone, 0.82, 0.93)
    rough = m.mixf(edge, rough, 0.75)
    rough = m.mixf(fresh, rough, 0.7)
    if hive:
        seep = m.math("SUBTRACT", 1.0, m.ramp(0.4, 2.6, m.height_z()), clamp=True)
        stain = m.math("MULTIPLY", seep, m.ramp(0.4, 0.6, m.noise(1.6, 4.0, 0.6, warped)))
        stain = m.math("MAXIMUM", stain, m.math("MULTIPLY", cavity, 0.7))
        col = m.mix(m.math("MULTIPLY", stain, 0.85), col, (0.03, 0.008, 0.009))
        rough = m.mixf(stain, rough, 0.3)
    lumps = m.nt.nodes.new("ShaderNodeTexVoronoi")
    lumps.feature = "SMOOTH_F1"
    lumps.inputs["Scale"].default_value = 2.5
    m.nt.links.new(warped, lumps.inputs["Vector"])
    height = m.math("MULTIPLY", lumps.outputs["Distance"], 0.7)
    height = m.math("ADD", height, m.math("MULTIPLY", grain, 0.2))
    height = m.math("SUBTRACT", height, m.math("MULTIPLY", crack, 0.5))
    return m.out(col, rough, height, 0.6, 0.04)


def mat_bone() -> bpy.types.Material:
    """Old bone: muted pale, fine cracks, darker porous patches, dark dried stains, dirt where it lies."""
    m = Mat("LairBone")
    warped = m.warped(2.0, 0.3)
    tone = m.noise(1.5, 4.0, 0.55)
    col = m.mix(m.ramp(0.3, 0.7, tone), (0.17, 0.155, 0.12), (0.26, 0.235, 0.185))
    grain = m.noise(40.0, 3.0, 0.6)
    col = m.scale(col, m.math("MULTIPLY_ADD", grain, 0.15, 0.92))
    cracks = m.math("MULTIPLY", C._voronoi_lines(m.nt, warped, 5.0, 0.02), m.ramp(0.45, 0.6, m.noise(3.0)))
    col = m.mix(cracks, col, (0.05, 0.042, 0.032))
    pores = m.math("MULTIPLY", m.ramp(0.55, 0.75, m.noise(2.5)), m.ramp(0.5, 0.7, m.noise(55.0, 2.0, 0.5)))
    col = m.mix(m.math("MULTIPLY", pores, 0.6), col, (0.09, 0.075, 0.055))
    stain = m.ramp(0.62, 0.78, m.noise(2.2, 4.0, 0.6, warped))
    col = m.mix(m.math("MULTIPLY", stain, 0.75), col, (0.05, 0.022, 0.016))
    dirt = m.math("SUBTRACT", 1.0, m.ramp(0.0, 0.18, m.height_z()), clamp=True)
    col = m.mix(m.math("MULTIPLY", dirt, 0.7), col, (0.05, 0.045, 0.04))
    col = m.mix(m.cavity(0.2), col, (0.02, 0.017, 0.014))
    rough = m.mixf(tone, 0.58, 0.72)
    height = m.math("SUBTRACT", m.math("MULTIPLY", grain, 0.2), m.math("ADD", cracks, m.math("MULTIPLY", pores, 0.3)))
    return m.out(col, rough, height, 0.35, 0.01)


def mat_shell() -> bpy.types.Material:
    """The prey's carapace: dull dark olive-brown plates with paler growth bands, bleached worn edges, the chalky
    inside and the broken edges pale."""
    m = Mat("LairShell")
    tone = m.noise(1.8, 4.0, 0.55)
    col = m.mix(m.ramp(0.3, 0.7, tone), (0.045, 0.042, 0.034), (0.085, 0.08, 0.062))
    wave = m.nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 3.8
    wave.inputs["Distortion"].default_value = 2.0
    m.nt.links.new(m.obj, wave.inputs["Vector"])
    bands = m.ramp(0.55, 0.9, wave.outputs["Fac"])
    col = m.mix(m.math("MULTIPLY", bands, 0.5), col, (0.12, 0.11, 0.085))
    edge = m.ramp(0.02, 0.1, C._bevel_edge(m.nt, 0.02, m.geo))
    col = m.mix(m.math("MULTIPLY", edge, 0.8), col, (0.2, 0.185, 0.15))
    inner = m.attr("fresh")
    col = m.mix(inner, col, m.mix(m.noise(20.0), (0.13, 0.115, 0.09), (0.18, 0.16, 0.125)))
    col = m.mix(m.cavity(0.2), col, (0.012, 0.011, 0.009))
    rough = m.mixf(tone, 0.42, 0.55)
    rough = m.mixf(inner, rough, 0.8)
    height = m.math("ADD", m.math("MULTIPLY", bands, 0.4), m.math("MULTIPLY", m.noise(30.0), 0.15))
    return m.out(col, rough, height, 0.3, 0.01)


def mat_soil() -> bpy.types.Material:
    """Trampled dark soil from the den map: packed and dark where the feet pressed it, lighter churned soil thrown
    up along the furrows and the rim, moist and darker in the hollows, a few old stains."""
    m = Mat("LairSoil")
    h01, churned, stain, packed = m.image(DEN_MAP, DEN_E)
    lo, hi = DEN_HRANGE
    tone = m.noise(0.7, 4.0, 0.55)
    grain = m.noise(45.0, 3.0, 0.6)
    flat = m.mix(m.ramp(0.3, 0.7, tone), (0.024, 0.022, 0.019), (0.038, 0.034, 0.029))
    thrown = m.mix(m.ramp(0.3, 0.7, m.noise(5.0, 3.0, 0.6)), (0.042, 0.037, 0.031), (0.062, 0.055, 0.046))
    col = m.mix(m.math("MULTIPLY", churned, 0.75), flat, thrown)
    col = m.mix(m.math("MULTIPLY", packed, 0.25), col, (0.018, 0.017, 0.015))
    level = -lo / (hi - lo)
    hollow = m.math("SUBTRACT", 1.0, m.ramp(level - 0.22, level - 0.04, h01), clamp=True)
    col = m.mix(m.math("MULTIPLY", hollow, 0.35), col, (0.014, 0.013, 0.011))
    col = m.mix(m.math("MULTIPLY", stain, 0.6), col, (0.028, 0.009, 0.009))
    col = m.scale(col, m.math("MULTIPLY_ADD", grain, 0.25, 0.88))
    col = m.mix(m.cavity(0.15), col, (0.01, 0.009, 0.008))
    rough = m.mixf(churned, 0.86, 0.95)
    rough = m.mixf(packed, rough, 0.74)
    rough = m.mixf(stain, rough, 0.6)
    height = m.math("MULTIPLY", h01, hi - lo)
    height = m.math("ADD", height, m.math("MULTIPLY", grain, 0.004))
    return m.out(col, rough, height, 1.0, 1.0)


def mat_slime() -> bpy.types.Material:
    """The hive's resin layer: glossy dark wine red with darker sinew veins under the surface, slow flow streaks,
    small blisters, a drier, duller film along the rim."""
    m = Mat("LairSlime")
    warped = m.warped(0.8, 0.5)
    big = m.noise(0.6, 4.0, 0.55)
    col = m.mix(m.ramp(0.25, 0.75, big), (0.024, 0.0045, 0.0065), (0.05, 0.009, 0.012))
    streak = m.noise(1.6, 6.0, 0.6, warped)
    col = m.mix(m.math("MULTIPLY", m.ramp(0.55, 0.75, streak), 0.5), col, (0.065, 0.013, 0.015))
    veins = m.math("MULTIPLY", C._voronoi_lines(m.nt, warped, 0.9, 0.035), m.ramp(0.35, 0.6, m.noise(1.3)))
    col = m.mix(m.math("MULTIPLY", veins, 0.8), col, (0.01, 0.0025, 0.004))
    rim = m.math("MULTIPLY", m.attr("edge"), m.ramp(0.3, 0.6, m.noise(4.0)))
    col = m.mix(m.math("MULTIPLY", rim, 0.7), col, (0.055, 0.024, 0.02))
    blister = m.nt.nodes.new("ShaderNodeTexVoronoi")
    blister.inputs["Scale"].default_value = 7.0
    m.nt.links.new(warped, blister.inputs["Vector"])
    dome = m.math(
        "MULTIPLY",
        m.math("SUBTRACT", 1.0, m.ramp(0.0, 0.2, blister.outputs["Distance"]), clamp=True),
        m.ramp(0.55, 0.7, m.noise(2.3)),
    )
    col = m.mix(m.math("MULTIPLY", m.cavity(0.12), 0.7), col, (0.008, 0.002, 0.003))
    rough = m.mixf(big, 0.06, 0.14)
    rough = m.mixf(rim, rough, 0.45)
    m.bsdf.inputs["Specular IOR Level"].default_value = 0.6
    height = m.math("ADD", m.math("MULTIPLY", veins, 0.5), m.math("MULTIPLY", dome, 0.8))
    height = m.math("ADD", height, m.math("MULTIPLY", streak, 0.3))
    return m.out(col, rough, height, 0.25, 0.012)


def mat_sac() -> bpy.types.Material:
    """Brood pod membrane: pale, sickly, veined dark red, very glossy, glowing faintly from inside (the "glow"
    layer: brightest round the middle, none at the base) between the veins."""
    m = Mat("LairSac")
    big = m.noise(3.0, 3.0, 0.5)
    col = m.mix(big, (0.075, 0.04, 0.024), (0.12, 0.068, 0.04))
    veins = m.ramp(0.0, 1.0, NB._veins(m.nt, m.obj, 5.0, 0.05))
    col = m.mix(veins, col, (0.08, 0.012, 0.015))
    col = m.mix(m.math("MULTIPLY", m.cavity(0.15), 0.85), col, (0.02, 0.006, 0.004))
    glow = m.nt.nodes.new("ShaderNodeAttribute")
    glow.attribute_name = "glow"
    lit = m.math("MULTIPLY", glow.outputs["Fac"], m.math("SUBTRACT", 1.0, veins, clamp=True))
    lit = m.math("MULTIPLY", lit, m.mixf(m.noise(4.0), 0.012, 0.04))
    m.nt.links.new(lit, m.bsdf.inputs["Emission Strength"])
    m.bsdf.inputs["Emission Color"].default_value = (*GLOW_COLOR, 1.0)
    return m.out(col, m.mixf(veins, 0.1, 0.25), veins, 0.35, 0.006)


def mat_glow() -> bpy.types.Material:
    """Glands: the aliens' sickly yellow-green glow, churning a little (the nest's and the Ravager's color)."""
    m = Mat("LairGlow")
    churn = m.noise(9.0, 4.0, 0.6)
    col = m.mix(churn, (0.4, 0.62, 0.012), GLOW_COLOR)
    m.nt.links.new(col, m.bsdf.inputs["Emission Color"])
    m.nt.links.new(m.mixf(churn, 1.6, 3.0), m.bsdf.inputs["Emission Strength"])
    return m.out(m.mix(churn, (0.2, 0.3, 0.008), (0.35, 0.5, 0.015)), 0.15, churn, 0.1, 0.005)


def make_materials() -> list:
    return [
        mat_rock("LairRock", False),
        mat_rock("LairRockHive", True),
        mat_bone(),
        mat_shell(),
        mat_soil(),
        NB.mat_chitin(),
        NB.mat_flesh(),
        NB.mat_resin(),
        mat_sac(),
        mat_slime(),
        mat_glow(),
    ]


# --- layouts (Godot coordinates of the part's scene) --------------------------------------------------------


def ring_at(name: str, phi: float, r: float, dyaw: float = 0.0, scale: float = 1.0) -> tuple:
    """A piece on a ring around the part's middle, its front (-Y in Blender, +Z in Godot) turned to the middle:
    Godot position (x, 0, z), yaw (deg about Y), uniform scale. phi 0 = the back (+Z), 180 = the way in (-Z)."""
    a = math.radians(phi)
    x, z = r * math.sin(a), r * math.cos(a)
    yaw = (phi + 180 + dyaw + 180) % 360 - 180
    return (name, round(x, 2), round(z, 2), round(yaw, 1), scale)


DEN_LAYOUT = [
    ("Den_ground", 0.0, 0.4, 0.0, 1.0),
    ring_at("Den_slab_a", -12, 8.6),
    ring_at("Den_slab_b", 24, 8.5, 6),
    ring_at("Den_slab_a", 60, 8.3, -8, 0.9),
    ring_at("Den_slab_c", 98, 9.2, 0, 1.0),
    ring_at("Den_slab_b", -52, 8.4, -5, 0.92),
    ring_at("Den_slab_a", -90, 8.2, 10, 0.85),
    ring_at("Den_slab_c", -128, 9.3, 15, 0.9),
    ring_at("Den_slab_b", 132, 8.7, -10, 0.8),
    ring_at("Den_bones", -38, 6.6, 70),
    ring_at("Den_bones", 118, 6.2, -40, 0.85),
]
HIVE_LAYOUT = [
    ("Hive_slime", 0.0, 0.4, 0.0, 1.0),
    ring_at("Hive_slab_a", 0, 8.7),
    ring_at("Hive_slab_b", -48, 8.5, 8),
    ring_at("Hive_slab_b", 46, 8.6, -10, 0.95),
    ring_at("Hive_slab_a", -100, 8.8, 5, 0.9),
    ring_at("Hive_slab_a", 102, 8.9, -5, 0.85),
    ring_at("Hive_rib_a", -72, 6.9),
    ring_at("Hive_rib_a", 74, 6.9, 0, 0.95),
    ring_at("Hive_rib_b", -24, 7.1, 0),
    ring_at("Hive_rib_b", 26, 7.0, 0, 1.05),
    ring_at("Hive_rib_a", -122, 7.2, 0, 0.85),
    ring_at("Hive_rib_b", 124, 7.3, 0, 0.9),
    ring_at("Hive_pod", -5, 5.9, 0, 1.0),
    ring_at("Hive_pod", -88, 5.8, 30, 0.85),
    ring_at("Hive_pod", 140, 6.4, -20, 0.9),
]
LAYOUTS = {"den": DEN_LAYOUT, "hive": HIVE_LAYOUT}
PROP_RADIUS = 12.5
FOOTPRINT = 15.5
ANCHOR = (0.0, 0.6)  # Godot (x, z) of the QuestAnchor

# --- preview scene and renders ------------------------------------------------------------------------------

GROUND = ((0.045, 0.042, 0.038), (0.085, 0.078, 0.068))  # a neutral dusty ground (linear)


def setup_preview() -> None:
    C.preview_scene(crystals=False, pebbles=False)
    bpy.data.objects["PreviewGround"].scale = (3, 3, 1)
    C.tint_ground(GROUND[0], GROUND[1])


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in PIECES]


KIT = {  # overview positions (Blender x, y)
    "Den_ground": (-7.0, 4.0),
    "Den_slab_a": (-11.0, -3.0),
    "Den_slab_b": (-6.0, -3.0),
    "Den_slab_c": (-1.5, -3.0),
    "Den_bones": (-4.0, 4.0),
    "Hive_slime": (8.0, 4.0),
    "Hive_slab_a": (3.0, -3.0),
    "Hive_slab_b": (8.0, -3.0),
    "Hive_rib_a": (12.0, -1.0),
    "Hive_rib_b": (15.0, -1.0),
    "Hive_pod": (5.0, 3.0),
}


def apply_kit_layout() -> None:
    for name, (x, y) in KIT.items():
        obj = bpy.data.objects[name]
        obj.location = (x, y, 0)
        obj.rotation_euler = (0, 0, 0)
        obj.hide_render = False
    bpy.data.objects["PreviewFigure"].location = (0.5, -6.0, 0)


def apply_bake_layout(gap: float = 3.0) -> None:
    """Saved .blend layout: every piece unrotated in one row along X with `gap` m between them (no AO from a
    neighbor); the bake zeroes the locations before the export."""
    x = 0.0
    bpy.context.view_layer.update()
    for name in PIECES:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.hide_render = False
        lo = min((obj.matrix_world.to_3x3() @ Vector(c)).x for c in obj.bound_box)
        hi = max((obj.matrix_world.to_3x3() @ Vector(c)).x for c in obj.bound_box)
        obj.location = (x - lo, 0, 0)
        x += hi - lo + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -3.0, 0)


def render_piece(name: str, prefix: str, views, samples: int, size: int) -> list:
    obj = bpy.data.objects[name]
    for o in kit_objects():
        o.hide_render = o is not obj
    obj.rotation_mode = "XYZ"
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    dx, dy, dz = obj.dimensions
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
    bpy.data.objects["PreviewFigure"].location = side * (max(dx, dy) / 2 + 0.6)
    w = max(dx, dy, dz * 1.1) * 1.25 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.4, dz * 0.4)))
    out = []
    for view in views:
        path = OUT / f"{prefix}{name}_{view}.png"
        C.render(
            path, view=view, samples=samples, size=size, target=tuple(target), zoom=w / (9.9 if view == "iso" else 6.3)
        )
        out.append(path)
    for o in kit_objects():
        o.hide_render = False
    return out


def _flat_mat(name: str, color, emission: float = 0.0) -> bpy.types.Material:
    mat, _nt, bsdf = C._new_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def _preview_mesh(name: str, op, mat, **kw) -> bpy.types.Object:
    op(**kw)
    obj = bpy.context.active_object
    for c in obj.users_collection:
        c.objects.unlink(obj)
    C.collection("Preview").objects.link(obj)
    obj.name = name
    C.assign(obj, mat)
    return obj


def game_light(on: bool) -> None:
    """Dim, cool game-like light: a weak low sun and a little sky instead of the preview's studio lights."""
    for name in ("Key", "Rim", "RimLow", "Fill"):
        bpy.data.objects[name].hide_render = on
    sun = bpy.data.objects.get("GameSun")
    if sun is None:
        data = bpy.data.lights.new("GameSun", "SUN")
        data.energy = 3.0
        data.color = (0.82, 0.88, 1.0)
        data.angle = math.radians(4)
        sun = bpy.data.objects.new("GameSun", data)
        C.collection("Preview").objects.link(sun)
        sun.rotation_euler = (math.radians(90 - 28), 0, math.radians(-150))
    sun.hide_render = not on
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.08, 0.09, 0.11, 1.0) if on else (0.012, 0.014, 0.018, 1.0)


def render_layout(part: str, path: pathlib.Path, from_front: bool, samples: int, size: int, zoom: float = 1.0) -> None:
    """The part's pieces placed like its layout, a 1.89 m pole, the prop radius as a thin ring and the quest anchor
    as an amber dot, from the game's angle (50 degrees down, 45 around; from_front looks in from the way in)."""
    for o in kit_objects():
        o.hide_render = True
    bpy.data.objects["PreviewFigure"].hide_render = True
    temp = []
    for name, x, z, yaw, scale in LAYOUTS[part]:
        d = bpy.data.objects[name].copy()
        C.collection("Preview").objects.link(d)
        d.parent = None
        d.hide_render = False
        d.rotation_mode = "XYZ"
        d.location = (x, -z, 0)
        d.rotation_euler = (0, 0, math.radians(yaw))
        d.scale = (scale,) * 3
        temp.append(d)
    pole_mat = _flat_mat("PreviewPole", (0.6, 0.6, 0.58))
    ring_mat = _flat_mat("PreviewRing", (0.5, 0.5, 0.5), 0.6)
    amber = _flat_mat("PreviewAnchor", (1.0, 0.45, 0.05), 3.0)
    temp.append(
        _preview_mesh(
            "Pole", bpy.ops.mesh.primitive_cylinder_add, pole_mat, radius=0.05, depth=1.89, location=(1.5, 9.5, 0.945)
        )
    )
    temp.append(
        _preview_mesh(
            "Ring",
            bpy.ops.mesh.primitive_torus_add,
            ring_mat,
            major_radius=PROP_RADIUS,
            minor_radius=0.04,
            major_segments=128,
            minor_segments=4,
        )
    )
    temp.append(
        _preview_mesh(
            "Anchor",
            bpy.ops.mesh.primitive_cylinder_add,
            amber,
            radius=0.15,
            depth=0.04,
            location=(ANCHOR[0], -ANCHOR[1], 0.05),
        )
    )
    game_light(True)
    sign = -1 if from_front else 1
    horiz = Vector((math.sqrt(0.5), -math.sqrt(0.5), 0)) * sign
    pitch = math.radians(50)
    dist = 44.0 * zoom
    target = Vector((0, 0, 0.8))
    loc = target + (horiz * math.cos(pitch) + Vector((0, 0, math.sin(pitch)))) * dist
    C.render_from(path, tuple(loc), tuple(target), lens=50, samples=samples, size=size)
    game_light(False)
    for d in temp:
        bpy.data.objects.remove(d)
    for o in kit_objects():
        o.hide_render = False
    bpy.data.objects["PreviewFigure"].hide_render = False


def check_layouts() -> None:
    """Every piece of a layout inside the prop radius; print the layout in Godot terms."""
    dg = bpy.context.evaluated_depsgraph_get()
    for part, layout in LAYOUTS.items():
        for name, x, z, yaw, scale in layout:
            obj = bpy.data.objects[name]
            me = obj.evaluated_get(dg).to_mesh()
            m = Matrix.Translation((x, -z, 0)) @ rz(yaw).to_4x4() @ Matrix.Diagonal((scale,) * 3 + (1,))
            reach = max(Vector((p.x, p.y)).length for p in (m @ v.co for v in me.vertices))
            obj.evaluated_get(dg).to_mesh_clear()
            flag = "" if reach <= PROP_RADIUS else "  OUTSIDE prop_radius!"
            print(f"LAYOUT {part} {name}: pos ({x}, 0, {z}) rot (0, {yaw}, 0) scale {scale} reach {reach:.2f}{flag}")


# --- report -------------------------------------------------------------------------------------------------


def godot_prims(prims: list) -> list:
    """Collision primitives in Godot axes (Y-up; Godot (x, y, z) = Blender (x, z, -y))."""
    out = []
    for p in prims:
        if "box" in p:
            c, s, axis, deg = p["box"]
            g_axis, g_deg = {"X": ("x", deg), "Y": ("z", -deg), "Z": ("y", deg)}[axis]
            rot = f" rot {g_axis} {g_deg:g}" if deg else ""
            out.append(f"box center ({c.x:.2f}, {c.z:.2f}, {-c.y:.2f}) size ({s.x:.2f}, {s.z:.2f}, {s.y:.2f}){rot}")
        else:
            c, r, h = p["cyl"]
            out.append(f"cylinder center ({c.x:.2f}, {c.z:.2f}, {-c.y:.2f}) radius {r:.2f} height {h:.2f}")
    return out


def report() -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    total = 0
    for name in PIECES:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        zs = [v.co.z for v in me.vertices]
        slots = sorted({p.material_index for p in me.polygons})
        total += len(me.loop_triangles)
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(d, 2) for d in obj.dimensions)}"
            f" z=({min(zs):.2f}, {max(zs):.2f}) slots={slots}"
        )
        obj.evaluated_get(dg).to_mesh_clear()
        for line in godot_prims(COLLISION.get(name, [])):
            print(f"COLLISION {name}: {line}")
    print("STATS total triangles", total)


# --- main ---------------------------------------------------------------------------------------------------


def build() -> None:
    global ROOT_OBJ, MATS, DEN_MAP
    ROOT_OBJ = C.asset_root(ASSET)
    work = bpy.data.collections.new("Work")
    bpy.context.scene.collection.children.link(work)
    DEN_MAP = OUT / "maps" / "den_ground.exr"
    MATS = []
    # The soil material reads the den map: build the ground first, then the materials, then attach them.
    ground = den_ground()
    MATS[:] = make_materials()
    for mat in MATS:
        ground.data.materials.append(mat)
    for name in PIECES:
        if name != "Den_ground":
            BUILDERS[name]()
    for coll in [work, *work.children_recursive]:
        for obj in list(coll.objects):
            me = obj.data
            bpy.data.objects.remove(obj)
            if me.users == 0:
                bpy.data.meshes.remove(me)
    for coll in [*work.children_recursive, work]:
        bpy.data.collections.remove(coll)


def main() -> None:
    C.reset(ASSET)
    build()
    report()
    check_layouts()
    setup_preview()
    apply_kit_layout()
    if MODE == "final":
        sheet = []
        apply_kit_layout()
        sheet.append(OUT / "final_kit_iso.png")
        C.render(sheet[-1], view="iso", samples=64, size=1024, target=(2.0, 0.0, 1.0), zoom=2.6)
        for part in ("den", "hive"):
            for front in (False, True):
                p = OUT / f"layout_{part}_{'front' if front else 'back'}.png"
                render_layout(part, p, front, 96, 1280)
                sheet.append(p)
            p = OUT / f"layout_{part}_close.png"
            render_layout(part, p, True, 96, 1280, zoom=0.62)
            sheet.append(p)
        for name in PIECES:
            sheet += render_piece(name, "final_", ("iso", "hero"), 48, 640)
        apply_kit_layout()
        C.contact_sheet(sheet, OUT / "sheet.png", cols=5, tile=512, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "lairs_procedural.blend")
        return
    wip = OUT / "wip"
    for view in VIEWS:
        if view == "kit":
            apply_kit_layout()
            C.render(wip / f"{TAG}_kit.png", view="iso", samples=24, size=1024, target=(2.0, 0.0, 1.0), zoom=2.6)
        elif view == "pieces":
            for name in PIECES:
                render_piece(name, f"wip/{TAG}_", ("iso", "hero"), 20, 512)
        elif view in BUILDERS:
            render_piece(view, f"wip/{TAG}_", ("iso", "hero"), 32, 768)
        elif view in LAYOUTS:
            render_layout(view, wip / f"{TAG}_{view}_back.png", False, 32, 1024)
            render_layout(view, wip / f"{TAG}_{view}_front.png", True, 32, 1024)
            render_layout(view, wip / f"{TAG}_{view}_close.png", True, 32, 1024, zoom=0.62)
        elif view == "sheet":
            names = sorted(p for p in wip.glob(f"{TAG}_*.png") if not p.name.endswith("sheet.png"))
            C.contact_sheet(names, wip / f"{TAG}_sheet.png", cols=4, tile=384, background=0.02)
        elif view == "save":
            apply_bake_layout()
            C.save_blend(OUT / "lairs_procedural.blend")
            return


if __name__ == "__main__":  # lairs_bake.py imports the layouts and renders
    main()
