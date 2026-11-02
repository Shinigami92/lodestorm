"""Rich vein kit (map part game/locations/parts/rich_vein.tscn): a wall of big dark smoky crystals breaking out of
a rock shelf in an arc, two loose crystal clusters to set beside it and a litter of fallen broken shards.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/vein/source/vein_build.py wip v1                     # pieces + layout
    tools/blender.sh assets/parts/vein/source/vein_build.py wip v1 Vein_wall,layout
    tools/blender.sh assets/parts/vein/source/vein_build.py final

Everything it writes goes to tmp/assets/parts/vein/: "wip <tag> [views]" renders previews into wip/<tag>_*.png
(views: pieces, layout, sheet, save, or a piece name); "final" renders every piece (front, back, hero), the part's
layout from the game's angle (front and back), writes the contact sheet sheet.png and saves the procedural
vein_procedural.blend that vein_bake.py turns into the game asset. In the .blend the pieces stand unrotated in a
row along X, 3 m apart (bake layout, so the AO bake doesn't pick up neighbors); the bake zeroes their locations.

Game contract (docs/technical/assets.md, map parts): every piece is one mesh at the kit's root, origin at the
bottom center (the ground contact), extra geometry below z = 0 (SINK). The wall's open side, where the crystals face
the area's way in, is +Y (the part's front, Godot -z): the wall is built around the greybox's arc of seven crystal
columns (radius ARC_R around the part's center, -63 to +63 degrees, the arc's middle at Godot +z); its origin sits
at the middle of its bounds, WALL_ORIGIN in the part's frame (printed by the build).

The crystals are dark smoky quartz, not ore: near-black brown-grey glass, opaque (the game imports no transmission),
glossy with a faint cold sheen from the sky, paler at their edges, faint fracture planes inside, never glowing;
the glowing ore placed in front of the wall stays the brightest, most saturated thing. The rock is neutral
grey-brown (the game lays the biome's cover on top-facing faces itself).

Modeling: convex pieces (convex hulls of jittered points, shaved by plane cuts) united with a boolean (manifold
solver), minus thin cutters for cracks and chips; the litter of shards stays separate shells of one mesh. A face
attribute "crystal" (1 crystal, 0 rock) rides through the booleans and picks each face's material; a random
per-face "facet" gives every face its own tone (dropped after the bake).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "vein"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
from common import T, ry, rz
from rock_geo import add_boolean, box_points, cut, hull, rand_dir, rand_rot, support, work_collection

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "v0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["pieces", "layout"]

ASSET = "Vein"
PIECES = ["Vein_wall", "Vein_cluster_a", "Vein_cluster_b", "Vein_shards"]
FRONT_Y = ("Vein_wall",)  # pieces whose front is +Y (the others have no front)
# Geometry kept below z = 0 per piece (m), so uneven ground never shows the bottom.
SINK = {"Vein_wall": 0.5, "Vein_cluster_a": 0.35, "Vein_cluster_b": 0.3, "Vein_shards": 0.06}
SHARP_DEG = 30.0  # edges sharper than this split the shading (facets); softer ones shade smooth
ARC_R = 6.2  # the greybox's crystal arc: radius around the part's center
PROP_RADIUS = 8.0  # rich_vein.tscn keeps map_part.gd's default
FOOTPRINT = 11.0
# Greybox markers (Godot x, z): the rarest ore in front of the wall.
ORE_MARKERS = [(-2.8, 2.2), (0.0, 3.4), (2.8, 2.2)]
WALL_ORIGIN = Vector((0.0, 0.0, 0.0))  # set by vein_wall(): the wall's origin in the part's frame (Blender)

# --- math helpers -------------------------------------------------------------------------------------


def lean(direction: Vector, deg: float) -> Matrix:
    """Rotation tipping +Z by `deg` degrees toward the horizontal `direction`."""
    axis = Vector((0, 0, 1)).cross(Vector((direction.x, direction.y, 0)))
    if axis.length < 1e-6:
        return Matrix.Identity(3)
    return Matrix.Rotation(math.radians(deg), 3, axis.normalized())


def arc(theta: float, r: float, z: float = 0.0) -> Vector:
    """Point on the greybox's arc (part frame): theta in degrees from its middle (Blender -Y), + toward +X."""
    a = math.radians(theta)
    return Vector((r * math.sin(a), -r * math.cos(a), z))


def outward(theta: float) -> Vector:
    """Horizontal direction away from the part's center (into the rock behind the wall)."""
    return arc(theta, 1.0)


def along(theta: float) -> Vector:
    """Horizontal direction along the arc, toward its +X end."""
    a = math.radians(theta)
    return Vector((math.cos(a), math.sin(a), 0.0))


# --- convex pieces -----------------------------------------------------------------------------------


def place(bm: bmesh.types.BMesh, m: Matrix) -> bmesh.types.BMesh:
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    bm.normal_update()
    return bm


def chunk(rnd: random.Random, size, cuts: int = 3, m: Matrix | None = None, keep=(0.72, 0.9), **kw):
    """A jagged rock block: a jittered box hull with `cuts` fracture facets shaved off its upper flanks."""
    bm = hull(box_points(rnd, size, **kw))
    for _ in range(cuts):
        cut(bm, rand_dir(rnd, min_z=-0.2), rnd.uniform(*keep))
    return place(bm, m) if m is not None else bm


def quartz(rnd: random.Random, r: float, length: float, flat: float = 0.9, broken: bool = False, m=None):
    """A smoky quartz column from z = 0 up to its point at `length`: an uneven six-sided prism narrowing a little
    toward the shoulder, then a six-faced point (off-center, about one radius high); `broken` snaps the point off at
    a slant, leaving a fresh fracture face."""
    a0 = rnd.uniform(0, math.tau)
    tip = min(r * rnd.uniform(1.0, 1.5), length * 0.45)
    shoulder = length - tip
    pts = []
    for i in range(6):
        a = a0 + (i + rnd.uniform(-0.1, 0.1)) / 6 * math.tau
        k = 1 + rnd.uniform(-0.16, 0.16)
        x, y = math.cos(a) * r * k, math.sin(a) * r * k * flat
        pts.append(Vector((x, y, 0.0)))
        t = 0.88 * (1 + rnd.uniform(-0.05, 0.05))
        pts.append(Vector((x * t, y * t, shoulder * (1 + rnd.uniform(-0.03, 0.03)))))
    pts.append(Vector((rnd.uniform(-0.3, 0.3) * r, rnd.uniform(-0.3, 0.3) * r * flat, length)))
    bm = hull(pts)
    if broken:
        a = rnd.uniform(0, math.tau)
        cut(bm, (math.cos(a) * 0.7, math.sin(a) * 0.7, 1.0), rnd.uniform(0.7, 0.8))
    return place(bm, m) if m is not None else bm


def prism_piece(rnd: random.Random, r: float, length: float, m: Matrix) -> bmesh.types.BMesh:
    """A broken length of a crystal column lying on its side (along X): six-sided, both ends snapped off at a
    slant; or, now and then, its point still on."""
    a0 = rnd.uniform(0, math.tau)
    pts = []
    taper = rnd.uniform(0.6, 0.85)
    flat = rnd.uniform(0.6, 0.85)
    for i in range(6):
        a = a0 + (i + rnd.uniform(-0.1, 0.1)) / 6 * math.tau
        k = 1 + rnd.uniform(-0.15, 0.15)
        y, z = math.cos(a) * r * k, math.sin(a) * r * k * flat
        pts.append(Vector((-length / 2, y, z)))
        pts.append(Vector((length / 2, y * taper, z * taper)))
    pointed = rnd.random() < 0.3
    if pointed:
        pts.append(Vector((length / 2 + r * 1.2, rnd.uniform(-0.2, 0.2) * r, rnd.uniform(-0.2, 0.2) * r)))
    bm = hull(pts)
    cut(bm, (-1.0, rnd.uniform(-1.2, 1.2), rnd.uniform(-1.0, 1.0)), rnd.uniform(0.82, 0.92))
    if not pointed:
        cut(bm, (1.0, rnd.uniform(-1.2, 1.2), rnd.uniform(-1.0, 1.0)), rnd.uniform(0.82, 0.92))
    a = rnd.uniform(0, math.tau)  # a long fracture down one flank
    cut(bm, (rnd.uniform(-0.3, 0.3), math.cos(a), math.sin(a)), rnd.uniform(0.75, 0.88))
    return place(bm, m)


def chip_cutter(rnd: random.Random, target: bmesh.types.BMesh, direction, size: float) -> bmesh.types.BMesh:
    """A small rotated block centered on the target's outermost point in `direction`: bites a chip out of a ridge."""
    p = support(target, direction)
    return chunk(rnd, (size, size * rnd.uniform(0.7, 1.1), size * rnd.uniform(0.6, 1.0)), 1, T(p, rand_rot(rnd, 60)))


def crack_cutter(rnd: random.Random, center, length: float, depth: float, width: float, rot: Matrix):
    """Thin slab (length along X, depth along Y, width along Z) that notches a crack into a face."""
    pts = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            for cz in (-1, 1):
                w = width * (rnd.uniform(0.4, 1.0) if cy > 0 else rnd.uniform(1.0, 1.8))  # wider at the mouth (-Y)
                pts.append(Vector((cx * length / 2 * rnd.uniform(0.85, 1.0), cy * depth / 2, cz * w / 2)))
    return place(hull(pts), T(center, rot))


# --- mesh assembly ------------------------------------------------------------------------------------


def bm_to_obj(bm: bmesh.types.BMesh, name: str, coll: str, crystal: float) -> bpy.types.Object:
    """A boolean operand: the piece as an object, every face carrying `crystal` (the booleans pass it on)."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.attributes.new("crystal", "FLOAT", "FACE").data.foreach_set("value", [crystal] * len(me.polygons))
    obj = bpy.data.objects.new(name, me)
    C.collection(coll).objects.link(obj)
    return obj


def solid(name: str, crystals: list, rock: list, cutters: list = ()) -> bmesh.types.BMesh:
    """Union of the rock and crystal pieces minus the cutters, cleaned up, bottom cut flat at -SINK; a face is
    crystal when it comes from a crystal piece (the booleans carry the attribute over)."""
    parts = [(bm, 0.0) for bm in rock] + [(bm, 1.0) for bm in crystals]
    base = bm_to_obj(parts[0][0], name + "_base", "Work", parts[0][1])
    if len(parts) > 1:
        coll = work_collection(name + "_union")
        for i, (bm, c) in enumerate(parts[1:]):
            bm_to_obj(bm, f"{name}_u{i}", coll.name, c)
        add_boolean(base, "UNION", coll)
    if cutters:
        coll = work_collection(name + "_cut")
        for i, bm in enumerate(cutters):
            bm_to_obj(bm, f"{name}_c{i}", coll.name, 0.0)
        add_boolean(base, "DIFFERENCE", coll)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.003)
    bmesh.ops.dissolve_degenerate(bm, dist=0.002, edges=bm.edges[:])
    cut(bm, (0, 0, -1), at=SINK[name])  # flat bottom at z = -SINK (normal points down: keeps what's above)
    layer = bm.faces.layers.float.get("crystal")
    for f in bm.faces:
        f[layer] = 1.0 if f[layer] > 0.5 else 0.0
    bmesh.ops.dissolve_limit(
        bm, angle_limit=math.radians(1.5), verts=bm.verts[:], edges=bm.edges[:], delimit={"NORMAL"}
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def shells(name: str, pieces: list) -> bmesh.types.BMesh:
    """Separate closed pieces (no boolean) as one mesh; `pieces` are (bmesh, crystal) pairs."""
    bm = bmesh.new()
    ranges = []
    for piece, crystal in pieces:
        me = bpy.data.meshes.new("tmp")
        piece.to_mesh(me)
        piece.free()
        start = len(bm.faces)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        ranges.append((start, len(bm.faces), crystal))
    layer = bm.faces.layers.float.new("crystal")
    bm.faces.ensure_lookup_table()
    for start, end, crystal in ranges:
        for f in bm.faces[start:end]:
            f[layer] = crystal
    cut(bm, (0, 0, -1), at=SINK[name])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def finish(bm: bmesh.types.BMesh, name: str) -> tuple[bpy.types.Object, Vector]:
    """Origin at the bottom center (x, y of the bounds' middle), sharp edges split, the material per face from the
    "crystal" attribute, a random tone per face. Returns the piece and how far it was shifted."""
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), 0))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), 0))
    shift = -(lo + hi) / 2
    bmesh.ops.translate(bm, vec=shift, verts=bm.verts[:])
    sharp = math.radians(SHARP_DEG)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > sharp)
    layer = bm.faces.layers.float.get("crystal")
    for f in bm.faces:
        f.smooth = True
        f.material_index = 1 if f[layer] > 0.5 else 0
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.attributes.remove(me.attributes["crystal"])
    rnd = random.Random(name)
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", [rnd.random() for _ in me.polygons])
    for mat in MATS:
        me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    obj["height"] = max(v.co.z for v in me.vertices)
    C.link(obj)  # at the kit's root: no parent
    return obj, shift


# --- pieces --------------------------------------------------------------------------------------------


def vein_wall() -> bpy.types.Object:
    """The rich vein: the greybox's seven big smoky quartz columns (2.8-6.4 m) on its arc, leaning back into the
    rock and fanning out toward the ends, medium columns bursting out between them, small ones along the shelf's
    lip pointing at the way in; all breaking out of a rock shelf that is low and stepped in front and rises behind
    the crystals, tapering into boulders at the arc's ends; joints and chips in the rock."""
    global WALL_ORIGIN
    rnd = random.Random(7)
    s = SINK["Vein_wall"]
    crystals, rock = [], []

    def column(th, rad, z, r, length, tilt, direction, broken=False) -> Matrix:
        bm = quartz(rnd, r, length, flat=rnd.uniform(0.82, 0.95), broken=broken)
        m = T(arc(th, rad, z), lean(direction, tilt) @ rz(rnd.uniform(0, 60)))
        crystals.append(place(bm, m))
        return m

    # Big columns: (angle on the arc, top height, radius); the greybox's heights.
    big = [(-63, 3.2, 0.6), (-42, 4.6, 0.78), (-21, 5.8, 0.88), (0, 6.4, 0.98), (21, 5.2, 0.85), (42, 4.2, 0.74)]
    big.append((63, 2.8, 0.58))
    for i, (th, h, r) in enumerate(big):
        th += rnd.uniform(-2, 2)
        tilt = 6 + abs(th) * 0.16 + rnd.uniform(-2, 2)
        direction = outward(th) + along(th) * (th / 63) * 0.9 + along(th) * rnd.uniform(-0.25, 0.25)
        length = (h + s) / math.cos(math.radians(tilt))
        m = column(th, ARC_R + 0.2, -s, r, length, tilt, direction, i in (2, 5))
        # One or two smaller crystals sprouting from its flank partway up, splaying out (breaks up the silhouette).
        for _ in range(rnd.choice((1, 2))):
            d = rz(rnd.uniform(-90, 90)) @ -outward(th)  # mostly toward the way in
            p = m @ Vector((0, 0, length * rnd.uniform(0.35, 0.6))) + d * r * 0.55
            bm = quartz(rnd, r * rnd.uniform(0.25, 0.35), r * rnd.uniform(1.5, 2.2))
            crystals.append(place(bm, T(p, lean(d, rnd.uniform(40, 58)) @ rz(rnd.uniform(0, 60)))))
    # Between two big ones: a slimmer column fanning out sideways, its foot a little in front.
    for (t0, h0, r0), (t1, h1, r1) in itertools.pairwise(big):
        th = (t0 + t1) / 2 + rnd.uniform(-3, 3)
        side = math.copysign(1.0, th) if abs(th) > 8 else rnd.choice((-1.0, 1.0))
        direction = outward(th) * 0.5 + along(th) * side
        tilt = rnd.uniform(14, 24)
        h = min(h0, h1) * rnd.uniform(0.55, 0.7)
        column(th, ARC_R - 0.1, -0.2, (r0 + r1) / 2 * 0.6, h / math.cos(math.radians(tilt)), tilt, direction)
    # Medium columns bursting out at the big ones' feet: out to the sides, and some toward the way in.
    for th, h, r in big:
        for side in (-1, 1):
            t2 = th + side * rnd.uniform(4, 8)
            fwd = (side > 0) == (th <= 0) and abs(th) < 55
            length = rnd.uniform(1.4, 2.2) if fwd else rnd.uniform(2.0, 3.0)
            d2 = -outward(t2) + along(t2) * side * 0.5 if fwd else outward(t2) * 0.3 + along(t2) * side
            tilt2 = rnd.uniform(20, 30) if fwd else rnd.uniform(28, 44)
            rad, z = ARC_R + (-0.35 if fwd else 0.25), 0.3 + rnd.uniform(0, 0.3)
            column(t2, rad, z, r * rnd.uniform(0.4, 0.55), length, tilt2, d2, rnd.random() < 0.25)
    # Small columns along the shelf's front lip, pointing up and toward the way in.
    for k in range(15):
        th = -64 + k * (128 / 14) + rnd.uniform(-2.5, 2.5)
        d = -outward(th) + along(th) * rnd.uniform(-0.8, 0.8)
        rad = 5.45 + rnd.uniform(0, 0.3)
        z = rnd.uniform(0.2, 0.5) * (1 - abs(th) / 120)
        column(th, rad, z, rnd.uniform(0.11, 0.2), rnd.uniform(0.5, 1.2), rnd.uniform(25, 50), d, rnd.random() < 0.2)
    # Rock shelf: a stepped front ledge sloping toward the way in and a higher back row, lower toward the ends.
    for k in range(12):
        th = -66 + k * (132 / 11) + rnd.uniform(-2, 2)
        end = abs(th) / 66
        top = (2.1 - 1.2 * end**2) * rnd.uniform(0.8, 1.1)
        size = (rnd.uniform(1.8, 2.3), 1.6, top + s + 0.1)
        m = T(arc(th, 6.9, (top - s - 0.1) / 2), rz(th + rnd.uniform(-8, 8)))
        bm = chunk(rnd, size, 2, m, keep=(0.8, 0.93), jitter=0.07, extra=6)
        cut(bm, -outward(th) * 0.8 + Vector((0, 0, 1)) + along(th) * rnd.uniform(-0.3, 0.3), rnd.uniform(0.7, 0.82))
        rock.append(bm)
    for k in range(14):
        th = -66 + k * (132 / 13) + rnd.uniform(-2, 2)
        end = abs(th) / 66
        top = (0.85 - 0.35 * end) * rnd.uniform(0.7, 1.15)
        size = (rnd.uniform(1.2, 1.7), 1.2, top + s + 0.1)
        m = T(arc(th, 5.95, (top - s - 0.1) / 2), rz(th + rnd.uniform(-10, 10)))
        bm = chunk(rnd, size, 2, m, keep=(0.75, 0.9), jitter=0.12, extra=5)
        cut(bm, -outward(th) + Vector((0, 0, 1.2)) + along(th) * rnd.uniform(-0.4, 0.4), rnd.uniform(0.62, 0.78))
        rock.append(bm)
    for th in (-71, 71):  # boulders at the arc's ends
        for j in range(2):
            t = th - math.copysign(j * 7, th)
            size = (rnd.uniform(1.0, 1.3), rnd.uniform(0.9, 1.1), rnd.uniform(0.6, 0.9))
            m = T(arc(t, 6.3 + j * 0.6, size[2] * 0.3 - 0.1), rand_rot(rnd, 12))
            rock.append(chunk(rnd, size, 4, m, keep=(0.72, 0.9), jitter=0.16))
    cutters = []
    for _ in range(7):  # vertical joints in the shelf's front
        th = rnd.uniform(-60, 60)
        rot = rz(th) @ ry(90 + rnd.uniform(-12, 12))
        cutters.append(crack_cutter(rnd, arc(th, 5.4, rnd.uniform(0.2, 0.6)), 1.2, 1.4, 0.07, rot))
    for _ in range(6):
        th = rnd.uniform(-65, 65)
        target = rock[rnd.randrange(12)]
        cutters.append(chip_cutter(rnd, target, -outward(th) + Vector((0, 0, 0.8)), rnd.uniform(0.35, 0.55)))
    bm = solid("Vein_wall", crystals, rock, cutters)
    obj, shift = finish(bm, "Vein_wall")
    WALL_ORIGIN = -shift
    print("WALL_ORIGIN (part frame, Blender)", tuple(round(c, 3) for c in WALL_ORIGIN))
    return obj


def cluster(name: str, seed: int, base: tuple, specs: list) -> bpy.types.Object:
    """A loose crystal cluster: a rock knob of `base` size with smoky quartz columns breaking out of it; `specs`
    are (length, radius, lean, azimuth, offset x, offset y, broken)."""
    rnd = random.Random(seed)
    s = SINK[name]
    rock = [chunk(rnd, (base[0], base[1], base[2] + s), 4, T((0, 0, (base[2] - s) / 2), rz(rnd.uniform(0, 90))))]
    rock.append(
        chunk(rnd, (base[0] * 0.6, base[1] * 0.5, base[2] * 0.6 + s), 3, T((base[0] * 0.4, -base[1] * 0.35, -s / 2)))
    )
    crystals = []
    for length, r, tilt, az, x, y, broken in specs:
        d = Vector((math.cos(math.radians(az)), math.sin(math.radians(az)), 0))
        bm = quartz(rnd, r, length + s, broken=broken)
        crystals.append(place(bm, T((x, y, -s), lean(d, tilt) @ rz(rnd.uniform(0, 60)))))
    obj, _shift = finish(solid(name, crystals, rock), name)
    return obj


def vein_shards() -> bpy.types.Object:
    """Fallen broken crystal: lengths of snapped-off columns lying on the ground, one leaning on another, small
    splinters and a few rock fragments, about 2.6 x 2 m, under 0.45 m high."""
    rnd = random.Random(41)
    pieces, spots = [], []
    specs = [(0.2, 1.2), (0.17, 0.95), (0.15, 0.8), (0.13, 0.7), (0.12, 0.6), (0.1, 0.5), (0.09, 0.4)]
    specs += [(0.07, 0.32)] * 4
    for r, length in specs:
        for _ in range(60):
            p = Vector((rnd.uniform(-1.2, 1.2), rnd.uniform(-0.9, 0.9), 0))
            if all((p - q).length > (length + ql) * 0.4 for q, ql in spots):
                break
        spots.append((p, length))
        tilt = rnd.uniform(-8, 8)
        m = T((p.x, p.y, r * 0.75), rz(rnd.uniform(0, 360)) @ ry(tilt))
        pieces.append((prism_piece(rnd, r, length, m), 1.0))
    # One length propped on the biggest, pointing up.
    p0 = spots[0][0]
    m = T((p0.x + 0.25, p0.y + 0.3, 0.2), rz(rnd.uniform(0, 360)) @ ry(-24))
    pieces.append((prism_piece(rnd, 0.11, 0.75, m), 1.0))
    for _ in range(6):
        p = Vector((rnd.uniform(-1.3, 1.3), rnd.uniform(-1.0, 1.0), 0.0))
        sz = rnd.uniform(0.12, 0.28)
        pieces.append((chunk(rnd, (sz, sz * 0.8, sz * 0.6), 2, T((p.x, p.y, sz * 0.15), rand_rot(rnd, 25))), 0.0))
    obj, _shift = finish(shells("Vein_shards", pieces), "Vein_shards")
    return obj


BUILDERS = {
    "Vein_wall": vein_wall,
    "Vein_cluster_a": lambda: cluster(
        "Vein_cluster_a",
        13,
        (1.2, 1.0, 0.45),
        [
            (1.9, 0.26, 8, 30, 0.0, 0.05, False),
            (1.4, 0.2, 24, 150, -0.18, 0.12, False),
            (1.1, 0.17, 30, -40, 0.2, -0.12, True),
            (0.8, 0.14, 42, 250, -0.1, -0.22, False),
            (0.55, 0.1, 55, 100, 0.05, 0.3, False),
        ],
    ),
    "Vein_cluster_b": lambda: cluster(
        "Vein_cluster_b",
        27,
        (0.9, 0.75, 0.3),
        [
            (1.15, 0.2, 18, 200, 0.0, 0.0, True),
            (0.9, 0.15, 36, 20, 0.15, 0.05, False),
            (0.6, 0.12, 50, 290, -0.05, -0.18, False),
            (0.45, 0.09, 58, 120, -0.18, 0.15, False),
        ],
    ),
    "Vein_shards": vein_shards,
}


# --- materials -----------------------------------------------------------------------------------------


class Mat:
    """Node helpers around one procedural material."""

    def __init__(self, name: str):
        self.mat, self.nt, self.bsdf = C._new_material(name)
        self.geo = self.nt.nodes.new("ShaderNodeNewGeometry")
        self.obj = self.nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]

    def math(self, op, a, b=None, c=None, clamp=False):
        return C._math(self.nt, op, a, b, c, clamp)

    def noise(self, scale, detail=4.0, rough=0.6, vector=None):
        return C._noise(self.nt, scale, detail, rough, vector=vector or self.obj).outputs["Fac"]

    def ramp(self, a, b, src):
        return C._ramp(self.nt, a, b, src)

    def mix(self, fac, a, b):
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b):
        return C._mix_float(self.nt, fac, a, b)

    def scale(self, col, fac):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = "SCALE"
        self.nt.links.new(col, n.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, n.inputs["Scale"])
        else:
            n.inputs["Scale"].default_value = fac
        return n.outputs[0]

    def facet(self):
        n = self.nt.nodes.new("ShaderNodeAttribute")
        n.attribute_type = "GEOMETRY"
        n.attribute_name = "facet"
        return n.outputs["Fac"]

    def up(self):
        """World Z of the shading normal (1 on faces looking up)."""
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.geo.outputs["Normal"], sep.inputs["Vector"])
        return sep.outputs["Z"]

    def z(self):
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.obj, sep.inputs["Vector"])
        return sep.outputs["Z"]

    def cavity(self, distance: float):
        ao = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = distance
        ao.samples = 16
        return ao.outputs["AO"]

    def warped(self, scale: float, amount: float):
        warp = C._noise(self.nt, scale, 3.0, 0.5, vector=self.obj)
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = "MULTIPLY_ADD"
        self.nt.links.new(warp.outputs["Color"], n.inputs[0])
        n.inputs[1].default_value = (amount, amount, amount)
        self.nt.links.new(self.obj, n.inputs[2])
        return n.outputs[0]

    def out(self, color, rough, height, strength: float, distance: float) -> bpy.types.Material:
        self.nt.links.new(color, self.bsdf.inputs["Base Color"])
        if isinstance(rough, bpy.types.NodeSocket):
            self.nt.links.new(rough, self.bsdf.inputs["Roughness"])
        else:
            self.bsdf.inputs["Roughness"].default_value = rough
        self.bsdf.inputs["Metallic"].default_value = 0.0
        C._bump(self.nt, self.bsdf, height, strength, distance)
        return self.mat


def mat_rock() -> bpy.types.Material:
    """Neutral grey-brown fractured rock: per-facet tone, faint strata, lighter chipped ridges, dark cracks and
    cavities, a little dust on top (low contrast, large scale: calm from the game camera); rough."""
    m = Mat("VeinRock")
    warped = m.warped(1.2, 0.35)
    breakup = m.noise(2.0, 4.0, 0.55)
    crack_big = m.math("MULTIPLY", C._voronoi_lines(m.nt, warped, 0.8, 0.028), m.ramp(0.45, 0.6, breakup))
    crack_fine = m.math(
        "MULTIPLY", C._voronoi_lines(m.nt, warped, 2.6, 0.02), m.math("MULTIPLY", m.ramp(0.55, 0.7, breakup), 0.5)
    )
    crack = m.math("MAXIMUM", crack_big, crack_fine)
    tone = m.noise(0.6, 5.0, 0.6)
    base = m.mix(m.ramp(0.3, 0.72, tone), (0.05, 0.046, 0.041), (0.1, 0.095, 0.088))
    base = m.scale(base, m.math("MULTIPLY_ADD", m.facet(), 0.3, 0.85))
    wave = m.nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 0.9
    wave.inputs["Distortion"].default_value = 5.0
    wave.inputs["Detail"].default_value = 3.0
    m.nt.links.new(m.obj, wave.inputs["Vector"])
    base = m.scale(base, m.math("MULTIPLY_ADD", wave.outputs["Fac"], 0.18, 0.9))
    grain = m.noise(30.0, 4.0, 0.7)
    base = m.scale(base, m.math("MULTIPLY_ADD", grain, 0.25, 0.88))
    edge = m.ramp(0.015, 0.09, C._bevel_edge(m.nt, 0.04, m.geo))
    edge = m.math("MULTIPLY", edge, m.ramp(0.3, 0.6, m.noise(7.0, 3.0, 0.6)))
    col = m.mix(edge, base, m.scale(base, 1.5))
    cavity = m.ramp(0.25, 0.95, m.cavity(0.4))
    col = m.mix(m.math("SUBTRACT", 1.0, cavity, clamp=True), col, (0.012, 0.011, 0.01))
    col = m.mix(crack, col, (0.01, 0.009, 0.008))
    dust = m.math("MULTIPLY", m.ramp(0.35, 0.8, m.up()), m.ramp(0.35, 0.65, m.noise(2.5, 5.0, 0.6)))
    dust = m.math("MULTIPLY", dust, 0.6)
    col = m.mix(dust, col, m.mix(grain, (0.12, 0.112, 0.1), (0.16, 0.15, 0.135)))
    rough = m.mixf(tone, 0.82, 0.93)
    rough = m.mixf(edge, rough, 0.74)
    rough = m.mixf(dust, rough, 0.95)
    lumps = m.nt.nodes.new("ShaderNodeTexVoronoi")
    lumps.feature = "SMOOTH_F1"
    lumps.inputs["Scale"].default_value = 2.5
    m.nt.links.new(warped, lumps.inputs["Vector"])
    height = m.math("MULTIPLY", lumps.outputs["Distance"], 0.5)
    height = m.math("ADD", height, m.math("MULTIPLY", grain, 0.2))
    height = m.math("SUBTRACT", height, m.math("MULTIPLY", crack, 0.7))
    return m.out(col, rough, height, 0.5, 0.03)


def mat_crystal() -> bpy.types.Material:
    """Dark smoky quartz (opaque, never glowing): near-black brown-grey in the depth of a face, smoky clouds, each
    face its own tone, paler toward the faces' edges and pale cold grey on the sharp rims, faint fracture planes
    inside, cloudier and dustier toward the foot; glossy (the sky gives it a faint cold sheen), dull where dusty."""
    m = Mat("VeinCrystal")
    warped = m.warped(1.0, 0.4)
    facet = m.facet()
    smoke = m.noise(1.3, 4.0, 0.6)
    core = m.mix(m.ramp(0.35, 0.68, smoke), (0.014, 0.012, 0.012), (0.04, 0.035, 0.034))
    core = m.scale(core, m.math("MULTIPLY_ADD", facet, 0.6, 0.7))
    near_edge = m.ramp(0.02, 0.4, C._bevel_edge(m.nt, 0.06, m.geo))
    rim = m.ramp(0.02, 0.16, C._bevel_edge(m.nt, 0.012, m.geo))
    col = m.mix(m.math("MULTIPLY", near_edge, 0.5), core, (0.07, 0.068, 0.074))
    inner = m.math(
        "MULTIPLY",
        C._voronoi_lines(m.nt, warped, 1.6, 0.01),
        m.ramp(0.45, 0.65, m.noise(2.5, 2.0)),
    )
    col = m.mix(m.math("MULTIPLY", inner, 0.45), col, (0.1, 0.098, 0.102))
    col = m.mix(m.math("MULTIPLY", rim, 0.6), col, (0.17, 0.175, 0.19))
    foot = m.ramp(1.4, 0.0, m.z())  # cloudier toward the foot (object Z)
    col = m.mix(m.math("MULTIPLY", foot, 0.5), col, (0.07, 0.064, 0.058))
    dust = m.math("MULTIPLY", m.ramp(0.7, 0.95, m.up()), m.ramp(0.5, 0.75, m.noise(3.0, 5.0, 0.65)))
    dust = m.math("MULTIPLY", dust, 0.35)
    col = m.mix(dust, col, (0.1, 0.095, 0.086))
    rough = m.mixf(m.noise(20.0, 3.0, 0.6), 0.12, 0.22)
    rough = m.mixf(m.math("MULTIPLY", foot, 0.6), rough, 0.4)
    rough = m.mixf(dust, rough, 0.75)
    height = m.math("MULTIPLY", smoke, 0.04)
    height = m.math("SUBTRACT", height, m.math("MULTIPLY", inner, 0.01))
    return m.out(col, rough, height, 0.3, 0.02)


# --- previews and layout ---------------------------------------------------------------------------------

# The part's layout (Godot: position x, y, z; rotation y in degrees; scale). The wall goes where its origin sits in
# the part's frame (WALL_ORIGIN), unrotated; filled in by layout().
SIDE_LAYOUT = [
    ("Vein_cluster_a", (-5.7, 0.0, 0.1), 20.0, 1.0),
    ("Vein_cluster_b", (5.5, 0.0, -0.3), -35.0, 1.15),
    ("Vein_shards", (2.0, 0.0, 4.6), 30.0, 1.0),
    ("Vein_shards", (-1.6, 0.0, 4.9), 200.0, 0.85),
]


def layout() -> list:
    o = WALL_ORIGIN
    return [("Vein_wall", (round(o.x, 3), 0.0, round(-o.y, 3)), 0.0, 1.0), *SIDE_LAYOUT]


def godot_to_blender(p) -> Vector:
    return Vector((p[0], -p[2], p[1]))


def setup_preview() -> None:
    """The shared preview scene (studio lights for the pieces) without its placeholder ore and pebbles."""
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in PIECES]


def render_piece(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The piece alone at the origin, its front toward the camera (the wall turned around), the scale figure
    beside it; "back" looks at its back."""
    obj = bpy.data.objects[name]
    for o in kit_objects():
        o.hide_render = o is not obj
    obj.location = (0, 0, 0)
    turn = math.pi if name in FRONT_Y else 0.0
    dx, dy, dz = obj.dimensions
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # screen right in the iso view
    fig.location = side * (max(dx, dy) / 2 + 0.55)
    w = max(dx, dy, dz * 1.1) * 1.3 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.5, dz * 0.42)))
    out = []
    for view in views:
        obj.rotation_euler = (0, 0, turn + (math.pi if view == "back" else 0.0))
        path = OUT / f"{prefix}{name}_{view}.png"
        zoom = w / (9.9 if view in ("iso", "back") else 6.3)
        C.render(path, view="iso" if view == "back" else view, samples=samples, size=size, target=target, zoom=zoom)
        out.append(path)
    obj.rotation_euler = (0, 0, 0)
    for o in kit_objects():
        o.hide_render = False
    return out


def ore_placeholder(name: str, at: Vector, seed: int) -> list:
    """Glowing violet crystals within 1.1 m of an ore marker (stand-in for the game's rarest ore)."""
    rnd = random.Random(seed)
    mat = bpy.data.materials.get("PreviewOre") or C.mat_emissive("PreviewOre", (0.55, 0.25, 1.0), 6.0)
    objs = []
    for i in range(7):
        a = i / 7 * math.tau + rnd.uniform(-0.3, 0.3)
        r = rnd.uniform(0.0, 0.8) if i else 0.0
        h = rnd.uniform(0.6, 1.2) if i else 1.4
        me = bpy.data.meshes.new(f"{name}_{i}")
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=rnd.uniform(0.1, 0.17), radius2=0.0, depth=h)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(f"{name}_{i}", me)
        C.link(obj, None, "Preview")
        d = Vector((math.cos(a), math.sin(a), 0))
        obj.location = at + d * r + Vector((0, 0, h * 0.4))
        obj.rotation_euler = (-d.y * 0.4, d.x * 0.4, 0)
        C.assign(obj, mat)
        objs.append(obj)
    return objs


def ring(name: str, radius: float, color, z: float = 0.03) -> bpy.types.Object:
    """A thin ring on the ground (prop_radius, footprint)."""
    n, w = 160, 0.05
    verts = [
        (math.cos(i / n * math.tau) * (radius + s * w), math.sin(i / n * math.tau) * (radius + s * w), z)
        for i in range(n)
        for s in (-1, 1)
    ]
    faces = [(2 * i, 2 * ((i + 1) % n), 2 * ((i + 1) % n) + 1, 2 * i + 1) for i in range(n)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, me)
    C.link(obj, None, "Preview")
    C.assign(obj, C.mat_emissive(name + "Mat", color, 1.5))
    return obj


def render_layout(prefix: str, samples: int, size: int) -> list:
    """The part as the game lays it out (Godot transforms converted), the greybox's ore markers with placeholder
    ore, the prop_radius ring and a 1.89 m pole, from the game's angle (about 50 degrees down, 45 degrees around)
    in a dim, cool light (a weak low sun and a little sky); front: the camera on the way-in side, back: behind."""
    for o in kit_objects():
        o.hide_render = True
    hidden = []
    for o in C.collection("Preview").objects:
        if o.type == "LIGHT" or o.name.startswith("PreviewFigure") or o.parent is not None:
            o.hide_render = True
            hidden.append(o)
    ground = bpy.data.objects["PreviewGround"]
    ground.scale = (3, 3, 1)
    ground_mix = next(n for n in ground.active_material.node_tree.nodes if n.bl_idname == "ShaderNodeMix")
    old_ground = tuple(ground_mix.inputs[6].default_value), tuple(ground_mix.inputs[7].default_value)
    ground_mix.inputs[6].default_value = (0.07, 0.066, 0.06, 1.0)  # a mid grey-brown ground, as the biomes'
    ground_mix.inputs[7].default_value = (0.12, 0.112, 0.1, 1.0)
    added = []
    for i, (name, pos, rot, scale) in enumerate(layout()):
        d = bpy.data.objects[name].copy()  # linked duplicate
        C.collection("Preview").objects.link(d)
        d.hide_render = False
        d.location = godot_to_blender(pos)
        d.rotation_euler = (0, 0, math.radians(rot))
        d.scale = (scale,) * 3
        d.name = f"Layout_{i}_{name}"
        added.append(d)
    for i, (x, z) in enumerate(ORE_MARKERS):
        added += ore_placeholder(f"PreviewOre{i}", godot_to_blender((x, 0, z)), 50 + i)
    added.append(ring("PreviewPropRadius", PROP_RADIUS, (0.5, 0.5, 0.5)))
    added.append(ring("PreviewFootprint", FOOTPRINT, (0.15, 0.15, 0.15)))
    me = bpy.data.meshes.new("PreviewPole")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.08, radius2=0.08, depth=1.89)
    bm.to_mesh(me)
    bm.free()
    pole = bpy.data.objects.new("PreviewPole", me)
    C.link(pole, None, "Preview")
    pole.location = (1.2, 1.0, 0.945)
    C.assign(pole, C.mat_emissive("PreviewPoleMat", (0.9, 0.5, 0.1), 0.6))
    added.append(pole)
    sun_data = bpy.data.lights.new("LayoutSun", "SUN")
    sun_data.energy = 2.2
    sun_data.color = (0.78, 0.86, 1.0)
    sun_data.angle = math.radians(2)
    sun = bpy.data.objects.new("LayoutSun", sun_data)
    C.link(sun, None, "Preview")
    sun.rotation_euler = (math.radians(66), 0, math.radians(-150))  # low, from the left
    added.append(sun)
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    old_bg = tuple(bg.inputs["Color"].default_value), bg.inputs["Strength"].default_value
    bg.inputs["Color"].default_value = (0.05, 0.06, 0.08, 1.0)
    bg.inputs["Strength"].default_value = 0.6
    out = []
    center = Vector((0, -2.8, 1.5))
    for view, azimuth in (("front", 45.0), ("back", 225.0)):
        a = math.radians(azimuth)
        pitch = math.radians(50)
        dist = 27.0
        loc = center + Vector((math.cos(a) * math.cos(pitch), math.sin(a) * math.cos(pitch), math.sin(pitch))) * dist
        path = OUT / f"{prefix}layout_{view}.png"
        C.render_from(path, loc, center, lens=42.0, samples=samples, size=size)
        out.append(path)
    bg.inputs["Color"].default_value = (*old_bg[0][:3], 1.0)
    bg.inputs["Strength"].default_value = old_bg[1]
    ground.scale = (1, 1, 1)
    ground_mix.inputs[6].default_value, ground_mix.inputs[7].default_value = old_ground
    for o in added:
        bpy.data.objects.remove(o)
    for o in hidden:
        o.hide_render = False
    for o in kit_objects():
        o.hide_render = False
    return out


def apply_bake_layout(gap: float = 3.0) -> None:
    """Saved .blend layout: every piece unrotated in one row along X with `gap` m between them, so the AO bake
    never picks up a neighbor. The bake zeroes the locations before the export."""
    x = 0.0
    for name in PIECES:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


# --- main -------------------------------------------------------------------------------------------


def build() -> None:
    global MATS
    MATS = [mat_rock(), mat_crystal()]
    work = bpy.data.collections.new("Work")
    bpy.context.scene.collection.children.link(work)
    for name in PIECES:
        BUILDERS[name]()
    for coll in [work, *work.children_recursive]:  # drop the boolean operands
        for obj in list(coll.objects):
            me = obj.data
            bpy.data.objects.remove(obj)
            if me.users == 0:
                bpy.data.meshes.remove(me)
    for coll in [*work.children_recursive, work]:
        bpy.data.collections.remove(coll)


def report() -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for name in PIECES:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        xs, ys, zs = ([v.co[i] for v in me.vertices] for i in range(3))
        crystal = sum(1 for p in me.polygons if p.material_index == 1) / max(len(me.polygons), 1)
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(d, 2) for d in obj.dimensions)}"
            f" x=({min(xs):.2f}, {max(xs):.2f}) y=({min(ys):.2f}, {max(ys):.2f}) z=({min(zs):.2f}, {max(zs):.2f})"
            f" crystal_faces={crystal:.2f} manifold={_is_manifold(obj)}"
        )
        obj.evaluated_get(dg).to_mesh_clear()
    print("STATS", C.stats())
    print("LAYOUT", layout())


def _is_manifold(obj: bpy.types.Object) -> bool:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = [e for e in bm.edges if not e.is_manifold]
    bm.free()
    return not bad


def main() -> None:
    C.reset(ASSET)
    build()
    report()
    setup_preview()
    if MODE == "final":
        sheet = render_layout("final_", 64, 1024)
        for name in PIECES:
            sheet += render_piece(name, "final_", ("iso", "hero", "back"), 32, 640)
        C.contact_sheet(sheet, OUT / "sheet.png", tile=512, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "vein_procedural.blend")
        return
    wip = OUT / "wip"
    for view in VIEWS:
        if view == "pieces":
            for name in PIECES:
                render_piece(name, f"wip/{TAG}_", ("iso", "hero"), 20, 512)
        elif view == "layout":
            render_layout(f"wip/{TAG}_", 24, 900)
        elif view in BUILDERS:
            render_piece(view, f"wip/{TAG}_", ("iso", "hero", "back"), 24, 640)
        elif view == "sheet":
            names = sorted(p for p in wip.glob(f"{TAG}_*.png") if not p.name.endswith("sheet.png"))
            C.contact_sheet(names, wip / f"{TAG}_sheet.png", tile=384, background=0.02)
        elif view == "save":
            apply_bake_layout()
            C.save_blend(OUT / "vein_procedural.blend")
            return


if __name__ == "__main__":
    main()
