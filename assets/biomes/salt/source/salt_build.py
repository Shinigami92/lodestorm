"""Salt pans scatter kit: salt-crusted boulders, an eroded salt pillar, halite crystals, a salt-coated dead shrub,
bleached alien bones, broken crust plates and pale evaporite cliff chunks (concepts: batch11 salt, salt_props).

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/salt/source/salt_build.py wip s1                  # kit iso + hero
    tools/blender.sh assets/biomes/salt/source/salt_build.py wip s1 Pillar_a,scatter
    tools/blender.sh assets/biomes/salt/source/salt_build.py final

Everything it writes goes to tmp/assets/salt/: "wip <tag> [views]" renders quick previews into wip/<tag>_*.png
(views: kit_iso, kit_hero, scatter, variants, back, sheet, save, or a part name); "final" renders the kit, every
part (iso + hero), the cliffs' backs and a game-distance scatter, writes the contact sheet sheet.png and saves the
procedural salt_procedural.blend that salt_bake.py turns into the game asset. In the .blend the parts stand
unrotated in a row along X, 3 m apart (so the AO bake doesn't pick up neighbors); the bake zeroes their locations.

Game contract (game/locations/scatter_type.gd): a ScatterType draws ONE mesh many times (random scale, tilt,
sink), so every part is one mesh object with the kit's one material ("Salt"), its origin at the ground contact
point (bottom center), standing on z = 0 with extra geometry below ground (SINK) so tilted or sunk instances don't
float. Cliffs face -Y (toward the camera side) with a flat back at y = +CLIFF_BACK. Budgets (TBD (playtest)):
small pieces and boulders <= ~800 triangles, the pillar and the cliffs <= ~2.5k.

Modeling: rock parts are unions (boolean, manifold solver) of convex chunks (convex hulls of jittered points),
shaved by random plane cuts into big fracture facets, with thin cutters notching cracks and grooves; the shrub and
the bones are tapering tubes. One procedural material covers the whole kit: a per-face "kind" attribute picks the
look (salt-crusted rock, layered evaporite, halite, bone, dead wood, crust plate) and a per-face "facet" value gives
every fracture plane its own tone.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "salt"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
import nodes as N
from common import T, rx, ry, rz, srgb
from rock_geo import (
    add_boolean,
    bm_to_obj,
    box_points,
    chip_cutter,
    chunk,
    column,
    crack_cutter,
    cut,
    hull,
    place,
    rand_dir,
    rand_rot,
    shave,
    work_collection,
)

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "s0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit_iso", "kit_hero"]

ASSET = "Salt"
MATERIAL = "Salt"
# Geometry kept below z = 0 per part (m), so random tilt / sink in the game never shows the bottom.
SINK = {
    "Boulder": 0.2,
    "Pillar": 0.35,
    "Halite": 0.12,
    "Shrub": 0.08,
    "Bones": 0.1,
    "Crust": 0.05,
    "Cliff": 0.45,
}
CLIFF_BACK = 1.0  # cliffs: flat back plane at y = +1 m, rock face toward -Y
SHARP_DEG = 32.0  # edges sharper than this split the shading (fracture ridges); softer ones shade smooth
KINDS = {"rock": 0, "evaporite": 1, "halite": 2, "bone": 3, "wood": 4, "crust": 5}
PARTS = [
    "Boulder_a",
    "Boulder_b",
    "Pillar_a",
    "Halite_a",
    "Shrub_a",
    "Bones_a",
    "Bones_b",
    "Crust_a",
    "Cliff_a",
    "Cliff_b",
]

# --- math helpers (T, rx/ry/rz: common) ---------------------------------------------------------------


# --- chunk builder (convex fracture pieces) ----------------------------------------------------------


def blob_points(rnd: random.Random, size, count: int = 22, jitter: float = 0.08) -> list:
    """Points on an ellipsoid (centered), radii jittered: a rounder hull than box_points."""
    pts = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        z = 1 - 2 * (i + 0.5) / count
        r = math.sqrt(1 - z * z)
        a = i * golden
        k = 1 + rnd.uniform(-jitter, jitter)
        pts.append(Vector((math.cos(a) * r * size[0] / 2 * k, math.sin(a) * r * size[1] / 2 * k, z * size[2] / 2 * k)))
    return pts


def groove_cutter(rnd: random.Random, angle: float, r: float, z: float, height: float, pen: float):
    """A horizontal groove into a round body of radius `r` at height `z`, from the direction `angle` (degrees),
    `pen` m deep: a soft band weathered back."""
    depth = 0.6
    d = Vector((math.cos(math.radians(angle)), math.sin(math.radians(angle)), 0))
    center = d * (r - pen + depth / 2) + Vector((0, 0, z))
    return crack_cutter(rnd, center, r * 1.3, depth, height, rz(angle + 90) @ ry(rnd.uniform(-4, 4)))


def pit_cutter(rnd: random.Random, point: Vector, outward: Vector, size: float) -> bmesh.types.BMesh:
    """A small rounded lump centered just outside `point`: bites a pit into the surface."""
    bm = hull(blob_points(rnd, (size, size * rnd.uniform(0.8, 1.0), size * rnd.uniform(0.6, 0.9)), 12, 0.2))
    return place(bm, T(point + outward * size * 0.15, rand_rot(rnd, 40)))


def skirt(rnd: random.Random, rx_: float, ry_: float, h: float, sides: int = 9, z0: float = -0.15) -> bmesh.types.BMesh:
    """Low lumpy collar (z0 .. h) around a base: the salt crust grown up around a rock's foot."""
    pts = []
    for i in range(sides):
        a = (i + rnd.uniform(-0.3, 0.3)) / sides * math.tau
        k = rnd.uniform(0.9, 1.1)
        pts.append(Vector((math.cos(a) * rx_ * k, math.sin(a) * ry_ * k, z0)))
        pts.append(Vector((math.cos(a) * rx_ * k * 0.78, math.sin(a) * ry_ * k * 0.78, h * rnd.uniform(0.6, 1.2))))
    return hull(pts)


def tube(bm: bmesh.types.BMesh, pts: list, radii: list, sides: int = 5, flat: float = 1.0, cap: bool = True) -> None:
    """A tapering tube along `pts` (radii per point) with `sides` sides, the cross-section squashed by `flat`
    along its second axis; the frame is carried along the path (no twist). Both ends capped."""
    n = len(pts)
    tangent = (pts[1] - pts[0]).normalized()
    ref = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
    u = tangent.cross(ref).normalized()
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        u = (u - t * u.dot(t)).normalized()
        v = t.cross(u)
        ring = []
        for s in range(sides):
            a = s / sides * math.tau
            ring.append(bm.verts.new(p + (u * math.cos(a) + v * math.sin(a) * flat) * radii[i]))
        rings.append(ring)
    for a, b in itertools.pairwise(rings):
        for s in range(sides):
            bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])


def join(parts: list) -> bmesh.types.BMesh:
    """One bmesh holding all `parts` (freed)."""
    me = bpy.data.meshes.new("join_tmp")
    out = bmesh.new()
    for bm in parts:
        bm.to_mesh(me)
        out.from_mesh(me)
        bm.free()
    bpy.data.meshes.remove(me)
    return out


# --- mesh assembly ------------------------------------------------------------------------------------


def boolean(name: str, parts: list, cutters: list = ()) -> bmesh.types.BMesh:
    """Union of the convex parts minus the cutters, as a bmesh."""
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
    return bm


def solid(
    name: str,
    kind: str,
    sink: str,
    parts: list,
    cutters: list = (),
    loose: list = (),
    center_y: bool = True,
    back_y: float | None = None,
    sharp: float = SHARP_DEG,
) -> bpy.types.Object:
    """The finished part: the union of `parts` minus `cutters`, plus `loose` pieces joined without a boolean,
    cleaned up, bottom cut flat at -SINK[sink], origin at the bottom center, one material, the "kind" and "facet"
    attributes."""
    bm = boolean(name, parts, cutters) if parts else bmesh.new()
    if loose:
        extra = join(loose)
        me = bpy.data.meshes.new("loose_tmp")
        extra.to_mesh(me)
        extra.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    finish_mesh(bm, sink, center_y, back_y, sharp)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    face_attributes(me, name, kind)
    obj = bpy.data.objects.new(name, me)
    C.link(obj, ROOT_OBJ)
    C.assign(obj, KIT_MAT)
    return obj


def finish_mesh(bm: bmesh.types.BMesh, sink: str, center_y: bool, back_y: float | None, sharp: float) -> None:
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.003)
    bmesh.ops.dissolve_degenerate(bm, dist=0.002, edges=bm.edges[:])
    cut(bm, (0, 0, -1), at=SINK[sink])  # flat bottom at z = -SINK (normal points down: keeps what's above)
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
    limit = math.radians(sharp)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit)
    for f in bm.faces:
        f.smooth = True


def face_attributes(me: bpy.types.Mesh, seed: str, kind: str) -> None:
    """Per face: "kind" picks the look in the kit material, "facet" (random) gives each plane its own tone."""
    rnd = random.Random(seed)
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", [rnd.random() for _ in me.polygons])
    attr = me.attributes.new("kind", "FLOAT", "FACE")
    attr.data.foreach_set("value", [float(KINDS[kind])] * len(me.polygons))


# --- parts --------------------------------------------------------------------------------------------


def boulder_a() -> bpy.types.Object:
    """Blocky grey rock with a wedge against it, chipped ridges, a crack, and salt crust grown up around its foot."""
    rnd = random.Random(101)
    main = chunk(
        rnd, (1.45, 1.25, 1.35), 5, T((0, 0, 0.5), rz(12)), keep=(0.74, 0.92), jitter=0.18, extra=10, bulge=0.18
    )
    side = chunk(rnd, (0.8, 0.7, 0.7), 3, T((0.62, -0.42, 0.15), rz(-25) @ ry(14)), keep=(0.75, 0.9), jitter=0.15)
    collar = skirt(rnd, 0.95, 0.85, 0.16)
    chips = [chip_cutter(rnd, main, (0.6, -0.5, 0.8), 0.3), chip_cutter(rnd, main, (-0.7, 0.3, 0.6), 0.28)]
    crack = crack_cutter(rnd, (-0.1, -0.55, 0.65), 1.3, 0.9, 0.045, rz(8) @ rx(-10) @ ry(25))
    return solid("Boulder_a", "rock", "Boulder", [main, side, collar], chips + [crack])


def boulder_b() -> bpy.types.Object:
    """Low, rounder grey rock split by a crack, a crust collar and a crusted hollow on top."""
    rnd = random.Random(202)
    body = hull(blob_points(rnd, (1.25, 1.05, 0.85), 26, 0.1))
    shave(body, rnd, 5, (0.8, 0.93), min_z=-0.1)
    place(body, T((0, 0, 0.3), rz(20)))
    cap = chunk(rnd, (0.7, 0.6, 0.4), 3, T((-0.15, 0.1, 0.62), rz(-15) @ rx(8)), keep=(0.75, 0.9))
    collar = skirt(rnd, 0.8, 0.7, 0.14, sides=8)
    hollow = pit_cutter(rnd, Vector((0.2, -0.15, 0.78)), Vector((0, 0, 1)), 0.38)
    crack = crack_cutter(rnd, (0.0, -0.45, 0.45), 1.3, 0.9, 0.05, rz(-30) @ ry(70))
    return solid("Boulder_b", "rock", "Boulder", [body, cap, collar], [hollow, crack])


def pillar_a() -> bpy.types.Object:
    """Tall eroded salt pillar: a flared foot and four stacked layered drums narrowing upward, set off-center from
    each other, horizontal grooves where soft bands weathered back, pits, a broken top and fallen lumps at its foot."""
    rnd = random.Random(303)
    s = SINK["Pillar"]
    drums = [(0.66, 0.6, -s, 1.25), (0.55, 0.5, 0.75, 1.05), (0.47, 0.42, 1.6, 1.0), (0.4, 0.35, 2.4, 1.2)]
    parts, x_off, y_off = [], 0.0, 0.0
    radius = []
    for i, (rx_, ry_, z0, h) in enumerate(drums):
        x_off += rnd.uniform(-0.07, 0.07)
        y_off += rnd.uniform(-0.05, 0.05)
        last = i == len(drums) - 1
        bm = column(rnd, rx_, h, sides=8, depth=ry_, taper=0.9, top_tilt=1.0 if last else 0.2, cuts=2)
        parts.append(place(bm, T((x_off, y_off, z0), rz(rnd.uniform(0, 45)))))
        radius.append((z0 + h, (rx_ + ry_) / 2))
    parts.append(skirt(rnd, 0.95, 0.85, 0.3, sides=10))
    for p in ((0.85, -0.6, 0.05), (-0.8, -0.5, 0.0), (0.2, 0.9, 0.0)):
        parts.append(chunk(rnd, (0.42, 0.36, 0.3), 3, T(p, rand_rot(rnd, 25))))

    def r_at(z: float) -> float:
        return next((r for top, r in radius if z < top - 0.1), radius[-1][1])

    cutters = []
    for z, height in ((0.55, 0.14), (1.0, 0.09), (1.5, 0.16), (2.05, 0.08), (2.45, 0.13), (3.0, 0.1)):
        for k in range(5):
            pen = rnd.uniform(0.06, 0.13)
            cutters.append(groove_cutter(rnd, k * 72 + rnd.uniform(-20, 20), r_at(z), z, height, pen))
    for _ in range(10):
        z = rnd.uniform(0.3, 3.2)
        a = rnd.uniform(0, math.tau)
        out = Vector((math.cos(a), math.sin(a), 0))
        cutters.append(pit_cutter(rnd, out * r_at(z) + Vector((0, 0, z)), out, rnd.uniform(0.14, 0.26)))
    cutters.append(chip_cutter(rnd, parts[3], (0.4, -0.3, 1.0), 0.35))
    return solid("Pillar_a", "evaporite", "Pillar", parts, cutters)


def hopper(rnd: random.Random, size: float, m: Matrix, steps: int = 3) -> tuple[bmesh.types.BMesh, list]:
    """A cubic halite crystal (edge `size`, sitting on z = 0 in its own frame) with shallow stepped hopper terraces
    sunk into its top face: the cube and its cutters, placed by `m`."""
    j = 0.04
    pts = [
        Vector((cx * size / 2, cy * size / 2, (cz + 1) * size / 2))
        + Vector((rnd.uniform(-j, j), rnd.uniform(-j, j), rnd.uniform(-j, j))) * size
        for cx in (-1, 1)
        for cy in (-1, 1)
        for cz in (-1, 1)
    ]
    cube = hull(pts)
    cut(cube, rand_dir(rnd, 0.3, 0.9), rnd.uniform(0.9, 0.96))  # a corner broken off
    cutters = []
    for w, d in ((0.84, 0.035), (0.6, 0.07), (0.36, 0.11))[:steps]:
        step = []
        for cx in (-1, 1):
            for cy in (-1, 1):
                step.append(Vector((cx * size * w / 2, cy * size * w / 2, size * (1 - d))))
                step.append(Vector((cx * size * w / 2, cy * size * w / 2, size * 1.3)))
        cutters.append(place(hull(step), m.copy()))
    return place(cube, m), cutters


def halite_a() -> bpy.types.Object:
    """A cluster of cubic halite crystals grown into and onto each other at all angles: a few big ones with
    shallow stepped hopper terraces, crusted with many small cubes."""
    rnd = random.Random(404)
    parts, cutters = [], []
    crystals = [  # (edge, location, rotation x / y / z degrees)
        (0.46, (0.0, 0.0, -0.14), (12, -8, 10)),
        (0.36, (0.36, 0.16, -0.12), (-24, 14, 35)),
        (0.3, (-0.3, 0.2, -0.08), (20, 26, -20)),
        (0.28, (0.08, 0.06, 0.22), (36, 28, 20)),
    ]
    for _ in range(14):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.2, 0.5)
        size = rnd.uniform(0.08, 0.2)
        z = rnd.uniform(-0.08, 0.32) * (1.0 - r)
        crystals.append(
            (size, (math.cos(a) * r, math.sin(a) * r, z - size * 0.3), tuple(rnd.uniform(-45, 45) for _ in range(3)))
        )
    for i, (size, loc, (ax, ay, az)) in enumerate(crystals):
        m = T(loc, rz(az) @ rx(ax) @ ry(ay))
        cube, cut_steps = hopper(rnd, size, m)
        parts.append(cube)
        if i < 3:
            cutters += cut_steps
        else:
            for bm in cut_steps:
                bm.free()
    return solid("Halite_a", "halite", "Halite", parts, cutters, sharp=40.0)


def shrub_a() -> bpy.types.Object:
    """A dead, brittle shrub: a few gnarled stems fanning out from one root crown, forking into stiff twigs, salt
    crust lumps on the crown and in the forks."""
    rnd = random.Random(505)
    bm = bmesh.new()
    lumps = []

    def branch(base: Vector, direction: Vector, length: float, r0: float, depth: int) -> None:
        steps = 4 if depth == 0 else 3
        pts, radii = [base.copy()], [r0]
        d = direction.normalized()
        p = base.copy()
        for i in range(steps):
            d = (d + Vector((rnd.gauss(0, 0.25), rnd.gauss(0, 0.25), rnd.gauss(0, 0.12)))).normalized()
            p = p + d * length / steps
            pts.append(p.copy())
            radii.append(r0 * (1 - 0.8 * (i + 1) / steps))
        tube(bm, pts, radii, sides=5 if depth == 0 else 4 if depth == 1 else 3)
        if depth >= 2:
            return
        forks = rnd.randint(2, 3) if depth == 0 else rnd.randint(0, 2)
        for _ in range(forks):
            k = rnd.randint(1, steps - 1)
            side = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.uniform(0.2, 1.0)))
            nd = (d * 0.6 + side.normalized() * 0.7).normalized()
            nd.z = max(nd.z, 0.15)
            branch(pts[k], nd, length * rnd.uniform(0.45, 0.65), radii[k] * 0.75, depth + 1)
            if depth == 0 and rnd.random() < 0.7:
                lumps.append((pts[k], radii[k] * 2.2))

    stems = 5
    for i in range(stems):
        a = (i + rnd.uniform(-0.3, 0.3)) / stems * math.tau
        lean = rnd.uniform(0.35, 0.8)
        d = Vector((math.cos(a) * lean, math.sin(a) * lean, 1.0))
        base = Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, -SINK["Shrub"]))
        branch(base, d, rnd.uniform(0.55, 0.75), rnd.uniform(0.03, 0.04), 0)
    crown = hull(blob_points(rnd, (0.22, 0.2, 0.16), 12, 0.25))
    place(crown, T((0, 0, 0.0)))
    loose = [crown]
    for p, r in lumps:
        loose.append(place(hull(blob_points(rnd, (r, r, r * 0.8), 8, 0.25)), T(p)))
    return solid("Shrub_a", "wood", "Shrub", [], loose=[bm, *loose], sharp=75.0)


def rib_path(height: float, half: float, lean: float, segs: int, broken: float = 1.0) -> list:
    """A rib arching from the spine (y = +half, ground) over to the far side (y = -half, into the ground), leaning
    back by `lean` m along X at its top; `broken` < 1 ends it partway."""
    pts = []
    for i in range(segs + 1):
        t = i / segs * broken
        a = math.pi * t
        y = half * math.cos(a)
        z = height * math.sin(a) ** 0.85 - 0.06 - 0.12 * t
        x = -lean * math.sin(a)
        pts.append(Vector((x, y, z)))
    return pts


def bones_a() -> bpy.types.Object:
    """Bleached rib cage of a large alien vertebrate lying on its side, half sunk in the crust: a row of heavy
    vertebrae on a low crust mound, thick flat ribs arching over and back into the salt, two of them broken."""
    rnd = random.Random(606)
    parts, loose = [], []
    spine_y = 0.42
    n = 8
    for i in range(n):
        x = -0.95 + i * 1.9 / (n - 1) + rnd.uniform(-0.03, 0.03)
        k = 1 - 0.35 * abs(i - (n - 1) / 2) / (n / 2)
        size = (0.17 * k, 0.24 * k, 0.2 * k)
        m = T((x, spine_y, 0.03), rz(rnd.uniform(-10, 10)))
        parts.append(chunk(rnd, size, 1, m, jitter=0.12, extra=0, keep=(0.8, 0.9)))
        fin = hull(
            [
                Vector((x - 0.05 * k, spine_y + 0.02, 0.06)),
                Vector((x + 0.05 * k, spine_y + 0.02, 0.06)),
                Vector((x - 0.02, spine_y + 0.26 * k, 0.08 + 0.08 * k)),
                Vector((x + 0.03, spine_y + 0.24 * k, 0.08 + 0.06 * k)),
                Vector((x, spine_y - 0.04, 0.15 * k)),
            ]
        )
        parts.append(fin)
    heights = [0.44, 0.6, 0.7, 0.8, 0.74, 0.64, 0.46]
    for i, h in enumerate(heights):
        x = -0.72 + i * 1.44 / (len(heights) - 1) + rnd.uniform(-0.04, 0.04)
        broken = rnd.uniform(0.5, 0.62) if i in (1, 5) else 1.0
        half = spine_y + 0.02 + rnd.uniform(-0.04, 0.04)
        pts = [p + Vector((x, 0.0, 0.0)) for p in rib_path(h, half, rnd.uniform(0.08, 0.18), 7, broken)]
        r0 = rnd.uniform(0.06, 0.075)
        radii = [r0 * (1 - 0.4 * k / 7) for k in range(len(pts))]
        bm = bmesh.new()
        tube(bm, pts, radii, sides=5, flat=0.6)
        loose.append(bm)
    mound = hull(blob_points(rnd, (2.5, 0.75, 0.3), 18, 0.12))
    place(mound, T((0.0, spine_y + 0.02, -0.1)))
    parts.append(mound)
    return solid("Bones_a", "bone", "Bones", parts, loose=loose, sharp=60.0)


def bones_b() -> bpy.types.Object:
    """An alien skull half sunk in the crust (long heavy cranium with a crest, deep orbits facing up and forward,
    a blunt snout with two short tusks) with its lower jaw, a long bone and two vertebrae scattered beside it."""
    rnd = random.Random(707)
    cranium = hull(blob_points(rnd, (0.66, 0.48, 0.34), 28, 0.05))
    place(cranium, T((0.08, 0.0, 0.14)))
    snout = hull(blob_points(rnd, (0.5, 0.3, 0.2), 16, 0.08))
    shave(snout, rnd, 3, (0.82, 0.93))
    place(snout, T((-0.3, 0.0, 0.11), ry(-8)))
    crest = hull(
        [
            Vector((0.4, 0.0, 0.26)),
            Vector((-0.02, 0.0, 0.3)),
            Vector((0.22, 0.02, 0.37)),
            Vector((0.4, 0.02, 0.33)),
            Vector((0.15, -0.05, 0.26)),
            Vector((0.15, 0.05, 0.26)),
        ]
    )
    tusks = []
    for side in (-1, 1):
        base = Vector((-0.5, side * 0.1, 0.07))
        pts = [base, base + Vector((-0.08, side * 0.03, -0.04)), base + Vector((-0.14, side * 0.06, -0.12))]
        bm = bmesh.new()
        tube(bm, pts, [0.04, 0.03, 0.012], sides=5)
        tusks.append(bm)
    cutters = []
    for side in (-1, 1):
        orbit = hull(blob_points(rnd, (0.2, 0.17, 0.22), 12, 0.08))
        cutters.append(place(orbit, T((-0.06, side * 0.16, 0.24))))
    cutters.append(place(hull(box_points(rnd, (0.12, 0.09, 0.1), 0.1, 2)), T((-0.52, 0.0, 0.18), ry(-30))))
    skull = boolean("Bones_b_skull", [cranium, snout, crest, *tusks], cutters)
    place(skull, T((0.0, 0.1, -0.05), rz(25) @ rx(-8), (1.15, 1.15, 1.15)))
    # Lower jaw: a blunt V of two flat bars, lying tipped over beside the skull.
    jaw = bmesh.new()
    for side in (-1, 1):
        pts = [Vector((0.34, side * 0.2, 0.04)), Vector((0.05, side * 0.17, 0.03)), Vector((-0.26, side * 0.05, 0.03))]
        tube(jaw, pts, [0.06, 0.05, 0.05], sides=5, flat=0.6)
    place(jaw, T((-0.1, -0.5, 0.0), rz(-40)))
    long_bone = bmesh.new()
    tube(long_bone, [Vector((x, 0.0, 0.03)) for x in (-0.34, -0.1, 0.12, 0.36)], [0.055, 0.04, 0.04, 0.055], sides=6)
    ends = [hull(blob_points(rnd, (0.15, 0.13, 0.11), 10, 0.15)) for _ in range(2)]
    place(ends[0], T((-0.37, 0.0, 0.03)))
    place(ends[1], T((0.39, 0.0, 0.03)))
    bone_group = join([long_bone, *ends])
    place(bone_group, T((0.45, -0.4, 0.0), rz(70) @ ry(4)))
    verts = []
    for p in ((0.6, 0.35, 0.02), (-0.55, 0.5, 0.0)):
        verts.append(chunk(rnd, (0.16, 0.19, 0.15), 2, T(p, rand_rot(rnd, 30)), jitter=0.1, extra=2))
    return solid("Bones_b", "bone", "Bones", [], loose=[skull, jaw, bone_group, *verts], sharp=55.0)


def crust_a() -> bpy.types.Object:
    """A patch of broken salt crust with a ragged outline: polygonal plates (a disk split into cells, the outer
    ones broken off short), some pushed up against each other along a pressure ridge, others sunk, a few loose
    fragments."""
    rnd = random.Random(808)
    seeds = [Vector((0, 0, 0))]
    while len(seeds) < 8:
        a, r = rnd.uniform(0, math.tau), rnd.uniform(0.3, 0.7)
        p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        if all((p - q).length > 0.32 for q in seeds):
            seeds.append(p)
    plates = []
    ridge_dir = Vector((1, 0.3, 0)).normalized()
    across = ridge_dir.cross(Vector((0, 0, 1)))
    for i, c in enumerate(seeds):
        pts = []
        for k in range(10):
            a = k / 10 * math.tau
            rr = 0.85 * rnd.uniform(0.92, 1.05)
            pts += [Vector((math.cos(a) * rr, math.sin(a) * rr, z)) for z in (-0.05, 0.035)]
        bm = hull(pts)
        for j, o in enumerate(seeds):
            if j != i:
                n = (o - c).normalized()
                cut(bm, n, at=((o + c) / 2).dot(n) - rnd.uniform(0.012, 0.03))
        if i:  # outer plates: broken off short of the disk's edge
            out = (c.normalized() + Vector((rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), 0))).normalized()
            cut(bm, out, at=c.dot(out) + rnd.uniform(0.12, 0.3))
        center = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        center.z = 0
        side = across.dot(c)
        if i and abs(side) < 0.5:  # beside the ridge line: tilted up toward it
            axis, angle, lift = ridge_dir.copy(), math.copysign(rnd.uniform(16, 32), side), rnd.uniform(0.04, 0.08)
        else:
            axis = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)).normalized()
            angle, lift = rnd.uniform(-7, 7), rnd.uniform(-0.02, 0.01)
        m = T(center + Vector((0, 0, lift))) @ Matrix.Rotation(math.radians(angle), 4, axis) @ T(-center)
        plates.append(place(bm, m))
    for _ in range(6):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(0.5, 0.9)
        size = rnd.uniform(0.08, 0.16)
        m = T((math.cos(a) * r, math.sin(a) * r, 0.0), rand_rot(rnd, 30))
        plates.append(chunk(rnd, (size, size * 0.8, 0.04), 1, m))
    return solid("Crust_a", "crust", "Crust", [], loose=plates, sharp=40.0)


def cliff_a() -> bpy.types.Object:
    """Layered evaporite cliff: many thin strata, the hard ones jutting out with jagged fronts, the soft ones
    weathered back into deep grooves, a broken top; flat back."""
    rnd = random.Random(909)
    s = SINK["Cliff"]
    parts, z, layer = [], -s, 0
    while z < 4.4:
        soft = layer > 0 and rnd.random() < 0.4
        th = 0.75 + s if layer == 0 else (rnd.uniform(0.18, 0.32) if soft else rnd.uniform(0.35, 0.8))
        if z + th > 4.1:
            th = 4.45 - z
        set_back = (0.25 if soft else rnd.uniform(-0.12, 0.12)) + 0.07 * layer
        cuts_x = sorted(rnd.uniform(-2.2, 2.2) for _ in range(0 if soft else rnd.choice((0, 1, 1, 2))))
        edges = [-3.1, *cuts_x, 3.1]
        spans = [
            (edges[i] - (0.1 if i else 0), edges[i + 1] + (0.1 if i + 2 < len(edges) else 0))
            for i in range(len(edges) - 1)
        ]
        for x0, x1 in spans:
            front = -1.0 + set_back + rnd.uniform(-0.15, 0.15)
            last = z + th >= 4.4
            top = z + th + (rnd.uniform(-0.3, 0.2) if last else 0.0)
            z0 = z - 0.12 if layer else z
            depth = CLIFF_BACK + 0.15 - front
            m = T(((x0 + x1) / 2, front + depth / 2, (z0 + top) / 2), rz(rnd.uniform(-2, 2)) @ ry(rnd.uniform(-1, 1)))
            bm = chunk(rnd, (x1 - x0, depth, top - z0), 0, m, jitter=0.02, extra=0)
            if not soft:
                for _ in range(rnd.randint(3, 5)):
                    cut(bm, (rnd.uniform(-1.0, 1.0), -1.0, rnd.uniform(-0.4, 0.4)), rnd.uniform(0.9, 0.97))
                cut(bm, (rnd.uniform(-0.3, 0.3), -1.0, rnd.uniform(0.6, 1.2)), rnd.uniform(0.86, 0.94))
            if last:
                for _ in range(2):
                    cut(bm, (rnd.uniform(-1.0, 1.0), rnd.uniform(-0.6, 0.2), 1.0), rnd.uniform(0.8, 0.92))
            parts.append(bm)
        z += th
        layer += 1
    for _ in range(4):
        p = (rnd.uniform(-2.6, 2.6), rnd.uniform(-1.3, -1.0), rnd.uniform(-0.05, 0.08))
        size = (rnd.uniform(0.45, 0.9), rnd.uniform(0.4, 0.7), rnd.uniform(0.25, 0.45))
        parts.append(chunk(rnd, size, 4, T(p, rand_rot(rnd, 25))))
    cutters = [
        chip_cutter(rnd, parts[rnd.randrange(len(parts) - 4)], (rnd.uniform(-0.6, 0.6), -0.7, 0.8), 0.45)
        for _ in range(4)
    ]
    for _ in range(2):  # vertical joints
        cutters.append(crack_cutter(rnd, (rnd.uniform(-2.5, 2.5), -1.1, rnd.uniform(1.0, 3.2)), 2.2, 1.2, 0.06, ry(90)))
    return solid("Cliff_a", "evaporite", "Cliff", parts, cutters, center_y=False, back_y=CLIFF_BACK)


def cliff_b() -> bpy.types.Object:
    """Jointed evaporite cliff: massive blocks split by vertical joints, each at its own depth, two soft bands
    weathered back across all of them, a rounded, crusted top and fallen blocks at the foot; flat back."""
    rnd = random.Random(1010)
    s = SINK["Cliff"]
    parts, x = [], -3.1
    while x < 3.0:
        w = rnd.uniform(1.1, 1.9)
        x1 = min(x + w, 3.1)
        front = rnd.uniform(-1.15, -0.7)
        depth = CLIFF_BACK + 0.15 - front
        h = rnd.uniform(3.7, 4.6)
        m = T(((x + x1) / 2, front + depth / 2, (h - s) / 2), rz(rnd.uniform(-3, 3)))
        bm = chunk(rnd, (x1 - x + 0.12, depth, h + s), 0, m, jitter=0.03, extra=0)
        for _ in range(rnd.randint(2, 4)):
            cut(bm, (rnd.uniform(-0.8, 0.8), -1.0, rnd.uniform(-0.3, 0.3)), rnd.uniform(0.9, 0.97))
        for _ in range(2):  # rounded top edge
            cut(bm, (rnd.uniform(-0.4, 0.4), -1.0, rnd.uniform(0.8, 1.4)), rnd.uniform(0.86, 0.93))
        cut(bm, (rnd.uniform(-0.25, 0.25), rnd.uniform(-0.3, 0.1), 1.0), rnd.uniform(0.9, 0.96))
        parts.append(bm)
        x = x1 - 0.06
    for _ in range(3):
        p = (rnd.uniform(-2.5, 2.5), rnd.uniform(-1.45, -1.1), rnd.uniform(-0.05, 0.1))
        size = (rnd.uniform(0.6, 1.0), rnd.uniform(0.5, 0.8), rnd.uniform(0.4, 0.65))
        parts.append(chunk(rnd, size, 4, T(p, rand_rot(rnd, 25))))
    cutters = []
    for zb, hb in ((1.2, 0.22), (2.7, 0.16)):
        for xb in (-2.0, 0.0, 2.0):
            cutters.append(
                crack_cutter(
                    rnd, (xb + rnd.uniform(-0.3, 0.3), -1.25, zb + rnd.uniform(-0.08, 0.08)), 2.4, 1.0, hb, rz(0)
                )
            )
    for _ in range(3):
        cutters.append(chip_cutter(rnd, parts[rnd.randrange(len(parts) - 3)], (rnd.uniform(-0.6, 0.6), -0.7, 0.9), 0.5))
    return solid("Cliff_b", "evaporite", "Cliff", parts, cutters, center_y=False, back_y=CLIFF_BACK)


BUILDERS = {
    "Boulder_a": boulder_a,
    "Boulder_b": boulder_b,
    "Pillar_a": pillar_a,
    "Halite_a": halite_a,
    "Shrub_a": shrub_a,
    "Bones_a": bones_a,
    "Bones_b": bones_b,
    "Crust_a": crust_a,
    "Cliff_a": cliff_a,
    "Cliff_b": cliff_b,
}

# --- material -----------------------------------------------------------------------------------------


class Shader(N.ShaderNodes):
    """Node helpers for the kit material (numbers are set, sockets linked)."""

    def palette(self, fac, colors: list) -> bpy.types.NodeSocket:
        """Constant color steps through `colors` (sRGB) along fac 0..1."""
        node = self.nt.nodes.new("ShaderNodeValToRGB")
        ramp = node.color_ramp
        ramp.interpolation = "CONSTANT"
        while len(ramp.elements) < len(colors):
            ramp.elements.new(0.5)
        for i, c in enumerate(colors):
            ramp.elements[i].position = i / len(colors)
            ramp.elements[i].color = (*srgb(*c), 1.0)
        self.nt.links.new(fac, node.inputs["Fac"])
        return node.outputs["Color"]


def mat_kit() -> bpy.types.Material:
    """The kit's one material, its look picked per face by "kind": salt-crusted grey rock (white crust on the
    lower part and in hollows), layered evaporite (grey, buff and off-white bands, salt crust in the recesses and
    on ledges, pits), dull off-white halite with a faint pink-grey tint (brighter edges, no glow), bleached bone
    (weathering cracks, crust at the ground), dead grey-brown wood coated with salt, broken crust plates (white
    tops, grey-brown undersides). Rough and matte; everything stays muted beside the glowing ores."""
    mat, nt, bsdf = C._new_material(MATERIAL)
    s = Shader(nt)
    kind = s.attr("kind")
    facet = s.attr("facet")
    pos = s.xyz(s.obj)
    z = pos.outputs["Z"]
    nz = s.xyz(s.geo.outputs["Normal"]).outputs["Z"]
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.3
    ao.samples = 16
    cavity = s.m("SUBTRACT", 1.0, s.ramp(0.3, 0.95, ao.outputs["AO"]), clamp=True)
    edge = s.ramp(0.015, 0.09, C._bevel_edge(nt, 0.03, s.geo))
    grain = s.noise(42.0, 4.0, 0.7)
    fine = s.noise(110.0, 2.0, 0.7)
    tone = s.noise(0.9, 4.0, 0.6)
    facet_k = s.m("MULTIPLY_ADD", facet, 0.3, 0.85)  # 0.85 .. 1.15
    warp = s.vec("MULTIPLY_ADD", C._noise(nt, 1.4, 3.0, 0.5, s.obj).outputs["Color"], (0.3, 0.3, 0.3))
    nt.links.new(s.obj, warp.node.inputs[2])
    cracks = s.m("MULTIPLY", C._voronoi_lines(nt, warp, 1.3, 0.022), s.ramp(0.45, 0.6, s.noise(2.0, 3.0, 0.55)))

    # Salt crust (shared): lumpy, crystalline, pale grey-white.
    lump = s.noise(16.0, 5.0, 0.65)
    crust_col = s.mix(s.spread(fine, 3.0), srgb(0.56, 0.56, 0.55), srgb(0.67, 0.67, 0.66))
    crust_col = s.mix(s.m("MULTIPLY", s.spread(lump, 2.5), 0.4), crust_col, srgb(0.5, 0.495, 0.48))
    crust_h = s.m("ADD", s.m("MULTIPLY", lump, 0.6), s.m("MULTIPLY", fine, 0.2))

    # 0 rock: grey, per-facet tone, cracks, lighter ridges; crust on the lower part and in hollows.
    rock = s.mix(s.spread(tone, 3.0), srgb(0.25, 0.245, 0.235), srgb(0.36, 0.35, 0.335))
    rock = s.scale_color(rock, facet_k)
    rock = s.scale_color(rock, s.m("MULTIPLY_ADD", grain, 0.35, 0.83))
    rock = s.mix(edge, rock, s.scale_color(rock, 1.35))
    rock = s.mix(s.m("MULTIPLY", cavity, 0.6), rock, srgb(0.12, 0.115, 0.11))
    rock = s.mix(cracks, rock, srgb(0.08, 0.075, 0.07))
    zz = s.m("ADD", z, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(2.2, 3.0, 0.6), 0.5), 1.5))
    low = s.m("SUBTRACT", 1.0, s.ramp(0.4, 0.62, zz), clamp=True)
    hollow = s.ramp(0.35, 0.6, cavity)
    up = s.m("MULTIPLY", s.ramp(0.75, 0.95, nz), s.ramp(0.55, 0.65, s.noise(3.5, 4.0, 0.6)))
    crust_k = s.m("MAXIMUM", s.m("MAXIMUM", low, hollow), s.m("MULTIPLY", up, 0.8))
    crust_k = s.ramp(0.42, 0.58, s.m("ADD", crust_k, s.m("MULTIPLY", s.m("SUBTRACT", lump, 0.5), 1.0)))
    rock_col = s.mix(crust_k, rock, crust_col)
    rock_rough = s.mixf(crust_k, s.mixf(edge, 0.86, 0.78), 0.95)
    rock_h = s.mixf(crust_k, s.m("SUBTRACT", s.m("MULTIPLY", grain, 0.5), s.m("MULTIPLY", cracks, 0.8)), crust_h)

    # 1 evaporite: thin horizontal bands, crust in the recesses and on ledges, pits.
    band_z = s.m("ADD", z, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(0.35, 2.0, 0.5), 0.5), 0.35))
    band_vec = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(band_z, band_vec.inputs["Z"])
    bands = s.noise(1.5, 2.0, 0.55, band_vec.outputs["Vector"])
    evap = s.palette(
        s.spread(bands, 3.5),
        [(0.40, 0.395, 0.385), (0.46, 0.44, 0.405), (0.54, 0.535, 0.52), (0.35, 0.345, 0.34), (0.45, 0.435, 0.41)],
    )
    evap = s.scale_color(evap, s.m("MULTIPLY_ADD", facet, 0.16, 0.92))
    evap = s.scale_color(evap, s.m("MULTIPLY_ADD", grain, 0.16, 0.92))
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 7.0
    nt.links.new(s.obj, vor.inputs["Vector"])
    pits = s.m(
        "MULTIPLY",
        s.m("SUBTRACT", 1.0, s.ramp(0.05, 0.16, vor.outputs["Distance"]), clamp=True),
        s.ramp(0.5, 0.6, s.noise(3.0, 2.0, 0.5)),
    )
    evap = s.mix(s.m("MULTIPLY", pits, 0.7), evap, srgb(0.22, 0.21, 0.2))
    evap = s.mix(cracks, evap, srgb(0.12, 0.115, 0.11))
    ledge = s.m("MULTIPLY", s.ramp(0.6, 0.9, nz), s.ramp(0.4, 0.55, s.noise(4.0, 3.0, 0.6)))
    salted = s.ramp(0.45, 0.6, s.m("ADD", s.m("MAXIMUM", s.ramp(0.3, 0.6, cavity), ledge), s.m("SUBTRACT", lump, 0.5)))
    evap_col = s.mix(salted, evap, crust_col)
    evap_rough = s.mixf(salted, s.mixf(s.spread(grain, 2.0), 0.82, 0.93), 0.95)
    evap_h = s.mixf(
        salted,
        s.m("SUBTRACT", s.m("ADD", s.m("MULTIPLY", grain, 0.4), s.m("MULTIPLY", bands, 0.6)), s.m("ADD", pits, cracks)),
        crust_h,
    )

    # 2 halite: dull off-white, faint pink-grey, brighter frosted edges, grey in the hopper steps.
    hal = s.mix(s.spread(facet, 1.0), srgb(0.56, 0.53, 0.535), srgb(0.64, 0.615, 0.62))
    hal = s.mix(s.spread(fine, 2.0), s.scale_color(hal, 0.93), hal)
    hal = s.mix(edge, hal, srgb(0.70, 0.68, 0.675))
    hal = s.mix(s.m("MULTIPLY", cavity, 0.8), hal, srgb(0.36, 0.335, 0.335))
    hal_col = s.mix(s.m("MULTIPLY", s.m("SUBTRACT", 1.0, s.ramp(0.0, 0.18, z), clamp=True), 0.5), hal, crust_col)
    hal_rough = s.mixf(edge, s.mixf(cavity, 0.55, 0.8), 0.62)
    hal_h = s.m("MULTIPLY", fine, 0.25)

    # 3 bone: bleached off-white, weathering cracks along its length, dark pores, crust where it meets the ground.
    stretch = s.vec("MULTIPLY", s.obj, (1.0, 3.0, 1.0))
    bone_cracks = s.m("MULTIPLY", C._voronoi_lines(nt, stretch, 6.0, 0.03), s.ramp(0.45, 0.6, s.noise(3.0, 3.0, 0.55)))
    bone = s.mix(s.spread(tone, 3.0), srgb(0.58, 0.555, 0.5), srgb(0.66, 0.635, 0.58))
    bone = s.scale_color(bone, s.m("MULTIPLY_ADD", grain, 0.2, 0.9))
    bone = s.mix(s.m("MULTIPLY", cavity, 0.75), bone, srgb(0.33, 0.30, 0.26))
    bone = s.mix(s.m("MULTIPLY", bone_cracks, 0.8), bone, srgb(0.3, 0.27, 0.23))
    ground = s.m("SUBTRACT", 1.0, s.ramp(0.02, 0.09, s.m("ADD", z, s.m("MULTIPLY", s.m("SUBTRACT", lump, 0.5), 0.2))))
    bone_col = s.mix(ground, bone, crust_col)
    bone_rough = s.mixf(ground, 0.74, 0.95)
    bone_h = s.m("SUBTRACT", s.m("MULTIPLY", grain, 0.3), bone_cracks)

    # 4 wood: dead grey-brown stems under a salt coat (thickest low down and on top of the forks).
    wood = s.mix(s.spread(grain, 2.0), srgb(0.27, 0.245, 0.22), srgb(0.36, 0.33, 0.295))
    wood = s.mix(s.m("MULTIPLY", cavity, 0.6), wood, srgb(0.16, 0.15, 0.135))
    coat = s.m(
        "ADD", s.m("SUBTRACT", 1.0, s.ramp(0.05, 0.35, z), clamp=True), s.m("MULTIPLY", s.ramp(0.3, 0.9, nz), 0.5)
    )
    coat = s.ramp(0.45, 0.6, s.m("ADD", s.m("MULTIPLY", coat, 0.7), s.m("MULTIPLY", s.m("SUBTRACT", lump, 0.5), 2.0)))
    wood_col = s.mix(coat, wood, crust_col)
    wood_rough = s.mixf(coat, 0.85, 0.95)
    wood_h = s.mixf(coat, s.m("MULTIPLY", grain, 0.3), crust_h)

    # 5 crust plate: crystalline white-grey top with a dusty film, grey-brown layered underside and broken edges.
    top = s.ramp(0.45, 0.8, nz)
    film = s.ramp(0.5, 0.62, s.noise(3.0, 3.0, 0.6))
    plate_top = s.mix(s.m("MULTIPLY", film, 0.5), crust_col, srgb(0.43, 0.405, 0.37))
    lam_vec = s.vec("MULTIPLY", s.obj, (0.0, 0.0, 1.0))
    lam = s.noise(40.0, 2.0, 0.5, lam_vec)
    under = s.mix(s.spread(lam, 4.0), srgb(0.33, 0.31, 0.28), srgb(0.43, 0.41, 0.37))
    plate_col = s.mix(top, under, plate_top)
    plate_col = s.mix(s.m("MULTIPLY", s.m("MULTIPLY", edge, top), 0.6), plate_col, srgb(0.7, 0.7, 0.69))
    plate_rough = s.mixf(top, 0.92, 0.9)
    plate_h = s.mixf(top, s.m("MULTIPLY", lam, 0.5), crust_h)

    looks = [
        (rock_col, rock_rough, rock_h),
        (evap_col, evap_rough, evap_h),
        (hal_col, hal_rough, hal_h),
        (bone_col, bone_rough, bone_h),
        (wood_col, wood_rough, wood_h),
        (plate_col, plate_rough, plate_h),
    ]
    col, rough, height = looks[0]
    for k, (c, r, h) in enumerate(looks[1:], start=1):
        pick = s.m("COMPARE", kind, float(k), 0.5)
        col = s.mix(pick, col, c)
        rough = s.mixf(pick, rough, r)
        height = s.mixf(pick, height, h)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    C._bump(nt, bsdf, height, 0.45, 0.02)
    return mat


# --- layout, preview, renders -------------------------------------------------------------------------

# Kit overview positions: (u along screen right, v toward the camera, z rotation). The iso camera looks from
# +X/-Y, so screen right is (+1, +1) and toward the camera is (+1, -1) in Blender XY.
LAYOUT = {
    "Cliff_a": (-3.4, -5.0, 45),
    "Cliff_b": (3.3, -5.0, 45),
    "Pillar_a": (-5.6, -0.6, 0),
    "Boulder_a": (-3.2, -0.4, 0),
    "Boulder_b": (-0.9, -0.4, 0),
    "Halite_a": (1.1, -0.3, 0),
    "Bones_a": (3.5, -0.3, 30),
    "Bones_b": (-2.6, 2.5, 0),
    "Shrub_a": (-0.5, 2.7, 0),
    "Crust_a": (1.7, 2.7, 0),
}
FIGURE_UV = (4.0, 2.7)
# Linear albedo of the salt crust ground (about the salt_ground texture's brightness) for the previews.
GROUND = ((0.17, 0.17, 0.16), (0.25, 0.25, 0.24))


def uv_to_xy(u: float, v: float) -> Vector:
    k = math.sqrt(0.5)
    return Vector((u * k + v * k, u * k - v * k, 0.0))


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
    for name in PARTS:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


def ground_color() -> None:
    """The preview ground in the salt crust's brightness (the default preview ground is dark rock)."""
    C.tint_ground(GROUND[0], GROUND[1])


def setup_preview() -> None:
    C.preview_scene(crystals=False, pebbles=False)  # the pebbles would read as part of the kit
    ground_color()


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in PARTS]


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


def render_part(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The part alone at the origin, framed by its size, the scale figure beside it."""
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
    put("Pillar_a", -6.0, -0.5, 1.0, 3, 0.1)
    put("Pillar_a", 5.5, 1.8, 0.8, 3, 0.1)
    for i, (x, y) in enumerate([(-2.6, 1.6), (2.6, -1.8), (-3.5, -3.2), (3.9, -4.6), (1.3, 2.2), (-5.6, 2.8)]):
        put(("Boulder_a", "Boulder_b")[i % 2], x, y, rnd.uniform(0.6, 1.4), 12, 0.1)
    for x, y in ((-1.2, -2.6), (4.8, -1.0)):
        put("Halite_a", x, y, rnd.uniform(0.8, 1.2), 10, 0.05)
    put("Bones_a", -0.8, 3.6, 1.0, 4, 0.05)
    put("Bones_b", 2.6, 0.6, 1.0, 5, 0.03)
    for _ in range(6):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(2.0, 8.0)
        put("Shrub_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.7, 1.3), 6, 0.03)
    for _ in range(7):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(1.5, 8.0)
        put("Crust_a", math.cos(a) * r, math.sin(a) * r, rnd.uniform(0.8, 1.4), 3, 0.01)
    C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.4)
    for d in dupes:
        bpy.data.objects.remove(d)
    for o in kit_objects():
        o.hide_render = False
    return path


# --- main -------------------------------------------------------------------------------------------


def build() -> None:
    global ROOT_OBJ, KIT_MAT
    ROOT_OBJ = C.asset_root(ASSET)
    KIT_MAT = mat_kit()
    work = bpy.data.collections.new("Work")
    bpy.context.scene.collection.children.link(work)
    for name in PARTS:
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
    for name in PARTS:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        zs = [v.co.z for v in me.vertices]
        dims = tuple(round(d, 2) for d in obj.dimensions)
        print(f"STATS {name}: tris={len(me.loop_triangles)} size={dims} z=({min(zs):.2f}, {max(zs):.2f})")
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
        for name in PARTS:
            sheet += render_part(name, "final_", ("iso", "hero"), 32, 640)
        for name in ("Cliff_a", "Cliff_b"):
            sheet += render_part(name, "final_", ("back",), 32, 640)
        C.contact_sheet(sheet, OUT / "sheet.png", tile=384, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "salt_procedural.blend")
    else:
        wip = OUT / "wip"
        for view in VIEWS:
            if view in ("kit_iso", "kit_hero"):
                render_kit(f"wip/{TAG}_", (view[4:],), 24, 768)
            elif view == "scatter":
                render_scatter(wip / f"{TAG}_scatter.png", 24, 768)
            elif view == "variants":
                for name in PARTS:
                    render_part(name, f"wip/{TAG}_", ("iso", "hero"), 20, 512)
            elif view == "back":
                for name in ("Cliff_a", "Cliff_b"):
                    render_part(name, f"wip/{TAG}_", ("back",), 20, 512)
            elif view in BUILDERS:
                render_part(view, f"wip/{TAG}_", ("iso", "hero"), 24, 640)
            elif view == "sheet":
                names = sorted(wip.glob(f"{TAG}_*.png"))
                C.contact_sheet(names, wip / f"{TAG}_sheet.png", tile=384, background=0.02)
            elif view == "save":
                apply_bake_layout()
                C.save_blend(OUT / "salt_procedural.blend")
                return


if __name__ == "__main__":
    main()
