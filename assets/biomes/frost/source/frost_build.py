"""Frost fields scatter kit: snow-capped dark boulders, glassy ice blocks, an ice-and-rock pinnacle, a wind-carved
snow drift, a frozen dead shrub, frosted rubble and cliff chunks of the frost rock (concepts: batch11 frost and
frost_props).

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/frost/source/frost_build.py wip f1                  # kit iso + hero
    tools/blender.sh assets/biomes/frost/source/frost_build.py wip f1 Ice_a,scatter
    tools/blender.sh assets/biomes/frost/source/frost_build.py final

Everything it writes goes to tmp/assets/frost/: "wip <tag> [views]" renders quick previews into wip/<tag>_*.png
(views: kit_iso, kit_hero, scatter, variants, back, sheet, save, or a variant name); "final" renders the kit,
every variant (iso + hero), the cliffs' backs and a game-distance scatter, writes the contact sheet sheet.png and
saves the procedural frost_procedural.blend that frost_bake.py turns into the game asset. In the .blend the
variants stand unrotated in a row along X, 3 m apart (so the AO bake doesn't pick up neighbors); the bake zeroes
their locations before the export.

Game contract (game/locations/scatter_type.gd): a ScatterType draws ONE mesh many times (random scale, tilt,
sink), so every variant is one mesh object, its origin at the ground contact point (bottom center), sitting on
z = 0 with extra geometry below ground (SINK) so tilted or sunk instances don't float. Cliffs face -Y (toward the
camera side) with a flat back at y = +CLIFF_BACK. Budgets (TBD (playtest)): small pieces and boulders <= ~800
triangles, the pinnacle and the cliffs <= ~2.5k.

Modeling: a variant is one or more shells, each a union (boolean, manifold solver) of convex chunks (convex hulls
of jittered points shaved by random plane cuts: big flat fracture facets, sharp ridges) minus thin cutters
(cracks, chips). Each shell is of one stuff: rock, ice, snow or wood, its material slot; rock and ice shells may
overlap (the ice of the pinnacle grows out of its rock). The bake turns the four procedural materials into the
kit's one material. A random per-face "facet" attribute gives each fracture plane its own tone.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "frost"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import common as C
from common import T, rx, ry, rz
from rock_geo import (
    add_boolean,
    bm_to_obj,
    chip_cutter,
    chunk,
    column,
    crack_cutter,
    cut,
    hull,
    place,
    rand_rot,
    uv_to_xy,
    work_collection,
)

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "f0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit_iso", "kit_hero"]

ASSET = "Frost"
# Geometry kept below z = 0 per kind (m), so random tilt / sink in the game never shows the bottom.
SINK = {"Boulder": 0.18, "Ice": 0.15, "Pinnacle": 0.35, "Drift": 0.06, "Shrub": 0.05, "Rubble": 0.06, "Cliff": 0.45}
CLIFF_BACK = 1.0  # cliffs: flat back plane at y = +1 m, rock face toward -Y
SHARP_DEG = 32.0  # edges sharper than this split the shading (fracture ridges); softer ones shade smooth
ROCK, ICE, SNOW, WOOD = range(4)  # material slots (one procedural material per stuff)
VARIANTS = [
    "Boulder_a",
    "Boulder_b",
    "Ice_a",
    "Ice_b",
    "Pinnacle_a",
    "Drift_a",
    "Shrub_a",
    "Rubble_a",
    "Cliff_a",
    "Cliff_b",
]

# Approximate linear albedo of the frost ground (frost_ground_albedo: blue-grey snow, sRGB about 0.5).
GROUND = ((0.16, 0.185, 0.225), (0.25, 0.28, 0.33))

# --- math helpers (T, rx/ry/rz: common) ---------------------------------------------------------------


def lean(direction_deg: float, deg: float) -> Matrix:
    """Rotation that tilts +Z by `deg` towards the horizontal direction `direction_deg`."""
    a = math.radians(direction_deg)
    axis = Vector((-math.sin(a), math.cos(a), 0.0))
    return Matrix.Rotation(math.radians(deg), 3, axis)


# --- chunk builder (convex fracture pieces) ----------------------------------------------------------


def shard(rnd: random.Random, length: float, width: float, thick: float, m: Matrix) -> bmesh.types.BMesh:
    """Ice shard: a flat, pointed slab along +Z (from z = 0 to `length`), broken across at its foot."""
    pts = []
    for i in range(5):
        a = i / 5 * math.tau + rnd.uniform(-0.3, 0.3)
        pts.append(Vector((math.cos(a) * width / 2, math.sin(a) * thick / 2, rnd.uniform(-0.02, 0.05) * length)))
    for i in range(3):
        a = i / 3 * math.tau + rnd.uniform(-0.4, 0.4)
        z = length * rnd.uniform(0.55, 0.7)
        pts.append(Vector((math.cos(a) * width * 0.32, math.sin(a) * thick * 0.35, z)))
    pts.append(Vector((rnd.uniform(-0.1, 0.1) * width, 0.0, length)))
    bm = hull(pts)
    cut(bm, (rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0.6), rnd.uniform(0.86, 0.95))
    return place(bm, m)


# --- shells and variants -----------------------------------------------------------------------------


def shell(name: str, parts: list, cutters: list = ()) -> bmesh.types.BMesh:
    """Union of the convex parts minus the cutters (booleans), as a cleaned-up bmesh."""
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
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.004)
    bmesh.ops.dissolve_degenerate(bm, dist=0.003, edges=bm.edges[:])
    return bm


def merge(dst: bmesh.types.BMesh, src: bmesh.types.BMesh, slot: int | None) -> None:
    """Copy `src`'s faces into `dst` with material slot `slot` (None: keep each face's own slot) as a separate
    shell; frees `src`."""
    vmap = {v: dst.verts.new(v.co) for v in src.verts}
    for f in src.faces:
        nf = dst.faces.new([vmap[v] for v in f.verts])
        nf.material_index = f.material_index if slot is None else slot
    src.free()


def solid(
    name: str,
    kind: str,
    shells: list,
    center_y: bool = True,
    back_y: float | None = None,
    sharp: float = SHARP_DEG,
    dissolve: bool = True,
) -> bpy.types.Object:
    """One variant from its shells [(bmesh, slot)]: bottom cut flat at -SINK, origin at the bottom center, sharp
    edges split; returns the object in the asset collection."""
    bm = bmesh.new()
    for part, slot in shells:
        merge(bm, part, slot)
    cut(bm, (0, 0, -1), at=SINK[kind])  # flat bottom at z = -SINK (normal points down: keeps what's above)
    if back_y is not None:
        cut(bm, (0, 1, 0), at=back_y)
    if dissolve:  # merge the coplanar triangles the hulls and booleans leave on the big facets (fewer triangles)
        bmesh.ops.dissolve_limit(
            bm, angle_limit=math.radians(2.0), verts=bm.verts[:], edges=bm.edges[:], delimit={"MATERIAL"}
        )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), 0))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), 0))
    shift = -(lo + hi) / 2
    if not center_y:
        shift.y = 0
    bmesh.ops.translate(bm, vec=shift, verts=bm.verts[:])
    limit = math.radians(sharp)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    rnd = random.Random(name)
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", [rnd.random() for _ in me.polygons])
    for mat in MATS:
        me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    C.link(obj, ROOT_OBJ)
    return obj


def boulder_a() -> bpy.types.Object:
    """Blocky dark rock with a broad, slightly tilted top (it holds the snow cap), a smaller block wedged against
    it, chipped ridges and a crack."""
    rnd = random.Random(101)
    main = chunk(rnd, (1.3, 1.1, 1.35), 7, T((0, 0, 0.5), rz(15)), keep=(0.7, 0.88), jitter=0.2, extra=12)
    cut(main, (0.18, -0.12, 1.0), 0.9)  # the snow-holding top
    side = chunk(rnd, (0.8, 0.7, 0.66), 4, T((0.62, -0.42, 0.14), rz(-25) @ ry(14)), keep=(0.72, 0.9))
    back = chunk(rnd, (0.7, 0.6, 0.85), 4, T((-0.5, 0.42, 0.25), rz(40) @ rx(-12)), keep=(0.72, 0.9))
    cutters = [
        chip_cutter(rnd, main, (0.6, -0.5, 0.7), 0.32),
        chip_cutter(rnd, main, (-0.7, 0.4, 0.6), 0.28),
        chip_cutter(rnd, main, (0.2, 0.8, 0.5), 0.3),
        crack_cutter(rnd, (-0.1, -0.55, 0.5), 1.3, 0.9, 0.05, rz(8) @ rx(-10) @ ry(22)),
        crack_cutter(rnd, (0.5, 0.0, 0.8), 1.0, 0.9, 0.04, rz(95) @ ry(-15)),
    ]
    return solid("Boulder_a", "Boulder", [(shell("Boulder_a", [main, side, back], cutters), ROCK)])


def boulder_b() -> bpy.types.Object:
    """Tall wedge: an upright, cracked block with a steep fractured top and a fallen piece at its foot."""
    rnd = random.Random(202)
    body = column(
        rnd, 0.55, 1.75, sides=5, depth=0.48, taper=0.75, top_tilt=0.9, cuts=2, m=T((0, 0, -0.18), ry(7) @ rz(20))
    )
    foot = chunk(rnd, (0.7, 0.55, 0.45), 3, T((0.5, -0.3, 0.02), rz(30) @ ry(-18)))
    ledge = chunk(rnd, (0.55, 0.5, 0.35), 3, T((-0.38, -0.2, 0.55), rz(-10) @ ry(10)), keep=(0.8, 0.92))
    cutters = [
        crack_cutter(rnd, (0.0, -0.45, 0.95), 1.4, 0.7, 0.05, rz(12) @ ry(-14)),
        chip_cutter(rnd, body, (-0.5, -0.6, 0.4), 0.28),
        chip_cutter(rnd, body, (0.6, 0.4, 0.9), 0.3),
    ]
    return solid("Boulder_b", "Boulder", [(shell("Boulder_b", [body, foot, ledge], cutters), ROCK)])


def ice_a() -> bpy.types.Object:
    """Ice block: a dense, roughly cubic chunk of clear ice with big sharp fracture faces, a broken wedge leaning on
    it and chipped corners."""
    rnd = random.Random(303)
    block = chunk(rnd, (1.1, 0.95, 0.9), 6, T((0, 0, 0.3), rz(10) @ rx(6)), keep=(0.74, 0.92), jitter=0.12, extra=4)
    wedge = chunk(rnd, (0.6, 0.45, 0.5), 3, T((-0.55, -0.28, 0.08), rz(-35) @ ry(-25)), keep=(0.7, 0.88))
    cut(block, (1.0, -1.0, 0.9), 0.86)  # sheared-off corners
    cut(block, (-0.6, 0.7, 0.8), 0.88)
    cutters = []
    cutters.append(crack_cutter(rnd, (0.1, -0.5, 0.45), 1.2, 0.6, 0.03, rz(-15) @ ry(30)))
    return solid("Ice_a", "Ice", [(shell("Ice_a", [block, wedge], cutters), ICE)])


def ice_b() -> bpy.types.Object:
    """Pressure ridge: broken ice plates pushed up against each other, their edges snapped off."""
    rnd = random.Random(404)
    plates = []
    for x, y, yaw, tilt, size in (
        (-0.32, 0.05, 8, 34, (0.95, 0.24, 1.15)),
        (0.3, -0.05, -14, -30, (0.85, 0.22, 1.0)),
        (0.02, 0.3, 80, 18, (0.7, 0.2, 0.75)),
    ):
        bm = chunk(rnd, size, 0, T((0, 0, size[2] / 2 - 0.15)), jitter=0.05, extra=0)
        cut(bm, (rnd.uniform(-0.6, 0.6), rnd.uniform(-0.3, 0.3), 1.0), rnd.uniform(0.82, 0.92))  # snapped top
        cut(bm, (rnd.choice((-1, 1)), 0.0, rnd.uniform(0.2, 0.8)), rnd.uniform(0.84, 0.94))
        plates.append(place(bm, T((x, y, 0.0), rz(yaw) @ ry(tilt))))
    for _ in range(2):  # loose blocks at the foot
        a = rnd.uniform(0, math.tau)
        p = (math.cos(a) * 0.65, math.sin(a) * 0.45, 0.0)
        plates.append(chunk(rnd, (0.36, 0.3, 0.26), 3, T(p, rand_rot(rnd, 25)), keep=(0.7, 0.88)))
    cutters = [chip_cutter(rnd, plates[0], (-0.4, -0.5, 1.0), 0.22)]
    return solid("Ice_b", "Ice", [(shell("Ice_b", plates, cutters), ICE)])


def pinnacle_a() -> bpy.types.Object:
    """Leaning pinnacle: a dark rock column with a massive ice spire grown up its windward side and over its top,
    ice shards splaying at its foot."""
    rnd = random.Random(505)
    s = SINK["Pinnacle"]
    rock = column(
        rnd, 0.6, 1.8 + s, sides=6, depth=0.52, taper=0.75, top_tilt=0.7, cuts=2, m=T((0.15, 0, -s), lean(200, 8))
    )
    foot = chunk(rnd, (0.6, 0.5, 0.45), 3, T((0.5, -0.35, 0.0), rz(25) @ ry(-12)))
    cutters = [
        crack_cutter(rnd, (0.15, -0.45, 0.9), 1.3, 0.8, 0.06, rz(10) @ ry(-12)),
        crack_cutter(rnd, (0.15, -0.45, 1.35), 1.1, 0.8, 0.05, rz(-20) @ ry(8)),
        chip_cutter(rnd, rock, (0.6, -0.4, 0.5), 0.32),
    ]
    rock_shell = shell("Pinnacle_rock", [rock, foot], cutters)
    spire = column(
        rnd, 0.58, 3.75 + s, sides=5, depth=0.48, taper=0.28, top_tilt=1.3, cuts=2, m=T((-0.2, 0.08, -s), lean(195, 9))
    )
    side = column(
        rnd, 0.36, 2.3 + s, sides=5, depth=0.26, taper=0.3, top_tilt=1.6, cuts=1, m=T((-0.3, 0.42, -s), lean(120, 15))
    )
    shards = []
    for ang, length in ((30, 0.85), (150, 1.25), (235, 0.9), (300, 0.7)):
        out = Vector((math.cos(math.radians(ang)), math.sin(math.radians(ang)), 0))
        m = T(out * 0.42 + Vector((0, 0, -0.15)), lean(ang, rnd.uniform(15, 28)) @ rz(ang + 90))
        shards.append(shard(rnd, length, rnd.uniform(0.3, 0.4), rnd.uniform(0.16, 0.22), m))
    ice_shell = shell("Pinnacle_ice", [spire, side, *shards])
    return solid("Pinnacle_a", "Pinnacle", [(rock_shell, ROCK), (ice_shell, ICE)])


def smooth01(x: float) -> float:
    """Smoothstep from 0 to 1 over 0..1 (clamped)."""
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def drift_a() -> bpy.types.Object:
    """Wind-carved snow drift: a long low tongue with a gently rising windward face, a soft crest and a steeper lee
    side, tapering into a tail downwind. Every edge runs out flat (zero slope at the toe) and sinks into the ground,
    so it blends into the snow around it instead of showing an outline."""
    length, width, height = 3.0, 1.2, 0.36
    nx, ny = 26, 12
    seed = Vector((3.1, 7.7, 1.3))
    bm = bmesh.new()
    grid = []
    for i in range(nx + 1):
        t = i / nx  # 0 at the head (upwind, -X) .. 1 at the tail
        along = smooth01(t / 0.3) * (1.0 - smooth01((t - 0.3) / 0.7))
        half = width / 2 * (0.6 + 0.4 * smooth01(t / 0.3)) * (1.0 - 0.5 * t)
        crest = 0.15 + 0.08 * math.sin(t * 5.0)  # crest line offset towards the lee (+Y), in half widths
        row = []
        for j in range(ny + 1):
            u = j / ny * 2.0 - 1.0  # -1 windward edge .. 1 lee edge
            if u <= crest:
                cross = 1.0 - (1.0 - (u + 1.0) / (crest + 1.0)) ** 1.6  # long gentle windward face
                cross *= smooth01((u + 1.0) / 0.5)  # flat toe
            else:
                cross = (1.0 - (u - crest) / (1.0 - crest)) ** 2.0  # zero slope at the lee toe
            x = -length / 2 + t * length
            y = u * half
            p = Vector((x, y, 0))
            scallop = 1.0 + 0.08 * noise.noise(p * 2.2 + seed)
            z = height * along * cross * scallop - 0.02  # the toe sinks into the ground
            if j in (0, ny) or i in (0, nx):
                z = -0.05
            row.append(bm.verts.new((x, y + 0.04 * noise.noise(p * 3.0 + seed), z)))
        grid.append(row)
    for i in range(nx):
        for j in range(ny):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bm.faces[0].normal.z < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    return solid("Drift_a", "Drift", [(bm, SNOW)], sharp=60.0, dissolve=False)


def tube(bm: bmesh.types.BMesh, pts: list, radii: list, sides: int, slot: int) -> None:
    """A closed twig along `pts` (radius per point, the last point a tip), `sides` faces around."""
    rings = []
    for i in range(len(pts) - 1):
        d = (pts[i + 1] - pts[i]).normalized() if i == 0 else (pts[i + 1] - pts[i - 1]).normalized()
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(d)
        rings.append(
            [
                bm.verts.new(pts[i] + (side * math.cos(a) + up * math.sin(a)) * radii[i])
                for a in (k / sides * math.tau for k in range(sides))
            ]
        )
    for a, b in itertools.pairwise(rings):
        for k in range(sides):
            f = bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
            f.material_index = slot
    tip = bm.verts.new(pts[-1])
    for k in range(sides):
        f = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], tip))
        f.material_index = slot
    f = bm.faces.new(list(reversed(rings[0])))
    f.material_index = slot


def crystal(bm: bmesh.types.BMesh, at: Vector, direction: Vector, size: float, rnd: random.Random) -> None:
    """Ice crystal: a four-sided bipyramid pointing along `direction` (8 triangles)."""
    d = direction.normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d)
    mid = at + d * size * 0.35
    spin = rnd.uniform(0, math.tau)
    ring = [
        bm.verts.new(
            mid + (side * math.cos(spin + k * math.pi / 2) + up * math.sin(spin + k * math.pi / 2)) * size * 0.1
        )
        for k in range(4)
    ]
    tip, base = bm.verts.new(at + d * size * 1.2), bm.verts.new(at - d * size * 0.1)
    for k in range(4):
        bm.faces.new((ring[k], ring[(k + 1) % 4], tip)).material_index = ICE
        bm.faces.new((ring[(k + 1) % 4], ring[k], base)).material_index = ICE


def shrub_a() -> bpy.types.Object:
    """Frozen dead shrub: a few gnarled stems forking into stiff twigs, coated in rime, ice crystals grown on the
    twig ends and forks."""
    rnd = random.Random(606)
    bm = bmesh.new()
    tips: list = []

    def branch(start: Vector, direction: Vector, length: float, radius: float, level: int) -> None:
        segs = (3, 2, 1)[level]
        pts = [start]
        d = direction.normalized()
        for _ in range(segs):
            d = (d + Vector((rnd.gauss(0, 0.25), rnd.gauss(0, 0.25), rnd.gauss(0.05, 0.12)))).normalized()
            pts.append(pts[-1] + d * length / segs)
        radii = [radius * 1.3 * (1.0 - 0.6 * i / segs) for i in range(segs + 1)]
        tube(bm, pts, radii, 4 if level == 0 else 3, WOOD)
        if level >= 2:
            tips.append((pts[-1], d))
            return
        for k in range(1 if level == 0 else 2):
            i = rnd.randint(1, segs - 1) if segs > 2 else 1
            a = rnd.uniform(0, math.tau)
            out = Vector((math.cos(a), math.sin(a), 0.0))
            child = (d * 0.6 + out * rnd.uniform(0.5, 0.9) + Vector((0, 0, 0.25))).normalized()
            branch(pts[i], child, length * rnd.uniform(0.5, 0.7), radii[i] * 0.75, level + 1)
        branch(pts[-1], d + Vector((rnd.gauss(0, 0.3), rnd.gauss(0, 0.3), 0.2)), length * 0.6, radii[-1], level + 1)

    stems = 5
    for k in range(stems):
        a = k / stems * math.tau + rnd.uniform(-0.4, 0.4)
        out = Vector((math.cos(a), math.sin(a), 0.0))
        base = out * rnd.uniform(0.04, 0.12) + Vector((0, 0, -0.06))
        direction = out * rnd.uniform(0.7, 1.2) + Vector((0, 0, 1.0))
        branch(base, direction, rnd.uniform(0.4, 0.55), rnd.uniform(0.026, 0.034), 0)
    for at, d in tips[::2]:  # needles of hoarfrost on every other twig end
        for _ in range(rnd.choice((2, 3))):
            spread = Vector((rnd.gauss(0, 0.6), rnd.gauss(0, 0.6), rnd.gauss(0.3, 0.3)))
            crystal(bm, at, d + spread, rnd.uniform(0.06, 0.1), rnd)
    return solid("Shrub_a", "Shrub", [(bm, None)], sharp=80.0, dissolve=False)


def rubble_a() -> bpy.types.Object:
    """A cluster of small frost-covered dark stones and broken ice shards, half buried."""
    rnd = random.Random(707)
    stones, spots = [], []
    for i in range(6):
        s = 0.34 - 0.22 * (i / 5) * rnd.uniform(0.8, 1.0)
        for _ in range(40):  # keep the stones apart
            a = rnd.uniform(0, math.tau)
            r = 0.42 * math.sqrt(rnd.random()) * (0.3 if i == 0 else 1.0)
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
            if all((p - q).length > (s + t) * 0.45 for q, t in spots):
                break
        spots.append((p, s))
        h = s * rnd.uniform(0.45, 0.75)
        m = T((p.x, p.y, h * rnd.uniform(0.1, 0.25)), rand_rot(rnd, 25))
        stones.append(chunk(rnd, (s, s * rnd.uniform(0.6, 0.9), h), 2, m, keep=(0.65, 0.85), extra=3))
    ice = []
    for _ in range(5):
        for _ in range(40):
            a = rnd.uniform(0, math.tau)
            r = rnd.uniform(0.15, 0.5)
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
            if all((p - q).length > (0.12 + t) * 0.45 for q, t in spots):
                break
        spots.append((p, 0.12))
        if rnd.random() < 0.5:
            m = T((p.x, p.y, -0.05), lean(rnd.uniform(0, 360), rnd.uniform(30, 60)) @ rz(rnd.uniform(0, 360)))
            ice.append(shard(rnd, rnd.uniform(0.22, 0.32), rnd.uniform(0.1, 0.16), rnd.uniform(0.05, 0.08), m))
        else:
            size = (rnd.uniform(0.14, 0.2), rnd.uniform(0.1, 0.16), rnd.uniform(0.08, 0.12))
            ice.append(chunk(rnd, size, 3, T((p.x, p.y, 0.02), rand_rot(rnd, 30)), keep=(0.7, 0.88), extra=2))
    shells = [(shell("Rubble_rock", stones), ROCK), (shell("Rubble_ice", ice), ICE)]
    return solid("Rubble_a", "Rubble", shells)


def cliff_a() -> bpy.types.Object:
    """Layered cliff face: level strata of uneven thickness, each set back or jutting out, with jagged faceted
    fronts and flat, up-facing ledges (where the snow lies), a few vertical joints and a broken top; flat back."""
    rnd = random.Random(808)
    s = SINK["Cliff"]
    parts, z, layer = [], -s, 0
    while z < 4.6:
        th = 0.8 + s if layer == 0 else (rnd.uniform(0.35, 0.55) if rnd.random() < 0.4 else rnd.uniform(0.65, 1.1))
        set_back = rnd.uniform(-0.15, 0.15) + 0.1 * layer  # upper strata recede: a cliff, not a stack
        cuts_x = sorted(rnd.uniform(-2.2, 2.2) for _ in range(rnd.choice((0, 1, 1, 2))))
        edges = [-3.1, *cuts_x, 3.1]
        spans = [
            (edges[i] - (0.1 if i else 0), edges[i + 1] + (0.1 if i + 2 < len(edges) else 0))
            for i in range(len(edges) - 1)
        ]
        for x0, x1 in spans:
            front = -1.0 + set_back + rnd.uniform(-0.18, 0.18)
            last = z + th >= 4.6
            top = z + th + (rnd.uniform(-0.3, 0.3) if last else 0.0)
            z0 = z - 0.15 if layer else z  # overlap the layer below: no floating strata
            depth = CLIFF_BACK + 0.15 - front
            m = T(
                ((x0 + x1) / 2, front + depth / 2, (z0 + top) / 2),
                rz(rnd.uniform(-3, 3)) @ ry(rnd.uniform(-1.2, 1.2)),
            )
            bm = chunk(rnd, (x1 - x0, depth, top - z0), 0, m, jitter=0.03, extra=0)
            for _ in range(rnd.randint(3, 5)):  # jagged front: facets at varied angles
                cut(bm, (rnd.uniform(-1.0, 1.0), -1.0, rnd.uniform(-0.4, 0.4)), rnd.uniform(0.88, 0.97))
            if last:  # broken top
                for _ in range(2):
                    cut(bm, (rnd.uniform(-1.0, 1.0), rnd.uniform(-0.6, 0.2), 1.0), rnd.uniform(0.8, 0.92))
            cut(bm, (rnd.uniform(-0.2, 0.2), -1.0, rnd.uniform(0.9, 1.6)), rnd.uniform(0.86, 0.94))  # ledge bevel
            if rnd.random() < 0.7:
                cut(bm, (rnd.uniform(-0.4, 0.4), -1.0, rnd.uniform(-0.8, -0.3)), rnd.uniform(0.84, 0.94))  # undercut
            parts.append(bm)
        z += th
        layer += 1
    for _ in range(3):  # fallen blocks at the foot
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.25, -0.95), rnd.uniform(-0.05, 0.1))
        parts.append(
            chunk(
                rnd, (rnd.uniform(0.6, 1.0), rnd.uniform(0.5, 0.8), rnd.uniform(0.35, 0.55)), 4, T(p, rand_rot(rnd, 25))
            )
        )
    cutters = [
        chip_cutter(
            rnd, parts[rnd.randrange(len(parts) - 3)], (rnd.uniform(-0.6, 0.6), -0.7, 0.8), rnd.uniform(0.4, 0.6)
        )
        for _ in range(4)
    ]
    for _ in range(3):  # vertical joints
        cutters.append(
            crack_cutter(
                rnd,
                (rnd.uniform(-2.5, 2.5), -1.1, rnd.uniform(1.0, 3.5)),
                2.0,
                1.2,
                0.07,
                ry(90 + rnd.uniform(-10, 10)),
            )
        )
    rock = shell("Cliff_a", parts, cutters)
    return solid("Cliff_a", "Cliff", [(rock, ROCK)], center_y=False, back_y=CLIFF_BACK)


def cliff_b() -> bpy.types.Object:
    """Blocky jointed cliff: tall, square-cut blocks of uneven depth and height split by level fracture lines,
    frozen seeps running down two joints as ribbed ice curtains with a cone of ice at their foot; flat back."""
    rnd = random.Random(909)
    s = SINK["Cliff"]
    parts, x = [], -3.1
    seams = []
    while x < 3.1:
        w = rnd.uniform(0.8, 1.4)
        cx = min(x + w / 2, 3.1 - w / 2 + 0.2)
        front = rnd.uniform(-1.05, -0.55)
        depth = CLIFF_BACK + 0.15 - front
        h = rnd.uniform(3.4, 5.2)
        bm = chunk(rnd, (w * 1.05, depth, h + s), 0, T((cx, front + depth / 2, (h - s) / 2)), jitter=0.04, extra=0)
        cut(bm, (rnd.uniform(-0.6, 0.6), rnd.uniform(-0.8, 0.0), 1.0), rnd.uniform(0.9, 0.97))  # broken top
        cut(bm, (rnd.uniform(-0.5, 0.5), -1.0, rnd.uniform(-0.2, 0.3)), rnd.uniform(0.9, 0.97))  # face facet
        parts.append(bm)
        seams.append((x + w * 0.9, front, h))
        x += w * rnd.uniform(0.85, 0.95)
    for _ in range(4):  # fallen blocks at the foot
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.25, -0.95), rnd.uniform(-0.05, 0.1))
        parts.append(
            chunk(
                rnd, (rnd.uniform(0.5, 0.9), rnd.uniform(0.45, 0.7), rnd.uniform(0.35, 0.6)), 3, T(p, rand_rot(rnd, 20))
            )
        )
    cutters = []
    for z in (1.2, 2.3, 3.4):  # level fracture lines
        for _ in range(2):
            cutters.append(
                crack_cutter(
                    rnd,
                    (rnd.uniform(-2.4, 2.4), -1.1, z + rnd.uniform(-0.3, 0.3)),
                    rnd.uniform(1.4, 2.4),
                    1.0,
                    0.07,
                    rz(rnd.uniform(-5, 5)) @ ry(rnd.uniform(-6, 6)),
                )
            )
    for _ in range(3):
        target = parts[rnd.randrange(len(parts) - 4)]
        cutters.append(chip_cutter(rnd, target, (rnd.uniform(-0.5, 0.5), -0.6, 1.0), rnd.uniform(0.4, 0.6)))
    rock = shell("Cliff_b", parts, cutters)
    ice = []
    for sx, front, h in sorted(seams[1:-1], key=lambda t: rnd.random())[:2]:  # two frozen seeps
        top = min(h - 0.4, rnd.uniform(2.6, 3.6))
        for k in range(3):  # ribs of the curtain
            r = rnd.uniform(0.14, 0.22)
            col = column(rnd, r, top + s - k * 0.4, sides=5, depth=r * 0.7, taper=0.55, top_tilt=0.3, cuts=0)
            place(col, T((sx + (k - 1) * 0.22, front - 0.04, -s), rx(180) @ ry(rnd.uniform(-4, 4))))
            place(col, T((0, 0, top - k * 0.4 - s + s)))  # hanging: wide at the top, thin at the bottom
            ice.append(col)
        cone = column(rnd, 0.55, 0.6 + s, sides=6, depth=0.4, taper=0.4, top_tilt=0.4, cuts=1)
        ice.append(place(cone, T((sx, front - 0.1, -s))))
    return solid(
        "Cliff_b", "Cliff", [(rock, ROCK), (shell("Cliff_b_ice", ice), ICE)], center_y=False, back_y=CLIFF_BACK
    )


BUILDERS = {
    "Boulder_a": boulder_a,
    "Boulder_b": boulder_b,
    "Ice_a": ice_a,
    "Ice_b": ice_b,
    "Pinnacle_a": pinnacle_a,
    "Drift_a": drift_a,
    "Shrub_a": shrub_a,
    "Rubble_a": rubble_a,
    "Cliff_a": cliff_a,
    "Cliff_b": cliff_b,
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


def snow_cover(m: Mat, lo: float, hi: float, patchy: float):
    """Snow / rime factor: on faces looking up (normal Z from lo to hi), broken up by noise (`patchy` 0..1)."""
    patches = m.ramp(0.2 + 0.25 * patchy, 0.4 + 0.15 * patchy, m.noise(2.6, 5.0, 0.6))
    return m.math("MULTIPLY", m.ramp(lo, hi, m.up()), patches)


def mat_rock() -> bpy.types.Material:
    """Dark blue-grey fractured rock: per-facet tone, faint strata, chipped lighter ridges, cracks filled with pale
    frost, cavity grime, snow caps on the faces looking up; rough fracture surface, the snow soft and raised."""
    m = Mat("FrostRock")
    warped = m.warped(1.4, 0.35)
    breakup = m.noise(2.2, 4.0, 0.55)
    crack_big = m.math("MULTIPLY", C._voronoi_lines(m.nt, warped, 0.9, 0.03), m.ramp(0.45, 0.6, breakup))
    crack_fine = m.math(
        "MULTIPLY", C._voronoi_lines(m.nt, warped, 3.0, 0.024), m.math("MULTIPLY", m.ramp(0.55, 0.7, breakup), 0.6)
    )
    crack = m.math("MAXIMUM", crack_big, crack_fine)
    tone = m.noise(0.7, 5.0, 0.6)
    base = m.mix(m.ramp(0.3, 0.72, tone), (0.03, 0.034, 0.041), (0.07, 0.076, 0.088))
    base = m.scale(base, m.math("MULTIPLY_ADD", m.facet(), 0.5, 0.75))
    wave = m.nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 1.1
    wave.inputs["Distortion"].default_value = 5.0
    wave.inputs["Detail"].default_value = 3.0
    m.nt.links.new(m.obj, wave.inputs["Vector"])
    base = m.scale(base, m.math("MULTIPLY_ADD", wave.outputs["Fac"], 0.25, 0.85))
    grain = m.noise(38.0, 4.0, 0.7)
    base = m.scale(base, m.math("MULTIPLY_ADD", grain, 0.35, 0.83))
    edge = m.ramp(0.015, 0.09, C._bevel_edge(m.nt, 0.035, m.geo))
    edge = m.math("MULTIPLY", edge, m.ramp(0.3, 0.6, m.noise(9.0, 3.0, 0.6)))
    col = m.mix(edge, base, m.scale(base, 1.7))
    cavity = m.ramp(0.25, 0.95, m.cavity(0.35))
    col = m.mix(m.math("SUBTRACT", 1.0, cavity, clamp=True), col, (0.009, 0.01, 0.012))
    col = m.mix(crack_fine, col, (0.008, 0.009, 0.011))
    frost_col = m.mix(grain, (0.12, 0.15, 0.19), (0.2, 0.24, 0.29))
    col = m.mix(m.math("MULTIPLY", crack_big, 0.75), col, frost_col)
    snow = snow_cover(m, 0.42, 0.65, 0.1)
    snow_col = m.mix(grain, (0.33, 0.37, 0.43), (0.41, 0.45, 0.51))
    snow_col = m.mix(m.math("SUBTRACT", 1.0, cavity, clamp=True), snow_col, (0.17, 0.21, 0.28))
    col = m.mix(snow, col, snow_col)
    rough = m.mixf(tone, 0.8, 0.92)
    rough = m.mixf(edge, rough, 0.72)
    rough = m.mixf(crack_big, rough, 0.4)
    rough = m.mixf(snow, rough, 0.9)
    lumps = m.nt.nodes.new("ShaderNodeTexVoronoi")
    lumps.feature = "SMOOTH_F1"
    lumps.inputs["Scale"].default_value = 3.0
    m.nt.links.new(warped, lumps.inputs["Vector"])
    height = m.math("MULTIPLY", lumps.outputs["Distance"], 0.5)
    height = m.math("ADD", height, m.math("MULTIPLY", grain, 0.25))
    height = m.math("SUBTRACT", height, m.math("MULTIPLY", crack, 0.6))
    height = m.mixf(snow, height, m.math("ADD", m.math("MULTIPLY", grain, 0.08), 0.75))
    return m.out(col, rough, height, 0.5, 0.03)


def mat_ice() -> bpy.types.Material:
    """Dense clear ice (opaque: the game gets no transmission): pale blue, each fracture face its own tone, deeper
    blue in the cracks and hollows, the fracture planes inside drawn as pale lines, white fresh edges, a little
    frost on top; glossy."""
    m = Mat("FrostIce")
    warped = m.warped(1.1, 0.3)
    base = m.mix(m.facet(), (0.22, 0.36, 0.48), (0.34, 0.48, 0.58))
    depth = m.noise(1.3, 3.0, 0.5)
    base = m.mix(m.math("MULTIPLY", m.ramp(0.4, 0.75, depth), 0.5), base, (0.1, 0.2, 0.32))
    inner = m.math("MULTIPLY", C._voronoi_lines(m.nt, warped, 1.6, 0.03), m.ramp(0.35, 0.6, m.noise(2.0, 3.0, 0.5)))
    base = m.mix(m.math("MULTIPLY", inner, 0.75), base, (0.5, 0.6, 0.68))
    bubbles = m.ramp(0.62, 0.7, m.noise(24.0, 2.0, 0.5))
    base = m.mix(m.math("MULTIPLY", bubbles, 0.35), base, (0.42, 0.5, 0.56))
    cavity = m.ramp(0.3, 0.95, m.cavity(0.3))
    col = m.mix(m.math("SUBTRACT", 1.0, cavity, clamp=True), base, (0.025, 0.07, 0.15))
    edge = m.ramp(0.02, 0.1, C._bevel_edge(m.nt, 0.025, m.geo))
    col = m.mix(m.math("MULTIPLY", edge, 0.8), col, (0.6, 0.68, 0.74))
    frost = snow_cover(m, 0.6, 0.9, 0.6)
    col = m.mix(m.math("MULTIPLY", frost, 0.8), col, (0.4, 0.45, 0.52))
    rough = m.mixf(inner, 0.14, 0.26)
    rough = m.mixf(frost, rough, 0.8)
    fine = m.noise(16.0, 3.0, 0.5)
    height = m.math("ADD", m.math("MULTIPLY", fine, 0.15), m.math("MULTIPLY", inner, 0.1))
    height = m.mixf(frost, height, m.math("ADD", m.math("MULTIPLY", fine, 0.2), 0.3))
    return m.out(col, rough, height, 0.25, 0.02)


def mat_snow() -> bpy.types.Material:
    """Wind-packed snow in the frost ground's own tone (frost_ground's snow, linear), barely lighter on the crest,
    faint wind ripples, a hint of blue in its hollows; matte like the ground."""
    m = Mat("FrostSnow")
    tone = m.noise(1.2, 4.0, 0.6)
    col = m.mix(m.ramp(0.35, 0.65, tone), (0.183, 0.214, 0.263), (0.205, 0.238, 0.29))
    grain = m.noise(60.0, 3.0, 0.7)
    col = m.scale(col, m.math("MULTIPLY_ADD", grain, 0.08, 0.96))
    col = m.mix(m.math("MULTIPLY", m.ramp(0.75, 0.98, m.up()), 0.3), col, (0.22, 0.253, 0.305))
    cavity = m.ramp(0.3, 0.95, m.cavity(0.3))
    col = m.mix(m.math("MULTIPLY", m.math("SUBTRACT", 1.0, cavity, clamp=True), 0.5), col, (0.15, 0.175, 0.22))
    wave = m.nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 3.5
    wave.inputs["Distortion"].default_value = 4.0
    wave.inputs["Detail"].default_value = 2.0
    m.nt.links.new(m.obj, wave.inputs["Vector"])
    height = m.math("ADD", m.math("MULTIPLY", wave.outputs["Fac"], 0.3), m.math("MULTIPLY", grain, 0.1))
    return m.out(col, 0.93, height, 0.12, 0.02)


def mat_wood() -> bpy.types.Material:
    """Dead wood under rime: dark grey-brown twigs, the frost settled thick on their upper sides and in tufts."""
    m = Mat("FrostWood")
    bark = m.noise(30.0, 4.0, 0.6)
    col = m.mix(bark, (0.022, 0.02, 0.019), (0.05, 0.045, 0.04))
    rime = m.math("MAXIMUM", snow_cover(m, 0.0, 0.6, 0.0), m.ramp(0.5, 0.6, m.noise(9.0, 3.0, 0.6)))
    col = m.mix(rime, col, m.mix(bark, (0.3, 0.33, 0.39), (0.4, 0.43, 0.49)))
    rough = m.mixf(rime, 0.85, 0.92)
    height = m.math("ADD", m.math("MULTIPLY", bark, 0.3), m.math("MULTIPLY", rime, 0.4))
    return m.out(col, rough, height, 0.4, 0.01)


# --- layout, preview, renders -------------------------------------------------------------------------

# Kit overview positions: (u along screen right, v toward the camera, z rotation). The iso camera looks from
# +X/-Y, so screen right is (+1, +1) and toward the camera is (+1, -1) in Blender XY.
LAYOUT = {
    "Cliff_a": (-3.4, -5.0, 45),
    "Cliff_b": (3.3, -5.0, 45),
    "Pinnacle_a": (-5.6, -0.8, 0),
    "Boulder_a": (-3.0, -0.4, 0),
    "Boulder_b": (-0.8, -0.4, 0),
    "Ice_a": (1.4, -0.4, 0),
    "Ice_b": (3.7, -0.4, 0),
    "Drift_a": (-2.4, 2.8, 30),
    "Shrub_a": (0.6, 2.8, 0),
    "Rubble_a": (2.2, 2.8, 0),
}
FIGURE_UV = (3.8, 2.8)


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


def ground_color() -> None:
    """The preview ground in the frost ground's blue-grey (approximate linear albedo)."""
    lo, hi = GROUND
    C.tint_ground(lo, hi)


def setup_preview() -> None:
    C.preview_scene(crystals=False, pebbles=False)  # the pebbles would read as part of the kit
    ground_color()


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in VARIANTS]


def render_kit(prefix: str, views, samples: int, size: int) -> list:
    apply_layout()
    center = uv_to_xy(0.0, -1.2) + Vector((0, 0, 0.9))
    out = []
    for view in views:
        path = OUT / f"{prefix}kit_{view}.png"
        C.render(
            path, view=view, samples=samples, size=size, target=tuple(center), zoom={"iso": 1.85, "hero": 2.4}[view]
        )
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
        C.render(path, view=view, samples=samples, size=size, target=tuple(target), zoom=zoom)
        out.append(path)
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

    put("Cliff_a", -4.5, 5.0, 1.0, 0, 0, rot=0)
    put("Cliff_b", 1.6, 5.3, 1.0, 0, 0, rot=0)
    put("Pinnacle_a", -6.0, -0.5, 1.0, 3, 0.1)
    put("Pinnacle_a", 5.6, 1.8, 0.85, 3, 0.1)
    spots = [(-2.6, 1.6), (2.6, -1.8), (-3.5, -3.2), (3.9, -4.6), (-0.9, -5.2), (1.3, 2.2), (6.5, -2.0), (-5.6, 2.8)]
    kinds = ["Boulder_a", "Ice_a", "Boulder_b", "Ice_b"]
    for i, (x, y) in enumerate(spots):
        put(kinds[i % 4], x, y, rnd.uniform(0.7, 1.4), 12, 0.1)
    for _ in range(5):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(2.0, 8.0)
        put("Drift_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.8, 1.3), 2, 0.02, rot=rnd.uniform(-20, 20))
    for _ in range(7):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.5, 8.0)
        put("Shrub_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.8, 1.2), 8, 0.02)
    for _ in range(12):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.5, 8.0)
        put("Rubble_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.6, 1.3), 12, 0.03)
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
    MATS = [mat_rock(), mat_ice(), mat_snow(), mat_wood()]
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
        slots = sorted({p.material_index for p in me.polygons})
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(d, 2) for d in obj.dimensions)}"
            f" z=({min(zs):.2f}, {max(zs):.2f}) slots={slots}"
        )
        obj.evaluated_get(dg).to_mesh_clear()
    print("STATS", C.stats())


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
        C.save_blend(OUT / "frost_procedural.blend")
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
                C.save_blend(OUT / "frost_procedural.blend")
                return


if __name__ == "__main__":
    main()
