"""Field equipment kit: the small gear the colony leaves around its camps and caches. The interactive supply crate
(body, lid and light strip as three pieces), a small case, a strapped stack of cases, a standing and a lying drum,
a tarp tied down over a stack of supplies, a beacon pole with its separate lens, a tripod work light, a cable spool,
a survey stake and a survey repeller post.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/field/source/field_build.py wip f1                       # kit overview
    tools/blender.sh assets/parts/field/source/field_build.py wip f1 Crate,Barrel_a,layouts
    tools/blender.sh assets/parts/field/source/field_build.py final

Everything it writes goes to tmp/assets/parts/field/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: kit, pieces, a piece name, the groups Crate, Crate_open and Beacon, a part layout name or
layouts, sheet, save); "final" renders the kit, every piece (iso + hero), the groups and the part layouts, writes
the contact sheet sheet.png and saves the procedural field_procedural.blend that field_bake.py turns into the game
asset. In the .blend the pieces stand unrotated in a row along X, 1.5 m apart (no AO from a neighbor), the lid at
the height it has on the crate and the lens on its pole; the bake zeroes their locations.

Game contract (game/models/model_parts.gd): the game places each piece by name at the transform its part scene
gives it, so every piece is one mesh object at the kit's root (no parents), one material after the bake. Origins
sit at the ground contact (bottom center, z = 0) with SINK m of extra geometry below ground, except Crate_lid
(on its hinge line: the lid spans y 0..0.84, z 0..0.14 and sits at (0, -0.4, 0.6) of the crate, turning about X)
and Beacon_lens (its own center; it sits at (0, 0, LENS_Z) of the pole). The crate's front is +Y (the lid's latches
and the stencil face the player who opens it); the other pieces face -Y. Budgets (TBD (playtest)): small props
<= ~800 triangles, medium ones (the tarp, the stack, the spool, the work light, the poles) <= ~3k.

Look: weathered prefab gear, like the ship and Waypost Ostra: olive-grey cargo paint, dark gunmetal frames, off-white
on the lamp heads and the repeller, faded amber markings, chipped edges, rust runs, grime in recesses and dust on the
lower part, all low-contrast so it stays calm from the game camera. Only small lamps glow (the work light's lens,
the beacon's red lens, the repeller's status light), as separate faces in the emission map. Each look is its own
procedural material slot; the bake turns them into the kit's one material.
"""

import contextlib
import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "field"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils import noise as mnoise

import common as C
from common import T, rx, ry, rz, srgb

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "f0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["kit"]

ASSET = "Field"
SINK = 0.3  # geometry below ground (m) under the standing pieces
EMIT = 6.0  # emission strength of the lamps (the bake divides by it, the baked material multiplies by it)
LENS_Z = 3.105  # the beacon lens's center above the pole's origin
LID_AT = (0.0, -0.4, 0.6)  # the lid's hinge line in the crate's frame
LID_OPEN = 1.9  # radians about X, as crate.gd swings it
PARTS = [
    "Crate_base",
    "Crate_lid",
    "Crate_strip",
    "Crate_small",
    "Crate_stack",
    "Barrel_a",
    "Barrel_b",
    "Tarp_stack",
    "Beacon_pole",
    "Beacon_lens",
    "Work_light",
    "Cable_spool",
    "Stake",
    "Repeller_post",
]

# Looks, one procedural material each (index = material slot of every piece).
LOOKS = [
    "olive",
    "olive_worn",
    "gun",
    "bone",
    "amber",
    "hazard",
    "steel",
    "rubber",
    "tarp",
    "strap",
    "interior",
    "stencil",
    "strip",
    "lamp",
    "lens",
    "status",
    "cable",
]
(
    OLIVE,
    OLIVE_WORN,
    GUN,
    BONE,
    AMBER,
    HAZARD,
    STEEL,
    RUBBER,
    TARP,
    STRAP,
    INTERIOR,
    STENCIL,
    STRIP,
    LAMP,
    LENS,
    STATUS,
    CABLE,
) = range(len(LOOKS))
MATS: list = []


# --- material -----------------------------------------------------------------------------------------

STEEL_COL = srgb(0.40, 0.39, 0.38)
RUST_COL = srgb(0.34, 0.2, 0.11)
DUST_COL = srgb(0.33, 0.30, 0.26)
# look: (sRGB color, edge wear, rust runs, roughness)
PAINTS = {
    "olive": ((0.30, 0.31, 0.27), 0.6, 0.5, 0.62),
    "olive_worn": ((0.28, 0.29, 0.25), 1.0, 1.0, 0.68),
    "gun": ((0.16, 0.16, 0.17), 0.7, 0.4, 0.55),
    "bone": ((0.47, 0.46, 0.43), 0.5, 0.5, 0.6),
    "amber": ((0.62, 0.44, 0.15), 0.6, 0.3, 0.62),
    "interior": ((0.055, 0.055, 0.055), 0.0, 0.0, 0.85),
    "strip": ((0.75, 0.5, 0.18), 0.0, 0.0, 0.4),
    "strap": ((0.4, 0.32, 0.19), 0.0, 0.0, 0.85),
    "rubber": ((0.045, 0.045, 0.045), 0.0, 0.0, 0.85),
}
GLOWS = {"lamp": (1.0, 0.82, 0.6), "lens": (1.0, 0.12, 0.06), "status": (0.55, 0.9, 1.0)}


class Shader:
    """Node helpers for the kit's materials (numbers are set, sockets linked)."""

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

    def noise(self, scale: float, detail: float = 4.0, rough: float = 0.6, vector=None) -> bpy.types.NodeSocket:
        """Noise Fac (about 0.5 +- 0.09)."""
        return C._noise(self.nt, scale, detail, rough, vector if vector is not None else self.obj).outputs["Fac"]

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

    def rgb(self, color: tuple) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeRGB")
        node.outputs[0].default_value = (*color, 1.0)
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


def weather(s: Shader, col, wear: float, rust: float, dust: float, rough: float, metal: float = 0.0) -> tuple:
    """The shared wear on a base color socket: a large calm tone, grime in the recesses, rust runs down the sides,
    grey-brown dust on the lower part and in the recesses, paint chipped to steel on the edges. Returns
    (color, roughness, metallic, height) sockets."""
    nt = s.nt
    z = s.xyz(s.obj).outputs["Z"]
    nz = s.xyz(s.geo.outputs["Normal"]).outputs["Z"]
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.2
    ao.samples = 16
    cavity = s.m("SUBTRACT", 1.0, s.ramp(0.35, 0.95, ao.outputs["AO"]), clamp=True)
    tone = s.noise(1.3, 3.0, 0.5)
    col = s.scale_color(col, s.m("MULTIPLY_ADD", s.spread(tone, 3.0), 0.12, 0.94))
    col = s.mix(s.m("MULTIPLY", cavity, 0.55), col, s.scale_color(col, 0.45))
    if rust > 0:
        runs = s.ramp(0.57, 0.68, s.noise(1.0, 3.0, 0.5, s.vec("MULTIPLY", s.obj, (9.0, 9.0, 0.8))))
        side = s.m("SUBTRACT", 1.0, s.ramp(0.35, 0.75, s.m("ABSOLUTE", nz)), clamp=True)
        col = s.mix(s.m("MULTIPLY", s.m("MULTIPLY", runs, side), 0.4 * rust), col, RUST_COL)
    zn = s.m("ADD", z, s.m("MULTIPLY", s.m("SUBTRACT", s.noise(2.2, 3.0, 0.6), 0.5), 0.6))
    low = s.m("SUBTRACT", 1.0, s.ramp(0.02, 0.5, zn), clamp=True)
    dust_k = s.m("MULTIPLY", s.m("MAXIMUM", s.m("MULTIPLY", low, 0.5), s.m("MULTIPLY", cavity, 0.35)), dust)
    col = s.mix(dust_k, col, DUST_COL)
    edge = s.ramp(0.02, 0.1, C._bevel_edge(nt, 0.012, s.geo))
    chip = s.ramp(0.46, 0.56, s.noise(8.0, 4.0, 0.6))
    wear_k = s.m("MULTIPLY", s.m("MULTIPLY", edge, chip), wear)
    col = s.mix(wear_k, col, STEEL_COL)
    metal_s = s.mixf(wear_k, metal, 0.9)
    r = s.mixf(tone, rough - 0.06, rough + 0.06)
    r = s.mixf(dust_k, r, 0.92)
    r = s.mixf(wear_k, r, 0.38)
    height = s.m("SUBTRACT", s.m("MULTIPLY", tone, 0.3), s.m("MULTIPLY", wear_k, 0.6))
    return col, r, metal_s, height


def material(look: str) -> bpy.types.Material:
    """One look of the kit (see LOOKS)."""
    mat, nt, bsdf = C._new_material(f"Field_{look}")
    s = Shader(nt)
    bump = 0.15
    if look in PAINTS:
        color, wear, rust, rough = PAINTS[look]
        col, r, metal, h = weather(s, s.rgb(srgb(*color)), wear, rust, 1.0 if look != "strip" else 0.0, rough)
    elif look == "hazard":
        p = s.xyz(s.obj)
        diag = s.m("ADD", s.m("ADD", p.outputs["X"], p.outputs["Y"]), p.outputs["Z"])
        stripe = s.ramp(0.47, 0.53, s.m("FRACT", s.m("MULTIPLY", diag, 5.0)))
        base = s.mix(stripe, srgb(0.62, 0.44, 0.15), srgb(0.07, 0.07, 0.07))
        col, r, metal, h = weather(s, base, 0.7, 0.3, 1.0, 0.62)
    elif look == "stencil":
        worn = s.ramp(0.42, 0.62, s.noise(14.0, 3.0, 0.6))
        base = s.mix(worn, srgb(0.6, 0.59, 0.54), srgb(0.4, 0.4, 0.36))
        col, r, metal, h = weather(s, base, 0.0, 0.0, 1.0, 0.7)
    elif look == "steel":
        col, r, metal, h = weather(s, s.rgb(STEEL_COL), 0.0, 0.3, 1.0, 0.45, metal=1.0)
    elif look == "tarp":
        nz = s.xyz(s.geo.outputs["Normal"]).outputs["Z"]
        base = s.mix(s.spread(s.noise(1.8, 3.0, 0.5), 3.0), srgb(0.25, 0.26, 0.2), srgb(0.3, 0.3, 0.24))
        base = s.mix(s.m("MULTIPLY", s.ramp(0.55, 0.95, nz), 0.7), base, srgb(0.36, 0.35, 0.29))
        col, r, metal, h = weather(s, base, 0.0, 0.0, 0.8, 0.9)
        h = s.m("ADD", h, s.m("MULTIPLY", s.noise(5.0, 3.0, 0.6), 0.6))
        bump = 0.25
    elif look == "cable":
        wave = s.m("SINE", s.m("MULTIPLY", s.xyz(s.obj).outputs["X"], math.tau / 0.05))
        base = s.mix(
            s.ramp(0.0, 0.5, s.m("MULTIPLY_ADD", wave, 0.5, 0.5)), srgb(0.02, 0.02, 0.02), srgb(0.07, 0.07, 0.065)
        )
        col, r, metal, h = weather(s, base, 0.0, 0.0, 1.0, 0.8)
        h = s.m("ADD", h, s.m("MULTIPLY", wave, 0.5))
        bump = 0.5
    elif look in GLOWS:
        glow = GLOWS[look]
        col = s.rgb(tuple(c * 0.6 for c in srgb(*glow)))
        r, metal, h = 0.3, 0.0, None
        bsdf.inputs["Emission Color"].default_value = (*srgb(*glow), 1.0)
        bsdf.inputs["Emission Strength"].default_value = EMIT
    else:
        raise ValueError(look)
    nt.links.new(col, bsdf.inputs["Base Color"])
    for name, val in (("Roughness", r), ("Metallic", metal)):
        if isinstance(val, bpy.types.NodeSocket):
            nt.links.new(val, bsdf.inputs[name])
        else:
            bsdf.inputs[name].default_value = val
    if h is not None:
        C._bump(nt, bsdf, h, bump, 0.01)
    return mat


# --- mesh builder -------------------------------------------------------------------------------------


class Piece(C.Part):
    """C.Part with the kit's material slots (mi = a look index) and a few more primitives. Boxes, cylinders and
    beams get bevelled edges (sharper than 35 degrees); rods, lathes, tubes, decals and whatever is built inside
    `with piece.plain():` stay plain (small details, where a bevel only costs triangles)."""

    def __init__(self, name: str, bevel: tuple[float, int] | None = (0.008, 1)):
        super().__init__(name, MATS, bevel)
        self.flat: list[tuple[int, int]] = []

    @contextlib.contextmanager
    def plain(self):
        start = len(self.bm.verts)
        yield
        self.flat.append((start, len(self.bm.verts)))

    def rod(self, *args, **kw):
        with self.plain():
            return super().rod(*args, **kw)

    def _face(self, verts: list, mi: int) -> bmesh.types.BMFace:
        f = self.bm.faces.new(verts)
        f.material_index = mi
        f.smooth = True
        f.normal_update()
        return f

    def retag(self, verts, mi: int, test) -> None:
        """Give the faces of `verts` whose normal passes `test` the look `mi`."""
        for f in {f for v in verts for f in v.link_faces}:
            f.normal_update()
            if test(f.normal):
                f.material_index = mi

    def box2(self, loc, size, rot=None, mi=0, top=None, bottom=None, front=None):
        """A box with other looks on its top (+Z), bottom (-Z) or front (-Y) faces."""
        verts = self.box(loc, size, rot, mi)
        for look, test in (
            (top, lambda n: n.z > 0.9),
            (bottom, lambda n: n.z < -0.9),
            (front, lambda n: n.y < -0.9),
        ):
            if look is not None:
                self.retag(verts, look, test)
        return verts

    def frame(self, c, outer, inner, z0, z1, mi=0, inner_mi=None, top=None, bottom=None, m=None) -> None:
        """A rectangular ring (outer and inner width x depth around c) from z0 to z1, transformed by m."""
        m = m or Matrix.Identity(4)

        def rect(w, d):
            return [(c[0] - w / 2, c[1] - d / 2), (c[0] + w / 2, c[1] - d / 2), (c[0] + w / 2, c[1] + d / 2)] + [
                (c[0] - w / 2, c[1] + d / 2)
            ]

        def level(pts, z):
            return [self.bm.verts.new(m @ Vector((x, y, z))) for x, y in pts]

        o, i = rect(*outer), rect(*inner)
        ob, ot, ib, it = level(o, z0), level(o, z1), level(i, z0), level(i, z1)
        for k in range(4):
            n = (k + 1) % 4
            self._face([ob[k], ob[n], ot[n], ot[k]], mi)
            self._face([ib[n], ib[k], it[k], it[n]], mi if inner_mi is None else inner_mi)
            self._face([ot[k], ot[n], it[n], it[k]], mi if top is None else top)
            self._face([ob[n], ob[k], ib[k], ib[n]], mi if bottom is None else bottom)

    def lathe(self, profile: list, seg: int = 16, m: Matrix | None = None, spin: float = 0.0) -> list:
        """Revolve (r, z, mi) points around local Z (bottom to top along the outside; r = 0 closes on the axis);
        each point's mi is the look of the band up to the next point. Returns the new verts."""
        start = len(self.bm.verts)
        m = m or Matrix.Identity(4)
        angs = [math.radians(spin) + s / seg * math.tau for s in range(seg)]
        rings = []
        for r, z, _mi in profile:
            if r < 1e-6:
                rings.append([self.bm.verts.new(m @ Vector((0, 0, z)))] * seg)
            else:
                rings.append([self.bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), z))) for a in angs])
        for i in range(len(profile) - 1):
            a, b, mi = rings[i], rings[i + 1], profile[i][2]
            for s in range(seg):
                t = (s + 1) % seg
                quad = []
                for v in (a[s], a[t], b[t], b[s]):
                    if v not in quad:
                        quad.append(v)
                if len(quad) >= 3:
                    self._face(quad, mi)
        self.flat.append((start, len(self.bm.verts)))
        return list({v for ring in rings for v in ring})

    def tube(self, pts, r, sides=6, flat=1.0, mi=0, ref=None, spin=0.0, cap=True) -> None:
        """A tube along `pts` (radius r, or one per point); `flat` squashes the cross-section along the first
        frame axis, which starts perpendicular to the path and to `ref` (default Z, or X for steep paths) and is
        carried along the path without twist; spin 0.5 with 4 sides makes a flat band."""
        start = len(self.bm.verts)
        pts = [Vector(p) for p in pts]
        radii = r if isinstance(r, list) else [r] * len(pts)
        n = len(pts)
        t0 = (pts[1] - pts[0]).normalized()
        if ref is None:
            ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
        u = t0.cross(Vector(ref)).normalized()
        rings = []
        for i, p in enumerate(pts):
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            u = (u - t * u.dot(t)).normalized()
            v = t.cross(u)
            ring = []
            for s in range(sides):
                a = (s + spin) / sides * math.tau
                ring.append(self.bm.verts.new(p + (u * math.cos(a) * flat + v * math.sin(a)) * radii[i]))
            rings.append(ring)
        for a, b in itertools.pairwise(rings):
            for s in range(sides):
                self._face([a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]], mi)
        if cap:
            self._face(list(reversed(rings[0])), mi)
            self._face(rings[-1], mi)
        self.flat.append((start, len(self.bm.verts)))

    def quad(self, center, along, across, length, width, mi=STENCIL) -> None:
        """A flat decal quad (normal along x across)."""
        c, a, b = Vector(center), Vector(along).normalized(), Vector(across).normalized()
        pts = [c + a * (sa * length / 2) + b * (sb * width / 2) for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        with self.plain():
            self._face([self.bm.verts.new(p) for p in pts], mi)

    def glyphs(self, origin, right, up, text: str, h: float, mi: int = STENCIL) -> None:
        """Stenciled digits (seven bars with stencil gaps) as decal quads: origin is the bottom left as the
        viewer sees it, right x up is the face's normal."""
        o, r, u = Vector(origin), Vector(right).normalized(), Vector(up).normalized()
        for i, ch in enumerate(text):
            x0 = i * (GLYPH_W + 0.24)
            for seg in DIGITS[ch]:
                a0, b0, a1, b1 = SEGMENTS[seg]
                c = o + r * ((x0 + (a0 + a1) / 2) * h) + u * ((b0 + b1) / 2 * h)
                self.quad(c, r, u, (a1 - a0) * h, (b1 - b0) * h, mi)

    def finish(self, parent=None) -> bpy.types.Object:
        """The mesh object; the bevel only takes the edges marked here (sharp, not on a plain detail)."""
        if self.bev:
            flat = set()
            for a, b in self.flat:
                flat.update(range(a, b))
            self.bm.verts.index_update()
            self.bm.normal_update()
            weight = self.bm.edges.layers.float.new("bevel_weight_edge")
            for e in self.bm.edges:
                if e.verts[0].index in flat or e.verts[1].index in flat or len(e.link_faces) != 2:
                    continue
                if e.calc_face_angle(0.0) > math.radians(35):
                    e[weight] = 1.0
        obj = super().finish(parent)
        if self.bev:
            obj.modifiers["Bevel"].limit_method = "WEIGHT"
        obj.data.set_sharp_from_angle(angle=math.radians(35))
        return obj


GLYPH_W, _T, _G = 0.56, 0.15, 0.04
SEGMENTS = {  # (x0, y0, x1, y1) in glyph heights
    "a": (_T + _G, 1 - _T, GLYPH_W - _T - _G, 1.0),
    "b": (GLYPH_W - _T, 0.5 + _G, GLYPH_W, 1 - _G),
    "c": (GLYPH_W - _T, _G, GLYPH_W, 0.5 - _G),
    "d": (_T + _G, 0.0, GLYPH_W - _T - _G, _T),
    "e": (0.0, _G, _T, 0.5 - _G),
    "f": (0.0, 0.5 + _G, _T, 1 - _G),
    "g": (_T + _G, 0.5 - _T / 2, GLYPH_W - _T - _G, 0.5 + _T / 2),
}
DIGITS = {
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
}


def text_width(text: str, h: float) -> float:
    return (len(text) * (GLYPH_W + 0.24) - 0.24) * h


# --- the crate (three pieces) -------------------------------------------------------------------------


def crate_base() -> bpy.types.Object:
    """The openable supply crate's body: 1.2 x 0.8 x 0.6 m, origin bottom center, front +Y. Olive cargo case with an
    open top (a shallow dark inside 24 cm deep), a top lip and a gunmetal skid band, gunmetal corner guards, ribbed
    sides, rubber-gripped handles at the ends, latches on the front, hinge knuckles at the back (on the lid's
    hinge line) and a stenciled number on the front. The light strip runs around it at z 0.42-0.48 (its own
    piece); the ribs end below it."""
    p = Piece("Crate_base")
    p.box2((0, 0, (-SINK + 0.36) / 2), (1.17, 0.77, 0.36 + SINK), mi=OLIVE, top=INTERIOR)
    p.frame((0, 0), (1.17, 0.77), (1.09, 0.69), 0.36, 0.6, OLIVE, inner_mi=INTERIOR, bottom=INTERIOR)
    p.frame((0, 0), (1.19, 0.79), (1.16, 0.76), 0.5, 0.596, OLIVE)
    p.frame((0, 0), (1.19, 0.79), (1.16, 0.76), -0.02, 0.07, GUN)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.555, sy * 0.355, 0.295), (0.1, 0.1, 0.63), mi=GUN)
    with p.plain():
        for sy in (-1, 1):
            for x in (-0.22, 0.22):
                p.box((x, sy * 0.39, 0.245), (0.06, 0.025, 0.35), mi=OLIVE)
        for sx in (-1, 1):
            for y in (-0.2, 0.2):
                p.box((sx * 0.59, y, 0.245), (0.025, 0.06, 0.35), mi=OLIVE)
            for y in (-0.11, 0.11):
                p.box((sx * 0.6, y, 0.3), (0.05, 0.04, 0.07), mi=GUN)
            p.rod((sx * 0.628, -0.13, 0.3), (sx * 0.628, 0.13, 0.3), 0.016, 8, mi=RUBBER)
        for x in (-0.35, 0.35):
            p.box((x, 0.405, 0.55), (0.09, 0.03, 0.08), mi=GUN)
            p.box((x, 0.422, 0.535), (0.045, 0.014, 0.085), mi=STEEL)
            p.box((x, -0.398, 0.55), (0.16, 0.012, 0.07), mi=GUN)
            for dx in (-0.065, 0.065):
                p.rod((x + dx - 0.025, LID_AT[1], LID_AT[2]), (x + dx + 0.025, LID_AT[1], LID_AT[2]), 0.02, 8, mi=GUN)
    label, h = "31", 0.13
    p.glyphs((text_width(label, h) / 2, 0.3875, 0.17), (-1, 0, 0), (0, 0, 1), label, h)
    return p.finish()


def crate_lid() -> bpy.types.Object:
    """The crate's lid: 1.24 x 0.84 x 0.14 m, origin on the hinge line at its back bottom edge (it spans y 0..0.84,
    z 0..0.14). An olive cap with a skirt, a raised center panel with a stenciled number and two chevrons towards
    the front, gunmetal corner caps, latch keepers on the front, hinge knuckles at the back; its inside (seen when
    it's open) is dark with a rubber gasket on the skirt."""
    p = Piece("Crate_lid")
    cy = 0.42
    p.frame((0, cy), (1.22, 0.82), (1.15, 0.75), 0.0, 0.09, OLIVE, inner_mi=INTERIOR, bottom=RUBBER)
    p.box2((0, cy, 0.1), (1.21, 0.81, 0.04), mi=OLIVE, bottom=INTERIOR)
    p.box((0, cy, 0.128), (1.0, 0.6, 0.024), mi=OLIVE)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.575, cy + sy * 0.375, 0.0675), (0.09, 0.09, 0.135), mi=GUN)
    for x in (-0.35, 0.35):
        p.box((x, 0.832, 0.04), (0.07, 0.02, 0.05), mi=STEEL)
        p.rod((x - 0.03, 0, 0), (x + 0.03, 0, 0), 0.02, 8, mi=GUN)
        p.box((x, 0.006, 0.045), (0.12, 0.012, 0.07), mi=GUN)
    label, h = "07", 0.2
    p.glyphs((text_width(label, h) / 2, cy + h / 2, 0.1415), (-1, 0, 0), (0, -1, 0), label, h)
    for x in (-0.36, 0.36):  # chevrons pointing to the front
        for side in (-1, 1):
            along = Vector((side * 0.707, -0.707, 0))
            p.quad((x + side * 0.04, cy + 0.06, 0.1415), along, Vector((0, 0, 1)).cross(along), 0.13, 0.035)
    return p.finish()


def crate_strip() -> bpy.types.Object:
    """The thin light band around the crate's body, z 0.42-0.48, 2-3 cm proud of its walls (1 cm of the corner
    guards); origin at the crate's bottom center. The game draws it in its own glowing amber material."""
    p = Piece("Crate_strip", (0.005, 1))
    p.frame((0, 0), (1.23, 0.83), (1.165, 0.765), 0.42, 0.48, STRIP)
    return p.finish()


# --- cases --------------------------------------------------------------------------------------------


def case(p: Piece, m: Matrix, size, paint=OLIVE, label="", sink=0.0, handles=True, ribs=True, stripe=False) -> None:
    """A closed cargo case in the frame m (origin bottom center, front -Y): body and lid with a dark seam between
    them, a raised lid panel, gunmetal corner guards, ribs, handles at the ends, latches and a stenciled number on
    the front, optionally a hazard stripe along the lid's front edge."""
    w, d, h = size
    rot = m.to_3x3()

    def at(x, y, z):
        return m @ Vector((x, y, z))

    g = 0.018
    hb = round(h * 0.74, 3)
    p.box(at(0, 0, (hb - sink) / 2), (w - 2 * g, d - 2 * g, hb + sink), rot, paint)
    p.box(at(0, 0, hb + 0.012), (w - 2 * g - 0.03, d - 2 * g - 0.03, 0.03), rot, GUN)
    lid0 = hb + 0.02
    p.box(at(0, 0, (lid0 + h) / 2), (w - 2 * g + 0.008, d - 2 * g + 0.008, h - lid0), rot, paint)
    p.box(at(0, 0, h + 0.008), (w * 0.7, d * 0.62, 0.02), rot, paint)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box(
                at(sx * (w / 2 - 0.035), sy * (d / 2 - 0.035), (h + 0.012 - sink) / 2),
                (0.07, 0.07, h + 0.012 + sink),
                rot,
                GUN,
            )
    with p.plain():
        if ribs:
            for sy in (-1, 1):
                for x in (-w * 0.24, w * 0.24):
                    p.box(at(x, sy * (d / 2 - g + 0.006), (0.05 + hb - 0.03) / 2), (0.05, 0.022, hb - 0.08), rot, paint)
        if handles:
            hy = min(0.11, d * 0.24)
            for sx in (-1, 1):
                for y in (-hy, hy):
                    p.box(at(sx * (w / 2 - g + 0.015), y, h * 0.52), (0.035, 0.035, 0.06), rot, GUN)
                p.rod(
                    at(sx * (w / 2 - g + 0.033), -hy - 0.02, h * 0.52),
                    at(sx * (w / 2 - g + 0.033), hy + 0.02, h * 0.52),
                    0.013,
                    6,
                    RUBBER,
                )
    with p.plain():
        for x in (-w * 0.33, w * 0.33):
            p.box(at(x, -(d / 2 - g) - 0.008, hb + 0.01), (0.06, 0.02, 0.07), rot, STEEL)
    if label:
        lh = min(0.12, hb * 0.4)
        p.glyphs(
            at(-text_width(label, lh) / 2, -(d / 2 - g) - 0.002, hb * 0.3),
            rot @ Vector((1, 0, 0)),
            rot @ Vector((0, 0, 1)),
            label,
            lh,
        )
    if stripe:
        lid_h = h - lid0
        p.quad(
            at(0, -(d / 2 - g + 0.004) - 0.002, lid0 + lid_h / 2),
            rot @ Vector((1, 0, 0)),
            rot @ Vector((0, 0, 1)),
            w - 0.16,
            lid_h * 0.6,
            HAZARD,
        )


def crate_small() -> bpy.types.Object:
    """A smaller closed cargo case, 0.8 x 0.5 x 0.45 m, front -Y."""
    p = Piece("Crate_small", (0.007, 1))
    case(p, Matrix.Identity(4), (0.8, 0.5, 0.45), OLIVE, "24", sink=SINK, stripe=True)
    return p.finish()


def crate_stack() -> bpy.types.Object:
    """Five cases of mixed sizes and paints stacked about 2.0 x 1.0 x 1.4 m, the left pile held by two ratchet
    straps; front -Y."""
    p = Piece("Crate_stack", (0.007, 1))
    ma = T((-0.4, 0.08, 0))
    mc = T((-0.42, 0.06, 0.6), rz(-5))
    case(p, ma, (1.2, 0.8, 0.6), OLIVE, "31", sink=SINK)
    case(p, T((0.58, -0.12, 0), rz(7)), (0.76, 0.62, 0.52), OLIVE_WORN, "8", sink=SINK, ribs=False)
    case(p, mc, (0.92, 0.66, 0.46), BONE, "05", stripe=True)
    case(p, T((-0.38, 0.02, 1.06), rz(14)), (0.52, 0.4, 0.32), OLIVE, handles=False, ribs=False)
    case(p, T((0.6, -0.1, 0.52), rz(-9)), (0.56, 0.44, 0.36), OLIVE, "2", ribs=False)
    for xa, xc in ((-0.3, -0.28), (0.22, 0.24)):
        pts = [
            ma @ Vector((xa, -0.415, -0.02)),
            ma @ Vector((xa, -0.415, 0.6)),
            mc @ Vector((xc, -0.345, 0.0)),
            mc @ Vector((xc, -0.345, 0.47)),
            mc @ Vector((xc, 0.345, 0.47)),
            mc @ Vector((xc, 0.345, 0.0)),
            ma @ Vector((xa, 0.415, 0.6)),
            ma @ Vector((xa, 0.415, -0.02)),
        ]
        p.tube(pts, 0.03, 4, 0.22, STRAP, ref=(1, 0, 0), spin=0.5)
        p.box(ma @ Vector((xa, -0.43, 0.32)), (0.07, 0.03, 0.11), mi=STEEL)
    return p.finish()


# --- drums --------------------------------------------------------------------------------------------

DRUM_R = 0.29


def drum_profile(sink: float, band: bool, dense: bool, mi: int) -> list:
    """A ribbed steel drum's outside, 0.9 m tall: bottom chime, two rolling hoops, a top chime around the
    recessed lid; optionally a faded amber band and extra rings for dents."""
    r = DRUM_R
    pts = [(0.0, -sink, mi), (r, -sink, mi)]
    pts += [(r, 0.025, mi), (r + 0.012, 0.035, mi), (r + 0.012, 0.05, mi), (r, 0.06, mi)]
    pts += [(r, z, mi) for z in ((0.13, 0.2) if dense else ())]
    pts += [(r, 0.27, mi), (r + 0.014, 0.282, mi), (r + 0.014, 0.318, mi), (r, 0.33, mi)]
    pts += [(r, z, mi) for z in ((0.41, 0.49) if dense else ())]
    pts += [(r, 0.57, mi), (r + 0.014, 0.582, mi), (r + 0.014, 0.618, mi), (r, 0.66, AMBER if band else mi)]
    pts += [(r, 0.74, mi)] + [(r, z, mi) for z in ((0.8,) if dense else ())]
    pts += [(r, 0.86, mi), (r + 0.012, 0.872, mi), (r + 0.012, 0.9, mi), (r - 0.012, 0.9, mi)]
    pts += [(r - 0.02, 0.885, mi), (0.0, 0.885, mi)]
    return pts


def barrel_a() -> bpy.types.Object:
    """A ribbed olive steel drum standing, 0.6 m across, 0.9 m tall, a faded amber band, two bung caps."""
    p = Piece("Barrel_a", None)
    p.lathe(drum_profile(SINK, True, False, OLIVE), 16)
    p.cyl((0.15, 0.06, 0.893), 0.032, 0.016, 8, mi=STEEL)
    p.cyl((-0.14, -0.06, 0.893), 0.022, 0.016, 8, mi=STEEL)
    return p.finish()


def barrel_b() -> bpy.types.Object:
    """A dented, rustier drum lying on its side along X; origin at its ground contact, the drum sunk 5 cm."""
    p = Piece("Barrel_b", None)
    p.lathe(drum_profile(0.0, False, True, OLIVE_WORN), 16)
    p.cyl((0.15, 0.06, 0.893), 0.032, 0.016, 8, mi=STEEL)
    for ang, z, rad, depth in (
        (40, 0.45, 0.17, 0.045),
        (200, 0.75, 0.12, 0.03),
        (300, 0.2, 0.1, 0.025),
        (120, 0.89, 0.12, 0.03),
    ):
        c = Vector((DRUM_R * math.cos(math.radians(ang)), DRUM_R * math.sin(math.radians(ang)), z))
        for v in p.bm.verts:
            r = math.hypot(v.co.x, v.co.y)
            dist = (v.co - c).length
            if r > 0.05 and dist < rad:
                k = (1 - (dist / rad) ** 2) ** 2 * depth
                v.co.x *= 1 - k / r
                v.co.y *= 1 - k / r
    bmesh.ops.transform(p.bm, matrix=T((-0.45, 0, DRUM_R - 0.05), ry(90)), verts=p.bm.verts[:])
    return p.finish()


# --- tarp ---------------------------------------------------------------------------------------------

# What the tarp lies on: ("box", x, y, width, depth, top) or ("cyl", x, y, radius, 0, top).
TARP_SHAPES = [
    ("box", -0.45, 0.0, 1.05, 1.1, 0.72),
    ("box", 0.5, -0.14, 0.8, 0.78, 0.62),
    ("box", -0.42, 0.06, 0.86, 0.8, 1.25),
    ("cyl", 0.56, 0.3, 0.29, 0.0, 0.95),
]
TARP_X, TARP_Y = 1.2, 0.8


def tarp_height(x: float, y: float) -> float:
    """The draped tarp's height: each shape's top with a rounded edge and a skirt pulled out to the ground,
    the highest wins; wrinkles on top; at least lying on the ground."""
    h = 0.0
    for kind, cx, cy, a, b, top in TARP_SHAPES:
        if kind == "box":
            qx, qy = abs(x - cx) - a / 2, abs(y - cy) - b / 2
            sd = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0)
        else:
            sd = math.hypot(x - cx, y - cy) - a
        flare = 0.08 + 0.12 * top
        t, k = sd / flare, 0.035 / flare
        f = t if t >= k else (0.0 if t <= -k else (t + k) ** 2 / (4 * k))
        h = max(h, top * (1 - min(f, 1.0)))
    if h > 0.02:  # soft wrinkles on top, folds running down the sides
        h += 0.01 * mnoise.noise(Vector((x * 2.3, y * 2.3, 0.5))) + 0.022 * mnoise.noise(Vector((x * 5, y * 5, 1.0)))
    return max(h, 0.012 + 0.004 * mnoise.noise(Vector((x * 3, y * 3, 4.0))))


def tarp_stack() -> bpy.types.Object:
    """A faded olive tarp tied down over a stack of supplies (two cases, a taller case on top and a drum),
    2.4 x 1.6 x 1.3 m: hard corners under the fabric, the skirt pulled out to the ground, two straps across
    staked down at both ends, corner tie lines to pegs."""
    p = Piece("Tarp_stack", None)
    nx, ny = 36, 24
    xs = [-TARP_X + 2 * TARP_X * i / nx for i in range(nx + 1)]
    ys = [-TARP_Y + 2 * TARP_Y * j / ny for j in range(ny + 1)]
    hs = [[tarp_height(x, y) for y in ys] for x in xs]
    for _ in range(2):  # soften the creases where two shapes' drapes meet (jagged on the grid otherwise)
        hs = [
            [
                hs[i][j]
                if i in (0, nx) or j in (0, ny)
                else 0.5 * hs[i][j] + 0.125 * (hs[i - 1][j] + hs[i + 1][j] + hs[i][j - 1] + hs[i][j + 1])
                for j in range(ny + 1)
            ]
            for i in range(nx + 1)
        ]

    def surface(x: float, y: float) -> float:
        """The smoothed tarp height between the grid points (bilinear)."""
        fx = min(max((x + TARP_X) / (2 * TARP_X) * nx, 0.0), nx - 1e-6)
        fy = min(max((y + TARP_Y) / (2 * TARP_Y) * ny, 0.0), ny - 1e-6)
        i, j = int(fx), int(fy)
        u, v = fx - i, fy - j
        return (hs[i][j] * (1 - u) + hs[i + 1][j] * u) * (1 - v) + (hs[i][j + 1] * (1 - u) + hs[i + 1][j + 1] * u) * v

    grid = [[p.bm.verts.new((x, y, hs[i][j])) for j, y in enumerate(ys)] for i, x in enumerate(xs)]
    for i in range(nx):
        for j in range(ny):
            p._face([grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]], TARP)
    loop = [grid[i][0] for i in range(nx)] + [grid[nx][j] for j in range(ny)]
    loop += [grid[i][ny] for i in range(nx, 0, -1)] + [grid[0][j] for j in range(ny, 0, -1)]
    low = [p.bm.verts.new((v.co.x, v.co.y, -SINK)) for v in loop]
    for k in range(len(loop)):
        n = (k + 1) % len(loop)
        p._face([low[k], low[n], loop[n], loop[k]], TARP)
    for x in (-0.42, 0.48):
        along = [-TARP_Y - 0.03 + (2 * TARP_Y + 0.06) * j / 27 for j in range(28)]
        p.tube([(x, y, surface(x, y) + 0.013) for y in along], 0.03, 4, 0.22, STRAP, ref=(1, 0, 0), spin=0.5)
        for sy in (-1, 1):
            peg(p, (x, sy * (TARP_Y + 0.06)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            pt = (sx * (TARP_X - 0.02), sy * (TARP_Y - 0.02))
            peg(p, pt)
            sh = (sx * 0.86, sy * 0.48)
            p.tube([(*sh, surface(*sh) + 0.005), (*pt, 0.2)], 0.009, 4, mi=STRAP)
    return p.finish()


def peg(p: Piece, xy) -> None:
    """A steel tent peg with an amber head, 22 cm above ground."""
    p.beam((xy[0], xy[1], -0.2), (xy[0], xy[1], 0.2), 0.025, 0.025, (1, 0, 0), mi=STEEL)
    p.box((xy[0], xy[1], 0.215), (0.05, 0.035, 0.03), mi=AMBER)


# --- poles and lights ---------------------------------------------------------------------------------


def beacon_pole() -> bpy.types.Object:
    """A 3.2 m beacon pole: a bolted base plate on a buried footing, a sleeve with gussets, a gunmetal pole with a
    faded hazard band, a junction box and a conduit, a guy collar with three cut guy-wire stubs hanging slack, and the lamp housing
    at the top with a guard cage and a cap; the lens (Beacon_lens) sits inside the cage at z LENS_Z."""
    p = Piece("Beacon_pole", (0.006, 1))
    p.box((0, 0, -SINK / 2), (0.3, 0.3, SINK), mi=GUN)
    p.box((0, 0, 0.02), (0.44, 0.44, 0.04), mi=GUN)
    with p.plain():
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.cyl((sx * 0.17, sy * 0.17, 0.052), 0.018, 0.026, 6, mi=STEEL)
        p.cyl((0, 0, 0.22), 0.07, 0.36, 12, mi=GUN)
        for a in (0, 90, 180, 270):
            side = C.polar(a + 90, 1.0)
            p.beam(C.polar(a, 0.06, 0.3), C.polar(a, 0.2, 0.045), 0.012, 0.06, side, mi=GUN)
        p.cyl((0, 0, 1.675), 0.042, 2.59, 10, mi=GUN)
        p.cyl((0, 0, 0.75), 0.046, 0.3, 10, mi=HAZARD)
        p.cyl((0, 0, 1.575), 0.055, 0.05, 10, mi=GUN)
        p.box((0, -0.075, 1.3), (0.1, 0.07, 0.16), mi=BONE)
        p.rod((0, -0.052, 1.37), (0, -0.052, 2.93), 0.01, 6, mi=RUBBER)
        p.cyl((0, 0, 2.44), 0.06, 0.08, 10, mi=GUN)
        for a in (90, 210, 330):
            p.box(C.polar(a, 0.08, 2.44), (0.05, 0.012, 0.06), rz(a), mi=GUN)
            p.tube(
                [C.polar(a, 0.095, 2.43), C.polar(a, 0.15, 2.3), C.polar(a, 0.17, 2.1), C.polar(a, 0.15, 1.9)],
                0.006,
                4,
                mi=STEEL,
            )
    p.lathe(
        [
            (0.0, 2.93, GUN),
            (0.06, 2.93, GUN),
            (0.085, 2.96, GUN),
            (0.085, 3.03, GUN),
            (0.07, 3.03, GUN),
            (0.0, 3.03, GUN),
        ],
        14,
    )
    for a in (45, 135, 225, 315):
        p.rod(C.polar(a, 0.078, 3.02), C.polar(a, 0.078, 3.19), 0.008, 4, mi=GUN)
    p.lathe([(0.0, 3.18, GUN), (0.088, 3.18, GUN), (0.088, 3.2, GUN), (0.0, 3.2, GUN)], 14)
    return p.finish()


def beacon_lens() -> bpy.types.Object:
    """The beacon's red lens, a rounded dome 13 cm across, origin at its own center; glows red (the game blinks
    it)."""
    p = Piece("Beacon_lens", None)
    prof = [(0.0, -0.075), (0.062, -0.075), (0.066, -0.06), (0.066, 0.035), (0.058, 0.058), (0.04, 0.071), (0.0, 0.075)]
    p.lathe([(r, z, LENS) for r, z in prof], 14)
    return p.finish()


def work_light() -> bpy.types.Object:
    """A tripod work light, about 2.2 m: three splayed gunmetal legs with rubber feet, a telescopic mast with a
    clamp collar, a yoke holding the off-white flood lamp head tilted 35 degrees down towards -Y (cooling fins
    at its back, a gunmetal bezel round the glowing warm-white lens), and its cable running down the mast and
    trailing over the ground behind it."""
    p = Piece("Work_light", (0.006, 1))
    for a in (90, 210, 330):
        top, foot = C.polar(a, 0.05, 0.95), C.polar(a, 0.62, 0.0)
        p.beam(top, foot + (foot - top).normalized() * 0.32, 0.034, 0.034, C.polar(a + 90, 1.0), mi=GUN)
        p.box(foot + Vector((0, 0, 0.01)), (0.08, 0.08, 0.025), rz(a), mi=RUBBER)
    with p.plain():
        p.cyl((0, 0, 0.94), 0.055, 0.12, 12, mi=GUN)
        p.cyl((0, 0, 1.21), 0.032, 0.58, 10, mi=GUN)
        p.cyl((0, 0, 1.69), 0.024, 0.5, 10, mi=STEEL)
        p.cyl((0, 0, 1.5), 0.042, 0.06, 10, mi=GUN)
        p.rod((0.04, 0, 1.5), (0.1, 0, 1.5), 0.01, 6, mi=AMBER)
        p.box((0, 0, 1.94), (0.4, 0.035, 0.03), mi=GUN)
        for sx in (-1, 1):
            p.box((sx * 0.19, 0, 2.0), (0.025, 0.04, 0.15), mi=GUN)
    lamp = T((0, 0, 2.05), rx(35))
    rot = lamp.to_3x3()
    p.box(lamp @ Vector((0, 0, 0)), (0.3, 0.13, 0.22), rot, mi=BONE)
    p.frame((0, 0), (0.32, 0.24), (0.25, 0.17), 0.06, 0.085, GUN, m=lamp @ rx(90).to_4x4())
    p.box(lamp @ Vector((0, -0.075, 0)), (0.255, 0.012, 0.175), rot, mi=LAMP)
    with p.plain():
        for z in (-0.075, -0.025, 0.025, 0.075):
            p.box(lamp @ Vector((0, 0.08, z)), (0.27, 0.04, 0.012), rot, mi=GUN)
    p.rod(lamp @ Vector((-0.18, 0, 0)), lamp @ Vector((0.18, 0, 0)), 0.018, 8, mi=GUN)
    back = lamp @ Vector((0.06, 0.1, -0.02))
    cable = [back, (0.06, 0.07, 1.85), (0.045, 0.045, 1.6), (0.045, 0.045, 1.05), (0.09, 0.1, 0.9)]
    cable += [(0.22, 0.3, 0.4), (0.33, 0.48, 0.05), (0.5, 0.7, 0.016), (0.85, 0.85, 0.016), (1.2, 1.05, 0.016)]
    p.tube(cable, 0.012, 6, mi=RUBBER)
    p.box((1.27, 1.09, 0.03), (0.12, 0.06, 0.05), rz(30), mi=GUN)
    return p.finish()


def cable_spool() -> bpy.types.Object:
    """A big cable drum, 1.2 m across, on a gunmetal frame: olive flanges with radial stiffeners, the wound
    dark cable between them, a steel hub on its axle in bearing blocks, A-frame stands on skids; the cable end
    hangs off the front (-Y) and trails a meter over the ground to a connector."""
    p = Piece("Cable_spool", (0.007, 1))
    ax = 0.66
    flange = [(0.0, -0.025), (0.585, -0.025), (0.6, -0.01), (0.6, 0.01), (0.585, 0.025), (0.0, 0.025)]
    for sx in (-1, 1):
        p.lathe([(r, z, OLIVE) for r, z in flange], 24, T((sx * 0.3, 0, ax), ry(90)))
        with p.plain():
            for a in range(0, 360, 60):
                d = Vector((0, math.cos(math.radians(a)), math.sin(math.radians(a))))
                x = sx * 0.34
                p.beam(Vector((x, 0, ax)) + d * 0.12, Vector((x, 0, ax)) + d * 0.56, 0.035, 0.03, (1, 0, 0), mi=OLIVE)
    p.lathe(
        [(0.0, -0.276, CABLE), (0.47, -0.276, CABLE), (0.47, 0.276, CABLE), (0.0, 0.276, CABLE)],
        24,
        T((0, 0, ax), ry(90)),
    )
    p.rod((-0.4, 0, ax), (0.4, 0, ax), 0.1, 12, mi=STEEL)
    p.rod((-0.5, 0, ax), (0.5, 0, ax), 0.035, 8, mi=GUN)
    for sx in (-1, 1):
        x = sx * 0.45
        for sy in (-1, 1):
            p.beam((x, 0, ax), (x, sy * 0.44, 0.04), 0.05, 0.05, (1, 0, 0), mi=GUN)
        p.box((x, 0, ax), (0.08, 0.13, 0.11), mi=GUN)
        p.box((x, 0, (0.06 - SINK) / 2), (0.07, 1.0, 0.06 + SINK), mi=GUN)
    for sy in (-1, 1):
        p.box((0, sy * 0.45, 0.03), (0.93, 0.06, 0.05), mi=GUN)
    hang = [(0.12, -0.45, ax + 0.1), (0.12, -0.49, ax - 0.05), (0.13, -0.5, 0.32), (0.15, -0.58, 0.07)]
    hang += [(0.2, -0.75, 0.022), (0.32, -1.0, 0.022), (0.26, -1.3, 0.022), (0.4, -1.55, 0.022)]
    p.tube(hang, 0.022, 6, mi=RUBBER)
    p.rod((0.42, -1.58, 0.03), (0.47, -1.68, 0.03), 0.036, 8, mi=AMBER)
    return p.finish()


def stake() -> bpy.types.Object:
    """A survey stake, 1.0 m: a pointed gunmetal steel post with a faded amber marker band and a cap at the top."""
    p = Piece("Stake", (0.004, 1))
    p.beam((0, 0, 0.0), (0, 0, -SINK), 0.035, 0.035, (1, 0, 0), mi=GUN, taper=0.15)
    p.beam((0, 0, 0.0), (0, 0, 0.84), 0.035, 0.035, (1, 0, 0), mi=GUN)
    p.box((0, 0, 0.905), (0.045, 0.045, 0.13), rz(45), mi=AMBER)
    p.box((0, 0, 0.985), (0.05, 0.05, 0.03), rz(45), mi=GUN)
    return p.finish()


def repeller_post() -> bpy.types.Object:
    """A survey repeller post that keeps aliens off: a tripod foot, a sturdy 1.8 m gunmetal post with a hazard
    band and an off-white junction box, and the emitter head at the top (three off-white fins round a core) with a
    small cyan-white status light on top."""
    p = Piece("Repeller_post", (0.006, 1))
    for a in (90, 210, 330):
        top, foot = C.polar(a, 0.06, 0.32), C.polar(a, 0.45, 0.0)
        p.beam(top, foot + (foot - top).normalized() * 0.3, 0.045, 0.04, C.polar(a + 90, 1.0), mi=GUN)
        p.box(foot + Vector((0, 0, 0.012)), (0.1, 0.1, 0.025), rz(a), mi=GUN)
    p.cyl((0, 0, 0.285), 0.075, 0.27, 12, mi=GUN)
    p.cyl((0, 0, 1.11), 0.055, 1.42, 12, mi=GUN)
    p.cyl((0, 0, 0.7), 0.06, 0.16, 12, mi=HAZARD)
    p.box((0, -0.105, 1.12), (0.17, 0.11, 0.28), mi=BONE)
    p.rod((0.05, -0.07, 1.26), (0.05, -0.04, 1.8), 0.012, 6, mi=RUBBER)
    p.cyl((0, 0, 1.83), 0.075, 0.06, 12, mi=GUN)
    p.cyl((0, 0, 1.97), 0.045, 0.22, 12, mi=GUN)
    for r, z in ((0.19, 1.89), (0.165, 1.95), (0.14, 2.01)):
        p.cyl((0, 0, z), r, 0.022, 16, mi=BONE)
    p.cyl((0, 0, 2.085), 0.055, 0.02, 12, mi=GUN)
    p.lathe(
        [
            (0.0, 2.095, STATUS),
            (0.024, 2.095, STATUS),
            (0.024, 2.11, STATUS),
            (0.012, 2.125, STATUS),
            (0.0, 2.127, STATUS),
        ],
        10,
    )
    return p.finish()


BUILDERS = {
    "Crate_base": crate_base,
    "Crate_lid": crate_lid,
    "Crate_strip": crate_strip,
    "Crate_small": crate_small,
    "Crate_stack": crate_stack,
    "Barrel_a": barrel_a,
    "Barrel_b": barrel_b,
    "Tarp_stack": tarp_stack,
    "Beacon_pole": beacon_pole,
    "Beacon_lens": beacon_lens,
    "Work_light": work_light,
    "Cable_spool": cable_spool,
    "Stake": stake,
    "Repeller_post": repeller_post,
}

# --- previews -----------------------------------------------------------------------------------------

# Groups shown together: the first piece at the origin, the others at (offset, rotation about X) from it.
GROUPS = {
    "Crate": [("Crate_base", (0, 0, 0), 0.0), ("Crate_strip", (0, 0, 0), 0.0), ("Crate_lid", LID_AT, 0.0)],
    "Crate_open": [("Crate_base", (0, 0, 0), 0.0), ("Crate_strip", (0, 0, 0), 0.0), ("Crate_lid", LID_AT, LID_OPEN)],
    "Beacon": [("Beacon_pole", (0, 0, 0), 0.0), ("Beacon_lens", (0, 0, LENS_Z), 0.0)],
}
# Kit overview: group or piece -> (u along screen right, v toward the camera, z rotation in degrees).
KIT = {
    "Tarp_stack": (-4.6, -1.8, 0),
    "Crate_stack": (-1.8, -2.0, 0),
    "Cable_spool": (0.6, -2.0, 0),
    "Beacon": (2.3, -1.6, 0),
    "Work_light": (3.7, -1.6, 0),
    "Repeller_post": (5.1, -1.6, 0),
    "Crate": (-4.0, 0.8, 0),
    "Crate_small": (-2.4, 0.8, 0),
    "Barrel_a": (-1.1, 0.8, 0),
    "Barrel_b": (0.5, 0.8, 0),
    "Stake": (1.9, 0.8, 0),
}

# Part layouts in Godot coordinates (x, y, z), rotation about Godot Y in degrees. "others" are the greybox
# stand-ins of what other kits build (box: center, size; cyl: base, radius, height), "marks" the markers, "pole"
# where the 1.89 m scale pole stands.
LAYOUTS = {
    "prospectors_cache": {
        "pole": (2.2, 0.0, 2.4),
        "radius": 4.5,
        "pieces": [
            ("Tarp_stack", (0.0, 0.0, -0.6), 15),
            ("Crate_stack", (-2.6, 0.0, 0.4), 60),
            ("Crate_small", (2.4, 0.0, 0.9), 45),
            ("Barrel_a", (1.9, 0.0, -1.9), 0),
            ("Barrel_a", (1.25, 0.0, -2.55), 40),
            ("Barrel_b", (2.75, 0.0, -0.85), 100),
            ("Beacon", (-1.6, 0.0, -2.2), 0),
            ("Crate", (0.3, 0.0, 1.4), 0),
        ],
        "others": [],
        "marks": [((0.3, 1.4), "quest")],
    },
    "hollis_camp": {
        "pole": (3.2, 0.0, -3.6),
        "radius": 8.0,
        "pieces": [
            ("Work_light", (-0.6, 0.0, 3.2), 170),
            ("Repeller_post", (1.4, 0.0, 3.6), 0),
            ("Crate_stack", (5.6, 0.0, -0.9), -70),
            ("Barrel_a", (6.1, 0.0, 0.8), 0),
            ("Barrel_a", (6.7, 0.0, 0.15), 30),
            ("Barrel_b", (5.0, 0.0, -2.7), 20),
            ("Cable_spool", (-2.5, 0.0, 4.3), -20),
            ("Tarp_stack", (-4.6, 0.0, 3.2), 25),
            ("Crate_small", (0.1, 0.0, 5.2), 10),
        ],
        "others": [("box", (3.6, 1.5, 2.6), (4.2, 3.0, 3.0), 15), ("cyl", (-3.7, 0.0, -0.6), 1.3, 3.4)],
        "marks": [((0.0, 0.0), "quest"), ((1.2, -1.6), "spot")],
    },
    "hollis_dig_site": {
        "pole": (-2.8, 0.0, -4.2),
        "radius": 6.0,
        "pieces": [
            ("Cable_spool", (-3.4, 0.0, 2.2), 90),
            ("Stake", (2.6, 0.0, -3.4), 0),
            ("Stake", (-2.2, 0.0, 3.9), 20),
            ("Stake", (0.6, 0.0, 4.6), 10),
            ("Stake", (5.0, 0.0, 0.9), 35),
            ("Stake", (-4.7, 0.0, 0.6), 5),
            ("Work_light", (-0.9, 0.0, 4.4), 125),
        ],
        "others": [
            ("cyl", (4.0, 0.0, 3.6), 0.7, 2.6),
            ("box", (-4.3, 0.45, -1.8), (1.6, 1.1, 1.3), 30),
            ("box", (0.4, 0.06, -0.9), (1.6, 0.08, 1.1), 20),
        ],
        "marks": [((2.2, 2.6), "ore"), ((-1.2, -1.0), "nest")],
    },
    "expedition_camp": {
        "pole": (0.8, 0.0, -3.4),
        "radius": 5.0,
        "pieces": [
            ("Crate_small", (2.6, 0.0, 2.6), 15),
            ("Crate_small", (3.3, 0.0, 1.6), -25),
            ("Barrel_a", (3.5, 0.0, 2.75), 0),
            ("Barrel_b", (1.5, 0.0, 3.7), 60),
        ],
        "others": [("box", (-0.4, 0.95, 1.4), (4.4, 2.2, 2.2), -150), ("cyl", (2.6, 0.0, -1.4), 0.1, 3.4)],
        "marks": [((-2.4, -2.6), "quest")],
    },
}
GROUND = ((0.05, 0.047, 0.043), (0.09, 0.085, 0.078))  # linear albedo of the preview ground
MARK_COLORS = {"quest": (1.0, 0.6, 0.15), "spot": (0.3, 0.5, 1.0), "ore": (0.1, 0.9, 0.85), "nest": (0.9, 0.15, 0.1)}


def uv_to_xy(u: float, v: float) -> Vector:
    k = math.sqrt(0.5)
    return Vector((u * k + v * k, u * k - v * k, 0.0))


def godot(pos) -> Vector:
    """Blender position of a Godot one."""
    return Vector((pos[0], -pos[2], pos[1]))


def kit_objects() -> list:
    return [bpy.data.objects[n] for n in PARTS]


def members(name: str) -> list:
    return GROUPS.get(name, [(name, (0, 0, 0), 0.0)])


def place(name: str, loc: Vector, rot_deg: float) -> list:
    """Put a piece or group at loc (rotated about Z) and return its objects."""
    out = []
    for piece, offset, open_x in members(name):
        obj = bpy.data.objects[piece]
        obj.location = loc + rz(rot_deg) @ Vector(offset)
        obj.rotation_euler = (open_x, 0, math.radians(rot_deg))
        out.append(obj)
    return out


def show_only(objs: list) -> None:
    for o in kit_objects():
        o.hide_render = o not in objs


def setup_preview() -> None:
    """The common preview scene without its pebbles, the ground about as bright as the game's dusty ground."""
    C.preview_scene(crystals=False, pebbles=False)
    C.tint_ground(GROUND[0], GROUND[1])


def render_kit(path: pathlib.Path, view: str, samples: int, size: int) -> pathlib.Path:
    shown = []
    for name, (u, v, rot) in KIT.items():
        shown += place(name, uv_to_xy(u, v), rot)
    show_only(shown)
    bpy.data.objects["PreviewFigure"].location = uv_to_xy(3.4, 0.8)
    center = uv_to_xy(0.3, -0.5) + Vector((0, 0, 0.6))
    C.render(path, view=view, samples=samples, size=size, target=tuple(center), zoom={"iso": 1.2, "hero": 1.55}[view])
    return path


def render_piece(name: str, prefix: str, views, samples: int, size: int) -> list:
    """A piece or group alone at the origin, framed by its size, the scale figure beside it."""
    objs = place(name, Vector((0, 0, 0)), 0)
    show_only(objs)
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo, hi = Vector(map(min, lo, w)), Vector(map(max, hi, w))
    dx, dy, dz = hi - lo
    dz = hi.z - max(lo.z, 0.0)
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
    fig.location = side * (max(dx, dy) / 2 + 0.55)
    w = max(dx, dy, dz * 1.1) * 1.3 + 1.4
    target = side * 0.3 + Vector((0, 0, max(0.5, dz * 0.42)))
    out = []
    for view in views:
        path = OUT / f"{prefix}{name}_{view}.png"
        C.render(
            path, view=view, samples=samples, size=size, target=tuple(target), zoom=w / (9.9 if view == "iso" else 6.3)
        )
        out.append(path)
    return out


def _flat_mat(name: str, color, emission: float = 0.0) -> bpy.types.Material:
    mat, _nt, bsdf = C._new_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.8
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def _preview_mesh(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    C.collection("Preview").objects.link(obj)
    me.materials.append(mat)
    return obj


def render_layout(part: str, path: pathlib.Path, samples: int, size: int) -> pathlib.Path:
    """The part as the game would show it: the pieces at the proposed layout (linked duplicates), grey stand-ins
    footprints for the other kits' pieces, the markers as colored discs, the prop radius as a thin ring and a 1.89 m pole,
    seen from about the game camera's angle (50 degrees down, 45 around) in a dim, cool light."""
    spec = LAYOUTS[part]
    radius = spec["radius"]
    extra = []
    show_only([])
    for name, pos, rot in spec["pieces"]:
        for o in place(name, godot(pos), rot):
            d = o.copy()
            C.collection("Preview").objects.link(d)
            d.hide_render = False
            extra.append(d)
    grey = _flat_mat("LayoutStandIn", (0.25, 0.25, 0.27))
    for item in spec["others"]:
        bm = bmesh.new()
        if item[0] == "box":
            _k, pos, sz, rot = item
            bmesh.ops.create_cube(bm, size=1.0, matrix=T(godot((pos[0], 0.15, pos[2])), rz(rot), (sz[0], sz[2], 0.3)))
        else:
            _k, pos, r, _h = item
            h = 0.3
            bmesh.ops.create_cone(
                bm,
                cap_ends=True,
                segments=16,
                radius1=r,
                radius2=r,
                depth=h,
                matrix=T(godot(pos) + Vector((0, 0, h / 2))),
            )
        extra.append(_preview_mesh("StandIn", bm, grey))
    for (gx, gz), kind in spec["marks"]:
        bm = bmesh.new()
        bmesh.ops.create_cone(
            bm, cap_ends=True, segments=20, radius1=0.35, radius2=0.35, depth=0.02, matrix=T(godot((gx, 0.02, gz)))
        )
        extra.append(_preview_mesh("Mark", bm, _flat_mat(f"Mark_{kind}", MARK_COLORS[kind], 2.0)))
    bm = bmesh.new()
    ring = Piece("Ring", None)
    ring.bm.free()
    ring.bm = bm
    ring.tube([C.polar(a * 5, radius, 0.02) for a in range(73)], 0.025, 4, mi=0, cap=False)
    extra.append(_preview_mesh("Ring", bm, _flat_mat("LayoutRing", (0.6, 0.6, 0.65), 0.6)))
    bm = bmesh.new()
    corner = godot(spec["pole"]) + Vector((0, 0, 0.945))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.04, radius2=0.04, depth=1.89, matrix=T(corner))
    extra.append(_preview_mesh("ScalePole", bm, _flat_mat("LayoutPole", (0.6, 0.58, 0.55))))
    fig = bpy.data.objects["PreviewFigure"]
    fig_loc = fig.location.copy()
    fig.location = (0, 0, -10)
    # Light: a weak low sun and a little cool sky instead of the preview's studio lights.
    lights = [o for o in C.collection("Preview").objects if o.type == "LIGHT"]
    for o in lights:
        o.hide_render = True
    sun_data = bpy.data.lights.new("LayoutSun", "SUN")
    sun_data.energy = 3.0
    sun_data.color = (0.85, 0.9, 1.0)
    sun_data.angle = math.radians(2)
    sun = bpy.data.objects.new("LayoutSun", sun_data)
    C.collection("Preview").objects.link(sun)
    sun.rotation_euler = Vector((0.75, 0.45, 0.4)).to_track_quat("Z", "Y").to_euler()
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    old_bg = tuple(bg.inputs["Color"].default_value), bg.inputs["Strength"].default_value
    bg.inputs["Color"].default_value = (0.05, 0.065, 0.09, 1.0)
    bg.inputs["Strength"].default_value = 1.2
    dist = (radius + 1.2) / math.tan(math.atan(18 / 50)) * 1.02
    pitch = math.radians(50)
    cam = Vector((math.cos(pitch) * math.sqrt(0.5), -math.cos(pitch) * math.sqrt(0.5), math.sin(pitch))) * dist
    C.render_from(path, tuple(cam + Vector((0, 0, 0.5))), (0, 0, 0.5), lens=50, samples=samples, size=size)
    for o in extra + [sun]:
        bpy.data.objects.remove(o)
    for o in lights:
        o.hide_render = False
    bg.inputs["Color"].default_value = old_bg[0]
    bg.inputs["Strength"].default_value = old_bg[1]
    fig.location = fig_loc
    return path


def apply_bake_layout(gap: float = 1.5) -> None:
    """Saved .blend layout: every piece unrotated in one row along X, `gap` m apart, the lid at the height it has
    on the crate, the lens on its pole. The bake zeroes the locations before the export."""
    x = 0.0
    for name in PARTS:
        obj = bpy.data.objects[name]
        obj.rotation_euler = (0, 0, 0)
        obj.hide_render = False
        if name == "Beacon_lens":
            obj.location = bpy.data.objects["Beacon_pole"].location + Vector((0, 0, LENS_Z))
            continue
        obj.location = (x + obj.dimensions.x / 2, 0, LID_AT[2] if name == "Crate_lid" else 0.0)
        x += obj.dimensions.x + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


# --- main ---------------------------------------------------------------------------------------------


def build() -> None:
    MATS.extend(material(look) for look in LOOKS)
    for name in PARTS:
        BUILDERS[name]()


def report() -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for name in PARTS:
        obj = bpy.data.objects[name]
        me = obj.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        xs, ys, zs = ([v.co[i] for v in me.vertices] for i in range(3))
        span = tuple(round(max(a) - min(a), 2) for a in (xs, ys, zs))
        lo = (round(min(xs), 3), round(min(ys), 3), round(min(zs), 3))
        hi = (round(max(xs), 3), round(max(ys), 3), round(max(zs), 3))
        print(f"STATS {name}: tris={len(me.loop_triangles)} size={span} min={lo} max={hi}")
        obj.evaluated_get(dg).to_mesh_clear()
    print("STATS", C.stats())


def main() -> None:
    C.reset(ASSET)
    build()
    report()
    setup_preview()
    if MODE == "final":
        sheet = [
            render_kit(OUT / "final_kit_iso.png", "iso", 64, 1024),
            render_kit(OUT / "final_kit_hero.png", "hero", 64, 1024),
        ]
        for part in LAYOUTS:
            sheet.append(render_layout(part, OUT / f"layout_{part}.png", 64, 1024))
        for name in ("Crate", "Crate_open", "Beacon"):
            sheet += render_piece(name, "final_", ("iso", "hero"), 32, 640)
        for name in PARTS:
            sheet += render_piece(name, "final_", ("iso", "hero"), 32, 640)
        C.contact_sheet(sheet, OUT / "sheet.png", cols=6, tile=384, background=0.02)
        apply_bake_layout()
        C.save_blend(OUT / "field_procedural.blend")
        return
    wip = OUT / "wip"
    for view in VIEWS:
        if view == "kit":
            render_kit(wip / f"{TAG}_kit_iso.png", "iso", 24, 900)
        elif view == "pieces":
            for name in PARTS:
                render_piece(name, f"wip/{TAG}_", ("iso",), 20, 512)
        elif view in BUILDERS or view in GROUPS:
            render_piece(view, f"wip/{TAG}_", ("iso", "hero"), 24, 640)
        elif view == "layouts":
            for part in LAYOUTS:
                render_layout(part, wip / f"{TAG}_layout_{part}.png", 24, 900)
        elif view in LAYOUTS:
            render_layout(view, wip / f"{TAG}_layout_{view}.png", 24, 900)
        elif view == "sheet":
            names = sorted(p for p in wip.glob(f"{TAG}_*.png") if not p.name.endswith("_sheet.png"))
            C.contact_sheet(names, wip / f"{TAG}_sheet.png", cols=5, tile=384, background=0.02)
        elif view == "save":
            apply_bake_layout()
            C.save_blend(OUT / "field_procedural.blend")
            return


if __name__ == "__main__":
    main()
