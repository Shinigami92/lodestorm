"""Rocks and cliff dressing kit: jagged, cracked boulders, rubble, outcrops and cliff chunks for the scattered
location decoration (concepts: overgrowth_v1..v4, dustflats_house).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/rocks/source/rocks_build.py wip r1                  # kit iso + hero
    tools/blender.sh assets/rocks/source/rocks_build.py wip r1 Boulder_a,scatter
    tools/blender.sh assets/rocks/source/rocks_build.py final

Everything it writes goes to tmp/assets/rocks/: "wip <tag> [views]" renders quick previews into wip/<tag>_*.png
(views: kit_iso, kit_hero, scatter, variants, back, or a variant name); "final" renders the kit, every variant
(iso + hero), the cliffs' backs and a game-distance scatter, writes the contact sheet sheet.png and saves the
procedural rocks_procedural.blend that the bake stage turns into the game asset ("wip <tag> save" only saves
it). In the .blend the variants stand unrotated in a row along X, 3 m apart (bake layout, so the AO bake doesn't
pick up neighbors); the bake stage zeroes their locations before the export.

Game contract (scripts/locations/scatter_type.gd): a ScatterType draws ONE mesh many times (random scale, tilt,
sink), so every variant is one closed mesh object with one material ("Rock"), its origin at the ground contact
point (bottom center), sitting on z = 0 with extra rock below ground (SINK) so tilted or sunk instances don't
float. Cliffs face -Y (toward the camera side) with a flat back at y = +CLIFF_BACK. Budgets (TBD (playtest)):
boulders and rubble <= ~800 triangles, outcrops and cliffs <= ~2.5k.

Modeling: every variant is a union (boolean, manifold solver) of convex chunks (convex hulls of jittered points),
each shaved by a few random plane cuts so big flat fracture facets and sharp ridges dominate; thin cutters notch
cracks and chips into them. A random per-face "facet" attribute gives each fracture plane its own tone.
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "rocks"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit_iso", "kit_hero"]

ASSET = "Rocks"
# Rock kept below z = 0 per kind (m), so random tilt / sink in the game never shows the bottom.
SINK = {"Boulder": 0.18, "Rubble": 0.06, "Outcrop": 0.35, "Cliff": 0.45}
CLIFF_BACK = 1.0  # cliffs: flat back plane at y = +1 m, rock face toward -Y
SHARP_DEG = 32.0  # edges sharper than this split the shading (fracture ridges); softer ones shade smooth
VARIANTS = [
    "Boulder_a",
    "Boulder_b",
    "Boulder_c",
    "Boulder_d",
    "Rubble_a",
    "Rubble_b",
    "Outcrop_a",
    "Outcrop_b",
    "Cliff_a",
    "Cliff_b",
]

# --- math helpers -----------------------------------------------------------------------------------


def T(loc=(0, 0, 0), rot: Matrix | None = None, scale=(1, 1, 1)) -> Matrix:
    m = Matrix.Translation(Vector(loc))
    if rot is not None:
        m = m @ rot.to_4x4()
    return m @ Matrix.Diagonal((*scale, 1.0))


def rz(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def rx(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rand_rot(rnd: random.Random, tilt: float, spin: float = 180.0) -> Matrix:
    """Random spin around Z, then a lean of up to `tilt` degrees in a random direction."""
    return rz(rnd.uniform(0, 360)) @ rx(rnd.uniform(-tilt, tilt)) @ rz(rnd.uniform(-spin, spin))


def rand_dir(rnd: random.Random, min_z: float = -1.0, max_z: float = 1.0) -> Vector:
    while True:
        v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1)))
        if v.length > 1e-3:
            v.normalize()
            if min_z <= v.z <= max_z:
                return v


# --- chunk builder (convex fracture pieces) ----------------------------------------------------------


def hull(points: list) -> bmesh.types.BMesh:
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in points]
    res = bmesh.ops.convex_hull(bm, input=verts, use_existing_faces=False)
    kill = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def fill_holes(bm: bmesh.types.BMesh) -> None:
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)


def cut(bm: bmesh.types.BMesh, normal, keep: float = 0.8, at: float | None = None) -> None:
    """Shave off everything beyond a plane: a fracture facet. The plane sits at `keep` (0..1) of the extent
    along `normal`, or at the absolute offset `at`."""
    n = Vector(normal).normalized()
    ds = [v.co.dot(n) for v in bm.verts]
    off = at if at is not None else min(ds) + (max(ds) - min(ds)) * keep
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=n * off, plane_no=n, clear_outer=True)
    fill_holes(bm)


def shave(bm: bmesh.types.BMesh, rnd: random.Random, n: int, keep=(0.72, 0.9), min_z: float = -0.25) -> None:
    for _ in range(n):
        cut(bm, rand_dir(rnd, min_z=min_z), rnd.uniform(*keep))


def place(bm: bmesh.types.BMesh, m: Matrix) -> bmesh.types.BMesh:
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    return bm


def box_points(rnd: random.Random, size, jitter: float = 0.14, extra: int = 6, bulge: float = 0.12) -> list:
    """Corners of a box (centered) jittered, plus a few points pushed out of its faces (extra facets)."""
    sx, sy, sz = size
    pts = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            for cz in (-1, 1):
                j = Vector((rnd.uniform(-1, 1) * sx, rnd.uniform(-1, 1) * sy, rnd.uniform(-1, 1) * sz)) * jitter
                pts.append(Vector((cx * sx / 2, cy * sy / 2, cz * sz / 2)) + j)
    for _ in range(extra):
        axis = rnd.randrange(3)
        p = [rnd.uniform(-0.4, 0.4) * s for s in size]
        p[axis] = rnd.choice((-1, 1)) * size[axis] / 2 * (1 + rnd.uniform(0, bulge))
        pts.append(Vector(p))
    return pts


def prism_points(rnd: random.Random, rx_: float, ry_: float, h: float, sides: int = 6, taper: float = 0.85, jitter: float = 0.12) -> list:
    """Column from z = 0 to h with an irregular polygon cross-section (top scaled by taper)."""
    a0 = rnd.uniform(0, math.tau)
    pts = []
    for i in range(sides):
        a = a0 + (i + rnd.uniform(-0.25, 0.25)) / sides * math.tau
        r = 1 + rnd.uniform(-jitter, jitter)
        pts.append(Vector((math.cos(a) * rx_ * r, math.sin(a) * ry_ * r, 0.0)))
        t = taper * (1 + rnd.uniform(-jitter, jitter))
        pts.append(Vector((math.cos(a) * rx_ * r * t, math.sin(a) * ry_ * r * t, h * (1 + rnd.uniform(-0.04, 0.04)))))
    return pts


def chunk(rnd: random.Random, size, cuts: int = 3, m: Matrix | None = None, keep=(0.72, 0.9), **kw) -> bmesh.types.BMesh:
    bm = hull(box_points(rnd, size, **kw))
    shave(bm, rnd, cuts, keep)
    return place(bm, m) if m is not None else bm


def column(rnd: random.Random, r: float, h: float, sides: int = 6, depth: float | None = None, taper: float = 0.85, top_tilt: float = 0.5, cuts: int = 1, m: Matrix | None = None) -> bmesh.types.BMesh:
    """Columnar block with a slanted, fractured top."""
    bm = hull(prism_points(rnd, r, depth if depth is not None else r * rnd.uniform(0.75, 1.0), h, sides, taper))
    a = rnd.uniform(0, math.tau)
    cut(bm, (math.cos(a) * top_tilt, math.sin(a) * top_tilt, 1.0), rnd.uniform(0.86, 0.95))
    for _ in range(cuts):
        a = rnd.uniform(0, math.tau)
        cut(bm, (math.cos(a), math.sin(a), rnd.uniform(-0.2, 0.6)), rnd.uniform(0.8, 0.92))
    return place(bm, m) if m is not None else bm


def support(bm: bmesh.types.BMesh, direction) -> Vector:
    d = Vector(direction).normalized()
    return max((v.co.copy() for v in bm.verts), key=lambda p: p.dot(d))


def chip_cutter(rnd: random.Random, target: bmesh.types.BMesh, direction, size: float) -> bmesh.types.BMesh:
    """A small rotated block centered on the target's outermost point in `direction`: bites a chip out of a ridge."""
    p = support(target, direction)
    return chunk(rnd, (size, size * rnd.uniform(0.7, 1.1), size * rnd.uniform(0.6, 1.0)), 1, T(p, rand_rot(rnd, 60)))


def crack_cutter(rnd: random.Random, center, length: float, depth: float, width: float = 0.05, rot: Matrix | None = None) -> bmesh.types.BMesh:
    """Thin slab (length along X, depth along Y, width along Z) that notches a crack into a face."""
    pts = []
    for cx in (-1, 1):
        for cy in (-1, 1):
            for cz in (-1, 1):
                w = width * (rnd.uniform(0.4, 1.0) if cy > 0 else rnd.uniform(1.0, 1.8))  # wider at the mouth (-Y)
                pts.append(Vector((cx * length / 2 * rnd.uniform(0.85, 1.0), cy * depth / 2, cz * w / 2)))
    return place(hull(pts), T(center, rot))


# --- mesh assembly ------------------------------------------------------------------------------------


def bm_to_obj(bm: bmesh.types.BMesh, name: str, coll: str = "Work") -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    C.collection(coll).objects.link(obj)
    return obj


def _work_collection(name: str) -> bpy.types.Collection:
    coll = bpy.data.collections.new(name)
    C.collection("Work").children.link(coll)
    return coll


def _boolean(base: bpy.types.Object, op: str, coll: bpy.types.Collection) -> None:
    mod = base.modifiers.new(op.title(), "BOOLEAN")
    mod.operation = op
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    try:
        mod.solver = "MANIFOLD"
    except TypeError:
        mod.solver = "EXACT"


def solid(name: str, kind: str, parts: list, cutters: list = (), center_y: bool = True, back_y: float | None = None) -> bpy.types.Object:
    """Union of the convex parts minus the cutters, cleaned up, bottom cut flat at -SINK, origin at the bottom
    center; returns the finished variant object in the asset collection."""
    base = bm_to_obj(parts[0], name + "_base")
    if len(parts) > 1:
        coll = _work_collection(name + "_union")
        for i, bm in enumerate(parts[1:]):
            bm_to_obj(bm, f"{name}_u{i}", coll.name)
        _boolean(base, "UNION", coll)
    if cutters:
        coll = _work_collection(name + "_cut")
        for i, bm in enumerate(cutters):
            bm_to_obj(bm, f"{name}_c{i}", coll.name)
        _boolean(base, "DIFFERENCE", coll)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    finish_mesh(bm, kind, center_y, back_y)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    facet_attribute(me, name)
    obj = bpy.data.objects.new(name, me)
    C.link(obj, ROOT_OBJ)
    C.assign(obj, ROCK)
    return obj


def finish_mesh(bm: bmesh.types.BMesh, kind: str, center_y: bool, back_y: float | None) -> None:
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.004)
    bmesh.ops.dissolve_degenerate(bm, dist=0.003, edges=bm.edges[:])
    cut(bm, (0, 0, -1), at=SINK[kind])  # flat bottom at z = -SINK (normal points down: keeps what's above)
    if back_y is not None:
        cut(bm, (0, 1, 0), at=back_y)
    # Merge the coplanar triangles the hulls and booleans leave on the big facets (fewer triangles).
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(2.0), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
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


def facet_attribute(me: bpy.types.Mesh, seed: str) -> None:
    """Random value per face: each fracture plane gets its own tone in the material."""
    rnd = random.Random(seed)
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", [rnd.random() for _ in me.polygons])


# --- variants ------------------------------------------------------------------------------------------


def boulder_a() -> bpy.types.Object:
    """Blocky: a big faceted block with a smaller one wedged against it, chipped ridges."""
    rnd = random.Random(11)
    main = chunk(rnd, (1.45, 1.3, 1.5), 5, T((0, 0, 0.55), rz(12)), keep=(0.74, 0.92), jitter=0.18, extra=10, bulge=0.18)
    side = chunk(rnd, (0.9, 0.8, 0.8), 3, T((0.66, -0.4, 0.2), rz(-25) @ ry(14)), keep=(0.75, 0.9), jitter=0.15)
    chips = [chip_cutter(rnd, main, (0.6, -0.5, 0.8), 0.32), chip_cutter(rnd, main, (-0.7, 0.3, 0.6), 0.28)]
    crack = crack_cutter(rnd, (-0.1, -0.55, 0.55), 1.3, 0.9, 0.045, rz(8) @ rx(-10) @ ry(25))
    return solid("Boulder_a", "Boulder", [main, side], chips + [crack])


def boulder_b() -> bpy.types.Object:
    """Slab: flat layered plates stacked off-center (strata), the upper one broken short."""
    rnd = random.Random(22)
    lower = chunk(rnd, (2.0, 1.3, 0.45), 4, T((0, 0, 0.02), rz(4) @ ry(5)), keep=(0.8, 0.94), extra=5, bulge=0.06)
    upper = chunk(rnd, (1.45, 1.05, 0.36), 4, T((0.18, 0.08, 0.36), rz(-9) @ ry(7)), keep=(0.78, 0.92), extra=4, bulge=0.06)
    top = chunk(rnd, (0.7, 0.6, 0.26), 3, T((0.38, 0.15, 0.62), rz(20) @ rx(9)), keep=(0.75, 0.9))
    chips = [chip_cutter(rnd, lower, (-1, -0.4, 0.4), 0.3)]
    return solid("Boulder_b", "Boulder", [lower, upper, top], chips)


def boulder_c() -> bpy.types.Object:
    """Split: one block cracked through, the halves leaning apart, a wedge stuck in the gap."""
    rnd = random.Random(33)
    block = chunk(rnd, (1.5, 1.25, 1.3), 6, T((0, 0, 0.45)), keep=(0.65, 0.88), jitter=0.2, extra=10, bulge=0.18)
    n = Vector((math.cos(math.radians(62)), math.sin(math.radians(62)), 0.12)).normalized()
    other = block.copy()
    cut(block, n, at=0.0)
    cut(other, -n, at=0.0)
    gap = 0.07
    axis = n.cross(Vector((0, 0, 1))).normalized()
    pivot_a = -n * 0.0 + Vector((0, 0, -0.1))
    tilt_a = Matrix.Rotation(math.radians(-5), 4, axis)
    tilt_b = Matrix.Rotation(math.radians(4), 4, axis)
    place(block, Matrix.Translation(pivot_a - n * gap) @ tilt_a @ Matrix.Translation(-pivot_a))
    place(other, Matrix.Translation(pivot_a + n * gap) @ tilt_b @ Matrix.Translation(-pivot_a))
    wedge = chunk(rnd, (0.28, 0.2, 0.3), 2, T((0, 0, 0.92), rz(62) @ rx(15)))
    chip = chip_cutter(rnd, other, (0.4, 0.6, 0.9), 0.3)
    return solid("Boulder_c", "Boulder", [block, other, wedge], [chip])


def boulder_d() -> bpy.types.Object:
    """Tall: an upright five-sided block with a steep fractured top and a fallen piece at its foot."""
    rnd = random.Random(44)
    body = column(rnd, 0.55, 2.0, sides=5, depth=0.45, taper=0.72, top_tilt=1.2, cuts=2, m=T((0, 0, -0.2), ry(6) @ rz(15)))
    foot = chunk(rnd, (0.75, 0.6, 0.55), 3, T((0.5, -0.32, 0.05), rz(30) @ ry(-20)))
    crack = crack_cutter(rnd, (0.0, -0.42, 1.05), 1.4, 0.7, 0.05, rz(15) @ ry(-18))
    chip = chip_cutter(rnd, body, (-0.5, -0.6, 0.3), 0.3)
    return solid("Boulder_d", "Boulder", [body, foot], [crack, chip])


def rubble(name: str, seed: int, count: int, radius: float, size: tuple, flat: tuple) -> bpy.types.Object:
    """Cluster of angular stones, half buried, biggest in the middle."""
    rnd = random.Random(seed)
    stones, spots = [], []
    for i in range(count):
        s = size[1] - (size[1] - size[0]) * (i / max(1, count - 1)) * rnd.uniform(0.8, 1.0)
        for _ in range(40):  # keep stones from merging into one blob
            a = rnd.uniform(0, math.tau)
            r = radius * math.sqrt(rnd.random()) * (0.35 if i == 0 else 1.0)
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
            if all((p - q).length > (s + t) * 0.42 for q, t in spots):
                break
        spots.append((p, s))
        h = s * rnd.uniform(*flat)
        m = T((p.x, p.y, h * rnd.uniform(0.12, 0.3)), rand_rot(rnd, 25))
        stones.append(chunk(rnd, (s, s * rnd.uniform(0.6, 0.95), h), 2, m, keep=(0.65, 0.85), extra=3))
    return solid(name, "Rubble", stones)


def outcrop_a() -> bpy.types.Object:
    """Columnar spire cluster: tall prismatic columns with fractured tops, cracked across, fallen blocks."""
    rnd = random.Random(55)
    parts = []
    cols = [(4.7, 0.62, (0.0, 0.1)), (3.9, 0.5, (0.62, -0.25)), (3.3, 0.48, (-0.6, -0.15)), (2.6, 0.45, (0.25, -0.75)), (2.1, 0.42, (-0.3, 0.7)), (1.5, 0.4, (0.95, 0.45))]
    for h, r, (x, y) in cols:
        lean = rx(rnd.uniform(-4, 4)) @ ry(rnd.uniform(-4, 4))
        parts.append(column(rnd, r, h + SINK["Outcrop"], sides=rnd.choice((5, 6)), taper=rnd.uniform(0.7, 0.85), top_tilt=rnd.uniform(0.4, 1.0), cuts=2, m=T((x, y, -SINK["Outcrop"]), lean @ rz(rnd.uniform(0, 60)))))
    for p in ((0.9, -0.85, 0.1), (-1.0, -0.6, 0.05), (-0.85, 0.75, 0.0)):
        parts.append(chunk(rnd, (0.65, 0.5, 0.45), 3, T(p, rand_rot(rnd, 25))))
    cutters = [
        crack_cutter(rnd, (0.0, -0.75, 1.6), 1.8, 1.2, 0.07, rz(-35) @ ry(6)),
        crack_cutter(rnd, (0.5, -0.6, 2.9), 1.2, 1.0, 0.06, rz(-40) @ ry(-8)),
        crack_cutter(rnd, (-0.4, -0.5, 0.9), 1.4, 1.0, 0.06, rz(-20) @ ry(10)),
        chip_cutter(rnd, parts[0], (0.3, -0.5, 1.0), 0.45),
        chip_cutter(rnd, parts[1], (0.7, -0.3, 0.8), 0.38),
    ]
    return solid("Outcrop_a", "Outcrop", parts, cutters)


def outcrop_b() -> bpy.types.Object:
    """Shard cluster: pointed slabs splaying out of the ground, broken shards at their foot."""
    rnd = random.Random(66)
    parts = []
    shards = [(3.8, 0.0, 4), (3.1, 70, 10), (2.7, 150, 13), (2.3, 215, 11), (1.9, 285, 15), (1.5, 330, 18), (1.3, 110, 21)]
    for h, ang, lean in shards:
        bm = column(rnd, rnd.uniform(0.5, 0.66), h + SINK["Outcrop"], sides=rnd.choice((4, 5)), depth=rnd.uniform(0.28, 0.42), taper=rnd.uniform(0.3, 0.5), top_tilt=rnd.uniform(1.2, 2.4), cuts=2)
        out = Vector((math.cos(math.radians(ang)), math.sin(math.radians(ang)), 0))
        axis = out.cross(Vector((0, 0, 1)))
        m = T(out * 0.38 + Vector((0, 0, -SINK["Outcrop"]))) @ Matrix.Rotation(math.radians(-lean), 4, axis) @ rz(ang + 90 + rnd.uniform(-25, 25)).to_4x4()
        parts.append(place(bm, m))
    for _ in range(4):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.9, 1.3)
        bm = column(rnd, rnd.uniform(0.3, 0.42), rnd.uniform(0.8, 1.2), sides=4, depth=0.2, taper=0.45, top_tilt=1.5, cuts=1)
        parts.append(place(bm, T((math.cos(a) * r, math.sin(a) * r, 0.02), rz(math.degrees(a)) @ ry(rnd.uniform(70, 85)))))
    cutters = [crack_cutter(rnd, (0.0, -0.3, 1.4), 1.2, 0.8, 0.06, rz(-30) @ ry(12)), crack_cutter(rnd, (0.0, -0.2, 2.5), 0.8, 0.6, 0.05, rz(10) @ ry(-15))]
    return solid("Outcrop_b", "Outcrop", parts, cutters)


def cliff_a() -> bpy.types.Object:
    """Columnar cliff face: vertical prismatic columns of uneven depth and height, horizontal fracture lines,
    fallen blocks at the foot; flat back."""
    rnd = random.Random(77)
    s = SINK["Cliff"]
    parts, x = [], -3.1
    while x < 3.1:
        w = rnd.uniform(0.75, 1.15)
        cx = min(x + w / 2, 3.1 - w / 2 + 0.2)
        front = rnd.uniform(-1.05, -0.6)
        depth = (CLIFF_BACK + 0.15 - front) / 2
        h = rnd.uniform(3.5, 5.3)
        bm = column(rnd, w / 2 * 1.12, h + s, sides=rnd.choice((5, 6, 6)), depth=depth, taper=rnd.uniform(0.86, 0.95), top_tilt=rnd.uniform(0.3, 0.8), cuts=1)
        parts.append(place(bm, T((cx, front + depth, -s), rx(rnd.uniform(-2, 3)))))
        x += w * rnd.uniform(0.82, 0.95)
    for x in (rnd.uniform(-2.4, -1.2), rnd.uniform(-0.4, 0.6), rnd.uniform(1.4, 2.4)):  # broken-off columns in front
        r = rnd.uniform(0.38, 0.5)
        bm = column(rnd, r, rnd.uniform(1.2, 2.6) + s, sides=6, taper=0.9, top_tilt=rnd.uniform(0.4, 1.0), cuts=1)
        parts.append(place(bm, T((x, -0.85, -s), rx(rnd.uniform(-6, 0)))))
    for _ in range(4):
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.1, -0.85), rnd.uniform(-0.05, 0.1))
        parts.append(chunk(rnd, (rnd.uniform(0.5, 0.9), rnd.uniform(0.45, 0.7), rnd.uniform(0.35, 0.6)), 3, T(p, rand_rot(rnd, 20))))
    cutters = []
    for z in (1.3, 2.5, 3.6):
        for _ in range(2):
            cutters.append(crack_cutter(rnd, (rnd.uniform(-2.4, 2.4), -1.1, z + rnd.uniform(-0.3, 0.3)), rnd.uniform(1.4, 2.4), 1.0, 0.07, rz(rnd.uniform(-6, 6)) @ ry(rnd.uniform(-8, 8))))
    for _ in range(3):
        cutters.append(chip_cutter(rnd, parts[rnd.randrange(len(parts) - 7)], (rnd.uniform(-0.5, 0.5), -0.6, 1.0), rnd.uniform(0.4, 0.6)))
    return solid("Cliff_a", "Cliff", parts, cutters, center_y=False, back_y=CLIFF_BACK)


def cliff_b() -> bpy.types.Object:
    """Layered cliff face: dipping strata of uneven thickness, each set back or jutting out, with jagged faceted
    fronts, weathered ledges, the odd vertical joint and a broken top; flat back."""
    rnd = random.Random(88)
    s = SINK["Cliff"]
    parts, z, layer = [], -s, 0
    dip = rnd.uniform(-4, 4)
    while z < 4.5:
        th = 0.85 + s if layer == 0 else (rnd.uniform(0.35, 0.6) if rnd.random() < 0.45 else rnd.uniform(0.7, 1.25))
        set_back = rnd.uniform(-0.18, 0.18) + 0.09 * layer  # upper strata recede: a cliff, not a stack
        cuts_x = sorted(rnd.uniform(-2.2, 2.2) for _ in range(rnd.choice((0, 1, 1, 2))))
        edges = [-3.1, *cuts_x, 3.1]
        spans = [(edges[i] - (0.1 if i else 0), edges[i + 1] + (0.1 if i + 2 < len(edges) else 0)) for i in range(len(edges) - 1)]
        for x0, x1 in spans:
            front = -1.0 + set_back + rnd.uniform(-0.2, 0.2)
            last = z + th >= 4.5
            top = z + th + (rnd.uniform(-0.3, 0.3) if last else 0.0)
            z0 = z - 0.15 if layer else z  # overlap the layer below: no floating strata
            depth = CLIFF_BACK + 0.15 - front
            m = T(((x0 + x1) / 2, front + depth / 2, (z0 + top) / 2), rz(rnd.uniform(-3, 3)) @ ry(dip + rnd.uniform(-1.5, 1.5)))
            bm = chunk(rnd, (x1 - x0, depth, top - z0), 0, m, jitter=0.03, extra=0)
            for _ in range(rnd.randint(3, 6)):  # jagged front: facets at varied angles
                cut(bm, (rnd.uniform(-1.0, 1.0), -1.0, rnd.uniform(-0.5, 0.5)), rnd.uniform(0.88, 0.97))
            if last:  # broken top
                for _ in range(2):
                    cut(bm, (rnd.uniform(-1.0, 1.0), rnd.uniform(-0.6, 0.2), 1.0), rnd.uniform(0.8, 0.92))
            cut(bm, (rnd.uniform(-0.3, 0.3), -1.0, rnd.uniform(0.6, 1.3)), rnd.uniform(0.85, 0.94))  # weathered ledge
            if rnd.random() < 0.8:
                cut(bm, (rnd.uniform(-0.4, 0.4), -1.0, rnd.uniform(-0.8, -0.3)), rnd.uniform(0.84, 0.94))  # undercut
            parts.append(bm)
        z += th
        layer += 1
    for _ in range(3):
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.25, -0.95), rnd.uniform(-0.05, 0.1))
        parts.append(chunk(rnd, (rnd.uniform(0.6, 1.0), rnd.uniform(0.5, 0.8), rnd.uniform(0.35, 0.55)), 4, T(p, rand_rot(rnd, 25))))
    cutters = [chip_cutter(rnd, parts[rnd.randrange(len(parts) - 3)], (rnd.uniform(-0.6, 0.6), -0.7, 0.8), rnd.uniform(0.4, 0.6)) for _ in range(4)]
    for _ in range(3):  # vertical joints
        cutters.append(crack_cutter(rnd, (rnd.uniform(-2.5, 2.5), -1.1, rnd.uniform(1.0, 3.5)), 2.0, 1.2, 0.07, ry(90 + rnd.uniform(-10, 10))))
    return solid("Cliff_b", "Cliff", parts, cutters, center_y=False, back_y=CLIFF_BACK)


BUILDERS = {
    "Boulder_a": boulder_a,
    "Boulder_b": boulder_b,
    "Boulder_c": boulder_c,
    "Boulder_d": boulder_d,
    "Rubble_a": lambda: rubble("Rubble_a", 101, 6, 0.32, (0.14, 0.42), (0.5, 0.8)),
    "Rubble_b": lambda: rubble("Rubble_b", 202, 9, 0.45, (0.1, 0.32), (0.3, 0.55)),
    "Outcrop_a": outcrop_a,
    "Outcrop_b": outcrop_b,
    "Cliff_a": cliff_a,
    "Cliff_b": cliff_b,
}

# --- material -----------------------------------------------------------------------------------------


def mat_rock() -> bpy.types.Material:
    """Dark grey-brown fractured rock: per-facet tone, strata bands, dark noise-warped cracks, lighter chipped
    ridges, cavity grime, dust settling on up-facing faces; rough, bumpy fracture surface."""
    mat, nt, bsdf = C._new_material("Rock")
    N, link = nt.nodes, nt.links.new

    def math_node(op, a, b=None, c=None, clamp=False):
        n = N.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for sock, val in ((n.inputs[0], a), (n.inputs[1], b), (n.inputs[2], c)):
            if val is None:
                continue
            if isinstance(val, bpy.types.NodeSocket):
                link(val, sock)
            else:
                sock.default_value = val
        return n.outputs[0]

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

    # Noise-warped coordinates for the cracks (no straight Voronoi lines).
    warp = N.new("ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = 1.4
    warp.inputs["Detail"].default_value = 3.0
    link(obj_co, warp.inputs["Vector"])
    warp_c = N.new("ShaderNodeVectorMath")
    warp_c.operation = "MULTIPLY_ADD"
    link(warp.outputs["Color"], warp_c.inputs[0])
    warp_c.inputs[1].default_value = (0.35, 0.35, 0.35)
    link(obj_co, warp_c.inputs[2])
    warped = warp_c.outputs[0]

    def cracks(scale, width):
        v = N.new("ShaderNodeTexVoronoi")
        v.feature = "DISTANCE_TO_EDGE"
        v.inputs["Scale"].default_value = scale
        link(warped, v.inputs["Vector"])
        r = N.new("ShaderNodeValToRGB")
        r.color_ramp.elements[0].position = 0.0
        r.color_ramp.elements[0].color = (1, 1, 1, 1)
        r.color_ramp.elements[1].position = width
        r.color_ramp.elements[1].color = (0, 0, 0, 1)
        link(v.outputs["Distance"], r.inputs["Fac"])
        return r.outputs["Color"]

    breakup = C._noise(nt, 2.2, 4.0, 0.55)
    crack_big = math_node("MULTIPLY", cracks(0.9, 0.028), C._ramp(nt, 0.45, 0.6, breakup.outputs["Fac"]))
    crack_fine = math_node("MULTIPLY", cracks(3.0, 0.022), math_node("MULTIPLY", C._ramp(nt, 0.55, 0.7, breakup.outputs["Fac"]), 0.6))
    crack = math_node("MAXIMUM", crack_big, crack_fine)

    # Base tone: large noise between dark and lighter grey-brown, per-facet variation, strata bands along Z.
    tone = C._noise(nt, 0.7, 5.0, 0.6)
    base = C._mix_color(nt, C._ramp(nt, 0.3, 0.72, tone.outputs["Fac"]), (0.050, 0.046, 0.041), (0.108, 0.103, 0.096))
    facet = N.new("ShaderNodeAttribute")
    facet.attribute_type = "GEOMETRY"
    facet.attribute_name = "facet"
    base = scale_color(base, math_node("MULTIPLY_ADD", facet.outputs["Fac"], 0.56, 0.72))  # 0.72 .. 1.28
    wave = N.new("ShaderNodeTexWave")
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 1.1
    wave.inputs["Distortion"].default_value = 5.0
    wave.inputs["Detail"].default_value = 3.0
    link(obj_co, wave.inputs["Vector"])
    base = scale_color(base, math_node("MULTIPLY_ADD", wave.outputs["Fac"], 0.28, 0.82))
    # Grain: fine speckle.
    grain = C._noise(nt, 38.0, 4.0, 0.7)
    base = scale_color(base, math_node("MULTIPLY_ADD", grain.outputs["Fac"], 0.35, 0.83))

    # Ridges: convex edges found with the Bevel node, chipped lighter (fresh fracture).
    bev = N.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.035
    dot = N.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    link(bev.outputs["Normal"], dot.inputs[0])
    link(geo.outputs["Normal"], dot.inputs[1])
    edge = C._ramp(nt, 0.015, 0.09, math_node("SUBTRACT", 1.0, dot.outputs["Value"]))
    edge = math_node("MULTIPLY", edge, C._ramp(nt, 0.3, 0.6, C._noise(nt, 9.0, 3.0, 0.6).outputs["Fac"]))
    col = C._mix_color(nt, edge, base, scale_color(base, 1.75))

    # Cavities (AO) and cracks go dark.
    ao = N.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.35
    ao.samples = 16
    cavity = C._ramp(nt, 0.25, 0.95, ao.outputs["AO"])
    col = C._mix_color(nt, math_node("SUBTRACT", 1.0, cavity, clamp=True), col, (0.012, 0.011, 0.010))
    col = C._mix_color(nt, crack, col, (0.008, 0.007, 0.006))

    # Dust on up-facing faces (world Z: tilt in the game is small), broken up, kept out of cracks.
    sep = N.new("ShaderNodeSeparateXYZ")
    link(geo.outputs["Normal"], sep.inputs["Vector"])
    up = C._ramp(nt, 0.45, 0.8, sep.outputs["Z"])
    dust_noise = C._noise(nt, 3.5, 6.0, 0.65)
    dust = math_node("MULTIPLY", up, C._ramp(nt, 0.28, 0.58, dust_noise.outputs["Fac"]))
    dust = math_node("MULTIPLY", dust, math_node("SUBTRACT", 1.0, crack, clamp=True))
    dust = math_node("MULTIPLY", dust, 0.9)
    dust_col = C._mix_color(nt, grain.outputs["Fac"], (0.145, 0.127, 0.105), (0.225, 0.196, 0.162))
    col = C._mix_color(nt, dust, col, dust_col)
    link(col, bsdf.inputs["Base Color"])

    rough = C._mix_float(nt, tone.outputs["Fac"], 0.8, 0.92)
    rough = C._mix_float(nt, edge, rough, 0.72)
    rough = C._mix_float(nt, dust, rough, 0.97)
    link(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0

    # Relief: cracks cut in, a coarse Voronoi gives the fracture surface lumps, fine noise grain.
    lumps = N.new("ShaderNodeTexVoronoi")
    lumps.feature = "SMOOTH_F1"
    lumps.inputs["Scale"].default_value = 3.0
    link(warped, lumps.inputs["Vector"])
    height = math_node("MULTIPLY", lumps.outputs["Distance"], 0.5)
    height = math_node("ADD", height, math_node("MULTIPLY", grain.outputs["Fac"], 0.25))
    height = math_node("SUBTRACT", height, math_node("MULTIPLY", crack, 0.9))
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.03
    link(height, bump.inputs["Height"])
    link(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# --- layout, preview, renders -------------------------------------------------------------------------

# Kit overview positions: (u along screen right, v toward the camera, z rotation). The iso camera looks from
# +X/-Y, so screen right is (+1, +1) and toward the camera is (+1, -1) in Blender XY.
LAYOUT = {
    "Cliff_a": (-3.4, -5.0, 45),
    "Cliff_b": (3.3, -5.0, 45),
    "Outcrop_a": (-5.4, -0.6, 0),
    "Boulder_a": (-2.4, -0.4, 0),
    "Boulder_b": (0.4, -0.4, 0),
    "Boulder_c": (3.0, -0.4, 0),
    "Outcrop_b": (6.0, -0.6, 0),
    "Boulder_d": (-2.0, 2.8, 0),
    "Rubble_a": (0.2, 2.8, 0),
    "Rubble_b": (1.9, 2.8, 0),
}
FIGURE_UV = (3.6, 2.8)


def uv_to_xy(u: float, v: float) -> Vector:
    s = math.sqrt(0.5)
    return Vector((u * s + v * s, u * s - v * s, 0.0))


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
    C.preview_scene(crystals=False)
    # Drop the preview's placeholder pebbles (icospheres): they'd read as part of the kit.
    for obj in list(C.collection("Preview").objects):
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)


def rock_objects() -> list:
    return [bpy.data.objects[n] for n in VARIANTS]


def render_view(path: pathlib.Path, view: str, samples: int, size: int, target, zoom: float) -> None:
    C.render(path, view=view, samples=samples, size=size, target=tuple(target), zoom=zoom)


def render_kit(prefix: str, views, samples: int, size: int) -> list:
    apply_layout()
    center = uv_to_xy(0.3, -1.2) + Vector((0, 0, 0.9))
    out = []
    for view in views:
        path = OUT / f"{prefix}kit_{view}.png"
        render_view(path, view, samples, size, center, {"iso": 1.85, "hero": 2.4, "back": 2.4}[view])
        out.append(path)
    return out


def render_variant(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The variant alone at the origin, framed by its size, the scale figure beside it."""
    obj = bpy.data.objects[name]
    for o in rock_objects():
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
    for o in rock_objects():
        o.hide_render = False
    return out


def render_scatter(path: pathlib.Path, samples: int, size: int) -> pathlib.Path:
    """Game-distance check: instances with random scale / tilt / sink like the ScatterType draws them, seen from
    about the game camera's distance (~19 m)."""
    rnd = random.Random(5)
    for o in rock_objects():
        o.hide_render = True
    bpy.data.objects["PreviewFigure"].location = (0.6, -0.8, 0)
    dupes = []

    def put(name, x, y, scale, tilt, sink, rot=None):
        src = bpy.data.objects[name]
        d = src.copy()  # linked duplicate (shares the mesh)
        C.collection("Preview").objects.link(d)
        d.hide_render = False
        d.parent = None
        d.location = (x, y, -sink * scale)
        d.rotation_euler = (math.radians(rnd.uniform(-tilt, tilt)), math.radians(rnd.uniform(-tilt, tilt)), math.radians(rot if rot is not None else rnd.uniform(0, 360)))
        d.scale = (scale,) * 3
        dupes.append(d)

    put("Cliff_a", -4.5, 5.0, 1.0, 0, 0, rot=0)
    put("Cliff_b", 1.6, 5.3, 1.0, 0, 0, rot=0)
    put("Outcrop_a", -6.5, -0.5, 0.9, 4, 0.1)
    put("Outcrop_b", 5.0, 1.5, 1.0, 4, 0.1)
    boulders = ["Boulder_a", "Boulder_b", "Boulder_c", "Boulder_d"]
    spots = [(-2.6, 1.6), (2.6, -1.8), (-3.5, -3.2), (3.9, -4.6), (-0.9, -5.2), (1.3, 2.2), (6.5, -2.0), (-5.6, 2.8)]
    for i, (x, y) in enumerate(spots):
        put(boulders[i % 4], x, y, rnd.uniform(0.6, 1.6), 15, 0.15)
    for _ in range(14):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.5, 8.0)
        put(rnd.choice(("Rubble_a", "Rubble_b")), math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.7, 1.4), 15, 0.05)
    render_view(path, "iso", samples, size, (0, 0, 0.5), 1.4)
    for d in dupes:
        bpy.data.objects.remove(d)
    for o in rock_objects():
        o.hide_render = False
    return path


def contact_sheet(paths: list, path: pathlib.Path, cols: int = 4, tile: int = 384) -> None:
    """Grid of the given renders (row-major, top-left first), composed with numpy inside Blender."""
    import numpy as np

    rows = math.ceil(len(paths) / cols)
    sheet = np.full((rows * tile, cols * tile, 4), 0.02, dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, p in enumerate(paths):
        img = bpy.data.images.load(str(p))
        img.scale(tile, tile)
        px = np.empty(tile * tile * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * tile  # Blender images are stored bottom-up
        sheet[y0 : y0 + tile, c * tile : (c + 1) * tile] = px.reshape(tile, tile, 4)
        bpy.data.images.remove(img)
    out = bpy.data.images.new("sheet", cols * tile, rows * tile, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = str(path)
    out.file_format = "PNG"
    out.save()
    print("SHEET", path)


# --- main -------------------------------------------------------------------------------------------


def build() -> None:
    global ROOT_OBJ, ROCK
    ROOT_OBJ = C.asset_root(ASSET)
    ROCK = mat_rock()
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
        manifold = _is_manifold(obj)
        print(f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(d, 2) for d in obj.dimensions)} z=({min(zs):.2f}, {max(zs):.2f}) manifold={manifold}")
        obj.evaluated_get(dg).to_mesh_clear()
    print("STATS", C.stats())


def _is_manifold(obj: bpy.types.Object) -> bool:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = [e for e in bm.edges if not e.is_manifold]
    if bad:
        print("NONMANIFOLD", obj.name, len(bad), [tuple(round(c, 2) for c in (e.verts[0].co + e.verts[1].co) / 2) for e in bad[:6]], [len(e.link_faces) for e in bad[:6]])
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
        contact_sheet(sheet, OUT / "sheet.png")
        apply_bake_layout()
        C.save_blend(OUT / "rocks_procedural.blend")
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
                contact_sheet(names, wip / f"{TAG}_sheet.png")
            elif view == "save":
                apply_bake_layout()
                C.save_blend(OUT / "rocks_procedural.blend")
                return


main()
