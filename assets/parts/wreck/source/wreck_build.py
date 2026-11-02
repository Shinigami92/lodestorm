"""Wreck kit: the crashed colony hauler of the wreck map part (game/locations/parts/wreck.tscn): its main hull with
the dorsal fin, crumpled nose and torn-open back end, the torn-off rear section lying on its side, a burnt hull plate
standing out of the ground, three pieces of debris (a bent strut with plating, a thruster bell, a crumpled panel)
and the scorched skid mark under it all.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/wreck/source/wreck_build.py wip w1                       # layout + kit views
    tools/blender.sh assets/parts/wreck/source/wreck_build.py wip w1 Wreck_hull,layout
    tools/blender.sh assets/parts/wreck/source/wreck_build.py final

Everything it writes goes to tmp/assets/parts/wreck/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: layout, layout_close, kit_iso, kit_hero, pieces, sheet, save, or a piece name); "final"
renders the layout from the game's angle, the kit and every piece (iso + hero), writes the contact sheet sheet.png
and saves the procedural wreck_procedural.blend that wreck_bake.py turns into the game asset. In the .blend the
pieces stand unrotated in a row along X, 3 m apart (so the AO bake doesn't pick up neighbors); the bake zeroes their
locations.

The vessel: an old, boxy colony cargo hauler, older than the player's ship but of the same family: slab sides with
chamfered corners, a flat belly, a sloped cab nose with a window strip, dark gunmetal frames round the hull, a dark
recessed rail belt along both sides, a cargo door with a hazard-striped lintel, bone-white paint, stenciled numbers.
It came down nose first and skidded: the nose is crushed, the rear section tore off and tumbled away, the break
burnt. The game places every piece by name (ModelParts) at the transform the part's scene gives it.

Game contract: every piece is one mesh object at the kit's root empty, one material ("Wreck"), origin at the ground
contact (bottom center; the hull: its underside's center), front towards -Y. Pieces that stand on the ground reach
0.3-0.5 m below z = 0; the hull is a full cross-section (it is placed sunk about a third). Budgets (TBD
(playtest)): hull <= ~8k triangles, section and panel <= ~3k, debris <= ~800, the scorch mark <= ~800.

Modeling: lofted rings of the hull's cross-section (the shared RING), shaped (the nose), crumpled with smooth noise,
double-walled where the hull is open (outer skin, torn rim, inner skin, a bulkhead closing the view), plus boxes,
beams and tubes. One procedural material covers the kit: a per-face "kind" attribute picks the look (bone paint,
gunmetal frame, interior, burnt metal, hazard stripes, cable, torn bare metal, nozzle, glass, scorched ground,
stenciled paint), a per-face "facet" value gives every plate its own tone and a per-vertex "soot" value says how
burnt it is.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "wreck"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils import noise as mnoise

import common as C
from common import T, rx, ry

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "w0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["layout", "kit_iso"]

ASSET = "Wreck"
MATERIAL = "Wreck"
KINDS = {
    "paint": 0,
    "frame": 1,
    "interior": 2,
    "burnt": 3,
    "hazard": 4,
    "cable": 5,
    "torn": 6,
    "nozzle": 7,
    "glass": 8,
    "scorch": 9,
    "stencil": 10,
}
PARTS = [
    "Wreck_hull",
    "Wreck_section",
    "Wreck_panel",
    "Wreck_debris_a",
    "Wreck_debris_b",
    "Wreck_debris_c",
    "Wreck_scorch",
]
SHARP_DEG = 30.0  # edges sharper than this split the shading (and get the bevel)

# The hauler's cross-section (x across, z up; counterclockwise seen from +Y): flat belly, chamfered corners, slab
# sides with a recessed rail belt at 2.2-2.7 m, a flat top. Long stretches are split so the tears and dents have
# vertices to work with.
RING_HALF = [
    (0.0, 0.0),
    (0.8, 0.0),
    (1.55, 0.0),
    (2.05, 0.35),
    (2.25, 0.9),
    (2.25, 1.55),
    (2.25, 2.2),
    (2.12, 2.27),
    (2.12, 2.6),
    (2.24, 2.68),
    (1.95, 3.15),
    (1.45, 3.4),
    (0.72, 3.4),
    (0.0, 3.4),
]
RING = RING_HALF + [(-x, z) for x, z in reversed(RING_HALF[1:-1])]
HULL_H = 3.4
NOSE_Y = -6.25  # the hull's nose tip (y = 0 is the hull's middle)
BODY_Y = -4.0  # where the nose starts to slope
BREAK_Y = 6.25  # the torn end (tears reach up to about 1.6 m further in)
BULKHEAD_Y = 3.4  # the inside ends here: the open part shows 2-3 m of the hull's dark interior
FRAMES_Y = (-4.0, -1.0, 2.0)  # gunmetal frames round the outside
INNER_FRAME_Y = 4.1  # the last frame, also standing inside the open part


# --- math helpers ---------------------------------------------------------------------------------------------


def srgb(r: float, g: float, b: float) -> tuple[float, float, float]:
    """Linear color from sRGB values (shader colors are linear)."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))


def smoothstep(a: float, b: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def ring_normals(ring: list) -> list:
    """Miter normals of a counterclockwise (x, z) polygon: offsetting a point by d * normal keeps both of its edges
    d away from where they were."""
    n = len(ring)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(ring[i - 1]), Vector(ring[i]), Vector(ring[(i + 1) % n])
        e0, e1 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n0, n1 = Vector((e0.y, -e0.x)), Vector((e1.y, -e1.x))
        avg = (n0 + n1).normalized()
        out.append(avg / max(0.5, avg.dot(n0)))
    return out


RING_N = ring_normals(RING)


def seg_mid(i: int) -> Vector:
    return (Vector(RING[i]) + Vector(RING[(i + 1) % len(RING)])) / 2


def seg_is_belt(i: int) -> bool:
    m = seg_mid(i)
    return 2.2 < m.y < 2.7 and abs(m.x) > 2.0


def seg_is_top(i: int) -> bool:
    return seg_mid(i).y > 3.3


def seg_is_side(i: int) -> bool:
    m = seg_mid(i)
    return abs(m.x) > 2.2 and 0.9 <= m.y <= 2.2


# --- mesh builder -----------------------------------------------------------------------------------------------


class Mesh:
    """One piece's bmesh with the kit's layers: per face "kind" (the look) and "facet" (plate tone), per vertex
    "soot" (how burnt). Shells are built closed; normals are recalculated at the end."""

    def __init__(self, name: str):
        self.name = name
        self.rnd = random.Random(name)
        self.bm = bmesh.new()
        self.kind = self.bm.faces.layers.float.new("kind")
        self.facet = self.bm.faces.layers.float.new("facet")
        self.soot = self.bm.verts.layers.float.new("soot")

    def verts(self, pts) -> list:
        return [self.bm.verts.new(Vector(p)) for p in pts]

    def face(self, verts, kind: str) -> bmesh.types.BMFace:
        f = self.bm.faces.new(verts)
        f[self.kind] = KINDS[kind]
        return f

    def tag(self, verts, kind: str) -> list:
        for f in {f for v in verts for f in v.link_faces}:
            f[self.kind] = KINDS[kind]
        return verts

    def loft(self, rings: list, kind, closed: bool = True) -> list:
        """Quads between consecutive rings of verts; kind is a name or a function (row, segment) -> name."""
        n = len(rings[0])
        rows = []
        for r in range(len(rings) - 1):
            a, b = rings[r], rings[r + 1]
            row = []
            for i in range(n if closed else n - 1):
                j = (i + 1) % n
                k = kind(r, i) if callable(kind) else kind
                row.append(self.face((a[i], a[j], b[j], b[i]), k))
            rows.append(row)
        return rows

    def box(self, loc, size, rot: Matrix | None = None, kind: str = "frame") -> list:
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=T(loc, rot, size))["verts"]
        return self.tag(verts, kind)

    def cyl(self, loc, r, depth, seg=12, rot: Matrix | None = None, kind="frame", r2=None) -> list:
        verts = bmesh.ops.create_cone(
            self.bm,
            cap_ends=True,
            cap_tris=False,
            segments=seg,
            radius1=r,
            radius2=r if r2 is None else r2,
            depth=depth,
            matrix=T(loc, rot),
        )["verts"]
        return self.tag(verts, kind)

    def hexa(self, a_pts, b_pts, kind: str) -> list:
        """A closed six-sided block between two quads (same corner order)."""
        a, b = self.verts(a_pts), self.verts(b_pts)
        self.loft([a, b], kind)
        self.face(list(reversed(a)), kind)
        self.face(b, kind)
        return a + b

    def beam(self, p0, p1, w: float, h: float, side=(0, 0, 1), kind: str = "frame", taper: float = 1.0) -> list:
        """Rectangular beam from p0 to p1, w measured along `side` (made perpendicular), h across."""
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        s = Vector(side)
        s = (s - d * s.dot(d)).normalized()
        u = d.cross(s)
        corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        a = [p0 + s * cx * w / 2 + u * cy * h / 2 for cx, cy in corners]
        b = [p1 + (s * cx * w / 2 + u * cy * h / 2) * taper for cx, cy in corners]
        return self.hexa(a, b, kind)

    def tube(self, pts: list, r: float, sides: int = 6, kind: str = "cable") -> list:
        """Round tube along a polyline (parallel-transported frames), closed at both ends."""
        pts = [Vector(p) for p in pts]
        rings, prev = [], None
        for k, p in enumerate(pts):
            t = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
            n = t.orthogonal().normalized() if prev is None else (prev - t * prev.dot(t)).normalized()
            prev = n
            b = t.cross(n)
            ring = [p + (n * math.cos(a) + b * math.sin(a)) * r for a in (i / sides * math.tau for i in range(sides))]
            rings.append(self.verts(ring))
        self.loft(rings, kind)
        self.face(list(reversed(rings[0])), kind)
        self.face(rings[-1], kind)
        return [v for ring in rings for v in ring]

    def plate(self, nu: int, nv: int, point, thick: float, front: str, back: str, rim: str) -> tuple[list, list]:
        """A two-sided plate over a (u, v) grid: point(u, v) -> (surface point, its normal); the front lies thick/2
        along +normal, the back along -normal, rim faces close the edges. Returns the front and back vertex grids."""
        fr, bk = [], []
        for j in range(nv + 1):
            rf, rb = [], []
            for i in range(nu + 1):
                p, n = point(i / nu, j / nv)
                rf.append(self.bm.verts.new(p + n * thick / 2))
                rb.append(self.bm.verts.new(p - n * thick / 2))
            fr.append(rf)
            bk.append(rb)
        for j in range(nv):
            for i in range(nu):
                self.face((fr[j][i], fr[j][i + 1], fr[j + 1][i + 1], fr[j + 1][i]), front)
                self.face((bk[j][i], bk[j + 1][i], bk[j + 1][i + 1], bk[j][i + 1]), back)
        edge = (
            [(0, i) for i in range(nu + 1)]
            + [(j, nu) for j in range(1, nv + 1)]
            + [(nv, i) for i in range(nu - 1, -1, -1)]
            + [(j, 0) for j in range(nv - 1, 0, -1)]
        )
        for k in range(len(edge)):
            (j0, i0), (j1, i1) = edge[k], edge[(k + 1) % len(edge)]
            self.face((fr[j0][i0], bk[j0][i0], bk[j1][i1], fr[j1][i1]), rim)
        return fr, bk

    def transform(self, m: Matrix) -> None:
        bmesh.ops.transform(self.bm, matrix=m, verts=self.bm.verts[:])

    def set_soot(self, fn) -> None:
        """soot = fn(position, vertex) for every vertex (0 clean .. 1 charred)."""
        for v in self.bm.verts:
            v[self.soot] = max(0.0, min(1.0, fn(v.co, v)))

    def finish(self, bevel: tuple[float, int] | None = (0.03, 2), fix_up: bool = False) -> bpy.types.Object:
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if fix_up:  # an open surface lying on the ground: every face up
            for f in bm.faces:
                f.normal_update()
                if f.normal.z < 0:
                    f.normal_flip()
        limit = math.radians(SHARP_DEG)
        for f in bm.faces:
            f.smooth = True
            f[self.facet] = self.rnd.random()
        for e in bm.edges:
            e.smooth = len(e.link_faces) == 2 and e.calc_face_angle(0.0) <= limit
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(self.name, me)
        C.link(obj, ROOT_OBJ)
        C.assign(obj, KIT_MAT)
        if bevel:
            C.bevel(obj, bevel[0], bevel[1], SHARP_DEG + 5)
        return obj


# --- the hull's rings ---------------------------------------------------------------------------------------------


def nose_t(y: float) -> float:
    """0 along the body, 1 at the nose tip."""
    return min(1.0, max(0.0, (BODY_Y - y) / (BODY_Y - NOSE_Y)))


def nose_shape(x: float, y: float, z: float) -> Vector:
    """The cab nose: the top slopes down to the tip, the belly rises a little, the sides draw in."""
    t = nose_t(y)
    return Vector((x * (1 - 0.16 * t**1.5), y, 0.25 * t * t + z * (1 - 0.48 * t**1.3)))


def crumple(p: Vector, y: float, seed: float = 0.0) -> Vector:
    """Smooth dents: barely along the body, crushed at the nose (shoved to one side), buckled at the break."""
    t = nose_t(y)
    amp = 0.035 + 0.42 * t**1.6 + 0.1 * smoothstep(4.0, 6.2, y)
    d = mnoise.noise_vector(Vector((p.x * 0.55 + seed, y * 0.55, p.z * 0.55))) * amp
    d.y *= 0.4  # stations never cross
    d.x += 0.3 * t * t
    return d


def ring_at(m: Mesh, ys, d: float, petal=None, shape=True, seed: float = 0.0) -> list:
    """A ring of verts at per-vertex stations ys (a number or a list), offset d from the skin (out > 0), petal: extra
    per-vertex offset (peeled plates)."""
    out = []
    for i, (x, z) in enumerate(RING):
        y = ys[i] if isinstance(ys, list) else ys
        off = d + (petal[i] if petal else 0.0)
        bx, bz = x + RING_N[i].x * off, z + RING_N[i].y * off
        p = nose_shape(bx, y, bz) if shape else Vector((bx, y, bz))
        out.append(p + crumple(Vector((x, y, z)), y, seed))
    return m.verts(out)


def band(m: Mesh, y: float, width: float, out: float, inn: float, kind: str = "frame") -> None:
    """A frame round the hull: a closed ring block from offset inn to out, width along y."""
    o0, o1 = ring_at(m, y - width / 2, out), ring_at(m, y + width / 2, out)
    i0, i1 = ring_at(m, y - width / 2, inn), ring_at(m, y + width / 2, inn)
    m.loft([o0, o1], kind)
    m.loft([i1, i0], kind)
    m.loft([i0, o0], kind)
    m.loft([o1, i1], kind)


def tear(rnd: random.Random, base: float, deep: float, top_bias: float, lo: float, hi: float) -> list:
    """Per ring vertex: how far the torn edge reaches (relative to `base`), deeper at the top, smoothed, zigzag."""
    raw = [-top_bias * smoothstep(1.6, HULL_H, z) + rnd.uniform(lo, hi) for _, z in RING]
    n = len(raw)
    smooth = [0.5 * raw[i] + 0.25 * (raw[i - 1] + raw[(i + 1) % n]) for i in range(n)]
    return [base + s * deep + (0.12 if i % 2 else -0.08) for i, s in enumerate(smooth)]


# --- pieces -------------------------------------------------------------------------------------------------------


def hull() -> bpy.types.Object:
    """Wreck_hull: the main hull, 4.5 m wide, 3.4 m high, 12.5 m long (y), origin at its underside's middle. The
    nose (-Y) is crushed, the back end (+Y) torn open: jagged plating peeled outwards, bare ribs and stringers, cables
    hanging out, a deck and a bulkhead inside. A swept dorsal fin, a top housing, the cargo doors and the stencils."""
    m = Mesh("Wreck_hull")
    rnd = m.rnd
    n = len(RING)
    end = tear(rnd, BREAK_Y, 1.0, 1.35, -0.5, 0.35)
    end = [max(INNER_FRAME_Y + 0.45, y) for y in end]
    mid = [INNER_FRAME_Y + (y - INNER_FRAME_Y) * 0.55 for y in end]
    petal = [0.0] * n
    for start, length, size in ((4, 4, 0.5), (17, 3, 0.4), (11, 2, -0.18)):  # peeled-out plates, one dented in
        for k in range(length):
            petal[(start + k) % n] = size * math.sin((k + 0.5) / length * math.pi)
    petal_mid = [p * 0.3 for p in petal]

    # Outer skin: nose tip to the torn end.
    nose_ys = [NOSE_Y, -5.9, -5.4, -4.75]
    body_ys = [BODY_Y, -2.5, -1.0, 0.5, 2.0, BULKHEAD_Y, INNER_FRAME_Y]
    rings = []
    for k, y in enumerate(nose_ys):
        jitter = [rnd.uniform(-0.2, 0.2) * nose_t(y) for _ in range(n)]
        ys = y + (rnd.uniform(-0.05, 0.2) if k == 0 else 0.0)
        rings.append(ring_at(m, ys, 0.0, jitter))
    rings += [ring_at(m, y, 0.0) for y in body_ys]
    rings += [ring_at(m, mid, 0.0, petal_mid), ring_at(m, end, 0.0, petal)]
    windscreen = (nose_ys.index(-5.4), nose_ys.index(-4.75))
    stencil_row = len(nose_ys)  # the row from BODY_Y to -2.5

    def outer_kind(r: int, i: int) -> str:
        if seg_is_belt(i):
            return "frame"
        if windscreen[0] <= r < windscreen[1] and seg_is_top(i):
            return "glass"
        if r == stencil_row and (seg_is_top(i) or seg_is_side(i)):
            return "stencil"
        return "paint"

    m.loft(rings, outer_kind)
    # Crushed nose cap: a fan to a dent pushed in.
    tip = rings[0]
    c = sum((v.co for v in tip), Vector()) / n + Vector((0.0, 0.35, 0.0))
    cv = m.bm.verts.new(c)
    for i in range(n):
        m.face((tip[(i + 1) % n], tip[i], cv), "paint")
    # Torn rim and the inner skin back to the bulkhead.
    inner = [
        ring_at(m, BULKHEAD_Y, -0.12),
        ring_at(m, INNER_FRAME_Y, -0.12),
        ring_at(m, mid, -0.12, petal_mid),
        ring_at(m, [y - 0.05 for y in end], -0.12, petal),
    ]
    m.loft([rings[-1], inner[-1]], "torn")
    m.loft(list(reversed(inner)), "interior")
    bulk = m.face(list(reversed(inner[0])), "interior")
    bmesh.ops.triangulate(m.bm, faces=[bulk])

    # Frames round the outside; the last one also stands inside the open part.
    for y in FRAMES_Y:
        band(m, y, 0.32, 0.07, -0.07)
    band(m, INNER_FRAME_Y, 0.3, 0.07, -0.3)
    # Bare rib where the plating is torn away, bent where it broke.
    rib_y = 5.3
    for i in range(n):
        j = (i + 1) % n
        if end[i] < rib_y - 0.1 and end[j] < rib_y - 0.1:
            pts = []
            for k in (i, j):
                x, z = RING[k]
                for off in (0.0, -0.22):
                    p = Vector((x + RING_N[k].x * off, rib_y, z + RING_N[k].y * off))
                    pts.append(p + crumple(Vector((x, rib_y, z)), rib_y) * 1.6)
            a = [pts[0] + Vector((0, -0.08, 0)), pts[1] + Vector((0, -0.08, 0))]
            a += [pts[3] + Vector((0, -0.08, 0)), pts[2] + Vector((0, -0.08, 0))]
            m.hexa(a, [p + Vector((0, 0.16, 0)) for p in a], "frame")
    # Stringers along the inside, sticking out of the tear and bent.
    for i in (11, 15, 5, 21):
        x, z = RING[i]
        if end[i] > 6.0:
            continue
        nrm = Vector((RING_N[i].x, 0, RING_N[i].y))
        p0 = Vector((x, BULKHEAD_Y + 0.1, z)) - nrm * 0.2
        p1 = Vector((x, end[i] - 0.1, z)) - nrm * 0.2 + crumple(Vector((x, end[i], z)), end[i])
        p2 = p1 + Vector((0, rnd.uniform(0.5, 0.9), 0)) + nrm * rnd.uniform(0.15, 0.35) + Vector((0, 0, 0.15))
        m.beam(p0, p1, 0.14, 0.14, nrm)
        m.beam(p1, p2, 0.14, 0.14, nrm, taper=0.8)
    # Deck inside and a hatch on the bulkhead.
    m.box((0.0, 4.65, 0.62), (3.9, 2.5, 0.14), rx(-2.5), "frame")
    for loc, size in (
        ((-0.62, BULKHEAD_Y + 0.05, 1.7), (0.12, 0.1, 2.0)),
        ((0.62, BULKHEAD_Y + 0.05, 1.7), (0.12, 0.1, 2.0)),
        ((0.0, BULKHEAD_Y + 0.05, 2.66), (1.36, 0.1, 0.12)),
        ((0.0, BULKHEAD_Y + 0.03, 1.7), (1.12, 0.06, 1.85)),
    ):
        m.box(loc, size, None, "frame")
    # Cables hanging out of the open end.
    for x0, r, drop, reach in ((-0.9, 0.06, 2.4, 2.0), (0.35, 0.045, 1.9, 1.5), (1.2, 0.05, 2.6, 2.3)):
        pts = []
        for k in range(8):
            t = k / 7
            pts.append(Vector((x0 + 0.2 * math.sin(t * 3 + x0), 4.5 + reach * t, 3.12 - drop * t**1.6)))
        m.tube(pts, r, 6, "cable")

    # Dorsal fin (leaning: bent in the crash) with a leading-edge frame and a hazard-striped tip.
    lean = Matrix.Translation((0, 0, HULL_H)) @ ry(12).to_4x4() @ Matrix.Translation((0, 0, -HULL_H))
    fin = []
    fin += m.hexa(
        [(-0.2, 0.6, 3.25), (0.2, 0.6, 3.25), (0.2, 3.3, 3.25), (-0.2, 3.3, 3.25)],
        [(-0.11, 2.45, 4.7), (0.11, 2.45, 4.7), (0.11, 3.8, 4.7), (-0.11, 3.8, 4.7)],
        "paint",
    )
    fin += m.hexa(
        [(-0.11, 2.45, 4.7), (0.11, 2.45, 4.7), (0.11, 3.8, 4.7), (-0.11, 3.8, 4.7)],
        [(-0.09, 2.62, 5.0), (0.09, 2.62, 5.0), (0.09, 3.86, 5.0), (-0.09, 3.86, 5.0)],
        "hazard",
    )
    fin += m.beam((0, 0.66, 3.3), (0, 2.5, 4.72), 0.46, 0.12, (1, 0, 0), "frame", taper=0.6)
    bmesh.ops.transform(m.bm, matrix=lean, verts=fin)
    # Top housing, a vent and the cargo doors on both sides.
    m.box((0.0, -1.75, 3.5), (1.4, 1.1, 0.3), None, "frame")
    m.cyl((0.75, 0.0, 3.52), 0.3, 0.3, 12, None, "frame")
    for sx in (-1, 1):
        x = sx * 2.29
        for loc, size, kind in (
            ((x, 0.55, 0.82), (0.1, 2.4, 0.12), "frame"),
            ((x, 0.55, 2.06), (0.1, 2.5, 0.16), "hazard"),
            ((x, -0.65, 1.44), (0.1, 0.12, 1.28), "frame"),
            ((x, 1.75, 1.44), (0.1, 0.12, 1.28), "frame"),
            ((sx * 2.27, 0.55, 1.44), (0.06, 0.06, 1.2), "frame"),
        ):
            m.box(loc, size, None, kind)

    def soot(p: Vector, v) -> float:
        brk = smoothstep(3.0, 5.6, p.y) * (0.75 + 0.25 * smoothstep(1.0, 3.4, p.z))
        top = 0.45 * smoothstep(0.5, 5.0, p.y) * smoothstep(2.6, 3.5, p.z)
        nose = 0.5 * smoothstep(-4.4, -6.2, p.y)
        return max(brk, top, nose)

    m.set_soot(soot)
    return m.finish((0.04, 1))


def section() -> bpy.types.Object:
    """Wreck_section: the torn-off rear section lying on its side, crushed where it hit the ground: about 3.5 m
    across (x), 3.9 m long (y, open torn end towards -Y, the aft bulkhead with one thruster mount and an empty one
    towards +Y), 2.9 m high above ground, 0.5 m below."""
    m = Mesh("Wreck_section")
    rnd = m.rnd
    n = len(RING)
    # Built in the hull's frame (y along the hull, open end at y ~ 0), then laid on its side.
    end = tear(rnd, 0.0, 1.0, -0.5, -0.3, 0.4)  # larger: torn further in
    end = [min(0.6, max(-0.3, y)) for y in end]
    mid = [y + (0.9 - y) * 0.45 for y in end]
    petal = [0.0] * n
    for start, length, size in ((9, 3, 0.35), (20, 3, 0.3)):
        for k in range(length):
            petal[(start + k) % n] = size * math.sin((k + 0.5) / length * math.pi)
    seed = 7.3
    outer = [
        ring_at(m, end, 0.0, petal, False, seed),
        ring_at(m, mid, 0.0, [p * 0.3 for p in petal], False, seed),
        ring_at(m, 0.9, 0.0, None, False, seed),
        ring_at(m, 2.0, 0.0, None, False, seed),
        ring_at(m, 2.8, 0.0, None, False, seed),
    ]
    # Aft end: drawn in a little (the tail), closed by the bulkhead.
    aft = []
    for i, (x, z) in enumerate(RING):
        p = Vector((x * 0.9, 3.25, 0.17 + z * 0.9))
        aft.append(p + crumple(Vector((x, 3.25, z)), 3.25, seed))
    aft = m.verts(aft)
    outer.append(aft)
    m.loft(outer, lambda r, i: "frame" if seg_is_belt(i) else "paint")
    cap = m.face(aft, "frame")
    bmesh.ops.triangulate(m.bm, faces=[cap])
    inner = [
        ring_at(m, [y + 0.04 for y in end], -0.12, petal, False, seed),
        ring_at(m, mid, -0.12, [p * 0.3 for p in petal], False, seed),
        ring_at(m, 1.25, -0.12, None, False, seed),
    ]
    m.loft([inner[0], outer[0]], "torn")
    m.loft(inner, "interior")
    bulk = m.face(inner[-1], "interior")
    bmesh.ops.triangulate(m.bm, faces=[bulk])
    for y, kind in ((1.45, "frame"), (2.8, "hazard")):
        o0, o1 = ring_at(m, y - 0.15, 0.07, None, False, seed), ring_at(m, y + 0.15, 0.07, None, False, seed)
        i0, i1 = ring_at(m, y - 0.15, -0.07, None, False, seed), ring_at(m, y + 0.15, -0.07, None, False, seed)
        m.loft([o0, o1], kind)
        m.loft([i1, i0], kind)
        m.loft([i0, o0], kind)
        m.loft([o1, i1], kind)
    # Thruster mounts on the aft bulkhead: one with its stub of a bell left, one torn out (dark hole).
    m.cyl((-1.0, 3.42, 1.55), 0.46, 0.34, 14, rx(90), "frame")
    m.cyl((-1.0, 3.85, 1.55), 0.42, 0.55, 14, rx(90), "nozzle", r2=0.3)
    m.cyl((1.0, 3.42, 1.55), 0.46, 0.34, 14, rx(90), "frame")
    m.cyl((1.0, 3.52, 1.55), 0.28, 0.2, 14, rx(90), "interior")
    m.box((0.0, 3.36, 2.75), (1.2, 0.16, 0.5), None, "frame")
    m.tube([(0.4, 0.5, 3.0), (0.6, -0.2, 2.6), (0.55, -0.6, 1.9), (0.7, -0.75, 1.3)], 0.05, 6, "cable")

    m.set_soot(lambda p, v: 0.9 * smoothstep(1.3, -0.2, p.y) + 0.35 * smoothstep(3.0, 4.0, p.y))
    # Lay it on its side (its +x side down), squash it and flatten the crushed underside.
    m.transform(ry(90).to_4x4())
    for v in m.bm.verts:
        z = v.co.z * 0.85
        if z < -1.2:
            z = -1.2 + (z + 1.2) * 0.4
        v.co.z = z
    lo = Vector([min(v.co[a] for v in m.bm.verts) for a in range(3)])
    hi = Vector([max(v.co[a] for v in m.bm.verts) for a in range(3)])
    m.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z - 0.5)))
    return m.finish((0.035, 1))


def panel() -> bpy.types.Object:
    """Wreck_panel: a burnt hull plate standing up out of the ground, buckled, its top torn and folded back like the
    hull's top corner: 4.6 m wide (x), up to 3.5 m high, 0.5 m below ground; the outer (painted, charred) face towards
    -Y, frame ribs on its back."""
    m = Mesh("Wreck_panel")
    rnd = m.rnd
    w, h, z0 = 4.6, 3.5, -0.5
    jag = [rnd.uniform(-0.55, 0.0) for _ in range(11)]
    jag[7], jag[8], jag[9], jag[10] = -0.7, -0.95, -1.1, -1.2  # a corner torn off

    def top(u: float) -> float:
        k = min(9, int(u * 10))
        f = u * 10 - k
        return h + jag[k] * (1 - f) + jag[k + 1] * f

    def surf(u: float, v: float) -> Vector:
        x = (u - 0.5) * w
        z = z0 + v * (top(u) - z0)
        y = 0.28 * math.sin(math.pi * v) * math.sin(math.pi * (u * 1.2 + 0.1)) + 0.55 * smoothstep(0.78, 1.0, v)
        y += mnoise.noise(Vector((x * 0.6, 3.1, z * 0.6))) * 0.12
        return Vector((x, y, z))

    def point(u: float, v: float) -> tuple[Vector, Vector]:
        e = 1e-3
        p = surf(u, v)
        du = surf(min(1, u + e), v) - surf(max(0, u - e), v)
        dv = surf(u, min(1, v + e)) - surf(u, max(0, v - e))
        return p, du.cross(dv).normalized()

    m.plate(10, 8, point, 0.12, "paint", "frame", "torn")
    # Ribs on the back, following the buckle.
    for u in (0.22, 0.62):
        pts = [surf(u, v) + Vector((0, 0.13, 0)) for v in (0.0, 0.2, 0.4, 0.6, 0.75)]
        for a, b in itertools.pairwise(pts):
            m.beam(a, b, 0.16, 0.14, (1, 0, 0))
    pts = [surf(u, 0.45) + Vector((0, 0.13, 0)) for u in (0.04, 0.3, 0.55, 0.8, 0.96)]
    for a, b in itertools.pairwise(pts):
        m.beam(a, b, 0.14, 0.14, (0, 0, 1))

    # A gunmetal frame strip across the outer face (the hull's rail belt).
    pts = [surf(u, 0.4) - Vector((0, 0.1, 0)) for u in (0.0, 0.25, 0.5, 0.75, 1.0)]
    for a, b in itertools.pairwise(pts):
        m.beam(a, b, 0.3, 0.08, (0, 0, 1))

    def soot(p: Vector, v) -> float:
        """Charred from the top and one side (where the fire came from), paint left low on the other side."""
        return 0.1 + 0.8 * smoothstep(0.6, 3.2, p.z + 0.45 * p.x) + 0.25 * mnoise.noise(p * 0.7)

    m.set_soot(soot)
    return m.finish((0.025, 2))


def debris_a() -> bpy.types.Object:
    """Wreck_debris_a: a bent box strut with a torn piece of plating still riveted to it, lying on the ground:
    about 1.8 x 0.8 m, 0.55 m high."""
    m = Mesh("Wreck_debris_a")
    pts = [Vector((-0.9, -0.1, 0.08)), Vector((0.05, 0.0, 0.16)), Vector((0.85, 0.3, 0.45))]
    m.beam(pts[0], pts[1], 0.2, 0.18, (0, 1, 0))
    m.beam(pts[1], pts[2], 0.2, 0.18, (0, 1, 0), taper=0.85)
    m.cyl(pts[1], 0.13, 0.26, 8, rx(90), "frame")

    def point(u: float, v: float) -> tuple[Vector, Vector]:
        x = -0.75 + u * 0.95
        y = 0.1 + v * 0.55
        z = 0.2 + 0.12 * math.sin(u * 2.4) + 0.1 * v * v + mnoise.noise(Vector((x * 2, y * 2, 1.7))) * 0.05
        return Vector((x, y, z)), Vector((0, 0, 1))

    m.plate(4, 3, point, 0.05, "paint", "frame", "torn")
    m.set_soot(lambda p, v: 0.35 + 0.35 * mnoise.noise(p * 1.5))
    m.transform(Matrix.Translation((0, 0, -0.12)))
    return m.finish((0.015, 2))


def debris_b() -> bpy.types.Object:
    """Wreck_debris_b: a thruster bell torn off the rear section, lying on its side and dug in: the bell about
    1.2 m long and 1.1 m across the mouth, the throat with its mount flange."""
    m = Mesh("Wreck_debris_b")
    sides = 12
    prof = [(0.0, 0.22), (0.25, 0.26), (0.55, 0.36), (0.85, 0.47), (1.15, 0.56)]
    outer, inner = [], []
    for s, r in prof:
        dent = [1 + 0.06 * mnoise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, s * 2))) for a in range(sides)]
        ang = [i / sides * math.tau for i in range(sides)]
        outer.append(m.verts([(s, math.cos(a) * r * dent[i], math.sin(a) * r * dent[i]) for i, a in enumerate(ang)]))
        inner.append(
            m.verts(
                [(s, math.cos(a) * (r - 0.04) * dent[i], math.sin(a) * (r - 0.04) * dent[i]) for i, a in enumerate(ang)]
            )
        )
    m.loft(outer, "nozzle")
    m.loft([outer[-1], inner[-1]], "torn")
    m.loft(list(reversed(inner)), "nozzle")
    m.loft([inner[0], outer[0]], "nozzle")
    m.cyl((0.05, 0, 0), 0.21, 0.02, 14, ry(90), "interior")  # a dark disc closing the throat
    m.cyl((-0.12, 0, 0), 0.3, 0.24, 14, ry(90), "frame")
    m.cyl((-0.27, 0, 0), 0.38, 0.06, 14, ry(90), "frame")
    inner_set = {v for ring in inner for v in ring}
    m.set_soot(lambda p, v: 1.0 if v in inner_set else 0.2 + 0.2 * smoothstep(0.4, 1.2, p.x))
    # Lying on its side, mouth up a little, dug in.
    m.transform(T((0.0, 0.0, 0.3), ry(-12) @ rx(20)))
    lo = Vector([min(v.co[a] for v in m.bm.verts) for a in range(3)])
    hi = Vector([max(v.co[a] for v in m.bm.verts) for a in range(3)])
    m.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z - 0.22)))
    return m.finish((0.015, 1))


def debris_c() -> bpy.types.Object:
    """Wreck_debris_c: a crumpled hull panel, folded once, one edge up: about 1.6 x 0.9 m, 0.45 m high."""
    m = Mesh("Wreck_debris_c")

    def point(u: float, v: float) -> tuple[Vector, Vector]:
        x = (u - 0.5) * 1.6
        y = (v - 0.5) * 0.9
        z = 0.32 * smoothstep(0.55, 1.0, u) + 0.08 * math.sin(v * 5 + u * 3)
        z += mnoise.noise(Vector((x * 2.2, y * 2.2, 4.2))) * 0.08
        return Vector((x, y, z)), Vector((0, 0, 1))

    m.plate(6, 4, point, 0.05, "paint", "frame", "torn")
    m.beam((-0.78, -0.4, 0.02), (-0.78, 0.4, 0.05), 0.1, 0.08, (1, 0, 0), "frame")
    m.set_soot(lambda p, v: 0.5 + 0.4 * mnoise.noise(p * 1.4))
    lowest = min(v.co.z for v in m.bm.verts)
    m.transform(Matrix.Translation((0, 0, -lowest - 0.08)))  # rests on the ground, its lowest dent 8 cm in
    return m.finish((0.015, 2))


def scorch() -> bpy.types.Object:
    """Wreck_scorch: the burnt skid mark the hauler ploughed: a flat irregular blob, 6 m x 14 m (long along Y),
    1-2 cm above the ground; "soot" darkens it towards a narrow trench down its middle, its rim fades to dust."""
    m = Mesh("Wreck_scorch")
    rnd = m.rnd
    seg = 40
    scales = [1.0, 0.8, 0.58, 0.36, 0.16]
    dark = [0.0, 0.35, 0.65, 0.85, 1.0]
    jit = [1 + 0.17 * mnoise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, 0.4))) for a in range(seg)]
    rings = []
    for k, s in enumerate(scales):
        pts = []
        for i in range(seg):
            a = i / seg * math.tau
            j = jit[i] * (1 + rnd.uniform(-0.05, 0.05) * (k > 0))
            pts.append(Vector((math.cos(a) * 3.0 * s**1.6 * j, math.sin(a) * 7.0 * s**0.6 * j, 0.01 + 0.01 * (1 - s))))
        ring = m.verts(pts)
        for v in ring:
            v[m.soot] = dark[k]
        rings.append(ring)
    m.loft(rings, "scorch")
    c = m.bm.verts.new((0, 0, 0.02))
    c[m.soot] = 1.0
    for i in range(seg):
        m.face((rings[-1][i], rings[-1][(i + 1) % seg], c), "scorch")
    return m.finish(None, fix_up=True)


BUILDERS = {
    "Wreck_hull": hull,
    "Wreck_section": section,
    "Wreck_panel": panel,
    "Wreck_debris_a": debris_a,
    "Wreck_debris_b": debris_b,
    "Wreck_debris_c": debris_c,
    "Wreck_scorch": scorch,
}


# --- material -----------------------------------------------------------------------------------------------------


class Shader:
    """Node helpers for the kit material (numbers are set, sockets linked)."""

    def __init__(self, nt: bpy.types.NodeTree):
        self.nt = nt
        self.obj = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        self.geo = nt.nodes.new("ShaderNodeNewGeometry")

    def m(self, op: str, a, b=None, c=None, clamp: bool = False) -> bpy.types.NodeSocket:
        return C._math(self.nt, op, a, b, c, clamp)

    def mix(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_float(self.nt, fac, a, b)

    def ramp(self, a: float, b: float, src) -> bpy.types.NodeSocket:
        return C._ramp(self.nt, a, b, src)

    def inv(self, x) -> bpy.types.NodeSocket:
        return self.m("SUBTRACT", 1.0, x, clamp=True)

    def noise(self, scale: float, detail: float = 4.0, rough: float = 0.6, vector=None) -> bpy.types.NodeSocket:
        """Noise Fac (about 0.5 +- 0.09)."""
        return C._noise(self.nt, scale, detail, rough, vector if vector is not None else self.obj).outputs["Fac"]

    def attr(self, name: str) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeAttribute")
        node.attribute_type = "GEOMETRY"
        node.attribute_name = name
        return node.outputs["Fac"]

    def xyz(self, vector) -> bpy.types.Node:
        node = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(vector, node.inputs["Vector"])
        return node

    def vec(self, op: str, a, b=None) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = op
        for sock, val in ((node.inputs[0], a), (node.inputs[1], b)):
            if val is None:
                continue
            if isinstance(val, bpy.types.NodeSocket):
                self.nt.links.new(val, sock)
            else:
                sock.default_value = val
        return node.outputs[0]

    def scale_color(self, col, fac) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = "SCALE"
        self.nt.links.new(col, node.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, node.inputs["Scale"])
        else:
            node.inputs["Scale"].default_value = fac
        return node.outputs[0]

    def spread(self, fac, k: float) -> bpy.types.NodeSocket:
        """Noise Fac stretched around 0.5 by `k`, clamped to 0..1."""
        return self.m("MULTIPLY_ADD", self.m("SUBTRACT", fac, 0.5), k, clamp=True, c=0.5)

    def lookup(self, kind, values: list) -> bpy.types.NodeSocket:
        """A number per kind (constant color ramp over kind / count)."""
        node = self.nt.nodes.new("ShaderNodeValToRGB")
        ramp = node.color_ramp
        ramp.interpolation = "CONSTANT"
        while len(ramp.elements) < len(values):
            ramp.elements.new(0.5)
        for i, v in enumerate(values):
            ramp.elements[i].position = i / len(values)
            ramp.elements[i].color = (v, v, v, 1.0)
        self.nt.links.new(self.m("DIVIDE", self.m("ADD", kind, 0.5), float(len(values))), node.inputs["Fac"])
        return self.m("ADD", node.outputs["Color"], 0.0)

    def line(self, coord, period: float, offset: float, width: float) -> bpy.types.NodeSocket:
        """1 on thin lines at coord = offset + k * period (seams), 0 beyond width."""
        f = self.m("FRACT", self.m("ADD", self.m("DIVIDE", self.m("ADD", coord, -offset), period), 0.5))
        dist = self.m("MULTIPLY", self.m("ABSOLUTE", self.m("SUBTRACT", f, 0.5)), period)
        return self.inv(self.ramp(width * 0.4, width, dist))

    def rect(self, u, v, u0: float, u1: float, v0: float, v1: float) -> bpy.types.NodeSocket:
        a = self.m("MULTIPLY", self.m("GREATER_THAN", u, u0), self.m("LESS_THAN", u, u1))
        b = self.m("MULTIPLY", self.m("GREATER_THAN", v, v0), self.m("LESS_THAN", v, v1))
        return self.m("MULTIPLY", a, b)

    def glyph(self, u, v, rects: list) -> bpy.types.NodeSocket:
        out = None
        for r in rects:
            g = self.rect(u, v, *r)
            out = g if out is None else self.m("MAXIMUM", out, g)
        return out


SEGMENTS = {"1": "bc", "4": "fgbc", "7": "abc", "2": "abged", "0": "abcdef"}


def digit_rects(ch: str, u0: float, v0: float, w: float, h: float, t: float) -> list:
    """Stencil digit as seven-segment bars in (u, v): box from (u0, v0), w x h, stroke t."""
    hm = h / 2
    bars = {
        "a": (u0, u0 + w, v0 + h - t, v0 + h),
        "b": (u0 + w - t, u0 + w, v0 + hm, v0 + h),
        "c": (u0 + w - t, u0 + w, v0, v0 + hm),
        "d": (u0, u0 + w, v0, v0 + t),
        "e": (u0, u0 + t, v0, v0 + hm),
        "f": (u0, u0 + t, v0 + hm, v0 + h),
        "g": (u0, u0 + w, v0 + hm - t / 2, v0 + hm + t / 2),
    }
    return [bars[s] for s in SEGMENTS[ch]]


def mat_kit() -> bpy.types.Material:
    """The kit's one material, its look picked per face by "kind": bone-white paint (per-plate tone, seams, chipped
    edges to bare steel, rust runs, grime in the recesses, dust low down), gunmetal frames, a dark sooty interior,
    charred metal, faded amber hazard stripes, black cable, torn bare steel with rust, heat-stained nozzle metal,
    dark crazed glass, the scorched ground and paint with dark stenciled numbers. Everything chars towards black-brown
    with a heat-browned halo where "soot" is high. Muted and calm: big shapes, low-contrast noise."""
    mat, nt, bsdf = C._new_material(MATERIAL)
    s = Shader(nt)
    kind = s.attr("kind")
    facet = s.attr("facet")
    soot_v = s.attr("soot")
    pos = s.xyz(s.obj)
    x, y, z = pos.outputs["X"], pos.outputs["Y"], pos.outputs["Z"]
    vt = nt.nodes.new("ShaderNodeVectorTransform")
    vt.vector_type = "NORMAL"
    vt.convert_from = "WORLD"
    vt.convert_to = "OBJECT"
    nt.links.new(s.geo.outputs["Normal"], vt.inputs["Vector"])
    nrm = s.xyz(vt.outputs["Vector"])
    nx, ny, nz = (s.m("ABSOLUTE", nrm.outputs[a]) for a in ("X", "Y", "Z"))

    def is_kind(name: str) -> bpy.types.NodeSocket:
        return s.m("COMPARE", kind, float(KINDS[name]), 0.5)

    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.35
    ao.samples = 16
    cavity = s.inv(s.ramp(0.35, 0.95, ao.outputs["AO"]))
    edge = s.ramp(0.02, 0.1, C._bevel_edge(nt, 0.035, s.geo))
    tone = s.noise(0.7, 3.0, 0.5)
    chips = s.m("MULTIPLY", edge, s.ramp(0.47, 0.56, s.noise(2.5, 4.0, 0.6)))
    seams = s.m(
        "MAXIMUM",
        s.m("MULTIPLY", s.line(x, 1.5, -4.0, 0.03), s.inv(s.ramp(0.5, 0.8, nx))),
        s.m("MULTIPLY", s.line(y, 1.5, -4.0, 0.03), s.inv(s.ramp(0.5, 0.8, ny))),
    )
    streak_vec = s.vec("MULTIPLY", s.obj, (5.0, 5.0, 0.45))
    streaks = s.m("MULTIPLY", s.ramp(0.58, 0.7, s.noise(1.0, 3.0, 0.5, streak_vec)), s.inv(s.ramp(0.4, 0.7, nz)))
    burn_in = s.m(
        "ADD",
        soot_v,
        s.m(
            "ADD",
            s.m("MULTIPLY", s.m("SUBTRACT", s.noise(0.9, 4.0, 0.6), 0.5), 1.6),
            s.m("MULTIPLY", s.m("SUBTRACT", s.noise(4.0, 3.0, 0.6), 0.5), 0.5),
        ),
    )
    soot = s.ramp(0.42, 0.66, burn_in)
    halo = s.m("MULTIPLY", s.ramp(0.15, 0.45, burn_in), s.inv(soot))
    dust = s.inv(s.ramp(0.1, 1.2, s.m("ADD", z, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(1.5, 3.0, 0.5), 0.5), 1.2))))

    # Base colors per kind.
    paint = s.scale_color(
        s.mix(s.spread(tone, 3.0), srgb(0.45, 0.44, 0.41), srgb(0.49, 0.48, 0.45)),
        s.m("MULTIPLY_ADD", facet, 0.1, 0.95),
    )
    paint = s.mix(s.m("MULTIPLY", streaks, 0.35), paint, srgb(0.36, 0.22, 0.13))
    glyphs = s.m(
        "MAXIMUM",
        s.m(
            "MULTIPLY",
            s.glyph(
                x, y, digit_rects("1", -0.75, -3.65, 0.55, 1.0, 0.16) + digit_rects("4", 0.05, -3.65, 0.6, 1.0, 0.16)
            ),
            s.ramp(0.7, 0.8, nz),
        ),
        s.m(
            "MULTIPLY",
            s.glyph(
                y, z, digit_rects("1", -3.55, 1.15, 0.45, 0.85, 0.13) + digit_rects("4", -2.95, 1.15, 0.5, 0.85, 0.13)
            ),
            s.ramp(0.7, 0.8, nx),
        ),
    )
    stencil_k = s.m("MULTIPLY", glyphs, s.m("MULTIPLY", s.ramp(0.4, 0.5, s.noise(3.0, 3.0, 0.6)), 0.85))
    stencil = s.mix(stencil_k, paint, srgb(0.19, 0.19, 0.19))
    frame = s.scale_color(
        s.mix(s.spread(tone, 2.0), srgb(0.15, 0.15, 0.16), srgb(0.18, 0.18, 0.19)), s.m("MULTIPLY_ADD", facet, 0.2, 0.9)
    )
    interior = s.mix(s.spread(tone, 2.0), srgb(0.09, 0.088, 0.085), srgb(0.13, 0.125, 0.12))
    burnt = s.mix(s.spread(s.noise(1.8, 4.0, 0.6), 3.0), srgb(0.06, 0.055, 0.05), srgb(0.15, 0.13, 0.11))
    stripes = s.ramp(0.47, 0.53, s.m("FRACT", s.m("DIVIDE", s.m("ADD", s.m("ADD", x, y), z), 0.38)))
    hazard = s.mix(stripes, srgb(0.13, 0.13, 0.13), srgb(0.64, 0.46, 0.16))
    hazard = s.mix(s.m("MULTIPLY", s.ramp(0.45, 0.6, s.noise(4.0, 3.0, 0.6)), 0.6), hazard, srgb(0.3, 0.28, 0.25))
    cable = srgb(0.045, 0.045, 0.045)
    torn = s.mix(s.ramp(0.5, 0.62, s.noise(3.0, 4.0, 0.6)), srgb(0.34, 0.33, 0.32), srgb(0.3, 0.19, 0.11))
    nozzle = s.mix(s.spread(s.noise(1.2, 3.0, 0.5), 3.0), srgb(0.12, 0.115, 0.11), srgb(0.2, 0.16, 0.13))
    nozzle = s.mix(s.m("MULTIPLY", s.ramp(0.55, 0.65, s.noise(2.0, 2.0, 0.5)), 0.6), nozzle, srgb(0.15, 0.16, 0.19))
    cracks = C._voronoi_lines(nt, s.obj, 4.0, 0.03)
    glass = s.mix(s.m("MULTIPLY", cracks, 0.6), srgb(0.03, 0.035, 0.04), srgb(0.2, 0.21, 0.22))
    furrow_vec = s.vec("MULTIPLY", s.obj, (9.0, 0.35, 1.0))
    furrows = s.spread(s.noise(1.0, 3.0, 0.5, furrow_vec), 3.0)
    scorch_k = s.ramp(0.25, 0.9, s.m("ADD", soot_v, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(0.6, 4.0, 0.6), 0.5), 1.0)))
    scorched = s.mix(scorch_k, srgb(0.2, 0.19, 0.17), srgb(0.06, 0.055, 0.05))
    scorched = s.mix(s.m("MULTIPLY", furrows, s.m("MULTIPLY", scorch_k, 0.35)), scorched, srgb(0.035, 0.032, 0.03))

    looks = [
        ("frame", frame),
        ("interior", interior),
        ("burnt", burnt),
        ("hazard", hazard),
        ("cable", cable),
        ("torn", torn),
        ("nozzle", nozzle),
        ("glass", glass),
        ("scorch", scorched),
        ("stencil", stencil),
    ]
    col = paint
    for name, c in looks:
        col = s.mix(is_kind(name), col, c)

    order = sorted(KINDS, key=KINDS.get)

    def per_kind(values: dict) -> bpy.types.NodeSocket:
        return s.lookup(kind, [values[k] for k in order])

    w_chip = per_kind({k: 1.0 if k in ("paint", "frame", "hazard", "stencil") else 0.0 for k in KINDS})
    w_seam = per_kind({k: 1.0 if k in ("paint", "stencil") else 0.0 for k in KINDS})
    w_soot = per_kind({k: 0.0 if k in ("scorch", "cable", "glass") else 1.0 for k in KINDS})
    w_dust = per_kind({k: 0.0 if k in ("scorch", "glass", "interior") else 1.0 for k in KINDS})
    w_grime = per_kind({k: 0.0 if k == "scorch" else 1.0 for k in KINDS})
    chips_k = s.m("MULTIPLY", chips, w_chip)
    seam_k = s.m("MULTIPLY", seams, w_seam)
    soot_k = s.m("MULTIPLY", soot, w_soot)
    col = s.mix(s.m("MULTIPLY", s.m("MULTIPLY", cavity, w_grime), 0.55), col, s.scale_color(col, 0.4))
    col = s.mix(s.m("MULTIPLY", seam_k, 0.7), col, srgb(0.16, 0.16, 0.16))
    col = s.mix(chips_k, col, srgb(0.36, 0.35, 0.34))
    col = s.mix(s.m("MULTIPLY", s.m("MULTIPLY", dust, w_dust), 0.5), col, srgb(0.34, 0.32, 0.28))
    col = s.mix(s.m("MULTIPLY", s.m("MULTIPLY", halo, w_soot), 0.65), col, srgb(0.26, 0.21, 0.16))
    col = s.mix(soot_k, col, srgb(0.055, 0.05, 0.045))
    nt.links.new(col, bsdf.inputs["Base Color"])

    rough = per_kind(
        {
            "paint": 0.62,
            "frame": 0.55,
            "interior": 0.8,
            "burnt": 0.85,
            "hazard": 0.6,
            "cable": 0.75,
            "torn": 0.45,
            "nozzle": 0.5,
            "glass": 0.15,
            "scorch": 0.95,
            "stencil": 0.62,
        }
    )
    rough = s.m("ADD", rough, s.m("MULTIPLY", s.m("SUBTRACT", tone, 0.5), 0.3))
    rough = s.mixf(soot_k, rough, 0.88)
    rough = s.mixf(chips_k, rough, 0.4)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    metal = per_kind(
        {k: {"frame": 0.25, "interior": 0.1, "burnt": 0.2, "torn": 0.8, "nozzle": 0.6}.get(k, 0.0) for k in KINDS}
    )
    metal = s.m("MULTIPLY", metal, s.inv(soot_k))
    metal = s.mixf(chips_k, metal, 0.7)
    nt.links.new(metal, bsdf.inputs["Metallic"])
    height = s.m(
        "SUBTRACT", s.m("MULTIPLY", s.noise(6.0, 3.0, 0.6), 0.3), s.m("ADD", seam_k, s.m("MULTIPLY", chips_k, 0.3))
    )
    height = s.mixf(is_kind("scorch"), height, s.m("MULTIPLY", furrows, 0.6))
    C._bump(nt, bsdf, height, 0.3, 0.01)
    return mat


# --- layout, preview, renders ---------------------------------------------------------------------------------

# The proposed layout in the part's own frame, in GODOT axes (Y up, the part's front towards -z): position (x, y, z)
# and rotation in degrees (x, y, z; Godot's YXZ order). The hull came down nose first towards the front (-z),
# skidded along the scorch mark and lost its rear section, which tumbled off to the side; the nose is dug in, the
# torn end raised towards the back. Crate marker (5.4, 0, -3.2) and quest anchor (2.5, 0, -5.5) stay free.
LAYOUT = {
    "Wreck_scorch": ((2.3, 0.0, 3.9), (0.0, 20.0, 0.0)),
    "Wreck_hull": ((0.8, -1.4, -0.3), (10.0, -160.0, 15.0)),
    "Wreck_section": ((-4.6, 0.0, 5.0), (0.0, 70.0, 0.0)),
    "Wreck_panel": ((-5.8, 0.0, -0.5), (8.0, 35.0, -6.0)),
    "Wreck_debris_a": ((4.4, 0.0, 2.6), (0.0, 25.0, 0.0)),
    "Wreck_debris_b": ((-1.6, 0.0, 8.4), (0.0, -30.0, 0.0)),
    "Wreck_debris_c": ((6.8, 0.0, 0.6), (0.0, 70.0, 0.0)),
}
MARKERS = {"Crate": (5.4, 0.0, -3.2), "QuestAnchor": (2.5, 0.0, -5.5)}
PROP_RADIUS = 10.0
GROUND = ((0.045, 0.042, 0.038), (0.075, 0.07, 0.063))  # linear albedo of a dusty ground
FOOTPRINT = 15.0
POLE = (5.6, 0.0, 5.2)  # the 1.89 m scale pole (Godot)
GODOT_TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def godot_matrix(pos, rot_deg) -> Matrix:
    """Blender world matrix of a piece placed at a Godot position and YXZ euler rotation."""
    ax, ay, az = (math.radians(a) for a in rot_deg)
    basis = Matrix.Rotation(ay, 3, "Y") @ Matrix.Rotation(ax, 3, "X") @ Matrix.Rotation(az, 3, "Z")
    b = GODOT_TO_BLENDER @ basis @ GODOT_TO_BLENDER.inverted()
    m = b.to_4x4()
    m.translation = GODOT_TO_BLENDER @ Vector(pos)
    return m


def gv(p) -> Vector:
    return GODOT_TO_BLENDER @ Vector(p)


def apply_layout(objs=None) -> None:
    objs = objs or {n: bpy.data.objects[n] for n in PARTS}
    for name, (pos, rot) in LAYOUT.items():
        obj = objs[name]
        obj.rotation_mode = "XYZ"
        obj.matrix_world = godot_matrix(pos, rot)
    fig = bpy.data.objects.get("PreviewFigure")
    if fig:
        fig.location = gv((4.2, 0.0, 5.6))


def apply_bake_layout(gap: float = 3.0) -> None:
    """Saved .blend layout: every piece unrotated in one row along X with `gap` m between them, so the AO bake
    never picks up a neighbor. The bake zeroes the locations before the export."""
    x = 0.0
    for name in PARTS:
        obj = bpy.data.objects[name]
        obj.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + gap
    fig = bpy.data.objects.get("PreviewFigure")
    if fig:
        fig.location = (-2.0, -2.0, 0)


def _flat_mat(name: str, color, emission: float = 0.0) -> bpy.types.Material:
    mat, _nt, bsdf = C._new_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.7
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


def layout_props() -> None:
    """Scale pole, the prop radius and footprint rings and the markers (preview only, never exported)."""
    grey = _flat_mat("PreviewPole", (0.55, 0.5, 0.42))
    ring_mat = _flat_mat("PreviewRing", (0.6, 0.6, 0.6), 0.6)
    foot_mat = _flat_mat("PreviewFoot", (0.25, 0.25, 0.25), 0.3)
    pole = _preview_mesh("PreviewPole", bpy.ops.mesh.primitive_cylinder_add, grey, vertices=12, radius=0.1, depth=1.89)
    pole.location = gv(POLE) + Vector((0, 0, 0.945))
    for name, r, mat, minor in (
        ("PreviewPropRing", PROP_RADIUS, ring_mat, 0.04),
        ("PreviewFootRing", FOOTPRINT, foot_mat, 0.03),
    ):
        ring = _preview_mesh(
            name, bpy.ops.mesh.primitive_torus_add, mat, major_radius=r, minor_radius=minor, major_segments=128
        )
        ring.location = (0, 0, 0.02)
    crate = _preview_mesh(
        "PreviewCrate", bpy.ops.mesh.primitive_cube_add, _flat_mat("PreviewCrateMat", (0.12, 0.13, 0.1)), size=1.0
    )
    crate.scale = (1.0, 0.7, 0.6)
    crate.location = gv(MARKERS["Crate"]) + Vector((0, 0, 0.3))
    crate.rotation_euler = (0, 0, math.radians(20))
    band = _preview_mesh(
        "PreviewCrateBand", bpy.ops.mesh.primitive_cube_add, _flat_mat("PreviewAmber", (1.0, 0.55, 0.12), 4.0), size=1.0
    )
    band.scale = (1.02, 0.72, 0.06)
    band.location = crate.location + Vector((0, 0, 0.05))
    band.rotation_euler = crate.rotation_euler
    anchor = _preview_mesh(
        "PreviewAnchor",
        bpy.ops.mesh.primitive_cylinder_add,
        _flat_mat("PreviewAnchorMat", (0.3, 0.7, 0.9), 2.0),
        vertices=24,
        radius=0.6,
        depth=0.04,
    )
    anchor.location = gv(MARKERS["QuestAnchor"]) + Vector((0, 0, 0.03))


def game_light(on: bool) -> None:
    """The game's look for the layout views: a weak low cool sun and a little sky instead of the studio lights."""
    for name in ("Key", "Rim", "RimLow", "Fill"):
        obj = bpy.data.objects.get(name)
        if obj:
            obj.hide_render = on
    sun = bpy.data.objects.get("GameSun")
    if sun is None:
        data = bpy.data.lights.new("GameSun", "SUN")
        data.energy = 4.0
        data.color = (0.86, 0.9, 1.0)
        data.angle = math.radians(2.0)
        sun = bpy.data.objects.new("GameSun", data)
        C.collection("Preview").objects.link(sun)
        sun.rotation_euler = (math.radians(62), 0, math.radians(66))
    sun.hide_render = not on
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.035, 0.045, 0.06, 1.0) if on else (0.012, 0.014, 0.018, 1.0)


def render_game(path: pathlib.Path, distance: float, target, samples: int, size: int) -> pathlib.Path:
    """From the game's angle: pitched 50 degrees down, 45 degrees around (from +X/-Y), 30 degree vertical field."""
    C._render_settings(samples, size)
    cam = C._camera("custom")
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(30)
    pitch = math.radians(50)
    d = Vector((math.cos(pitch) * math.sqrt(0.5), -math.cos(pitch) * math.sqrt(0.5), math.sin(pitch)))
    cam.location = Vector(target) + d * distance
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    game_light(True)
    C._write_render(path)
    game_light(False)
    return path


def setup_preview() -> None:
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    ground = bpy.data.objects["PreviewGround"]
    ground.scale = (2.5, 2.5, 1.0)
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:  # a mid-dark dusty ground, not black
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*GROUND[0], 1.0)
            node.inputs[7].default_value = (*GROUND[1], 1.0)
    layout_props()


def render_layout(prefix: str, samples: int, size: int) -> list:
    apply_layout()
    return [
        render_game(OUT / f"{prefix}layout.png", 42.0, (0.5, -0.5, 0.0), samples, size),
        render_game(OUT / f"{prefix}layout_close.png", 24.0, (0.3, -0.8, 0.8), samples, size),
    ]


def render_kit(prefix: str, views, samples: int, size: int) -> list:
    apply_layout()
    out = []
    for view in views:
        path = OUT / f"{prefix}kit_{view}.png"
        C.render(
            path, view=view, samples=samples, size=size, target=(0.5, -0.5, 1.0), zoom={"iso": 1.6, "hero": 2.6}[view]
        )
        out.append(path)
    return out


def render_part(name: str, prefix: str, views, samples: int, size: int) -> list:
    """The piece alone at the origin, framed by its size, the scale figure beside it."""
    obj = bpy.data.objects[name]
    hidden = [
        o
        for o in C.collection("Preview").objects
        if o.name.startswith(("PreviewPole", "PreviewProp", "PreviewFoot", "PreviewCrate", "PreviewAnchor"))
    ]
    for o in [bpy.data.objects[n] for n in PARTS] + hidden:
        o.hide_render = o is not obj
    keep = obj.matrix_world.copy()
    obj.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    dx, dy, dz = obj.dimensions
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
    fig.location = side * (max(dx, dy) / 2 + 0.6)
    w = max(dx, dy, dz * 1.1) * 1.25 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.4, dz * 0.4)))
    out = []
    for view in views:
        path = OUT / f"{prefix}{name}_{view}.png"
        zoom = w / (9.9 if view == "iso" else 6.3)
        C.render(path, view=view, samples=samples, size=size, target=tuple(target), zoom=zoom)
        out.append(path)
    obj.matrix_world = keep
    for o in [bpy.data.objects[n] for n in PARTS] + hidden:
        o.hide_render = False
    return out


# --- main -------------------------------------------------------------------------------------------------------


def build() -> None:
    global ROOT_OBJ, KIT_MAT
    ROOT_OBJ = C.asset_root(ASSET)
    KIT_MAT = mat_kit()
    for name in PARTS:
        BUILDERS[name]()


def report() -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for name in PARTS:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        lo = [min(v.co[a] for v in me.vertices) for a in range(3)]
        hi = [max(v.co[a] for v in me.vertices) for a in range(3)]
        dims = tuple(round(h - lo_, 2) for h, lo_ in zip(hi, lo, strict=True))
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={dims} min={tuple(round(v, 2) for v in lo)} max={tuple(round(v, 2) for v in hi)}"
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
        sheet = render_layout("final_", 96, 1024)
        sheet += render_kit("final_", ("iso", "hero"), 64, 1024)
        for name in PARTS:
            sheet += render_part(name, "final_", ("iso", "hero"), 32, 640)
        C.contact_sheet(sheet, OUT / "sheet.png", tile=512, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "wreck_procedural.blend")
        return
    wip = OUT / "wip"
    for view in VIEWS:
        if view == "layout":
            render_game(wip / f"{TAG}_layout.png", 42.0, (0.5, -0.5, 0.0), 32, 900)
        elif view == "layout_close":
            render_game(wip / f"{TAG}_layout_close.png", 24.0, (0.3, -0.8, 0.8), 32, 900)
        elif view in ("kit_iso", "kit_hero"):
            render_kit(f"wip/{TAG}_", (view[4:],), 24, 900)
        elif view == "pieces":
            for name in PARTS:
                render_part(name, f"wip/{TAG}_", ("iso", "hero"), 20, 512)
        elif view in BUILDERS:
            render_part(view, f"wip/{TAG}_", ("iso", "hero"), 24, 640)
        elif view == "sheet":
            names = sorted(wip.glob(f"{TAG}_*.png"))
            C.contact_sheet(names, wip / f"{TAG}_sheet.png", tile=512, background=0.02)
        elif view == "save":
            apply_bake_layout()
            C.save_blend(OUT / "wreck_procedural.blend")
            return


if __name__ == "__main__":
    main()
