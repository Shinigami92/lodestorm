"""Waypost Ostra's outside, everything above and around the shell's walls (the layout is
game/space_station/ostra/ostra_layout.py; the walls and floors come from ostra_shell_build.py):

    assets/space_station/ostra/exterior/exterior_roofs.glb       the rooms' roofs (one object per room): the hangar's
        barrel vault with ribs and the pressure frame round the ship's opening, the hub's drum and dome (the
        station's landmark) on the flat roof over the hub and its machinery blocks, rounded module roofs with
        their own machinery on the depot, council, bar and market, the gallery's rounded roof with a glazed band
    assets/space_station/ostra/exterior/exterior_structures.glb  what stands on the platform outside the rooms: the
        mast tower, the solar pylon with its two wings, storage silos, containers and crates, pipe runs, masts
    assets/space_station/ostra/exterior/exterior_platform.glb    the round deck platform: plated top, rim with
        running lights and rails, hazard band where the ship reaches over it, the underside's ribs, tanks,
        thrusters and hub cone

Every model's origin is the station's (the layout's coordinates as they are). The roofs' undersides lie at
the rooms' ceilings and reach out to the walls' outer faces (0.3 m overhang with a trim where an edge is free;
an edge against a taller wall tucks into it). The hangar's opening (z -27.3..27.3, up to 17.5 m at x 8) stays
free, nothing stands at x < 8 in front of it, the platform's top stays flat for x < 20 (the ship's hull reaches
over it), and in front of the rooms (z > 30) nothing is taller than 1.5 m.

The materials are placeholders named for the game (OstraLook swaps in the station's materials by name).

Run from the repo root:
    tools/blender.sh assets/space_station/ostra/source/ostra_exterior_build.py [parts...] [nopreview] [shell]
parts: exterior_roofs, exterior_structures, exterior_platform (default: all three). Previews (with grey
placeholder walls, floors and a box for the ship's tail; `shell`: the shell's models instead of the placeholders,
when they're built) and a contact sheet go to tmp/ostra_exterior/.

Godot axes (x right, y up, z towards the camera) become Blender's (x, -z, y).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "assets" / "space_station" / "ostra" / "exterior"
TMP = ROOT / "tmp" / "ostra_exterior"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))  # ostra_materials
sys.path.insert(0, str(ROOT / "game" / "space_station" / "ostra"))

import bmesh
import bpy
import ostra_layout as L
from mathutils import Vector

import common as C
from ostra_materials import material

ARGV = C.args()
C.reset("ExteriorRoofs")


def flat(name, color, roughness=0.6, metallic=0.0, emission=None, strength=0.0, transmission=0.0):
    """A plain material for the preview's stand-ins (walls, floors, the ship); the kit's own come from ostra_materials."""
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    if transmission:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    return mat


MATS = [
    material(n)
    for n in (
        "OstraPaint",
        "OstraPaintDark",
        "OstraMetal",
        "OstraFloor",
        "OstraGrating",
        "OstraHazard",
        "OstraRubber",
        "OstraGlass",
        "OstraLamp",
        "OstraAmber",
        "OstraRed",
        "OstraCanvas",
        "OstraContainerRed",
        "OstraContainerBlue",
        "OstraContainerOlive",
    )
]
PAINT, DARK, METAL, FLOOR, GRATING, HAZARD, RUBBER, GLASS, LAMP, AMBER, RED, CANVAS, CRED, CBLUE, COLIVE = range(
    len(MATS)
)
SHARP = math.radians(35)
FREE, BLOCK, MIXED = (0.25, 1.0), (0.0, 0.0), (0.2, 0.0)  # an edge's base offset from the wall's center line, overhang


def g(x, y, z) -> Vector:
    """A Godot point (or direction) in Blender's axes."""
    return Vector((x, -z, y))


def oct_r(apothem: float) -> float:
    return apothem / math.cos(math.pi / 8)


class Part(C.Part):
    """common's Part, flat-shaded at hard edges (sharp above 35°), normals pointing out, Godot-axis helpers."""

    def __init__(self, name: str, mats=None):
        super().__init__(name, mats or MATS, bevel=None)

    def gbox(self, c, s, mi, ry=0.0):
        return self.box(g(*c), (s[0], s[2], s[1]), C.rz(ry) if ry else None, mi)

    def gcyl(self, c, r, h, mi, seg=16, r2=None):
        return self.cyl(g(*c), r, h, seg, mi=mi, r2=r2)

    def grod(self, a, b, r, mi, seg=10, r2=None):
        return self.rod(g(*a), g(*b), r, seg, mi, r2)

    def gbeam(self, a, b, w, h, mi, side=(0, 1, 0), taper=1.0):
        return self.beam(g(*a), g(*b), w, h, g(*side), mi, taper)

    def finish(self, parent):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > SHARP:
                e.smooth = False
        return super().finish(parent)


# --- mesh builders ---------------------------------------------------------------------------------


def loft(p: Part, loops, mis, cap0=None, cap1=None) -> None:
    """Join loops of 3D points (same length, or a single point for a fan) band by band; mis per band (or one)."""
    bm = p.bm
    vl = [[bm.verts.new(v) for v in loop] for loop in loops]
    for k in range(len(vl) - 1):
        a, b = vl[k], vl[k + 1]
        mi = mis[k] if isinstance(mis, (list, tuple)) else mis
        n = max(len(a), len(b))
        if n == 1:
            continue
        for i in range(n):
            j = (i + 1) % n
            if len(a) == 1:
                vs = (a[0], b[i], b[j])
            elif len(b) == 1:
                vs = (a[i], a[j], b[0])
            else:
                vs = (a[i], a[j], b[j], b[i])
            bm.faces.new(vs).material_index = mi
    for loop, mi in ((vl[0], cap0), (vl[-1], cap1)):
        if mi is not None and len(loop) > 2:
            bm.faces.new(loop).material_index = mi


def lathe(p: Part, cx: float, cz: float, profile, seg: int = 24, spin: float = 0.0) -> None:
    """Turn a profile [(radius, height, material of the band above)] about a vertical axis through Godot (cx, cz)."""
    c = g(cx, 0, cz)
    angles = [math.radians(spin) + math.tau * i / seg for i in range(seg)]
    loops = []
    for r, y, _ in profile:
        if r < 1e-6:
            loops.append([Vector((c.x, c.y, y))])
        else:
            loops.append([Vector((c.x + r * math.cos(a), c.y + r * math.sin(a), y)) for a in angles])
    loft(p, loops, [m for *_, m in profile[:-1]], cap0=profile[0][2], cap1=profile[-1][2])


def signed_area(pts) -> float:
    return 0.5 * sum(
        pts[i].x * pts[(i + 1) % len(pts)].y - pts[(i + 1) % len(pts)].x * pts[i].y for i in range(len(pts))
    )


def offset_poly(pts, offs):
    """Push each edge of a CCW polygon (Blender xy) outwards by offs[i] (edge i runs from pts[i] to pts[i + 1])."""
    n = len(pts)
    lines = []
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        d = (b - a).normalized()
        lines.append((a + Vector((d.y, -d.x)) * offs[i], d))
    out = []
    for i in range(n):
        p1, d1 = lines[i - 1]
        p2, d2 = lines[i]
        cross = d1.x * d2.y - d1.y * d2.x
        if abs(cross) < 1e-9:
            out.append(p2.copy())
            continue
        diff = p2 - p1
        out.append(p1 + d1 * ((diff.x * d2.y - diff.y * d2.x) / cross))
    return out


def ray_hit(ring, origin, d):
    """Where a ray (Blender xy) from inside a ring of 3D points leaves it (the point keeps the ring's height)."""
    best = None
    n = len(ring)
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        e = (b - a).to_2d()
        den = d.x * e.y - d.y * e.x
        if abs(den) < 1e-9:
            continue
        w = a.to_2d() - origin
        t = (w.x * e.y - w.y * e.x) / den
        u = (w.x * d.y - w.y * d.x) / den
        if t > 0 and -1e-6 <= u <= 1 + 1e-6 and (best is None or t < best[0]):
            best = (t, a + (b - a) * u)
    return best[1]


def rib_line(p: Part, pts, w, h):
    """A rib of beams along points on a roof's surface, lifted to sit on it."""
    for a, b in itertools.pairwise(pts):
        d = b - a
        if d.length < 0.05:
            continue
        side = d.cross(Vector((0, 0, 1)))
        up = side.cross(d).normalized()
        p.beam(a + up * h * 0.4, b + up * h * 0.4, w, h, side, DARK)


def room_roof(p: Part, poly_g, y0: float, kind, profile, light_step: float = 6.5):
    """A roof over a convex floor polygon (Godot x, z on the walls' center lines): rings of the profile
    [(overhang, height above y0, material of the band above)] on the free edges, straight up on the others
    (kind(x, z) of an edge's middle says FREE, BLOCK or MIXED), amber running lights on the free edges' trim.
    Returns the rings (Blender) and the edges' kinds, both CCW."""
    n = len(poly_g)
    kinds = []
    for i in range(n):
        (x0, z0), (x1, z1) = poly_g[i], poly_g[(i + 1) % n]
        kinds.append(kind((x0 + x1) / 2, (z0 + z1) / 2))
    pts = [Vector((x, -z)) for x, z in poly_g]
    if signed_area(pts) < 0:
        pts = pts[::-1]
        kinds = [kinds[(n - 2 - j) % n] for j in range(n)]
    rings = []
    for off, dz, _ in profile:
        ring = offset_poly(pts, [b + f * off for b, f in kinds])
        rings.append([Vector((v.x, v.y, y0 + dz)) for v in ring])
    loft(p, rings, [m for *_, m in profile[:-1]], cap0=DARK, cap1=profile[-1][2])
    if light_step:
        r0 = rings[0]
        for i, (_, f) in enumerate(kinds):
            if not f:
                continue
            a, c = r0[i], r0[(i + 1) % n]
            d = (c - a).normalized()
            nrm = Vector((d.y, -d.x, 0))
            count = max(1, int((c - a).length // light_step))
            for k in range(count):
                q = a + (c - a) * ((k + 0.5) / count) + nrm * 0.04
                q.z = y0 + 0.18
                p.box(q, (0.9, 0.12, 0.12), C.rz(math.degrees(math.atan2(d.y, d.x))), AMBER)
    return rings, kinds


# --- greebles (Godot coordinates; y is the surface they stand on) -----------------------------------


def ac_unit(p: Part, x, y, z, w=3.0, d=2.0, h=1.4, fans=2, ry=0.0):
    p.gbox((x, y + 0.1, z), (w + 0.2, 0.2, d + 0.2), DARK, ry)
    p.gbox((x, y + 0.2 + h / 2, z), (w, h, d), PAINT, ry)
    c, s = math.cos(math.radians(ry)), math.sin(math.radians(ry))
    for i in range(fans):
        t = (i + 0.5) / fans - 0.5
        fx, fz = x + c * t * w, z - s * t * w
        p.gcyl((fx, y + 0.2 + h + 0.05, fz), min(w / fans, d) * 0.38, 0.12, DARK, 16)
        p.gcyl((fx, y + 0.2 + h + 0.12, fz), min(w / fans, d) * 0.33, 0.06, GRATING, 16)
    p.gbox((x + s * d / 2, y + 0.2 + h * 0.45, z + c * d / 2), (w * 0.8, h * 0.6, 0.06), GRATING, ry)


def vent_box(p: Part, x, y, z, w=1.6, d=1.2, h=0.8, ry=0.0):
    p.gbox((x, y + h / 2, z), (w, h, d), DARK, ry)
    p.gbox((x, y + h + 0.05, z), (w * 0.85, 0.1, d * 0.8), GRATING, ry)


def tank_h(p: Part, x, y, z, length, r, along_x=True):
    """A horizontal tank on two saddles, its bottom at y."""
    cy = y + 0.35 + r
    rot = C.ry(90) if along_x else C.rx(90)
    p.cyl(g(x, cy, z), r, length, 16, rot=rot, mi=PAINT)
    for s in (-1, 1):
        dx, dz = (s * length / 2, 0) if along_x else (0, s * length / 2)
        scale = (0.35, 1, 1) if along_x else (1, 0.35, 1)
        p.sphere(g(x + dx, cy, z + dz), r, 16, 6, scale=scale, mi=PAINT)
        sx, sz = (x + s * length * 0.3, z) if along_x else (x, z + s * length * 0.3)
        p.gbox(
            (sx, y + 0.35 + r * 0.4, sz), (0.4 if along_x else 2 * r, 0.7 + r * 0.8, 2 * r if along_x else 0.4), DARK
        )
        p.cyl(g(sx, cy, sz), r + 0.05, 0.2, 16, rot=rot, mi=DARK)


def stack(p: Part, x, y, z, r, h):
    """An exhaust stack with bands and a rain cap."""
    p.gcyl((x, y + 0.3, z), r * 1.6, 0.6, DARK, 12)
    p.gcyl((x, y + h / 2, z), r, h, METAL, 12)
    for k in (0.35, 0.7):
        p.gcyl((x, y + h * k, z), r + 0.06, 0.2, DARK, 12)
    p.gcyl((x, y + h + 0.25, z), r * 1.5, 0.12, DARK, 12)
    p.gcyl((x, y + h + 0.45, z), r * 1.3, 0.25, DARK, 12, r2=0.05)


def hatch(p: Part, x, y, z, w, d):
    p.gbox((x, y + 0.15, z), (w, 0.3, d), DARK)
    p.gbox((x, y + 0.36, z), (w - 0.5, 0.14, d - 0.5), PAINT)
    for s in (-1, 1):
        p.gbox((x, y + 0.31, z + s * (d / 2 - 0.12)), (w, 0.04, 0.24), HAZARD)
    p.grod((x - w * 0.25, y + 0.55, z), (x + w * 0.25, y + 0.55, z), 0.06, METAL, 6)


def skylight(p: Part, x, y, z, w, d):
    p.gbox((x, y + 0.25, z), (w, 0.5, d), DARK)
    p.gbox((x, y + 0.53, z), (w - 0.4, 0.08, d - 0.4), GLASS)
    for i in range(1, 4):
        p.gbox((x - w / 2 + w * i / 4, y + 0.6, z), (0.12, 0.1, d - 0.3), METAL)


def dish(p: Part, x, y, z, r, yaw, pitch):
    """A dish on a short pedestal, facing yaw (degrees from +x round +y) and pitch up."""
    p.gcyl((x, y + 0.4, z), 0.35, 0.8, DARK, 10)
    p.gbox((x, y + 0.95, z), (0.7, 0.4, 0.7), PAINT)
    a, b = math.radians(yaw), math.radians(pitch)
    d = g(math.cos(a) * math.cos(b), math.sin(b), -math.sin(a) * math.cos(b))
    rot = C.basis(d, Vector((0, 0, 1)))
    c = g(x, y + 1.2 + r * 0.4, z)
    p.cyl(c, r * 0.2, r * 0.35, 16, rot=rot, mi=PAINT, r2=r)
    p.rod(c, c + d * r * 0.9, 0.05, 6, METAL)


def fan_box(p: Part, x, y, z, s, h):
    p.gbox((x, y + h / 2, z), (s, h, s), PAINT)
    p.gcyl((x, y + h + 0.05, z), s * 0.42, 0.1, DARK, 20)
    p.gcyl((x, y + h + 0.11, z), s * 0.38, 0.04, GRATING, 20)
    p.gcyl((x, y + h + 0.16, z), 0.18, 0.12, DARK, 8)


def radiator(p: Part, x, y, z, n, length, h, along_x=True):
    for i in range(n):
        t = (i - (n - 1) / 2) * 0.45
        c = (x, y + h / 2 + 0.3, z + t) if along_x else (x + t, y + h / 2 + 0.3, z)
        p.gbox(c, (length, h, 0.06) if along_x else (0.06, h, length), METAL)
    w = (n - 1) * 0.45 + 0.4
    p.gbox((x, y + 0.15, z), (length + 0.3, 0.3, w) if along_x else (w, 0.3, length + 0.3), DARK)


def canvas_heap(p: Part, x, y, z, w, h, d, ry=0.0):
    p.gbox((x, y + h * 0.35, z), (w, h * 0.7, d), CANVAS, ry)
    p.sphere(g(x, y + h * 0.65, z), 1.0, 10, 5, scale=(w * 0.5, d * 0.5, h * 0.35), rot=C.rz(ry), mi=CANVAS)
    for t in (-0.3, 0.3):
        c, s = math.cos(math.radians(ry)), math.sin(math.radians(ry))
        p.gbox((x + c * t * w, y + h * 0.5, z - s * t * w), (0.08, h, d + 0.06), RUBBER, ry)


def crate(p: Part, x, y, z, s, mi=PAINT, ry=0.0):
    sx, sy, sz = s
    p.gbox((x, y + sy / 2, z), (sx, sy, sz), mi, ry)
    p.gbox((x, y + sy * 0.5, z), (sx + 0.04, 0.12, sz + 0.04), DARK, ry)
    p.gbox((x, y + sy - 0.05, z), (sx + 0.04, 0.1, sz + 0.04), DARK, ry)


def container(p: Part, x, y, z, ry, mi):
    """A 6.06 x 2.59 x 2.44 m cargo container, its bottom at y, along x before rotating by ry (degrees)."""
    lx, hy, wz = 6.06, 2.59, 2.44
    rot = C.rz(ry)
    c0 = g(x, y + hy / 2, z)
    p.box(c0, (lx - 0.1, wz - 0.06, hy - 0.1), rot, mi)

    def at(dx, dy, dz):
        return c0 + rot @ g(dx, dy, dz)

    for s in (-1, 1):
        for i in range(9):
            p.box(at(-2.6 + i * 0.65, 0, s * (wz / 2 - 0.02)), (0.22, 0.08, hy - 0.4), rot, mi)
        for dy in (-1, 1):
            p.box(at(0, dy * (hy / 2 - 0.08), s * (wz / 2 - 0.05)), (lx, 0.12, 0.16), rot, DARK)
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box(at(sx * (lx / 2 - 0.1), 0, sz * (wz / 2 - 0.1)), (0.2, 0.2, hy), rot, DARK)
    for k in (-0.6, -0.2, 0.2, 0.6):
        a = at(lx / 2 + 0.02, -hy / 2 + 0.2, k)
        p.rod(a, a + g(0, hy - 0.4, 0), 0.04, 6, METAL)


def pipe_run(p: Part, pts, y, r=0.18, pipes=2, gap=0.5, support=4.0, base=-0.3):
    """Pipes along a polyline (Godot x, z) at height y on supports standing on `base`."""
    for k in range(pipes):
        off = (k - (pipes - 1) / 2) * gap
        q = []
        for i, (x, z) in enumerate(pts):
            a = Vector(pts[max(i - 1, 0)])
            b = Vector(pts[min(i + 1, len(pts) - 1)])
            d = (b - a).normalized()
            q.append((x - d.y * off, z + d.x * off))
        for i in range(len(q) - 1):
            p.grod((q[i][0], y, q[i][1]), (q[i + 1][0], y, q[i + 1][1]), r, METAL if k else PAINT, 8)
        for x, z in q[1:-1]:
            p.sphere(g(x, y, z), r * 1.25, 8, 4, mi=DARK)
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        n = max(1, int((b - a).length // support))
        ang = math.degrees(math.atan2(-(b - a).y, (b - a).x))
        for j in range(n + 1):
            c = a + (b - a) * (j / n)
            p.gbox((c.x, (y - r + base) / 2, c.y), (0.3, y - r - base, gap * pipes + 0.2), DARK, ang)


def lattice_mast(p: Part, x, z, h, w=1.2, base=-0.3):
    legs = [(x + w * math.cos(a), z + w * math.sin(a)) for a in (0.5, 2.6, 4.7)]
    for lx, lz in legs:
        p.grod((lx, base, lz), (x + (lx - x) * 0.3, base + h, z + (lz - z) * 0.3), 0.08, METAL, 6)
    steps = int(h // 2.5)
    for s in range(1, steps + 1):
        t0, t1 = (s - 1) / steps, s / steps
        for i in range(3):
            a, b = legs[i], legs[(i + 1) % 3]

            def pt(leg, t):
                k = 1 - 0.7 * t
                return (x + (leg[0] - x) * k, base + h * t, z + (leg[1] - z) * k)

            p.grod(pt(a, t1), pt(b, t1), 0.04, METAL, 4)
            p.grod(pt(a, t0), pt(b, t1), 0.03, METAL, 4)
    p.gbox((x, base + 0.3, z), (w * 2.4, 0.6, w * 2.4), DARK)


# --- roofs -----------------------------------------------------------------------------------------

MODULE = [
    (0.30, 0.0, DARK),
    (0.30, 0.35, PAINT),
    (0.12, 0.47, PAINT),
    (-0.15, 0.72, PAINT),
    (-0.6, 0.92, PAINT),
    (-1.3, 1.05, PAINT),
]
MODULE_TOP = 1.05
SLAB = [(0.30, 0.0, DARK), (0.30, 0.4, DARK), (0.0, 0.6, PAINT), (-0.5, 0.75, PAINT)]
SLAB_TOP = 0.75
GALLERY = [
    (0.30, 0.0, DARK),
    (0.30, 0.35, PAINT),
    (0.12, 0.5, GLASS),
    (-0.7, 1.15, PAINT),
    (-1.1, 1.35, PAINT),
    (-2.4, 1.65, PAINT),
    (-4.5, 1.8, PAINT),
]
GALLERY_TOP = 1.8

# The hangar's vault: across z, rising from the eaves (VYE) to the crest (VYT), along x from the frame to the hub.
VX0, VX1 = 7.75, 44.55
VW, VY0, VYE, VYT = L.Z_HANGAR + 0.55, L.H_HANGAR, L.H_HANGAR + 0.6, L.H_HANGAR + 4.0
VR = (VW**2 + (VYT - VYE) ** 2) / (2 * (VYT - VYE))
VYC = VYT - VR


def vault_y(z: float) -> float:
    return VYC + math.sqrt(VR * VR - z * z)


def vault_n(z: float) -> tuple[float, float]:
    """The vault's outward normal at z, as (nz, ny)."""
    return z / VR, (vault_y(z) - VYC) / VR


def vault_rib(p: Part, x, w, lo, hi, z_ext, mi, n=28):
    loops = []
    for i in range(n + 1):
        z = -z_ext + 2 * z_ext * i / n
        y = vault_y(z)
        nz, ny = vault_n(z)
        zi, yi, zo, yo = z - lo * nz, y - lo * ny, z + hi * nz, y + hi * ny
        loops.append([g(x - w / 2, yi, zi), g(x + w / 2, yi, zi), g(x + w / 2, yo, zo), g(x - w / 2, yo, zo)])
    loft(p, loops, mi, cap0=mi, cap1=mi)


def on_vault(p: Part, x, z, size, mi, lift=0.0):
    """A box sitting on the vault's slope at (x, z), tilted with it."""
    y = vault_y(z)
    nz, ny = vault_n(z)
    nb = g(0, ny, nz)
    c = g(x, y, z) + nb * (size[1] / 2 + lift)
    p.box(c, (size[0], size[2], size[1]), C.basis(nb, Vector((1, 0, 0))), mi)
    return c, nb


def hangar_roof(root):
    p = Part("HangarRoof")
    section = [(-VW, VY0)] + [(-VW + 2 * VW * i / 28, vault_y(-VW + 2 * VW * i / 28)) for i in range(29)] + [(VW, VY0)]
    loft(p, [[g(x, y, z) for z, y in section] for x in (VX0, VX1)], PAINT, cap0=PAINT, cap1=PAINT)
    # Ribs over the vault with corbels under the eaves, heavier arches at both ends.
    ribs = [10.5 + 4.5 * k for k in range(8)]
    for x in ribs:
        vault_rib(p, x, 0.7, 0.05, 0.38, VW + 0.15, DARK)
        for s in (-1, 1):
            p.gbox((x, 19.0, s * 28.6), (0.6, 1.3, 0.7), DARK)
    for x in (VX0 + 0.3, VX1 - 0.3):
        vault_rib(p, x, 0.8, 0.05, 0.5, VW + 0.25, DARK)
    # Eave trims with running lights.
    for s in (-1, 1):
        p.gbox(((VX0 + VX1) / 2, 20.15, s * 28.6), (VX1 - VX0, 1.2, 0.75), DARK)
        for k in range(6):
            x = VX0 + 3.5 + k * 6.5
            p.gbox((x, 20.15, s * 29.0), (0.9, 0.14, 0.08), AMBER)
    # Purlins along the slopes.
    for z in (-20.0, -10.0, 10.0, 20.0):
        nz, ny = vault_n(z)
        y = vault_y(z) + 0.08
        p.gbeam((VX0, y, z), (VX1, y, z), 0.35, 0.18, PAINT, side=(0, -nz, ny))
    # Low vent ridges between the ribs near both eaves.
    for x0, x1 in itertools.pairwise(ribs):
        for z in (-24.5, 24.5):
            c, nb = on_vault(p, (x0 + x1) / 2, z, (3.0, 0.45, 1.3), DARK)
            p.box(c + nb * 0.25, (2.6, 1.0, 0.08), C.basis(nb, Vector((1, 0, 0))), GRATING)
    # A glazed ridge light along the crest.
    p.gbox((26.0, VYT + 0.25, 0), (28.0, 0.5, 4.4), DARK)
    p.gbox((26.0, VYT + 0.55, 0), (27.4, 0.12, 3.8), GLASS)
    for x in ribs[1:-1]:
        p.gbox((x, VYT + 0.62, 0), (0.25, 0.12, 4.2), METAL)
    # Vent housings on the front slope, fans and an access hatch on the back slope.
    for x in (15.0, 26.0, 37.0):
        c, nb = on_vault(p, x, 15.5, (2.6, 1.0, 1.8), DARK)
        p.box(c + nb * 0.55, (2.2, 1.4, 0.12), C.basis(nb, Vector((1, 0, 0))), GRATING)
    for x in (17.5, 30.5):
        c, nb = on_vault(p, x, -14.0, (2.8, 0.5, 2.8), PAINT)
        p.cyl(c + nb * 0.3, 1.1, 0.12, 20, rot=C.basis(nb, Vector((1, 0, 0))), mi=GRATING)
    on_vault(p, 40.0, -7.0, (2.4, 0.3, 2.0), DARK)
    on_vault(p, 40.0, -7.0, (2.0, 0.15, 1.6), PAINT, lift=0.3)
    # Red lights on the end arches' crests.
    for x in (VX0 + 0.3, VX1 - 0.3):
        p.gcyl((x, VYT + 0.6, 0), 0.18, 0.25, RED, 8)
    p.finish(root)


def pressure_frame(root):
    """The heavy frame round the ship's opening in the hangar's left end (the opening itself stays free)."""
    p = Part("PressureFrame")
    jx0, jx1 = 8.0 - 1.38, 9.25  # 1.38 m out of the wall to -x (+ a 0.1 m hazard plate)
    zi, ztop = L.MOUTH_HALF, L.MOUTH_TOP
    for s in (-1, 1):
        p.gbox(((jx0 + jx1) / 2, 10.6, s * (zi + 28.6) / 2), (jx1 - jx0, 21.8, 28.6 - zi), DARK)
        p.gbox(((7.4 + jx1) / 2, 10.6, s * 29.45), (jx1 - 7.4, 21.8, 1.7), PAINT)
        p.gbox((jx0 - 0.05, 8.75, s * (zi + 0.55)), (0.1, 16.9, 1.1), HAZARD)
        for k in range(8):
            p.gbox((7.36, 1.5 + k * 2.2, s * 29.4), (0.1, 0.45, 0.45), AMBER)
        for k in range(7):
            p.gbox(((7.4 + jx1) / 2, 1.5 + k * 3.0, s * 30.38), (jx1 - 7.4, 0.3, 0.16), DARK)
        for x in (8.15, 8.85):
            p.grod((x, 0.4, s * 30.75), (x, 9.0, s * 30.75), 0.2, METAL, 10)
            p.grod((x, 9.0, s * 30.75), (x, 16.8, s * 30.75), 0.34, DARK, 10)
            p.gbox((x, 0.2, s * 30.75), (0.6, 0.4, 0.8), DARK)
            p.gbox((x, 17.0, s * 30.75), (0.6, 0.5, 0.8), DARK)
        p.gbox((8.3, 21.7, s * 30.2), (2.4, 1.6, 1.6), PAINT)
        p.gbox((8.3, 22.55, s * 30.2), (0.5, 0.12, 0.5), AMBER)
    p.gbox(((jx0 + jx1) / 2, (ztop + 21.5) / 2, 0), (jx1 - jx0, 21.5 - ztop, 2 * 30.3), DARK)
    p.gbox(((7.2 + jx1) / 2, 22.0, 0), (jx1 - 7.2, 1.0, 2 * 29.6), PAINT)
    p.gbox((jx0 - 0.05, ztop + 0.35, 0), (0.1, 0.7, 2 * zi), HAZARD)
    for k in range(17):
        p.gbox((jx0 - 0.05, 19.7, -24.0 + k * 3.0), (0.1, 0.45, 0.9), AMBER)
    for k in range(9):
        p.gbox((jx0 - 0.06, 20.9, -24.0 + k * 6.0), (0.12, 0.5, 0.5), DARK)
    p.finish(root)


def hub_roof(root):
    """The flat roof over the hub and its machinery blocks, the octagonal drum with its windows, the dome."""
    p = Part("HubRoof")
    x0, x1, z0, z1 = L.X_HUB0, L.X_HUB1, -L.Z_HUB, L.Z_HUB
    room_roof(p, L.rect(x0, x1, z0, z1), L.H_HUB, lambda x, z: BLOCK if x < x0 + 0.1 else FREE, SLAB)
    top = L.H_HUB + SLAB_TOP
    hx, hz = L.HUB
    # Drum: base trim, wall, cornice.
    drum = [(16.6, top, DARK), (16.6, top + 0.35, DARK), (16.2, top + 0.35, PAINT), (16.2, top + 2.85, DARK)]
    drum += [(16.6, top + 2.85, DARK), (16.6, top + 3.25, DARK)]
    lathe(p, hx, hz, [(oct_r(a), y, m) for a, y, m in drum], 8, 22.5)
    y_drum = top + 3.25
    # Windows round the drum (lit, a few dark), light strips at its corners.
    face = 2 * 16.2 * math.tan(math.pi / 8)
    for k in range(8):
        a = math.radians(45 * k)
        n, t = Vector((math.cos(a), math.sin(a), 0)), Vector((-math.sin(a), math.cos(a), 0))
        c = g(hx, 0, hz)
        for i in range(5):
            o = (i - 2) * face / 5.4
            q = c + n * 16.2 + t * o
            q.z = top + 1.65
            p.box(q + n * 0.04, (0.12, 1.75, 1.25), C.rz(45 * k), DARK)
            p.box(q + n * 0.08, (0.1, 1.4, 0.9), C.rz(45 * k), GLASS if (i + k) % 4 == 0 else LAMP)
        q = c + polar_b(22.5 + 45 * k, oct_r(16.2) + 0.03)
        q.z = top + 1.65
        p.box(q, (0.18, 0.18, 1.8), C.rz(22.5 + 45 * k), AMBER)
    # Dome: a base ring, a lower tier, a ledge with lights, an upper tier, a cap with antennas.
    rd, ycd = 28.8, y_drum + 0.6 + 4.4 - 28.8

    def dy(r, lift=0.0):
        return ycd + math.sqrt(rd * rd - r * r) + lift

    ledge = 11.0
    prof = [(15.8, y_drum, DARK), (15.8, y_drum + 0.5, DARK), (15.3, y_drum + 0.6, PAINT)]
    prof += [(r, dy(r), PAINT) for r in (14.2, 12.6)]
    prof += [(ledge, dy(ledge), DARK), (ledge + 0.35, dy(ledge), DARK), (ledge + 0.35, dy(ledge) + 0.45, DARK)]
    prof += [(ledge - 0.3, dy(ledge - 0.3, 0.45), PAINT)]
    prof += [(r, dy(r, 0.45), PAINT) for r in (9.2, 7.4)]
    yc = dy(5.6, 0.45)
    prof += [(5.6, yc, DARK), (5.95, yc, DARK), (5.95, yc + 0.8, DARK), (4.4, yc + 1.0, PAINT)]
    prof += [(4.4, yc + 1.4, DARK), (2.6, yc + 1.7, DARK), (0.0, yc + 1.75, DARK)]
    lathe(p, hx, hz, prof, 32)

    def meridian(a_deg, r0, r1, lift, n=5):
        a = math.radians(a_deg)
        loops = []
        for i in range(n + 1):
            r = r0 + (r1 - r0) * i / n
            y = dy(r, lift)
            nr, ny = r / rd, (y - lift - ycd) / rd
            u = Vector((math.cos(a), math.sin(a), 0))
            v = Vector((-math.sin(a), math.cos(a), 0))
            base = g(hx, 0, hz) + u * r + Vector((0, 0, y))
            nb = u * nr + Vector((0, 0, ny))
            lo, hi = base - nb * 0.05, base + nb * 0.3
            loops.append([lo - v * 0.22, lo + v * 0.22, hi + v * 0.22, hi - v * 0.22])
        loft(p, loops, DARK, cap0=DARK, cap1=DARK)

    for k in range(16):
        meridian(k * 22.5, 15.3, ledge + 0.3, 0.0)
        meridian(k * 22.5 + 11.25, ledge - 0.4, 5.8, 0.45, 4)
        q = g(hx, 0, hz) + polar_b(k * 22.5 + 11.25, ledge + 0.38)
        q.z = dy(ledge) + 0.22
        p.box(q, (0.1, 0.7, 0.16), C.rz(k * 22.5 + 11.25), AMBER)
    # Antennas and a small dish on the cap.
    cap = yc + 1.75
    p.gcyl((hx, cap + 0.3, hz), 0.9, 0.6, DARK, 12)
    p.grod((hx, cap, hz), (hx, cap + 8.0, hz), 0.16, METAL, 8, r2=0.07)
    p.sphere(g(hx, cap + 8.1, hz), 0.22, 8, 4, mi=RED)
    for ang, h in ((40.0, 4.5), (220.0, 5.5)):
        a = math.radians(ang)
        ax, az = hx + 2.8 * math.cos(a), hz - 2.8 * math.sin(a)
        p.grod((ax, cap - 0.3, az), (ax, cap + h, az), 0.09, METAL, 6)
        p.grod((ax - 0.7, cap + h - 0.8, az), (ax + 0.7, cap + h - 0.8, az), 0.04, METAL, 4)
        p.sphere(g(ax, cap + h + 0.05, az), 0.12, 6, 3, mi=AMBER)
    dish(p, hx - 3.3, yc + 0.8, hz + 3.3, 1.1, 225.0, 35.0)
    # Machinery on the corners (over the machinery blocks).
    ac_unit(p, hx - 14.5, top, hz - 12.5, 3.2, 2.0, 1.3, 2, ry=45)
    ac_unit(p, hx - 12.0, top, hz - 14.8, 3.2, 2.0, 1.3, 2, ry=45)
    tank_h(p, hx + 14.5, top, hz - 14.5, 5.0, 0.9, along_x=True)
    vent_box(p, hx + 15.6, top, hz - 10.0, 1.4, 1.2, 0.8)
    radiator(p, hx - 14.2, top, hz + 14.2, 7, 4.0, 1.4, along_x=True)
    fan_box(p, hx + 14.0, top, hz + 14.0, 3.4, 1.2)
    vent_box(p, hx + 9.6, top, hz + 16.4, 1.6, 1.0, 0.7)
    p.finish(root)


def polar_b(deg: float, r: float) -> Vector:
    """A point at r m in the direction deg (Blender, round +z) from the origin."""
    return Vector((math.cos(math.radians(deg)) * r, math.sin(math.radians(deg)) * r, 0.0))


def depot_roof(root):
    p = Part("DepotRoof")
    x0, x1, z0, z1 = L.X_HUB0, L.X_MID, L.Z_BACK, -L.Z_HUB

    def kind(x, z):
        return FREE if z < z0 + 0.1 else (MIXED if x < x0 + 0.1 else BLOCK)

    room_roof(p, L.rect(x0, x1, z0, z1), L.H_ROOM, kind, MODULE)
    y = L.H_ROOM + MODULE_TOP
    hatch(p, 50.0, y, -25.0, 5.0, 4.0)
    tank_h(p, 51.5, y, -35.2, 8.0, 0.95)
    tank_h(p, 51.5, y, -32.6, 8.0, 0.95)
    for z in (-34.0, -29.5, -25.0):
        vent_box(p, 58.6, y, z, 1.4, 1.8, 0.9)
    pipe_run(p, [(46.0, -30.5), (56.5, -30.5), (56.5, -21.0)], y + 0.45, 0.14, 2, 0.4, 99.0, y)
    p.gbox((x1, y + 0.12, (z0 + z1) / 2), (0.5, 0.25, z1 - z0 + 0.5), DARK)
    p.finish(root)


def council_roof(root):
    p = Part("CouncilRoof")
    x0, x1, z0, z1 = L.X_MID, L.X_HUB1, L.Z_BACK, -L.Z_HUB

    def kind(x, z):
        return FREE if z < z0 + 0.1 else (MIXED if x > x1 - 0.1 else BLOCK)

    room_roof(p, L.rect(x0, x1, z0, z1), L.H_ROOM, kind, MODULE)
    y = L.H_ROOM + MODULE_TOP
    skylight(p, 70.0, y, -27.0, 7.0, 4.5)
    dish(p, 75.5, y, -35.0, 1.8, 120.0, 30.0)
    ac_unit(p, 66.0, y, -35.0, 3.0, 2.0, 1.3, 2)
    lattice_mast(p, 77.5, -21.5, 6.0, 0.5, y)
    p.gbox((77.5, y + 6.2, -21.5), (0.3, 0.3, 0.3), RED)
    p.finish(root)


def bar_roof(root):
    p = Part("BarRoof")
    x0, x1, z0, z1 = L.X_HUB0, L.X_MID, L.Z_HUB, L.Z_BAR

    def kind(x, z):
        return FREE if z > z1 - 0.1 else (MIXED if x < x0 + 0.1 else BLOCK)

    room_roof(p, L.rect(x0, x1, z0, z1), L.H_ROOM, kind, MODULE)
    y = L.H_ROOM + MODULE_TOP
    for x, z, h in ((47.5, 22.5, 3.2), (50.0, 22.5, 2.6), (47.5, 25.5, 2.2)):
        stack(p, x, y, z, 0.42, h)
    fan_box(p, 56.5, y, 26.0, 2.6, 1.1)
    fan_box(p, 56.5, y, 31.0, 2.6, 1.1)
    vent_box(p, 48.5, y, 32.5, 2.4, 1.4, 0.7)
    pipe_run(p, [(50.0, 23.5), (54.0, 23.5), (54.0, 34.5)], y + 0.4, 0.13, 2, 0.35, 99.0, y)
    p.finish(root)


def market_roof(root):
    p = Part("MarketRoof")
    x0, x1, z0, z1 = L.X_MID, L.X_HUB1, L.Z_HUB, L.Z_MARKET

    def kind(x, z):
        if z < z0 + 0.1:
            return BLOCK
        return MIXED if x > x1 - 0.1 else FREE

    h = L.ROOM_HEIGHTS["Market"]
    room_roof(p, L.rect(x0, x1, z0, z1), h, kind, MODULE)
    y = h + MODULE_TOP
    for x in (66.0, 70.5, 75.0):
        ac_unit(p, x, y, 29.0, 3.4, 2.2, 1.2, 2)
    canvas_heap(p, 74.5, y, 22.5, 4.0, 1.4, 2.6, 10.0)
    p.gcyl((66.5, y + 1.3, 22.5), 1.2, 2.6, PAINT, 16)
    p.gcyl((66.5, y + 2.65, 22.5), 1.25, 0.15, DARK, 16)
    p.gcyl((66.5, y + 0.6, 22.5), 1.25, 0.15, DARK, 16)
    p.grod((67.7, y + 2.0, 22.5), (70.0, y + 2.0, 22.5), 0.12, METAL, 6)
    p.grod((70.0, y + 2.0, 22.5), (70.0, y + 0.3, 22.5), 0.12, METAL, 6)
    p.finish(root)


def gallery_roof(root):
    p = Part("GalleryRoof")
    poly = [(L.X_HUB1, -L.GALLERY_RADIUS)] + L.gallery_arc() + [(L.X_HUB1, L.GALLERY_RADIUS)]
    rings, kinds = room_roof(
        p, poly, L.H_GALLERY, lambda x, z: BLOCK if x < L.X_HUB1 + 0.1 else FREE, GALLERY, light_step=5.0
    )
    # Mullions over the glazed band.
    n = len(kinds)
    for i, (_, f) in enumerate(kinds):
        if not f:
            continue
        a2, b2, a3, b3 = rings[2][i], rings[2][(i + 1) % n], rings[3][i], rings[3][(i + 1) % n]
        count = max(1, round((b2 - a2).length / 2.4))
        d = (b2 - a2).normalized()
        nrm = Vector((d.y, -d.x, 0.6)).normalized()
        for k in range(count + 1):
            t = k / count
            p.beam(a2 + (b2 - a2) * t + nrm * 0.06, a3 + (b3 - a3) * t + nrm * 0.06, 0.14, 0.1, d, METAL)
    y = L.H_GALLERY + GALLERY_TOP
    cx, cz = L.GALLERY_CENTER
    # Ribs over the rounded edge: radial ones round the half circle, across the straight part.
    hub = Vector((cx + 3.0, -cz))
    for k in range(7):
        d = polar_b(-67.5 + 22.5 * k, 1.0).to_2d()
        pts = [ray_hit(r, hub, d) for r in rings[1:]][::-1]
        pts = [Vector((hub.x + d.x * 3.6, hub.y + d.y * 3.6, y))] + pts
        rib_line(p, pts, 0.45, 0.28)
    for x in (84.0, 90.0, 96.0):
        o = Vector((x, 0.0))
        side_a = [ray_hit(r, o, Vector((0, 1))) for r in rings[1:]]
        side_b = [ray_hit(r, o, Vector((0, -1))) for r in rings[1:]]
        rib_line(p, side_a + side_b[::-1], 0.45, 0.28)
    cupola = [(3.4, y, DARK), (3.4, y + 0.5, GLASS), (3.0, y + 1.5, DARK), (3.1, y + 1.5, DARK)]
    cupola += [(3.1, y + 1.75, PAINT), (2.0, y + 2.3, PAINT), (0.0, y + 2.5, PAINT)]
    lathe(p, cx + 3.0, cz, cupola, 16)
    p.gcyl((cx + 3.0, y + 2.7, cz), 0.25, 0.4, AMBER, 8)
    for ang in (-50.0, 50.0):
        a = math.radians(ang)
        vent_box(p, cx + 12.0 * math.cos(a), y, cz + 12.0 * math.sin(a), 1.8, 1.2, 0.7, -ang)
    for x, z in ((87.0, -15.0), (87.0, 15.0)):
        vent_box(p, x, y, z, 2.2, 1.4, 0.6)
    hatch(p, 90.0, y, 0.0, 2.4, 2.4)
    p.grod((cx - 4.0, y, cz - 14.0), (cx - 4.0, y + 5.5, cz - 14.0), 0.07, METAL, 6)
    p.sphere(g(cx - 4.0, y + 5.6, cz - 14.0), 0.13, 6, 3, mi=RED)
    p.finish(root)


def build_roofs(root):
    hangar_roof(root)
    pressure_frame(root)
    hub_roof(root)
    depot_roof(root)
    council_roof(root)
    bar_roof(root)
    market_roof(root)
    gallery_roof(root)


# --- structures on the platform ------------------------------------------------------------------

TOWER = (27.0, -47.0)
PYLON = (96.0, -52.0)
FLOOR_Y = L.PLATFORM_TOP


def tower(root):
    """The mast tower: a tapering lighthouse with bands, small windows, a gallery, a lit lantern and a mast."""
    p = Part("MastTower")
    tx, tz = TOWER
    y0 = FLOOR_Y
    lathe(p, tx, tz, [(oct_r(a), y, m) for a, y, m in ((3.8, y0, DARK), (3.8, 0.9, DARK), (3.2, 1.5, DARK))], 8, 22.5)
    prof = [(2.9, 1.5, PAINT)]
    bands = [6.0, 12.5, 19.0, 25.5]

    def r_at(y):
        return 2.9 - (y - 1.5) * (0.95 / 31.5)

    for b in bands:
        prof += [
            (r_at(b), b, DARK),
            (r_at(b) + 0.2, b, DARK),
            (r_at(b) + 0.2, b + 0.6, DARK),
            (r_at(b + 0.6), b + 0.6, PAINT),
        ]
    prof += [(r_at(33.0), 33.0, DARK), (3.4, 33.0, DARK), (3.4, 33.6, DARK), (1.7, 33.6, LAMP), (1.7, 36.4, DARK)]
    prof += [(2.1, 36.4, DARK), (2.1, 36.8, DARK), (0.5, 38.4, DARK), (0.0, 38.6, DARK)]
    lathe(p, tx, tz, prof, 20)
    c = g(tx, 0, tz)
    for k in range(8):
        a = 22.5 + 45 * k
        q = c + polar_b(a, 1.72)
        p.rod(q + Vector((0, 0, 33.6)), q + Vector((0, 0, 36.4)), 0.07, 4, METAL)
    for k in range(12):
        q = c + polar_b(30 * k, 3.3)
        p.rod(q + Vector((0, 0, 33.6)), q + Vector((0, 0, 34.7)), 0.04, 4, METAL)
        q2 = c + polar_b(30 * (k + 1), 3.3)
        p.rod(q + Vector((0, 0, 34.7)), q2 + Vector((0, 0, 34.7)), 0.04, 4, METAL)
    for k in range(10):
        y = 3.5 + k * 2.9
        if any(b - 0.6 < y < b + 1.2 for b in bands):
            y += 1.4
        a = -70.0 + k * 72.0
        q = c + polar_b(a, r_at(y) + 0.02)
        q.z = y
        p.box(q, (0.16, 0.5, 0.8), C.rz(a), LAMP)
    for b in bands:
        for a in (-90.0, 0.0, 90.0, 180.0):
            q = c + polar_b(a, r_at(b) + 0.22)
            q.z = b + 0.3
            p.box(q, (0.08, 0.4, 0.2), C.rz(a), AMBER)
    p.grod((tx, 38.4, tz), (tx, 46.5, tz), 0.18, METAL, 8, r2=0.07)
    for y, w in ((41.0, 1.4), (43.5, 1.0)):
        p.grod((tx - w, y, tz), (tx + w, y, tz), 0.05, METAL, 4)
        p.grod((tx, y, tz - w), (tx, y, tz + w), 0.05, METAL, 4)
    p.sphere(g(tx, 46.65, tz), 0.25, 8, 4, mi=RED)
    # A service hut at its foot.
    p.gbox((32.6, y0 + 1.45, -45.6), (3.6, 2.9, 3.2), PAINT)
    p.gbox((32.6, y0 + 3.0, -45.6), (3.9, 0.2, 3.5), DARK)
    p.gbox((32.6, y0 + 1.1, -43.98), (1.2, 2.2, 0.06), DARK)
    p.gbox((32.6, y0 + 2.5, -43.94), (0.6, 0.12, 0.08), AMBER)
    vent_box(p, 33.4, y0 + 3.1, -46.2, 1.2, 1.0, 0.5)
    p.finish(root)


def solar_pylon(root):
    """A pylon with two big solar wings (each about 30 x 10 m), tilted 25° towards the camera."""
    p = Part("SolarPylon")
    px, pz = PYLON
    lathe(
        p, px, pz, [(oct_r(a), y, m) for a, y, m in ((2.8, FLOOR_Y, DARK), (2.8, 1.8, DARK), (2.2, 2.6, DARK))], 8, 22.5
    )
    lathe(
        p,
        px,
        pz,
        [(1.1, 2.6, PAINT), (0.95, 12.6, DARK), (1.25, 12.6, DARK), (1.25, 13.0, DARK), (0.0, 13.0, DARK)],
        16,
    )
    for y in (5.5, 9.0):
        p.gcyl((px, y, pz), 1.1, 0.3, DARK, 16)
    hy = 14.4
    p.gbox((px, hy - 0.2, pz), (3.0, 2.4, 2.6), PAINT)
    p.gbox((px, hy + 1.1, pz), (1.6, 0.3, 1.6), DARK)
    for s in (-1, 1):
        p.cyl(g(px + s * 2.6, hy, pz), 1.0, 2.2, 16, rot=C.ry(90), mi=DARK)
    p.grod((px, hy + 1.2, pz), (px, hy + 4.5, pz), 0.12, METAL, 6)
    p.sphere(g(px, hy + 4.6, pz), 0.15, 6, 3, mi=RED)
    p.gbeam((px - 31.6, hy, pz), (px + 31.6, hy, pz), 0.5, 0.5, METAL)
    tilt = math.radians(25)
    nb = g(0, math.cos(tilt), math.sin(tilt))
    rot = C.basis(nb, Vector((1, 0, 0)))
    across = g(0, -math.sin(tilt), math.cos(tilt))
    for s in (-1, 1):
        for j in range(3):
            x = px + s * (2.0 + 4.9 + j * 9.85)
            c = g(x, hy, pz) + nb * 0.4
            p.box(c, (9.6, 10.0, 0.14), rot, CBLUE)
            p.box(c + nb * 0.09, (9.3, 9.7, 0.05), rot, GLASS)
            for t in (-2.5, 0.0, 2.5):
                p.box(c + nb * 0.12 + across * t, (9.4, 0.08, 0.04), rot, METAL)
            for t in (-3.2, 3.2):
                p.box(c + nb * 0.12 + Vector((t, 0, 0)), (0.08, 9.8, 0.04), rot, METAL)
            p.box(c - nb * 0.15, (0.3, 10.0, 0.25), rot, METAL)
        tip = px + s * 31.4
        p.grod((px, hy + 4.3, pz), (tip, hy + 0.4, pz), 0.05, METAL, 4)
    pipe_run(p, [(px, pz + 3.0), (px, -43.5), (70.0, -43.5), (70.0, -40.6)], 0.35, 0.2, 2, 0.5)
    p.finish(root)


def cargo(root):
    """Container stacks behind the rooms and beside the gallery, low crates in front."""
    p = Part("Cargo")
    y0 = FLOOR_Y
    for x, y, z, ry, mi in (
        (36.5, y0, -32.6, 0, CRED),
        (36.5, y0, -35.4, 0, COLIVE),
        (36.3, y0 + 2.59, -33.0, 4, CBLUE),
        (48.5, y0, -44.6, 0, CBLUE),
        (55.4, y0, -44.6, 0, CRED),
        (48.8, y0 + 2.59, -44.6, -3, COLIVE),
        (61.0, y0, -49.0, 90, COLIVE),
        (106.0, y0, -36.0, 0, CBLUE),
        (106.2, y0 + 2.59, -35.8, 5, CRED),
        (113.5, y0, -32.5, 90, COLIVE),
    ):
        container(p, x, y, z, ry, mi)
    for x, z, s, mi in (
        (41.5, -33.0, (1.4, 1.2, 1.4), PAINT),
        (41.6, -35.0, (1.2, 1.0, 1.2), CANVAS),
        (55.0, -48.6, (1.6, 1.3, 1.4), PAINT),
        (101.5, -38.0, (1.4, 1.2, 1.4), PAINT),
        (110.5, -38.6, (1.2, 1.1, 1.2), CANVAS),
    ):
        crate(p, x, y0, z, s, mi)
    # In front of the rooms: nothing taller than 1.5 m.
    for x, z, s, mi, ry in (
        (47.5, 41.2, (1.4, 1.2, 1.2), PAINT, 0),
        (49.2, 41.4, (1.2, 1.0, 1.2), PAINT, 8),
        (48.3, 42.9, (1.3, 0.9, 1.1), CANVAS, -5),
        (70.0, 37.2, (1.5, 1.3, 1.3), PAINT, 0),
        (24.0, 32.5, (1.4, 1.2, 1.4), PAINT, 0),
        (25.8, 32.8, (1.2, 0.9, 1.2), CANVAS, 12),
        (108.0, 30.5, (1.4, 1.2, 1.4), PAINT, -10),
        (109.8, 31.6, (1.1, 0.9, 1.1), PAINT, 15),
    ):
        crate(p, x, y0, z, s, mi, ry)
    canvas_heap(p, 74.5, y0, 37.6, 2.4, 1.2, 1.8, -8)
    for x, z in ((57.5, 40.6), (58.4, 41.3), (57.7, 42.1), (116.0, 25.5), (116.8, 26.2)):
        p.gcyl((x, y0 + 0.55, z), 0.38, 1.1, PAINT, 12)
        p.gcyl((x, y0 + 0.75, z), 0.4, 0.08, DARK, 12)
        p.gcyl((x, y0 + 0.3, z), 0.4, 0.08, DARK, 12)
    p.finish(root)


def pipes_and_masts(root):
    p = Part("PipesMasts")
    pipe_run(p, [(30.5, -41.0), (61.0, -41.0)], 0.35, 0.2, 2, 0.5)
    pipe_run(p, [(106.0, 24.6), (106.0, 34.5), (118.0, 34.5)], 0.25, 0.16, 2, 0.4)
    pipe_run(p, [(31.0, -43.8), (31.0, -41.6)], 0.35, 0.2, 1, 0.5)
    lattice_mast(p, 52.0, -54.0, 18.0, 1.3)
    p.gbox((52.0, 17.9, -54.0), (0.35, 0.35, 0.35), RED)
    dish(p, 52.0, 9.0, -54.0, 1.3, 210.0, 25.0)
    lattice_mast(p, 118.0, -24.0, 14.0, 1.1)
    p.gbox((118.0, 13.9, -24.0), (0.35, 0.35, 0.35), RED)
    dish(p, 118.0, 7.0, -24.0, 1.1, 0.0, 30.0)
    # Bollard lights along the front walkway.
    for x, z in ((30.0, 40.0), (44.0, 46.5), (60.0, 49.5), (76.0, 49.5), (92.0, 44.0), (104.0, 38.0)):
        p.gcyl((x, FLOOR_Y + 0.45, z), 0.18, 0.9, DARK, 8)
        p.gcyl((x, FLOOR_Y + 0.95, z), 0.2, 0.12, AMBER, 8)
    p.finish(root)


def silos(root):
    """Two storage silos behind the council, under the solar wing, piped into the conduit."""
    p = Part("Silos")
    for x, z in ((76.0, -57.5), (84.5, -55.5)):
        prof = [(3.1, FLOOR_Y, DARK), (3.1, 0.7, DARK), (2.85, 0.7, PAINT), (2.85, 7.6, PAINT), (2.1, 8.9, DARK)]
        prof += [(1.0, 9.3, DARK), (1.0, 9.7, DARK), (0.0, 9.7, DARK)]
        lathe(p, x, z, prof, 24)
        for y in (2.9, 5.2):
            p.gcyl((x, y, z), 2.95, 0.3, DARK, 24)
        for k in range(4):
            a = math.radians(45 + 90 * k)
            lx, lz = x + 2.9 * math.cos(a), z - 2.9 * math.sin(a)
            p.gbox((lx, 0.2, lz), (0.6, 1.0, 0.6), DARK, 45 + 90 * k)
        lx, lz = x - 2.95, z + 0.6
        for dz in (-0.25, 0.25):
            p.grod((lx, 0.7, lz + dz), (lx, 8.0, lz + dz), 0.04, METAL, 4)
        for k in range(12):
            p.grod((lx, 1.0 + k * 0.6, lz - 0.25), (lx, 1.0 + k * 0.6, lz + 0.25), 0.03, METAL, 4)
        p.gbox((x, 2.0, z + 2.9), (0.5, 0.5, 0.12), AMBER)
        p.gbox((x, 9.8, z), (0.3, 0.2, 0.3), RED)
        pipe_run(p, [(x, z + 2.85), (x, -46.0)], 1.2, 0.18, 1, 0.5)
    pipe_run(p, [(76.0, -46.0), (84.5, -46.0), (84.5, -44.0)], 1.2, 0.18, 1, 0.5)
    p.finish(root)


def build_structures(root):
    tower(root)
    silos(root)
    solar_pylon(root)
    cargo(root)
    pipes_and_masts(root)


# --- the platform ------------------------------------------------------------------------------------

PCX, PCZ = L.PLATFORM_CENTER
PR = L.PLATFORM_RADIUS
PT = L.PLATFORM_TOP
SHIP_SIDE_X = 20.0  # the platform's top stays flat left of this (the ship reaches over it)


def ppos(deg: float, r: float, y: float) -> Vector:
    """A point on the platform at angle deg (Blender, round +z from +x) and radius r, height y."""
    return g(PCX, y, PCZ) + polar_b(deg, r)


def platform(root):
    p = Part("Platform")
    top = [(0.0, FLOOR), (9.7, DARK), (10.0, FLOOR), (23.7, DARK), (24.0, FLOOR), (37.7, DARK), (38.0, FLOOR)]
    top += [(51.7, DARK), (52.0, FLOOR), (62.6, DARK), (62.9, GRATING), (65.5, DARK)]
    prof = [(r, PT, m) for r, m in top]
    prof += [(PR, PT - 0.25, PAINT), (PR, PT - 1.15, DARK), (PR - 0.4, PT - 1.25, DARK), (PR - 0.4, PT - 1.75, DARK)]
    prof += [(PR, PT - 1.85, PAINT), (PR, PT - 2.7, DARK), (PR - 0.8, PT - 3.2, PAINT), (58.0, PT - 4.0, PAINT)]
    prof += [(24.0, PT - 4.3, DARK), (20.0, PT - 4.3, PAINT), (12.0, PT - 8.2, DARK), (8.5, PT - 8.9, PAINT)]
    prof += [(8.5, PT - 10.1, DARK), (5.0, PT - 11.1, DARK), (0.0, PT - 11.3, DARK)]
    lathe(p, PCX, PCZ, prof, 96)
    p.finish(root)


def platform_rim(root):
    """Running lights in the rim's groove, rails along the edge (not on the ship's side), thrusters."""
    p = Part("PlatformRim")
    for k in range(72):
        a = k * 5.0
        mi = RED if k % 18 == 0 else AMBER
        p.box(ppos(a, PR - 0.36, PT - 1.5), (0.12, 1.2 if mi == AMBER else 0.6, 0.3), C.rz(a), mi)
    posts = [a * 4.0 for a in range(90)]
    keep = [a for a in posts if ppos(a, PR - 0.8, 0).x >= SHIP_SIDE_X]
    for a in keep:
        q = ppos(a, PR - 0.8, PT)
        p.rod(q, q + Vector((0, 0, 1.1)), 0.05, 6, METAL)
        if a + 4.0 in keep or (a + 4.0) % 360 in keep:
            q2 = ppos(a + 4.0, PR - 0.8, PT)
            for h in (0.55, 1.1):
                p.rod(q + Vector((0, 0, h)), q2 + Vector((0, 0, h)), 0.045, 6, METAL)
        p.box(ppos(a, PR - 0.8, PT + 0.06), (0.25, 0.25, 0.12), C.rz(a), DARK)
    # Side thrusters (four nozzles each) on the rim, main thrusters and tanks under the platform.
    for a in (45.0, 135.0, 225.0, 315.0):
        p.box(ppos(a, PR + 0.4, PT - 2.25), (1.6, 3.2, 1.2), C.rz(a), DARK)
        for t in (-0.75, 0.75):
            q = ppos(a + math.degrees(t / PR), PR + 1.2, PT - 2.25)
            d = polar_b(a, 1.0)
            p.rod(q, q + d * 0.8, 0.22, 10, METAL, r2=0.38)
    p.finish(root)


def platform_underside(root):
    p = Part("PlatformUnderside")
    for k in range(24):
        a = k * 15.0
        p.beam(ppos(a, 22.0, PT - 4.75), ppos(a, 58.5, PT - 4.35), 1.0, 0.6, Vector((0, 0, 1)), DARK, 0.7)
    for k in range(6):
        a = 30.0 + k * 60.0
        c = ppos(a, 40.0, PT - 7.4)
        p.sphere(c, 3.0, 16, 8, mi=PAINT)
        p.cyl(c, 3.05, 0.35, 16, mi=DARK)
        p.cyl(c + Vector((0, 0, 2.8)), 0.8, 1.6, 10, mi=DARK)
    for k in range(6):
        a = k * 60.0
        c = ppos(a, 46.0, PT - 5.4)
        p.cyl(c, 1.2, 9.0, 14, rot=C.rz(a) @ C.rx(90), mi=PAINT)
    for a in (0.0, 90.0, 180.0, 270.0):
        c = ppos(a, 30.0, PT - 5.2)
        p.box(c, (4.0, 4.0, 1.8), C.rz(a), DARK)
        for t in (-1.0, 1.0):
            q = c + polar_b(a + 90.0, t) + Vector((0, 0, -0.9))
            p.cyl(q + Vector((0, 0, -1.2)), 1.25, 2.4, 16, mi=METAL, r2=0.8)
    c = ppos(0.0, 0.0, PT - 11.3)
    p.rod(c, c + Vector((0, 0, -10.0)), 0.5, 8, METAL, r2=0.1)
    p.sphere(c + Vector((0, 0, -10.1)), 0.3, 8, 4, mi=RED)
    p.finish(root)


def platform_markings(root):
    """Flat on the deck (a few cm): seams, the hazard band on the ship's side of the rim, deck hatches."""
    p = Part("PlatformMarkings")
    for k in range(24):
        a = k * 15.0 + 7.5
        q0, q1 = ppos(a, 10.0, PT + 0.01), ppos(a, 62.6, PT + 0.01)
        p.box((q0 + q1) / 2, ((q1 - q0).length, 0.15, 0.02), C.rz(a), DARK)
    for k in range(180):
        a = k * 2.0
        if k % 2 or ppos(a, 64.2, 0).x >= SHIP_SIDE_X + 2.0:
            continue
        p.box(ppos(a + 1.0, 64.2, PT + 0.012), (2.4, 2.0, 0.025), C.rz(a + 1.0), HAZARD)
    for x, z, w, d in (
        (30.0, 47.0, 4.0, 3.0),
        (98.0, 44.0, 3.0, 3.0),
        (20.0, -38.0, 3.6, 3.6),
        (84.0, -46.0, 3.0, 4.0),
    ):
        p.gbox((x, PT + 0.03, z), (w, 0.06, d), DARK)
        p.gbox((x, PT + 0.05, z), (w - 0.6, 0.06, d - 0.6), GRATING)
        for s in (-1, 1):
            p.gbox((x, PT + 0.04, z + s * (d / 2 - 0.15)), (w, 0.07, 0.3), HAZARD)
    for x, z in ((38.0, 36.0), (64.0, 44.0), (86.0, 36.5), (52.0, 54.0), (112.0, 18.0), (120.0, -12.0), (14.0, -30.0)):
        p.gbox((x, PT + 0.03, z), (2.0, 0.06, 1.2), DARK)
        p.gbox((x, PT + 0.05, z), (1.7, 0.06, 0.9), GRATING)
    for k in range(25):
        a = -150.0 + k * 5.0
        p.box(ppos(a, 58.0, PT + 0.012), (0.25, 2.2, 0.025), C.rz(a), AMBER)
    p.finish(root)


def build_platform(root):
    platform(root)
    platform_rim(root)
    platform_underside(root)
    platform_markings(root)


# --- preview -------------------------------------------------------------------------------------


def import_shell() -> bool:
    """The shell's models (ostra_shell_build.py) into the Preview collection, when they exist."""
    shell = ROOT / "assets" / "space_station" / "ostra" / "shell"
    files = [shell / f"{n}.glb" for n in ("shell_station", "shell_cut", "glass_station", "glass_cut")]
    if not all(f.exists() for f in files):
        return False
    for f in files:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(f))
        for obj in set(bpy.data.objects) - before:
            for coll in obj.users_collection:
                coll.objects.unlink(obj)
            C.collection("Preview").objects.link(obj)
    return True


def preview_stage(shell: bool):
    """Grey placeholder walls (from the layout; or the shell's models), floors, the ship's tail, sky and sun."""
    shell = shell and import_shell()
    mats = [flat("PreviewWall", (0.32, 0.31, 0.29), 0.7), flat("PreviewFloor", (0.18, 0.18, 0.18), 0.7)]
    mats.append(flat("PreviewShip", (0.55, 0.55, 0.53), 0.5))
    C.ASSET = "Preview"
    p = Part("PreviewShell", mats)
    for w in [] if shell else L.WALLS:
        (x0, z0), (x1, z1) = w["from"], w["to"]
        d = Vector((x1 - x0, -(z1 - z0)))
        c = g((x0 + x1) / 2, w["height"] / 2, (z0 + z1) / 2)
        p.box(c, (d.length + L.WALL, L.WALL, w["height"]), C.rz(math.degrees(math.atan2(d.y, d.x))), 0)
    for _, _, polys, _, _ in [] if shell else L.ROOMS:
        for poly in polys:
            ring = [g(x, 0.0, z) for x, z in poly]
            loft(p, [[v + Vector((0, 0, -0.3)) for v in ring], ring], 1, 1, 1)
    for _, poly in [] if shell else L.FILLS:
        ring = [g(x, 0.0, z) for x, z in poly]
        loft(p, [ring, [v + Vector((0, 0, L.FILL_HEIGHT)) for v in ring]], 0, 0, 0)
    p.gbox((-3.0, 9.0, 0.0), (22.0, 18.0, 54.0), 2)
    p.finish(None)
    scene = bpy.context.scene
    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.02, 0.022, 0.03, 1.0)
    for name, energy, color, rot in (
        ("Sun", 3.5, (1.0, 0.9, 0.8), (math.radians(50), 0, math.radians(-35))),
        ("Back", 0.8, (0.6, 0.7, 1.0), (math.radians(60), 0, math.radians(160))),
    ):
        data = bpy.data.lights.new(name, "SUN")
        data.energy = energy
        data.color = color
        data.angle = math.radians(2)
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = rot
        C.link(obj, None, "Preview")


def previews():
    preview_stage("shell" in ARGV)
    target = Vector((66.0, 0.0, 6.0))
    pitch = math.radians(35)
    shots = {
        "game": (target + Vector((0, -math.cos(pitch), math.sin(pitch))) * 185.0, target, 35.0),
        "game_near": (
            Vector((62, 0, 8)) + Vector((0, -math.cos(pitch), math.sin(pitch))) * 95.0,
            Vector((62, 0, 8)),
            35,
        ),
        "side_x": (target + Vector((185.0, -30.0, 40.0)), target, 35.0),
        "back": (target + Vector((-20.0, 185.0, 50.0)), target, 35.0),
        "top": (target + Vector((0.0, -0.01, 230.0)), target, 35.0),
        "frame": (Vector((-16.0, -52.0, 20.0)), Vector((8.0, 0.0, 10.0)), 28.0),
        "under": (target + Vector((110.0, -130.0, -70.0)), Vector((66.0, 0.0, -4.0)), 35.0),
    }
    paths = []
    for name, (loc, tgt, lens) in shots.items():
        path = TMP / f"{name}.png"
        C.render_from(path, loc, tgt, lens, 32, 1024)
        paths.append(path)
    C.contact_sheet(paths, TMP / "sheet.png", cols=3, tile=768)


# --- main ----------------------------------------------------------------------------------------

PARTS = {
    "exterior_roofs": ("ExteriorRoofs", build_roofs),
    "exterior_structures": ("ExteriorStructures", build_structures),
    "exterior_platform": ("ExteriorPlatform", build_platform),
}


def main():
    chosen = [a for a in ARGV if a in PARTS] or list(PARTS)
    scene = bpy.context.scene
    for part in chosen:
        coll = PARTS[part][0]
        if coll not in bpy.data.collections:
            scene.collection.children.link(bpy.data.collections.new(coll))
        C.ASSET = coll
        PARTS[part][1](C.asset_root(coll))
    total = 0
    for part in chosen:
        coll = PARTS[part][0]
        C.export_glb(OUT / f"{part}.glb", coll)
        stats = C.stats(coll)
        total += stats["triangles"]
        print("PART", part, stats)
        print("  per object", C.tris_per_object(coll))
    print("TOTAL triangles", total)
    if "nopreview" not in ARGV:
        previews()


if __name__ == "__main__":
    main()
