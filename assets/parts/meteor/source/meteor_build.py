"""Meteor crater kit (map part game/locations/parts/meteor_crater.tscn, also the late deposit's impact site): a heavy
iron-stone meteorite partly buried at the crater's middle, three pieces broken off it and the ring of thrown-up rock
slabs and rubble around the impact point.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/meteor/source/meteor_build.py wip m1                    # pieces + layout
    tools/blender.sh assets/parts/meteor/source/meteor_build.py wip m1 Meteorite,layout
    tools/blender.sh assets/parts/meteor/source/meteor_build.py final

Everything it writes goes to tmp/assets/parts/meteor/: "wip <tag> [views]" renders previews into wip/<tag>_*.png
(views: pieces, layout, sheet, save, or a piece name); "final" renders every piece (iso, hero, back), the part's
layout from the game's angle (front and back), writes the contact sheet sheet.png and saves the procedural
meteor_procedural.blend that meteor_bake.py turns into the game asset. In the .blend the pieces stand unrotated in a
row along X, 3 m apart (bake layout, so the AO bake doesn't pick up neighbors); the bake zeroes their locations.

Game contract (docs/technical/assets.md, map parts): every piece is one mesh at the kit's root, origin at the bottom
center on the ground (z = 0), extra geometry below it (SINK; the meteorite is buried 1.2 m deep). The meteorite's
broken-open side faces -Y; the ejecta ring is centered on the impact point, its gaps lined up with the greybox's ore
markers when it stands unrotated.

Look: the meteorite's fused crust is near-black brown, satin, pitted all over with thumbprint hollows (in the mesh
and finer in the normal map), rusty in patches; where a piece broke off, the lighter iron-nickel interior shows,
metallic, with dark stony inclusions and rust at its rims; cracks run from the break across the crust, the deepest
holding a faint dull-red ember (a small emission, far dimmer than any ore). The ejecta is neutral grey-brown rock,
scorched darker toward the impact; the game lays the biome's cover on top-facing faces itself.

Modeling: the masses are subdivided icospheres rippled by a few waves and dented by thumbprint hollows (the distance
to the nearest and second-nearest of scattered sites), broken by boolean cutters (manifold solver) or plane cuts;
the chunks and the ejecta are separate shells of one mesh. A face attribute "kind" (0 crust, 1 interior, 2 crack,
3 rock) rides through the booleans and cuts and picks each face's material; a random per-face "facet" gives every
face its own tone (dropped after the bake).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "meteor"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
import nodes as N
from common import T, rx, ry, rz
from rock_geo import box_points, hull, rand_dir, rand_rot, support, work_collection

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "m0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["pieces", "layout"]

ASSET = "Meteor"
PIECES = ["Meteorite", "Meteor_chunk_a", "Meteor_chunk_b", "Meteor_chunk_c", "Meteor_ejecta"]
CRUST, INTERIOR, CRACK, ROCK = 0.0, 1.0, 2.0, 3.0  # face attribute "kind" = material slot
# Geometry kept below z = 0 per piece (m), so uneven ground never shows the bottom.
SINK = {"Meteorite": 1.2, "Meteor_chunk_a": 0.2, "Meteor_chunk_b": 0.16, "Meteor_chunk_c": 0.14, "Meteor_ejecta": 0.3}
SHARP_DEG = 35.0  # edges sharper than this split the shading; softer ones shade smooth
PROP_RADIUS = 4.2  # meteor_crater.tscn
FOOTPRINT = 7.5
# Greybox ore markers (Godot x, z), outside prop_radius: the ejecta keeps gaps toward them.
ORE_MARKERS = [(5.6, -2.0), (-5.4, -1.4), (0.6, 5.8)]

# --- math helpers -------------------------------------------------------------------------------------


def frame(x: Vector, y: Vector) -> Matrix:
    """3x3 rotation with X along `x` and Y as close as possible to `y`."""
    x = x.normalized()
    y = (y - x * y.dot(x)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()


def smoothstep(a: float, b: float, x: float) -> float:
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


# --- convex pieces and cuts ---------------------------------------------------------------------------


def cut(bm: bmesh.types.BMesh, normal, keep: float = 0.8, at: float | None = None, kind: float | None = None):
    """Shave off everything beyond a plane (at `keep` 0..1 of the extent along `normal`, or at the offset `at`) and
    close the hole; with `kind` the new face gets that kind (a fresh fracture face)."""
    n = Vector(normal).normalized()
    ds = [v.co.dot(n) for v in bm.verts]
    off = at if at is not None else min(ds) + (max(ds) - min(ds)) * keep
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=n * off, plane_no=n, clear_outer=True)
    boundary = [e for e in bm.edges if e.is_boundary]
    if not boundary:
        return
    faces = bmesh.ops.holes_fill(bm, edges=boundary, sides=0)["faces"]
    layer = bm.faces.layers.float.get("kind")
    if kind is not None and layer is not None:
        for f in faces:
            f[layer] = kind


def place(bm: bmesh.types.BMesh, m: Matrix) -> bmesh.types.BMesh:
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    bm.normal_update()
    return bm


def chunk(rnd: random.Random, size, cuts: int = 3, m: Matrix | None = None, keep=(0.72, 0.9), **kw):
    """A jagged rock block: a jittered box hull with `cuts` fracture facets shaved off."""
    bm = hull(box_points(rnd, size, **kw))
    for _ in range(cuts):
        cut(bm, rand_dir(rnd, min_z=-0.2), rnd.uniform(*keep))
    return place(bm, m) if m is not None else bm


def mass(rnd: random.Random, size, subdivisions: int, sites: int, dent: float, lumps: float = 0.1):
    """A meteorite mass of `size` (full extents), centered: an icosphere rippled by a few long waves and pitted by
    `sites` thumbprint hollows (bowls up to `dent` of the radius deep, sharp-ish ridges between them where the
    nearest and second-nearest sites are equally far). Every face is crust."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
    waves = [(rand_dir(rnd) * rnd.uniform(1.2, 2.8), rnd.uniform(0, math.tau)) for _ in range(5)]
    dirs = [rand_dir(rnd) for _ in range(sites)]
    depth = [rnd.uniform(0.6, 1.0) for _ in range(sites)]
    cell = math.sqrt(4 * math.pi / sites)  # typical angular spacing of the sites
    for v in bm.verts:
        d = v.co.normalized()
        ang = sorted((math.acos(max(-1.0, min(1.0, d.dot(s)))), i) for i, s in enumerate(dirs))
        (a1, i1), (a2, _i2) = ang[0], ang[1]
        bowl = smoothstep(0.0, 0.45, (a2 - a1) / cell)
        r = 1.0 + sum(lumps * math.cos(d.dot(w) + ph) for w, ph in waves) / 2.5 - dent * depth[i1] * bowl
        v.co = Vector((d.x * size[0] / 2, d.y * size[1] / 2, d.z * size[2] / 2)) * r
    bm.normal_update()
    kind = bm.faces.layers.float.new("kind")
    for f in bm.faces:
        f[kind] = CRUST
    return bm


def crack_cutter(rnd: random.Random, at: Vector, normal: Vector, along: Vector, length: float, depth: float, w: float):
    """A thin wedge (open at the surface, narrowing inward) centered on the surface point `at`: `length` along
    `along`, reaching `depth` into the mass against `normal`, `w` wide at its mouth."""
    pts = []
    for cx in (-1, 1):
        for cy, width in ((1, w), (-1, w * 0.15)):  # +Y: the mouth (outside), -Y: the bottom (inside)
            for cz in (-1, 1):
                pts.append(Vector((cx * length / 2 * rnd.uniform(0.75, 1.0), cy * depth / 2, cz * width / 2)))
    pts.append(Vector((0, 0, w * 0.8)))  # a kink in the crack
    bm = hull(pts)
    return place(bm, T(at - normal * (depth / 2 - 0.05), frame(along, normal)))


# --- mesh assembly ------------------------------------------------------------------------------------


def bm_to_obj(bm: bmesh.types.BMesh, name: str, coll: str, kind: float | None) -> bpy.types.Object:
    """A boolean operand: the piece as an object; `kind` sets every face's kind (None keeps the bmesh's)."""
    layer = bm.faces.layers.float.get("kind")
    if layer is None:
        layer = bm.faces.layers.float.new("kind")
    if kind is not None:
        for f in bm.faces:
            f[layer] = kind
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    C.collection(coll).objects.link(obj)
    return obj


def subtract(name: str, base_bm: bmesh.types.BMesh, cutters: list) -> bmesh.types.BMesh:
    """The base minus the cutters ((bmesh, kind) pairs: the faces a cutter leaves behind get its kind)."""
    base = bm_to_obj(base_bm, name + "_base", "Work", None)
    coll = work_collection(name + "_cut")
    for i, (bm, kind) in enumerate(cutters):
        bm_to_obj(bm, f"{name}_c{i}", coll.name, kind)
    mod = base.modifiers.new("Difference", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    try:
        mod.solver = "MANIFOLD"
    except TypeError:
        mod.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.003)
    bmesh.ops.dissolve_degenerate(bm, dist=0.002, edges=bm.edges[:])
    return bm


def shells(pieces: list) -> bmesh.types.BMesh:
    """Separate closed pieces (no boolean) as one mesh; `pieces` are (bmesh, kind) pairs, kind None keeps the
    piece's own per-face kinds."""
    bm = bmesh.new()
    layer = bm.faces.layers.float.new("kind")
    for piece, kind in pieces:
        src = piece.faces.layers.float.get("kind")
        vmap = {v: bm.verts.new(v.co) for v in piece.verts}
        for f in piece.faces:
            nf = bm.faces.new([vmap[v] for v in f.verts])
            nf[layer] = kind if kind is not None else (f[src] if src is not None else ROCK)
        piece.free()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def finish(bm: bmesh.types.BMesh, name: str, center: bool = True) -> bpy.types.Object:
    """Bottom cut flat at -SINK (a buried face, kind of the rock or crust it cuts), origin at the bottom center
    (x, y of the bounds' middle unless `center` is off), sharp edges split, the material per face from "kind", a
    random tone per face."""
    cut(bm, (0, 0, -1), at=SINK[name], kind=ROCK if name == "Meteor_ejecta" else INTERIOR)
    layer = bm.faces.layers.float.get("kind")
    for f in bm.faces:
        f.material_index = round(f[layer])
    bmesh.ops.dissolve_limit(
        bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:], delimit={"NORMAL", "MATERIAL"}
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if center:
        lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), 0))
        hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), 0))
        bmesh.ops.translate(bm, vec=-(lo + hi) / 2, verts=bm.verts[:])
    sharp = math.radians(SHARP_DEG)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > sharp)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.attributes.remove(me.attributes["kind"])
    rnd = random.Random(name)
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", [rnd.random() for _ in me.polygons])
    for mat in MATS:
        me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    C.link(obj)  # at the kit's root: no parent
    return obj


# --- pieces --------------------------------------------------------------------------------------------


def meteorite() -> bpy.types.Object:
    """The meteorite: a heavy iron-stone mass about 4.6 m long and 2.9 m above the ground (1.2 m more buried),
    lumpy and pitted all over with thumbprint hollows, nosed a little down into the ground; on its -Y side a
    stepped break where pieces came off shows the metal interior, cracks run out from it across the crust."""
    rnd = random.Random(5)
    bm = mass(rnd, (5.0, 3.7, 3.7), 4, 42, 0.1, lumps=0.17)
    place(bm, T((0, 0, 0.6), ry(9) @ rx(-6) @ rz(12)))  # one end higher, nosed into the ground, turned off-axis
    cutters = []
    # The break: overlapping jagged blocks, each turned its own way, bite a stepped, fractured hollow into the
    # -Y flank (where the chunks came off).
    for _ in range(7):
        d = Vector((0.15 + rnd.uniform(-0.55, 0.55), -1.0, 0.2 + rnd.uniform(-0.35, 0.45))).normalized()
        sz = rnd.uniform(0.8, 1.35)
        p = support(bm, d) - d * rnd.uniform(0.0, 0.18)
        size = (sz * rnd.uniform(1.0, 1.4), sz * rnd.uniform(0.7, 1.0), sz * rnd.uniform(0.7, 1.0))
        cutters.append((chunk(rnd, size, 4, T(p, rand_rot(rnd, 50)), keep=(0.6, 0.85), jitter=0.18), INTERIOR))
    # Cracks across the crust, most of them running out from the break.
    for d0, length in (
        ((0.9, -0.5, 0.4), 1.6),
        ((-0.8, -0.6, 0.3), 1.4),
        ((0.1, -0.5, 0.85), 1.9),
        ((0.5, 0.2, 0.85), 1.5),
        ((-0.6, 0.6, 0.5), 1.2),
        ((0.95, 0.1, 0.1), 1.3),
    ):
        d = Vector(d0).normalized()
        p = support(bm, d)
        along = d.cross(Vector((0, 0, 1))) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        along = (rz(rnd.uniform(-35, 35)) @ along).normalized()
        cutters.append(
            (crack_cutter(rnd, p, d, along, length, rnd.uniform(0.35, 0.55), rnd.uniform(0.07, 0.12)), CRACK)
        )
    return finish(subtract("Meteorite", bm, cutters), "Meteorite", center=False)


def meteor_chunk(name: str, seed: int, size: tuple, breaks: int) -> bpy.types.Object:
    """A piece broken off the meteorite: crust on its rounded outer side, `breaks` flat fracture faces showing the
    metal interior, lying with a fracture face partly up."""
    rnd = random.Random(seed)
    bm = mass(rnd, size, 2, 10, 0.08, lumps=0.14)
    for i in range(breaks):
        d = rand_dir(rnd, min_z=-0.2, max_z=0.7) if i else Vector((rnd.uniform(-0.4, 0.4), -0.6, 0.8))
        cut(bm, d, rnd.uniform(0.58, 0.72), kind=INTERIOR)
    place(bm, rand_rot(rnd, 10))
    zmin = min(v.co.z for v in bm.verts)
    place(bm, T((0, 0, -zmin - SINK[name] * 1.4)))
    return finish(bm, name)


def ejecta() -> bpy.types.Object:
    """The ejecta ring around the impact point, about 9.4 m across and under 1 m high: rock slabs thrown up and
    tipped outward (their inner edges raised toward the crater's middle), overlapping like broken pavement, with
    rubble between them; an empty middle (radius 2.6) for the meteorite and lower, sparser gaps toward the ore
    markers (outside prop_radius)."""
    rnd = random.Random(23)
    gaps = [math.degrees(math.atan2(-z, x)) for x, z in ORE_MARKERS]  # Godot (x, z) -> Blender angle

    def gap(a: float) -> float:
        """1 in the middle of a gap toward an ore marker, 0 outside (+-17 degrees)."""
        dist = min(abs((a - g + 180) % 360 - 180) for g in gaps)
        return 1.0 - smoothstep(6.0, 17.0, dist)

    pieces = []
    # Two rows: big slabs steeply upturned at the rim, smaller ones flatter outside them.
    for r0, steps, scale, tilts in ((3.2, (13, 19), 1.0, (32, 50)), (3.95, (15, 24), 0.62, (12, 26))):
        a = rnd.uniform(0, 8)
        while a < 360:
            g = gap(a)
            if g < 0.5:
                u = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
                r = r0 + rnd.uniform(-0.15, 0.2)
                size = (rnd.uniform(0.9, 1.5) * scale, rnd.uniform(0.8, 1.15) * scale, rnd.uniform(0.15, 0.24))
                tilt = rnd.uniform(*tilts) * (1 - g)
                rot = rz(a + rnd.uniform(-14, 14)) @ Matrix.Rotation(math.radians(tilt), 3, "Y")  # inner edge up
                z = math.sin(math.radians(tilt)) * size[1] * 0.25 - 0.04
                m = T(u * r + Vector((0, 0, z)), rot @ rz(90 + rnd.uniform(-10, 10)))
                pieces.append((chunk(rnd, size, 2, m, keep=(0.75, 0.9), jitter=0.14, extra=4), ROCK))
            a += rnd.uniform(*steps)
    for _ in range(46):  # rubble
        for _ in range(30):
            a = rnd.uniform(0, 360)
            if gap(a) < rnd.uniform(0.3, 1.0):
                break
        r = rnd.uniform(2.7, 4.6)
        u = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        s = rnd.uniform(0.14, 0.42) * (1.0 - 0.35 * (r - 2.7) / 1.9)
        m = T(u * r + Vector((0, 0, s * 0.15)), rand_rot(rnd, 30))
        pieces.append((chunk(rnd, (s, s * rnd.uniform(0.6, 0.9), s * rnd.uniform(0.45, 0.7)), 2, m), ROCK))
    return finish(shells(pieces), "Meteor_ejecta", center=False)


BUILDERS = {
    "Meteorite": meteorite,
    "Meteor_chunk_a": lambda: meteor_chunk("Meteor_chunk_a", 31, (1.25, 0.95, 0.85), 2),
    "Meteor_chunk_b": lambda: meteor_chunk("Meteor_chunk_b", 42, (0.95, 0.75, 0.62), 2),
    "Meteor_chunk_c": lambda: meteor_chunk("Meteor_chunk_c", 53, (0.75, 0.6, 0.5), 3),
    "Meteor_ejecta": ejecta,
}


# --- materials -----------------------------------------------------------------------------------------


class Mat(N.MatNodes):
    """Node helpers around one procedural material."""

    def xyz(self):
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.obj, sep.inputs["Vector"])
        return sep.outputs

    def voronoi(self, scale: float, feature: str = "SMOOTH_F1", vector=None):
        n = self.nt.nodes.new("ShaderNodeTexVoronoi")
        n.feature = feature
        n.inputs["Scale"].default_value = scale
        self.nt.links.new(vector or self.obj, n.inputs["Vector"])
        return n.outputs["Distance"]

    def out(self, color, rough, height, strength: float, distance: float, metallic=0.0) -> bpy.types.Material:
        self.nt.links.new(color, self.bsdf.inputs["Base Color"])
        for sock, val in ((self.bsdf.inputs["Roughness"], rough), (self.bsdf.inputs["Metallic"], metallic)):
            if isinstance(val, bpy.types.NodeSocket):
                self.nt.links.new(val, sock)
            else:
                sock.default_value = val
        C._bump(self.nt, self.bsdf, height, strength, distance)
        return self.mat


def mat_crust() -> bpy.types.Material:
    """Fusion crust: near-black brown, satin, finer thumbprint pits and faint flow lines in the relief, rusty brown
    in large soft patches, a little lighter and smoother on the ridges, dust low on it; slightly metallic."""
    m = Mat("MeteorCrust")
    warped = m.warped(0.8, 0.3)
    tone = m.noise(0.9, 4.0, 0.55)
    col = m.mix(m.ramp(0.3, 0.7, tone), (0.018, 0.016, 0.015), (0.034, 0.03, 0.027))
    col = m.scale(col, m.math("MULTIPLY_ADD", m.facet(), 0.15, 0.93))
    rust = m.math("MULTIPLY", m.ramp(0.52, 0.72, m.noise(0.7, 5.0, 0.6, vector=warped)), 0.75)
    col = m.mix(rust, col, m.mix(m.noise(6.0, 3.0), (0.05, 0.026, 0.014), (0.075, 0.04, 0.02)))
    ridge = m.math("MULTIPLY", m.ramp(0.02, 0.1, C._bevel_edge(m.nt, 0.05, m.geo)), 0.6)
    col = m.mix(ridge, col, (0.07, 0.066, 0.062))
    cavity = m.ramp(0.3, 0.95, m.cavity(0.35))
    col = m.mix(m.math("SUBTRACT", 1.0, cavity, clamp=True), col, (0.008, 0.007, 0.007))
    low = m.ramp(0.8, -0.2, m.xyz()["Z"])  # dust settled on the lower part, the ground's grey-brown
    dust = m.math("MULTIPLY", low, m.ramp(0.4, 0.7, m.noise(2.5, 5.0, 0.6)))
    dust = m.math("MAXIMUM", m.math("MULTIPLY", dust, 0.7), m.math("MULTIPLY", m.ramp(0.75, 0.95, m.up()), 0.25))
    col = m.mix(dust, col, (0.1, 0.092, 0.082))
    rough = m.mixf(tone, 0.48, 0.62)
    rough = m.mixf(rust, rough, 0.8)
    rough = m.mixf(ridge, rough, 0.4)
    rough = m.mixf(dust, rough, 0.92)
    pits = m.math("MULTIPLY", m.voronoi(9.0, vector=m.warped(3.0, 0.15)), m.ramp(0.3, 0.7, m.noise(2.0, 3.0)))
    flow = m.noise(3.0, 2.0, 0.5, vector=m.warped(2.0, 0.6))
    height = m.math("ADD", m.math("MULTIPLY", pits, 0.6), m.math("MULTIPLY", flow, 0.2))
    metal = m.mixf(rust, 0.15, 0.0)
    return m.out(col, rough, height, 0.3, 0.02, metal)


def mat_interior() -> bpy.types.Material:
    """The broken-open interior: lighter iron-nickel metal, a faint coarse grain, dark brown-grey stony inclusions
    (rounded, not metal), rust creeping in from the rims and into the hollows; metallic, half rough."""
    m = Mat("MeteorMetal")
    grain = m.noise(9.0, 3.0, 0.6)
    col = m.mix(grain, (0.27, 0.262, 0.25), (0.36, 0.35, 0.335))
    stones = m.ramp(0.12, 0.19, m.voronoi(6.0, "F1", vector=m.warped(2.5, 0.9)))  # 0 inside an inclusion
    inclusion = m.math("SUBTRACT", 1.0, stones, clamp=True)
    inclusion = m.math("MULTIPLY", inclusion, m.ramp(0.4, 0.6, m.noise(1.8, 2.0)))
    col = m.mix(inclusion, col, m.mix(m.noise(20.0, 2.0), (0.09, 0.082, 0.072), (0.13, 0.118, 0.1)))
    rim = m.ramp(0.02, 0.2, C._bevel_edge(m.nt, 0.08, m.geo))
    cavity = m.math("SUBTRACT", 1.0, m.ramp(0.35, 0.95, m.cavity(0.3)), clamp=True)
    rust = m.math("MAXIMUM", rim, cavity)
    rust = m.math("MULTIPLY", rust, m.ramp(0.35, 0.6, m.noise(4.0, 4.0, 0.6)))
    col = m.mix(rust, col, (0.11, 0.05, 0.022))
    col = m.mix(m.math("MULTIPLY", cavity, 0.6), col, (0.02, 0.018, 0.016))
    rough = m.mixf(grain, 0.42, 0.55)
    rough = m.mixf(inclusion, rough, 0.85)
    rough = m.mixf(rust, rough, 0.85)
    metal = m.math("MULTIPLY", m.math("SUBTRACT", 1.0, m.math("MAXIMUM", inclusion, rust), clamp=True), 0.75)
    height = m.math("ADD", m.math("MULTIPLY", inclusion, -0.12), m.math("MULTIPLY", grain, 0.15))
    return m.out(col, rough, height, 0.35, 0.02, metal)


def mat_crack() -> bpy.types.Material:
    """Inside the cracks: dark scorched metal and stone; the deepest parts hold a faint dull-red ember (emission,
    far dimmer than any ore), flickering in patches along the crack."""
    m = Mat("MeteorCrack")
    deep = m.ramp(0.4, 0.06, m.cavity(0.25))  # 1 deep in the crack
    col = m.mix(m.noise(8.0, 3.0), (0.012, 0.01, 0.009), (0.03, 0.022, 0.018))
    m.bsdf.inputs["Emission Color"].default_value = (0.75, 0.16, 0.04, 1.0)
    patches = m.ramp(0.4, 0.62, m.noise(2.2, 3.0, 0.6))
    m.nt.links.new(m.math("MULTIPLY", m.math("MULTIPLY", deep, patches), 0.45), m.bsdf.inputs["Emission Strength"])
    return m.out(col, 0.8, m.noise(12.0, 3.0), 0.3, 0.02)


def mat_rock() -> bpy.types.Material:
    """Neutral grey-brown broken rock (the crater's floor thrown up): per-facet tone, faint strata, lighter chipped
    ridges, dark cracks and cavities, scorched darker toward the impact (object radius under about 3.5 m); rough."""
    m = Mat("MeteorRock")
    warped = m.warped(1.2, 0.35)
    breakup = m.noise(2.0, 4.0, 0.55)
    crack = m.math("MULTIPLY", C._voronoi_lines(m.nt, warped, 1.4, 0.03), m.ramp(0.45, 0.6, breakup))
    tone = m.noise(0.6, 5.0, 0.6)
    base = m.mix(m.ramp(0.3, 0.72, tone), (0.05, 0.046, 0.041), (0.1, 0.095, 0.088))
    base = m.scale(base, m.math("MULTIPLY_ADD", m.facet(), 0.35, 0.82))
    grain = m.noise(30.0, 4.0, 0.7)
    base = m.scale(base, m.math("MULTIPLY_ADD", grain, 0.25, 0.88))
    edge = m.ramp(0.015, 0.09, C._bevel_edge(m.nt, 0.03, m.geo))
    edge = m.math("MULTIPLY", edge, m.ramp(0.3, 0.6, m.noise(7.0, 3.0, 0.6)))
    col = m.mix(edge, base, m.scale(base, 1.5))
    cavity = m.ramp(0.25, 0.95, m.cavity(0.3))
    col = m.mix(m.math("SUBTRACT", 1.0, cavity, clamp=True), col, (0.012, 0.011, 0.01))
    col = m.mix(crack, col, (0.01, 0.009, 0.008))
    xyz = m.xyz()
    radius = m.math("SQRT", m.math("ADD", m.math("POWER", xyz["X"], 2.0), m.math("POWER", xyz["Y"], 2.0)))
    scorch = m.math("MULTIPLY", m.ramp(3.7, 2.8, radius), m.ramp(0.3, 0.7, m.noise(1.5, 4.0)))
    col = m.mix(m.math("MULTIPLY", scorch, 0.75), col, (0.018, 0.015, 0.013))
    dust = m.math("MULTIPLY", m.ramp(0.35, 0.8, m.up()), m.ramp(0.35, 0.65, m.noise(2.5, 5.0, 0.6)))
    col = m.mix(m.math("MULTIPLY", dust, 0.55), col, m.mix(grain, (0.12, 0.112, 0.1), (0.16, 0.15, 0.135)))
    rough = m.mixf(tone, 0.82, 0.93)
    rough = m.mixf(edge, rough, 0.74)
    lumps = m.voronoi(2.5, vector=warped)
    height = m.math("ADD", m.math("MULTIPLY", lumps, 0.5), m.math("MULTIPLY", grain, 0.2))
    height = m.math("SUBTRACT", height, m.math("MULTIPLY", crack, 0.7))
    return m.out(col, rough, height, 0.5, 0.03)


# --- previews and layout ---------------------------------------------------------------------------------

# The part's layout (Godot: position x, y, z; rotation y in degrees; scale): the meteorite at the impact point turned
# by 180 degrees, so its broken side (-Y, Godot +z) faces the way in (Godot -z); the chunks thrown out in front of
# the break, lying on the ejecta's ring, clear of the ore markers.
LAYOUT = [
    ("Meteor_ejecta", (0.0, 0.0, 0.0), 0.0, 1.0),
    ("Meteorite", (0.0, 0.0, 0.0), 180.0, 1.0),
    ("Meteor_chunk_a", (1.9, 0.0, -2.9), 35.0, 1.0),
    ("Meteor_chunk_b", (-2.4, 0.0, -2.4), 110.0, 1.0),
    ("Meteor_chunk_c", (3.1, 0.0, 0.9), 200.0, 1.0),
]


def godot_to_blender(p) -> Vector:
    return Vector((p[0], -p[2], p[1]))


def setup_preview() -> None:
    """The shared preview scene (studio lights for the pieces) without its placeholder ore and pebbles."""
    C.preview_scene(crystals=False, pebbles=False)


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in PIECES]


def render_piece(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The piece alone at the origin, its front (-Y) toward the camera, the scale figure beside it; "back" looks
    at its back."""
    obj = bpy.data.objects[name]
    for o in kit_objects():
        o.hide_render = o is not obj
    obj.location = (0, 0, 0)
    dx, dy, _dz = obj.dimensions
    top = max(v.co.z for v in obj.data.vertices)
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # screen right in the iso view
    fig.location = side * (max(dx, dy) / 2 + 0.55)
    w = max(dx, dy, top * 1.1) * 1.3 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.4, top * 0.42)))
    out = []
    for view in views:
        obj.rotation_euler = (0, 0, math.pi if view == "back" else 0.0)
        path = OUT / f"{prefix}{name}_{view}.png"
        zoom = w / (9.9 if view in ("iso", "back") else 6.3)
        C.render(path, view="iso" if view == "back" else view, samples=samples, size=size, target=target, zoom=zoom)
        out.append(path)
    obj.rotation_euler = (0, 0, 0)
    for o in kit_objects():
        o.hide_render = False
    return out


def ore_placeholder(name: str, at: Vector, seed: int) -> list:
    """Glowing violet crystals within 1.1 m of an ore marker (stand-in for the game's ore)."""
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
    n, w = 160, 0.04
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
    ore, the prop_radius and footprint rings and a 1.89 m pole, from the game's angle (about 50 degrees down, 45
    degrees around) in a dim, cool light (a weak low sun and a little sky); front: the camera on the way-in side
    (Godot -z), back: behind. The terrain's crater bowl isn't shown (flat ground)."""
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
    for i, (name, pos, rot, scale) in enumerate(LAYOUT):
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
    pole.location = (2.4, 4.6, 0.945)
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
    center = Vector((0, 0, 0.8))
    for view, azimuth in (("front", 45.0), ("back", 225.0)):
        a = math.radians(azimuth)
        pitch = math.radians(50)
        loc = center + Vector((math.cos(a) * math.cos(pitch), math.sin(a) * math.cos(pitch), math.sin(pitch))) * 24.0
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
    MATS = [mat_crust(), mat_interior(), mat_crack(), mat_rock()]
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
        kinds = [0] * 4
        for p in me.polygons:
            kinds[p.material_index] += 1
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        manifold = all(e.is_manifold for e in bm.edges)
        bm.free()
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(d, 2) for d in obj.dimensions)}"
            f" x=({min(xs):.2f}, {max(xs):.2f}) y=({min(ys):.2f}, {max(ys):.2f}) z=({min(zs):.2f}, {max(zs):.2f})"
            f" faces crust/interior/crack/rock={kinds} manifold={manifold}"
        )
        obj.evaluated_get(dg).to_mesh_clear()
    print("STATS", C.stats())


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
        C.save_blend(OUT / "meteor_procedural.blend")
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
            C.save_blend(OUT / "meteor_procedural.blend")
            return


if __name__ == "__main__":
    main()
