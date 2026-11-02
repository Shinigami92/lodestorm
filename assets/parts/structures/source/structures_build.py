"""Colony structures kit: the bigger prefab structures of the map parts (points of interest and set pieces): two
habitat/storage modules of the abandoned outpost, its pressure tank, comms mast and landing pad, the expedition
camp's survival pod and portable beacon mast (with its separate lens), Hollis' field shelter and his survey drill
tripod with its base plate.

Run from the repo root (see docs/technical/assets.md), through the GPU slot when other agents bake at the same time:
    tools/blender.sh assets/parts/structures/source/structures_build.py wip s1                  # pieces overview
    tools/blender.sh assets/parts/structures/source/structures_build.py wip s1 Module_a,outpost
    tools/blender.sh assets/parts/structures/source/structures_build.py final

Everything it writes goes to tmp/assets/parts/structures/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: kit, pieces, a piece name, a part layout name (outpost, expedition_camp, hollis_camp,
hollis_dig_site), sheet, save); "final" renders every piece (iso + hero), the part layouts from the game's angle,
writes the contact sheet sheet.png and saves the procedural structures_procedural.blend that structures_bake.py turns
into the game asset. In the .blend the pieces stand unrotated in a row along X, 3 m apart (so the AO bake doesn't
pick up neighbors); the bake zeroes their locations.

Game contract (game/models/model_parts.gd): the map parts place each piece by name, so every piece is one mesh object
at the kit's root, its origin at the bottom center on z = 0 (the ground contact; the lens at its own center), front
(doors, hatches) towards -Y, with extra geometry below ground (skids, legs, skirts) so it doesn't float on uneven
ground. Budgets (TBD (playtest)): medium pieces <= ~3k triangles, the modules and the pad <= ~8k.

Look (the colony's shared look): weathered paint on steel; bone-white habitat panels, olive-grey cargo paint, dark
gunmetal frames; chipped edges, rust streaks down the walls, grime in recesses, neutral dust on the lower part;
faded amber hazard stripes on door frames, dark stenciled numbers. Only small lamps glow (the mast's red light, the
beacon lens, the pad's lights, the shelter's lit window); each is its own small faces in a lamp material. Several
procedural materials (one per stuff); the bake turns them into the kit's one material with an emission map.
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "structures"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
from common import T, rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "s0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit"]

ASSET = "Structures"
PIECES = [
    "Module_a",
    "Module_b",
    "Tank",
    "Mast",
    "Landing_pad",
    "Survival_pod",
    "Expedition_mast",
    "Expedition_lens",
    "Shelter",
    "Drill_tripod",
    "Drill_plate",
]
LENS_HEIGHT = 3.75  # the lens's center above the expedition mast's origin

# Material slots, the same list on every piece (index = slot).
(
    HAB,  # abandoned habitat paint (bone), rusty
    CAMP,  # the shelter's bone paint, kept up a little better
    POD,  # the pod's hull paint, scorched from the landing
    CARGO,  # olive-grey cargo paint (tank, cases, the drill's motor)
    FRAME,  # dark gunmetal frames, legs, machinery
    HAZ,  # faded amber / dark diagonal hazard stripes
    AMBER,  # faded amber paint (bands, collars)
    DECK,  # worn bare steel (steps, plates, rods)
    PAD,  # the landing pad's deck: plates, faded circle and cross, soot
    DARK,  # dark interiors (open hatch, missing panels, grilles)
    GLASS,  # dark window glass
    CRACKED,  # the cracked window
    RUBBER,  # hoses, cables
    STENCIL,  # dark stencil paint (numbers)
    SHIELD,  # the pod's charred heat shield
    TARP,  # the shelter's awning canvas
    LAMP_RED,  # glowing: the mast's red marker light
    LAMP_AMBER,  # glowing: the expedition beacon's lens
    LAMP_PAD,  # glowing: the pad's embedded lights
    LAMP_WIN,  # glowing: the shelter's lit window (dim)
) = range(20)
EMISSION = 6.0  # the strength the bake divides the emission by (glTF emissive strength of the kit material)


# --- colors -------------------------------------------------------------------------------------------


def lin(c: float) -> float:
    return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92


def srgb(r: float, g: float, b: float) -> tuple[float, float, float]:
    """sRGB (as in the art brief) to the linear values the nodes take."""
    return (lin(r), lin(g), lin(b))


BONE = (0.47, 0.46, 0.43)
OLIVE = (0.30, 0.31, 0.27)
GUNMETAL = (0.16, 0.16, 0.17)
AMBER_PAINT = (0.70, 0.48, 0.14)
RUST = (0.34, 0.21, 0.12)
DUST = (0.36, 0.33, 0.29)


# --- geometry helpers ---------------------------------------------------------------------------------

# Profile frames for Part.prism: MX maps local (a, b, c) to world (c, a, b) (a profile in the YZ plane extruded
# along X), MY maps it to (a, -c, b) (a profile in the XZ plane extruded along -Y). Both keep the orientation.
MX = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
MY = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


class KPart(C.Part):
    """C.Part whose bevel only rounds the hard-surface primitives: thin rods, wires and lathed shapes are marked
    `thin` and keep their edges (an angle bevel on a 6-sided rod or a 20-sided hull would only add triangles)."""

    def __init__(self, name: str, bevel: tuple[float, int] = (0.02, 2)):
        super().__init__(name, MATERIALS, bevel)
        self.soft: set = set()
        self.split: set = set()  # faces of hollow rings: each its own UV island (see structures_bake.py)
        # Layers before any geometry: adding one later invalidates the faces held in self.split.
        self.split_layer = self.bm.faces.layers.int.new("split")
        self.weight_layer = self.bm.edges.layers.float.new("bevel_weight_edge")

    def thin(self, verts):
        self.soft.update(verts)
        return verts

    def finish(self, parent=None) -> bpy.types.Object:
        bm = self.bm
        bm.normal_update()
        for f in self.split:
            f[self.split_layer] = 1
        layer = self.weight_layer
        for e in bm.edges:
            hard = not (e.verts[0] in self.soft or e.verts[1] in self.soft)
            angle = e.calc_face_angle(0.0)
            e[layer] = 1.0 if hard and angle > math.radians(35) else 0.0
        bev = self.bev
        self.bev = None
        obj = super().finish(parent)
        self.bev = bev
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bev[0]
        mod.segments = bev[1]
        mod.limit_method = "WEIGHT"
        mod.harden_normals = True
        obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL").keep_sharp = True
        return obj


def rounded_rect(w: float, h: float, rt: float, rb: float, z0: float, seg: int = 4) -> list:
    """CCW profile (y, z) of a box section with rounded corners: rt on top, rb at the bottom, from z0 to z0 + h."""
    pts = []
    corners = (
        (w / 2 - rb, z0 + rb, rb, -90),
        (w / 2 - rt, z0 + h - rt, rt, 0),
        (-w / 2 + rt, z0 + h - rt, rt, 90),
        (-w / 2 + rb, z0 + rb, rb, 180),
    )
    for cy, cz, r, a0 in corners:
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cy + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def band_x(p: KPart, outer: list, inner: list, x0: float, x1: float, mi: int) -> list:
    """A rib around a prism along X: the outer surface and both side rings, open inside (hidden in the body)."""
    bm = p.bm
    n = len(outer)
    o0 = [bm.verts.new((x0, y, z)) for y, z in outer]
    o1 = [bm.verts.new((x1, y, z)) for y, z in outer]
    i0 = [bm.verts.new((x0, y, z)) for y, z in inner]
    i1 = [bm.verts.new((x1, y, z)) for y, z in inner]
    for i in range(n):
        j = (i + 1) % n
        sides = (bm.faces.new((o1[i], o1[j], i1[j], i1[i])), bm.faces.new((i0[i], i0[j], o0[j], o0[i])))
        p.split.update(sides)
        for f in (bm.faces.new((o0[i], o0[j], o1[j], o1[i])), *sides):
            f.normal_update()
    return p._tag(o0 + o1 + i0 + i1, mi)


def lathe(
    p: KPart,
    prof: list,
    seg: int,
    mi: int,
    m: Matrix | None = None,
    axis: str = "z",
    caps: bool = True,
    spin: float = 0.0,
    split_flat: bool = True,
):
    """Revolve a profile of (a, r) around the Z axis (or X): a along the axis, r = 0 closes with a pole. The
    profile runs from the low end to the high end along the outside, so the normals point out. split_flat: the
    flat rings across the axis (hollow in the UVs) are split into one UV island per face."""
    bm = p.bm
    m = m or Matrix.Identity(4)
    rings = []
    for a, r in prof:
        if r <= 0:
            pt = (0, 0, a) if axis == "z" else (a, 0, 0)
            rings.append([bm.verts.new(m @ Vector(pt))])
            continue
        ring = []
        for k in range(seg):
            t = math.radians(spin) + math.tau * k / seg
            c, s = math.cos(t) * r, math.sin(t) * r
            pt = (c, s, a) if axis == "z" else (a, c, s)
            ring.append(bm.verts.new(m @ Vector(pt)))
        rings.append(ring)
    for n, (ra, rb) in enumerate(itertools.pairwise(rings)):
        flat = split_flat and len(ra) > 1 and len(rb) > 1 and abs(prof[n][0] - prof[n + 1][0]) < 1e-6
        for k in range(seg):
            q = (k + 1) % seg
            if len(ra) == 1:
                f = bm.faces.new((ra[0], rb[q], rb[k]))
            elif len(rb) == 1:
                f = bm.faces.new((ra[k], ra[q], rb[0]))
            else:
                f = bm.faces.new((ra[k], ra[q], rb[q], rb[k]))
                if flat:
                    p.split.add(f)
            f.normal_update()
    if caps and len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0]))).normal_update()
    if caps and len(rings[-1]) > 1:
        bm.faces.new(rings[-1]).normal_update()
    verts = [v for ring in rings for v in ring]
    return p.thin(p._tag(verts, mi))


def tube(p: KPart, pts: list, r: float, sides: int = 6, mi: int = RUBBER, caps: bool = True):
    """A round tube along a polyline (hoses, cables, wires), its rings turned along the averaged direction."""
    bm = p.bm
    pts = [Vector(q) for q in pts]
    rings = []
    hint = Vector((0, 0, 1))
    for i, q in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if abs(d.dot(hint)) > 0.95:
            hint = Vector((1, 0, 0))
        b = C.basis(d, hint)
        x_ax, y_ax = b.col[0], b.col[1]
        hint = Vector(x_ax)
        ring = []
        for k in range(sides):
            t = math.tau * k / sides
            ring.append(bm.verts.new(q + (x_ax * math.cos(t) + y_ax * math.sin(t)) * r))
        rings.append(ring)
    for ra, rb in itertools.pairwise(rings):
        for k in range(sides):
            q = (k + 1) % sides
            bm.faces.new((ra[k], ra[q], rb[q], rb[k])).normal_update()
    if caps:
        bm.faces.new(list(reversed(rings[0]))).normal_update()
        bm.faces.new(rings[-1]).normal_update()
    return p.thin(p._tag([v for ring in rings for v in ring], mi))


def sector(p: KPart, x0, x1, r0, r1, a0, a1, seg: int, mi: int, m: Matrix | None = None):
    """A curved slab around the X axis: radii r0..r1, angles a0..a1 (degrees from +Y towards +Z), x0..x1."""
    bm = p.bm
    m = m or Matrix.Identity(4)

    def ring(x, r):
        out = []
        for i in range(seg + 1):
            a = math.radians(a0 + (a1 - a0) * i / seg)
            out.append(bm.verts.new(m @ Vector((x, r * math.cos(a), r * math.sin(a)))))
        return out

    o0, o1, i0, i1 = ring(x0, r1), ring(x1, r1), ring(x0, r0), ring(x1, r0)
    faces = []
    for i in range(seg):
        j = i + 1
        faces += [
            bm.faces.new((o0[i], o0[j], o1[j], o1[i])),
            bm.faces.new((i0[j], i0[i], i1[i], i1[j])),
            bm.faces.new((o1[i], o1[j], i1[j], i1[i])),
            bm.faces.new((i0[i], i0[j], o0[j], o0[i])),
        ]
    faces += [bm.faces.new((o0[0], o1[0], i1[0], i0[0])), bm.faces.new((o0[-1], i0[-1], i1[-1], o1[-1]))]
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return p._tag(o0 + o1 + i0 + i1, mi)


# 7-segment digits for the stencils: segments a (top), b, c (right), d (bottom), e, f (left), g (middle).
SEGMENTS = {
    "0": "abcdef",
    "1": "bc",
    "2": "abged",
    "3": "abgcd",
    "4": "fgbc",
    "5": "afgcd",
    "6": "afgedc",
    "7": "abc",
    "8": "abcdefg",
    "9": "abcdfg",
    "-": "g",
}


def stencil(p: KPart, text: str, origin, right, up, h: float, mi: int = STENCIL) -> None:
    """Block digits painted on a surface: origin is the text's bottom-left on the surface, right/up span it; each
    segment is a 1 cm thin plate just proud of the surface."""
    origin, right, up = Vector(origin), Vector(right).normalized(), Vector(up).normalized()
    normal = right.cross(up)
    w, t = 0.56 * h, 0.15 * h
    rot = Matrix((right, up, normal)).transposed()
    seg_box = {
        "a": (w / 2, h - t / 2, w, t),
        "d": (w / 2, t / 2, w, t),
        "g": (w / 2, h / 2, w, t),
        "b": (w - t / 2, 0.75 * h, t, h / 2),
        "c": (w - t / 2, 0.25 * h, t, h / 2),
        "e": (t / 2, 0.25 * h, t, h / 2),
        "f": (t / 2, 0.75 * h, t, h / 2),
    }
    for k, ch in enumerate(text):
        base = origin + right * (k * (w + 0.3 * h))
        for s in SEGMENTS.get(ch, ""):
            cx, cy, sx, sy = seg_box[s]
            p.thin(p.box(base + right * cx + up * cy + normal * 0.004, (sx, sy, 0.01), rot, mi))


# --- materials ----------------------------------------------------------------------------------------


class Shader:
    """Node helpers for the kit materials (numbers are set, sockets linked)."""

    def __init__(self, nt: bpy.types.NodeTree):
        self.nt = nt
        self.obj = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        self.geo = nt.nodes.new("ShaderNodeNewGeometry")
        pos = self.xyz(self.obj)
        self.x, self.y, self.z = pos.outputs["X"], pos.outputs["Y"], pos.outputs["Z"]
        self.nz = self.xyz(self.geo.outputs["Normal"]).outputs["Z"]

    def m(self, op: str, a, b=None, c=None, clamp: bool = False) -> bpy.types.NodeSocket:
        return C._math(self.nt, op, a, b, c, clamp)

    def mix(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_float(self.nt, fac, a, b)

    def ramp(self, a: float, b: float, src) -> bpy.types.NodeSocket:
        """0 below a, 1 above b, linear between (any range, unlike a color ramp's 0..1 positions)."""
        node = self.nt.nodes.new("ShaderNodeMapRange")
        node.clamp = True
        node.inputs["From Min"].default_value = a
        node.inputs["From Max"].default_value = b
        self.nt.links.new(src, node.inputs["Value"])
        return node.outputs["Result"]

    def inv(self, src) -> bpy.types.NodeSocket:
        return self.m("SUBTRACT", 1.0, src, clamp=True)

    def noise(self, scale: float, detail: float = 3.0, rough: float = 0.55, vector=None) -> bpy.types.NodeSocket:
        """Noise Fac (about 0.5 +- 0.09)."""
        return C._noise(self.nt, scale, detail, rough, vector if vector is not None else self.obj).outputs["Fac"]

    def spread(self, fac, k: float) -> bpy.types.NodeSocket:
        """Noise Fac stretched around 0.5 by `k`, clamped to 0..1."""
        return self.m("MULTIPLY_ADD", self.m("SUBTRACT", fac, 0.5), k, 0.5, clamp=True)

    def xyz(self, vector) -> bpy.types.Node:
        node = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(vector, node.inputs["Vector"])
        return node

    def vec(self, x, y, z) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeCombineXYZ")
        for sock, val in zip(node.inputs, (x, y, z)):
            if isinstance(val, bpy.types.NodeSocket):
                self.nt.links.new(val, sock)
            else:
                sock.default_value = val
        return node.outputs[0]

    def scaled(self, k) -> bpy.types.NodeSocket:
        """The object coordinates scaled per axis (stretched noise: streaks)."""
        return self.vec(
            self.m("MULTIPLY", self.x, k[0]), self.m("MULTIPLY", self.y, k[1]), self.m("MULTIPLY", self.z, k[2])
        )

    def ao(self, distance: float) -> bpy.types.NodeSocket:
        """Cavity: 0 in the open, up to 1 in recesses."""
        node = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        node.inputs["Distance"].default_value = distance
        node.samples = 16
        return self.inv(self.ramp(0.35, 0.95, node.outputs["AO"]))

    def edge(self, radius: float = 0.025) -> bpy.types.NodeSocket:
        return self.ramp(0.02, 0.1, C._bevel_edge(self.nt, radius, self.geo))


def weathering(s: Shader, col, rough, wear: float, rust: float, dust: float, metal_edges: bool = True):
    """The colony's weathering over a paint color: chipped edges to bare (rusting) steel, grime in recesses, rust
    streaks running down the walls and spots on top, neutral dust on the lower part. Low contrast and large scale
    (the game camera sees it from far). Returns (color, roughness, metallic, height)."""
    cavity = s.ao(0.25)
    edge = s.edge()
    chips = s.m("MULTIPLY", edge, s.ramp(0.52 - 0.08 * wear, 0.58 - 0.08 * wear, s.noise(5.0, 4.0, 0.65)))
    chips = s.m("MULTIPLY", chips, min(1.0, 0.4 + wear))
    wall = s.inv(s.ramp(0.55, 0.85, s.m("ABSOLUTE", s.nz)))
    streak = s.ramp(0.56, 0.7, s.noise(1.0, 2.0, 0.5, s.scaled((7.0, 7.0, 0.45))))
    source = s.ramp(0.5, 0.62, s.noise(1.1, 2.0, 0.5))
    streaks = s.m("MULTIPLY", s.m("MULTIPLY", streak, source), s.m("MULTIPLY", wall, 0.55 * rust))
    spots = s.m("MULTIPLY", s.ramp(0.6, 0.7, s.noise(2.6, 3.0, 0.6)), s.m("MULTIPLY", s.inv(wall), 0.45 * rust))
    rust_k = s.m("MAXIMUM", streaks, spots)
    low = s.inv(s.ramp(0.05, 1.1, s.m("ADD", s.z, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(1.4), 0.5), 1.2))))
    dust_k = s.m("MULTIPLY", s.m("ADD", s.m("MULTIPLY", low, 0.6), s.m("MULTIPLY", cavity, 0.35)), dust, clamp=True)
    col = s.mix(s.m("MULTIPLY", cavity, 0.45), col, srgb(0.1, 0.095, 0.085))
    col = s.mix(rust_k, col, srgb(*RUST))
    col = s.mix(dust_k, col, srgb(*DUST))
    steel = s.mix(s.m("MULTIPLY", s.noise(3.0), rust * 0.8), srgb(0.36, 0.355, 0.35), srgb(*RUST))
    col = s.mix(chips, col, steel)
    rough = s.mixf(rust_k, rough, 0.85)
    rough = s.mixf(dust_k, rough, 0.92)
    rough = s.mixf(chips, rough, 0.42)
    metal = s.m("MULTIPLY", chips, 0.8 if metal_edges else 0.0)
    height = s.m(
        "ADD", s.m("MULTIPLY", chips, -0.6), s.m("MULTIPLY", s.m("MULTIPLY", rust_k, s.noise(30.0, 3.0, 0.6)), 0.5)
    )
    height = s.m("ADD", height, s.m("MULTIPLY", s.noise(60.0, 2.0, 0.5), 0.08))
    return col, rough, metal, height


def finish_mat(s: Shader, bsdf, col, rough, metal, height, bump: float = 0.25) -> None:
    nt = s.nt
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    if isinstance(metal, bpy.types.NodeSocket):
        nt.links.new(metal, bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Metallic"].default_value = metal
    C._bump(nt, bsdf, height, bump, 0.01)


def mat_paint(
    name: str,
    color,
    rough: float = 0.62,
    wear: float = 0.5,
    rust: float = 0.5,
    dust: float = 0.5,
    scorch: float = 0.0,
    stripes: bool = False,
) -> bpy.types.Material:
    """Weathered paint on steel in `color` (sRGB). stripes: diagonal hazard stripes of the color and dark paint;
    scorch: soot from the -X end (the pod's heat shield) streaming back along the hull."""
    mat, nt, bsdf = C._new_material(name)
    s = Shader(nt)
    tone = s.noise(0.7, 3.0, 0.5)
    base = s.mix(s.spread(tone, 3.0), srgb(*(c * 0.94 for c in color)), srgb(*(c * 1.05 for c in color)))
    if stripes:
        diag = s.m("ADD", s.m("ADD", s.x, s.y), s.z)
        band = s.m("GREATER_THAN", s.m("FRACT", s.m("DIVIDE", diag, 0.34)), 0.5)
        base = s.mix(band, base, srgb(0.13, 0.125, 0.12))
        base = s.mix(s.m("MULTIPLY", s.ramp(0.45, 0.6, s.noise(4.0)), 0.35), base, srgb(0.3, 0.29, 0.27))
    r = s.mixf(tone, rough - 0.05, rough + 0.05)
    col, r, metal, height = weathering(s, base, r, wear, rust, dust)
    if scorch:
        along = s.m("ADD", s.x, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(0.9), 0.5), 1.6))
        soot = s.inv(s.ramp(-1.5, 0.4, along))
        streak = s.ramp(0.4, 0.62, s.noise(1.0, 2.0, 0.5, s.scaled((0.35, 5.0, 5.0))))
        soot = s.m("MULTIPLY", s.m("MULTIPLY", soot, s.m("ADD", 0.45, streak)), scorch, clamp=True)
        col = s.mix(soot, col, srgb(0.06, 0.055, 0.05))
        r = s.mixf(soot, r, 0.9)
    finish_mat(s, bsdf, col, r, metal, height)
    return mat


def mat_deck(name: str, pad: bool = False) -> bpy.types.Material:
    """Worn bare steel (steps, plates, rods). pad: the landing pad's deck, 1.5 m plates with dark seams and their
    own tones, a faded amber circle and cross (paint worn off in patches), soot in the middle, dust at the rim."""
    mat, nt, bsdf = C._new_material(name)
    s = Shader(nt)
    tone = s.noise(1.2, 3.0, 0.5)
    col = s.mix(s.spread(tone, 3.0), srgb(0.27, 0.27, 0.265), srgb(0.33, 0.33, 0.32))
    rough = s.mixf(tone, 0.45, 0.62)
    height = s.m("MULTIPLY", s.noise(45.0, 2.0, 0.5), 0.1)
    if pad:
        cell = 1.5

        def seam_dist(v):
            return s.m("MULTIPLY", s.m("ABSOLUTE", s.m("SUBTRACT", s.m("FRACT", s.m("DIVIDE", v, cell)), 0.5)), cell)

        dx, dy = seam_dist(s.x), seam_dist(s.y)
        seam = s.inv(s.ramp(0.008, 0.018, s.m("SUBTRACT", cell / 2, s.m("MAXIMUM", dx, dy))))
        cell_id = s.vec(s.m("FLOOR", s.m("DIVIDE", s.x, cell)), s.m("FLOOR", s.m("DIVIDE", s.y, cell)), 0.0)
        white = nt.nodes.new("ShaderNodeTexWhiteNoise")
        white.noise_dimensions = "3D"
        nt.links.new(cell_id, white.inputs["Vector"])
        plate_k = s.m("MULTIPLY_ADD", white.outputs["Value"], 0.16, 0.92)
        tint = nt.nodes.new("ShaderNodeVectorMath")
        tint.operation = "SCALE"
        nt.links.new(col, tint.inputs[0])
        nt.links.new(plate_k, tint.inputs["Scale"])
        col = tint.outputs[0]
        rad = nt.nodes.new("ShaderNodeVectorMath")
        rad.operation = "LENGTH"
        nt.links.new(s.vec(s.x, s.y, 0.0), rad.inputs[0])
        r = rad.outputs["Value"]
        ring = s.m("MULTIPLY", s.ramp(2.42, 2.46, r), s.inv(s.ramp(2.72, 2.76, r)))
        ax, ay = s.m("ABSOLUTE", s.x), s.m("ABSOLUTE", s.y)
        bar1 = s.m("MULTIPLY", s.inv(s.ramp(0.19, 0.21, ax)), s.inv(s.ramp(1.68, 1.72, ay)))
        bar2 = s.m("MULTIPLY", s.inv(s.ramp(0.19, 0.21, ay)), s.inv(s.ramp(1.68, 1.72, ax)))
        mark = s.m("MAXIMUM", ring, s.m("MAXIMUM", bar1, bar2))
        fade = s.m("MULTIPLY", s.ramp(0.4, 0.55, s.noise(2.0, 4.0, 0.6)), 0.75)
        mark = s.m("MULTIPLY", mark, fade)
        col = s.mix(mark, col, srgb(0.6, 0.43, 0.15))
        rough = s.mixf(mark, rough, 0.7)
        soot = s.inv(s.ramp(0.3, 2.6, s.m("ADD", r, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(1.2), 0.5), 2.0))))
        col = s.mix(s.m("MULTIPLY", soot, 0.6), col, srgb(0.07, 0.065, 0.06))
        rim_dust = s.m("MULTIPLY", s.ramp(2.8, 3.9, r), s.ramp(0.45, 0.6, s.noise(1.8)))
        col = s.mix(s.m("MULTIPLY", rim_dust, 0.55), col, srgb(*DUST))
        col = s.mix(seam, col, srgb(0.06, 0.06, 0.06))
        rough = s.mixf(s.m("MAXIMUM", rim_dust, soot), rough, 0.85)
        height = s.m("SUBTRACT", height, seam)
        cavity = s.ao(0.2)
        col = s.mix(s.m("MULTIPLY", cavity, 0.5), col, srgb(0.08, 0.075, 0.07))
        finish_mat(s, bsdf, col, rough, 0.55, height, 0.35)
        return mat
    col, rough, _metal, height2 = weathering(s, col, rough, 0.0, 0.6, 0.7, metal_edges=False)
    finish_mat(s, bsdf, col, rough, 0.6, s.m("ADD", height, height2))
    return mat


def mat_flat(name: str, color, rough: float, dust: float = 0.4, metal: float = 0.0, cracks: bool = False):
    """Plain stuff with a little grime and dust (interiors, glass, rubber, canvas, the charred shield)."""
    mat, nt, bsdf = C._new_material(name)
    s = Shader(nt)
    tone = s.noise(1.5, 3.0, 0.5)
    col = s.mix(s.spread(tone, 2.0), srgb(*(c * 0.88 for c in color)), srgb(*(c * 1.1 for c in color)))
    height = s.m("MULTIPLY", s.noise(25.0, 3.0, 0.6), 0.2)
    rough_s = s.mixf(tone, rough - 0.04, rough + 0.04)
    if cracks:
        lines = C._voronoi_lines(nt, s.obj, 5.0, 0.03)
        col = s.mix(s.m("MULTIPLY", lines, 0.8), col, srgb(*(min(1, c * 3.5) for c in color)))
        height = s.m("SUBTRACT", height, s.m("MULTIPLY", lines, 0.6))
    if dust:
        low = s.inv(s.ramp(0.05, 1.0, s.m("ADD", s.z, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(1.4), 0.5), 1.2))))
        dust_k = s.m("MULTIPLY", s.m("ADD", s.m("MULTIPLY", low, 0.6), s.m("MULTIPLY", s.ao(0.2), 0.3)), dust)
        col = s.mix(dust_k, col, srgb(*DUST))
        rough_s = s.mixf(dust_k, rough_s, 0.9)
    finish_mat(s, bsdf, col, rough_s, metal, height, 0.2)
    return mat


def mat_cracked_glass(name: str) -> bpy.types.Material:
    """Dark window glass with a cracked star of light lines from one impact point and a dusty film."""
    mat, nt, bsdf = C._new_material(name)
    s = Shader(nt)
    lines = C._voronoi_lines(nt, s.scaled((1.0, 1.0, 1.0)), 9.0, 0.035)
    col = s.mix(s.m("MULTIPLY", lines, 0.7), srgb(0.03, 0.035, 0.04), srgb(0.28, 0.29, 0.3))
    rough = s.mixf(lines, 0.12, 0.5)
    finish_mat(s, bsdf, col, rough, 0.0, s.m("MULTIPLY", lines, -0.5), 0.3)
    return mat


def mat_lamp(name: str, color, strength: float) -> bpy.types.Material:
    mat = C.mat_emissive(name, color, strength)
    return mat


def make_materials() -> list:
    """Every kit material in slot order (see the slot constants)."""
    return [
        mat_paint("Hab", BONE, 0.62, wear=0.7, rust=1.0, dust=0.6),
        mat_paint("Camp", BONE, 0.6, wear=0.45, rust=0.35, dust=0.6),
        mat_paint("PodHull", (0.5, 0.49, 0.46), 0.5, wear=0.5, rust=0.15, dust=0.45, scorch=1.0),
        mat_paint("Cargo", OLIVE, 0.6, wear=0.5, rust=0.6, dust=0.55),
        mat_paint("Frame", GUNMETAL, 0.55, wear=0.6, rust=0.7, dust=0.6),
        mat_paint("Hazard", AMBER_PAINT, 0.65, wear=0.8, rust=0.4, dust=0.4, stripes=True),
        mat_paint("Amber", (0.62, 0.43, 0.14), 0.65, wear=0.8, rust=0.3, dust=0.45),
        mat_deck("Deck"),
        mat_deck("PadDeck", pad=True),
        mat_flat("Dark", (0.025, 0.024, 0.023), 0.9, dust=0.2),
        mat_flat("Glass", (0.03, 0.035, 0.04), 0.12, dust=0.3),
        mat_cracked_glass("GlassCracked"),
        mat_flat("Rubber", (0.035, 0.035, 0.035), 0.75, dust=0.6),
        mat_flat("Stencil", (0.13, 0.13, 0.12), 0.7, dust=0.3),
        mat_flat("Shield", (0.075, 0.065, 0.058), 0.9, dust=0.2, cracks=True),
        mat_flat("Tarp", (0.29, 0.28, 0.23), 0.95, dust=0.5),
        mat_lamp("LampRed", (1.0, 0.1, 0.05), 6.0),
        mat_lamp("LampAmber", (1.0, 0.5, 0.15), 6.0),
        mat_lamp("LampPad", (1.0, 0.6, 0.28), 3.0),
        mat_lamp("LampWindow", (1.0, 0.6, 0.3), 1.2),
    ]


MATERIALS: list = []


# --- pieces -------------------------------------------------------------------------------------------

Z0 = 0.3  # the modules' floor: the body stands on skids this high


def window(p: KPart, x: float, side: int, half_d: float, z: float, mi: int = GLASS, w=0.72, h=0.44) -> None:
    """A small window on a long wall (side -1: the -Y wall, +1: the +Y wall): a frame of four bars, the glass
    recessed in it."""
    y = side * half_d
    fw, fd = 0.08, 0.07
    p.box((x, y + side * 0.012, z), (w, 0.024, h), mi=mi)
    for dz in (-1, 1):
        p.box((x, y + side * fd / 2, z + dz * (h + fw) / 2), (w + 2 * fw, fd, fw), mi=FRAME)
    for dx in (-1, 1):
        p.box((x + dx * (w + fw) / 2, y + side * fd / 2, z), (fw, fd, h), mi=FRAME)


def door(p: KPart, x: float, half_d: float, z0: float, open_: bool, w: float = 1.1, h: float = 2.05) -> None:
    """A door in the -Y wall: amber-striped frame, the leaf (closed in the frame, or slid half open on a rail in
    front of the wall with the dark inside showing), a steel step in front."""
    y = -half_d
    fw, fd = 0.2, 0.16
    zb = z0 + 0.04
    for dx in (-1, 1):
        p.box((x + dx * (w + fw) / 2, y - fd / 2 + 0.03, zb + (h + fw) / 2), (fw, fd, h + fw), mi=HAZ)
    p.box((x, y - fd / 2 + 0.03, zb + h + fw / 2), (w + 2 * fw, fd, fw), mi=HAZ)
    if open_:
        p.box((x, y - 0.004, zb + h / 2), (w, 0.01, h), mi=DARK)
        lx = x + 0.62
        p.box((lx, y - 0.2, zb + h / 2), (w + 0.04, 0.06, h + 0.02), mi=FRAME)
        p.box((x + 0.35, y - 0.2, zb + h + 0.13), (2 * w + 0.7, 0.1, 0.1), mi=FRAME)  # rail
        p.box((lx - 0.2, y - 0.235, zb + h * 0.72), (0.26, 0.012, 0.34), mi=GLASS)
    else:
        p.box((x, y - 0.02, zb + h / 2), (w, 0.06, h), mi=FRAME)
        p.box((x, y - 0.053, zb + h * 0.72), (0.28, 0.012, 0.36), mi=GLASS)
        p.thin(p.rod((x + w / 2 - 0.12, y - 0.1, zb + 0.85), (x + w / 2 - 0.12, y - 0.1, zb + 1.25), 0.02, 6, FRAME))
    # Step: a grating box in front of the door, down into the ground.
    p.box((x, y - 0.42, (z0 - 0.4) / 2 - 0.02), (w + 0.5, 0.62, z0 + 0.36), mi=DECK)


def roof_vent(p: KPart, x: float, y: float, z: float, w=0.8, d=0.6) -> None:
    """A louvered vent box on the roof: a dark grille on top with slats across."""
    p.box((x, y, z + 0.16), (w, d, 0.32), mi=FRAME)
    p.box((x, y, z + 0.322), (w - 0.14, d - 0.14, 0.01), mi=DARK)
    for k in range(4):
        p.box((x - (w - 0.2) / 2 + k * (w - 0.2) / 3, y, z + 0.33), (0.04, d - 0.12, 0.03), mi=FRAME)


def mushroom_vent(p: KPart, x: float, y: float, z: float) -> None:
    p.thin(p.cyl((x, y, z + 0.18), 0.11, 0.36, 12, mi=FRAME))
    p.cyl((x, y, z + 0.4), 0.22, 0.08, 12, mi=FRAME)


def module(name: str, length: float, depth: float, height: float, variant: str) -> bpy.types.Object:
    """A prefab habitat/storage module: a long body with rounded edges on two skids, gunmetal end frames and
    ribs between the panel bays, small dark windows, roof vents, a door frame with amber hazard stripes on the -Y
    side. Abandoned: a roof panel and a wall panel missing (dark holes with the stringers behind), one panel lying
    against the wall, a window cracked; rust streaks and dust in the material."""
    p = KPart(name, bevel=(0.025, 2))
    hl, hd = length / 2, depth / 2
    rt, rb = 0.5, 0.12
    h = height - Z0
    body = rounded_rect(depth, h, rt, rb, Z0)
    p.prism(body, -hl, hl, m=MX, mi=HAB)

    def ring(x0: float, x1: float, out: float, mi: int):
        outer = rounded_rect(depth + 2 * out, h + 2 * out, rt + out, rb + out, Z0 - out)
        inner = rounded_rect(depth - 0.04, h - 0.04, rt - 0.02, rb - 0.02, Z0 + 0.02)
        band_x(p, outer, inner, x0, x1, mi)

    ring(-hl - 0.03, -hl + 0.2, 0.06, FRAME)
    ring(hl - 0.2, hl + 0.03, 0.06, FRAME)
    bays = round(length / 1.4)
    bay = length / bays
    for k in range(1, bays):
        x = -hl + k * bay
        ring(x - 0.06, x + 0.06, 0.035, HAB)
    # Skids, down into the ground, upturned ends.
    for sy in (-1, 1):
        yc = sy * (hd - 0.45)
        pts = [
            (-hl - 0.2, -0.4),
            (hl + 0.2, -0.4),
            (hl + 0.2, 0.08),
            (hl - 0.1, Z0),
            (-hl + 0.1, Z0),
            (-hl - 0.2, 0.08),
        ]
        p.prism(pts, -yc - 0.12, -yc + 0.12, m=MY, mi=FRAME)
    a = variant == "a"
    top = height
    if a:
        door_x = 1.5
        door(p, door_x, hd, Z0, open_=False)
        window(p, -0.6, -1, hd, Z0 + 1.55)
        window(p, -2.4, -1, hd, Z0 + 1.55, mi=CRACKED)
        window(p, 0.9, 1, hd, Z0 + 1.55)
        window(p, 2.5, 1, hd, Z0 + 1.55)
        stencil(p, "04", (-hl + 0.45, -hd, Z0 + 0.45), (1, 0, 0), (0, 0, 1), 0.5)
        # Roof: an air handler with a fan, a louvered vent, two mushroom vents, a missing roof panel.
        p.box((-1.9, 0.1, top + 0.27), (1.4, 1.1, 0.54), mi=HAB)
        p.cyl((-1.9, 0.1, top + 0.545), 0.4, 0.012, 16, mi=DARK)
        for ang in (45, 135):
            p.thin(p.box((-1.9, 0.1, top + 0.56), (0.84, 0.035, 0.03), rz(ang), mi=FRAME))
        p.thin(p.cyl((-1.9, 0.1, top + 0.555), 0.08, 0.04, 8, mi=FRAME))
        roof_vent(p, 0.4, -0.55, top)
        mushroom_vent(p, 2.9, 0.6, top)
        mushroom_vent(p, 0.2, 0.75, top)
        hole_x = -hl + 4.5 * bay
        p.box((hole_x, -0.1, top + 0.003), (bay - 0.2, 1.5, 0.012), mi=DARK)
        for dy in (-0.45, 0.25):
            p.box((hole_x, -0.1 + dy, top + 0.0), (bay - 0.14, 0.07, 0.05), mi=FRAME)
        stencil(p, "04", (-3.2, -1.25, top), (1, 0, 0), (0, 1, 0), 0.7)
        # Back wall: a missing panel, the panel itself leaning against the wall below.
        hx = -hl + 1.5 * bay
        hz0, hz1 = Z0 + 0.45, top - rt - 0.1
        p.box((hx, hd + 0.004, (hz0 + hz1) / 2), (bay - 0.2, 0.012, hz1 - hz0), mi=DARK)
        for zz in (hz0 + 0.55, hz0 + 1.25):
            p.box((hx, hd + 0.012, zz), (bay - 0.14, 0.05, 0.07), mi=FRAME)
        p.beam(
            (hx - bay / 2 + 0.1, hd + 0.015, hz0 + 0.05),
            (hx + bay / 2 - 0.1, hd + 0.015, hz1 - 0.05),
            0.06,
            0.05,
            (0, 1, 0),
            mi=FRAME,
        )
        lean = 26
        bottom = Vector((hx + 1.0, hd + 0.72, -0.05))
        up = Vector((0, -math.sin(math.radians(lean)), math.cos(math.radians(lean))))
        p.box(bottom + up * 0.8, (bay - 0.22, 0.05, 1.6), rz(-8) @ rx(lean), mi=HAB)
        # End wall: a utility box with a dark grille.
        p.box((-hl - 0.3, -0.6, Z0 + 0.75), (0.45, 0.9, 0.8), mi=FRAME)
        p.box((-hl - 0.53, -0.6, Z0 + 0.75), (0.012, 0.6, 0.5), mi=DARK)
    else:
        door_x = -0.9
        door(p, door_x, hd, Z0, open_=True)
        window(p, 1.3, -1, hd, Z0 + 1.55)
        window(p, -0.2, 1, hd, Z0 + 1.55)
        stencil(p, "07", (hl - 1.3, -hd, Z0 + 0.45), (1, 0, 0), (0, 0, 1), 0.5)
        # Roof: a hatch, an antenna mast, a mushroom vent, a loose panel.
        p.box((0.9, -0.1, top + 0.06), (0.95, 0.95, 0.12), mi=FRAME)
        p.box((0.86, -0.12, top + 0.15), (0.8, 0.8, 0.07), rx(4), mi=HAB)
        p.thin(p.rod((-1.6, 0.6, top), (-1.6, 0.6, top + 1.5), 0.04, 8, FRAME))
        p.thin(p.rod((-1.6, 0.6, top + 1.3), (-1.0, 0.6, top + 1.3), 0.02, 6, FRAME))
        p.box((-1.6, 0.6, top + 0.05), (0.3, 0.3, 0.1), mi=FRAME)
        mushroom_vent(p, 2.0, 0.7, top)
        roof_vent(p, -0.4, -0.6, top, 0.7, 0.5)
        p.box((-hl + 1.5 * bay, 0.2, top + 0.05), (bay - 0.18, 1.3, 0.04), ry(3) @ rx(-5), mi=HAB)
        stencil(p, "07", (1.45, -1.2, top), (1, 0, 0), (0, 1, 0), 0.6)
        # Back wall: a missing panel.
        hx = hl - 1.5 * bay
        hz0, hz1 = Z0 + 0.45, top - rt - 0.1
        p.box((hx, hd + 0.004, (hz0 + hz1) / 2), (bay - 0.2, 0.012, hz1 - hz0), mi=DARK)
        for zz in (hz0 + 0.5, hz0 + 1.1):
            p.box((hx, hd + 0.012, zz), (bay - 0.14, 0.05, 0.07), mi=FRAME)
        # End walls: an air conditioner with a fan grille (-X), a ladder to the roof (+X).
        p.box((-hl - 0.32, 0.3, Z0 + 0.9), (0.5, 1.1, 0.95), mi=FRAME)
        p.cyl((-hl - 0.575, 0.3, Z0 + 0.9), 0.36, 0.012, 16, ry(90), mi=DARK)
        for ang in (45, -45):
            p.thin(p.box((-hl - 0.585, 0.3, Z0 + 0.9), (0.025, 0.74, 0.03), rx(ang), mi=FRAME))
        for sy in (-0.25, 0.25):
            p.thin(p.rod((hl + 0.16, sy - 0.6, 0.0), (hl + 0.16, sy - 0.6, top + 0.5), 0.025, 6, FRAME))
            p.thin(p.rod((hl + 0.03, sy - 0.6, top - 0.6), (hl + 0.16, sy - 0.6, top - 0.6), 0.02, 6, FRAME))
        for k in range(9):
            z = 0.35 + k * 0.32
            p.thin(p.rod((hl + 0.16, -0.85, z), (hl + 0.16, -0.35, z), 0.018, 6, FRAME))
    return p.finish()


def module_a() -> bpy.types.Object:
    """Module_a: the long habitat module (7.0 x 3.6 x 3.0 m), door closed on the -Y side near +X, a cracked
    window, an air handler and a missing panel on the roof, a missing wall panel (its panel leaning below) on the
    back. Turned 180 degrees it shows its damaged back."""
    return module("Module_a", 7.0, 3.6, 3.0, "a")


def module_b() -> bpy.types.Object:
    """Module_b: the shorter storage module (5.2 x 3.4 x 2.8 m) with its door slid half open (dark inside), an
    antenna, a roof hatch, a loose roof panel, an air conditioner on the -X end, a ladder on the +X end."""
    return module("Module_b", 5.2, 3.4, 2.8, "b")


def hoop(p: KPart, a0: float, a1: float, r0: float, r1: float, seg: int, mi: int, m=None, axis: str = "z"):
    """A band around a round body: radii r0 (inside, hidden) to r1, from a0 to a1 along the axis."""
    return lathe_open(p, [(a0, r0), (a0, r1), (a1, r1), (a1, r0)], seg, mi, m, axis)


def lathe_open(p: KPart, prof: list, seg: int, mi: int, m=None, axis: str = "z", split_flat: bool = True):
    """lathe() without the end caps (the open ends sit inside or against something else)."""
    return lathe(p, prof, seg, mi, m, axis, caps=False, split_flat=split_flat)


def tank() -> bpy.types.Object:
    """Tank: a vertical pressure tank (olive cargo paint) with domed ends on a gunmetal frame (four legs, a ground
    frame, a band), a faded amber band, a ladder on +X, a manway and a relief valve on top, an outlet pipe with a
    valve and a side pipe running into the ground. 2.4 m across, 3.4 m tall."""
    p = KPart("Tank", bevel=(0.02, 2))
    R = 0.95
    prof = [(0.42, 0), (0.45, 0.45), (0.53, 0.75), (0.68, R), (2.86, R), (3.0, 0.75), (3.09, 0.45), (3.12, 0)]
    lathe(p, prof, 20, CARGO)
    hoop(p, 2.35, 2.5, R - 0.02, R + 0.012, 20, AMBER)
    hoop(p, 1.0, 1.14, R - 0.02, R + 0.04, 20, FRAME)
    stencil(p, "2", (-0.12, -R - 0.02, 1.5), (1, 0, 0), (0, 0, 1), 0.45)
    corners = [Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0)) for a in (45, 135, 225, 315)]
    for c in corners:
        p.box(c * 0.98 + Vector((0, 0, 0.42)), (0.13, 0.13, 1.64), rz(45), mi=FRAME)
    for a, b in zip(corners, corners[1:] + corners[:1]):
        p.beam(a * 0.98 + Vector((0, 0, 0.06)), b * 0.98 + Vector((0, 0, 0.06)), 0.12, 0.12, (0, 0, 1), mi=FRAME)
    p.box((0, 0, -0.17), (1.5, 1.5, 0.34), rz(45), mi=FRAME)  # footing below ground
    # Top: manway, relief valve, vent gooseneck.
    p.cyl((0, 0, 3.15), 0.26, 0.1, 16, mi=FRAME)
    p.cyl((0, 0, 3.23), 0.22, 0.07, 16, mi=FRAME)
    p.thin(p.cyl((0.42, 0.25, 3.12), 0.06, 0.26, 10, mi=FRAME))
    p.cyl((0.42, 0.25, 3.27), 0.09, 0.05, 10, mi=AMBER)
    tube(
        p,
        [(-0.35, -0.3, 3.0), (-0.35, -0.3, 3.3), (-0.4, -0.3, 3.4), (-0.52, -0.3, 3.36), (-0.55, -0.3, 3.25)],
        0.05,
        8,
        FRAME,
    )
    # Ladder on +X: rails bending over onto the dome, rungs.
    for sy in (-0.2, 0.2):
        tube(p, [(1.13, sy, -0.3), (1.13, sy, 2.95), (1.0, sy, 3.2), (0.7, sy, 3.25)], 0.025, 6, FRAME)
        for z in (1.0, 2.6):
            p.thin(p.rod((0.93, sy, z), (1.13, sy, z), 0.018, 6, FRAME))
    for k in range(10):
        z = 0.3 + k * 0.29
        p.thin(p.rod((1.13, -0.2, z), (1.13, 0.2, z), 0.017, 6, FRAME))
    # Outlet under the bottom dome, through a valve, into the ground; a side pipe down the -X side.
    tube(
        p,
        [(0, 0, 0.45), (0, 0, 0.2), (-0.1, 0, 0.16), (-1.05, 0, 0.16), (-1.15, 0, 0.08), (-1.15, 0, -0.3)],
        0.07,
        10,
        DECK,
    )
    p.box((-0.6, 0, 0.16), (0.22, 0.2, 0.22), mi=FRAME)
    p.thin(p.rod((-0.6, 0, 0.27), (-0.6, 0, 0.45), 0.02, 6, FRAME))
    p.cyl((-0.6, 0, 0.46), 0.16, 0.035, 12, mi=AMBER)
    tube(
        p,
        [(-0.66, -0.66, 2.2), (-0.86, -0.76, 2.2), (-0.92, -0.8, 2.12), (-0.92, -0.8, 0.1), (-0.92, -0.8, -0.3)],
        0.055,
        8,
        DECK,
    )
    p.cyl((-0.92, -0.8, 1.4), 0.09, 0.14, 10, mi=FRAME)
    return p.finish()


def mast() -> bpy.types.Object:
    """Mast: a 7 m comms mast: a three-chord lattice tower on a steel footing, a dish and two panel antennas, a
    cross arm and whips on a top pole, a small red marker light at the top (its own faces, glowing), an equipment
    cabinet at the foot, three guy wires to ground anchors 2.6 m out (at 0, 120 and 240 degrees)."""
    p = KPart("Mast", bevel=(0.015, 2))
    p.box((0, 0, -0.15), (1.0, 1.0, 0.5), rz(15), mi=FRAME)
    top = 5.9

    def chord(i: int, z: float) -> Vector:
        a = math.radians(90 + 120 * i)
        r = 0.32 - 0.12 * (z - 0.1) / (top - 0.1)
        return Vector((r * math.cos(a), r * math.sin(a), z))

    for i in range(3):
        p.thin(p.rod(chord(i, 0.1), chord(i, top), 0.045, 8, FRAME))
    levels = [0.1 + k * (top - 0.1) / 8 for k in range(9)]
    for k, z in enumerate(levels):
        for i in range(3):
            j = (i + 1) % 3
            if k > 0:
                p.thin(p.rod(chord(i, z), chord(j, z), 0.02, 4, FRAME))
            if k < 8:
                a, b = (i, j) if k % 2 == 0 else (j, i)
                p.thin(p.rod(chord(a, z), chord(b, levels[k + 1]), 0.018, 4, FRAME))
    p.cyl((0, 0, top + 0.03), 0.3, 0.06, 12, mi=FRAME)
    p.thin(p.rod((0, 0, top), (0, 0, 6.82), 0.055, 10, FRAME))
    p.thin(p.rod((-0.55, 0, 6.35), (0.55, 0, 6.35), 0.03, 6, FRAME))
    for sx in (-0.5, 0.5):
        p.thin(p.rod((sx, 0, 5.85), (sx, 0, 6.6), 0.014, 4, HAB))
    p.thin(p.rod((0.16, 0.05, top), (0.16, 0.05, 7.3), 0.012, 4, FRAME))
    p.thin(p.rod((-0.12, -0.1, top), (-0.12, -0.1, 7.05), 0.012, 4, FRAME))
    p.thin(p.cyl((0, 0, 6.85), 0.075, 0.06, 10, mi=FRAME))
    lathe(p, [(6.88, 0.0), (6.88, 0.065), (6.95, 0.065), (6.99, 0.035), (7.0, 0.0)], 10, LAMP_RED)
    # Dish on the +X side, looking out and a little up; panel antennas on the other chords.
    m = T(
        (0.62, -0.05, 4.7),
        C.basis(Vector((math.cos(math.radians(-10)), math.sin(math.radians(-10)), 0.3)), Vector((0, 0, 1))),
    )
    dish = [
        (-0.16, 0),
        (-0.13, 0.22),
        (-0.06, 0.42),
        (0.04, 0.56),
        (0.06, 0.57),
        (-0.03, 0.42),
        (-0.1, 0.22),
        (-0.12, 0),
    ]
    lathe(p, dish, 20, HAB, m)
    p.thin(p.rod(m @ Vector((0, 0, -0.14)), m @ Vector((0, 0, 0.42)), 0.02, 6, FRAME))
    p.cyl(m @ Vector((0, 0, 0.45)), 0.05, 0.08, 8, m.to_3x3(), FRAME)
    p.thin(p.rod(m @ Vector((0, 0, -0.15)), chord(0, 4.7) * Vector((0.6, 0.6, 1.0)), 0.035, 6, FRAME))
    for i in (1, 2):
        c = chord(i, 5.3)
        out = Vector((c.x, c.y, 0)).normalized()
        p.box(c + out * 0.1, (0.16, 0.07, 0.9), rz(math.degrees(math.atan2(out.y, out.x)) + 90), mi=HAB)
    # Cabinet at the foot, a conduit into the tower.
    p.box((0.1, -0.9, 0.38), (0.7, 0.42, 1.36), mi=CARGO)
    p.box((0.1, -0.9, 1.08), (0.8, 0.5, 0.05), mi=FRAME)
    p.box((0.3, -1.115, 0.6), (0.2, 0.012, 0.3), mi=DARK)
    stencil(p, "3", (-0.12, -1.11, 0.25), (1, 0, 0), (0, 0, 1), 0.3)
    tube(p, [(0.1, -0.7, 0.9), (0.1, -0.45, 0.9), (0.05, -0.2, 1.0), (0.0, -0.1, 1.2)], 0.035, 6, FRAME)
    # Guy wires and anchors.
    for a in (0, 120, 240):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        anchor = d * 2.6
        tube(p, [d * 0.22 + Vector((0, 0, 5.0)), anchor + Vector((0, 0, 0.2))], 0.012, 4, DECK, caps=False)
        p.box(anchor + Vector((0, 0, -0.15)), (0.32, 0.32, 0.6), rz(a), mi=FRAME)
        p.thin(p.rod(anchor + Vector((0, 0, 0.15)), anchor + Vector((0, 0, 0.24)), 0.03, 6, FRAME))
    return p.finish()


def landing_pad() -> bpy.types.Object:
    """Landing_pad: a 9.1 m landing pad only 0.2 m high: a deck of steel plates (faded amber circle and cross,
    soot in the middle) in a gunmetal ring frame with a bevelled outer edge to walk over, twelve small embedded
    lights (glowing dots) on the frame, a skirt 0.3 m into the ground."""
    p = KPart("Landing_pad", bevel=(0.02, 2))
    seg = 48
    lathe_open(p, [(-0.3, 3.88), (-0.3, 4.56), (0.0, 4.56), (0.2, 4.24), (0.2, 3.9)], seg, FRAME)
    lathe_open(p, [(0.198, 3.93), (0.198, 2.6), (0.198, 1.3), (0.198, 0.0)], seg, PAD, split_flat=False)
    for k in range(12):
        a = math.radians(k * 30 + 15)
        c = Vector((math.cos(a), math.sin(a), 0)) * 4.06
        p.thin(p.cyl(c + Vector((0, 0, 0.205)), 0.1, 0.02, 10, mi=FRAME))
        p.thin(p.cyl(c + Vector((0, 0, 0.215)), 0.06, 0.02, 8, mi=LAMP_PAD))
    # Four tie-down plates on the deck.
    for k in range(4):
        a = math.radians(k * 90 + 45)
        c = Vector((math.cos(a), math.sin(a), 0)) * 3.3
        p.thin(p.box(c + Vector((0, 0, 0.205)), (0.3, 0.3, 0.02), rz(k * 90 + 45), mi=FRAME))
        p.thin(p.box(c + Vector((0, 0, 0.225)), (0.06, 0.2, 0.03), rz(k * 90 + 45), mi=FRAME))
    return p.finish()


POD_Z = 1.1  # the pod's axis above the ground (its 1.25 m hull sinks 0.15 m into the ground)


def survival_pod() -> bpy.types.Object:
    """Survival_pod: an escape pod lying on the ground (3.6 m long, 2.5 m across, 2.4 m high), its axis along X,
    the charred heat shield at -X dug in, the nose lifted 4 degrees: a rounded bone hull with soot streaming back
    from the shield, an amber stripe and two frame bands, an open hatch on the -Y side (dark inside, the hatch door
    swung out on its hinge), a porthole, nose thrusters, grab rails and an antenna on top."""
    p = KPart("Survival_pod", bevel=(0.015, 2))
    m = T((0, 0, POD_Z), ry(-4))
    hull = [
        (-1.5, 1.2),
        (-1.3, 1.25),
        (0.5, 1.25),
        (0.95, 1.17),
        (1.3, 1.0),
        (1.55, 0.75),
        (1.7, 0.45),
        (1.76, 0.2),
        (1.77, 0),
    ]
    lathe_open(p, hull, 20, POD, m, "x")
    lathe_open(
        p, [(-1.88, 0), (-1.86, 0.55), (-1.8, 0.95), (-1.68, 1.17), (-1.52, 1.25), (-1.42, 1.25)], 20, SHIELD, m, "x"
    )
    hoop(p, -1.1, -0.75, 1.24, 1.272, 20, AMBER, m, "x")
    hoop(p, -1.36, -1.26, 1.24, 1.29, 20, FRAME, m, "x")
    hoop(p, 0.42, 0.52, 1.23, 1.285, 20, FRAME, m, "x")
    # Hatch: dark opening, a striped frame, the door swung out on its front edge.
    x0, x1, a0, a1 = -0.5, 0.32, 128, 184
    sector(p, x0, x1, 1.24, 1.256, a0, a1, 6, DARK, m)
    sector(p, x0 - 0.07, x1 + 0.07, 1.24, 1.31, a0 - 6, a0, 6, HAZ, m)
    sector(p, x0 - 0.07, x1 + 0.07, 1.24, 1.31, a1, a1 + 6, 6, HAZ, m)
    sector(p, x0 - 0.07, x0, 1.24, 1.31, a0, a1, 6, HAZ, m)
    sector(p, x1, x1 + 0.07, 1.24, 1.31, a0, a1, 6, HAZ, m)

    def on_hull(x: float, a: float, r: float) -> Vector:
        return Vector((x, r * math.cos(math.radians(a)), r * math.sin(math.radians(a))))

    ha, hb = on_hull(x1 + 0.05, a0, 1.3), on_hull(x1 + 0.05, a1, 1.3)
    swing = T(ha) @ Matrix.Rotation(math.radians(-105), 4, (hb - ha).normalized()) @ T(-ha)
    door = m @ swing
    sector(p, x0 + 0.02, x1 - 0.02, 1.26, 1.32, a0 + 1, a1 - 1, 6, POD, door)
    sector(p, x0 + 0.12, x1 - 0.12, 1.255, 1.262, a0 + 8, a1 - 8, 4, FRAME, door)
    for a in (a0 + 10, a1 - 10):
        p.thin(p.rod(door @ on_hull(x1 + 0.0, a, 1.3), m @ on_hull(x1 + 0.08, a, 1.3), 0.025, 6, FRAME))
    # Porthole near the nose, thrusters, grab rails, antenna.
    port = on_hull(0.78, 160, 1.19)
    rot = C.basis(Vector((0, math.cos(math.radians(160)), math.sin(math.radians(160)))), Vector((1, 0, 0)))
    p.cyl(m @ port, 0.2, 0.08, 14, m.to_3x3() @ rot, FRAME)
    p.cyl(m @ (port + rot.col[2] * 0.035), 0.14, 0.03, 14, m.to_3x3() @ rot, GLASS)
    for a in (45, 135, 225, 315):
        base = on_hull(1.32, a, 0.92)
        out = on_hull(1.26, a, 1.04)
        p.thin(p.rod(m @ base, m @ out, 0.05, 8, FRAME, r2=0.08))
    for a in (72, 108):
        pts = [on_hull(-0.9, a, 1.24), on_hull(-0.9, a, 1.36), on_hull(0.2, a, 1.36), on_hull(0.2, a, 1.24)]
        tube(p, [m @ q for q in pts], 0.022, 6, FRAME)
    p.thin(p.rod(m @ on_hull(0.9, 95, 1.15), m @ on_hull(0.9, 95, 1.9), 0.015, 4, FRAME))
    p.cyl(m @ on_hull(0.9, 95, 1.17), 0.07, 0.08, 8, m.to_3x3() @ C.basis(Vector((0, 0, 1)), Vector((1, 0, 0))), FRAME)
    return p.finish()


def expedition_mast() -> bpy.types.Object:
    """Expedition_mast: a light portable beacon mast (4 m): a telescoping steel pole with amber locking collars in
    a tripod (legs at 90, 210 and 330 degrees, 0.95 m out), a lamp housing at the top with a cage around the
    lens's place (the lens is the separate Expedition_lens, its center 3.75 m up), a cable down to a battery case
    on the ground."""
    p = KPart("Expedition_mast", bevel=(0.01, 2))
    p.thin(p.rod((0, 0, -0.3), (0, 0, 1.7), 0.045, 10, DECK))
    p.thin(p.rod((0, 0, 1.6), (0, 0, 2.8), 0.036, 10, DECK))
    p.thin(p.rod((0, 0, 2.7), (0, 0, 3.6), 0.028, 10, DECK))
    p.thin(p.cyl((0, 0, 1.66), 0.062, 0.09, 10, mi=AMBER))
    p.thin(p.cyl((0, 0, 2.76), 0.05, 0.08, 10, mi=AMBER))
    p.thin(p.cyl((0, 0, 1.1), 0.075, 0.14, 10, mi=FRAME))
    for a in (90, 210, 330):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        top = d * 0.07 + Vector((0, 0, 1.08))
        foot = d * 0.95
        leg = foot - top
        p.thin(p.rod(top, top + leg * (1.38 / 1.08), 0.024, 6, FRAME))
        p.thin(p.box(foot + Vector((0, 0, 0.015)), (0.14, 0.14, 0.03), rz(a), mi=FRAME))
        mid = top + leg * (0.63 / 1.08)
        p.thin(p.rod(Vector((0, 0, 0.45)) + d * 0.04, mid, 0.012, 4, FRAME))
    # Lamp housing: base, cage bars, cap; the lens sits between z 3.65 and 3.85.
    p.thin(p.cyl((0, 0, 3.6), 0.125, 0.1, 12, mi=FRAME))
    for k in range(4):
        a = math.radians(45 + 90 * k)
        c = Vector((math.cos(a), math.sin(a), 0)) * 0.128
        p.thin(p.rod(c + Vector((0, 0, 3.64)), c + Vector((0, 0, 3.87)), 0.012, 4, FRAME))
    p.thin(p.cyl((0, 0, 3.885), 0.135, 0.05, 12, mi=FRAME))
    p.thin(p.cyl((0, 0, 3.93), 0.035, 0.05, 8, mi=FRAME))
    # Cable and battery case.
    tube(
        p,
        [(0.05, 0.0, 3.55), (0.05, 0.0, 1.25), (0.12, -0.05, 0.9), (0.3, -0.2, 0.45), (0.42, -0.3, 0.36)],
        0.014,
        5,
        RUBBER,
    )
    p.box((0.52, -0.38, 0.12), (0.5, 0.3, 0.44), rz(-30), mi=CARGO)
    p.box((0.52, -0.38, 0.345), (0.52, 0.32, 0.03), rz(-30), mi=FRAME)
    p.thin(p.box((0.52, -0.38, 0.39), (0.22, 0.03, 0.05), rz(-30), mi=FRAME))
    return p.finish()


def expedition_lens() -> bpy.types.Object:
    """Expedition_lens: the beacon's glowing amber lens (0.21 m across, 0.2 m high), origin at its own center; the
    game blinks it (BeaconLight) and places it 3.75 m above the expedition mast's origin."""
    p = KPart("Expedition_lens", bevel=(0.005, 1))
    prof = [(-0.1, 0), (-0.1, 0.085), (-0.06, 0.1), (0.0, 0.106), (0.06, 0.1), (0.1, 0.085), (0.1, 0)]
    lathe(p, prof, 14, LAMP_AMBER)
    return p.finish()


SHELTER_CABLE_END = (3.95, -0.52)  # where the cable ends: next to the work light's foot in the camp's layout


def shelter() -> bpy.types.Object:
    """Shelter: Hollis' prefab two-person field shelter (3.6 x 2.6 m body, 2.75 m high): bone panels with ribs on
    skids, a dark mono-pitch roof with a vent stack and an antenna, a door with an amber-striped frame on the -Y
    side under a canvas awning on two poles, a warm lit window (dim glow), a dark window at the back, a tool rack
    with a shovel, a pick and a pry bar on the -X end, a power box on the +X end with a cable along the ground to
    the work light (ends at SHELTER_CABLE_END)."""
    p = KPart("Shelter", bevel=(0.03, 2))
    hl, hd, zb, zt = 1.8, 1.3, 0.25, 2.45
    p.box((0, 0, (zb + zt) / 2), (2 * hl, 2 * hd, zt - zb), mi=CAMP)
    for x in (-0.9, 0.0, 0.9):
        for sy in (-1, 1):
            if sy < 0 and x == 0.0:
                continue
            p.box((x, sy * hd, (zb + zt) / 2), (0.1, 0.05, zt - zb), mi=CAMP)
    for sx in (-1, 1):
        p.box((sx * hl, 0, (zb + zt) / 2), (0.05, 0.1, zt - zb), mi=CAMP)
    roof = [(-hd - 0.15, zt), (hd + 0.15, zt), (hd + 0.15, 2.74), (-hd - 0.15, 2.58)]
    p.prism(roof, -hl - 0.18, hl + 0.18, m=MX, mi=FRAME)
    slope = math.degrees(math.atan2(0.16, 2 * hd + 0.3))

    def roof_z(y: float) -> float:
        return 2.66 + 0.16 / (2 * hd + 0.3) * y

    for k in range(9):  # standing seams down the slope
        x = -hl - 0.18 + (k + 0.5) * (2 * hl + 0.36) / 9
        p.beam(
            (x, -hd - 0.15, roof_z(-hd - 0.15) + 0.02),
            (x, hd + 0.15, roof_z(hd + 0.15) + 0.02),
            0.05,
            0.05,
            (0, 0, 1),
            mi=FRAME,
        )
    # A solar panel on short legs and a water tank lying on the roof.
    p.box((-0.75, -0.2, roof_z(-0.2) + 0.16), (1.5, 1.05, 0.05), rx(slope + 8), mi=FRAME)
    p.box((-0.75, -0.2, roof_z(-0.2) + 0.19), (1.38, 0.93, 0.02), rx(slope + 8), mi=GLASS)
    for dx in (-0.6, 0.6):
        for dy in (-0.35, 0.35):
            p.thin(
                p.rod(
                    (-0.75 + dx, -0.2 + dy, roof_z(-0.2 + dy)),
                    (-0.75 + dx, -0.2 + dy, roof_z(-0.2 + dy) + 0.15),
                    0.02,
                    4,
                    FRAME,
                )
            )
    lathe(
        p,
        [(-0.55, 0), (-0.55, 0.22), (-0.5, 0.3), (0.5, 0.3), (0.55, 0.22), (0.55, 0)],
        14,
        CARGO,
        T((1.15, 0.85, roof_z(0.85) + 0.33)),
        "x",
    )
    for dx in (-0.3, 0.3):
        p.box((1.15 + dx, 0.85, roof_z(0.85) + 0.07), (0.08, 0.5, 0.14), mi=FRAME)
    for sy in (-1, 1):
        p.box((0, sy * 0.9, -0.05), (2 * hl + 0.3, 0.2, 0.6), mi=FRAME)
    door(p, 1.0, hd, zb, open_=False, h=1.95)
    window(p, -0.75, -1, hd, 1.65, mi=LAMP_WIN, w=0.9, h=0.45)
    window(p, 0.4, 1, hd, 1.65, w=0.8, h=0.4)
    stencil(p, "12", (-1.55, -hd, 0.55), (1, 0, 0), (0, 0, 1), 0.35)
    # Awning over the door.
    p.box((1.0, -hd - 0.66, 2.29), (1.8, 1.36, 0.03), rx(10), mi=TARP)
    p.thin(p.rod((0.1, -hd - 1.32, 2.17), (1.9, -hd - 1.32, 2.17), 0.025, 6, FRAME))
    for x in (0.12, 1.88):
        p.thin(p.rod((x, -hd - 1.32, -0.3), (x, -hd - 1.32, 2.2), 0.028, 6, FRAME))
    # Roof: vent stack, antenna.
    p.thin(p.rod((0.8, 0.6, 2.6), (0.8, 0.6, 3.05), 0.07, 10, FRAME))
    p.cyl((0.8, 0.6, 3.08), 0.14, 0.06, 10, mi=FRAME)
    p.thin(p.rod((-1.4, 0.95, 2.66), (-1.4, 0.95, 3.6), 0.015, 4, FRAME))
    # Tool rack on the -X end.
    for y in (-0.65, 0.65):
        p.box((-hl - 0.1, y, 1.1), (0.06, 0.06, 1.5), mi=FRAME)
    for z in (0.95, 1.7):
        p.thin(p.rod((-hl - 0.16, -0.72, z), (-hl - 0.16, 0.72, z), 0.022, 6, FRAME))
    p.thin(p.rod((-hl - 0.42, -0.4, 0.02), (-hl - 0.22, -0.44, 1.78), 0.022, 6, AMBER))
    p.box((-hl - 0.43, -0.4, 0.17), (0.04, 0.24, 0.3), ry(-6), mi=DECK)
    p.thin(p.rod((-hl - 0.4, 0.12, 0.02), (-hl - 0.22, 0.08, 1.6), 0.024, 6, AMBER))
    p.beam((-hl - 0.24, -0.15, 1.56), (-hl - 0.2, 0.32, 1.62), 0.06, 0.05, (0, 0, 1), mi=FRAME, taper=0.4)
    p.thin(p.rod((-hl - 0.35, 0.45, 0.0), (-hl - 0.22, 0.5, 1.45), 0.018, 6, DECK))
    # Power box on the +X end and the cable to the work light.
    p.box((hl + 0.12, -0.6, 0.9), (0.22, 0.5, 0.6), mi=FRAME)
    p.box((hl + 0.235, -0.6, 1.0), (0.01, 0.3, 0.15), mi=AMBER)
    cx, cy = SHELTER_CABLE_END
    cable = [(hl + 0.15, -0.6, 0.6), (hl + 0.18, -0.6, 0.15), (hl + 0.3, -0.63, 0.035), (2.6, -0.45, 0.035)]
    cable += [(3.1, -0.62, 0.035), (3.5, -0.5, 0.035), (cx, cy, 0.035)]
    tube(p, cable, 0.03, 6, RUBBER)
    return p.finish()


def drill_tripod() -> bpy.types.Object:
    """Drill_tripod: a survey drill tripod (3.1 m): three gunmetal legs (at 90, 210 and 330 degrees, feet 1.05 m
    out) on foot plates, a head with a sheave, a ring of struts, the drill's olive motor housing (amber-striped)
    hanging from the head over the middle, the drill string down into a casing in the ground, two hoses down to
    the ground and out between the legs (towards +X+Y) in loose loops."""
    p = KPart("Drill_tripod", bevel=(0.015, 2))
    apex = Vector((0, 0, 3.0))
    feet = []
    for a in (90, 210, 330):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        top = apex + d * 0.1 - Vector((0, 0, 0.08))
        foot = d * 1.05
        leg = foot - top
        p.thin(p.rod(top, top + leg * ((top.z + 0.3) / top.z), 0.05, 8, FRAME))
        p.box(foot + Vector((0, 0, 0.02)), (0.26, 0.26, 0.04), rz(a), mi=FRAME)
        feet.append(top + leg * (2.0 / top.z))
    for a, b in zip(feet, feet[1:] + feet[:1]):
        p.thin(p.rod(a, b, 0.025, 6, FRAME))
    p.box(apex, (0.34, 0.34, 0.26), mi=FRAME)
    p.thin(p.cyl(apex + Vector((0, 0, 0.2)), 0.17, 0.06, 14, rx(90), FRAME))
    p.thin(p.rod(apex + Vector((0, -0.05, 0.2)), apex + Vector((0, 0.05, 0.2)), 0.03, 6, FRAME))
    p.thin(p.rod((0, 0, 2.9), (0, 0, 2.05), 0.014, 4, DECK))
    # Motor housing, its motor and the drill string.
    p.box((0, 0, 1.75), (0.5, 0.45, 0.55), mi=CARGO)
    p.box((0, 0, 1.52), (0.52, 0.47, 0.09), mi=HAZ)
    p.box((0, 0, 2.05), (0.16, 0.16, 0.08), mi=FRAME)
    p.cyl((0.32, 0, 1.85), 0.15, 0.36, 14, ry(90), FRAME)
    p.cyl((0.51, 0, 1.85), 0.12, 0.04, 14, ry(90), DARK)
    p.thin(p.rod((0, 0, 1.475), (0, 0, -0.5), 0.042, 10, DECK))
    p.thin(p.cyl((0, 0, 0.0), 0.11, 0.26, 12, mi=FRAME))
    p.thin(p.cyl((0, 0, 0.6), 0.08, 0.12, 10, mi=FRAME))
    # Hoses down to the ground and out between the legs.
    h = 0.035
    tube(
        p,
        [
            (0.22, 0.12, 1.65),
            (0.42, 0.24, 1.35),
            (0.58, 0.34, 0.8),
            (0.68, 0.4, 0.3),
            (0.82, 0.48, h + 0.02),
            (1.5, 0.8, h),
            (2.0, 0.72, h),
            (2.15, 0.35, h),
            (1.85, 0.12, h),
            (1.45, 0.28, h),
        ],
        0.035,
        6,
        RUBBER,
    )
    tube(
        p,
        [
            (0.22, -0.05, 1.6),
            (0.45, 0.06, 1.25),
            (0.62, 0.2, 0.6),
            (0.76, 0.3, h + 0.04),
            (1.0, 0.36, h),
            (1.35, 0.52, h),
            (1.7, 0.98, h),
        ],
        0.03,
        6,
        RUBBER,
    )
    p.thin(p.cyl((1.74, 1.04, 0.045), 0.05, 0.12, 8, C.basis(Vector((0.6, 0.8, 0)), Vector((0, 0, 1))), FRAME))
    return p.finish()


def drill_plate() -> bpy.types.Object:
    """Drill_plate: a 1.6 x 1.6 m steel base plate, 5 cm thick, with a collar around the dark bore hole in the
    middle, bolts at the corners and two lifting lugs; a skirt 0.15 m below ground."""
    p = KPart("Drill_plate", bevel=(0.012, 2))
    p.box((0, 0, 0.025), (1.6, 1.6, 0.05), mi=DECK)
    p.box((0, 0, -0.075), (1.5, 1.5, 0.15), mi=DECK)
    hoop(p, 0.05, 0.09, 0.14, 0.21, 16, FRAME)
    p.thin(p.cyl((0, 0, 0.052), 0.15, 0.01, 16, mi=DARK))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.thin(p.cyl((sx * 0.68, sy * 0.68, 0.06), 0.035, 0.03, 6, mi=FRAME))
        p.box((sx * 0.62, 0, 0.08), (0.06, 0.18, 0.06), mi=FRAME)
    return p.finish()


BUILDERS = {
    "Module_a": module_a,
    "Module_b": module_b,
    "Tank": tank,
    "Mast": mast,
    "Landing_pad": landing_pad,
    "Survival_pod": survival_pod,
    "Expedition_mast": expedition_mast,
    "Expedition_lens": expedition_lens,
    "Shelter": shelter,
    "Drill_tripod": drill_tripod,
    "Drill_plate": drill_plate,
}


# --- part layouts (Godot axes: x, y up, z; rotation about Y in degrees) -----------------------------------

# The pieces as the map parts would place them, with stand-ins for the other kits' pieces (the field kit's crates,
# supplies, spool and stakes, the old miner) and the greybox's markers, inside the part's prop_radius.
LAYOUTS = {
    "outpost": {
        "radius": 11.0,
        "pieces": [
            ("Module_a", (-5.4, 0, 2.0), 90),
            ("Module_a", (0.4, 0, 6.8), 180),
            ("Module_b", (5.8, 0, 1.6), -100),
            ("Tank", (-5.6, 0, 7.8), 30),
            ("Mast", (6.6, 0, -4.4), 0),
            ("Landing_pad", (0.6, 0, -5.4), 0),
        ],
        "boxes": [],
        "markers": [("crate", (-4.4, 0, -3.4))],
        "pole": (2.4, 0, 0.6),
    },
    "expedition_camp": {
        "radius": 5.0,
        "pieces": [
            ("Survival_pod", (-0.4, 0, 1.4), 210),
            ("Expedition_mast", (2.6, 0, -1.4), 0),
            ("Expedition_lens", (2.6, LENS_HEIGHT, -1.4), 0),
        ],
        "boxes": [((2.6, 0.3, 2.6), (0.8, 0.6, 0.6), 15), ((3.2, 0.25, 1.7), (0.6, 0.5, 0.6), -25)],
        "markers": [("quest", (-2.4, 0, -2.6))],
        "pole": (0.6, 0, -1.2),
    },
    "hollis_camp": {
        "radius": 8.0,
        "pieces": [("Shelter", (3.6, 0, 2.6), 195)],
        "boxes": [
            ((-0.6, 1.4, 3.2), (0.15, 2.8, 0.15), 0),
            ((5.4, 0.35, -0.6), (1.0, 0.7, 0.7), -20),
            ((5.3, 0.95, -0.5), (0.6, 0.5, 0.6), 30),
            ((6.1, 0.45, 0.8), (0.6, 0.9, 0.6), 0),
            ((-3.7, 1.2, -0.6), (2.0, 2.4, 3.0), 35),
            ((1.4, 1.0, 3.6), (0.24, 2.0, 0.24), 0),
        ],
        "markers": [("person", (1.2, 0, -1.6)), ("quest", (0, 0, 0))],
        "pole": (2.6, 0, -2.4),
    },
    "hollis_dig_site": {
        "radius": 6.0,
        "pieces": [("Drill_plate", (4.5, 0, 1.2), 110), ("Drill_tripod", (4.5, 0, 1.2), 110)],
        "boxes": [
            ((-3.4, 0.45, 2.2), (0.5, 0.9, 0.9), 0),
            ((-4.3, 0.45, -1.8), (1.6, 1.1, 1.3), 30),
            ((2.6, 0.45, -3.4), (0.08, 0.9, 0.08), 0),
            ((-2.2, 0.45, 3.9), (0.08, 0.9, 0.08), 0),
        ],
        "markers": [("ore", (2.2, 0, 2.6)), ("nest", (-1.2, 0, -1.0))],
        "pole": (1.0, 0, -2.6),
    },
}
MARKER_LOOK = {  # radius, emission color
    "crate": (0.5, (1.0, 0.55, 0.1)),
    "quest": (0.5, (0.8, 0.9, 1.0)),
    "person": (0.35, (0.4, 1.0, 0.4)),
    "ore": (1.35, (0.1, 0.9, 0.85)),
    "nest": (1.0, (1.0, 0.15, 0.1)),
}


def godot_to_blender(pos) -> Vector:
    return Vector((pos[0], -pos[2], pos[1]))


def _flat_mat(name: str, color, emission: float = 0.0) -> bpy.types.Material:
    mat, _nt, bsdf = C._new_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def _preview_mesh(name: str, bm: bmesh.types.BMesh, mat) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    C.link(obj, None, "Preview")
    me.materials.append(mat)
    return obj


def layout_scene(name: str) -> list:
    """Place the part's pieces (linked duplicates), stand-ins, markers, a 1.89 m pole and the prop_radius ring;
    dim the preview lights for a weak low sun and a little sky. Returns what to remove afterwards."""
    spec = LAYOUTS[name]
    made = []
    for piece, pos, rot in spec["pieces"]:
        d = bpy.data.objects[piece].copy()
        C.collection("Preview").objects.link(d)
        d.hide_render = False
        d.location = godot_to_blender(pos)
        d.rotation_mode = "XYZ"
        d.rotation_euler = (0, 0, math.radians(rot))
        made.append(d)
    stand_in = _flat_mat("LayoutStandIn", (0.09, 0.085, 0.08))
    for k, (pos, size, rot) in enumerate(spec["boxes"]):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=T((0, 0, 0), None, (size[0], size[2], size[1])))
        o = _preview_mesh(f"LayoutBox{k}", bm, stand_in)
        o.location = godot_to_blender(pos)
        o.rotation_euler = (0, 0, math.radians(rot))
        made.append(o)
    for k, (kind, pos) in enumerate(spec["markers"]):
        r, col = MARKER_LOOK[kind]
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=True, segments=32, radius=r)
        o = _preview_mesh(f"LayoutMarker{k}", bm, _flat_mat(f"Marker_{kind}", col, 1.5))
        o.location = godot_to_blender(pos) + Vector((0, 0, 0.02))
        made.append(o)
    bm = bmesh.new()
    outer = bmesh.ops.create_circle(bm, segments=96, radius=spec["radius"] + 0.06)["verts"]
    inner = bmesh.ops.create_circle(bm, segments=96, radius=spec["radius"] - 0.06)["verts"]
    for i in range(96):
        j = (i + 1) % 96
        bm.faces.new((inner[i], inner[j], outer[j], outer[i]))
    o = _preview_mesh("LayoutRing", bm, _flat_mat("LayoutRing", (0.9, 0.9, 0.9), 0.6))
    o.location = (0, 0, 0.02)
    made.append(o)
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, segments=10, radius1=0.05, radius2=0.05, depth=1.89, matrix=T((0, 0, 0.945))
    )
    o = _preview_mesh("LayoutPole", bm, _flat_mat("LayoutPole", (0.9, 0.85, 0.7), 0.8))
    o.location = godot_to_blender(spec["pole"])
    made.append(o)
    for o in C.collection("Preview").objects:
        if o.type == "LIGHT":
            o.hide_render = True
    sun = bpy.data.lights.new("LayoutSun", "SUN")
    sun.energy = 3.0
    sun.color = (0.8, 0.87, 1.0)
    sun.angle = math.radians(2)
    so = bpy.data.objects.new("LayoutSun", sun)
    C.link(so, None, "Preview")
    so.rotation_euler = (math.radians(55), 0, math.radians(-45))
    made.append(so)
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.03, 0.036, 0.048, 1.0)
    return made


def layout_restore(made: list) -> None:
    for o in made:
        bpy.data.objects.remove(o)
    for o in C.collection("Preview").objects:
        if o.type == "LIGHT":
            o.hide_render = False
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.014, 0.018, 1.0)


def render_layout(name: str, path: pathlib.Path, samples: int, size: int, hide: list) -> pathlib.Path:
    """The part from the game's angle: camera pitched 50 degrees down from the +X/-Y diagonal, far enough to see
    the whole prop_radius."""
    for o in hide:
        o.hide_render = True
    made = layout_scene(name)
    r = LAYOUTS[name]["radius"]
    target = Vector((0, 0, 0.8))
    pitch = math.radians(50)
    direction = Vector((math.cos(pitch) * math.sqrt(0.5), -math.cos(pitch) * math.sqrt(0.5), math.sin(pitch)))
    location = target + direction * (r + 2.0) * 2.9
    C.render_from(path, location, target, lens=50, samples=samples, size=size)
    layout_restore(made)
    for o in hide:
        o.hide_render = False
    return path


# --- previews, renders ----------------------------------------------------------------------------------


def setup_preview() -> None:
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in PIECES]


def render_piece(name: str, prefix: str, views, samples: int, size: int, objs: list | None = None) -> list:
    """The piece alone at the origin (the expedition mast with its lens), framed by its size, the 1.8 m scale
    figure beside it."""
    objs = objs or kit_objects()
    obj = bpy.data.objects[name]
    shown = {name, "Expedition_lens"} if name == "Expedition_mast" else {name}
    saved = {o.name: (o.location.copy(), o.rotation_euler.copy()) for o in objs}
    for o in objs:
        o.hide_render = o.name not in shown
        o.rotation_euler = (0, 0, 0)
    obj.location = (0, 0, 0)
    if name == "Expedition_mast":
        bpy.data.objects["Expedition_lens"].location = (0, 0, LENS_HEIGHT)
    bpy.context.view_layer.update()
    dx, dy, dz = obj.dimensions
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
    fig_loc = fig.location.copy()
    fig.location = side * (max(dx, dy) / 2 + 0.55)
    w = max(dx, dy, dz * 1.1) * 1.3 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.4, dz * 0.42)))
    out = []
    for view in views:
        path = OUT / f"{prefix}{name}_{view}.png"
        zoom = w / (9.9 if view == "iso" else 6.3)
        C.render(path, view=view, samples=samples, size=size, target=tuple(target), zoom=zoom)
        out.append(path)
    fig.location = fig_loc
    for o in objs:
        o.hide_render = False
        o.location, o.rotation_euler = saved[o.name]
    return out


def apply_bake_layout(gap: float = 3.0) -> None:
    """Saved .blend layout: every piece unrotated in one row along X with `gap` m between them, so the AO bake
    never picks up a neighbor. The bake zeroes the locations before the export."""
    x = 0.0
    bpy.context.view_layer.update()
    for name in PIECES:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.location = (x + obj.dimensions.x / 2, 0, 0)
        x += obj.dimensions.x + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


def build() -> None:
    global MATERIALS
    MATERIALS = make_materials()
    for name in PIECES:
        BUILDERS[name]()


def report() -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for name in PIECES:
        obj = bpy.data.objects[name]
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        xs, ys, zs = ([v.co[i] for v in me.vertices] for i in range(3))
        size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        print(
            f"STATS {name}: tris={len(me.loop_triangles)} size={tuple(round(s, 2) for s in size)}"
            f" x=({min(xs):.2f}, {max(xs):.2f}) y=({min(ys):.2f}, {max(ys):.2f}) z=({min(zs):.2f}, {max(zs):.2f})"
        )
        ev.to_mesh_clear()
    print("STATS", C.stats())


def main() -> None:
    C.reset(ASSET)
    build()
    report()
    setup_preview()
    if MODE == "final":
        sheet = []
        for name in PIECES:
            if name != "Expedition_lens":
                sheet += render_piece(name, "final_", ("iso", "hero"), 32, 640)
        for name in LAYOUTS:
            sheet.append(render_layout(name, OUT / f"final_layout_{name}.png", 64, 1024, kit_objects()))
        C.contact_sheet(sheet, OUT / "sheet.png", cols=4, tile=480, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "structures_procedural.blend")
        return
    wip = OUT / "wip"
    for view in VIEWS:
        if view == "pieces":
            for name in PIECES:
                if name != "Expedition_lens":
                    render_piece(name, f"wip/{TAG}_", ("iso",), 20, 512)
        elif view in BUILDERS:
            render_piece(view, f"wip/{TAG}_", ("iso", "hero"), 24, 640)
        elif view in LAYOUTS:
            render_layout(view, wip / f"{TAG}_layout_{view}.png", 32, 900, kit_objects())
        elif view == "layouts":
            for name in LAYOUTS:
                render_layout(name, wip / f"{TAG}_layout_{name}.png", 32, 900, kit_objects())
        elif view == "sheet":
            names = sorted(wip.glob(f"{TAG}_*.png"))
            C.contact_sheet(names, wip / f"{TAG}_sheet.png", tile=384, background=0.02)
        elif view == "save":
            apply_bake_layout()
            C.save_blend(OUT / "structures_procedural.blend")
            return


if __name__ == "__main__":
    main()
