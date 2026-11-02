"""Overgrowth scatter kit: the giant fungal growth of the growth walls and the fungal groves (concepts:
overgrowth_v1..v4, batch11 growth), the big relatives of the small Overgrowth plants in assets/plants/.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/overgrowth/source/overgrowth_build.py wip r1                  # line-ups
    tools/blender.sh assets/biomes/overgrowth/source/overgrowth_build.py wip r1 band,grove
    tools/blender.sh assets/biomes/overgrowth/source/overgrowth_build.py wip r1 Growth_Cap_a     # one part close
    tools/blender.sh assets/biomes/overgrowth/source/overgrowth_build.py final

Everything it writes goes to tmp/assets/overgrowth/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: tall, small, band, grove, or a part name; default tall,small); "final" renders all of
them, puts them on a contact sheet (sheet.png) and saves overgrowth_procedural.blend, which
overgrowth_bake.py turns into the game asset.

Game contract (game/locations/scatter_type.gd): a ScatterType draws ONE mesh many times (random scale, tilt,
sink), so every part is one mesh object with one material, origin at its ground contact (bottom center),
standing on z = 0 with its stems and roots reaching below ground (SINK) so tilted or sunk instances don't float.
The parts share the small plants' look: the same color ramps, cracked plates on the caps, fibrous stems and
tiny dim bioluminescent bulbs, only with the texture features grown with the size. Per-vertex float attributes
drive the procedural materials (and bake with them):
    grad   0 at the base of a stem / the ends of a root .. 1 at its top (color ramp: dark base -> pale top)
    glow   1 on the bulbs and the tube throats (emission), 0 elsewhere
    plate  1 where the cracked plate pattern shows (cap tops)
In the .blend the parts stand in a row along X, BAKE_STEP apart (bake layout: no AO from a neighbor); the
bake stage zeroes their locations for the export. Triangle budgets (tall pieces <= ~3k, roots <= ~1.5k) are
provisional, TBD (playtest).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "overgrowth"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import common as C

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["tall", "small"]

ASSET = "Overgrowth"
TAU = math.tau
UP = Vector((0, 0, 1))
SINK = 0.5  # stems reach this far below z = 0 (m)
BAKE_STEP = 10.0
PARTS = [
    "Growth_Stalk_a",
    "Growth_Stalk_b",
    "Growth_Cap_a",
    "Growth_Cap_b",
    "Growth_Root_a",
    "Growth_Root_b",
    "Grove_Stalk_a",
    "Grove_Cap_a",
]
# Approximate linear albedo of the Overgrowth's ground (as in plants_build.py).
GROUND = ((0.018, 0.019, 0.011), (0.045, 0.047, 0.026))
ROW_DIR = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # across the iso view: nothing hides behind a neighbor
FAR_DIR = Vector((-math.sqrt(0.5), math.sqrt(0.5), 0))  # away from the iso camera

# --- math helpers -----------------------------------------------------------------------------------


def sph(az_deg: float, elev_deg: float) -> Vector:
    """Unit vector at azimuth / elevation (degrees)."""
    a, e = math.radians(az_deg), math.radians(elev_deg)
    return Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def frames(pts: list, side: Vector | None):
    """Parallel-transport frames (T, N, B) along a polyline; N starts as close to `side` as possible."""
    n = len(pts)
    T = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    s = Vector(side) if side is not None else Vector((1, 0, 0))
    n0 = s - T[0] * s.dot(T[0])
    if n0.length < 1e-4:
        s = Vector((0, 1, 0))
        n0 = s - T[0] * s.dot(T[0])
    N = [n0.normalized()]
    for i in range(1, n):
        v = N[-1] - T[i] * N[-1].dot(T[i])
        N.append(v.normalized() if v.length > 1e-6 else N[-1])
    B = [t.cross(nn) for t, nn in zip(T, N)]
    return T, N, B


def along(pts: list, f: float) -> tuple[Vector, int, float]:
    """Point at fraction f of a polyline's point index range; returns (point, index, remainder)."""
    idx = f * (len(pts) - 1)
    i = min(int(idx), len(pts) - 2)
    return pts[i].lerp(pts[i + 1], idx - i), i, idx - i


def axis_rot(direction: Vector) -> Matrix:
    """Rotation that turns +Z into `direction`."""
    return Vector(direction).normalized().to_track_quat("Z", "Y").to_matrix()


# --- mesh builder -----------------------------------------------------------------------------------


class Growth:
    """Accumulates the parts of one kit piece into one bmesh (one object, one material)."""

    def __init__(self, name: str, seed: int):
        self.name = name
        self.bm = bmesh.new()
        self.l_grad = self.bm.verts.layers.float.new("grad")
        self.l_glow = self.bm.verts.layers.float.new("glow")
        self.l_plate = self.bm.verts.layers.float.new("plate")
        self.rnd = random.Random(seed)

    def v(self, co, grad=0.0, glow=0.0, plate=0.0):
        vert = self.bm.verts.new(co)
        vert[self.l_grad], vert[self.l_glow], vert[self.l_plate] = grad, glow, plate
        return vert

    def face(self, verts, smooth=True):
        f = self.bm.faces.new(verts)
        f.smooth = smooth
        return f

    def ring(self, c, N, B, rx, ry, seg, spin=0.0, grad=0.0, glow=0.0, plate=0.0, flutes=0, flute=0.0):
        """Ellipse of seg verts; flutes: that many lengthwise ridges, the radius swelling by `flute`."""
        out = []
        for k in range(seg):
            a = spin + k * TAU / seg
            f = 1.0 + flute * math.cos(flutes * (a - spin)) if flutes else 1.0
            out.append(self.v(c + N * (math.cos(a) * rx * f) + B * (math.sin(a) * ry * f), grad, glow, plate))
        return out

    def bridge(self, ra, rb, smooth=True):
        n = len(ra)
        for k in range(n):
            self.face((ra[k], ra[(k + 1) % n], rb[(k + 1) % n], rb[k]), smooth)

    def fan(self, r, apex, smooth=True, reverse=False):
        n = len(r)
        for k in range(n):
            self.face((r[(k + 1) % n], r[k], apex) if reverse else (r[k], r[(k + 1) % n], apex), smooth)

    def sweep(
        self,
        pts,
        radii,
        seg,
        side=None,
        grads=None,
        tip=False,
        cap_end=False,
        cap_start=False,
        glow=0.0,
        flutes=0,
        flute=0.0,
        twist=0.0,
    ):
        """Tube along pts; radii per point: r or (rx along N, ry along B). tip: the last point is a spike tip.
        flutes / flute: lengthwise ridges (see ring), turned by `twist` radians per ring (fibrous, rope-like).
        Returns (rings, frames) so callers can extend the end (a tube's mouth) or place things on it."""
        n = len(pts)
        T, N, B = frames(pts, side)
        grads = grads or [i / (n - 1) for i in range(n)]
        rings = []
        last = n - 1 if tip else n
        for i in range(last):
            r = radii[i]
            rx, ry = (r, r) if isinstance(r, (int, float)) else r
            g = glow[i] if isinstance(glow, (list, tuple)) else glow
            rings.append(self.ring(pts[i], N[i], B[i], rx, ry, seg, twist * i, grads[i], g, 0.0, flutes, flute))
        for a, b in itertools.pairwise(rings):
            self.bridge(a, b)
        if tip:
            self.fan(rings[-1], self.v(pts[-1], grads[-1]))
        elif cap_end:
            self.face(rings[-1])
        if cap_start:
            self.face(list(reversed(rings[0])))
        return rings, (T, N, B)

    def lathe(
        self,
        center,
        profile,
        seg,
        rot: Matrix | None = None,
        spin=0.0,
        wobble=0.0,
        wfreq=1.0,
        glow=None,
        lobes=0,
        lobe=0.0,
        wave=0.0,
    ):
        """Surface of revolution around the local Z axis. profile: (r, z, grad, plate) bottom to top; r = 0 at
        the first / last entry closes it with a fan. glow: optional per-entry glow values. lobes: a wavy rim,
        the radius swelling by `lobe` and the height by `wave` * the widest radius, strongest at the rim."""
        rot = rot or Matrix.Identity(3)
        c = Vector(center)
        r_max = max(e[0] for e in profile)
        ph = self.rnd.uniform(0, TAU)
        rings, apexes = [], {}
        for idx, (r, z, g, p) in enumerate(profile):
            gl = glow[idx] if glow else 0.0
            if r <= 1e-6:
                apexes[idx] = self.v(c + rot @ Vector((0, 0, z)), g, gl, p)
                continue
            ring = []
            for k in range(seg):
                a = spin + k * TAU / seg
                rr, zz = r, z
                if lobes:  # two harmonics, so the rim doesn't turn into a regular polygon
                    w = (r / r_max) ** 2
                    h = math.sin(lobes * a + ph) + 0.7 * math.sin((2 * lobes + 1) * a + ph * 1.7)
                    rr = r * (1.0 + lobe * 0.6 * w * h)
                    zz = z + wave * r_max * w * math.cos((lobes - 1) * a + ph)
                local = Vector((math.cos(a) * rr, math.sin(a) * rr, zz))
                if wobble:
                    local += C.noise_vector(local * wfreq + c * 1.7) * wobble * r
                ring.append(self.v(c + rot @ local, g, gl, p))
            rings.append((idx, ring))
        for (_, a), (_, b) in itertools.pairwise(rings):
            self.bridge(a, b)
        if 0 in apexes and rings:
            self.fan(rings[0][1], apexes[0], reverse=True)
        if len(profile) - 1 in apexes and rings:
            self.fan(rings[-1][1], apexes[len(profile) - 1])
        return [r for _, r in rings]

    def blob(self, center, radius, scale=(1, 1, 1), sub=2, wobble=0.25, grad=None):
        """Lumpy ball (icosphere: sub 2 = 80 triangles). grad None: 0 at its bottom .. 1 at its top."""
        m = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*scale, 1))
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=radius, matrix=m)["verts"]
        c = Vector(center)
        seed = Vector((self.rnd.uniform(0, 50), self.rnd.uniform(0, 50), self.rnd.uniform(0, 50)))
        for vert in verts:
            d = vert.co - c
            vert.co += d.normalized() * noise.noise(d * (2.2 / radius) + seed) * wobble * radius
            zt = (d.z / (radius * scale[2]) + 1) * 0.5
            vert[self.l_grad] = zt if grad is None else grad
            vert[self.l_glow] = 0.0
            vert[self.l_plate] = 0.0
        for f in {f for vert in verts for f in vert.link_faces}:
            f.smooth = True
        return verts

    def bulb(self, center, r, glow=1.0, grad=1.0, out: Vector | None = None):
        """Bioluminescent bulb: a squashed hexagonal bipyramid (12 triangles), its axis along `out`."""
        c = Vector(center)
        rot = axis_rot(out) if out is not None else Matrix.Identity(3)
        ring = [
            self.v(c + rot @ Vector((math.cos(k * TAU / 6) * r, math.sin(k * TAU / 6) * r, 0)), grad, glow)
            for k in range(6)
        ]
        self.fan(ring, self.v(c + rot @ Vector((0, 0, r * 0.7)), grad, glow))
        self.fan(ring, self.v(c + rot @ Vector((0, 0, -r * 0.7)), grad, glow), reverse=True)

    def wobble(self, verts, amp, freq=1.0):
        """Organic irregularity: shift verts by smooth 3D noise."""
        seed = Vector((self.rnd.uniform(0, 99), self.rnd.uniform(0, 99), self.rnd.uniform(0, 99)))
        for vert in verts:
            vert.co += C.noise_vector(vert.co * freq + seed) * amp

    def finish(self, parent, mat, location=(0, 0, 0)) -> bpy.types.Object:
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, me)
        obj.location = location
        C.link(obj, parent)
        C.assign(obj, mat)
        return obj


# --- materials --------------------------------------------------------------------------------------


class NT:
    """Small node-building helper around one material's node tree."""

    def __init__(self, nt):
        self.nt = nt

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, val in props.items():
            setattr(n, k, val)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def attr(self, name):
        return self.node("ShaderNodeAttribute", attribute_type="GEOMETRY", attribute_name=name).outputs["Fac"]

    def math(self, op, a, b=None):
        return C._math(self.nt, op, a, b)

    def ramp(self, src, stops):
        """stops: [(pos, value-or-rgb)]; returns the Color output."""
        n = self.node("ShaderNodeValToRGB")
        els = n.color_ramp.elements
        while len(els) < len(stops):
            els.new(0.5)
        for el, (pos, val) in zip(els, stops):
            el.position = pos
            el.color = (*val, 1.0) if isinstance(val, tuple) else (val, val, val, 1.0)
        self.link(src, n.inputs["Fac"])
        return n.outputs["Color"]

    def coords(self, scale=(1, 1, 1)):
        coord = self.node("ShaderNodeTexCoord")
        if scale == (1, 1, 1):
            return coord.outputs["Object"]
        mp = self.node("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = scale
        self.link(coord.outputs["Object"], mp.inputs["Vector"])
        return mp.outputs["Vector"]

    def noise(self, scale, detail=4.0, rough=0.55, vec_scale=(1, 1, 1)):
        n = self.node("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        self.link(self.coords(vec_scale), n.inputs["Vector"])
        return n.outputs["Fac"]

    def voronoi(self, scale, feature="F1"):
        n = self.node("ShaderNodeTexVoronoi", feature=feature)
        n.inputs["Scale"].default_value = scale
        self.link(self.coords(), n.inputs["Vector"])
        return n

    def mix(self, fac, a, b):
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b):
        return C._mix_float(self.nt, fac, a, b)


def mat_growth(
    name: str,
    stops: list,
    size: float,
    rough=(0.4, 0.7),
    ground_h=0.4,
    streaks: float = 0.0,
    streak_dir=(1.0, 1.0, 0.12),
    plates: bool = False,
    plate_scale: float = 2.2,
    crack_w: float = 0.09,
    pores: float = 0.0,
    glow_strength: float = 2.5,
    bump: float = 0.3,
    var: float = 0.25,
) -> bpy.types.Material:
    """The small plants' organic material (plants_build.mat_plant) with its features grown by `size`: color ramp
    along the stem (grad), noise variation, fibrous streaks, cracked plates on the caps (plate, plate_scale cells
    per m), pores, mud band at the ground, cavity darkening, emission on the bulbs (glow). Non-metallic."""
    mat, nt, bsdf = C._new_material(name)
    n = NT(nt)
    s = 1.0 / size
    col = n.ramp(n.attr("grad"), stops)
    bright = n.node("ShaderNodeMapRange")
    n.link(n.noise(5.0 * s, 6.0, 0.6), bright.inputs["Value"])
    bright.inputs["From Min"].default_value = 0.3
    bright.inputs["From Max"].default_value = 0.7
    bright.inputs["To Min"].default_value = 1.0 - var
    bright.inputs["To Max"].default_value = 1.0 + var
    scale = n.node("ShaderNodeVectorMath", operation="SCALE")
    n.link(col, scale.inputs[0])
    n.link(bright.outputs["Result"], scale.inputs["Scale"])
    col = scale.outputs["Vector"]
    height = None

    def add_height(sock, k):
        nonlocal height
        h = n.math("MULTIPLY", sock, k)
        height = h if height is None else n.math("ADD", height, h)

    if streaks > 0:
        # Fibers along the stems (mostly vertical) or roots (mostly along X): noise stretched along them.
        fib = n.noise(18.0 * s, 3.0, 0.5, vec_scale=streak_dir)
        fib_mask = n.ramp(fib, [(0.35, 0.0), (0.65, 1.0)])
        col = n.mix(n.math("MULTIPLY", fib_mask, 0.45 * streaks), col, (0.01, 0.009, 0.007))
        add_height(fib, 0.5 * streaks)
    if plates:
        # Cracked plates on the cap tops, mossy olive tint per plate, dark deep cracks.
        plate_m = n.attr("plate")
        cells = n.voronoi(plate_scale)
        edges = n.voronoi(plate_scale, "DISTANCE_TO_EDGE")
        crack = n.ramp(edges.outputs["Distance"], [(0.0, 1.0), (crack_w, 0.0)])
        crack_m = n.math("MULTIPLY", crack, plate_m)
        cell_rand = n.ramp(cells.outputs["Color"], [(0.0, 0.0), (1.0, 1.0)])
        tint = n.mix(n.math("MULTIPLY", cell_rand, plate_m), col, (0.062, 0.066, 0.036))
        col = n.mix(n.math("MULTIPLY", crack_m, 0.92), tint, (0.005, 0.006, 0.004))
        add_height(n.math("MULTIPLY", crack_m, -1.0), 1.0)
        # Each plate bulges a little toward its middle.
        dome = n.ramp(edges.outputs["Distance"], [(0.0, 0.0), (0.35, 1.0)])
        add_height(n.math("MULTIPLY", dome, plate_m), 0.35)
        lumps = n.noise(14.0 * s, 3.0, 0.5)
        add_height(n.math("MULTIPLY", lumps, plate_m), 0.3)
    if pores > 0:
        dots = n.voronoi(16.0 * s)
        pore = n.ramp(dots.outputs["Distance"], [(0.08, 1.0), (0.22, 0.0)])
        col = n.mix(n.math("MULTIPLY", pore, 0.7 * pores), col, (0.008, 0.009, 0.006))
        add_height(n.math("MULTIPLY", pore, -1.0), 0.5 * pores)
    # Cavities (between stems, under caps) darker.
    ao = n.node("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.2 * size
    cav = n.ramp(ao.outputs["AO"], [(0.25, 1.0), (0.9, 0.0)])
    col = n.mix(n.math("MULTIPLY", cav, 0.75), col, (0.006, 0.006, 0.005))
    # Mud band where it meets the ground.
    sep = n.node("ShaderNodeSeparateXYZ")
    n.link(n.coords(), sep.inputs["Vector"])
    band = n.node("ShaderNodeMapRange")
    n.link(sep.outputs["Z"], band.inputs["Value"])
    band.inputs["From Min"].default_value = 0.0
    band.inputs["From Max"].default_value = ground_h
    band.inputs["To Min"].default_value = 0.85
    band.inputs["To Max"].default_value = 0.0
    dirt = n.math("MULTIPLY", band.outputs["Result"], n.ramp(n.noise(9.0 * s, 4.0, 0.6), [(0.3, 0.55), (0.6, 1.0)]))
    col = n.mix(dirt, col, MUD)
    n.link(col, bsdf.inputs["Base Color"])
    rough_s = n.mixf(n.noise(7.0 * s, 4.0, 0.5), rough[0], rough[1])
    rough_s = n.mixf(dirt, rough_s, 0.95)
    n.link(rough_s, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Color"].default_value = (*GLOW_TEAL, 1.0)
    n.link(n.math("MULTIPLY", n.attr("glow"), glow_strength), bsdf.inputs["Emission Strength"])
    # Bump: fine organic noise (kept fine: it still shows on the close camera) plus the pattern heights.
    add_height(n.noise(40.0 * s, 4.0, 0.6), 0.25)
    bmp = n.node("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = bump
    bmp.inputs["Distance"].default_value = 0.004 * size
    n.link(height, bmp.inputs["Height"])
    n.link(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


MUD = (0.014, 0.014, 0.009)
GLOW_TEAL = (0.2, 1.0, 0.72)


def make_materials() -> dict:
    """One material per kind of piece, the giant cousins of the small plants' ramps (plants_build.py)."""
    M = {}
    # Tubes: Overgrowth_Tube_a's dark teal-olive flesh, paling to the lip; small plated caps on some.
    M["stalk"] = mat_growth(
        "Growth_Stalk",
        [
            (0.0, (0.012, 0.02, 0.015)),
            (0.45, (0.026, 0.045, 0.03)),
            (0.8, (0.055, 0.068, 0.045)),
            (0.84, (0.018, 0.02, 0.013)),
            (0.9, (0.046, 0.043, 0.028)),
            (1.0, (0.066, 0.064, 0.044)),
        ],
        size=3.0,
        rough=(0.35, 0.65),
        ground_h=0.6,
        streaks=0.55,
        plates=True,
        plate_scale=3.2,
        pores=0.4,
    )
    # Mushrooms: Overgrowth_Fungus_b's brown stems, dark gills, mossy olive cracked plates.
    M["cap"] = mat_growth(
        "Growth_Cap",
        [
            (0.0, (0.025, 0.024, 0.014)),
            (0.45, (0.055, 0.054, 0.034)),
            (0.55, (0.018, 0.019, 0.012)),
            (0.75, (0.042, 0.038, 0.025)),
            (1.0, (0.064, 0.057, 0.038)),
        ],
        size=3.0,
        rough=(0.35, 0.65),
        ground_h=0.6,
        streaks=0.35,
        plates=True,
        plate_scale=1.9,
        crack_w=0.08,
    )
    # Roots: the stems' brown, darker where they dive into the ground, porous.
    M["root"] = mat_growth(
        "Growth_Root",
        [(0.0, (0.016, 0.015, 0.01)), (0.5, (0.042, 0.04, 0.026)), (1.0, (0.068, 0.064, 0.042))],
        size=2.0,
        rough=(0.55, 0.85),
        bump=0.5,
        ground_h=0.25,
        streaks=0.6,
        streak_dir=(0.12, 1.0, 1.0),
        pores=0.5,
        var=0.3,
    )
    return M


# --- shapes -----------------------------------------------------------------------------------------

# Grad values of a cap's parts per material (see the ramps in make_materials): stem top, dark underside / gills,
# rim, plated top.
CAP_GRADS = {"stalk": (0.8, 0.84, 0.9, 0.95), "cap": (0.46, 0.55, 0.7, 0.85)}


def mound(p: Growth, base, radius: float, height: float = 0.35):
    """Low lumpy mound of root flesh around a stem's foot, mostly buried: fills between its roots."""
    p.blob(Vector(base) + Vector((0, 0, -height * 0.3)), radius, scale=(1, 1, height / radius), wobble=0.25, grad=0.04)


def foot_roots(p: Growth, base, r_foot: float, count: int, reach: float, thick: float, rise: float, fork=0.6):
    """Thick roots leaving a stem's foot: plank-tall at the stem, curving out low over the ground in a small arch
    and diving in at their ends (no gap under them at the stem, no points above ground), fluted and twisted like
    rope, of uneven length and thickness; some fork."""
    base = Vector(base)
    az0 = p.rnd.uniform(0, 360)
    # (fraction of the reach, height of the center, thickness factor)
    prof = [(0.0, rise, 1.0), (0.16, rise * 0.5, 0.85), (0.38, 0.5, 0.7), (0.6, 0.95, 0.56), (0.8, 0.5, 0.46)]
    for k in range(count):
        az = az0 + k * 360 / count + p.rnd.uniform(-22, 22)
        o = sph(az, 0)
        side = UP.cross(o)
        rr = reach * p.rnd.uniform(0.6, 1.3)
        th = thick * p.rnd.uniform(0.75, 1.2)
        curl = p.rnd.uniform(-0.6, 0.6)
        pts, radii = [], []
        for i, (f, z, w) in enumerate(prof):
            dist = r_foot * 0.45 + (r_foot * 0.55 + rr) * f
            zc = z if i < 2 else th * w * z
            pts.append(base + o * dist + side * curl * rr * f * f + Vector((0, 0, zc)))
            radii.append((rise * 0.6, th) if i == 0 else (rise * 0.47, th * w) if i == 1 else (th * w, th * w * 0.95))
        f_end = 1.05
        pts.append(base + o * (r_foot + rr * f_end) + side * curl * rr * f_end * f_end + Vector((0, 0, -0.45)))
        radii.append((th * 0.35, th * 0.35))
        p.sweep(
            pts,
            radii,
            7,
            side=UP,
            grads=[0.1, 0.07, 0.05, 0.04, 0.03, 0.0],
            cap_end=True,
            flutes=3,
            flute=0.06,
            twist=0.2,
        )
        if p.rnd.random() < fork:
            s = pts[2]
            d = (o + side * p.rnd.choice((-1, 1)) * 0.9).normalized()
            ln = rr * p.rnd.uniform(0.35, 0.55)
            bp = [s, s + d * ln * 0.55 + Vector((0, 0, th * 0.25)), s + d * ln + Vector((0, 0, -0.4))]
            p.sweep(bp, [th * 0.5, th * 0.42, th * 0.26], 5, grads=[0.04, 0.03, 0.0], cap_end=True)


def stem_bulbs(p: Growth, pts, rings_frames, radius_at, count: int, h0: float, h1: float, r: float):
    """A loose vertical row of bulbs half sunk into one side of a stem."""
    _, N, B = rings_frames
    a = p.rnd.uniform(0, TAU)
    for i in range(count):
        f = lerp(h0, h1, (i + 0.5) / count) + p.rnd.uniform(-0.03, 0.03)
        c, idx, _ = along(pts, f)
        aa = a + p.rnd.uniform(-0.35, 0.35)
        out = N[idx] * math.cos(aa) + B[idx] * math.sin(aa)
        p.bulb(c + out * radius_at(f) * 0.93, r, out=out, grad=lerp(0.3, 0.8, f))


def shelves(p: Growth, pts, rings_frames, radius_at, count: int, h0: float, h1: float, size: float, kind: str):
    """Small plated bracket mushrooms on a stem's side (the small plants' caps), some with a bulb under them."""
    _, N, B = rings_frames
    _, under, edge, top = CAP_GRADS[kind]
    a = p.rnd.uniform(0, TAU)
    for i in range(count):
        f = lerp(h0, h1, (i + 0.5) / count)
        c, idx, _ = along(pts, f)
        a += p.rnd.uniform(1.6, 2.6)
        out = N[idx] * math.cos(a) + B[idx] * math.sin(a)
        cap_r = size * p.rnd.uniform(0.75, 1.2)
        rot = axis_rot((UP + out * 0.35).normalized())
        center = c + out * (radius_at(f) * 0.8 + cap_r * 0.45)
        prof = [
            (0.0, -cap_r * 0.18, under, 0.0),
            (cap_r * 0.9, -cap_r * 0.12, under, 0.0),
            (cap_r, 0.0, edge, 0.5),
            (cap_r * 0.72, cap_r * 0.3, top, 1.0),
            (0.0, cap_r * 0.42, 1.0, 1.0),
        ]
        p.lathe(center, prof, 8, rot=rot, spin=p.rnd.uniform(0, 1), wobble=0.12, wfreq=2.5)
        if i % 2 == 0:
            p.bulb(center + rot @ Vector((0, 0, -cap_r * 0.2)), max(0.04, cap_r * 0.14), out=-UP, grad=under)


def lumps(p: Growth, pts, rings_frames, radius_at, count: int, h0: float, h1: float, grad_top: float):
    """Swollen fleshy lumps half sunk into a stem's side."""
    _, N, B = rings_frames
    for _ in range(count):
        f = p.rnd.uniform(h0, h1)
        c, idx, _ = along(pts, f)
        a = p.rnd.uniform(0, TAU)
        out = N[idx] * math.cos(a) + B[idx] * math.sin(a)
        rr = radius_at(f)
        p.blob(c + out * rr * 0.55, rr * 0.62, scale=(1, 1, 1.7), sub=2, wobble=0.2, grad=grad_top * f)


def cap_top(p: Growth, style: str, top: Vector, axis: Vector, cap_r: float, rt: float, seg: int, bulbs: int, kind: str):
    """A stem's cap, centered on the stem's top point, its axis along `axis`:
    "trumpet" a funnel flaring out of the stem into a lobed, wavy, plated cap (the concepts' giant stalks);
    "dome"    a thick domed cap with cracked plates (the small plants' mushroom caps), lobed rim;
    "goblet"  the stem widens into a flat cracked top with a thick rounded rim.
    Bulbs hang under the rim."""
    stem, under, edge, top_g = CAP_GRADS[kind]
    rot = axis_rot(axis)
    if style == "trumpet":
        prof = [
            (rt * 0.92, -cap_r * 1.2, stem, 0.0),
            (rt * 1.12, -cap_r * 0.85, stem, 0.0),
            (cap_r * 0.36, -cap_r * 0.5, under, 0.0),
            (cap_r * 0.62, -cap_r * 0.24, under, 0.0),
            (cap_r * 0.88, -cap_r * 0.06, under + 0.03, 0.0),
            (cap_r * 1.0, cap_r * 0.06, edge, 0.3),
            (cap_r * 1.02, cap_r * 0.17, top_g, 0.8),
            (cap_r * 0.8, cap_r * 0.25, 1.0, 1.0),
            (cap_r * 0.4, cap_r * 0.29, 1.0, 1.0),
            (0.0, cap_r * 0.3, 1.0, 1.0),
        ]
        bulb_at = (cap_r * 0.62, -cap_r * 0.2)
    elif style == "goblet":
        prof = [
            (rt * 0.92, -cap_r * 0.45, stem, 0.0),
            (cap_r * 0.55, -cap_r * 0.27, under, 0.0),
            (cap_r * 0.88, -cap_r * 0.11, under + 0.05, 0.0),
            (cap_r * 1.0, -cap_r * 0.02, edge, 0.2),
            (cap_r * 1.03, cap_r * 0.1, top_g, 0.7),
            (cap_r * 0.95, cap_r * 0.18, top_g + 0.05, 1.0),
            (cap_r * 0.62, cap_r * 0.21, 1.0, 1.0),
            (cap_r * 0.25, cap_r * 0.23, 1.0, 1.0),
            (0.0, cap_r * 0.24, 1.0, 1.0),
        ]
        bulb_at = (cap_r * 0.9, -cap_r * 0.07)
    else:
        t = cap_r * 0.6
        prof = [
            (rt * 0.85, -0.05, stem, 0.0),
            (cap_r * 0.55, -0.06 * cap_r, under, 0.0),
            (cap_r * 0.92, -0.11 * cap_r, under + 0.05, 0.0),
            (cap_r * 1.02, -0.04 * cap_r, edge, 0.4),
            (cap_r * 1.0, t * 0.22, top_g, 1.0),
            (cap_r * 0.86, t * 0.62, top_g + 0.07, 1.0),
            (cap_r * 0.58, t * 0.93, top_g + 0.12, 1.0),
            (cap_r * 0.26, t * 1.06, 1.0, 1.0),
            (0.0, t * 1.09, 1.0, 1.0),
        ]
        bulb_at = (cap_r * 0.8, -0.1 * cap_r - 0.03)
    p.lathe(top, prof, seg, rot=rot, spin=p.rnd.uniform(0, 1), wobble=0.06, wfreq=0.9, lobes=5, lobe=0.07, wave=0.05)
    for k in range(bulbs):
        a = k * TAU / bulbs + p.rnd.uniform(-0.25, 0.25)
        local = Vector((math.cos(a) * bulb_at[0], math.sin(a) * bulb_at[0], bulb_at[1]))
        p.bulb(top + rot @ local, max(0.05, cap_r * 0.035), out=rot @ Vector((0, 0, -1)), grad=under)


def giant_tube(
    p: Growth,
    base,
    height: float,
    r: float,
    lean_dir: Vector,
    lean: float,
    seg: int,
    top: str = "mouth",
    bulbs: int = 0,
    foot: float = 0.8,
    cap_r: float = 0.0,
    n_shelves: int = 0,
    n_lumps: int = 0,
):
    """Fleshy ribbed, lumpy tube rising from a flared foot, a belly below its neck. top: "mouth" (an open lipped
    mouth, its throat glowing dimly deep inside), "pod" (a swollen closed head with plates), or a cap style of
    cap_top() with cap_r. Returns (points, frames, radius_at) for roots, shelves and bulbs."""
    base = Vector(base)
    d = Vector(lean_dir).normalized()
    side = d.cross(UP)
    wig = p.rnd.uniform(0, TAU)
    seed = p.rnd.uniform(0, 100)
    n = max(9, round(height * 1.7))
    pts, radii = [], []

    def radius_at(t: float) -> float:
        z = -SINK + (height + SINK) * t
        rr = r * (1.0 + foot * math.exp(-max(z, 0.0) / 0.55))
        rr *= 1.0 + 0.2 * math.exp(-(((t - 0.62) / 0.16) ** 2))
        rr *= 1.0 + 0.13 * noise.noise(Vector((z * 0.8, seed, 0.0)))  # swellings
        return rr * lerp(1.0, 0.8, t)

    for i in range(n):
        t = i / (n - 1)
        z = -SINK + (height + SINK) * t
        bend = side * math.sin(t * 3.0 + wig) * 0.03 * height * t
        pts.append(base + Vector((0, 0, z)) + d * lean * height * t * t + bend)
        radii.append(radius_at(t) * (1.08 if i % 2 else 0.94))  # fleshy ribs
    rings, fr = p.sweep(
        pts,
        radii,
        seg,
        side=Vector((1, 0, 0)),
        grads=[0.8 * i / (n - 1) for i in range(n)],
        flutes=4,
        flute=0.07,
        twist=0.12,
    )
    p.wobble([v for ring in rings for v in ring], r * 0.1, freq=1.0)
    T, N, B = fr
    tp, t_, n_, b_ = pts[-1], T[-1], N[-1], B[-1]
    rt = radii[-1]
    if top == "mouth":
        lip = p.ring(tp + t_ * rt * 0.14, n_, b_, rt * 1.36, rt * 1.3, seg, grad=0.97)
        rim = p.ring(tp + t_ * rt * 0.12, n_, b_, rt * 0.9, rt * 0.9, seg, grad=1.0)
        throat = p.ring(tp - t_ * rt * 0.6, n_, b_, rt * 0.66, rt * 0.66, seg, grad=0.84, glow=0.05)
        p.wobble(lip, rt * 0.08, freq=2.0)
        p.bridge(rings[-1], lip)
        p.bridge(lip, rim)
        p.bridge(rim, throat)
        p.fan(throat, p.v(tp - t_ * rt * 0.95, 0.84, 0.3))
    elif top == "pod":
        rot = axis_rot(t_)
        prof = [
            (rt * 0.95, -rt * 0.3, 0.8, 0.0),
            (rt * 1.35, rt * 0.45, 0.9, 0.3),
            (rt * 1.3, rt * 1.2, 0.95, 1.0),
            (rt * 0.85, rt * 1.85, 1.0, 1.0),
            (0.0, rt * 2.1, 1.0, 1.0),
        ]
        p.lathe(tp, prof, seg, rot=rot, spin=p.rnd.uniform(0, 1), wobble=0.08, wfreq=1.5)
        for _ in range(2):
            a = p.rnd.uniform(0, TAU)
            out = rot @ Vector((math.cos(a), math.sin(a), 0.25)).normalized()
            p.bulb(tp + rot @ Vector((0, 0, rt * 0.7)) + out * rt * 1.28, max(0.045, rt * 0.14), out=out, grad=0.95)
    else:
        p.face(rings[-1])
        cap_top(p, top, tp, t_, cap_r, rt, seg + 8, max(3, round(cap_r * 6)), "stalk")
    if bulbs:
        stem_bulbs(p, pts, fr, radius_at, bulbs, 0.3, 0.78, max(0.045, r * 0.13))
    if n_shelves:
        shelves(p, pts, fr, radius_at, n_shelves, 0.25, 0.7, max(0.18, r * 0.65), "stalk")
    if n_lumps:
        lumps(p, pts, fr, radius_at, n_lumps, 0.2, 0.6, 0.8)
    return pts, fr, radius_at


def giant_mushroom(
    p: Growth,
    base,
    height: float,
    cap_r: float,
    stalk_r: float,
    lean_dir: Vector,
    lean: float,
    seg: int,
    bulbs: int,
    style: str = "dome",
    foot: float = 0.9,
    n_shelves: int = 0,
    n_lumps: int = 0,
):
    """Thick fleshy stem on a flared foot under a giant cap (cap_top's "dome" or "goblet"; a goblet's stem widens
    into its cap). Returns (points, frames, radius_at)."""
    base = Vector(base)
    d = Vector(lean_dir).normalized()
    goblet = style == "goblet"
    seed = p.rnd.uniform(0, 100)
    n = 10
    top_z = height - (cap_r * 0.45 if goblet else 0.0)

    def radius_at(t: float) -> float:
        z = -SINK + (top_z + SINK) * t
        rr = stalk_r * (1.0 + foot * math.exp(-max(z, 0.0) / 0.6))
        rr *= 1.0 - 0.08 * math.sin(t * math.pi)  # waist
        rr *= 1.0 + 0.1 * noise.noise(Vector((z * 0.9, seed, 0.0)))
        return rr * (1.0 + 0.9 * t**4 if goblet else 1.0)

    pts, radii = [], []
    for i in range(n):
        t = i / (n - 1)
        z = -SINK + (top_z + SINK) * t
        pts.append(base + Vector((0, 0, z)) + d * lean * height * t * t)
        radii.append(radius_at(t) * (1.04 if i % 2 else 0.97))
    rings, fr = p.sweep(
        pts,
        radii,
        seg - 8,
        side=Vector((1, 0, 0)),
        grads=[0.46 * i / (n - 1) for i in range(n)],
        flutes=5,
        flute=0.07,
        twist=0.1,
    )
    p.wobble([v for ring in rings for v in ring], stalk_r * 0.08, freq=1.2)
    axis = (UP + d * lean * 1.2).normalized()
    cap_top(p, style, pts[-1], axis, cap_r, radii[-1], seg, bulbs, "cap")
    if n_shelves:
        shelves(p, pts, fr, radius_at, n_shelves, 0.25, 0.65, max(0.18, stalk_r * 0.55), "cap")
    if n_lumps:
        lumps(p, pts, fr, radius_at, n_lumps, 0.2, 0.55, 0.46)
    return pts, fr, radius_at


def root_run(
    p: Growth,
    start,
    direction,
    length: float,
    r0: float,
    r1: float,
    keys: list,
    forks: int = 0,
    n: int = 12,
    seg: int = 8,
):
    """A thick root running over the ground (all of a piece's roots flow roughly the same way, so it never reads
    as limbs around a body), tapering from r0 to r1, its center's height following `keys` [(t, z)] (below
    -r: buried, so it arches out of the ground and dives back in), knotted, lightly fluted and twisted; `forks`
    thinner roots leave its highest points at a shallow angle forward and dive in. Returns (points, frames,
    radii)."""
    s = Vector((start[0], start[1], 0.0))  # its height comes from the keys only
    d = Vector((*direction[:2], 0)).normalized()
    side = UP.cross(d)
    ph = p.rnd.uniform(0, TAU)
    pts, radii, grads = [], [], []
    zs = [key_height(keys, i / (n - 1)) for i in range(n)]
    for _ in range(2):  # soften the turns at the keys, so the arches bend evenly
        zs = [zs[0]] + [0.25 * a + 0.5 * b + 0.25 * c for a, b, c in zip(zs, zs[1:], zs[2:])] + [zs[-1]]
    for i in range(n):
        t = i / (n - 1)
        rr = lerp(r0, r1, t) * p.rnd.uniform(0.92, 1.08)
        if i % 3 == 1:
            rr *= 1.15  # knot
        z = zs[i]
        pts.append(s + d * length * t + side * math.sin(t * math.pi * 1.3 + ph) * 0.07 * length + Vector((0, 0, z)))
        radii.append((rr * 0.85, rr * 1.12))
        grads.append(min(1.0, 0.2 + 0.7 * max(0.0, z + rr) / 1.0))
    rings, fr = p.sweep(
        pts, radii, seg, side=UP, grads=grads, cap_end=True, cap_start=True, flutes=3, flute=0.05, twist=0.15
    )
    p.wobble([v for ring in rings for v in ring], r0 * 0.12, freq=1.4)
    radii = [rx for rx, _ in radii]
    T = fr[0]
    crests = sorted(range(2, n - 3), key=lambda i: -pts[i].z)
    for k, i in enumerate(crests[:forks]):
        turn = math.radians(p.rnd.uniform(22, 38)) * (1 if k % 2 else -1)
        fd = Matrix.Rotation(turn, 3, "Z") @ Vector((T[i].x, T[i].y, 0)).normalized()
        ln = length * p.rnd.uniform(0.28, 0.4)
        a = pts[i]
        f_r = radii[i] * 0.6
        keys = [(0.0, a.z), (0.3, a.z * 0.6 + f_r), (0.75, -f_r * 0.4), (1.0, -0.4)]
        root_run(p, a, fd, ln, f_r, f_r * 0.4, keys, n=7, seg=6)
    return pts, fr, radii


def key_height(keys: list, t: float) -> float:
    """Smooth (smoothstep) interpolation of [(t, z)] keys."""
    for (t0, z0), (t1, z1) in itertools.pairwise(keys):
        if t <= t1:
            u = min(1.0, max(0.0, (t - t0) / (t1 - t0)))
            return lerp(z0, z1, u * u * (3 - 2 * u))
    return keys[-1][1]


def rootlet(p: Growth, start, direction, length: float, r: float):
    """Thin root leaving a thicker one, arching a little and diving into the ground."""
    a = Vector(start)
    d = Vector((*direction[:2], 0)).normalized()
    pts = [a, a + d * length * 0.45 + Vector((0, 0, 0.05 - a.z * 0.4)), a + d * length + Vector((0, 0, -a.z - 0.35))]
    p.sweep(pts, [r, r * 0.8, r * 0.45], 5, grads=[0.5, 0.4, 0.0], cap_end=True)


def root_bulbs(p: Growth, pts, fr, radii, count: int, r: float):
    """Bulbs on the upper side of a root's crests."""
    T = fr[0]
    for i in sorted(range(2, len(pts) - 2), key=lambda i: -pts[i].z)[:count]:
        up = (UP - T[i] * UP.dot(T[i])).normalized()
        side = T[i].cross(up) * p.rnd.uniform(-0.6, 0.6)
        out = (up + side).normalized()
        p.bulb(pts[i] + out * radii[i] * 0.92, max(0.04, r), out=out, grad=0.9)


# --- the pieces -------------------------------------------------------------------------------------


def build_growth_stalk_a(root, M):
    """Clump of six giant fleshy tubes, 1.8-7.8 m, most of them open-mouthed, two with swollen plated pods, on a
    root mound with thick roots running out (the giant Overgrowth_Tube_a)."""
    p = Growth("Growth_Stalk_a", 201)
    specs = [
        ((0.0, 0.0), 7.8, 0.44, (-0.3, 0.4), 0.05, 11, "mouth", 4, 2, 1),
        ((0.8, 0.32), 6.3, 0.38, (1.0, 0.3), 0.07, 10, "mouth", 3, 1, 1),
        ((-0.6, 0.64), 5.2, 0.34, (-1.0, 0.6), 0.08, 10, "pod", 0, 1, 0),
        ((0.22, -0.84), 4.1, 0.31, (0.3, -1.0), 0.09, 9, "mouth", 2, 0, 1),
        ((-0.84, -0.42), 2.9, 0.28, (-1.0, -0.5), 0.1, 9, "mouth", 0, 0, 0),
        ((1.04, -0.62), 1.8, 0.22, (1.0, -0.6), 0.1, 8, "pod", 0, 0, 0),
    ]
    for (x, y), h, r, d, lean, seg, top, bulbs, n_shelves, n_lumps in specs:
        giant_tube(p, (x, y, 0), h, r, Vector((*d, 0)), lean, seg, top, bulbs, n_shelves=n_shelves, n_lumps=n_lumps)
    mound(p, (0.1, -0.1, 0), 1.45, 0.4)
    foot_roots(p, Vector((0.1, -0.1, 0)), 1.1, 7, 1.3, 0.2, 0.5)
    return p.finish(root, M["stalk"])


def build_growth_stalk_b(root, M):
    """Clump of four stalks, 3.2-7.6 m, three opening into lobed trumpet caps (the concepts' giant stalks), one
    open-mouthed tube; bracket shelves, lumps and bulb rows up their sides, thick roots running out."""
    p = Growth("Growth_Stalk_b", 211)
    giant_tube(
        p, (0, 0, 0), 6.7, 0.42, Vector((0.5, 0.4, 0)), 0.05, 11, "trumpet", 4, cap_r=1.15, n_shelves=2, n_lumps=1
    )
    giant_tube(p, (-0.95, 0.35, 0), 5.2, 0.36, Vector((-1.0, 0.25, 0)), 0.08, 10, "trumpet", 3, cap_r=0.9, n_shelves=1)
    giant_tube(p, (0.65, -0.8, 0), 4.3, 0.33, Vector((0.6, -1.0, 0)), 0.1, 10, "mouth", 0, n_lumps=1)
    giant_tube(p, (-0.45, -0.9, 0), 2.8, 0.3, Vector((-0.6, -1.0, 0)), 0.1, 9, "trumpet", 0, cap_r=0.62)
    mound(p, (-0.1, -0.2, 0), 1.4, 0.4)
    foot_roots(p, Vector((-0.1, -0.2, 0)), 1.05, 7, 1.3, 0.2, 0.5)
    return p.finish(root, M["stalk"])


def build_growth_cap_a(root, M):
    """Giant mushroom, 6.9 m, its lobed, domed, plated cap 4.5 m across with bulbs under the rim, a young 2 m one
    at its foot (the giant Overgrowth_Fungus_b); bracket shelves on the stem, roots running out."""
    p = Growth("Growth_Cap_a", 221)
    giant_mushroom(p, (0, 0, 0), 5.6, 2.2, 0.55, Vector((-0.4, 0.6, 0)), 0.05, 24, 10, n_shelves=3, n_lumps=2)
    giant_mushroom(p, (1.3, -0.75, 0), 1.6, 0.75, 0.2, Vector((1.0, -0.5, 0)), 0.12, 14, 4)
    mound(p, (0.2, -0.1, 0), 1.25, 0.4)
    foot_roots(p, Vector((0, 0, 0)), 0.9, 7, 1.4, 0.22, 0.55)
    return p.finish(root, M["cap"])


def build_growth_cap_b(root, M):
    """Two goblet mushrooms, 5.8 and 3.6 m: thick stems widening into flat cracked tops with rounded rims, dim
    bulbs under the rims, roots running out."""
    p = Growth("Growth_Cap_b", 231)
    giant_mushroom(
        p, (0, 0, 0), 5.8, 1.75, 0.48, Vector((0.3, 0.5, 0)), 0.04, 22, 8, style="goblet", n_shelves=2, n_lumps=1
    )
    giant_mushroom(p, (1.55, -0.95, 0), 3.6, 1.05, 0.34, Vector((1.0, -0.6, 0)), 0.08, 18, 5, style="goblet")
    mound(p, (0.7, -0.45, 0), 1.4, 0.38)
    foot_roots(p, Vector((0.7, -0.45, 0)), 1.1, 7, 1.3, 0.2, 0.5)
    return p.finish(root, M["cap"])


def root_bundle(p: Growth, specs: list) -> None:
    """Roots flowing side by side the same way (from the growth toward the open ground), crossing each other in
    long, gentle arches in and out of the ground. specs: (y offset, turn in degrees, length, r0, arch keys
    [(t, top of the root)], forks); bulbs on the thicker ones' crests."""
    for y, turn, length, r0, tops, forks in specs:
        d = Matrix.Rotation(math.radians(turn), 3, "Z") @ Vector((1, 0, 0))
        start = Vector((0, y, 0)) - d * (length / 2)
        keys = [(t, top - r0 * (1.0 - 0.6 * t) if top > -0.3 else top) for t, top in tops]
        n, seg = (19, 7) if r0 > 0.25 else (14, 6)
        pts, fr, radii = root_run(p, start, d, length, r0, r0 * 0.4, keys, forks=forks, n=n, seg=seg)
        root_bulbs(p, pts, fr, radii, 2 if r0 > 0.25 else 1 if r0 > 0.18 else 0, 0.045)


def build_growth_root_a(root, M):
    """A bundle of five roots of different thickness flowing the same way, 4.5 m long and 2.4 m wide, crossing
    in long gentle arches, the thickest one rising to 1 m with daylight under it; forks, bulbs on the crests."""
    p = Growth("Growth_Root_a", 261)
    gentle = [(0.0, -0.45), (0.22, 0.0), (0.5, 0.6), (0.78, 0.05), (1.0, -0.45)]
    root_bundle(
        p,
        [
            (0.05, 4, 4.5, 0.34, [(0.0, -0.5), (0.18, 0.1), (0.42, 1.0), (0.7, 0.2), (0.85, 0.35), (1.0, -0.45)], 2),
            (-0.6, -9, 3.9, 0.24, [(0.0, -0.45), (0.3, 0.55), (0.55, 0.0), (0.8, 0.45), (1.0, -0.45)], 1),
            (0.65, 11, 3.6, 0.2, gentle, 1),
            (-1.05, 6, 3.0, 0.15, [(0.0, -0.45), (0.4, 0.4), (1.0, -0.45)], 0),
            (1.1, -7, 3.2, 0.16, [(0.0, -0.45), (0.25, 0.1), (0.6, 0.45), (1.0, -0.45)], 0),
        ],
    )
    return p.finish(root, M["root"])


def build_growth_root_b(root, M):
    """A braid of four roots snaking in and out of the ground out of step, 4.5 m long and 2 m wide, the thickest
    arching to 1 m twice; forks, bulbs on the crests."""
    p = Growth("Growth_Root_b", 271)
    root_bundle(
        p,
        [
            (0.0, -3, 4.5, 0.36, [(0.0, -0.5), (0.25, 1.0), (0.48, 0.0), (0.72, 0.8), (1.0, -0.45)], 2),
            (0.55, 8, 4.0, 0.22, [(0.0, -0.45), (0.15, 0.1), (0.38, 0.0), (0.6, 0.6), (0.85, 0.1), (1.0, -0.45)], 1),
            (-0.6, -10, 4.1, 0.25, [(0.0, -0.45), (0.35, 0.65), (0.6, 0.1), (0.85, 0.4), (1.0, -0.45)], 1),
            (-1.0, 5, 2.8, 0.14, [(0.0, -0.45), (0.5, 0.35), (1.0, -0.45)], 0),
        ],
    )
    return p.finish(root, M["root"])


def build_grove_stalk_a(root, M):
    """Single giant stalk, 5 m, opening into a lobed trumpet cap, shelves and a row of bulbs on its side; compact
    foot (about 1.1 m) so the grove's paths stay open."""
    p = Growth("Grove_Stalk_a", 241)
    giant_tube(
        p,
        (0, 0, 0),
        4.3,
        0.3,
        Vector((0.4, -0.3, 0)),
        0.05,
        11,
        "trumpet",
        4,
        foot=0.6,
        cap_r=0.8,
        n_shelves=2,
        n_lumps=1,
    )
    foot_roots(p, Vector((0, 0, 0)), 0.42, 4, 0.22, 0.13, 0.4, fork=0.0)
    return p.finish(root, M["stalk"])


def build_grove_cap_a(root, M):
    """Single giant mushroom, 4.3 m, lobed domed plated cap 3 m across; compact foot (about 1.1 m)."""
    p = Growth("Grove_Cap_a", 251)
    giant_mushroom(p, (0, 0, 0), 3.4, 1.45, 0.33, Vector((0.5, 0.4, 0)), 0.06, 20, 7, foot=0.6, n_shelves=2)
    foot_roots(p, Vector((0, 0, 0)), 0.45, 4, 0.22, 0.14, 0.42, fork=0.0)
    return p.finish(root, M["cap"])


BUILDERS = {
    "Growth_Stalk_a": build_growth_stalk_a,
    "Growth_Stalk_b": build_growth_stalk_b,
    "Growth_Cap_a": build_growth_cap_a,
    "Growth_Cap_b": build_growth_cap_b,
    "Growth_Root_a": build_growth_root_a,
    "Growth_Root_b": build_growth_root_b,
    "Grove_Stalk_a": build_grove_stalk_a,
    "Grove_Cap_a": build_grove_cap_a,
}


# --- build + report ---------------------------------------------------------------------------------


def bake_location(name: str) -> Vector:
    return Vector((PARTS.index(name) * BAKE_STEP, 0, 0))


def build() -> dict:
    root = C.asset_root(ASSET)
    M = make_materials()
    objs = {}
    for name in PARTS:
        obj = BUILDERS[name](root, M)
        obj.location = bake_location(name)
        objs[name] = obj
    return objs


def per_object_stats(objs: dict) -> dict:
    dg = bpy.context.evaluated_depsgraph_get()
    out = {}
    for name, obj in objs.items():
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        # Footprint at the ground: the widest extent of what stands between 0 and 0.3 m.
        low = [(v.co.x, v.co.y) for v in me.vertices if 0.0 <= v.co.z <= 0.3]
        foot = max((math.hypot(x, y) for x, y in low), default=0.0)
        out[name] = {
            "tris": len(me.loop_triangles),
            "size": (round(max(xs) - min(xs), 2), round(max(ys) - min(ys), 2), round(max(zs), 2)),
            "zmin": round(min(zs), 3),
            "foot_r": round(foot, 2),
        }
        obj.evaluated_get(dg).to_mesh_clear()
    return out


# --- preview ----------------------------------------------------------------------------------------


def ground_color() -> None:
    lo, hi = GROUND
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*lo, 1.0)
            node.inputs[7].default_value = (*hi, 1.0)


def import_plants() -> dict:
    """The small Overgrowth plants from the game kit, for scale and family next to the giants."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets" / "plants" / "plants.glb"))
    keep = {}
    for o in set(bpy.data.objects) - before:
        for c in o.users_collection:
            c.objects.unlink(o)
        C.link(o, None, "Preview")
        if o.type == "MESH" and not o.name.startswith("Overgrowth_"):
            o.hide_render = True
        elif o.type == "MESH":
            o.parent = None
            o.rotation_mode = "XYZ"
            o.rotation_euler = (0, 0, 0)
            o.hide_render = True
            keep[o.name] = o
    return keep


LIGHT_BASE = {}


def light_scale(f: float, target=(0, 0, 0)) -> None:
    """Scale the preview lights' rig around `target` (the kit is up to 8 m tall; the rig is set up for ~2 m)."""
    for o in C.collection("Preview").all_objects:
        if o.type != "LIGHT":
            continue
        if o.name not in LIGHT_BASE:
            LIGHT_BASE[o.name] = (o.location.copy(), o.data.energy)
        loc, energy = LIGHT_BASE[o.name]
        o.location = Vector(target) + loc * f
        o.data.energy = energy * f * f
        aim = Vector(target) + Vector((0, 0, 1.6 * f))
        o.rotation_euler = (aim - o.location).to_track_quat("-Z", "Y").to_euler()


def show_only(visible: list) -> None:
    vis = {o.name for o in visible}
    for o in C.collection(ASSET).all_objects:
        if o.type == "MESH":
            o.hide_render = o.name not in vis
    for o in C.collection("Preview").all_objects:
        if o.type == "MESH" and (o.name.startswith(("Scatter", "Overgrowth_", "Wall"))):
            o.hide_render = o.name not in vis


def clear_scatter() -> None:
    for o in [o for o in C.collection("Preview").all_objects if o.name.startswith(("Scatter", "Wall"))]:
        bpy.data.objects.remove(o)


def copy_of(obj, loc, rnd: random.Random, scale=(0.85, 1.15), tilt=4.0, sink=0.1) -> bpy.types.Object:
    """Game-like instance: linked copy, random turn, lean, scale and sink."""
    o = obj.copy()
    o.parent = None
    C.link(o, None, "Preview")
    o.name = f"Scatter_{obj.name}"
    s = rnd.uniform(*scale)
    o.location = Vector((loc[0], loc[1], -sink * s))
    t = math.radians(tilt)
    o.rotation_euler = (rnd.uniform(-t, t), rnd.uniform(-t, t), rnd.uniform(0, TAU))
    o.scale = (s, s, s)
    return o


def lineup(names: list, step: float, extra: list = ()) -> list:
    """Place parts (and extra objects) in a row across the iso view, centered on the origin."""
    row = list(names) + list(extra)
    for i, o in enumerate(row):
        k = i - (len(row) - 1) / 2
        o.location = ROW_DIR * (k * step)
    return row


def scatter_band(objs: dict, seed: int) -> list:
    """A growth wall like the game's: a trail along ROW_DIR (13 m of open ground), the band beyond it with tall
    stalks and caps over roots and a low rock wall behind; on the camera's side only roots."""
    rnd = random.Random(seed)
    out, placed = [], []

    def free(x, y, d):
        return all((x - px) ** 2 + (y - py) ** 2 > (d + pd) ** 2 for px, py, pd in placed)

    def put(name, u, v, d, **kw):
        loc = ROW_DIR * u + FAR_DIR * v
        if not free(loc.x, loc.y, d):
            return
        placed.append((loc.x, loc.y, d))
        out.append(copy_of(objs[name], loc, rnd, **kw))

    tall = ["Growth_Stalk_a", "Growth_Stalk_b", "Growth_Cap_a", "Growth_Cap_b"]
    for _ in range(140):
        u, v = rnd.uniform(-17, 17), rnd.uniform(7.5, 13.0)
        put(rnd.choice(tall), u, v, 1.2, scale=(0.8, 1.15), tilt=6.0)
    for _ in range(160):
        u, v = rnd.uniform(-17, 17), rnd.uniform(6.6, 13.0)
        put(rnd.choice(["Growth_Root_a", "Growth_Root_b"]), u, v, 0.9, scale=(0.75, 0.95), tilt=8.0, sink=0.05)
    for _ in range(160):  # the camera's side: roots only
        u, v = rnd.uniform(-17, 17), rnd.uniform(-13.0, -6.6)
        put(rnd.choice(["Growth_Root_a", "Growth_Root_b"]), u, v, 0.9, scale=(0.75, 0.95), tilt=8.0, sink=0.05)
    rock = bpy.data.materials["PreviewRock"]
    for v0, v1, h in ((13.0, 17.0, 4.0), (17.0, 22.0, 7.0)):
        bpy.ops.mesh.primitive_cube_add(size=1)
        wall = bpy.context.active_object
        for c in wall.users_collection:
            c.objects.unlink(wall)
        C.link(wall, None, "Preview")
        wall.name = "Wall"
        wall.location = FAR_DIR * ((v0 + v1) / 2) + Vector((0, 0, h / 2))
        wall.rotation_euler = (0, 0, math.radians(45))
        wall.scale = (40.0, v1 - v0, h)
        C.assign(wall, rock)
        out.append(wall)
    return out


def scatter_grove(objs: dict, plants: dict, seed: int) -> list:
    """A fungal grove: grove stalks and caps at least 4 m apart (the game's spacing), small plants between."""
    rnd = random.Random(seed)
    out, placed = [], []
    for _ in range(400):
        x, y = rnd.uniform(-11, 11), rnd.uniform(-11, 11)
        if all((x - px) ** 2 + (y - py) ** 2 > 4.6**2 for px, py in placed) and (x - 1.5) ** 2 + (y + 1.5) ** 2 > 4:
            placed.append((x, y))
            name = "Grove_Stalk_a" if len(placed) % 2 else "Grove_Cap_a"
            out.append(copy_of(objs[name], (x, y), rnd, scale=(0.9, 1.2), tilt=5.0))
    small = [n for n in ("Overgrowth_Frond_b", "Overgrowth_Fungus_a", "Overgrowth_Frond_a") if n in plants]
    for _ in range(60):
        x, y = rnd.uniform(-11, 11), rnd.uniform(-11, 11)
        if small:
            out.append(copy_of(plants[rnd.choice(small)], (x, y), rnd, scale=(0.6, 1.3), tilt=8.0, sink=0.0))
    return out


def render_view(view: str, objs: dict, plants: dict, prefix: str, samples: int, size: int) -> list:
    fig = bpy.data.objects["PreviewFigure"]
    paths = []
    if view == "tall":
        names = ["Growth_Stalk_a", "Growth_Stalk_b", "Growth_Cap_a", "Growth_Cap_b"]
        row = lineup([objs[n] for n in names], 5.6, [fig])
        show_only(row)
        light_scale(2.6)
        for v, zoom in (("iso", 2.75), ("hero", 3.2)):
            path = OUT / f"{prefix}_tall_{v}.png"
            C.render(path, view=v, samples=samples, size=size, target=(0, 0, 3.0), zoom=zoom)
            paths.append(path)
    elif view == "small":
        names = ["Growth_Root_a", "Growth_Root_b", "Grove_Stalk_a", "Grove_Cap_a"]
        extra = [plants[n] for n in ("Overgrowth_Tube_a", "Overgrowth_Fungus_b") if n in plants]
        row = lineup([objs[n] for n in names], 4.2, [*extra, fig])
        show_only(row)
        light_scale(2.0)
        for v, zoom in (("iso", 3.5), ("hero", 3.8)):
            path = OUT / f"{prefix}_small_{v}.png"
            C.render(path, view=v, samples=samples, size=size, target=(0, 0, 1.6), zoom=zoom)
            paths.append(path)
    elif view == "band":
        copies = scatter_band(objs, 7)
        fig.location = ROW_DIR * 2.0
        show_only(copies)
        light_scale(3.2)
        for v, zoom, tgt in (("iso", 3.0, (0, 0, 1.0)), ("game", 2.0, (0, 0, 0.5))):
            path = OUT / f"{prefix}_band_{v}.png"
            C.render(path, view="iso", samples=samples, size=size, target=tgt, zoom=zoom)
            paths.append(path)
        clear_scatter()
    elif view == "grove":
        copies = scatter_grove(objs, plants, 11)
        fig.location = (1.5, -1.5, 0)
        show_only(copies)
        light_scale(2.6)
        path = OUT / f"{prefix}_grove_iso.png"
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 1.0), zoom=2.4)
        paths.append(path)
        clear_scatter()
    elif view in objs:
        obj = objs[view]
        obj.location = (0, 0, 0)
        show_only([obj])
        h = obj.dimensions.z
        w = max(obj.dimensions.x, obj.dimensions.y)
        fig.location = ROW_DIR * (w / 2 + 0.8)
        light_scale(max(1.0, h / 3.0))
        for v in ("iso", "hero"):
            zoom = (max(w, h) * 1.25 + 1.2) / (9.9 if v == "iso" else 6.3)
            path = OUT / f"{prefix}_{view}_{v}.png"
            C.render(path, view=v, samples=samples, size=size, target=(0, 0, h * 0.42), zoom=zoom)
            paths.append(path)
    else:
        raise ValueError(view)
    return paths


def main() -> None:
    C.reset(ASSET)
    objs = build()
    stats = per_object_stats(objs)
    for name, s in stats.items():
        print(f"STATS {name:16s} tris {s['tris']:5d}  size {s['size']}  zmin {s['zmin']}  foot_r {s['foot_r']}")
    print("STATS total", sum(s["tris"] for s in stats.values()))
    C.preview_scene(crystals=False, figure_location=(0, 0, 0))
    for o in list(C.collection("Preview").all_objects):  # preview pebbles would clutter the line-ups
        if o.type == "MESH" and o.name.startswith("Ico"):
            bpy.data.objects.remove(o)
    ground = bpy.data.objects["PreviewGround"]
    ground.scale = (2.5, 2.5, 1)
    ground_color()
    plants = import_plants()
    if MODE == "final":
        views = ["tall", "small", "band", "grove", *PARTS]
        paths = []
        for view in views:
            paths += render_view(view, objs, plants, "final/final", samples=48, size=768)
        C.contact_sheet(paths, OUT / "sheet.png", tile=512)
        for name, obj in objs.items():
            obj.location = bake_location(name)
            obj.hide_render = False
        for o in plants.values():
            bpy.data.objects.remove(o)
        C.save_blend(OUT / "overgrowth_procedural.blend")
    else:
        paths = []
        for view in VIEWS:
            paths += render_view(view, objs, plants, f"wip/{TAG}", samples=24, size=640)
        C.contact_sheet(paths, OUT / "wip" / f"{TAG}_sheet.png", tile=480)
        if "save" in ARGV[2:]:
            for name, obj in objs.items():
                obj.location = bake_location(name)
            C.save_blend(OUT / "overgrowth_procedural.blend")


if __name__ == "__main__":
    main()
