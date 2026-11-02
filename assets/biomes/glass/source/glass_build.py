"""Glass plains scatter kit: glass spire clusters for the shard gardens, the shard fences' spike, slivers, splinter
patches for the shards hazard, half-vitrified boulders, a fulgurite, glass chunks and slag, and cliff chunks of rock
fused in layers (concepts: local/concepts/batch11/glass, glass_props).

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/glass/source/glass_build.py wip g1                  # kit iso + hero
    tools/blender.sh assets/biomes/glass/source/glass_build.py wip g1 Spire_a,scatter
    tools/blender.sh assets/biomes/glass/source/glass_build.py final

Everything it writes goes to tmp/assets/glass/: "wip <tag> [views]" renders quick previews into wip/<tag>_*.png
(views: kit_iso, kit_hero, scatter, variants, back, sheet, save, or a variant name); "final" renders the kit, every
variant (iso + hero), the cliffs' backs and a game-distance scatter, writes the contact sheet sheet.png and saves
the procedural glass_procedural.blend that glass_bake.py turns into the game asset. In the .blend the variants
stand unrotated in a row along X, 3 m apart (bake layout, so the AO bake doesn't pick up neighbors); the bake stage
zeroes their locations before the export.

Game contract (game/locations/scatter_type.gd): a ScatterType draws ONE mesh many times (random scale, tilt, sink),
so every variant is one mesh object with one material ("Glass"), its origin at the ground contact point (bottom
center), standing on z = 0 with extra geometry below ground (SINK) so tilted or sunk instances don't float. Cliffs
face -Y (toward the camera side) with a flat back at y = +CLIFF_BACK. Budgets (TBD (playtest)): the fence spike
<= ~150 triangles, the sliver <= ~100, the splinter patch <= ~400, small pieces and boulders <= ~800, the spire
clusters and cliffs <= ~2.5k.

Modeling: convex pieces (convex hulls of jittered points, shaved by plane cuts into sharp facets; rounded melt
skins over them) united with a boolean (manifold solver), minus thin cutters for cracks, chips and burst bubbles;
loose pieces (splinters, chunks, the fulgurite's tubes) stay separate shells of one mesh. Glass reads as glass
without transmission (the game imports none): opaque, glossy but not a mirror, smoky in the middle of a facet, paler
toward its edges and the top, a faint teal glow toward the edges. Which faces are glass is a face attribute
"glass" (1 glass, 0 stone, between: patchy): every piece and cutter carries its value and the booleans pass it on
to the faces they keep. A random per-face "facet" gives every fracture plane its own tone. Both attributes only
feed the procedural material and are dropped after the bake.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "glass"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import common as C
from common import T, rx, ry, rz
from rock_geo import (
    add_boolean,
    box_points,
    cut,
    hull,
    rand_dir,
    rand_rot,
    shave,
    support,
    uv_to_xy,
    work_collection,
)

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "g0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit_iso", "kit_hero"]

ASSET = "Glass"
# Geometry kept below z = 0 per kind (m), so random tilt / sink in the game never shows the bottom.
SINK = {
    "Spire": 0.3,
    "Spike": 0.2,
    "Sliver": 0.1,
    "Splinters": 0.03,
    "Boulder": 0.18,
    "Fulgurite": 0.25,
    "Chunks": 0.06,
    "Cliff": 0.45,
}
CLIFF_BACK = 1.0  # cliffs: flat back plane at y = +1 m, rock face toward -Y
SHARP_DEG = 32.0  # edges sharper than this split the shading (facets, fracture ridges); softer ones shade smooth
VARIANTS = [
    "Spire_a",
    "Spire_b",
    "Spike_a",
    "Sliver_a",
    "Splinters_a",
    "Boulder_a",
    "Boulder_b",
    "Fulgurite_a",
    "Chunks_a",
    "Cliff_a",
    "Cliff_b",
]

# --- math helpers (T, rx/ry/rz: common) ---------------------------------------------------------------


def lean(direction: Vector, deg: float) -> Matrix:
    """Rotation tipping +Z by `deg` degrees toward the horizontal `direction`."""
    axis = Vector((0, 0, 1)).cross(Vector((direction.x, direction.y, 0)))
    if axis.length < 1e-6:
        return Matrix.Identity(3)
    return Matrix.Rotation(math.radians(deg), 3, axis.normalized())


# --- convex pieces -----------------------------------------------------------------------------------


def place(bm: bmesh.types.BMesh, m: Matrix) -> bmesh.types.BMesh:
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    bm.normal_update()
    return bm


def chunk(
    rnd: random.Random, size, cuts: int = 3, m: Matrix | None = None, keep=(0.72, 0.9), **kw
) -> bmesh.types.BMesh:
    bm = hull(box_points(rnd, size, **kw))
    shave(bm, rnd, cuts, keep)
    return place(bm, m) if m is not None else bm


def blob(rnd: random.Random, size, lumps: float = 0.12, subdivisions: int = 2, m: Matrix | None = None):
    """Rounded lump: an icosphere scaled to `size`, its radius rippled by a few random waves (melt, slag)."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
    waves = [(rand_dir(rnd) * rnd.uniform(1.5, 3.5), rnd.uniform(0, math.tau)) for _ in range(4)]
    for v in bm.verts:
        d = v.co.normalized()
        r = 1.0 + sum(lumps * math.cos(d.dot(w) + ph) for w, ph in waves) / 2
        v.co = Vector((d.x * size[0] / 2, d.y * size[1] / 2, d.z * size[2] / 2)) * r
    bm.normal_update()
    return place(bm, m) if m is not None else bm


def shard(
    rnd: random.Random,
    r: float,
    h: float,
    sides: int = 6,
    flat: float = 0.8,
    taper: float = 0.6,
    tip: float = 0.22,
    cuts: int = 0,
    m: Matrix | None = None,
) -> bmesh.types.BMesh:
    """Glass spike from z = 0 up to its point at h: a `sides`-sided prism (depth `flat` of its width) narrowing to
    `taper` at the shoulder, then a faceted point over the top `tip` share of its height (slightly off-center);
    `cuts` fracture facets shaved off its flanks."""
    a0 = rnd.uniform(0, math.tau)
    shoulder = h * (1.0 - tip)
    pts = []
    for i in range(sides):
        a = a0 + (i + rnd.uniform(-0.2, 0.2)) / sides * math.tau
        k = 1 + rnd.uniform(-0.12, 0.12)
        x, y = math.cos(a) * r * k, math.sin(a) * r * k * flat
        pts.append(Vector((x, y, 0.0)))
        t = taper * (1 + rnd.uniform(-0.1, 0.1))
        pts.append(Vector((x * t, y * t, shoulder * (1 + rnd.uniform(-0.05, 0.05)))))
    pts.append(Vector((rnd.uniform(-0.15, 0.15) * r, rnd.uniform(-0.15, 0.15) * r * flat, h)))
    bm = hull(pts)
    for _ in range(cuts):
        a = rnd.uniform(0, math.tau)
        cut(bm, (math.cos(a), math.sin(a), rnd.uniform(-0.1, 0.4)), rnd.uniform(0.8, 0.92))
    return place(bm, m) if m is not None else bm


def chip_cutter(rnd: random.Random, target: bmesh.types.BMesh, direction, size: float) -> bmesh.types.BMesh:
    """A small rotated block centered on the target's outermost point in `direction`: bites a chip out of a ridge."""
    p = support(target, direction)
    return chunk(rnd, (size, size * rnd.uniform(0.7, 1.1), size * rnd.uniform(0.6, 1.0)), 1, T(p, rand_rot(rnd, 60)))


def crack_cutter(
    rnd: random.Random, center, length: float, depth: float, width: float = 0.05, rot: Matrix | None = None
) -> bmesh.types.BMesh:
    """Thin slab (length along X, depth along Y, width along Z) that notches a crack into a face."""
    pts = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            for cz in (-1, 1):
                w = width * (rnd.uniform(0.4, 1.0) if cy > 0 else rnd.uniform(1.0, 1.8))  # wider at the mouth (-Y)
                pts.append(Vector((cx * length / 2 * rnd.uniform(0.85, 1.0), cy * depth / 2, cz * w / 2)))
    return place(hull(pts), T(center, rot))


def pit_cutter(rnd: random.Random, target: bmesh.types.BMesh, direction, r: float) -> bmesh.types.BMesh:
    """A small rounded lump sunk halfway into the target's surface in `direction`: a burst bubble."""
    p = support(target, direction) - Vector(direction).normalized() * r * 0.35
    return blob(rnd, (2 * r, 2 * r, 2 * r * 0.8), 0.1, 1, T(p, rand_rot(rnd, 90)))


def drip(
    rnd: random.Random, top: Vector, length: float, width: float, out: Vector, slant: float = 0.0
) -> bmesh.types.BMesh:
    """A glass run hanging down a face from `top`: a flat tongue of melt, wide where it leaves the glass above and
    rounded off at its lower end, its crest a little proud of the face along `out` (the face's horizontal outward
    normal); `slant` m back into the face by its end (to hug a face that lies further back)."""
    side = Vector((0, 0, 1)).cross(out).normalized()
    pts = []
    for t, w in ((0.0, 1.0), (0.35, 0.85), (0.65, 0.65), (0.85, 0.45), (0.96, 0.22)):
        z = top.z - t * length
        c = Vector((top.x, top.y, z)) + side * rnd.uniform(-0.08, 0.08) * width * t - out * slant * t
        for s in (-1, 1):
            pts.append(c + side * s * width / 2 * w - out * width * 0.3)
            pts.append(c + side * s * width / 2 * w * 0.7 + out * min(width * 0.12, 0.03))
        pts.append(c + out * min(width * 0.2, 0.045))  # the rounded crest
    pts.append(Vector((top.x, top.y, top.z - length)) - out * (slant + 0.01))
    return hull(pts)


def front_at(trees: list, x: float, z: float) -> float | None:
    """The front-most (-Y) surface point of the pieces at (x, z), by a ray from the camera side."""
    hits = [tree.ray_cast(Vector((x, -10.0, z)), Vector((0, 1, 0)))[0] for tree in trees]
    ys = [h.y for h in hits if h is not None]
    return min(ys) if ys else None


# --- mesh assembly ------------------------------------------------------------------------------------


def bm_to_obj(bm: bmesh.types.BMesh, name: str, coll: str = "Work", glass: float = 0.0) -> bpy.types.Object:
    """A boolean operand: the piece as an object, every face carrying `glass` (the booleans pass it on)."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.attributes.new("glass", "FLOAT", "FACE").data.foreach_set("value", [glass] * len(me.polygons))
    obj = bpy.data.objects.new(name, me)
    C.collection(coll).objects.link(obj)
    return obj


def solid(
    name: str,
    kind: str,
    glass: list,
    stone: list = (),
    cutters: list = (),
    center_y: bool = True,
    back_y: float | None = None,
    glass_cutters: list = (),
) -> bpy.types.Object:
    """Union of the glass and stone pieces minus the cutters, cleaned up, bottom cut flat at -SINK, origin at the
    bottom center; a face is glass when it comes from a glass piece or a glass cutter (a burst bubble in the glass),
    the booleans carry that over. Returns the finished variant."""
    parts = [(bm, 0.0) for bm in stone] + [(bm, 1.0) for bm in glass]
    base = bm_to_obj(parts[0][0], name + "_base", glass=parts[0][1])
    if len(parts) > 1:
        coll = work_collection(name + "_union")
        for i, (bm, g) in enumerate(parts[1:]):
            bm_to_obj(bm, f"{name}_u{i}", coll.name, g)
        add_boolean(base, "UNION", coll)
    subtract = [(bm, 0.0) for bm in cutters] + [(bm, 1.0) for bm in glass_cutters]
    if subtract:
        coll = work_collection(name + "_cut")
        for i, (bm, g) in enumerate(subtract):
            bm_to_obj(bm, f"{name}_c{i}", coll.name, g)
        add_boolean(base, "DIFFERENCE", coll)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    clean(bm, kind, back_y)
    layer = bm.faces.layers.float.get("glass")
    for f in bm.faces:
        if back_y is not None and f.normal.y > 0.99:
            f[layer] = 0.0  # the flat back faces the terrain
        f[layer] = 1.0 if f[layer] > 0.5 else 0.0
    return finish(bm, name, kind, center_y)


def shells(name: str, kind: str, pieces: list) -> bpy.types.Object:
    """Separate closed pieces (no boolean: splinters, chunks, tubes) as one mesh; `pieces` are (bmesh, glass)
    pairs, glass 0..1 for every face of that piece."""
    bm = bmesh.new()
    ranges = []
    for piece, glass in pieces:
        me = bpy.data.meshes.new("tmp")
        piece.to_mesh(me)
        piece.free()
        start = len(bm.faces)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        ranges.append((start, len(bm.faces), glass))
    layer = bm.faces.layers.float.new("glass")
    bm.faces.ensure_lookup_table()
    for start, end, glass in ranges:
        for f in bm.faces[start:end]:
            f[layer] = glass
    cut(bm, (0, 0, -1), at=SINK[kind])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, name, kind, True)


def clean(bm: bmesh.types.BMesh, kind: str, back_y: float | None) -> None:
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.003)
    bmesh.ops.dissolve_degenerate(bm, dist=0.002, edges=bm.edges[:])
    cut(bm, (0, 0, -1), at=SINK[kind])  # flat bottom at z = -SINK (normal points down: keeps what's above)
    if back_y is not None:
        cut(bm, (0, 1, 0), at=back_y)
    # Merge the coplanar triangles the hulls and booleans leave on the big facets (fewer triangles).
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.5), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def finish(bm: bmesh.types.BMesh, name: str, kind: str, center_y: bool) -> bpy.types.Object:
    """Origin at the bottom center (x, y of the bounds' middle), sharp edges split, a random tone per facet."""
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), 0))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), 0))
    shift = -(lo + hi) / 2
    if not center_y:
        shift.y = 0
    bmesh.ops.translate(bm, vec=shift, verts=bm.verts[:])
    sharp = math.radians(SHARP_DEG)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > sharp)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    rnd = random.Random(name)
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", [rnd.random() for _ in me.polygons])
    obj = bpy.data.objects.new(name, me)
    obj["height"] = max(v.co.z for v in me.vertices)  # read by the material (paler tips)
    C.link(obj, ROOT_OBJ)
    C.assign(obj, GLASS)
    return obj


# --- variants ------------------------------------------------------------------------------------------


def spire_cluster(name: str, seed: int, spires: list, foot: int, broken: int) -> bpy.types.Object:
    """Tall, thick faceted glass spires (broad facets that catch the light) leaning out of one root, smaller shards
    splaying around their foot; `spires` are (height, radius, x, y, lean); the `broken` tallest-but-one lose their
    points to a slanted fracture."""
    rnd = random.Random(seed)
    s = SINK["Spire"]
    parts = []
    for i, (h, r, x, y, tilt) in enumerate(spires):
        out = Vector((x, y, 0)) if (x or y) else Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0))
        bm = shard(rnd, r, h + s, sides=rnd.choice((5, 6)), flat=rnd.uniform(0.8, 0.95), taper=0.6, tip=0.22)
        if 0 < i <= broken:
            a = rnd.uniform(0, math.tau)
            cut(bm, (math.cos(a) * 0.8, math.sin(a) * 0.8, 1.0), rnd.uniform(0.72, 0.82))
        parts.append(place(bm, T((x, y, -s), lean(out, tilt) @ rz(rnd.uniform(0, 60)))))
    for k in range(foot):
        a = k / foot * math.tau + rnd.uniform(-0.3, 0.3)
        out = Vector((math.cos(a), math.sin(a), 0))
        h = rnd.uniform(0.4, 0.8)
        bm = shard(rnd, rnd.uniform(0.1, 0.15), h + s, sides=rnd.choice((4, 5)), flat=0.75, taper=0.6, tip=0.35)
        parts.append(place(bm, T(out * rnd.uniform(0.3, 0.5) + Vector((0, 0, -s)), lean(out, rnd.uniform(25, 50)))))
    return solid(name, "Spire", parts)


def spike_a() -> bpy.types.Object:
    """Fence spike: one thick, sharp shard of glass leaning a little, a short side shard fused to its foot."""
    rnd = random.Random(31)
    s = SINK["Spike"]
    blade = shard(rnd, 0.15, 1.3 + s, sides=5, flat=0.75, taper=0.55, tip=0.35, cuts=1)
    blade = place(blade, T((0, 0, -s), ry(6) @ rx(-3)))
    side = shard(rnd, 0.08, 0.5 + s, sides=4, flat=0.8, taper=0.6, tip=0.4)
    side = place(side, T((0.1, 0.03, -s), lean(Vector((1, 0.4, 0)), 26)))
    return solid("Spike_a", "Spike", [blade, side])


def sliver_a() -> bpy.types.Object:
    """A single small glass sliver, leaning, its point snapped off at a slant."""
    rnd = random.Random(41)
    s = SINK["Sliver"]
    bm = shard(rnd, 0.07, 0.58 + s, sides=4, flat=0.5, taper=0.65, tip=0.35)
    cut(bm, (0.5, 0.2, 1.0), 0.9)
    return solid("Sliver_a", "Sliver", [place(bm, T((0, 0, -s), ry(14) @ rz(20)))])


def splinter(rnd: random.Random, length: float, m: Matrix) -> bmesh.types.BMesh:
    """A lying glass splinter: a skewed, flattened double point (an octahedron's eight faces)."""
    w = length * rnd.uniform(0.15, 0.35)
    t = w * rnd.uniform(0.35, 0.6)
    pts = [
        Vector((length / 2 * rnd.uniform(0.7, 1.0), 0, 0)),
        Vector((-length / 2 * rnd.uniform(0.4, 1.0), 0, 0)),
        Vector((rnd.uniform(-0.25, 0.25) * length, w / 2, 0)),
        Vector((rnd.uniform(-0.25, 0.25) * length, -w / 2, 0)),
        Vector((rnd.uniform(-0.2, 0.2) * length, 0, t / 2)),
        Vector((rnd.uniform(-0.2, 0.2) * length, 0, -t / 4)),
    ]
    return place(hull(pts), m)


def splinters_a() -> bpy.types.Object:
    """Hazard patch: a flat litter of sharp glass splinters about 1 m across, a few sticking up out of it."""
    rnd = random.Random(51)
    pieces = []
    for _ in range(38):
        a, r = rnd.uniform(0, math.tau), 0.5 * math.sqrt(rnd.random())
        length = math.exp(rnd.uniform(math.log(0.1), math.log(0.32)))
        m = T((math.cos(a) * r, math.sin(a) * r, 0.0), rz(rnd.uniform(0, 360)) @ rx(rnd.uniform(-12, 12)))
        pieces.append((splinter(rnd, length, m), 1.0))
    for _ in range(5):
        a, r = rnd.uniform(0, math.tau), 0.4 * math.sqrt(rnd.random())
        out = Vector((math.cos(a), math.sin(a), 0))
        bm = shard(rnd, rnd.uniform(0.02, 0.035), rnd.uniform(0.1, 0.16), sides=3, flat=0.6, taper=0.8, tip=0.5)
        pieces.append((place(bm, T(out * r - Vector((0, 0, 0.03)), lean(out, rnd.uniform(15, 40)))), 1.0))
    return shells("Splinters_a", "Splinters", pieces)


def boulder(name: str, seed: int, size: tuple, glaze: float, tilt: float, drips: int, pits: int):
    """Half-vitrified boulder: a jagged stone block (a big one with a smaller one wedged against it) whose upper
    part melted into a thin glossy glass skin with a ragged lip, running down its flanks in tongues that hug the
    stone, pocked by burst bubbles."""
    rnd = random.Random(seed)
    sx, sy, sz = size
    m = T((0, 0, sz * 0.4), rz(rnd.uniform(0, 90)))
    rock = chunk(rnd, size, 8, m, keep=(0.76, 0.92), jitter=0.2, extra=12, bulge=0.2)
    side = chunk(rnd, (sx * 0.55, sy * 0.5, sz * 0.4), 6, T((sx * 0.36, -sy * 0.2, 0.0), rand_rot(rnd, 12)))
    top = max(v.co.z for v in rock.verts)
    trees = [BVHTree.FromBMesh(rock), BVHTree.FromBMesh(side)]
    cap = skin(rock, rnd, 0.022, cuts=1, smooth=0.25)
    a = math.radians(tilt)
    cut(cap, (math.sin(a), 0.0, -math.cos(a)), at=-(top - sz * glaze))
    for _ in range(4):  # a ragged lip: the skin's edge bitten back in places
        cut(cap, rand_dir(rnd, max_z=-0.35), rnd.uniform(0.82, 0.94))
    glass = [cap]
    for i in range(drips):
        ang = i / drips * math.tau + rnd.uniform(-0.3, 0.3)
        out = Vector((math.cos(ang), math.sin(ang), 0))
        edge = support(cap, out - Vector((0, 0, 1.2))) - out * 0.02 + Vector((0, 0, 0.06))
        length, width = rnd.uniform(0.18, 0.4), rnd.uniform(0.14, 0.26)
        low = edge - Vector((0, 0, length * 0.85))
        hits = [tree.ray_cast(low + out * 2.0, -out)[0] for tree in trees]
        hits = [h for h in hits if h is not None]
        if not hits:
            continue
        face = max(hits, key=lambda h: h.dot(out))  # the outermost stone surface at the drip's foot
        glass.append(drip(rnd, edge, length, width, out, (edge - face).dot(out) - 0.005))
    bubbles = [pit_cutter(rnd, cap, rand_dir(rnd, min_z=0.25), rnd.uniform(0.04, 0.08)) for _ in range(pits)]
    chips = [chip_cutter(rnd, rock, (-0.7, -0.5, -0.1), 0.28)]
    return solid(name, "Boulder", glass, [rock, side], chips, glass_cutters=bubbles)


def fulgurite_a() -> bpy.types.Object:
    """Fulgurite: a lumpy tube of fused glass, the track of a flare discharge, rising crooked out of the ground,
    a branch off its side and a stub at its foot; its open mouth shows the glassy hollow inside, the outside is
    crusted with grit in patches."""
    rnd = random.Random(61)
    s = SINK["Fulgurite"]
    pieces = [
        (tube(rnd, [(0, 0, -s), (0.06, 0.02, 0.4), (0.2, 0.05, 0.85), (0.27, 0.14, 1.3)], (0.14, 0.085), 7), 0.55),
        (tube(rnd, [(0.06, 0.02, 0.45), (0.28, -0.1, 0.62), (0.48, -0.14, 0.78)], (0.075, 0.045), 6), 0.55),
        (tube(rnd, [(-0.02, 0.0, -0.1), (-0.17, 0.09, 0.15), (-0.26, 0.14, 0.34)], (0.085, 0.055), 6), 0.55),
    ]
    return shells("Fulgurite_a", "Fulgurite", pieces)


def tube(rnd: random.Random, path: list, radius: tuple, sides: int) -> bmesh.types.BMesh:
    """Lumpy tube along `path` (smoothed, about 8 cm steps), radius from radius[0] to radius[1], closed at its
    start, its end an open mouth: the rim folds inward and down into a short dark hollow."""
    pts = [Vector(p) for p in path]
    steps = []
    for a, b in itertools.pairwise(pts):
        n = max(1, int((b - a).length / 0.08))
        steps += [a.lerp(b, i / n) for i in range(n)]
    steps.append(pts[-1])
    bm = bmesh.new()
    rings = []
    prev_x = Vector((1, 0, 0))
    for i, p in enumerate(steps):
        t = i / (len(steps) - 1)
        d = (steps[min(i + 1, len(steps) - 1)] - steps[max(i - 1, 0)]).normalized()
        x = (prev_x - d * prev_x.dot(d)).normalized()
        prev_x = x
        y = d.cross(x)
        r = (radius[0] + (radius[1] - radius[0]) * t) * rnd.uniform(0.85, 1.2)
        rings.append(
            [
                bm.verts.new(p + (x * math.cos(a) + y * math.sin(a)) * r * rnd.uniform(0.85, 1.15))
                for a in (j / sides * math.tau for j in range(sides))
            ]
        )
    # The mouth: the rim turns inward and down into the hollow.
    end, d = steps[-1], (steps[-1] - steps[-2]).normalized()
    inner_r = radius[1] * 0.55
    for depth in (0.0, 0.12):
        c = end - d * depth
        ring = rings[-1]
        rings.append([bm.verts.new(c + (v.co - end) * inner_r / max((v.co - end).length, 1e-6)) for v in ring])
    for a, b in itertools.pairwise(rings):
        for j in range(sides):
            bm.faces.new((a[j], a[(j + 1) % sides], b[(j + 1) % sides], b[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def chunks_a() -> bpy.types.Object:
    """A cluster of smoky glass chunks (sharp, conchoidal facets) and rounded slag lumps, about 1 m across."""
    rnd = random.Random(71)
    pieces, spots = [], []
    specs = [(0.42, 1.0), (0.34, 0.0), (0.3, 1.0), (0.26, 1.0), (0.24, 0.0), (0.2, 1.0), (0.16, 0.0), (0.13, 1.0)]
    for i, (sz, glass) in enumerate(specs):
        for _ in range(40):  # keep pieces from merging into one blob
            a = rnd.uniform(0, math.tau)
            r = 0.45 * math.sqrt(rnd.random()) * (0.3 if i == 0 else 1.0)
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
            if all((p - q).length > (sz + t) * 0.45 for q, t in spots):
                break
        spots.append((p, sz))
        h = sz * rnd.uniform(0.55, 0.8)
        m = T((p.x, p.y, h * 0.3), rand_rot(rnd, 25))
        if glass:
            bm = chunk(rnd, (sz, sz * rnd.uniform(0.6, 0.9), h), 5, m, keep=(0.6, 0.85), jitter=0.2, extra=3)
        else:
            bm = blob(rnd, (sz, sz * rnd.uniform(0.7, 0.95), h), 0.18, 1, m)
        pieces.append((bm, glass))
    return shells("Chunks_a", "Chunks", pieces)


def strata_cliff(name: str, seed: int, glass_layers: set, top: float, glaze_top: bool) -> bpy.types.Object:
    """Cliff chunk of rock fused in layers: strata of uneven thickness with jagged, set-back fronts, rough stone
    and (the `glass_layers`) smoky glass, the glass ones smoother and a little proud, glass running from their
    underside in drips that hug the stone below; with `glaze_top` a glass skin also drapes over the broken top
    edge and runs down; flat back."""
    rnd = random.Random(seed)
    s = SINK["Cliff"]
    stone, glass, z, layer = [], [], -s, 0
    dip = rnd.uniform(-3, 3)
    while z < top:
        is_glass = layer in glass_layers
        if is_glass:
            th = rnd.uniform(0.24, 0.45)
        else:
            th = 0.85 + s if layer == 0 else (rnd.uniform(0.35, 0.6) if rnd.random() < 0.4 else rnd.uniform(0.7, 1.2))
        last = z + th >= top
        set_back = rnd.uniform(-0.15, 0.15) + 0.08 * layer - (0.06 if is_glass else 0.0)
        cuts_x = sorted(rnd.uniform(-2.2, 2.2) for _ in range(rnd.choice((0, 1, 1, 2))))
        edges = [-3.1, *cuts_x, 3.1]
        layer_parts = []
        for i in range(len(edges) - 1):
            x0 = edges[i] - (0.1 if i else 0)
            x1 = edges[i + 1] + (0.1 if i + 2 < len(edges) else 0)
            front = -1.0 + set_back + rnd.uniform(-0.2, 0.2) * (0.7 if is_glass else 1.0)
            hi = z + th + (rnd.uniform(-0.3, 0.3) if last else 0.0)
            z0 = z - 0.15 if layer else z  # overlap the layer below: no floating strata
            depth = CLIFF_BACK + 0.15 - front
            m = T(((x0 + x1) / 2, front + depth / 2, (z0 + hi) / 2), rz(rnd.uniform(-3, 3)) @ ry(dip))
            bm = chunk(rnd, (x1 - x0, depth, hi - z0), 0, m, jitter=0.03, extra=0)
            for _ in range(rnd.randint(3, 4) if is_glass else rnd.randint(3, 6)):  # jagged front
                cut(bm, (rnd.uniform(-1.0, 1.0), -1.0, rnd.uniform(-0.5, 0.5)), rnd.uniform(0.9, 0.97))
            if last:  # broken top
                for _ in range(2):
                    cut(bm, (rnd.uniform(-1.0, 1.0), rnd.uniform(-0.6, 0.2), 1.0), rnd.uniform(0.8, 0.92))
            if is_glass:  # rounded-off melt edges instead of ledges
                cut(bm, (0.0, -1.0, 1.0), 0.95)
                cut(bm, (0.0, -1.0, -1.0), 0.95)
            else:
                cut(bm, (rnd.uniform(-0.3, 0.3), -1.0, rnd.uniform(0.6, 1.3)), rnd.uniform(0.85, 0.94))  # ledge
                if rnd.random() < 0.8:
                    cut(bm, (rnd.uniform(-0.4, 0.4), -1.0, rnd.uniform(-0.8, -0.3)), rnd.uniform(0.84, 0.94))
            layer_parts.append(bm)
        if is_glass:
            below = [BVHTree.FromBMesh(bm) for bm in stone]
            for bm in layer_parts:
                xs = [v.co.x for v in bm.verts]
                for _ in range(max(1, int((max(xs) - min(xs)) * 1.2))):
                    p = support(bm, Vector((rnd.uniform(-0.4, 0.4), -1.0, -1.6))) + Vector((0, 0.04, 0.06))
                    p.x = rnd.uniform(min(xs) + 0.2, max(xs) - 0.2)
                    length, width = rnd.uniform(0.25, 0.8), rnd.uniform(0.2, 0.42)
                    face = front_at(below, p.x, p.z - length * 0.85)
                    if face is None or face < p.y - 0.04:
                        continue  # the stone below juts out further: the drip would vanish in it
                    glass.append(drip(rnd, p, length, width, Vector((0, -1, 0)), min(face - p.y - 0.01, 0.4)))
            glass += layer_parts
        else:
            stone += layer_parts
        z += th
        layer += 1
    if glaze_top:
        caps = glaze_over(rnd, stone, -3.1, 3.1)
        below = [BVHTree.FromBMesh(bm) for bm in stone]
        for cap in caps:
            for _ in range(2):
                p = support(cap, Vector((rnd.uniform(-0.6, 0.6), -1.0, -1.5))) + Vector((0, 0.04, 0.06))
                length, width = rnd.uniform(0.3, 0.9), rnd.uniform(0.25, 0.5)
                face = front_at(below, p.x, p.z - length * 0.85)
                if face is None or face < p.y - 0.04:
                    continue
                glass.append(drip(rnd, p, length, width, Vector((0, -1, 0)), min(face - p.y - 0.01, 0.4)))
        glass += caps
    for _ in range(3):  # fallen blocks at the foot
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.25, -0.95), rnd.uniform(-0.05, 0.1))
        size = (rnd.uniform(0.6, 1.0), rnd.uniform(0.5, 0.8), rnd.uniform(0.35, 0.55))
        stone.append(chunk(rnd, size, 4, T(p, rand_rot(rnd, 25))))
    cutters = [
        chip_cutter(
            rnd, stone[rnd.randrange(len(stone) - 3)], (rnd.uniform(-0.6, 0.6), -0.7, 0.8), rnd.uniform(0.4, 0.6)
        )
        for _ in range(4)
    ]
    for _ in range(3):  # vertical joints
        center = (rnd.uniform(-2.5, 2.5), -1.1, rnd.uniform(1.0, 3.5))
        cutters.append(crack_cutter(rnd, center, 2.0, 1.2, 0.07, ry(90 + rnd.uniform(-10, 10))))
    return solid(name, "Cliff", glass, stone, cutters, center_y=False, back_y=CLIFF_BACK)


def skin(src: bmesh.types.BMesh, rnd: random.Random, thick: float, cuts: int = 2, smooth: float = 1.0):
    """A melted glass skin over a convex piece: a copy of it subdivided and rounded off (by `smooth`), pushed out
    along its normals by about `thick` (thicker and thinner in waves)."""
    bm = src.copy()
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, smooth=smooth, use_grid_fill=True)
    bm.normal_update()
    waves = [(rand_dir(rnd) * rnd.uniform(2.0, 5.0), rnd.uniform(0, math.tau)) for _ in range(3)]
    for v in bm.verts:
        v.co += v.normal * thick * (1.0 + 0.6 * sum(math.cos(v.co.dot(w) + ph) for w, ph in waves) / 3)
    bm.normal_update()
    return bm


def glaze_over(rnd: random.Random, stone: list, x0: float, x1: float) -> list:
    """A glass skin draped over a cliff's broken top: convex segments 1.2-1.8 m long hugging the top and running
    a little way down its front edge, overhanging it."""
    segs = []
    x = x0
    while x < x1 - 0.3:
        xe = min(x + rnd.uniform(1.2, 1.8), x1)
        near = [v.co for bm in stone for v in bm.verts if x - 0.3 <= v.co.x <= xe + 0.3]
        top = max(p.z for p in near)
        front = min(p.y for p in near if p.z > top - 0.7)
        pts = []
        for xi in (x - 0.05, (x + xe) / 2 + rnd.uniform(-0.2, 0.2), xe + 0.05):
            th = rnd.uniform(0.08, 0.16)
            drop = rnd.uniform(0.3, 0.55)
            pts += [
                Vector((xi, front + 1.2, top + th * 0.5)),
                Vector((xi, front + 0.35, top + th)),
                Vector((xi, front - 0.02, top - 0.04)),
                Vector((xi, front - 0.06 - th * 0.4, top - drop * 0.6)),
                Vector((xi, front - 0.02, top - drop)),
                Vector((xi, front + 0.3, top - drop - 0.1)),
                Vector((xi, front + 1.2, top - 0.3)),
            ]
        segs.append(hull(pts))
        x = xe - 0.05
    return segs


BUILDERS = {
    "Spire_a": lambda: spire_cluster(
        "Spire_a",
        11,
        [
            (3.3, 0.42, 0.0, 0.0, 3),
            (2.6, 0.36, 0.34, 0.14, 10),
            (2.0, 0.32, -0.3, 0.22, 14),
            (1.4, 0.28, 0.1, -0.36, 20),
        ],
        3,
        1,
    ),
    "Spire_b": lambda: spire_cluster(
        "Spire_b",
        22,
        [
            (2.9, 0.4, 0.05, 0.0, 6),
            (2.4, 0.36, -0.34, 0.06, 13),
            (1.8, 0.3, 0.28, 0.26, 18),
        ],
        3,
        1,
    ),
    "Spike_a": spike_a,
    "Sliver_a": sliver_a,
    "Splinters_a": splinters_a,
    "Boulder_a": lambda: boulder("Boulder_a", 81, (1.25, 1.05, 1.1), 0.5, 8, 6, 5),
    "Boulder_b": lambda: boulder("Boulder_b", 92, (1.5, 1.15, 0.8), 0.6, 18, 5, 4),
    "Fulgurite_a": fulgurite_a,
    "Chunks_a": chunks_a,
    "Cliff_a": lambda: strata_cliff("Cliff_a", 101, {2, 5}, 4.5, False),
    "Cliff_b": lambda: strata_cliff("Cliff_b", 112, {3}, 4.0, True),
}


# --- material -----------------------------------------------------------------------------------------


def mat_glass() -> bpy.types.Material:
    """The kit's one material. Glass (face attribute "glass"): opaque, glossy but not a mirror (roughness about 0.3),
    pale smoky grey-teal in the middle of a facet, paler toward its edges and toward the piece's top, faint fracture
    planes inside, grit settled on up-facing faces, a dim teal glow toward the edges. Stone: pale fused grey rock with a
    tone per facet, dark cracks and cavities, lighter chipped ridges and dust on top; rough."""
    mat, nt, bsdf = C._new_material("Glass")
    N, link = nt.nodes, nt.links.new

    def m(op, a, b=None, c=None, clamp=False):
        return C._math(nt, op, a, b, c, clamp)

    def attr(name: str, kind: str = "GEOMETRY") -> bpy.types.NodeSocket:
        node = N.new("ShaderNodeAttribute")
        node.attribute_type = kind
        node.attribute_name = name
        return node.outputs["Fac"]

    def scale_color(col, fac):
        n = N.new("ShaderNodeVectorMath")
        n.operation = "SCALE"
        link(col, n.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            link(fac, n.inputs["Scale"])
        else:
            n.inputs["Scale"].default_value = fac
        return n.outputs[0]

    coord = N.new("ShaderNodeTexCoord")
    geo = N.new("ShaderNodeNewGeometry")
    obj_co = coord.outputs["Object"]
    pos = N.new("ShaderNodeSeparateXYZ")
    link(obj_co, pos.inputs["Vector"])
    normal = N.new("ShaderNodeSeparateXYZ")
    link(geo.outputs["Normal"], normal.inputs["Vector"])
    up = C._ramp(nt, 0.45, 0.85, normal.outputs["Z"])

    # Glass where the face attribute says so; in between (a fulgurite's crust) in noisy patches.
    patch = C._noise(nt, 6.0, 3.0, 0.6)
    glass = C._ramp(
        nt, 0.45, 0.55, m("ADD", attr("glass"), m("MULTIPLY", m("SUBTRACT", patch.outputs["Fac"], 0.5), 1.6))
    )
    glass = C._bw(nt, glass)

    # Noise-warped coordinates for cracks and inner fracture planes.
    warp = C._noise(nt, 1.4, 3.0, 0.5, vector=obj_co)
    warp_c = N.new("ShaderNodeVectorMath")
    warp_c.operation = "MULTIPLY_ADD"
    link(warp.outputs["Color"], warp_c.inputs[0])
    warp_c.inputs[1].default_value = (0.35, 0.35, 0.35)
    link(obj_co, warp_c.inputs[2])
    warped = warp_c.outputs[0]
    facet = attr("facet")
    grain = C._noise(nt, 38.0, 4.0, 0.7)

    # --- glass ---
    rim = C._ramp(nt, 0.02, 0.15, C._bevel_edge(nt, 0.015, geo))  # the sharp rims
    near_edge = C._ramp(nt, 0.02, 0.4, C._bevel_edge(nt, 0.12, geo))  # toward a facet's edges
    tip = C._ramp(nt, 0.4, 1.0, m("DIVIDE", pos.outputs["Z"], m("MAXIMUM", attr("height", "OBJECT"), 0.1)))
    smoke = C._noise(nt, 2.0, 4.0, 0.6)
    core = C._mix_color(nt, C._ramp(nt, 0.35, 0.65, smoke.outputs["Fac"]), (0.1, 0.13, 0.14), (0.14, 0.18, 0.19))
    core = scale_color(core, m("MULTIPLY_ADD", facet, 0.2, 0.9))
    body = C._mix_color(nt, m("MULTIPLY", near_edge, 0.85), core, (0.22, 0.29, 0.31))
    body = C._mix_color(nt, m("MULTIPLY", tip, 0.6), body, (0.28, 0.36, 0.38))
    inner = m(
        "MULTIPLY",
        C._voronoi_lines(nt, warped, 2.2, 0.012),
        C._ramp(nt, 0.45, 0.65, C._noise(nt, 3.0, 2.0).outputs["Fac"]),
    )
    body = C._mix_color(nt, m("MULTIPLY", inner, 0.35), body, (0.26, 0.33, 0.35))
    body = C._mix_color(nt, m("MULTIPLY", rim, 0.4), body, (0.34, 0.43, 0.45))
    grit = m("MULTIPLY", up, C._ramp(nt, 0.5, 0.75, C._noise(nt, 4.0, 5.0, 0.65).outputs["Fac"]))
    grit = m("MULTIPLY", grit, 0.7)
    glass_col = C._mix_color(nt, grit, body, (0.15, 0.16, 0.16))
    glass_rough = C._mix_float(nt, grain.outputs["Fac"], 0.25, 0.35)  # glossy, not a mirror
    glass_rough = C._mix_float(nt, grit, glass_rough, 0.7)

    # --- stone ---
    crack = m(
        "MAXIMUM",
        m(
            "MULTIPLY",
            C._voronoi_lines(nt, warped, 0.9, 0.028),
            C._ramp(nt, 0.45, 0.6, C._noise(nt, 2.2, 4.0).outputs["Fac"]),
        ),
        m("MULTIPLY", C._voronoi_lines(nt, warped, 3.0, 0.022), 0.5),
    )
    tone = C._noise(nt, 0.7, 5.0, 0.6)
    stone = C._mix_color(nt, C._ramp(nt, 0.3, 0.72, tone.outputs["Fac"]), (0.058, 0.063, 0.067), (0.12, 0.126, 0.13))
    stone = scale_color(stone, m("MULTIPLY_ADD", facet, 0.5, 0.75))
    stone = scale_color(stone, m("MULTIPLY_ADD", grain.outputs["Fac"], 0.35, 0.83))
    ridge = m(
        "MULTIPLY",
        C._ramp(nt, 0.015, 0.09, C._bevel_edge(nt, 0.035, geo)),
        C._ramp(nt, 0.3, 0.6, C._noise(nt, 9.0, 3.0).outputs["Fac"]),
    )
    stone = C._mix_color(nt, ridge, stone, scale_color(stone, 1.6))
    ao = N.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.3
    ao.samples = 16
    cavity = m("SUBTRACT", 1.0, C._ramp(nt, 0.25, 0.95, ao.outputs["AO"]), clamp=True)
    stone = C._mix_color(nt, cavity, stone, (0.012, 0.012, 0.012))
    stone = C._mix_color(nt, crack, stone, (0.008, 0.008, 0.008))
    dust = m("MULTIPLY", up, C._ramp(nt, 0.3, 0.6, C._noise(nt, 3.5, 6.0, 0.65).outputs["Fac"]))
    dust = m("MULTIPLY", m("MULTIPLY", dust, m("SUBTRACT", 1.0, crack, clamp=True)), 0.85)
    stone = C._mix_color(
        nt, dust, stone, C._mix_color(nt, grain.outputs["Fac"], (0.13, 0.135, 0.13), (0.2, 0.205, 0.198))
    )
    stone_rough = C._mix_float(nt, tone.outputs["Fac"], 0.8, 0.92)
    stone_rough = C._mix_float(nt, dust, C._mix_float(nt, ridge, stone_rough, 0.72), 0.96)

    link(C._mix_color(nt, glass, stone, glass_col), bsdf.inputs["Base Color"])
    link(C._mix_float(nt, glass, stone_rough, glass_rough), bsdf.inputs["Roughness"])
    # A dim teal glow on the glass rims (baked into the emission map; ores stay the only bright things).
    bsdf.inputs["Emission Color"].default_value = (0.3, 0.62, 0.68, 1.0)
    link(m("MULTIPLY", m("MULTIPLY", near_edge, glass), 0.2), bsdf.inputs["Emission Strength"])

    # Relief: stone lumps and cracks; the glass only faint ripples.
    lumps = N.new("ShaderNodeTexVoronoi")
    lumps.feature = "SMOOTH_F1"
    lumps.inputs["Scale"].default_value = 3.0
    link(warped, lumps.inputs["Vector"])
    stone_h = m("ADD", m("MULTIPLY", lumps.outputs["Distance"], 0.5), m("MULTIPLY", grain.outputs["Fac"], 0.25))
    stone_h = m("SUBTRACT", stone_h, m("MULTIPLY", crack, 0.9))
    glass_h = m("MULTIPLY", smoke.outputs["Fac"], 0.06)
    C._bump(nt, bsdf, C._mix_float(nt, glass, stone_h, glass_h), 0.5, 0.03)
    return mat


# --- layout, preview, renders -------------------------------------------------------------------------

# Kit overview positions: (u along screen right, v toward the camera, z rotation). The iso camera looks from
# +X/-Y, so screen right is (+1, +1) and toward the camera is (+1, -1) in Blender XY.
LAYOUT = {
    "Cliff_a": (-3.4, -5.2, 45),
    "Cliff_b": (3.3, -5.2, 45),
    "Spire_a": (-5.6, -0.8, 0),
    "Boulder_a": (-3.0, -0.2, 0),
    "Fulgurite_a": (-1.0, -0.3, 0),
    "Boulder_b": (1.0, -0.2, 0),
    "Spire_b": (3.8, -0.8, 0),
    "Spike_a": (-3.4, 2.6, 0),
    "Sliver_a": (-2.2, 2.7, 0),
    "Splinters_a": (-0.6, 2.7, 0),
    "Chunks_a": (1.0, 2.7, 0),
}
FIGURE_UV = (2.6, 2.8)


def apply_layout() -> None:
    for name, (u, v, rot) in LAYOUT.items():
        obj = bpy.data.objects[name]
        obj.location = uv_to_xy(u, v)
        obj.rotation_euler = (0, 0, math.radians(rot))
    bpy.data.objects["PreviewFigure"].location = uv_to_xy(*FIGURE_UV)


def apply_bake_layout(gap: float = 3.0) -> None:
    """Saved .blend layout: every variant unrotated in one row along X with `gap` m between them, so the AO
    bake never picks up a neighbor. The bake stage zeroes the locations before the export."""
    x = 0.0
    for name in VARIANTS:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


def setup_preview() -> None:
    """The shared preview scene on a grey-teal glassy ground (instead of its brown one), without its pebbles."""
    C.preview_scene(crystals=False, pebbles=False)
    mat, nt, bsdf = C._new_material("PreviewGlassGround")
    noise = C._noise(nt, 0.8, 6.0, 0.6)
    nt.links.new(
        C._mix_color(nt, noise.outputs["Fac"], (0.035, 0.045, 0.048), (0.08, 0.09, 0.09)), bsdf.inputs["Base Color"]
    )
    nt.links.new(C._mix_float(nt, noise.outputs["Fac"], 0.3, 0.85), bsdf.inputs["Roughness"])
    C.assign(bpy.data.objects["PreviewGround"], mat)


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in VARIANTS]


def render_view(path: pathlib.Path, view: str, samples: int, size: int, target, zoom: float) -> None:
    C.render(path, view=view, samples=samples, size=size, target=tuple(target), zoom=zoom)


def render_kit(prefix: str, views, samples: int, size: int) -> list:
    apply_layout()
    center = uv_to_xy(0.0, -1.2) + Vector((0, 0, 0.9))
    out = []
    for view in views:
        path = OUT / f"{prefix}kit_{view}.png"
        render_view(path, view, samples, size, center, {"iso": 1.9, "hero": 2.4, "back": 2.4}[view])
        out.append(path)
    return out


def render_variant(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The variant alone at the origin, framed by its size, the scale figure beside it."""
    obj = bpy.data.objects[name]
    for o in kit_objects():
        o.hide_render = o is not obj
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
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
        render_view(path, view, samples, size, target, zoom)
        out.append(path)
    for o in kit_objects():
        o.hide_render = False
    return out


def render_scatter(path: pathlib.Path, samples: int, size: int) -> pathlib.Path:
    """Game-distance check: a terrace edge with its shard fence, a shard garden with a splinter patch, boulders and
    scatter, with random scale / tilt / sink like the ScatterType draws them, from about the game camera's
    distance (~19 m)."""
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

    put("Cliff_a", -4.5, 5.6, 1.0, 0, 0, rot=0)
    put("Cliff_b", 1.6, 5.9, 1.0, 0, 0, rot=0)
    for i in range(16):  # the fence along a terrace edge
        put(
            "Spike_a",
            -7.0 + i * 0.75 + rnd.uniform(-0.1, 0.1),
            3.0 + rnd.uniform(-0.1, 0.1),
            rnd.uniform(0.8, 1.2),
            8,
            0.0,
        )
    for x, y in ((-4.8, -1.0), (-3.2, -2.6), (-5.6, -3.0), (-3.6, 0.2)):  # a shard garden
        put(rnd.choice(("Spire_a", "Spire_b")), x, y, rnd.uniform(0.75, 1.3), 10, 0.1)
    for x, y in ((-1.8, -1.6), (-2.3, -0.6), (-1.4, -2.6)):
        put("Splinters_a", x, y, rnd.uniform(0.8, 1.4), 5, 0.0)
    for name, x, y in (
        ("Boulder_a", 2.4, -1.4),
        ("Boulder_b", 4.6, -3.6),
        ("Boulder_a", 5.6, 0.6),
        ("Boulder_b", 0.6, 1.8),
    ):
        put(name, x, y, rnd.uniform(0.7, 1.4), 12, 0.1)
    put("Fulgurite_a", 3.4, 1.8, 1.0, 8, 0.05)
    put("Fulgurite_a", -0.8, -4.6, 0.8, 8, 0.05)
    for _ in range(5):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.5, 7.0)
        put("Chunks_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.6, 1.2), 10, 0.03)
    for _ in range(14):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.0, 8.0)
        put("Sliver_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.6, 1.5), 35, 0.05)
    render_view(path, "iso", samples, size, (0, 0, 0.5), 1.4)
    for d in dupes:
        bpy.data.objects.remove(d)
    for o in kit_objects():
        o.hide_render = False
    return path


# --- main -------------------------------------------------------------------------------------------


def build() -> None:
    global ROOT_OBJ, GLASS
    ROOT_OBJ = C.asset_root(ASSET)
    GLASS = mat_glass()
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
        vals = [0.0] * len(me.polygons)
        me.attributes["glass"].data.foreach_get("value", vals)
        share = sum(vals) / max(len(vals), 1)
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(d, 2) for d in obj.dimensions)}"
            f" z=({min(zs):.2f}, {max(zs):.2f}) glass_faces={share:.2f} manifold={_is_manifold(obj)}"
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
        C.save_blend(OUT / "glass_procedural.blend")
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
                C.save_blend(OUT / "glass_procedural.blend")
                return


if __name__ == "__main__":
    main()
