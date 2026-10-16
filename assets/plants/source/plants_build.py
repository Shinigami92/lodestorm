"""Biome scatter kit: plants and debris for the dust flats and the overgrowth (concepts: overgrowth_v1..v4,
dustflats_house).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/plants/source/plants_build.py wip r1            # line-ups + scatter previews
    tools/blender.sh assets/plants/source/plants_build.py wip r1 close      # plus per-variant close-ups
    tools/blender.sh assets/plants/source/plants_build.py final

Everything it writes goes to tmp/assets/plants/: "wip <tag> [close]" renders quick previews into wip/<tag>_*.png;
"final" renders the line-ups, game-distance scatter views and per-variant close-ups, puts them on a contact
sheet (sheet.png) and saves the procedural plants_procedural.blend that the bake stage turns into the game asset.

Every variant is ONE mesh object with ONE material, origin at its ground contact (bottom center), base a bit
below z = 0: the game draws each one many times through a MultiMesh (ScatterType). Stems are vertical-ish and
grow from the origin, so a sway shader can bend them by height. Per-vertex float attributes drive the
procedural materials (and bake with them):
    grad   0 at the base of a stem / blade .. 1 at its tip (color ramp: living base -> dry or pale tip)
    glow   1 on the tiny bioluminescent bulbs (emission), 0 elsewhere
    plate  1 where the cracked plate pattern shows (fungus caps)
Objects are laid out in two rows (dust, overgrowth) in the .blend; only their mesh data matters to the game.
Triangle budgets (small <= ~1k, tall <= ~2.5k) are provisional, TBD (playtest).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "plants"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import itertools

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import common as C

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
CLOSE = "close" in ARGV[2:]
ASSET = "Plants"
TAU = math.tau
UP = Vector((0, 0, 1))

DUST = ["Dust_Debris_a", "Dust_Shrub_a", "Dust_Spire_a", "Dust_Shrub_b", "Dust_Debris_b"]
OVERGROWTH = [
    "Overgrowth_Frond_b",
    "Overgrowth_Fungus_a",
    "Overgrowth_Tube_a",
    "Overgrowth_Fungus_b",
    "Overgrowth_Frond_a",
]
ROW_STEP = 2.1
ROW_DIR = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # perpendicular to the iso view: nothing hides behind a neighbor
ROW_CENTER = {"dust": Vector((2.0, -2.0, 0)), "overgrowth": Vector((-2.0, 2.0, 0))}

# Approximate linear albedo of the game's biome grounds (dust.tres / overgrowth.tres colors are sRGB).
GROUND = {
    "dust": ((0.055, 0.042, 0.03), (0.11, 0.085, 0.06)),
    "overgrowth": ((0.018, 0.019, 0.011), (0.045, 0.047, 0.026)),
}

# --- math helpers -----------------------------------------------------------------------------------


def sph(az_deg: float, elev_deg: float) -> Vector:
    a, e = math.radians(az_deg), math.radians(elev_deg)
    return Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))


def arc(
    base: Vector, direction: Vector, length: float, droop: float = 0.0, n: int = 5, curl: Vector | None = None
) -> list:
    """Points of a gently bent stem: straight along `direction`, pulled down by `droop` (negative: curls up)."""
    d = Vector(direction).normalized()
    pts = []
    for i in range(n):
        t = i / (n - 1)
        p = Vector(base) + d * length * t + Vector((0, 0, -droop * length * t * t))
        if curl is not None:
            p += Vector(curl) * length * t * t
        pts.append(p)
    return pts


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


# --- mesh builder -----------------------------------------------------------------------------------


class Plant:
    """Accumulates the parts of one variant into one bmesh (one object, one material)."""

    def __init__(self, name: str, seed: int):
        self.name = name
        self.bm = bmesh.new()
        self.l_grad = self.bm.verts.layers.float.new("grad")
        self.l_glow = self.bm.verts.layers.float.new("glow")
        self.l_plate = self.bm.verts.layers.float.new("plate")
        self.rnd = random.Random(seed)

    # primitives
    def v(self, co, grad=0.0, glow=0.0, plate=0.0):
        vert = self.bm.verts.new(co)
        vert[self.l_grad], vert[self.l_glow], vert[self.l_plate] = grad, glow, plate
        return vert

    def face(self, verts, smooth=True):
        f = self.bm.faces.new(verts)
        f.smooth = smooth
        return f

    def ring(self, c, N, B, rx, ry, seg, spin=0.0, grad=0.0, glow=0.0, plate=0.0):
        out = []
        for k in range(seg):
            a = spin + k * TAU / seg
            out.append(self.v(c + N * (math.cos(a) * rx) + B * (math.sin(a) * ry), grad, glow, plate))
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
        spin=0.0,
        glow=0.0,
        plate=0.0,
        smooth=True,
    ):
        """Tube along pts; radii per point: r or (rx along N, ry along B). tip: the last point is a spike tip.
        Returns (rings, frames) so callers can extend the end (e.g. a tube mouth)."""
        n = len(pts)
        T, N, B = frames(pts, side)
        grads = grads or [i / (n - 1) for i in range(n)]
        rings = []
        last = n - 1 if tip else n
        for i in range(last):
            r = radii[i]
            rx, ry = (r, r) if isinstance(r, (int, float)) else r
            g = glow[i] if isinstance(glow, (list, tuple)) else glow
            rings.append(self.ring(pts[i], N[i], B[i], rx, ry, seg, spin, grads[i], g, plate))
        for a, b in itertools.pairwise(rings):
            self.bridge(a, b, smooth)
        if tip:
            g = glow[-1] if isinstance(glow, (list, tuple)) else glow
            self.fan(rings[-1], self.v(pts[-1], grads[-1], g, plate), smooth)
        elif cap_end:
            self.face(rings[-1], smooth)
        if cap_start:
            self.face(list(reversed(rings[0])), smooth)
        return rings, (T, N, B)

    def lathe(self, center, profile, seg, rot: Matrix | None = None, spin=0.0, smooth=True, wobble=0.0, wfreq=3.0):
        """Surface of revolution around the local Z axis. profile: (r, z, grad, plate) bottom to top; r = 0 at
        the first / last entry closes it with a fan. Normals face outward when the solid is on the axis side."""
        rot = rot or Matrix.Identity(3)
        c = Vector(center)
        rings, apexes = [], {}
        for idx, (r, z, g, p) in enumerate(profile):
            if r <= 1e-6:
                apexes[idx] = self.v(c + rot @ Vector((0, 0, z)), g, 0.0, p)
                continue
            ring = []
            for k in range(seg):
                a = spin + k * TAU / seg
                local = Vector((math.cos(a) * r, math.sin(a) * r, z))
                if wobble:
                    local += noise.noise_vector(local * wfreq + c * 1.7) * wobble * r
                ring.append(self.v(c + rot @ local, g, 0.0, p))
            rings.append((idx, ring))
        for (_, a), (_, b) in itertools.pairwise(rings):
            self.bridge(a, b, smooth)
        if 0 in apexes and rings:
            self.fan(rings[0][1], apexes[0], smooth, reverse=True)
        if len(profile) - 1 in apexes and rings:
            self.fan(rings[-1][1], apexes[len(profile) - 1], smooth)
        return [v for _, r in rings for v in r] + list(apexes.values())

    def blob(self, center, radius, scale=(1, 1, 1), sub=2, wobble=0.25, grad=None, smooth=True, rot=None):
        """Lumpy ball (bmesh icosphere: sub 2 = 80 triangles, sub 1 = the bare icosahedron). grad None: 0 at its bottom .. 1 at its top."""
        m = Matrix.Translation(Vector(center)) @ (rot or Matrix.Identity(3)).to_4x4() @ Matrix.Diagonal((*scale, 1))
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
            f.smooth = smooth
        return verts

    def bulb(self, center, r, glow=1.0, grad=1.0):
        """Tiny bioluminescent bulb: a squashed hexagonal bipyramid (12 triangles), smooth shaded a dot."""
        c = Vector(center)
        ring = [
            self.v(c + Vector((math.cos(k * TAU / 6) * r, math.sin(k * TAU / 6) * r, 0)), grad, glow) for k in range(6)
        ]
        self.fan(ring, self.v(c + Vector((0, 0, r * 0.6)), grad, glow))
        self.fan(ring, self.v(c + Vector((0, 0, -r * 0.6)), grad, glow), reverse=True)

    def stone(self, center, size, npts=12, rot_z=0.0, tilt=(0.0, 0.0), grad=0.0, jag=0.25):
        """Jagged pebble: convex hull of jittered points on an ellipsoid, flat shaded (~2n-4 triangles)."""
        sx, sy, sz = size
        rot = Matrix.Rotation(rot_z, 3, "Z") @ Matrix.Rotation(tilt[0], 3, "X") @ Matrix.Rotation(tilt[1], 3, "Y")
        pts = []
        for i in range(npts):
            # Fibonacci sphere + jitter: well spread, all on the hull.
            z = 1 - 2 * (i + 0.5) / npts
            r = math.sqrt(max(0.0, 1 - z * z))
            a = i * 2.39996 + self.rnd.uniform(-0.3, 0.3)
            k = 1 + self.rnd.uniform(-jag, jag)
            local = Vector((math.cos(a) * r * sx * k, math.sin(a) * r * sy * k, z * sz * k))
            pts.append(self.v(Vector(center) + rot @ local, grad))
        res = bmesh.ops.convex_hull(self.bm, input=pts)
        junk = [e for e in res["geom_interior"] + res["geom_unused"] if isinstance(e, bmesh.types.BMVert)]
        if junk:
            bmesh.ops.delete(self.bm, geom=junk, context="VERTS")
        faces = [e for e in res["geom"] if isinstance(e, bmesh.types.BMFace)]
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        for f in faces:
            f.smooth = False

    def wobble(self, verts, amp, freq=4.0):
        seed = Vector((self.rnd.uniform(0, 99), self.rnd.uniform(0, 99), self.rnd.uniform(0, 99)))
        for vert in verts:
            vert.co += noise.noise_vector(vert.co * freq + seed) * amp

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
        n = self.node("ShaderNodeAttribute", attribute_type="GEOMETRY", attribute_name=name)
        return n.outputs["Fac"]

    def math(self, op, a, b=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        for sock, val in ((n.inputs[0], a), (n.inputs[1], b)):
            if val is None:
                continue
            if isinstance(val, bpy.types.NodeSocket):
                self.link(val, sock)
            else:
                sock.default_value = val
        return n.outputs[0]

    def ramp(self, src, stops):
        """stops: [(pos, value-or-rgb)]; returns the Color output (use [0] channel semantics for floats)."""
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


def mat_plant(
    name: str,
    stops: list,
    rough=(0.6, 0.85),
    ground_col=(0.09, 0.07, 0.05),
    ground_h=0.12,
    streaks: float = 0.0,
    plates: bool = False,
    pores: bool = False,
    top_dust: float = 0.0,
    glow_col=(0.25, 1.0, 0.7),
    glow_strength: float = 3.0,
    bump: float = 0.25,
    var: float = 0.25,
) -> bpy.types.Material:
    """Organic PBR: color ramp along the stem (grad), noise variation, fibrous streaks, cracked plates on
    fungus caps (plate), pores, dirt band at the ground, cavity darkening, dust on top faces (debris),
    emission only on the bulbs (glow). Non-metallic."""
    mat, nt, bsdf = C._new_material(name)
    n = NT(nt)
    col = n.ramp(n.attr("grad"), stops)
    # Brightness variation: scale by a noise-driven factor 1 -/+ var.
    bright = n.node("ShaderNodeMapRange")
    n.link(n.noise(5.0, 6.0, 0.6), bright.inputs["Value"])
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
        s = n.math("MULTIPLY", sock, k)
        height = s if height is None else n.math("ADD", height, s)

    if streaks > 0:
        # Fibers along the (mostly vertical) stems: noise stretched along Z.
        fib = n.noise(18.0, 3.0, 0.5, vec_scale=(1.0, 1.0, 0.12))
        fib_mask = n.ramp(fib, [(0.35, 0.0), (0.65, 1.0)])
        col = n.mix(n.math("MULTIPLY", fib_mask, 0.45 * streaks), col, (0.01, 0.009, 0.007))
        add_height(fib, 0.5 * streaks)
    if plates:
        # Cracked plates on the caps (concept: tiled, cracked fungus tops with moss in the cracks).
        plate_m = n.attr("plate")
        cells = n.voronoi(7.0)
        edges = n.voronoi(7.0, "DISTANCE_TO_EDGE")
        crack = n.ramp(edges.outputs["Distance"], [(0.0, 1.0), (0.06, 0.0)])
        crack_m = n.math("MULTIPLY", crack, plate_m)
        cell_rand = n.ramp(cells.outputs["Color"], [(0.0, 0.0), (1.0, 1.0)])
        tint = n.mix(n.math("MULTIPLY", cell_rand, plate_m), col, (0.075, 0.08, 0.045))  # mossy olive plates
        col = n.mix(n.math("MULTIPLY", crack_m, 0.9), tint, (0.006, 0.007, 0.004))
        add_height(n.math("MULTIPLY", crack_m, -1.0), 0.8)
        lumps = n.noise(14.0, 3.0, 0.5)
        add_height(n.math("MULTIPLY", lumps, plate_m), 0.3)
    if pores:
        dots = n.voronoi(16.0)
        pore = n.ramp(dots.outputs["Distance"], [(0.08, 1.0), (0.22, 0.0)])
        col = n.mix(n.math("MULTIPLY", pore, 0.7), col, (0.008, 0.009, 0.006))
        add_height(n.math("MULTIPLY", pore, -1.0), 0.5)
    # Cavities (between blades, under caps) darker.
    ao = n.node("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.2
    cav = n.ramp(ao.outputs["AO"], [(0.25, 1.0), (0.9, 0.0)])
    col = n.mix(n.math("MULTIPLY", cav, 0.75), col, (0.006, 0.006, 0.005))
    # Dirt band where it meets the ground.
    sep = n.node("ShaderNodeSeparateXYZ")
    n.link(n.coords(), sep.inputs["Vector"])
    band = n.node("ShaderNodeMapRange")
    n.link(sep.outputs["Z"], band.inputs["Value"])
    band.inputs["From Min"].default_value = 0.0
    band.inputs["From Max"].default_value = ground_h
    band.inputs["To Min"].default_value = 0.85
    band.inputs["To Max"].default_value = 0.0
    dirt_noise = n.noise(9.0, 4.0, 0.6)
    dirt = n.math("MULTIPLY", band.outputs["Result"], n.ramp(dirt_noise, [(0.3, 0.55), (0.6, 1.0)]))
    col = n.mix(dirt, col, ground_col)
    if top_dust > 0:
        geo = n.node("ShaderNodeNewGeometry")
        nz = n.node("ShaderNodeSeparateXYZ")
        n.link(geo.outputs["Normal"], nz.inputs["Vector"])
        up_m = n.ramp(nz.outputs["Z"], [(0.45, 0.0), (0.9, 1.0)])
        speck = n.ramp(n.noise(11.0, 5.0, 0.65), [(0.35, 0.2), (0.6, 1.0)])
        col = n.mix(n.math("MULTIPLY", n.math("MULTIPLY", up_m, speck), top_dust), col, ground_col)
    n.link(col, bsdf.inputs["Base Color"])
    # Roughness: noise between the two values, dirt is matte.
    rough_s = n.mixf(n.noise(7.0, 4.0, 0.5), rough[0], rough[1])
    rough_s = n.mixf(dirt, rough_s, 0.95)
    n.link(rough_s, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    # Bulbs glow.
    bsdf.inputs["Emission Color"].default_value = (*glow_col, 1.0)
    n.link(n.math("MULTIPLY", n.attr("glow"), glow_strength), bsdf.inputs["Emission Strength"])
    # Bump: fine organic noise plus the pattern heights.
    add_height(n.noise(40.0, 4.0, 0.6), 0.25)
    bmp = n.node("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = bump
    bmp.inputs["Distance"].default_value = 0.004
    n.link(height, bmp.inputs["Height"])
    n.link(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


DUST_GROUND = (0.085, 0.064, 0.044)
MUD = (0.014, 0.014, 0.009)
GLOW_TEAL = (0.2, 1.0, 0.72)
GLOW_AMBER = (1.0, 0.5, 0.16)


def make_materials() -> dict:
    M = {}
    # Dust flats: dry, dark olive-brown bodies with pale bleached tips; dark against the sand like the concept.
    M["Dust_Shrub_a"] = mat_plant(
        "Plant_Dust_Shrub_a",
        [
            (0.0, (0.02, 0.024, 0.008)),
            (0.45, (0.048, 0.052, 0.02)),
            (0.8, (0.1, 0.088, 0.045)),
            (1.0, (0.18, 0.145, 0.085)),
        ],
        rough=(0.6, 0.85),
        ground_col=DUST_GROUND,
        streaks=0.7,
    )
    M["Dust_Shrub_b"] = mat_plant(
        "Plant_Dust_Shrub_b",
        [
            (0.0, (0.02, 0.014, 0.008)),
            (0.35, (0.06, 0.045, 0.026)),
            (0.75, (0.13, 0.105, 0.065)),
            (1.0, (0.22, 0.185, 0.125)),
        ],
        rough=(0.65, 0.9),
        ground_col=DUST_GROUND,
        streaks=0.4,
    )
    M["Dust_Spire_a"] = mat_plant(
        "Plant_Dust_Spire_a",
        [
            (0.0, (0.03, 0.024, 0.013)),
            (0.4, (0.062, 0.048, 0.028)),
            (0.8, (0.1, 0.08, 0.05)),
            (1.0, (0.15, 0.125, 0.085)),
        ],
        rough=(0.6, 0.85),
        ground_col=DUST_GROUND,
        ground_h=0.2,
        streaks=1.0,
        glow_col=GLOW_AMBER,
        glow_strength=3.0,
    )
    M["Dust_Debris_a"] = mat_plant(
        "Plant_Dust_Debris_a",
        [(0.0, (0.028, 0.026, 0.024)), (1.0, (0.05, 0.045, 0.04))],
        rough=(0.75, 0.95),
        ground_col=DUST_GROUND,
        ground_h=0.05,
        top_dust=0.85,
        bump=0.4,
        var=0.35,
    )
    M["Dust_Debris_b"] = mat_plant(
        "Plant_Dust_Debris_b",
        [(0.0, (0.13, 0.115, 0.09)), (1.0, (0.2, 0.18, 0.145))],
        rough=(0.55, 0.8),
        ground_col=DUST_GROUND,
        ground_h=0.06,
        streaks=0.5,
        top_dust=0.6,
        var=0.3,
    )
    # Overgrowth: fleshy, wet-looking, dark olive / teal, with tiny dim teal bulbs.
    M["Overgrowth_Fungus_a"] = mat_plant(
        "Plant_Overgrowth_Fungus_a",
        [(0.0, (0.01, 0.013, 0.006)), (0.55, (0.032, 0.045, 0.016)), (1.0, (0.065, 0.078, 0.036))],
        rough=(0.4, 0.7),
        ground_col=MUD,
        ground_h=0.15,
        pores=True,
        glow_col=GLOW_TEAL,
        glow_strength=3.0,
    )
    M["Overgrowth_Fungus_b"] = mat_plant(
        "Plant_Overgrowth_Fungus_b",
        [
            (0.0, (0.025, 0.024, 0.014)),
            (0.45, (0.08, 0.072, 0.05)),
            (0.55, (0.02, 0.022, 0.014)),
            (0.75, (0.055, 0.048, 0.032)),
            (1.0, (0.09, 0.08, 0.055)),
        ],
        rough=(0.35, 0.65),
        ground_col=MUD,
        ground_h=0.15,
        plates=True,
        streaks=0.3,
        glow_col=GLOW_TEAL,
        glow_strength=3.0,
    )
    M["Overgrowth_Tube_a"] = mat_plant(
        "Plant_Overgrowth_Tube_a",
        [
            (0.0, (0.01, 0.02, 0.016)),
            (0.5, (0.02, 0.048, 0.04)),
            (0.88, (0.05, 0.075, 0.058)),
            (1.0, (0.085, 0.085, 0.06)),
        ],
        rough=(0.35, 0.65),
        ground_col=MUD,
        ground_h=0.2,
        streaks=0.5,
        glow_col=GLOW_TEAL,
        glow_strength=3.0,
    )
    M["Overgrowth_Frond_a"] = mat_plant(
        "Plant_Overgrowth_Frond_a",
        [(0.0, (0.012, 0.018, 0.008)), (0.4, (0.032, 0.052, 0.018)), (1.0, (0.045, 0.075, 0.05))],
        rough=(0.4, 0.7),
        ground_col=MUD,
        streaks=0.6,
        glow_col=GLOW_TEAL,
        glow_strength=3.0,
    )
    M["Overgrowth_Frond_b"] = mat_plant(
        "Plant_Overgrowth_Frond_b",
        [(0.0, (0.01, 0.015, 0.006)), (0.5, (0.038, 0.052, 0.018)), (1.0, (0.095, 0.09, 0.045))],
        rough=(0.45, 0.75),
        ground_col=MUD,
        streaks=0.5,
        glow_col=GLOW_TEAL,
        glow_strength=2.5,
    )
    return M


# --- dust flats -------------------------------------------------------------------------------------


def blade(p: Plant, base, direction, length, width, thick, droop, n=4, grad0=0.0, taper=(1.0, 0.85, 0.5)):
    """Keeled, pointed blade (triangle section, keel down): yucca leaves, dry spikes, grass straps."""
    d = Vector(direction).normalized()
    side = UP.cross(d)
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    pts = arc(base, d, length, droop, n)
    rx, ry = width / 2 / math.cos(math.radians(30)), thick / 1.5
    radii = [(rx * t, ry * t) for t in taper] + [0.0]
    radii = radii[: n - 1] + [0.0]
    grads = [lerp(grad0, 1.0, i / (n - 1)) for i in range(n)]
    p.sweep(pts, radii, 3, side=side, grads=grads, tip=True, spin=-math.pi / 2)


def build_dust_shrub_a(root, M):
    """Dry yucca-like rosette: ~45 keeled blades, long and upright in the middle, short and drooping outside."""
    p = Plant("Dust_Shrub_a", 11)
    p.lathe(
        (0, 0, 0),
        [(0.0, -0.08, 0.0, 0), (0.15, -0.08, 0.0, 0), (0.16, 0.05, 0.05, 0), (0.1, 0.14, 0.15, 0), (0.0, 0.17, 0.2, 0)],
        7,
        wobble=0.15,
    )
    count = 44
    for i in range(count):
        f = i / (count - 1)
        elev = lerp(84, 10, f**0.85) + p.rnd.uniform(-7, 7)
        az = i * 137.5 + p.rnd.uniform(-12, 12)
        length = lerp(1.05, 0.55, f) * p.rnd.uniform(0.85, 1.1)
        base = sph(az, 0) * (0.03 + 0.1 * f) + Vector((0, 0, lerp(0.12, 0.03, f)))
        droop = lerp(0.05, 0.38, f) * p.rnd.uniform(0.7, 1.3)
        blade(p, base, sph(az, elev), length, lerp(0.05, 0.075, f), 0.024, droop, n=4)
    for i in range(4):  # dead blades lying on the ground
        az = p.rnd.uniform(0, 360)
        base = sph(az, 0) * 0.18 + Vector((0, 0, 0.01))
        blade(p, base, sph(az + p.rnd.uniform(-20, 20), -2), p.rnd.uniform(0.45, 0.7), 0.06, 0.02, 0.0, n=4, grad0=0.6)
    return p.finish(root, M["Dust_Shrub_a"])


def build_dust_shrub_b(root, M):
    """Dry bristle tuft (the dark spiky clumps of the concept): stiff needles radiating from a low dome."""
    p = Plant("Dust_Shrub_b", 23)
    p.lathe(
        (0, 0, 0),
        [(0.0, -0.08, 0.0, 0), (0.24, -0.08, 0.0, 0), (0.26, 0.06, 0.1, 0), (0.18, 0.2, 0.2, 0), (0.0, 0.26, 0.25, 0)],
        8,
        wobble=0.2,
    )
    count = 84
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        # Fibonacci points on the upper part of a sphere: even coverage, nothing pointing into the ground.
        z = lerp(0.98, -0.12, (i + 0.5) / count)
        r = math.sqrt(1 - z * z)
        a = i * golden
        d = Vector((math.cos(a) * r, math.sin(a) * r, z))
        d += Vector((p.rnd.uniform(-0.15, 0.15), p.rnd.uniform(-0.15, 0.15), p.rnd.uniform(-0.05, 0.15)))
        d.normalize()
        base = Vector((d.x * 0.17, d.y * 0.17, 0.08 + d.z * 0.12))
        length = p.rnd.uniform(0.45, 0.72) * lerp(1.0, 0.75, max(0.0, -z))
        blade(p, base, d, length, 0.034, 0.024, p.rnd.uniform(0.0, 0.12), n=3, taper=(1.0, 0.6))
    return p.finish(root, M["Dust_Shrub_b"])


def stalk(
    p: Plant,
    base,
    height,
    r0,
    r1,
    seg,
    lean: Vector,
    rings=12,
    nodes=3,
    tip=True,
    spikes=0,
    spike_len=(0.6, 0.25),
    grad_top=1.0,
    glands=0,
):
    """Segmented dry stalk with knotted nodes and upward-curving side spikes."""
    pts, radii = [], []
    for i in range(rings):
        t = i / (rings - 1)
        sway = Vector((math.sin(t * 2.6) * 0.06, math.cos(t * 2.1) * 0.04, 0))
        pts.append(Vector(base) + Vector((0, 0, -0.12 + (height + 0.12) * t)) + lean * t * t + sway * t)
        r = lerp(r0, r1, t**0.8)
        if nodes and i % nodes == 0 and 0 < i < rings - 1:
            r *= 1.22
        radii.append(r)
    if tip:
        radii[-1] = 0.0
    grads = [lerp(0.0, grad_top, i / (rings - 1)) for i in range(rings)]
    p.sweep(pts, radii, seg, side=Vector((1, 0, 0)), grads=grads, tip=tip, cap_end=not tip)
    for i in range(spikes):
        f = (i + 0.5) / spikes
        h = lerp(0.22, 0.9, f)
        idx = h * (rings - 1)
        a, b = pts[int(idx)], pts[min(int(idx) + 1, rings - 1)]
        c = a.lerp(b, idx - int(idx))
        az = i * 137.5 + p.rnd.uniform(-15, 15)
        out = sph(az, 0)
        r = lerp(r0, r1, h**0.8)
        length = lerp(spike_len[0], spike_len[1], f) * p.rnd.uniform(0.8, 1.15)
        d = sph(az, p.rnd.uniform(5, 30))
        spts = arc(c + out * r * 0.6, d, length, droop=-p.rnd.uniform(0.35, 0.6), n=4)
        rr = lerp(0.05, 0.022, f) * (r0 / 0.16) ** 0.5
        p.sweep(spts, [rr, rr * 0.7, rr * 0.4, 0.0], 3, grads=[lerp(0.3, 0.6, f), 0.7, 0.85, 1.0], tip=True)
    tips = []
    for i in range(glands):
        h = lerp(0.84, 0.97, i / max(1, glands - 1))
        idx = h * (rings - 1)
        c = pts[int(idx)].lerp(pts[min(int(idx) + 1, rings - 1)], idx - int(idx))
        az = i * 151 + 20
        r = lerp(r0, r1, h**0.8)
        tips.append((c, az, r))
    return pts, tips


def build_dust_spire_a(root, M):
    """Tall dry stalk plant (replaces the greybox "Spire plant"): a 3.5 m knotted spike with curved side
    thorns, a shorter second stalk and a broken stub, standing in a rosette of dead drooping blades; a few
    dried pods near the top carry tiny dim amber glands."""
    p = Plant("Dust_Spire_a", 37)
    _, tips = stalk(
        p,
        (0, 0, 0),
        3.5,
        0.16,
        0.03,
        7,
        Vector((0.08, 0.05, 0)),
        rings=16,
        nodes=3,
        spikes=24,
        spike_len=(0.85, 0.3),
        glands=4,
    )
    stalk(
        p,
        (0.26, 0.13, 0),
        2.25,
        0.11,
        0.022,
        6,
        Vector((0.3, 0.15, 0)),
        rings=11,
        nodes=3,
        spikes=11,
        spike_len=(0.55, 0.22),
    )
    stalk(p, (-0.18, 0.22, 0), 1.0, 0.1, 0.08, 6, Vector((-0.08, 0.06, 0)), rings=5, nodes=2, tip=False, grad_top=0.85)
    for c, az, r in tips:  # seed pods hanging from the main stalk, a gland at each pod's tip
        out = sph(az, 0)
        top = c + out * r
        bottom = top + out * 0.06 + Vector((0, 0, -0.17))
        p.sweep(
            [top, top.lerp(bottom, 0.45) + out * 0.03, bottom], [0.018, 0.034, 0.0], 4, grads=[0.8, 0.9, 1.0], tip=True
        )
        p.bulb(bottom + Vector((0, 0, -0.012)), 0.02)
    for i in range(11):
        az = i * 137.5 + p.rnd.uniform(-15, 15)
        base = sph(az, 0) * 0.12 + Vector((0, 0, 0.06))
        blade(
            p,
            base,
            sph(az, p.rnd.uniform(25, 50)),
            p.rnd.uniform(0.75, 1.05),
            0.085,
            0.026,
            p.rnd.uniform(0.55, 0.85),
            n=5,
            taper=(1.0, 0.95, 0.75, 0.4),
            grad0=0.15,
        )
    return p.finish(root, M["Dust_Spire_a"])


def build_dust_debris_a(root, M):
    """Pebble patch: one sunken slab, a few medium stones and grit, flat (max ~0.17 m), jagged."""
    p = Plant("Dust_Debris_a", 41)
    p.stone((0.05, 0.02, 0.0), (0.3, 0.22, 0.09), npts=18, rot_z=0.4, tilt=(0.08, -0.05))
    for i in range(4):
        a = i * 1.7 + 0.5
        r = p.rnd.uniform(0.28, 0.45)
        s = p.rnd.uniform(0.09, 0.15)
        p.stone(
            (math.cos(a) * r, math.sin(a) * r, s * 0.15),
            (s, s * p.rnd.uniform(0.6, 0.9), s * 0.6),
            npts=14,
            rot_z=p.rnd.uniform(0, 3),
            tilt=(p.rnd.uniform(-0.3, 0.3), p.rnd.uniform(-0.3, 0.3)),
        )
    for i in range(12):
        a = p.rnd.uniform(0, TAU)
        r = p.rnd.uniform(0.15, 0.62) ** 0.9
        s = p.rnd.uniform(0.03, 0.07)
        p.stone(
            (math.cos(a) * r, math.sin(a) * r, s * 0.2),
            (s, s * p.rnd.uniform(0.6, 1.0), s * 0.55),
            npts=8,
            rot_z=p.rnd.uniform(0, 3),
            tilt=(p.rnd.uniform(-0.4, 0.4), p.rnd.uniform(-0.4, 0.4)),
        )
    for i in range(3):  # thin flaked shards
        a = p.rnd.uniform(0, TAU)
        r = p.rnd.uniform(0.25, 0.5)
        p.stone((math.cos(a) * r, math.sin(a) * r, 0.0), (0.12, 0.07, 0.025), npts=8, rot_z=a, tilt=(0.25, 0.1))
    return p.finish(root, M["Dust_Debris_a"])


def build_dust_debris_b(root, M):
    """Bleached bones of some large animal, half buried: rib arcs, a vertebra row, a long bone, fragments."""
    p = Plant("Dust_Debris_b", 53)
    spine_y = -0.28
    for i in range(5):  # vertebrae with a spinous process
        x = -0.36 + i * 0.17
        c = Vector((x, spine_y + math.sin(i * 0.8) * 0.03, 0.02))
        p.stone(c, (0.065, 0.075, 0.06), npts=12, rot_z=0.1 * i, grad=0.4, jag=0.15)
        p.sweep(
            [c + Vector((0, 0, 0.03)), c + Vector((-0.02, -0.03, 0.12))],
            [(0.018, 0.03), 0.0],
            4,
            grads=[0.5, 1.0],
            tip=True,
        )
    for i in range(4):  # ribs: arcs out of the spine, over, and back into the ground
        x = -0.32 + i * 0.19
        span = lerp(0.62, 0.48, abs(i - 1.5) / 1.5)
        hgt = lerp(0.3, 0.22, abs(i - 1.5) / 1.5)
        pts = []
        for k in range(8):
            t = k / 7
            ang = t * math.pi * 0.92
            y = spine_y + (1 - math.cos(ang)) * 0.5 * span
            z = math.sin(ang) * hgt - 0.03
            pts.append(Vector((x + t * 0.08 + math.sin(t * 3 + i) * 0.02, y, z)))
        radii = [(0.03 * lerp(1.0, 0.6, t), 0.02 * lerp(1.0, 0.6, t)) for t in (k / 7 for k in range(8))]
        p.sweep(pts, radii, 5, side=Vector((1, 0, 0)), grads=[0.3 + 0.7 * k / 7 for k in range(8)], cap_end=True)
    # Long bone lying across the front, ends knobbed.
    a, b = Vector((-0.45, 0.42, 0.015)), Vector((0.32, 0.18, 0.03))
    pts = [a.lerp(b, t) + Vector((0, 0, math.sin(t * math.pi) * 0.015)) for t in (0, 0.15, 0.35, 0.65, 0.85, 1.0)]
    p.sweep(
        pts,
        [0.05, 0.034, 0.028, 0.028, 0.032, 0.045],
        6,
        side=UP,
        grads=[0.5, 0.7, 0.8, 0.8, 0.7, 0.6],
        cap_end=True,
        cap_start=True,
    )
    p.stone(a + Vector((-0.02, 0.0, 0.0)), (0.07, 0.06, 0.05), npts=10, grad=0.5, jag=0.12)
    p.stone(b + Vector((0.03, -0.01, 0.0)), (0.06, 0.07, 0.045), npts=10, grad=0.5, jag=0.12)
    for i in range(4):  # fragments
        ang = p.rnd.uniform(0, TAU)
        r = p.rnd.uniform(0.35, 0.6)
        p.stone((math.cos(ang) * r, math.sin(ang) * r, 0.0), (0.06, 0.025, 0.02), npts=8, rot_z=ang, grad=0.7)
    return p.finish(root, M["Dust_Debris_b"])


# --- overgrowth -------------------------------------------------------------------------------------


def build_overgrowth_fungus_a(root, M):
    """Puffball cluster (replaces the greybox "Puffball bush"): lumpy fleshy balls piled into a dome,
    a few pinhead bulbs glowing dimly between them."""
    p = Plant("Overgrowth_Fungus_a", 61)
    balls = [((0.0, 0.0, 0.34), 0.38)]
    for i in range(6):
        a = i * TAU / 6 + 0.3
        balls.append(((math.cos(a) * 0.46, math.sin(a) * 0.46, 0.14 + 0.04 * (i % 2)), p.rnd.uniform(0.21, 0.29)))
    for i in range(3):
        a = i * TAU / 3 + 1.0
        balls.append(((math.cos(a) * 0.2, math.sin(a) * 0.2, 0.68 + 0.06 * i), p.rnd.uniform(0.17, 0.23)))
    for i in range(1):
        a = i * 2.6 + 2.0
        balls.append(((math.cos(a) * 0.76, math.sin(a) * 0.76, 0.03), p.rnd.uniform(0.1, 0.13)))
    for c, r in balls:
        p.blob(c, r, scale=(1, 1, 0.88), wobble=0.22)
    for i in range(5):  # bulbs sit in the gaps on the upper half
        a = i * 1.3 + 0.4
        c, r = balls[1 + (i % 6)]
        top = Vector(c) + Vector((0, 0, r * 0.85)) + sph(math.degrees(a), 0) * 0.08
        p.bulb(top, 0.022)
    return p.finish(root, M["Overgrowth_Fungus_a"])


def mushroom(p: Plant, base, height, cap_r, lean_dir: Vector, lean: float, seg: int, bulbs: int):
    """Stalk with a flared, rooted foot and a thick domed cap with cracked plates (plate = 1 on top)."""
    base = Vector(base)
    stalk_r = cap_r * 0.24
    lean_v = Vector(lean_dir).normalized() * lean
    n = 6
    pts = [
        base + Vector((0, 0, -0.08 + (height + 0.08) * (i / (n - 1)))) + lean_v * (i / (n - 1)) ** 2 for i in range(n)
    ]
    radii = [stalk_r * 1.9, stalk_r * 1.25, stalk_r, stalk_r * 0.92, stalk_r * 0.9, stalk_r * 1.05]
    p.sweep(pts, radii, max(6, seg - 4), side=Vector((1, 0, 0)), grads=[0.0, 0.15, 0.3, 0.38, 0.44, 0.48])
    for k in range(3):  # buttress roots
        az = k * 120 + p.rnd.uniform(0, 60)
        o = sph(az, 0)
        r0 = base + o * stalk_r * 1.2 + Vector((0, 0, 0.12 * cap_r / 0.5))
        p.sweep(
            [r0, r0 + o * stalk_r * 1.6 + Vector((0, 0, -0.08)), r0 + o * stalk_r * 2.6 + Vector((0, 0, -0.2))],
            [stalk_r * 0.5, stalk_r * 0.3, 0.0],
            3,
            grads=[0.1, 0.05, 0.0],
            tip=True,
        )
    top = pts[-1]
    tilt_axis = UP.cross(Vector(lean_dir).normalized())
    rot = Matrix.Rotation(lean * 0.6, 3, tilt_axis) if tilt_axis.length > 1e-3 else Matrix.Identity(3)
    t = cap_r * 0.6  # cap thickness
    prof = [
        (stalk_r * 0.85, -0.02, 0.5, 0.0),
        (cap_r * 0.55, -0.05 * cap_r, 0.56, 0.0),
        (cap_r * 0.92, -0.1 * cap_r, 0.6, 0.0),
        (cap_r * 1.02, -0.04 * cap_r, 0.7, 0.4),
        (cap_r * 1.0, t * 0.22, 0.85, 1.0),
        (cap_r * 0.86, t * 0.62, 0.92, 1.0),
        (cap_r * 0.58, t * 0.93, 0.97, 1.0),
        (cap_r * 0.26, t * 1.06, 1.0, 1.0),
        (0.0, t * 1.09, 1.0, 1.0),
    ]
    p.lathe(top, prof, seg, rot=rot, spin=p.rnd.uniform(0, 1), wobble=0.07, wfreq=2.5)
    for k in range(bulbs):
        a = k * TAU / bulbs + p.rnd.uniform(-0.3, 0.3)
        local = Vector((math.cos(a) * cap_r * 0.8, math.sin(a) * cap_r * 0.8, -0.09 * cap_r - 0.012))
        p.bulb(top + rot @ local, max(0.014, cap_r * 0.045))


def build_overgrowth_fungus_b(root, M):
    """Cluster of plated mushroom caps, 0.35-1.75 m (small cousins of the concept's funnel trees)."""
    p = Plant("Overgrowth_Fungus_b", 71)
    mushroom(p, (0.0, 0.0, 0), 1.75, 0.55, Vector((-0.4, 0.6, 0)), 0.12, 12, 5)
    mushroom(p, (0.42, 0.22, 0), 1.05, 0.36, Vector((1, 0.4, 0)), 0.18, 10, 3)
    mushroom(p, (-0.3, -0.3, 0), 0.62, 0.25, Vector((-1, -0.6, 0)), 0.14, 9, 0)
    mushroom(p, (0.22, -0.42, 0), 0.36, 0.16, Vector((0.6, -1, 0)), 0.1, 8, 0)
    return p.finish(root, M["Overgrowth_Fungus_b"])


def tube(p: Plant, base, height, r, lean_dir: Vector, lean: float, seg: int):
    """Fleshy ribbed tube with an open, lipped mouth; its throat glows dimly deep inside."""
    base = Vector(base)
    lean_v = Vector(lean_dir).normalized() * lean
    n = max(9, int(height * 4.5) | 1)
    side = Vector(lean_dir).normalized().cross(UP)
    wig = p.rnd.uniform(0, TAU)
    pts, radii = [], []
    for i in range(n):
        t = i / (n - 1)
        bend = side * math.sin(t * 3.0 + wig) * 0.04 * height
        pts.append(base + Vector((0, 0, -0.1 + (height + 0.1) * t)) + lean_v * t * t + bend * t)
        rr = r * (1.7 - 0.7 * min(1.0, t * 3.5))  # flared foot
        rr *= 1.12 if i % 2 else 0.9  # fleshy ribs
        rr *= 1.0 + 0.25 * math.exp(-(((t - 0.6) / 0.18) ** 2))  # belly below the neck
        radii.append(rr * lerp(1.0, 0.8, t))
    rings, (T, N, B) = p.sweep(pts, radii, seg, side=Vector((1, 0, 0)), grads=[0.85 * i / (n - 1) for i in range(n)])
    top, t_, n_, b_ = pts[-1], T[-1], N[-1], B[-1]
    rt = radii[-1]
    lip = p.ring(top + t_ * 0.05, n_, b_, rt * 1.45, rt * 1.4, seg, grad=0.95)
    rim = p.ring(top + t_ * 0.045, n_, b_, rt * 0.95, rt * 0.95, seg, grad=1.0)
    throat = p.ring(top - t_ * 0.18, n_, b_, rt * 0.72, rt * 0.72, seg, grad=0.9, glow=0.35)
    p.bridge(rings[-1], lip)
    p.bridge(lip, rim)
    p.bridge(rim, throat)
    p.fan(throat, p.v(top - t_ * 0.26, 0.9, 1.0))


def build_overgrowth_tube_a(root, M):
    """Cluster of fleshy tubes, 0.6-2.6 m, rising from a lumpy root mass."""
    p = Plant("Overgrowth_Tube_a", 83)
    specs = [
        ((0.0, 0.0), 2.6, 0.17, (-0.3, 0.4), 0.18, 9),
        ((0.3, 0.14), 2.05, 0.15, (1.0, 0.3), 0.32, 9),
        ((-0.24, 0.26), 1.65, 0.14, (-1.0, 0.6), 0.3, 8),
        ((0.1, -0.32), 1.25, 0.13, (0.3, -1.0), 0.28, 8),
        ((-0.34, -0.14), 0.85, 0.11, (-1.0, -0.5), 0.2, 7),
        ((0.42, -0.24), 0.55, 0.09, (1.0, -0.6), 0.14, 7),
    ]
    for (x, y), h, r, d, lean, seg in specs:
        tube(p, (x, y, 0), h, r, Vector((*d, 0)), lean, seg)
    for c, s in (
        ((0.05, 0.05, 0.0), (0.42, 0.36, 0.18)),
        ((0.3, -0.25, -0.02), (0.22, 0.2, 0.1)),
        ((-0.25, 0.1, -0.02), (0.25, 0.28, 0.12)),
    ):
        p.blob(c, 1.0, scale=s, wobble=0.2, grad=0.05)
    return p.finish(root, M["Overgrowth_Tube_a"])


def frond(p: Plant, base, direction, length, width, thick, droop, n=7):
    """Broad fleshy frond: diamond section (closed, no alpha), narrow at the base, widest past the middle."""
    d = Vector(direction).normalized()
    side = UP.cross(d)
    pts = arc(base, d, length, droop, n)
    prof = [0.15, 0.55, 0.85, 1.0, 0.9, 0.55, 0.0]
    radii = [(width / 2 * w, thick / 2 * (0.4 + 0.6 * w)) for w in prof[: n - 1]] + [0.0]
    p.sweep(pts, radii, 4, side=side, grads=[i / (n - 1) for i in range(n)], tip=True)


def fiddlehead(p: Plant, base, height, curl_dir: Vector, rc: float, seg=5):
    """Young frond: rises straight, then curls over into a spiral with a dim bulb in its heart."""
    d = Vector(curl_dir).normalized()
    top = Vector(base) + Vector((0, 0, height))
    pts = [Vector(base) + Vector((0, 0, -0.05 + (height + 0.05) * t)) for t in (0.0, 0.35, 0.7)]
    center = top + d * rc
    steps = 7
    for k in range(steps + 1):
        th = k / steps * 1.55 * math.pi
        rr = rc * lerp(1.0, 0.35, k / steps)
        pts.append(center + (-d * math.cos(th) + UP * math.sin(th)) * rr)
    n = len(pts)
    radii = [lerp(0.032, 0.012, i / (n - 1)) for i in range(n)]
    p.sweep(pts, radii, seg, side=d.cross(UP), grads=[lerp(0.1, 1.0, i / (n - 1)) for i in range(n)], cap_end=True)
    p.bulb(center + Vector((0, 0, 0.005)), 0.026)


def build_overgrowth_frond_a(root, M):
    """Low frond cluster: a dozen broad arching fronds around two curled young ones."""
    p = Plant("Overgrowth_Frond_a", 97)
    p.lathe(
        (0, 0, 0),
        [(0.0, -0.06, 0.0, 0), (0.12, -0.06, 0.0, 0), (0.11, 0.06, 0.05, 0), (0.0, 0.1, 0.1, 0)],
        6,
        wobble=0.2,
    )
    for i in range(13):
        f = i / 12
        az = i * 137.5 + p.rnd.uniform(-10, 10)
        elev = lerp(72, 42, f) + p.rnd.uniform(-5, 5)  # inner fronds upright, outer ones arch out
        base = sph(az, 0) * 0.05 + Vector((0, 0, 0.03))
        frond(
            p,
            base,
            sph(az, elev),
            lerp(0.85, 1.1, f) * p.rnd.uniform(0.9, 1.1),
            p.rnd.uniform(0.2, 0.26),
            0.016,
            lerp(0.35, 0.7, f) * p.rnd.uniform(0.85, 1.15),
        )
    fiddlehead(p, (0.03, 0.02, 0), 0.7, Vector((1, -0.6, 0)), 0.09)
    return p.finish(root, M["Overgrowth_Frond_a"])


def build_overgrowth_frond_b(root, M):
    """Strap-leaf tuft (replaces the greybox "Grass tuft"): fleshy narrow blades and a few thin stalks
    carrying dim bulbs."""
    p = Plant("Overgrowth_Frond_b", 103)
    for i in range(24):
        az = i * 137.5 + p.rnd.uniform(-12, 12)
        elev = p.rnd.uniform(52, 86)
        base = sph(az, 0) * p.rnd.uniform(0.02, 0.09) + Vector((0, 0, -0.02))
        blade(
            p,
            base,
            sph(az, elev),
            p.rnd.uniform(0.45, 0.8),
            0.045,
            0.016,
            p.rnd.uniform(0.2, 0.5),
            n=5,
            taper=(1.0, 1.0, 0.8, 0.45),
        )
    for i in range(3):
        az = i * 120 + p.rnd.uniform(-25, 25)
        h = p.rnd.uniform(0.7, 0.95)
        base = sph(az, 0) * 0.04
        top = base + sph(az, 84) * h
        mid = base.lerp(top, 0.5) + sph(az, 0) * 0.03
        p.sweep(
            [base + Vector((0, 0, -0.03)), mid, top], [0.011, 0.008, 0.006], 3, grads=[0.2, 0.6, 0.95], cap_end=True
        )
        p.bulb(top + Vector((0, 0, 0.018)), 0.024)
    return p.finish(root, M["Overgrowth_Frond_b"])


BUILDERS = {
    "Dust_Shrub_a": build_dust_shrub_a,
    "Dust_Shrub_b": build_dust_shrub_b,
    "Dust_Spire_a": build_dust_spire_a,
    "Dust_Debris_a": build_dust_debris_a,
    "Dust_Debris_b": build_dust_debris_b,
    "Overgrowth_Fungus_a": build_overgrowth_fungus_a,
    "Overgrowth_Fungus_b": build_overgrowth_fungus_b,
    "Overgrowth_Tube_a": build_overgrowth_tube_a,
    "Overgrowth_Frond_a": build_overgrowth_frond_a,
    "Overgrowth_Frond_b": build_overgrowth_frond_b,
}


# --- build + report ---------------------------------------------------------------------------------


def row_location(name: str) -> Vector:
    group, names = ("dust", DUST) if name in DUST else ("overgrowth", OVERGROWTH)
    k = names.index(name) - (len(names) - 1) / 2
    return ROW_CENTER[group] + ROW_DIR * (k * ROW_STEP)


def build() -> dict:
    root = C.asset_root(ASSET)
    M = make_materials()
    objs = {}
    for name, fn in BUILDERS.items():
        obj = fn(root, M)
        obj.location = row_location(name)
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
        out[name] = {
            "tris": len(me.loop_triangles),
            "size": (round(max(xs) - min(xs), 2), round(max(ys) - min(ys), 2), round(max(zs), 2)),
            "zmin": round(min(zs), 3),
        }
        obj.evaluated_get(dg).to_mesh_clear()
    return out


# --- preview ----------------------------------------------------------------------------------------


def ground_color(biome: str) -> None:
    mat = bpy.data.materials["PreviewGround"]
    lo, hi = GROUND[biome]
    for node in mat.node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*lo, 1.0)
            node.inputs[7].default_value = (*hi, 1.0)


def scatter(objs: dict, biome: str, seed: int) -> list:
    """Game-like scatter of linked copies (dense, to judge how the kit reads from the game camera)."""
    rnd = random.Random(seed)
    counts = (
        {"Dust_Shrub_a": 9, "Dust_Shrub_b": 12, "Dust_Spire_a": 4, "Dust_Debris_a": 8, "Dust_Debris_b": 3}
        if biome == "dust"
        else {
            "Overgrowth_Frond_b": 24,
            "Overgrowth_Fungus_a": 8,
            "Overgrowth_Tube_a": 4,
            "Overgrowth_Fungus_b": 5,
            "Overgrowth_Frond_a": 9,
        }
    )
    copies, placed = [], []
    for name, count in counts.items():
        for _ in range(count):
            for _try in range(30):
                x, y = rnd.uniform(-7, 7), rnd.uniform(-7, 7)
                if (
                    all((x - px) ** 2 + (y - py) ** 2 > 1.0 for px, py in placed)
                    and (x - 1.5) ** 2 + (y + 1.5) ** 2 > 2.0
                ):
                    break
            placed.append((x, y))
            o = objs[name].copy()
            o.parent = None
            C.link(o, None, "Preview")
            o.location = (x, y, 0)
            o.rotation_euler = (rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06), rnd.uniform(0, TAU))
            s = rnd.uniform(0.7, 1.3)
            o.scale = (s, s, s)
            copies.append(o)
    return copies


def show_only(visible: list) -> None:
    vis = {o.name for o in visible}
    for o in C.collection(ASSET).all_objects:
        if o.type == "MESH":
            o.hide_render = o.name not in vis
    for o in C.collection("Preview").all_objects:
        if o.name.startswith("Scatter"):
            o.hide_render = o.name not in vis


def place_figure(loc) -> None:
    bpy.data.objects["PreviewFigure"].location = loc


def render_set(objs: dict, prefix: str, samples: int, size: int, close: bool) -> list:
    paths = []
    scatter_sets = {}
    for biome, seed in (("dust", 5), ("overgrowth", 9)):
        copies = scatter(objs, biome, seed)
        for i, o in enumerate(copies):
            o.name = f"Scatter_{biome}_{i:02d}"
        scatter_sets[biome] = copies
    for biome, names in (("dust", DUST), ("overgrowth", OVERGROWTH)):
        ground_color(biome)
        # Line-up from the game angle, figure at the end of the row for scale.
        show_only([objs[n] for n in names])
        center = ROW_CENTER[biome]
        place_figure(center + ROW_DIR * (ROW_STEP * 2.9))
        path = OUT / f"{prefix}_{biome}_lineup.png"
        C.render(path, view="iso", samples=samples, size=size, target=tuple(center + Vector((0, 0, 0.5))), zoom=1.12)
        paths.append(path)
        # Game distance (~20 m), dense scatter.
        show_only(scatter_sets[biome])
        place_figure((1.5, -1.5, 0))
        path = OUT / f"{prefix}_{biome}_scatter.png"
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.3), zoom=1.45)
        paths.append(path)
        if close:
            for name in names:
                obj = objs[name]
                h = obj.dimensions.z
                show_only([obj])
                loc = obj.location
                place_figure(loc + Vector((1.3, 0.9, 0)))
                tgt = tuple(loc + Vector((0, 0, max(0.15, h * 0.45))))
                zoom = max(0.2, min(0.62, 0.12 + h * 0.16))
                for view in ("iso", "hero"):
                    path = OUT / f"{prefix}_{name}_{view}.png"
                    C.render(
                        path,
                        view=view,
                        samples=samples,
                        size=size // 2 if size > 512 else size,
                        target=tgt,
                        zoom=zoom * (0.9 if view == "iso" else 1.0),
                    )
                    paths.append(path)
    return paths


def main() -> None:
    C.reset(ASSET)
    objs = build()
    stats = per_object_stats(objs)
    for name, s in stats.items():
        print(f"STATS {name:22s} tris {s['tris']:5d}  size {s['size']}  zmin {s['zmin']}")
    print("STATS total", sum(s["tris"] for s in stats.values()))
    C.preview_scene(crystals=False, figure_location=(0, 0, 0))
    # Preview rubble from common would clutter the line-ups; keep only ground, figure and lights.
    for o in list(C.collection("Preview").all_objects):
        if o.type == "MESH" and o.name.startswith("Ico"):
            bpy.data.objects.remove(o)
    if MODE == "final":
        paths = render_set(objs, "final", samples=48, size=768, close=True)
        C.contact_sheet(paths, OUT / "sheet.png", tile=512)
        for o in [o for o in C.collection("Preview").all_objects if o.name.startswith("Scatter")]:
            bpy.data.objects.remove(o)
        for o in C.collection(ASSET).all_objects:
            o.hide_render = False
        C.save_blend(OUT / "plants_procedural.blend")
    else:
        paths = render_set(objs, f"wip/{TAG}", samples=24, size=512, close=CLOSE)
        C.contact_sheet(paths, OUT / "wip" / f"{TAG}_sheet.png", tile=384)


main()
