"""Waypost Ostra's dressing props, one model each: cargo containers (red, blue, olive), crates and cases, a strapped
crate stack, drums on a spill pallet, a cable drum, a wall screen, a work light, a hydroponic planter, a cargo
lifter, a hand cart, a wall pipe bundle, a station machine block and a ship's docking clamp.

Run from the repo root:
    tools/blender.sh assets/space_station/ostra/source/ostra_dressing_build.py [names...]

No names builds all of them. Each writes assets/space_station/ostra/props/<name>.glb (an asset root empty named in
PascalCase after it) and renders an iso-like and an eye-level preview to tmp/ostra_dressing/, plus a contact sheet
of every model rendered so far (tmp/ostra_dressing/sheet.png).

Godot axes (x right, y up, z towards the camera) are Blender's (x, -z, y): a model's front (Godot +z) faces
Blender -Y. Sizes are the collision boxes the game places; the origin is the floor at the footprint's center
unless a model says otherwise. The materials are plain placeholders named for the game (OstraLook swaps in the
station's own by name), so only the names below are used.
"""

import itertools
import json
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
PROPS = ROOT / "assets" / "space_station" / "ostra" / "props"
OUT = ROOT / "tmp" / "ostra_dressing"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))  # ostra_materials

import bpy
from mathutils import Matrix, Vector

import common as C
from ostra_materials import material

PAINT, DARK, METAL, GRATING, HAZARD = "OstraPaint", "OstraPaintDark", "OstraMetal", "OstraGrating", "OstraHazard"
RUBBER, FABRIC, SCREEN, LAMP = "OstraRubber", "OstraFabric", "OstraScreen", "OstraLamp"
AMBER, RED, PLANT, ORANGE = "OstraAmber", "OstraRed", "OstraPlant", "OstraOrange"

SHARP = math.radians(50)  # edges bent more than this shade hard (boxes, flanges), less stays smooth (cylinders)
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


def spline(pts: list, steps: int) -> list:
    """Catmull-Rom through the points, `steps` samples per span (1 keeps the polyline)."""
    pts = [Vector(p) for p in pts]
    if steps <= 1 or len(pts) < 3:
        return pts
    ext = [pts[0] * 2 - pts[1], *pts, pts[-1] * 2 - pts[-2]]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1 : i + 3]
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
    out.append(pts[-1])
    return out


def arc(corner, d_in, d_out, radius: float, n: int = 6) -> list:
    """A pipe bend's points where a run along d_in turns into d_out (perpendicular) at `corner`."""
    corner, d_in, d_out = Vector(corner), Vector(d_in), Vector(d_out)
    center = corner - d_in * radius + d_out * radius
    return [
        center - d_out * radius * math.cos(a) + d_in * radius * math.sin(a)
        for a in (math.pi / 2 * i / n for i in range(n + 1))
    ]


def corrugation(u0: float, u1: float, pitch: float, depth: float) -> list:
    """A trapezoid corrugation profile ((u, depth in) pairs) from u0 to u1, starting and ending on an outer flat."""
    n = max(1, round((u1 - u0) / pitch))
    p = (u1 - u0) / n
    pts = []
    for i in range(n):
        u = u0 + i * p
        pts += [(u, 0.0), (u + 0.38 * p, 0.0), (u + 0.45 * p, depth), (u + 0.93 * p, depth)]
    return [*pts, (u1, 0.0)]


SEGMENTS = {"a": (0.5, 1.0, 0), "b": (1.0, 0.75, 1), "c": (1.0, 0.25, 1), "d": (0.5, 0.0, 0)}
SEGMENTS |= {"e": (0.0, 0.25, 1), "f": (0.0, 0.75, 1), "g": (0.5, 0.5, 0)}
DIGITS = {"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg"}
DIGITS |= {"7": "abc", "8": "abcdefg", "9": "abcdfg"}


class P(C.Part):
    """common's Part with materials by name (only the used ones end up on the mesh), hard edges marked sharp,
    and a few more primitives: tubes, lathes, corrugated sheets, tori, leaves and stencilled digits."""

    def __init__(self, name: str, bevel: tuple[float, int] | None = (0.012, 1)):
        super().__init__(name, [], bevel)
        self.names: list[str] = []

    def _tag(self, verts, mi, smooth: bool = True):
        if mi not in self.names:
            self.names.append(mi)
        return super()._tag(verts, self.names.index(mi), smooth)

    def _faces(self, faces: list, mi: str) -> None:
        for f in faces:
            f.normal_update()
        self._tag([v for f in faces for v in f.verts], mi)

    def tube(self, pts, r: float, mi: str, seg: int = 10, steps: int = 3, caps: bool = True) -> None:
        """A round tube along the points (smoothed by a spline unless steps=1)."""
        path = spline(pts, steps)
        n = len(path)
        tangents = [(path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized() for i in range(n)]
        t0 = tangents[0]
        ref = Z if abs(t0.z) < 0.9 else X
        normal = (ref - t0 * ref.dot(t0)).normalized()
        rings = []
        for p, t in zip(path, tangents):
            normal = (normal - t * normal.dot(t)).normalized()  # parallel transport: no twist along the path
            side = t.cross(normal)
            rings.append(
                [
                    self.bm.verts.new(p + (normal * math.cos(a) + side * math.sin(a)) * r)
                    for a in (math.tau * k / seg for k in range(seg))
                ]
            )
        faces = []
        for a, b in itertools.pairwise(rings):
            for k in range(seg):
                faces.append(self.bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k])))
        if caps:
            faces += [self.bm.faces.new(list(reversed(rings[0]))), self.bm.faces.new(rings[-1])]
        self._faces(faces, mi)

    def lathe(self, profile: list, mi: str, m: Matrix, seg: int = 16, caps: bool = True) -> None:
        """Turn a profile ((r, z) pairs, bottom to top) about local +Z, placed by m."""
        rings = [
            [self.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), z))) for a in _angles(seg)]
            for r, z in profile
        ]
        faces = []
        for a, b in itertools.pairwise(rings):
            for k in range(seg):
                faces.append(self.bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k])))
        if caps:
            faces += [self.bm.faces.new(list(reversed(rings[0]))), self.bm.faces.new(rings[-1])]
        self._faces(faces, mi)

    def sheet(self, origin, u_dir, v_dir, prof: list, vs: list, mi: str, dents=()) -> None:
        """A single-sided corrugated sheet: profile (u, depth in) along u_dir, rows at vs along v_dir, its face
        towards u_dir x v_dir. dents: (u, v, radius, depth) pushed in."""
        origin, u_dir, v_dir = Vector(origin), Vector(u_dir), Vector(v_dir)
        n = u_dir.cross(v_dir)
        grid = []
        for u, d in prof:
            col = []
            for v in vs:
                push = d
                for du, dv, rad, depth in dents:
                    dist = math.hypot(u - du, v - dv) / rad
                    push += depth * max(0.0, 1.0 - dist * dist)
                col.append(self.bm.verts.new(origin + u_dir * u + v_dir * v - n * push))
            grid.append(col)
        faces = []
        for a, b in itertools.pairwise(grid):
            for j in range(len(vs) - 1):
                faces.append(self.bm.faces.new((a[j], b[j], b[j + 1], a[j + 1])))
        self._faces(faces, mi)

    def torus(self, center, normal, radius: float, r: float, mi: str, seg: int = 20, seg2: int = 8) -> None:
        center, n = Vector(center), Vector(normal).normalized()
        u = (X if abs(n.x) < 0.9 else Y).cross(n).normalized()
        v = n.cross(u)
        grid = [
            [
                self.bm.verts.new(
                    center + (u * math.cos(a) + v * math.sin(a)) * (radius + r * math.cos(b)) + n * r * math.sin(b)
                )
                for b in _angles(seg2)
            ]
            for a in _angles(seg)
        ]
        faces = []
        for i in range(seg):
            a, b = grid[i], grid[(i + 1) % seg]
            for j in range(seg2):
                faces.append(self.bm.faces.new((a[j], b[j], b[(j + 1) % seg2], a[(j + 1) % seg2])))
        self._faces(faces, mi)

    def leaf(self, base, azimuth: float, elevation: float, length: float, width: float, mi: str = PLANT) -> None:
        """A thin diamond leaf from `base` pointing along azimuth/elevation (degrees)."""
        a, e = math.radians(azimuth), math.radians(elevation)
        d = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
        side = Vector((-math.sin(a), math.cos(a), 0.0))
        n = d.cross(side)
        m = Matrix((d, side, n)).transposed().to_4x4()
        m.translation = Vector(base)
        pts = [(0.0, 0.0), (length * 0.4, -width / 2), (length, 0.0), (length * 0.4, width / 2)]
        self.prism(pts, -0.004, 0.004, m=m, mi=mi)

    def stencil(self, text: str, origin, right, up, h: float, mi: str = PAINT) -> None:
        """Seven-segment digits (a stencilled number) on a face, raised 6 mm along right x up."""
        right, up = Vector(right), Vector(up)
        rot = Matrix((right, up, right.cross(up))).transposed()
        w, t = 0.55 * h, 0.14 * h
        for i, ch in enumerate(text):
            for s in DIGITS.get(ch, ""):
                sx, sy, vertical = SEGMENTS[s]
                loc = Vector(origin) + right * (i * w * 1.5 + sx * w) + up * (sy * h)
                self.box(loc, (t, h / 2, 0.006) if vertical else (w, t, 0.006), rot=rot, mi=mi)

    def finish(self, parent) -> bpy.types.Object:
        for e in self.bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > SHARP:
                e.smooth = False
        self.mats = [material(n) for n in self.names]
        return super().finish(parent)


def _angles(seg: int) -> list:
    return [math.tau * k / seg for k in range(seg)]


class Frame:
    """A local frame (a crate in a stack, on a cart): places boxes, tubes and points of a sub-assembly."""

    def __init__(self, loc=(0, 0, 0), deg: float = 0.0):
        self.m = C.T(loc, C.rz(deg))
        self.r = C.rz(deg)

    def pt(self, x: float, y: float, z: float) -> Vector:
        return self.m @ Vector((x, y, z))

    def box(self, p: P, loc, size, mi: str) -> None:
        p.box(self.pt(*loc), size, rot=self.r, mi=mi)


# --- crates (shared by the crates, the stack and the cart) ---------------------------------------------------------


def add_crate(p: P, f: Frame, sx: float, sy: float, sz: float, body: str = PAINT, trim: str = DARK, simple=False):
    """A ribbed steel crate (sx x sy x sz, standing on f's origin): skids, corner posts, belts, a lid, handles."""
    k = min(sx, sy, sz)
    skid, lid, e, post = 0.05 * k, 0.07 * k, 0.03 * k, 0.07 * k
    h = sz - skid - lid  # the body between skids and lid
    zc = skid + h / 2
    for s in (-1, 1):
        f.box(p, (0, s * (sy / 2 - 0.12 * k), skid / 2), (sx - 0.04 * k, 0.1 * k, skid), trim)
    f.box(p, (0, 0, zc), (sx - 2 * e, sy - 2 * e, h), body)
    f.box(p, (0, 0, sz - lid / 2), (sx - 0.01, sy - 0.01, lid), body)
    for sxs in (-1, 1):
        for sys_ in (-1, 1):
            f.box(p, (sxs * (sx / 2 - post / 2), sys_ * (sy / 2 - post / 2), zc), (post, post, h), trim)
    for frac in (0.3, 0.68) if not simple else (0.5,):
        f.box(p, (0, 0, skid + frac * h), (sx - 0.012 * k, sy - 0.012 * k, 0.05 * k), trim)
    if simple:
        return
    for s in (-1, 1):
        for t in (-1, 1):
            f.box(p, (t * sx * 0.2, s * (sy / 2 - e), zc), (0.06 * k, 0.03 * k, h), trim)  # ribs
            f.box(p, (s * (sx / 2 - e), t * sy * 0.2, zc), (0.03 * k, 0.06 * k, h), trim)
        f.box(p, (0, s * sy * 0.22, sz + 0.012 * k), (sx * 0.8, 0.06 * k, 0.025 * k), trim)  # lid ridges
        f.box(p, (s * sx * 0.3, -sy / 2 + e - 0.012 * k, sz - lid - 0.02 * k), (0.07 * k, 0.03 * k, 0.09 * k), METAL)
        zh, xo = skid + 0.5 * h, sx / 2 - e
        p.tube(
            [f.pt(s * xo, -0.16 * k, zh), f.pt(s * (xo + 0.04 * k), -0.13 * k, zh)]
            + [f.pt(s * (xo + 0.04 * k), 0.13 * k, zh), f.pt(s * xo, 0.16 * k, zh)],
            0.014 * k,
            METAL,
            seg=6,
            steps=2,
        )
    f.box(p, (sx * 0.22, -sy / 2 + e - 0.004, skid + 0.84 * h), (0.24 * k, 0.008, 0.11 * k), HAZARD)  # label


def add_case(p: P, f: Frame, sx: float, sy: float, sz: float, body: str = PAINT, band: str = HAZARD, simple=False):
    """A long equipment case along x: base and lid with a seam, ribs, hazard end bands, latches, end handles."""
    k = min(sy, sz)
    foot, seam, gap = 0.05 * k, 0.6 * sz, 0.02 * k
    for s in (-1, 1):
        f.box(p, (0, s * (sy / 2 - 0.15 * k), foot / 2), (sx - 0.1 * k, 0.1 * k, foot), RUBBER)
    f.box(p, (0, 0, (foot + seam) / 2), (sx - 0.04 * k, sy - 0.04 * k, seam - foot), body)
    f.box(p, (0, 0, (seam + gap + sz) / 2), (sx - 0.04 * k, sy - 0.04 * k, sz - seam - gap), body)
    f.box(p, (0, 0, seam + gap / 2), (sx - 0.1 * k, sy - 0.1 * k, gap + 0.01), DARK)  # the seam's groove
    ribs = max(1, round(sx / 0.8) - 1)
    for i in range(ribs):
        x = -sx / 2 + sx * (i + 1) / (ribs + 1)
        f.box(p, (x, 0, (foot + sz) / 2), (0.06 * k, sy, sz - foot), body)
    for s in (-1, 1):
        f.box(p, (s * (sx / 2 - 0.07 * k), 0, (foot + sz) / 2), (0.14 * k, sy, sz - foot), band)
    if simple:
        return
    for i in range(ribs + 1):
        x = -sx / 2 + sx * (i + 0.5) / (ribs + 1)
        f.box(p, (x, -sy / 2 + 0.01 * k, seam + gap / 2), (0.08 * k, 0.04 * k, 0.12 * k), METAL)
    for s in (-1, 1):
        z, xo = 0.62 * sz, sx / 2
        p.tube(
            [f.pt(s * xo, -0.15 * k, z), f.pt(s * (xo + 0.025 * k), -0.12 * k, z)]
            + [f.pt(s * (xo + 0.025 * k), 0.12 * k, z), f.pt(s * xo, 0.15 * k, z)],
            0.014 * k,
            METAL,
            seg=6,
            steps=2,
        )


def add_pallet(p: P, sx: float, sy: float, h: float, mi: str = DARK) -> None:
    """A steel pallet: top boards on three runners."""
    boards = max(3, round(sx / 0.26))
    for i in range(boards):
        x = -sx / 2 + (i + 0.5) * sx / boards
        p.box((x, 0, h - 0.015), (sx / boards - 0.03, sy, 0.03), mi=mi)
    for s in (-1, 0, 1):
        p.box((0, s * (sy / 2 - 0.06), (h - 0.03) / 2), (sx, 0.12, h - 0.03), mi=mi)


# --- containers --------------------------------------------------------------------------------------------------


def build_container(root, body: str) -> None:
    """A 20-foot-like container, 6.0 x 2.6 x 2.44 (long along x), its doors at x = +3."""
    n = root.name
    hx, hy, h = 3.0, 1.22, 2.6
    fr = P(n + "Frame", bevel=(0.012, 1))
    dt = P(n + "Detail", bevel=None)
    wl = P(n + "Walls", bevel=None)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (0.059, h - 0.059):
                fr.box((sx * (hx - 0.089), sy * (hy - 0.081), z), (0.178, 0.162, 0.118), mi=DARK)
            fr.box((sx * (hx - 0.08), sy * (hy - 0.075), h / 2), (0.15, 0.14, h - 0.236), mi=body)
        # Casting holes: dark recesses on the castings' faces.
        for sy in (-1, 1):
            for z in (0.059, h - 0.059):
                dt.box((sx * (hx - 0.089), sy * (hy + 0.001), z), (0.1, 0.004, 0.05), mi=RUBBER)
    for sy in (-1, 1):
        fr.box((0, sy * (hy - 0.05), 0.105), (2 * hx - 0.356, 0.1, 0.17), mi=body)
        fr.box((0, sy * (hy - 0.045), h - 0.06), (2 * hx - 0.356, 0.09, 0.12), mi=body)
        for x in (-0.95, 0.95):  # forklift pockets
            dt.box((x, sy * (hy + 0.0005), 0.105), (0.36, 0.004, 0.1), mi=RUBBER)
    for sx in (-1, 1):
        fr.box((sx * (hx - 0.06), 0, 0.12), (0.12, 2 * hy - 0.324, 0.2), mi=body)
        fr.box((sx * (hx - 0.06), 0, h - 0.075), (0.12, 2 * hy - 0.324, 0.15), mi=body)
    # Corrugated walls and roof, a few dents.
    vs = [0.19, 0.8, 1.6, 2.54]
    side = corrugation(-2.845, 2.845, 0.285, 0.04)
    wl.sheet((0, -hy + 0.006, 0), X, Z, side, vs, body, dents=[(-1.3, 1.1, 0.45, 0.035), (1.75, 0.6, 0.35, 0.03)])
    wl.sheet((0, hy - 0.006, 0), -X, Z, side, vs, body, dents=[(0.6, 1.9, 0.5, 0.035)])
    wl.sheet((-hx + 0.012, 0, 0), -Y, Z, corrugation(-1.075, 1.075, 0.27, 0.04), [0.22, 1.3, 2.45], body)
    roof = corrugation(-2.88, 2.88, 0.4, 0.02)
    wl.sheet((0, 0, h - 0.012), X, Y, roof, [-1.13, 0.0, 1.13], body, dents=[(-0.6, 0.1, 0.7, 0.025)])
    # Doors: two leaves with frames, four locking bars with cam keepers, handles and guides, hinges.
    for y0, y1 in ((-1.075, -0.005), (0.005, 1.075)):
        wl.sheet((hx - 0.035, 0, 0), Y, Z, corrugation(y0 + 0.06, y1 - 0.06, 0.2, 0.025), [0.3, 1.3, 2.37], body)
        for y in (y0 + 0.035, y1 - 0.035):
            fr.box((hx - 0.025, y, 1.335), (0.05, 0.07, 2.23), mi=body)
        for z in (0.265, 2.405):
            fr.box((hx - 0.025, (y0 + y1) / 2, z), (0.05, y1 - y0, 0.09), mi=body)
        mid = (y0 + y1) / 2
        for y in (mid - 0.22, mid + 0.22):
            dt.rod((hx + 0.025, y, 0.3), (hx + 0.025, y, 2.37), 0.022, seg=8, mi=METAL)
            for z in (0.27, 2.4):
                dt.box((hx + 0.022, y, z), (0.045, 0.08, 0.07), mi=DARK)
            for z in (0.75, 1.9):
                dt.box((hx + 0.02, y, z), (0.04, 0.075, 0.035), mi=DARK)
            toward = -1 if y > 0 else 1
            dt.box((hx + 0.04, y + toward * 0.11, 1.12), (0.025, 0.24, 0.04), mi=METAL)
            dt.box((hx + 0.03, y + toward * 0.22, 1.12), (0.03, 0.03, 0.08), mi=DARK)
    for sy in (-1, 1):
        for z in (0.5, 1.05, 1.6, 2.15):
            dt.rod((hx + 0.005, sy * 1.06, z - 0.07), (hx + 0.005, sy * 1.06, z + 0.07), 0.028, seg=8, mi=METAL)
    # Stencilled numbers on both long sides and a plate on the door.
    for sy, right in ((-1, X), (1, -X)):
        o = Vector((-2.55 * right.x, sy * (hy - 0.003), 0))
        dt.stencil("4471", o + Vector((0, 0, 1.98)), right, Z, 0.3)
    dt.box((hx - 0.032, 0.54, 1.75), (0.006, 0.34, 0.22), mi=PAINT)
    for part in (fr, dt, wl):
        part.finish(root)


# --- crates ------------------------------------------------------------------------------------------------------


def build_crate_small(root) -> None:
    p = P(root.name + "Body")
    add_crate(p, Frame(), 1.2, 1.2, 1.2)
    p.finish(root)


def build_crate_long(root) -> None:
    p = P(root.name + "Body")
    add_case(p, Frame(), 2.4, 1.2, 1.2)
    p.finish(root)


def build_crate_stack(root) -> None:
    """Crates and cases on a pallet (2.4 cube), strapped down."""
    p = P(root.name + "Body")
    add_pallet(p, 2.4, 2.4, 0.14)
    z1 = 0.14
    add_case(p, Frame((0, 0.6, z1)), 2.3, 1.12, 1.15, simple=True)  # back row, along x
    add_crate(p, Frame((-0.58, -0.6, z1), 2), 1.14, 1.12, 1.15, body=PAINT, simple=True)
    add_crate(p, Frame((0.6, -0.6, z1), -3), 1.06, 1.1, 1.0, body=DARK, trim=PAINT, simple=True)
    z2 = z1 + 1.15
    add_case(p, Frame((-0.56, 0.0, z2), 90), 2.2, 1.0, 0.95, body=DARK, band=HAZARD, simple=True)
    add_crate(p, Frame((0.6, 0.6, z2), 4), 0.95, 0.95, 0.95, simple=True)
    add_crate(p, Frame((0.62, -0.58, z1 + 1.0), -8), 0.7, 0.7, 0.6, body=ORANGE, simple=True)
    # Straps: two front to back over the left column, one side to side over the back row.
    top = z2 + 0.95 + 0.008
    for x in (-0.8, -0.32):
        pts = [(x, -1.19, 0.12), (x, -1.19, z2 + 0.005), (x, -1.11, z2 + 0.005), (x, -1.11, top)]
        pts += [(x, 1.11, top), (x, 1.11, z2 + 0.005), (x, 1.17, z2 + 0.005), (x, 1.17, 0.12)]
        strap(p, pts)
    y = 0.75
    pts = [(-1.17, y, 0.12), (-1.17, y, z2 + 0.005), (-1.07, y, z2 + 0.005), (-1.07, y, top)]
    pts += [(1.08, y, top), (1.08, y, z2 + 0.005), (1.17, y, z2 + 0.005)]
    pts += [(1.17, y, 0.12)]
    strap(p, pts)
    p.finish(root)


def strap(p: P, pts: list, w: float = 0.06, mi: str = ORANGE) -> None:
    """A flat cargo strap along the points (beams, a buckle on the first upright)."""
    pts = [Vector(q) for q in pts]
    for a, b in itertools.pairwise(pts):
        if (b - a).length < 1e-4:
            continue
        d = (b - a).normalized()
        side = X if abs(d.x) < 0.5 else Y
        p.beam(a, b, w, 0.012, side, mi=mi)
    a, b = pts[0], pts[1]
    p.box(a.lerp(b, 0.55), (0.09 if abs(a.x) < 1.0 else 0.03, 0.03 if abs(a.x) < 1.0 else 0.09, 0.1), mi=METAL)


# --- barrels -----------------------------------------------------------------------------------------------------


def drum_profile(r: float, h: float) -> list:
    """A steel drum: chimes top and bottom, two rolling hoops, a recessed lid."""
    hoops = []
    for z in (h * 0.33, h * 0.66):
        hoops += [(r, z - 0.018), (r + 0.01, z - 0.01), (r + 0.01, z + 0.01), (r, z + 0.018)]
    return [
        (r - 0.015, 0.0),
        (r, 0.012),
        *hoops,
        (r, h - 0.012),
        (r + 0.004, h),
        (r - 0.012, h),
        (r - 0.016, h - 0.015),
    ]


def build_barrels(root) -> None:
    """Four drums on a spill pallet, one with a hand pump (1.2 x 1.0 x 1.2)."""
    n = root.name
    p = P(n + "Pallet")
    d = P(n + "Drums", bevel=None)
    # Spill pallet: a tray with a grating on top, on feet.
    p.box((0, 0, 0.05), (1.2, 1.2, 0.06), mi=DARK)
    for s in (-1, 1):
        p.box((s * 0.585, 0, 0.065), (0.03, 1.2, 0.07), mi=ORANGE)
        p.box((0, s * 0.585, 0.065), (1.17, 0.03, 0.07), mi=ORANGE)
        for t in (-1, 1):
            p.box((s * 0.45, t * 0.45, 0.01), (0.18, 0.18, 0.02), mi=DARK)
    p.box((0, 0, 0.092), (1.14, 1.14, 0.016), mi=GRATING)
    h, r, z0 = 0.82, 0.29, 0.1
    colors = {(-1, -1): DARK, (1, -1): ORANGE, (-1, 1): PAINT, (1, 1): DARK}
    for (sx, sy), mi in colors.items():
        c = Vector((sx * 0.3, sy * 0.3, z0))
        spin = C.rz(sx * 37 + sy * 11).to_4x4()
        d.lathe(drum_profile(r, h), mi, C.T(c) @ spin, seg=18)
        d.cyl(c + spin @ Vector((0.17, 0.05, h - 0.008)), 0.032, 0.02, seg=8, mi=METAL)
        if (sx, sy) != (1, -1):
            d.cyl(c + spin @ Vector((-0.15, -0.1, h - 0.01)), 0.022, 0.015, seg=8, mi=METAL)
    # Hand pump on the orange drum: a riser, a head with a lever lying flat, a hose down the drum's front.
    top = z0 + h - 0.015
    px, py = 0.22, -0.24
    d.rod((px, py, top), (px, py, 0.985), 0.022, seg=8, mi=METAL)
    p.box((px, py, 0.995), (0.08, 0.07, 0.05), mi=DARK)
    p.beam((px + 0.02, py, 1.01), (px + 0.3, py + 0.06, 1.03), 0.025, 0.02, Z, mi=ORANGE)
    d.rod((px + 0.27, py + 0.055, 1.03), (px + 0.33, py + 0.065, 1.033), 0.016, seg=8, mi=RUBBER)
    d.tube(
        [(px, py - 0.04, 0.99), (px - 0.01, py - 0.2, 1.0), (px + 0.02, -0.57, 0.95), (px + 0.03, -0.605, 0.78)]
        + [(px + 0.0, -0.607, 0.6), (px - 0.03, -0.605, 0.5)],
        0.014,
        RUBBER,
        seg=8,
    )
    d.rod((px - 0.03, -0.605, 0.5), (px - 0.035, -0.605, 0.44), 0.012, seg=8, mi=METAL)
    p.finish(root)
    d.finish(root)


# --- cable spool -------------------------------------------------------------------------------------------------


def build_cable_spool(root) -> None:
    """A cable drum lying on its side (axis along Godot z) on a low stand, a loose end on the floor."""
    n = root.name
    st = P(n + "Stand")
    sp = P(n + "Drum", bevel=None)
    cz, fr = 0.63, 0.52
    along = C.rx(-90).to_4x4()  # local +Z along Blender +Y (Godot -z)
    # The wound cable: ridges of turns between the flanges.
    turns = 9
    prof = []
    for i in range(2 * turns + 1):
        prof.append((0.4 + (0.026 if i % 2 else 0.0), -0.41 + 0.82 * i / (2 * turns)))
    sp.lathe(prof, RUBBER, C.T((0, 0, cz)) @ along, seg=22)
    for s in (-1, 1):
        y = s * 0.43
        sp.rod((0, y - 0.02, cz), (0, y + 0.02, cz), fr, seg=28, mi=PAINT)
        sp.rod((0, y - 0.03, cz), (0, y + 0.03, cz), fr - 0.02, seg=28, mi=PAINT)
        sp.rod((0, y + s * 0.02, cz), (0, y + s * 0.06, cz), 0.12, seg=12, mi=DARK)
        for k in range(6):
            a = math.radians(k * 60 + 15)
            mid = Vector((math.cos(a) * 0.3, y + s * 0.035, cz + math.sin(a) * 0.3))
            sp.box(mid, (0.36, 0.02, 0.05), rot=C.ry(-math.degrees(a)), mi=DARK)
    sp.rod((0, -0.53, cz), (0, 0.53, cz), 0.045, seg=10, mi=METAL)
    # Stand: an A-frame each side, base rails and ties, bearing blocks.
    for s in (-1, 1):
        y = s * 0.49
        for t in (-1, 1):
            st.beam((t * 0.44, y, 0.05), (t * 0.05, y, cz - 0.02), 0.06, 0.05, Y, mi=DARK)
        st.box((0, y, 0.025), (1.0, 0.06, 0.05), mi=DARK)
        st.box((0, y, cz), (0.16, 0.06, 0.14), mi=ORANGE)
    for t in (-1, 1):
        st.box((t * 0.44, 0, 0.025), (0.06, 0.98, 0.05), mi=DARK)
    # The loose end: off the drum's side, down to the floor, along the front, a plug.
    sp.tube(
        [(0.41, 0.12, 0.8), (0.43, 0.12, 0.6), (0.47, 0.1, 0.35), (0.53, 0.05, 0.1), (0.56, -0.1, 0.04)]
        + [(0.55, -0.33, 0.035), (0.42, -0.47, 0.035), (0.15, -0.5, 0.04)],
        0.033,
        RUBBER,
        seg=10,
        steps=4,
    )
    sp.rod((0.15, -0.5, 0.042), (0.02, -0.5, 0.042), 0.042, seg=10, mi=DARK)
    sp.rod((0.02, -0.5, 0.042), (-0.02, -0.5, 0.042), 0.03, seg=10, mi=METAL)
    st.finish(root)
    sp.finish(root)


# --- wall screen -------------------------------------------------------------------------------------------------


def build_wall_screen(root) -> None:
    """A teal info screen in a chunky frame, its origin at the middle of its back face, facing Godot +z."""
    n = root.name
    fr = P(n + "Frame", bevel=(0.01, 1))
    dt = P(n + "Detail", bevel=None)
    w, h, d = 1.6, 1.0, 0.12
    b = 0.1  # border
    for z in (-1, 1):
        fr.box((0, -d / 2, z * (h / 2 - b / 2)), (w, d, b), mi=DARK)
    for x in (-1, 1):
        fr.box((x * (w / 2 - b / 2), -d / 2, 0), (b, d, h - 2 * b), mi=DARK)
    fr.box((0, -0.02, 0), (w - 2 * b + 0.02, 0.04, h - 2 * b + 0.02), mi=DARK)  # back plate
    # Bezel stepping in to the screen.
    for z in (-1, 1):
        fr.box((0, -0.085, z * (h / 2 - b - 0.015)), (w - 2 * b, 0.03, 0.03), mi=PAINT)
    for x in (-1, 1):
        fr.box((x * (w / 2 - b - 0.015), -0.085, 0), (0.03, 0.03, h - 2 * b - 0.06), mi=PAINT)
    sw, sh = w - 2 * b - 0.06, h - 2 * b - 0.06
    dt.box((0, -0.075, 0), (sw, 0.01, sh), mi=SCREEN)
    # Panels on the screen: a header line, a column divider, rows in the left panel.
    dt.box((0, -0.082, sh / 2 - 0.11), (sw - 0.04, 0.004, 0.012), mi=DARK)
    dt.box((0.22, -0.082, -0.06), (0.012, 0.004, sh - 0.2), mi=DARK)
    for i in range(5):
        dt.box((-0.27, -0.082, 0.12 - i * 0.085), (0.66, 0.004, 0.006), mi=DARK)
    dt.box((0.4, -0.082, -0.15), (0.26, 0.004, 0.2), mi=DARK)
    dt.box((-sw / 2 + 0.07, -0.082, sh / 2 - 0.05), (0.08, 0.004, 0.035), mi=AMBER)
    # Bolts on the frame, status lights on the bottom border.
    for x in (-0.74, -0.25, 0.25, 0.74):
        for z in (-0.45, 0.45):
            dt.rod((x, -d, z), (x, -d - 0.01, z), 0.018, seg=6, mi=METAL)
    for z in (-0.18, 0.18):
        for x in (-0.75, 0.75):
            dt.rod((x, -d, z), (x, -d - 0.01, z), 0.018, seg=6, mi=METAL)
    dt.rod((-0.55, -d, -0.45), (-0.55, -d - 0.008, -0.45), 0.014, seg=8, mi=AMBER)
    dt.rod((-0.5, -d, -0.45), (-0.5, -d - 0.008, -0.45), 0.014, seg=8, mi=RED)
    # The cable: out of the bottom, down the wall in a clip, into a junction box (hangs below the box).
    dt.rod((0.55, -0.045, -0.5), (0.55, -0.045, -0.53), 0.03, seg=8, mi=METAL)
    dt.tube([(0.55, -0.045, -0.52), (0.56, -0.04, -0.66), (0.6, -0.03, -0.8), (0.62, -0.03, -0.9)], 0.018, RUBBER)
    fr.box((0.6, -0.025, -0.78), (0.07, 0.05, 0.03), mi=METAL)
    fr.box((0.62, -0.035, -0.96), (0.14, 0.07, 0.12), mi=DARK)
    fr.finish(root)
    dt.finish(root)


# --- work light --------------------------------------------------------------------------------------------------


def build_work_light(root) -> None:
    """A tripod work light (0.7 x 2.2 x 0.7) with two warm lamp heads and a cable."""
    n = root.name
    fr = P(n + "Frame", bevel=(0.008, 1))
    dt = P(n + "Detail", bevel=None)
    hub = 0.9
    for k in range(3):
        a = math.radians(90 + k * 120 + 30)
        foot = Vector((math.cos(a) * 0.31, math.sin(a) * 0.31, 0.03))
        dt.rod(foot, (math.cos(a) * 0.04, math.sin(a) * 0.04, hub), 0.02, seg=8, mi=DARK)
        dt.rod(foot - Vector((0, 0, 0.03)), foot + Vector((0, 0, 0.02)), 0.035, seg=8, mi=RUBBER)
        mid = foot.lerp(Vector((0, 0, hub)), 0.45)
        dt.rod(mid, (0, 0, 0.45), 0.011, seg=6, mi=METAL)
    dt.rod((0, 0, 0.42), (0, 0, 0.48), 0.04, seg=10, mi=DARK)
    dt.rod((0, 0, hub - 0.04), (0, 0, hub + 0.05), 0.048, seg=10, mi=DARK)
    dt.rod((0, 0, 0.35), (0, 0, 1.5), 0.03, seg=10, mi=DARK)
    dt.rod((0, 0, 1.5), (0, 0, 1.94), 0.022, seg=10, mi=METAL)
    dt.rod((0, 0, 1.47), (0, 0, 1.53), 0.04, seg=10, mi=ORANGE)
    dt.rod((0, -0.04, 1.5), (0, -0.09, 1.5), 0.012, seg=6, mi=ORANGE)  # clamp knob
    fr.box((0, 0.045, 1.15), (0.12, 0.06, 0.16), mi=DARK)  # ballast box with a switch light
    dt.rod((0.03, 0.075, 1.2), (0.03, 0.082, 1.2), 0.01, seg=6, mi=AMBER)
    fr.box((0, 0, 1.955), (0.62, 0.04, 0.04), mi=DARK)
    for x in (-0.16, 0.16):
        for s in (-1, 1):
            fr.box((x + s * 0.145, 0, 2.015), (0.015, 0.04, 0.12), mi=DARK)
            dt.rod((x + s * 0.137, 0, 2.065), (x + s * 0.162, 0, 2.065), 0.02, seg=8, mi=METAL)
        head = C.T((x, -0.005, 2.065), C.rx(15))
        rot = C.rx(15)
        fr.box(head @ Vector((0, 0, 0)), (0.26, 0.1, 0.19), rot=rot, mi=ORANGE)
        fr.box(head @ Vector((0, -0.052, 0)), (0.27, 0.012, 0.2), rot=rot, mi=DARK)  # bezel
        dt.box(head @ Vector((0, -0.06, 0)), (0.22, 0.008, 0.15), rot=rot, mi=LAMP)
        for z in (-0.06, -0.02, 0.02, 0.06):
            dt.box(head @ Vector((0, 0.06, z)), (0.22, 0.025, 0.012), rot=rot, mi=DARK)  # cooling fins
    dt.tube(
        [(0.05, 0.05, 2.03), (0.03, 0.04, 1.9), (0.035, 0.03, 1.6), (0.04, 0.035, 1.2), (0.04, 0.05, 0.85)]
        + [(0.1, 0.12, 0.45), (0.18, 0.22, 0.05), (0.24, 0.3, 0.018), (0.3, 0.33, 0.018)],
        0.012,
        RUBBER,
        seg=6,
    )
    fr.finish(root)
    dt.finish(root)


# --- planter -----------------------------------------------------------------------------------------------------


def build_planter(root) -> None:
    """A hydroponic trough on legs (2.4 x 1.0 x 0.8) with plants, a grow lamp bar on two posts up to 1.9 m."""
    n = root.name
    fr = P(n + "Trough", bevel=(0.01, 1))
    dt = P(n + "Plants", bevel=None)
    hx, hy, z0, z1 = 1.18, 0.38, 0.42, 0.74
    fr.box((0, 0, z0 + 0.02), (2 * hx, 2 * hy, 0.04), mi=PAINT)
    for s in (-1, 1):
        fr.box((0, s * (hy - 0.025), (z0 + z1) / 2), (2 * hx, 0.05, z1 - z0), mi=PAINT)
        fr.box((s * (hx - 0.025), 0, (z0 + z1) / 2), (0.05, 2 * hy - 0.1, z1 - z0), mi=PAINT)
        fr.box((0, s * (hy - 0.025), z1 + 0.01), (2 * hx + 0.02, 0.07, 0.02), mi=METAL)  # rim
        for t in (-1, 1):
            fr.box((t * (hx - 0.08), s * (hy - 0.08), z0 / 2), (0.06, 0.06, z0), mi=DARK)
        fr.box((s * (hx - 0.08), 0, 0.12), (0.04, 2 * hy - 0.16, 0.04), mi=DARK)
    fr.box((0, -0.3, 0.12), (2 * hx - 0.16, 0.04, 0.04), mi=DARK)
    for x in (-0.6, 0.0, 0.6):
        fr.box((x, -hy - 0.005, (z0 + z1) / 2), (0.05, 0.02, z1 - z0), mi=DARK)  # ribs
    fr.box((-0.9, -hy - 0.012, 0.62), (0.18, 0.008, 0.08), mi=HAZARD)  # label
    dt.box((0, 0, z1 - 0.06), (2 * hx - 0.1, 2 * hy - 0.1, 0.04), mi=RUBBER)  # growth medium
    dt.rod((0.95, hy - 0.05, z0 + 0.05), (0.95, hy - 0.05, 0.05), 0.02, seg=8, mi=DARK)  # drain
    # Plants: two staggered rows of leafy clumps.
    rnd = random.Random(7)
    soil = z1 - 0.04
    for row, y in enumerate((-0.15, 0.15)):
        for i in range(8):
            x = -1.02 + i * 0.29 + (0.14 if row else 0.0) + rnd.uniform(-0.03, 0.03)
            if x > 1.06:
                continue
            leaves = rnd.randint(9, 11)
            for j in range(leaves):
                az = j * 360 / leaves + rnd.uniform(-15, 15)
                el = rnd.uniform(25, 40) if j % 2 else rnd.uniform(45, 70)  # an outer ring and an inner tuft
                length = rnd.uniform(0.2, 0.3) if j % 2 else rnd.uniform(0.15, 0.24)
                reach = math.cos(math.radians(el)) * length
                tip = Vector((x, y, 0)) + Vector((math.cos(math.radians(az)), math.sin(math.radians(az)), 0)) * reach
                if abs(tip.y) > 0.4 or abs(tip.x) > 1.17:
                    length *= 0.55
                dt.leaf((x, y, soil), az, el, length, rnd.uniform(0.1, 0.15))
    # Grow lamp: two posts at the back, a top bar, two arms, the lamp bar over the plants, a cable.
    py = hy - 0.05
    for s in (-1, 1):
        fr.box((s * (hx - 0.03), py, (z0 + 1.9) / 2), (0.05, 0.05, 1.9 - z0), mi=METAL)
        fr.box((s * (hx - 0.12), py / 2, 1.86), (0.04, py + 0.06, 0.04), mi=DARK)
    fr.box((0, py, 1.875), (2 * hx, 0.05, 0.05), mi=DARK)
    fr.box((0, 0, 1.82), (2 * hx - 0.12, 0.14, 0.06), mi=DARK)
    dt.box((0, 0, 1.788), (2 * hx - 0.2, 0.1, 0.006), mi=LAMP)
    dt.tube([(-1.0, 0.05, 1.85), (-1.08, 0.2, 1.87), (-1.12, py - 0.03, 1.7), (-1.12, py - 0.035, 0.8)], 0.012, RUBBER)
    fr.finish(root)
    dt.finish(root)


# --- lifter ------------------------------------------------------------------------------------------------------


def wheel(p: P, x: float, y: float, r: float, w: float, side: int) -> None:
    """A tyre (rounded lathe) on a hub, its axis along x."""
    m = C.T((x, y, r), C.ry(90))
    p.lathe(
        [(r * 0.55, -w / 2), (r * 0.9, -w / 2), (r, -w * 0.32), (r, w * 0.32), (r * 0.9, w / 2), (r * 0.55, w / 2)],
        RUBBER,
        m,
        seg=20,
        caps=False,
    )
    p.rod((x - w * 0.46, y, r), (x + w * 0.46, y, r), r * 0.58, seg=16, mi=DARK)
    p.rod((x + side * w * 0.46, y, r), (x + side * w * 0.52, y, r), r * 0.25, seg=10, mi=METAL)


def build_lifter(root) -> None:
    """A small cargo lifter (1.4 x 2.2 x 2.6, long along Godot z), its forks towards Godot +z."""
    n = root.name
    b = P(n + "Body", bevel=(0.025, 2))
    fr = P(n + "Frame", bevel=(0.01, 1))
    dt = P(n + "Detail", bevel=None)
    # Chassis, cowl, hood under the seat, counterweight with a hazard band.
    b.box((0, 0.27, 0.465), (0.96, 1.24, 0.57), mi=ORANGE)
    b.box((0, -0.2, 0.92), (0.86, 0.28, 0.34), mi=ORANGE)
    b.box((0, 0.55, 0.81), (0.9, 0.56, 0.12), mi=ORANGE)
    cw = [(0.85, 0.2), (1.2, 0.2), (1.3, 0.34), (1.3, 0.86), (1.2, 1.0), (0.85, 1.0)]
    swap = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # local (x, y, z) -> (Y, Z, X)
    b.prism(cw, -0.55, 0.55, m=swap, mi=ORANGE)
    dt.box((0, 1.305, 0.45), (1.0, 0.012, 0.12), mi=HAZARD)
    for s in (-1, 1):
        dt.box((s * 0.556, 1.07, 0.45), (0.012, 0.36, 0.12), mi=HAZARD)
        fr.box((s * 0.59, -0.2, 0.64), (0.24, 0.66, 0.04), mi=DARK)  # fenders
        fr.box((s * 0.585, 0.88, 0.52), (0.22, 0.5, 0.04), mi=DARK)
    fr.box((0, 0.13, 0.755), (0.8, 0.4, 0.02), mi=DARK)  # floor plate
    # Seat, steering, levers.
    fr.box((0, 0.56, 0.9), (0.5, 0.44, 0.06), mi=DARK)
    b.box((0, 0.55, 0.96), (0.48, 0.42, 0.08), mi=FABRIC)
    b.box((0, 0.79, 1.17), (0.48, 0.09, 0.42), rot=C.rx(-10), mi=FABRIC)
    dt.rod((0, -0.2, 1.05), (0, 0.04, 1.32), 0.03, seg=8, mi=DARK)
    dt.torus((0, 0.06, 1.34), (0, 0.5, 1), 0.16, 0.016, RUBBER, seg=18, seg2=6)
    dt.rod((-0.15, 0.06, 1.34), (0.15, 0.06, 1.34), 0.012, seg=6, mi=DARK)
    for i, x in enumerate((0.22, 0.28, 0.34)):
        dt.rod((x, -0.12, 1.08), (x, -0.06, 1.3 - i * 0.03), 0.01, seg=6, mi=METAL)
        dt.rod((x, -0.06, 1.3 - i * 0.03), (x, -0.06, 1.33 - i * 0.03), 0.02, seg=8, mi=RED if i == 0 else DARK)
    # Wheels.
    for s in (-1, 1):
        wheel(dt, s * 0.59, -0.2, 0.3, 0.2, s)
        wheel(dt, s * 0.585, 0.88, 0.24, 0.18, s)
    # Overhead guard.
    for s in (-1, 1):
        fr.beam((s * 0.44, -0.28, 0.75), (s * 0.44, -0.12, 2.0), 0.06, 0.06, X, mi=DARK)
        fr.beam((s * 0.44, 0.95, 1.0), (s * 0.44, 0.95, 2.0), 0.06, 0.06, X, mi=DARK)
        fr.box((s * 0.44, 0.41, 2.0), (0.06, 1.16, 0.06), mi=DARK)
        fr.box((s * 0.44, -0.24, 1.45), (0.1, 0.08, 0.08), mi=DARK)  # headlights
        dt.box((s * 0.44, -0.283, 1.45), (0.07, 0.008, 0.055), mi=LAMP)
    for i in range(5):
        fr.box((0, -0.06 + i * 0.22, 2.0), (0.88, 0.06, 0.03), mi=DARK)
    dt.rod((0.32, 0.86, 2.015), (0.32, 0.86, 2.1), 0.045, seg=10, mi=AMBER)
    # Mast: outer and inner channels, crossheads, lift cylinder, chains.
    for s in (-1, 1):
        fr.box((s * 0.32, -0.47, 1.15), (0.08, 0.12, 2.1), mi=DARK)
        fr.box((s * 0.24, -0.53, 1.06), (0.06, 0.08, 1.9), mi=METAL)
        dt.box((s * 0.1, -0.5, 1.25), (0.03, 0.02, 1.4), mi=DARK)
        dt.rod((s * 0.44, -0.33, 0.62), (s * 0.36, -0.45, 1.0), 0.035, seg=8, mi=METAL)  # tilt cylinders
    fr.box((0, -0.47, 2.16), (0.72, 0.1, 0.08), mi=DARK)
    fr.box((0, -0.47, 0.22), (0.72, 0.1, 0.08), mi=DARK)
    fr.box((0, -0.5, 1.98), (0.54, 0.08, 0.06), mi=DARK)
    dt.rod((0, -0.42, 0.25), (0, -0.42, 1.5), 0.045, seg=12, mi=DARK)
    dt.rod((0, -0.42, 1.5), (0, -0.42, 1.95), 0.03, seg=12, mi=METAL)
    # Carriage with a load backrest, forks.
    fr.box((0, -0.6, 0.38), (0.92, 0.06, 0.4), mi=DARK)
    for x in (-0.42, -0.14, 0.14, 0.42):
        fr.box((x, -0.6, 0.86), (0.04, 0.03, 0.6), mi=DARK)
    fr.box((0, -0.6, 1.16), (0.92, 0.03, 0.04), mi=DARK)
    for s in (-1, 1):
        x = s * 0.28
        fr.box((x, -0.645, 0.3), (0.12, 0.05, 0.52), mi=METAL)
        fr.beam((x, -0.66, 0.07), (x, -1.29, 0.06), 0.12, 0.05, X, mi=METAL, taper=0.8)
    b.finish(root)
    fr.finish(root)
    dt.finish(root)


# --- hand cart ---------------------------------------------------------------------------------------------------


def build_hand_cart(root) -> None:
    """A flat hand cart (0.8 x 1.0 x 1.4) with a push handle at its back, two small crates on it."""
    n = root.name
    fr = P(n + "Frame", bevel=(0.008, 1))
    dt = P(n + "Detail", bevel=None)
    fr.box((0, 0, 0.215), (0.78, 1.24, 0.05), mi=DARK)
    dt.box((0, -0.02, 0.246), (0.72, 1.14, 0.012), mi=RUBBER)
    for s in (-1, 1):
        fr.box((s * 0.385, 0, 0.215), (0.02, 1.26, 0.06), mi=METAL)
        for t in (-1, 1):
            x, y = s * 0.29, t * 0.5
            fr.box((x, y, 0.182), (0.1, 0.1, 0.016), mi=METAL)
            fr.box((x, y, 0.13), (0.07, 0.04, 0.09), mi=METAL)
            dt.rod((x - 0.022, y, 0.075), (x + 0.022, y, 0.075), 0.075, seg=14, mi=RUBBER)
            dt.rod((x - 0.025, y, 0.075), (x + 0.025, y, 0.075), 0.03, seg=8, mi=DARK)
    dt.tube(
        [(-0.34, 0.6, 0.22), (-0.34, 0.64, 0.8), (-0.33, 0.67, 0.95), (-0.27, 0.68, 0.98), (0.27, 0.68, 0.98)]
        + [(0.33, 0.67, 0.95), (0.34, 0.64, 0.8), (0.34, 0.6, 0.22)],
        0.018,
        ORANGE,
        seg=10,
        steps=3,
    )
    dt.rod((-0.2, 0.68, 0.98), (0.2, 0.68, 0.98), 0.024, seg=10, mi=RUBBER)
    for s in (-1, 1):
        fr.box((s * 0.34, 0.6, 0.27), (0.05, 0.06, 0.06), mi=DARK)
    add_crate(fr, Frame((0.0, -0.24, 0.252), 4), 0.56, 0.56, 0.44)
    add_case(fr, Frame((0.02, 0.33, 0.252), -7), 0.56, 0.34, 0.28, body=DARK)
    fr.finish(root)
    dt.finish(root)


# --- pipe cluster ------------------------------------------------------------------------------------------------


def build_pipe_cluster(root) -> None:
    """A vertical bundle of pipes on a wall (1.2 x 4.0 x 0.6, its back at Godot z = -0.3): flanges, a gate valve, a
    ball valve, a gauge, wall rails with clamps."""
    n = root.name
    fr = P(n + "Mounts", bevel=(0.008, 1))
    pp = P(n + "Pipes", bevel=None)
    pipes = [  # x, y, r, material, path
        (-0.32, 0.08, 0.13, PAINT, [(-0.32, 0.08, 0.0), *arc((-0.32, 0.08, 3.8), Z, Y, 0.2), (-0.32, 0.3, 3.8)]),
        (0.0, 0.12, 0.08, DARK, [(0.0, 0.12, 0.0), (0.0, 0.12, 4.0)]),
        (0.3, 0.09, 0.1, METAL, [(0.3, 0.3, 0.32), *arc((0.3, 0.09, 0.32), -Y, Z, 0.16), (0.3, 0.09, 4.0)]),
        (0.52, 0.2, 0.045, DARK, [(0.52, 0.2, 0.0), (0.52, 0.2, 4.0)]),
    ]
    for _x, _y, r, mi, path in pipes:
        pp.tube(path, r, mi, seg=16 if r > 0.06 else 10, steps=1)
    flanges = {0: (0.12, 1.3, 2.6, 3.5), 1: (0.1, 2.0, 3.3), 2: (1.1, 2.4, 3.5), 3: ()}
    for i, zs in flanges.items():
        x, y, r = pipes[i][:3]
        for z in zs:
            pp.rod((x, y, z - 0.03), (x, y, z + 0.03), r + 0.035, seg=16, mi=DARK)
    pp.rod((-0.32, 0.26, 3.8), (-0.32, 0.3, 3.8), 0.18, seg=16, mi=DARK)  # wall flanges
    pp.rod((0.3, 0.26, 0.32), (0.3, 0.3, 0.32), 0.15, seg=16, mi=DARK)
    for i in (0, 1, 3):
        x, y, r = pipes[i][:3]
        fr.box((x, y, 0.02), (2 * r + 0.12, 2 * r + 0.12, 0.04), mi=DARK)
    # Wall rails with clamps and stand-offs.
    for z in (0.9, 2.2, 3.4):
        fr.box((0, 0.275, z), (1.2, 0.05, 0.06), mi=DARK)
        for x, y, r, _mi, _path in pipes:
            pp.rod((x, y, z - 0.025), (x, y, z + 0.025), r + 0.012, seg=16, mi=METAL)
            if y + r < 0.25:
                fr.box((x, (y + r + 0.25) / 2, z), (0.05, 0.25 - y - r, 0.04), mi=METAL)
    # Gate valve on the big pipe: body, bonnet, hand wheel.
    pp.rod((-0.32, 0.08, 1.08), (-0.32, 0.08, 1.42), 0.18, seg=16, mi=DARK)
    pp.rod((-0.32, -0.05, 1.25), (-0.32, -0.2, 1.25), 0.05, seg=10, mi=DARK)
    pp.rod((-0.32, -0.2, 1.25), (-0.32, -0.26, 1.25), 0.016, seg=6, mi=METAL)
    pp.torus((-0.32, -0.25, 1.25), Y, 0.13, 0.016, ORANGE, seg=18, seg2=6)
    for k in range(3):
        a = math.radians(90 + k * 120)
        pp.rod((-0.32, -0.25, 1.25), (-0.32 + math.cos(a) * 0.13, -0.25, 1.25 + math.sin(a) * 0.13), 0.01, 6, ORANGE)
    # Ball valve on the bare pipe with a lever.
    fr.box((0.3, 0.09, 1.65), (0.24, 0.24, 0.2), mi=DARK)
    fr.box((0.3, -0.05, 1.68), (0.06, 0.04, 0.05), mi=METAL)
    fr.beam((0.3, -0.055, 1.69), (0.53, -0.07, 1.7), 0.035, 0.015, Z, mi=ORANGE)
    # Gauge on the thin pipe.
    pp.rod((0.0, 0.05, 1.75), (0.0, -0.07, 1.75), 0.02, seg=8, mi=METAL)
    pp.rod((0.0, -0.07, 1.75), (0.0, -0.12, 1.75), 0.09, seg=16, mi=METAL)
    pp.rod((0.0, -0.12, 1.75), (0.0, -0.124, 1.75), 0.078, seg=16, mi=PAINT)
    pp.box((0.02, -0.126, 1.77), (0.006, 0.003, 0.065), rot=C.ry(-40), mi=DARK)
    pp.box((-0.04, -0.126, 1.72), (0.03, 0.003, 0.012), rot=C.ry(30), mi=RED)
    # Hazard bands and a junction box on the conduit with a light.
    for x, y, r, z in ((0.3, 0.09, 0.1, 2.0), (-0.32, 0.08, 0.13, 2.05)):
        pp.rod((x, y, z - 0.06), (x, y, z + 0.06), r + 0.004, seg=16, mi=HAZARD)
    fr.box((0.52, 0.17, 1.4), (0.14, 0.1, 0.22), mi=DARK)
    pp.rod((0.52, 0.12, 1.45), (0.52, 0.11, 1.45), 0.016, seg=8, mi=AMBER)
    fr.finish(root)
    pp.finish(root)


# --- machine block -----------------------------------------------------------------------------------------------


def build_machine_block(root) -> None:
    """A station machine (3.0 x 3.0 x 2.0): a casing with vents, a fan, pipes going in, an access door and a
    control panel with amber and red lights and a teal screen."""
    n = root.name
    cs = P(n + "Casing", bevel=(0.02, 1))
    dt = P(n + "Detail", bevel=None)
    cs.box((0, 0, 0.075), (2.9, 1.9, 0.15), mi=DARK)
    dt.box((0, -0.955, 0.075), (2.8, 0.012, 0.07), mi=HAZARD)
    fy = -0.85  # the casing's front
    cs.box((0, 0, 1.275), (2.6, 1.7, 2.25), mi=PAINT)
    cs.box((0, 0, 2.45), (2.7, 1.8, 0.1), mi=DARK)
    cs.box((0, 0.05, 2.65), (2.3, 1.4, 0.3), mi=PAINT)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cs.box((sx * 1.28, sy * 0.83, 1.275), (0.1, 0.1, 2.25), mi=DARK)
    cs.box((0, 0, 2.25), (2.64, 1.74, 0.06), mi=DARK)
    # Top fan.
    dt.rod((0.45, 0.05, 2.8), (0.45, 0.05, 2.92), 0.42, seg=24, mi=DARK)
    dt.rod((0.45, 0.05, 2.92), (0.45, 0.05, 2.93), 0.38, seg=24, mi=GRATING)
    dt.rod((0.45, 0.05, 2.93), (0.45, 0.05, 2.95), 0.07, seg=10, mi=DARK)
    # Pipes: into the top from the ceiling, down the sides into the casing.
    for x, y, r in ((-0.6, 0.3, 0.1), (-0.2, 0.4, 0.07)):
        dt.rod((x, y, 2.8), (x, y, 3.0), r, seg=14, mi=METAL)
        dt.rod((x, y, 2.8), (x, y, 2.86), r + 0.035, seg=14, mi=DARK)
    side_pipes = [
        ([(-1.43, 0.3, 3.0), *arc((-1.43, 0.3, 1.6), -Z, X, 0.1), (-1.25, 0.3, 1.6)], 0.06, PAINT),
        ([(-1.43, -0.35, 0.0), *arc((-1.43, -0.35, 1.0), Z, X, 0.1), (-1.25, -0.35, 1.0)], 0.055, DARK),
        ([(1.43, 0.5, 3.0), *arc((1.43, 0.5, 1.9), -Z, -X, 0.1), (1.25, 0.5, 1.9)], 0.06, METAL),
    ]
    for path, r, mi in side_pipes:
        dt.tube(path, r, mi, seg=14, steps=1)
        end = Vector(path[-1])
        out = 1 if end.x > 0 else -1
        dt.rod(end, end + Vector((out * 0.05, 0, 0)), r + 0.04, seg=14, mi=DARK)
    # Front: a louvred vent, an access door, a control panel.
    vx0, vx1, vz0, vz1 = -1.15, -0.25, 0.55, 1.75
    for z in (vz0, vz1):
        cs.box(((vx0 + vx1) / 2, fy - 0.025, z), (vx1 - vx0 + 0.08, 0.05, 0.06), mi=DARK)
    for x in (vx0, vx1):
        cs.box((x, fy - 0.025, (vz0 + vz1) / 2), (0.06, 0.05, vz1 - vz0), mi=DARK)
    dt.box(((vx0 + vx1) / 2, fy - 0.002, (vz0 + vz1) / 2), (vx1 - vx0, 0.004, vz1 - vz0), mi=RUBBER)
    slats = 9
    for i in range(slats):
        z = vz0 + (i + 0.5) * (vz1 - vz0) / slats
        cs.box(((vx0 + vx1) / 2, fy - 0.03, z), (vx1 - vx0 - 0.04, 0.1, 0.018), rot=C.rx(40), mi=GRATING)
    dx0, dx1, dz0, dz1 = -0.05, 0.75, 0.3, 2.1
    cs.box(((dx0 + dx1) / 2, fy - 0.01, (dz0 + dz1) / 2), (dx1 - dx0, 0.02, dz1 - dz0), mi=PAINT)
    for z in (dz0, dz1):
        cs.box(((dx0 + dx1) / 2, fy - 0.02, z), (dx1 - dx0 + 0.05, 0.03, 0.05), mi=DARK)
    for x in (dx0, dx1):
        cs.box((x, fy - 0.02, (dz0 + dz1) / 2), (0.05, 0.03, dz1 - dz0), mi=DARK)
        if x == dx0:
            for z in (0.6, 1.8):
                dt.rod((x, fy - 0.045, z - 0.08), (x, fy - 0.045, z + 0.08), 0.025, seg=8, mi=METAL)
    cs.box((0.64, fy - 0.06, 1.2), (0.03, 0.03, 0.28), mi=METAL)
    for z in (1.08, 1.32):
        cs.box((0.64, fy - 0.035, z), (0.03, 0.04, 0.03), mi=METAL)
    dt.box((0.35, fy - 0.022, 1.75), (0.32, 0.006, 0.16), mi=HAZARD)
    px, pz = 1.05, 1.45
    cs.box((px, fy - 0.07, pz), (0.42, 0.14, 0.7), mi=DARK)
    dt.box((px, fy - 0.143, pz + 0.17), (0.32, 0.008, 0.2), mi=SCREEN)
    for i, x in enumerate((px - 0.12, px - 0.06, px, px + 0.06, px + 0.12)):
        dt.rod((x, fy - 0.14, pz - 0.03), (x, fy - 0.16, pz - 0.03), 0.02, seg=8, mi=AMBER if i < 3 else RED)
    for x in (px - 0.12, px - 0.06, px):
        dt.box((x, fy - 0.15, pz - 0.13), (0.02, 0.03, 0.04), mi=METAL)
    dt.rod((px + 0.1, fy - 0.14, pz - 0.18), (px + 0.1, fy - 0.17, pz - 0.18), 0.035, seg=12, mi=RED)
    cs.box((px + 0.13, fy - 0.03, 2.0), (0.06, 0.05, 0.42), mi=DARK)  # conduit up from the panel
    # +x side: a big round fan grille.
    fan = (1.3, -0.2, 1.0)
    dt.rod(fan, (1.38, -0.2, 1.0), 0.45, seg=24, mi=DARK)
    dt.rod((1.38, -0.2, 1.0), (1.39, -0.2, 1.0), 0.41, seg=24, mi=GRATING)
    dt.rod((1.39, -0.2, 1.0), (1.41, -0.2, 1.0), 0.08, seg=10, mi=DARK)
    # -x side: a small vent.
    cs.box((-1.31, 0.05, 0.45), (0.03, 0.6, 0.3), mi=GRATING)
    cs.finish(root)
    dt.finish(root)


# --- docking clamp -----------------------------------------------------------------------------------------------


def build_clamp(root) -> None:
    """A docking clamp: a rubber-faced pad 2.5 x 1.6 x 0.6 centered at the origin (its face at Godot z = -0.3
    presses the hull), a hydraulic arm 1.2 x 0.8 x 4.0 behind it centered at Godot z = +2.3."""
    n = root.name
    pd = P(n + "Pad", bevel=(0.02, 1))
    arm = P(n + "Arm", bevel=(0.012, 1))
    dt = P(n + "Detail", bevel=None)
    # Pad: body, back stiffeners, three rubber blocks on the hull side, hazard caps on its ends.
    pd.box((0, -0.06, 0), (2.5, 0.36, 1.6), mi=DARK)
    for z in (-0.5, 0.5):
        pd.box((0, -0.27, z), (2.2, 0.06, 0.1), mi=DARK)
    for x in (-1.0, -0.62, 0.62, 1.0):
        pd.box((x, -0.27, 0), (0.1, 0.06, 1.4), mi=DARK)
    for x in (-0.8, 0.0, 0.8):
        pd.box((x, 0.21, 0), (0.76, 0.18, 1.48), mi=RUBBER)
    for s in (-1, 1):
        pd.box((s * 1.18, -0.06, 0), (0.14, 0.38, 1.62), mi=HAZARD)
    # Clevis on the pad and the rod's eye.
    for s in (-1, 1):
        arm.box((s * 0.22, -0.44, 0), (0.08, 0.32, 0.6), mi=DARK)
    arm.rod((-0.3, -0.48, 0), (0.3, -0.48, 0), 0.06, seg=12, mi=METAL)
    arm.rod((-0.17, -0.48, 0), (0.17, -0.48, 0), 0.15, seg=16, mi=METAL)
    # Rod, gland, end caps, barrel with a hazard band, tie rods.
    dt.rod((0, -0.58, 0), (0, -1.95, 0), 0.16, seg=20, mi=METAL)
    arm.rod((0, -1.8, 0), (0, -1.93, 0), 0.26, seg=20, mi=DARK)
    arm.box((0, -2.02, 0), (0.84, 0.2, 0.78), mi=DARK)
    dt.rod((0, -2.12, 0), (0, -3.75, 0), 0.34, seg=24, mi=PAINT)
    dt.rod((0, -3.24, 0), (0, -3.36, 0), 0.345, seg=24, mi=HAZARD)
    arm.box((0, -3.85, 0), (0.84, 0.2, 0.78), mi=DARK)
    for sx in (-1, 1):
        for sz in (-1, 1):
            dt.rod((sx * 0.36, -1.9, sz * 0.33), (sx * 0.36, -3.97, sz * 0.33), 0.025, seg=8, mi=METAL)
    # Rear clevis and the mount plate with bolts.
    for s in (-1, 1):
        arm.box((s * 0.3, -4.06, 0), (0.08, 0.32, 0.5), mi=DARK)
        for t in (-1, 1):
            dt.rod((s * 0.48, -4.2, t * 0.3), (s * 0.48, -4.17, t * 0.3), 0.04, seg=8, mi=METAL)
    arm.rod((-0.38, -4.04, 0), (0.38, -4.04, 0), 0.07, seg=12, mi=METAL)
    arm.rod((-0.24, -4.04, 0), (0.24, -4.04, 0), 0.14, seg=16, mi=DARK)
    arm.box((0, -4.25, 0), (1.2, 0.1, 0.8), mi=DARK)
    # Hydraulic hoses from the end caps' ports along the sides to the mount.
    for s in (-1, 1):
        dt.rod((s * 0.42, -2.0, 0.2), (s * 0.47, -2.0, 0.2), 0.035, seg=8, mi=METAL)
        dt.tube(
            [(s * 0.46, -2.0, 0.2), (s * 0.52, -2.12, 0.2), (s * 0.53, -3.0, 0.24), (s * 0.53, -3.95, 0.26)]
            + [(s * 0.5, -4.17, 0.25)],
            0.028,
            RUBBER,
            seg=8,
        )
        dt.rod((s * 0.42, -3.85, -0.18), (s * 0.47, -3.85, -0.18), 0.035, seg=8, mi=METAL)
        dt.tube([(s * 0.46, -3.85, -0.18), (s * 0.52, -3.97, -0.2), (s * 0.5, -4.17, -0.24)], 0.028, RUBBER, seg=8)
    pd.finish(root)
    arm.finish(root)
    dt.finish(root)


# --- models, previews --------------------------------------------------------------------------------------------

MODELS = {  # name: (builder, preview: lift above the floor, wall at this Blender y or None)
    "container_red": (lambda r: build_container(r, "OstraContainerRed"), 0.0, None),
    "container_blue": (lambda r: build_container(r, "OstraContainerBlue"), 0.0, None),
    "container_olive": (lambda r: build_container(r, "OstraContainerOlive"), 0.0, None),
    "crate_small": (build_crate_small, 0.0, None),
    "crate_long": (build_crate_long, 0.0, None),
    "crate_stack": (build_crate_stack, 0.0, None),
    "barrels": (build_barrels, 0.0, None),
    "cable_spool": (build_cable_spool, 0.0, None),
    "wall_screen": (build_wall_screen, 1.6, 0.0),
    "work_light": (build_work_light, 0.0, None),
    "planter": (build_planter, 0.0, None),
    "lifter": (build_lifter, 0.0, None),
    "hand_cart": (build_hand_cart, 0.0, None),
    "pipe_cluster": (build_pipe_cluster, 0.0, 0.3),
    "machine_block": (build_machine_block, 0.0, None),
    "clamp": (build_clamp, 1.3, None),
}


VIEWS = ("iso", "eye", "side")  # previews: iso-like, eye level from the front, close from the right


def pascal(name: str) -> str:
    return "".join(w.capitalize() for w in name.split("_"))


def preview(name: str, root: bpy.types.Object, st: dict, lift: float, wall: float | None) -> list:
    """Renders from an iso-like view (35 degrees down along the diagonal) and from eye level."""
    lo, hi = Vector(st["min"]), Vector(st["max"])
    C.preview_scene(crystals=False, figure_location=(hi.x + 0.8, hi.y + 0.6, 0.0))
    for obj in [o for o in C.collection("Preview").objects if o.name.startswith("Icosphere")]:
        bpy.data.objects.remove(obj)
    root.location.z = lift
    if wall is not None:
        bpy.ops.mesh.primitive_plane_add(size=6, location=(0, wall + 0.001, 3.0), rotation=(math.pi / 2, 0, 0))
        plane = bpy.context.active_object
        for c in plane.users_collection:
            c.objects.unlink(plane)
        C.link(plane, None, "Preview")
        mat, _nt, bsdf = C._new_material("PreviewWall")
        bsdf.inputs["Base Color"].default_value = (0.06, 0.06, 0.06, 1.0)
        C.assign(plane, mat)
    center = (lo + hi) / 2 + Vector((0, 0, lift))
    radius = max((hi - lo).length / 2, 0.8)
    down = math.radians(35)
    iso = Vector((math.cos(down) * 0.7071, -math.cos(down) * 0.7071, math.sin(down)))
    paths = [OUT / f"{name}_{view}.png" for view in VIEWS]
    C.render_from(paths[0], center + iso * radius * 3.3, center, 50, 32, 640)
    eye = Vector((0.5, -1.0, 0.0)).normalized() * (radius * 2.6 + 0.6)
    C.render_from(paths[1], Vector((center.x + eye.x, center.y + eye.y, 1.6)), center, 40, 32, 640)
    near = Vector((1.0, -0.4, 0.0)).normalized() * (radius * 1.7 + 0.5)
    C.render_from(paths[2], Vector((center.x + near.x, center.y + near.y, center.z + 0.4)), center, 40, 32, 640)
    return paths


def main() -> None:
    names = C.args() or list(MODELS)
    unknown = [n for n in names if n not in MODELS]
    if unknown:
        raise SystemExit(f"unknown models: {unknown} (known: {list(MODELS)})")
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names:
        build, lift, wall = MODELS[name]
        C.reset(pascal(name))
        root = C.asset_root(pascal(name))
        build(root)
        st = C.stats()
        st["parts"] = C.tris_per_object()
        print("MODEL", name, st)
        (OUT / f"{name}.json").write_text(json.dumps(st, indent=1), encoding="utf-8", newline="\n")
        C.export_glb(PROPS / f"{name}.glb")
        preview(name, root, st, lift, wall)
    shots = [OUT / f"{name}_{view}.png" for name in MODELS for view in VIEWS]
    C.contact_sheet(shots, OUT / "sheet.png", cols=6, tile=300)


if __name__ == "__main__":
    main()
