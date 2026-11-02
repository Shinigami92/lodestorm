"""Shared helpers of the colony-made map part kits built by assets/parts/<kit>/source/<kit>_build.py (the Dust flats'
crawler, the Salt pans' pump station, the Ash fields' heat tap): the colony's weathered look as procedural Cycles
materials, a mesh builder with chunky bevels only where wanted, the previews (each piece, and the part's layout
from the game's angle with a 1.89 m pole and the prop radius) and the kit flow (wip previews, final contact sheet
and procedural .blend, bake checks).

The colony's look: everything human out there was hauled in by the colony, industrial prefab equipment worn hard.
Off-white paint on habitat panels and cabs, dull olive-grey on cargo, dark gunmetal on frames and machinery, chipped
to bare steel on the edges, rust streaks running down, grime in the recesses, faded amber hazard stripes, small red
marker lights. Each kit belongs to one biome and shows it (drifted dust, salt crust, scorch and heat tint), but keeps
its top-facing surfaces fairly clean: the game lays the biome's loose cover on them in a shader. Noise and grime stay
low-contrast and large-scale, so the pieces read calm from the game's camera.

Usage (a kit's build script):

    sys.path.insert(0, str(ROOT / "tools" / "blender"))
    import colony as K
    KIT = K.Kit(name="crawler", weather="dust", pieces={...}, layout=[...], ...)
    looks = K.Looks("dust", {"bone": ("paint", K.BONE, {}), ...})
    p = K.Piece("Crawler", looks)
    p.box(..., mi=looks["bone"])
    p.finish()
    K.main(KIT)
"""

import dataclasses
import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C


def srgb(r: float, g: float, b: float) -> tuple[float, float, float]:
    """Linear color from sRGB values (shader colors are linear)."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))


# The colony's paints and markings (sRGB).
BONE = (0.47, 0.46, 0.43)  # habitat panels, pods, cabs
OLIVE = (0.30, 0.31, 0.27)  # cargo: crates, barrels, tanks
GUNMETAL = (0.16, 0.16, 0.17)  # frames, legs, machinery
AMBER = (0.70, 0.48, 0.14)  # hazard stripes (faded, not glowing)
STEEL = (0.36, 0.35, 0.34)  # bare steel where the paint is worn off
RUST = (0.33, 0.20, 0.12)
GRIME = (0.085, 0.08, 0.075)
TRACK = (0.11, 0.105, 0.10)  # track links, dark steel
LAMP_RED = (1.0, 0.12, 0.06)
EMBER = (1.0, 0.30, 0.08)

# Biome weathering colors (sRGB), matched to the terrain layers (assets/terrain/source/layers/<biome>.py).
DUST = ((0.35, 0.31, 0.26), (0.41, 0.365, 0.31))  # Dust flats sand
SALT = ((0.56, 0.56, 0.55), (0.67, 0.67, 0.66))  # Salt pans crust
ASH = (0.27, 0.262, 0.25)  # Ash fields ash film
SOOT = (0.07, 0.064, 0.06)
BURNT = (0.24, 0.17, 0.11)  # paint browned at the edge of a scorch
# Heat tint on bare steel (straw, bronze, purple, blue), kept dull.
HEAT_TINTS = [(0.42, 0.37, 0.27), (0.37, 0.29, 0.23), (0.29, 0.24, 0.30), (0.24, 0.26, 0.33)]
# Linear albedo of each biome's ground for the preview floor (about the ground texture's brightness).
GROUND = {
    "dust": (srgb(0.31, 0.275, 0.235), srgb(0.38, 0.335, 0.28)),
    "salt": ((0.17, 0.17, 0.16), (0.25, 0.25, 0.24)),
    "ash": (srgb(0.17, 0.166, 0.162), srgb(0.25, 0.243, 0.235)),
}
PLAYER = 1.89  # the scale pole in the layout renders


# --- material -----------------------------------------------------------------------------------------


class Shader:
    """Node helpers for the kit materials (numbers are set, sockets linked)."""

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
        """0 below a, 1 above b, linear between (any range, unlike a color ramp's 0..1 positions)."""
        node = self.nt.nodes.new("ShaderNodeMapRange")
        node.clamp = True
        node.inputs["From Min"].default_value = a
        node.inputs["From Max"].default_value = b
        self.nt.links.new(src, node.inputs["Value"])
        return node.outputs["Result"]

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

    def scale_color(self, col, fac) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = "SCALE"
        if isinstance(col, bpy.types.NodeSocket):
            self.nt.links.new(col, node.inputs[0])
        else:
            node.inputs[0].default_value = col
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, node.inputs["Scale"])
        else:
            node.inputs["Scale"].default_value = fac
        return node.outputs[0]

    def palette(self, fac, colors: list) -> bpy.types.NodeSocket:
        """Smooth steps through `colors` (sRGB) along fac 0..1."""
        node = self.nt.nodes.new("ShaderNodeValToRGB")
        ramp = node.color_ramp
        while len(ramp.elements) < len(colors):
            ramp.elements.new(0.5)
        for i, c in enumerate(colors):
            ramp.elements[i].position = i / max(1, len(colors) - 1)
            ramp.elements[i].color = (*srgb(*c), 1.0)
        self.nt.links.new(fac, node.inputs["Fac"])
        return node.outputs["Color"]

    def spread(self, fac, k: float) -> bpy.types.NodeSocket:
        """Noise Fac stretched around 0.5 by `k`, clamped to 0..1."""
        return self.m("MULTIPLY_ADD", self.m("SUBTRACT", fac, 0.5), k, clamp=True, c=0.5)

    def stripes(self, period: float) -> bpy.types.NodeSocket:
        """Diagonal hazard stripes in object space, 0/1, `period` m from one amber stripe to the next."""
        wave = self.nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = "DIAGONAL"
        wave.inputs["Scale"].default_value = math.tau / (10.0 * period)
        wave.inputs["Distortion"].default_value = 0.0
        wave.inputs["Detail"].default_value = 0.0
        self.nt.links.new(self.obj, wave.inputs["Vector"])
        return self.ramp(0.47, 0.53, wave.outputs["Fac"])


@dataclasses.dataclass
class Surface:
    """The look being assembled: color, roughness, metallic and bump height sockets (or numbers)."""

    col: object
    rough: object
    metal: object
    height: object


def _common_masks(s: Shader) -> dict:
    pos = s.xyz(s.obj)
    ao = s.nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.35
    ao.samples = 16
    streak_vec = s.vec("MULTIPLY", s.obj, (1.0, 1.0, 0.08))
    return {
        "z": pos.outputs["Z"],
        "nz": s.xyz(s.geo.outputs["Normal"]).outputs["Z"],
        "cavity": s.m("SUBTRACT", 1.0, s.ramp(0.35, 0.95, ao.outputs["AO"]), clamp=True),
        "edge": s.ramp(0.02, 0.1, C._bevel_edge(s.nt, 0.03, s.geo)),
        "tone": s.noise(0.6, 3.0, 0.5),
        "grain": s.noise(28.0, 3.0, 0.6),
        "streak": s.noise(5.0, 3.0, 0.5, streak_vec),
        "patch": s.noise(1.3, 3.0, 0.55),
    }


def _low(s: Shader, k: dict, z0: float, z1: float, wobble: float = 1.0) -> bpy.types.NodeSocket:
    """1 near the piece's bottom fading out between z0 and z1 (wobbled by a large noise)."""
    zz = s.m("ADD", k["z"], s.m("MULTIPLY", s.m("SUBTRACT", s.noise(1.4, 3.0, 0.55), 0.5), wobble))
    return s.m("SUBTRACT", 1.0, s.ramp(z0, z1, zz), clamp=True)


def _weather(s: Shader, k: dict, w: str, surf: Surface, opts: dict) -> Surface:
    """The biome's own weathering over a finished surface."""
    up = s.ramp(0.6, 0.92, k["nz"])
    keep_top = s.m("SUBTRACT", 1.0, s.m("MULTIPLY", up, 0.75))  # tops stay fairly clean: the game covers them
    amount = opts.get("weather", 1.0)
    if w == "dust":
        band = opts.get("dust_band", 1.3)
        low = _low(s, k, 0.15, band, 1.0)
        f = s.m("MAXIMUM", s.m("MULTIPLY", low, 0.75), s.m("MULTIPLY", k["cavity"], 0.5))
        f = s.m("MULTIPLY", s.m("ADD", f, 0.05), keep_top)
        f = s.m(
            "MULTIPLY",
            s.ramp(0.12, 0.7, s.m("ADD", f, s.m("MULTIPLY", s.m("SUBTRACT", k["patch"], 0.5), 0.8))),
            amount,
        )
        dust = s.mix(s.spread(k["tone"], 3.0), srgb(*DUST[0]), srgb(*DUST[1]))
        surf.col = s.mix(f, surf.col, dust)
        surf.rough = s.mixf(f, surf.rough, 0.92)
        surf.metal = s.mixf(f, surf.metal, 0.0)
        surf.height = s.mixf(f, surf.height, s.m("MULTIPLY", k["grain"], 0.4))
    elif w == "salt":
        band = opts.get("salt_band", 0.7)
        lump = s.noise(12.0, 5.0, 0.65)
        low = _low(s, k, 0.0, band, 0.8)
        bloom = s.m("MULTIPLY", s.ramp(0.6, 0.7, k["streak"]), s.m("SUBTRACT", 1.0, up))  # efflorescence runs
        f = s.m("MAXIMUM", s.m("MAXIMUM", low, s.m("MULTIPLY", k["cavity"], 0.8)), s.m("MULTIPLY", bloom, 0.62))
        f = s.m("MULTIPLY", f, keep_top)
        f = s.m("MULTIPLY", s.ramp(0.3, 0.5, s.m("ADD", f, s.m("MULTIPLY", s.m("SUBTRACT", lump, 0.5), 1.3))), amount)
        crust = s.mix(s.spread(s.noise(60.0, 2.0, 0.6), 2.5), srgb(*SALT[0]), srgb(*SALT[1]))
        crust = s.mix(s.m("MULTIPLY", s.spread(lump, 2.5), 0.35), crust, srgb(0.5, 0.495, 0.48))
        surf.col = s.mix(f, surf.col, crust)
        surf.rough = s.mixf(f, surf.rough, 0.93)
        surf.metal = s.mixf(f, surf.metal, 0.0)
        surf.height = s.mixf(f, surf.height, s.m("ADD", s.m("MULTIPLY", lump, 1.2), 0.3))
    elif w == "ash":
        # Scorch: soot rising towards the hot end (heat_z: from, to in m), a browned band where it fades out,
        # broken up by a large soft noise rather than in blotches.
        heat = s.m("MULTIPLY_ADD", k["patch"], 0.8, opts.get("heat", 0.0) - 0.05)
        z_heat = opts.get("heat_z")
        if z_heat is not None:
            heat = s.m("ADD", heat, s.m("MULTIPLY", s.ramp(z_heat[0], z_heat[1], k["z"]), 0.45))
        scorch = s.ramp(0.5, 0.75, heat)
        rim = s.m("SUBTRACT", s.ramp(0.42, 0.55, heat), scorch, clamp=True)
        surf.col = s.mix(s.m("MULTIPLY", rim, 0.35), surf.col, srgb(*BURNT))
        surf.col = s.mix(s.m("MULTIPLY", scorch, 0.8), surf.col, srgb(*SOOT))
        surf.rough = s.mixf(scorch, surf.rough, 0.9)
        ash = s.m("MAXIMUM", s.m("MULTIPLY", _low(s, k, 0.0, 0.6, 0.8), 0.6), s.m("MULTIPLY", k["cavity"], 0.45))
        ash = s.m(
            "MULTIPLY",
            s.ramp(0.2, 0.8, s.m("ADD", ash, s.m("MULTIPLY", s.m("SUBTRACT", k["grain"], 0.5), 1.5))),
            keep_top,
        )
        surf.col = s.mix(s.m("MULTIPLY", ash, amount), surf.col, srgb(*ASH))
        surf.rough = s.mixf(ash, surf.rough, 0.93)
        surf.metal = s.mixf(s.m("MAXIMUM", ash, scorch), surf.metal, 0.0)
    return surf


def _heat_tint(s: Shader, k: dict, steel) -> bpy.types.NodeSocket:
    """Bare steel heat-tinted in bands (straw, bronze, purple, blue), kept dull."""
    tint = s.palette(s.spread(s.noise(1.8, 3.0, 0.55), 3.0), HEAT_TINTS)
    return s.mix(s.ramp(0.45, 0.6, k["patch"]), steel, tint)


def _paint(s: Shader, k: dict, w: str, color, opts: dict) -> Surface:
    """Weathered paint on steel: tone, chipped edges and worn patches down to steel, rust runs, grime."""
    wear = opts.get("wear", 0.5)
    rust = opts.get("rust", 0.5)
    base = srgb(*color)
    if opts.get("hazard"):
        stripe = s.stripes(opts.get("period", 0.36))
        base = s.mix(stripe, srgb(*opts.get("under", (0.09, 0.09, 0.09))), srgb(*AMBER))
    col = s.scale_color(base, s.m("MULTIPLY_ADD", k["tone"], 0.6, 0.7))
    col = s.scale_color(col, s.m("MULTIPLY_ADD", k["grain"], 0.25, 0.875))
    breakup = s.noise(4.0, 5.0, 0.65)
    chips = s.m("MULTIPLY", k["edge"], s.ramp(0.53 - 0.1 * wear, 0.6 - 0.1 * wear, breakup))
    patches = s.ramp(0.71 - 0.04 * wear, 0.735 - 0.04 * wear, s.noise(1.7, 6.0, 0.7))
    chips = s.m("MAXIMUM", chips, s.m("MULTIPLY", patches, wear))
    steel = s.mix(s.spread(k["grain"], 2.0), srgb(*STEEL), srgb(0.42, 0.41, 0.4))
    if w == "ash":
        steel = _heat_tint(s, k, steel)
    rusty = s.ramp(0.5, 0.6, s.noise(6.0, 3.0, 0.6))
    steel = s.mix(s.m("MULTIPLY", rusty, rust), steel, srgb(*RUST))
    col = s.mix(chips, col, steel)
    runs = s.m("MULTIPLY", s.ramp(0.57, 0.68, k["streak"]), s.ramp(0.45, 0.6, k["patch"]))
    col = s.mix(s.m("MULTIPLY", runs, 0.45 * rust), col, srgb(*RUST))
    col = s.mix(s.m("MULTIPLY", k["cavity"], opts.get("grime", 0.6)), col, srgb(*GRIME))
    paint_rough = opts.get("rough", 0.62)
    rough = s.mixf(k["tone"], paint_rough - 0.05, paint_rough + 0.05)
    rough = s.mixf(chips, rough, 0.4)
    rough = s.mixf(k["cavity"], rough, 0.85)
    metal = s.m("MULTIPLY", chips, s.m("SUBTRACT", 1.0, s.m("MULTIPLY", rusty, rust)))
    height = s.m("SUBTRACT", s.m("MULTIPLY", k["grain"], 0.15), s.m("MULTIPLY", chips, 0.5))
    return Surface(col, rough, metal, height)


def _steel(s: Shader, k: dict, w: str, color, opts: dict) -> Surface:
    """Bare or galvanized steel: tone, rust runs, grime; heat-tinted in the Ash fields."""
    col = s.mix(s.spread(k["tone"], 3.0), srgb(*color), srgb(*(min(1.0, c * 1.15) for c in color)))
    col = s.scale_color(col, s.m("MULTIPLY_ADD", k["grain"], 0.3, 0.85))
    if w == "ash":
        col = _heat_tint(s, k, col)
    rust = opts.get("rust", 0.4)
    runs = s.m("MULTIPLY", s.ramp(0.56, 0.66, k["streak"]), s.ramp(0.45, 0.6, k["patch"]))
    col = s.mix(s.m("MULTIPLY", runs, 0.55 * rust), col, srgb(*RUST))
    col = s.mix(s.m("MULTIPLY", k["cavity"], 0.6), col, srgb(*GRIME))
    rough = s.mixf(k["grain"], opts.get("rough", 0.42) - 0.06, opts.get("rough", 0.42) + 0.08)
    rough = s.mixf(runs, rough, 0.7)
    metal = s.m("SUBTRACT", 1.0, s.m("MULTIPLY", runs, rust))
    return Surface(col, rough, metal, s.m("MULTIPLY", k["grain"], 0.2))


def _glass(s: Shader, k: dict, w: str, color, opts: dict) -> Surface:
    """Dark tinted window glass, glossy, with a grime film in the corners."""
    col = s.mix(s.m("MULTIPLY", k["cavity"], 0.5), srgb(*color), srgb(*GRIME))
    rough = s.mixf(s.spread(k["patch"], 3.0), 0.08, 0.22)
    return Surface(col, rough, 0.0, 0.0)


def _crust(s: Shader, k: dict, w: str, color, opts: dict) -> Surface:
    """Thick salt crust lumps: crystalline off-white, grey hollows, a faint dusty film."""
    lump = s.noise(9.0, 5.0, 0.65)
    col = s.mix(s.spread(s.noise(60.0, 2.0, 0.6), 2.5), srgb(*SALT[0]), srgb(*SALT[1]))
    col = s.mix(s.m("MULTIPLY", s.spread(lump, 2.5), 0.35), col, srgb(0.5, 0.495, 0.48))
    col = s.mix(s.m("MULTIPLY", k["cavity"], 0.7), col, srgb(0.36, 0.35, 0.33))
    col = s.mix(s.m("MULTIPLY", s.ramp(0.52, 0.66, k["patch"]), 0.4), col, srgb(0.44, 0.42, 0.39))
    return Surface(col, 0.92, 0.0, s.m("ADD", s.m("MULTIPLY", lump, 1.0), s.m("MULTIPLY", k["grain"], 0.3)))


def _sand(s: Shader, k: dict, w: str, color, opts: dict) -> Surface:
    """Drifted Dust flats sand: fine, with faint wind ripples."""
    wave = s.nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 0.6
    wave.inputs["Distortion"].default_value = 4.0
    wave.inputs["Detail Scale"].default_value = 0.6
    s.nt.links.new(s.obj, wave.inputs["Vector"])
    col = s.mix(s.spread(k["tone"], 3.0), srgb(0.33, 0.295, 0.25), srgb(0.39, 0.345, 0.29))
    col = s.mix(s.m("MULTIPLY", s.spread(k["grain"], 2.0), 0.4), col, srgb(0.30, 0.27, 0.23))
    col = s.mix(s.m("MULTIPLY", k["cavity"], 0.5), col, srgb(0.22, 0.20, 0.18))
    height = s.m("ADD", s.m("MULTIPLY", wave.outputs["Fac"], 0.5), s.m("MULTIPLY", k["grain"], 0.3))
    return Surface(col, 0.95, 0.0, height)


def _lamp(s: Shader, k: dict, w: str, color, opts: dict) -> Surface:
    return Surface(srgb(*(c * 0.6 for c in color)), 0.25, 0.0, 0.0)


def _ember(s: Shader, k: dict, w: str, color, opts: dict) -> Surface:
    """Dark cinders with a dull glow in the cracks between them (the emission is set in mat())."""
    col = s.mix(s.spread(k["grain"], 2.0), srgb(0.05, 0.042, 0.038), srgb(0.1, 0.08, 0.07))
    return Surface(col, 0.9, 0.0, s.m("MULTIPLY", k["grain"], 0.4))


KINDS = {
    "paint": _paint,
    "steel": _steel,
    "glass": _glass,
    "crust": _crust,
    "sand": _sand,
    "lamp": _lamp,
    "ember": _ember,
}


def mat(name: str, kind: str, color, weather: str, opts: dict) -> bpy.types.Material:
    """One look as a procedural material. Lamps and embers glow (their emission is baked into the kit's map)."""
    material, nt, bsdf = C._new_material(name)
    s = Shader(nt)
    k = _common_masks(s)
    surf = KINDS[kind](s, k, weather, color, opts)
    if kind in ("paint", "steel", "glass"):
        surf = _weather(s, k, weather, surf, opts)
    for sock, val in ((bsdf.inputs["Base Color"], surf.col), (bsdf.inputs["Roughness"], surf.rough)):
        if isinstance(val, bpy.types.NodeSocket):
            nt.links.new(val, sock)
        elif sock.type == "RGBA":
            sock.default_value = (*val, 1.0)
        else:
            sock.default_value = val
    if isinstance(surf.metal, bpy.types.NodeSocket):
        nt.links.new(surf.metal, bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Metallic"].default_value = surf.metal
    if isinstance(surf.height, bpy.types.NodeSocket):
        C._bump(nt, bsdf, surf.height, opts.get("bump", 0.3), 0.01)
    if kind == "lamp":
        bsdf.inputs["Emission Color"].default_value = (*srgb(*color), 1.0)
        bsdf.inputs["Emission Strength"].default_value = opts.get("strength", 6.0)
    elif kind == "ember":
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = opts.get("cells", 3.0)
        nt.links.new(s.obj, vor.inputs["Vector"])
        cracks = s.m("SUBTRACT", 1.0, s.ramp(0.0, 0.12, vor.outputs["Distance"]), clamp=True)
        glow = s.m("ADD", s.m("MULTIPLY", cracks, 0.8), s.m("MULTIPLY", s.ramp(0.45, 0.65, k["tone"]), 0.35))
        glow = s.m("MULTIPLY", glow, s.ramp(0.35, 0.65, s.noise(2.0, 3.0, 0.5)))
        bsdf.inputs["Emission Color"].default_value = (*srgb(*color), 1.0)
        nt.links.new(s.m("MULTIPLY", glow, opts.get("strength", 3.0)), bsdf.inputs["Emission Strength"])
    return material


class Looks:
    """A kit's materials, picked by name: Looks(weather, {name: (kind, color, opts)}); looks["bone"] is the
    material index, looks.mats the list a Piece gets (made on first use, after the scene's reset)."""

    def __init__(self, weather: str, table: dict):
        self.weather = weather
        self.table = table
        self.names = list(table)
        self._mats: list | None = None

    @property
    def mats(self) -> list:
        if self._mats is None or any(m.name not in bpy.data.materials for m in self._mats):
            w = self.weather
            self._mats = [mat(f"{w}_{n}", kind, color, w, opts) for n, (kind, color, opts) in self.table.items()]
        return self._mats

    def __getitem__(self, name: str) -> int:
        return self.names.index(name)


# --- mesh builder ---------------------------------------------------------------------------------------


def hull_verts(bm: bmesh.types.BMesh, points: list) -> list:
    """Convex hull of `points` added to `bm`; returns its verts."""
    verts = [bm.verts.new(p) for p in points]
    res = bmesh.ops.convex_hull(bm, input=verts, use_existing_faces=False)
    kill = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
    faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace) and g.is_valid]
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return [v for v in verts if v.is_valid]


class Piece(C.Part):
    """common.Part with a chunky bevel only where wanted: edges sharper than 35 degrees between hard faces get a
    bevel weight (the modifier bevels by weight); soft() primitives (crust lumps, sand, hulls) stay unbevelled.
    The finished object is linked at the kit's root (no parent)."""

    def __init__(self, name: str, looks: Looks, bevel: tuple[float, int] = (0.035, 1)):
        super().__init__(name, looks.mats, bevel)
        self.looks = looks
        self.soft_verts: set = set()

    def soft(self, verts: list) -> list:
        self.soft_verts.update(verts)
        return verts

    def blob(self, center, size, rnd: random.Random, mi: int, count: int = 14, jitter: float = 0.22, rot=None):
        """A lumpy convex hull (crust lump, pile), smooth shaded, unbevelled."""
        golden = math.pi * (3 - math.sqrt(5))
        pts = []
        m = C.T(center, rot)
        for i in range(count):
            zz = 1 - 2 * (i + 0.5) / count
            r = math.sqrt(1 - zz * zz)
            a = i * golden
            kk = 1 + rnd.uniform(-jitter, jitter)
            pts.append(
                m
                @ Vector(
                    (math.cos(a) * r * size[0] / 2 * kk, math.sin(a) * r * size[1] / 2 * kk, zz * size[2] / 2 * kk)
                )
            )
        verts = hull_verts(self.bm, pts)
        self._tag(verts, mi, smooth=True)
        return self.soft(verts)

    def tube(self, pts: list, radii, sides: int = 8, mi: int = 0, closed: bool = False, cap: bool = True) -> list:
        """A tube along `pts` (radius per point or one radius), the frame carried along the path (no twist);
        closed=True joins the last ring to the first (a torus), else both ends are capped."""
        if not isinstance(radii, (list, tuple)):
            radii = [radii] * len(pts)
        pts = [Vector(p) for p in pts]
        n = len(pts)
        tangent = (pts[1] - pts[0]).normalized()
        ref = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
        u = tangent.cross(ref).normalized()
        rings = []
        for i, p in enumerate(pts):
            if closed:
                t = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
            else:
                t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            u = (u - t * u.dot(t)).normalized()
            v = t.cross(u)
            rings.append(
                [
                    self.bm.verts.new(
                        p + (u * math.cos(s / sides * math.tau) + v * math.sin(s / sides * math.tau)) * radii[i]
                    )
                    for s in range(sides)
                ]
            )
        pairs = list(itertools.pairwise(rings)) + ([(rings[-1], rings[0])] if closed else [])
        faces = []
        for a, b in pairs:
            for s in range(sides):
                faces.append(self.bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s])))
        if cap and not closed:
            faces.append(self.bm.faces.new(list(reversed(rings[0]))))
            faces.append(self.bm.faces.new(rings[-1]))
        for f in faces:
            f.normal_update()
        verts = [v for r in rings for v in r]
        return self._tag(verts, mi)

    def pipe(
        self,
        p0,
        p1,
        r: float,
        wall: float,
        mi: int,
        inner_mi: int | None = None,
        seg: int = 16,
        jag0: float = 0.0,
        jag1: float = 0.0,
        rnd: random.Random | None = None,
    ) -> list:
        """A hollow pipe from p0 to p1 (outer radius r, wall thickness), its ends torn jagged by up to jag0 / jag1
        m (cut back towards the middle); the inside gets inner_mi."""
        rnd = rnd or random.Random(7)
        p0, p1 = Vector(p0), Vector(p1)
        axis = (p1 - p0).normalized()
        rot = C.basis(axis, Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0)))
        ends = []
        for p, jag, sign in ((p0, jag0, 1), (p1, jag1, -1)):
            cuts = [rnd.uniform(0, jag) if jag else 0.0 for _ in range(seg)]
            if jag:  # torn: a few deep tongues between shallow bites
                cuts = [c * (0.3 if i % 3 else 1.0) for i, c in enumerate(cuts)]
            outer, inner = [], []
            for i in range(seg):
                a = i / seg * math.tau
                d = rot @ Vector((math.cos(a), math.sin(a), 0))
                q = p + axis * cuts[i] * sign
                outer.append(self.bm.verts.new(q + d * r))
                inner.append(self.bm.verts.new(q + d * (r - wall)))
            ends.append((outer, inner))
        (o0, i0), (o1, i1) = ends
        faces = []
        for i in range(seg):
            j = (i + 1) % seg
            faces.append(self.bm.faces.new((o0[i], o0[j], o1[j], o1[i])))
            faces.append(self.bm.faces.new((i0[j], i0[i], i1[i], i1[j])))
            faces.append(self.bm.faces.new((o0[j], o0[i], i0[i], i0[j])))
            faces.append(self.bm.faces.new((o1[i], o1[j], i1[j], i1[i])))
        for f in faces:
            f.normal_update()
            f.material_index = mi
            f.smooth = True
        if inner_mi is not None:
            for f in faces[1::4]:
                f.material_index = inner_mi
        return o0 + i0 + o1 + i1

    def finish(self, parent=None, center: bool = False) -> bpy.types.Object:
        """The mesh object with the bevel and weighted normals; center=True moves the origin to the middle of
        the piece's footprint (bottom center)."""
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if center:
            xs = [v.co.x for v in bm.verts]
            ys = [v.co.y for v in bm.verts]
            shift = Vector((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, 0))
            bmesh.ops.translate(bm, vec=shift, verts=bm.verts[:])
        layer = bm.edges.layers.float.get("bevel_weight_edge") or bm.edges.layers.float.new("bevel_weight_edge")
        limit = math.radians(35.0)
        for e in bm.edges:
            hard = not (e.verts[0] in self.soft_verts and e.verts[1] in self.soft_verts)
            e[layer] = 1.0 if hard and len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit else 0.0
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(self.name, me)
        C.link(obj, parent)
        for m in self.mats:
            me.materials.append(m)
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = self.bev[0]
        mod.segments = self.bev[1]
        mod.limit_method = "WEIGHT"
        mod.harden_normals = True
        obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL").keep_sharp = True
        return obj


# --- kit flow, previews, layout -------------------------------------------------------------------------


@dataclasses.dataclass
class Kit:
    """A map part kit: its pieces (name -> builder), the part's layout in Blender axes (part frame, its way in
    towards +Y: name, location, rotation XYZ degrees, scale) and the greybox values the layout keeps."""

    name: str
    weather: str
    pieces: dict
    layout: list
    prop_radius: float
    footprint: float
    crate: tuple  # ((x, y), yaw degrees) of the game's crate (1.2 x 0.8 m)
    ores: list  # [(x, y), ...] ore spots
    emission: bool = False

    @property
    def out(self) -> pathlib.Path:
        return ROOT / "tmp" / "assets" / "parts" / self.name

    @property
    def collection(self) -> str:
        return self.name


def setup_preview(kit: Kit) -> None:
    """common's preview scene (dark ground, scale figure, area lights) on the biome's ground color."""
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    lo, hi = GROUND[kit.weather]
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*lo, 1.0)
            node.inputs[7].default_value = (*hi, 1.0)
    bpy.data.objects["PreviewGround"].scale = (3, 3, 1)


def pieces(kit: Kit) -> list:
    return [bpy.data.objects[n] for n in kit.pieces]


def render_piece(kit: Kit, name: str, prefix: str, views, samples: int, size: int) -> list:
    """The piece alone at the origin, framed by its size, the scale figure beside it."""
    obj = bpy.data.objects[name]
    for o in pieces(kit):
        o.hide_render = o is not obj
    keep = obj.location.copy(), obj.rotation_euler.copy(), obj.scale.copy()
    obj.location, obj.rotation_euler, obj.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)
    bpy.context.view_layer.update()
    lo, hi = bounds(obj)
    center = (lo + hi) / 2
    dx, dy, dz = hi - lo
    fig = bpy.data.objects["PreviewFigure"]
    side = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
    fig.location = Vector((center.x, center.y, 0)) + side * (max(dx, dy) / 2 + 0.6)
    w = max(dx, dy, dz * 1.1) * 1.25 + 1.4
    target = Vector((center.x, center.y, 0)) + side * 0.3 + Vector((0, 0, max(0.4, hi.z * 0.42)))
    out = []
    for view in views:
        path = kit.out / f"{prefix}{name}_{view}.png"
        zoom = w / (9.9 if view == "iso" else 6.3)
        C.render(path, view=view, samples=samples, size=size, target=tuple(target), zoom=zoom)
        out.append(path)
    obj.location, obj.rotation_euler, obj.scale = keep
    for o in pieces(kit):
        o.hide_render = False
    return out


def bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    """World bounds of the evaluated mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [obj.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return Vector(map(min, *pts)), Vector(map(max, *pts))


def apply_layout(kit: Kit) -> None:
    for o in pieces(kit):
        o.hide_render = True
    for name, loc, rot, scale in kit.layout:
        obj = bpy.data.objects[name]
        obj.rotation_mode = "XYZ"
        obj.location = loc
        obj.rotation_euler = tuple(math.radians(a) for a in rot)
        obj.scale = (scale,) * 3 if isinstance(scale, (int, float)) else scale
        obj.hide_render = False


def _marker_mat(name: str, color, emission: float = 0.0) -> bpy.types.Material:
    material, _nt, bsdf = C._new_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return material


def _preview_mesh(name: str, bm: bmesh.types.BMesh, material: bpy.types.Material) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    C.link(obj, None, "Preview")
    C.assign(obj, material)
    return obj


def layout_extras(kit: Kit) -> list:
    """Preview-only helpers: the 1.89 m pole, the prop radius as a thin ring (the footprint as a fainter one),
    the game's crate (1.2 x 0.8 x 0.7 m with its amber band) and the ore spots (cyan, the ore node's 1.35 m disc)."""
    objs = []
    ring = _marker_mat("LayoutRing", (0.8, 0.8, 0.75), 0.6)
    faint = _marker_mat("LayoutFaint", (0.35, 0.35, 0.33), 0.15)
    for radius, material, r in ((kit.prop_radius, ring, 0.04), (kit.footprint, faint, 0.03)):
        bm = bmesh.new()
        p = Piece.__new__(Piece)
        p.bm = bm
        pts = [(math.cos(a / 96 * math.tau) * radius, math.sin(a / 96 * math.tau) * radius, 0.02) for a in range(96)]
        Piece.tube(p, pts, r, 4, closed=True)
        objs.append(_preview_mesh(f"LayoutRing{radius}", bm, material))
    pole = _marker_mat("LayoutPole", (0.75, 0.75, 0.72))
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        segments=12,
        radius1=0.06,
        radius2=0.06,
        depth=PLAYER,
        matrix=Matrix.Translation((0, 0, PLAYER / 2)),
    )
    obj = _preview_mesh("LayoutPole", bm, pole)
    obj.location = (kit.prop_radius * 0.72, -kit.prop_radius * 0.72, 0)
    objs.append(obj)
    crate = _marker_mat("LayoutCrate", srgb(*OLIVE))
    band = _marker_mat("LayoutCrateBand", srgb(1.0, 0.62, 0.15), 3.0)
    (cx, cy), yaw = kit.crate
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=C.T((0, 0, 0.35), None, (1.2, 0.8, 0.7)))
    obj = _preview_mesh("LayoutCrate", bm, crate)
    obj.location, obj.rotation_euler = (cx, cy, 0), (0, 0, math.radians(yaw))
    objs.append(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=C.T((0, 0, 0.5), None, (1.24, 0.84, 0.06)))
    obj = _preview_mesh("LayoutCrateBand", bm, band)
    obj.location, obj.rotation_euler = (cx, cy, 0), (0, 0, math.radians(yaw))
    objs.append(obj)
    crystal = _marker_mat("LayoutOre", srgb(0.12, 0.9, 0.85), 3.0)
    disc = _marker_mat("LayoutOreDisc", (0.05, 0.12, 0.12))
    rnd = random.Random(3)
    for i, (ox, oy) in enumerate(kit.ores):
        bm = bmesh.new()
        bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            segments=24,
            radius1=1.35,
            radius2=1.35,
            depth=0.02,
            matrix=Matrix.Translation((0, 0, 0.01)),
        )
        obj = _preview_mesh(f"LayoutOreDisc{i}", bm, disc)
        obj.location = (ox, oy, 0)
        objs.append(obj)
        bm = bmesh.new()
        for j in range(7):
            a = j / 7 * math.tau + rnd.uniform(-0.3, 0.3)
            r = rnd.uniform(0.3, 0.9)
            h = rnd.uniform(0.5, 1.1)
            m = C.T((math.cos(a) * r, math.sin(a) * r, h * 0.4), C.rx(-math.sin(a) * 25) @ C.ry(math.cos(a) * 25))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.14, radius2=0.0, depth=h, matrix=m)
        obj = _preview_mesh(f"LayoutOre{i}", bm, crystal)
        obj.location = (ox, oy, 0)
        objs.append(obj)
    return objs


def game_light() -> tuple[list, tuple]:
    """Dim, cool outside light like the game's: a weak low sun and a little sky. Returns what to undo."""
    lights = [o for o in C.collection("Preview").objects if o.type == "LIGHT"]
    for o in lights:
        o.hide_render = True
    data = bpy.data.lights.new("LayoutSun", "SUN")
    data.energy = 3.0
    data.color = (0.86, 0.9, 1.0)
    data.angle = math.radians(2.0)
    sun = bpy.data.objects.new("LayoutSun", data)
    C.link(sun, None, "Preview")
    sun.rotation_euler = (math.radians(62), 0, math.radians(-45))  # 28 degrees up, from the camera's left
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    old = tuple(bg.inputs["Color"].default_value), bg.inputs["Strength"].default_value
    bg.inputs["Color"].default_value = (0.05, 0.06, 0.08, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    return lights + [sun], old


def render_layout(kit: Kit, prefix: str, samples: int, size: int) -> list:
    """The part as laid out, from the game's angle (50 degrees down, 45 around) and from lower and closer."""
    apply_layout(kit)
    fig = bpy.data.objects["PreviewFigure"]
    fig.hide_render = True
    extras = layout_extras(kit)
    undo, old = game_light()
    out = []
    reach = kit.footprint + 1.5
    for view, pitch, dist, lens in (("layout", 50.0, reach * 2.75, 50.0), ("layout_low", 28.0, reach * 1.55, 40.0)):
        d = Vector(
            (
                math.cos(math.radians(pitch)) * math.sqrt(0.5),
                -math.cos(math.radians(pitch)) * math.sqrt(0.5),
                math.sin(math.radians(pitch)),
            )
        )
        target = Vector((0, 0, 0.6))
        path = kit.out / f"{prefix}{view}.png"
        C.render_from(path, target + d * dist, target, lens=lens, samples=samples, size=size)
        out.append(path)
    for o in extras:
        bpy.data.objects.remove(o)
    for o in undo:
        if o.type == "LIGHT" and o.name.startswith("LayoutSun"):
            bpy.data.objects.remove(o)
        else:
            o.hide_render = False
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value, bg.inputs["Strength"].default_value = old
    fig.hide_render = False
    return out


def bake_layout(kit: Kit, gap: float = 3.0) -> None:
    """Saved .blend layout: every piece unrotated in one row along X, `gap` m apart, so the AO bake never picks up
    a neighbor; the bake zeroes the locations for the export."""
    x = 0.0
    for o in pieces(kit):
        o.location, o.rotation_euler, o.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)
        bpy.context.view_layer.update()
        lo, hi = bounds(o)
        o.location = (x - lo.x, -(lo.y + hi.y) / 2, 0)
        x += hi.x - lo.x + gap
    bpy.data.objects["PreviewFigure"].location = (-2.0, -2.0, 0)


# --- Godot side -----------------------------------------------------------------------------------------

TO_GODOT = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))  # Blender (x, y, z) -> Godot (x, z, -y)


def godot_transform(loc, rot_deg, scale) -> str:
    """A layout entry as Godot position, rotation_degrees (YXZ, Godot's default order) and scale."""
    r = (
        Matrix.Rotation(math.radians(rot_deg[2]), 3, "Z")
        @ Matrix.Rotation(math.radians(rot_deg[1]), 3, "Y")
        @ Matrix.Rotation(math.radians(rot_deg[0]), 3, "X")
    )
    g = TO_GODOT @ r @ TO_GODOT.transposed()
    e = g.to_euler("ZXY")  # R = Ry @ Rx @ Rz, Godot's YXZ
    p = TO_GODOT @ Vector(loc)
    s = scale if isinstance(scale, (int, float)) else scale[0]
    return (
        f"position ({p.x:.2f}, {p.y:.2f}, {p.z:.2f}), rotation ({math.degrees(e.x):.1f}, {math.degrees(e.y):.1f}, "
        f"{math.degrees(e.z):.1f}), scale {s:g}"
    )


def print_layout(kit: Kit) -> None:
    for name, loc, rot, scale in kit.layout:
        print(f"LAYOUT {name}: {godot_transform(loc, rot, scale)}")
    (cx, cy), yaw = kit.crate
    print(f"LAYOUT crate marker: {godot_transform((cx, cy, 0), (0, 0, yaw), 1)}")
    for x, y in kit.ores:
        print(f"LAYOUT ore marker: {godot_transform((x, y, 0), (0, 0, 0), 1)} (r {math.hypot(x, y):.1f} m)")


def report(kit: Kit) -> None:
    dg = bpy.context.evaluated_depsgraph_get()
    for o in pieces(kit):
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
        lo, hi = bounds(o)
        size = tuple(round(v, 2) for v in hi - lo)
        print(
            f"STATS {o.name}: tris={tris} size={size} min={tuple(round(v, 2) for v in lo)} max={tuple(round(v, 2) for v in hi)}"
        )
    print_layout(kit)


def build(kit: Kit) -> None:
    C.reset(kit.collection)
    for builder in kit.pieces.values():
        builder()


def main(kit: Kit) -> None:
    """wip <tag> [views]: views are piece names, "pieces" (all), "layout", "sheet"; final: everything, the
    contact sheet and the procedural .blend for the bake."""
    argv = C.args()
    mode = argv[0] if argv else "wip"
    tag = argv[1] if len(argv) > 1 else "w0"
    views = argv[2].split(",") if len(argv) > 2 else ["layout"]
    build(kit)
    report(kit)
    setup_preview(kit)
    if mode == "final":
        sheet = render_layout(kit, "final_", 96, 1024)
        for name in kit.pieces:
            sheet += render_piece(kit, name, "final_", ("iso", "hero"), 48, 640)
        C.contact_sheet(sheet, kit.out / "sheet.png", cols=4, tile=512, background=0.02)
        bake_layout(kit)
        C.save_blend(kit.out / f"{kit.name}_procedural.blend")
        return
    wip = kit.out / "wip"
    for view in views:
        if view == "layout":
            render_layout(kit, f"wip/{tag}_", 32, 900)
        elif view == "pieces":
            for name in kit.pieces:
                render_piece(kit, name, f"wip/{tag}_", ("iso", "hero"), 24, 560)
        elif view in kit.pieces:
            render_piece(kit, view, f"wip/{tag}_", ("iso", "hero"), 32, 640)
        elif view == "sheet":
            names = sorted(wip.glob(f"{tag}_*.png"))
            C.contact_sheet(names, wip / f"{tag}_sheet.png", cols=4, tile=448, background=0.02)


# --- bake ---------------------------------------------------------------------------------------------


def hidden_scale(obj: bpy.types.Object, poly: bpy.types.MeshPolygon) -> float | None:
    """UV scale for faces nobody sees: flat bottoms below the ground."""
    if poly.normal.z < -0.97 and poly.center.z < -0.04:
        return 0.08
    return None


def bake_finish(job, objs: list) -> None:
    for o in objs:
        o.location, o.rotation_euler, o.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)


def bake_checks(kit: Kit, job, meshes: list) -> None:
    """Check renders of the baked .glb: the layout from the game's angle and each piece."""
    assert sorted(o.name for o in meshes) == sorted(kit.pieces), [o.name for o in meshes]
    for o in meshes:
        o.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    setup_preview(kit)
    sheet = []
    paths = render_layout(kit, "", 96, 1024)  # into the kit's tmp folder, moved next to the bake's checks
    for p in paths:
        target = job.game / f"check_{p.name}"
        target.parent.mkdir(parents=True, exist_ok=True)
        p.replace(target)
        sheet.append(target)
    for name in kit.pieces:
        for p in render_piece(kit, name, "", ("iso",), 48, 640):
            target = job.game / f"check_{p.name}"
            p.replace(target)
            sheet.append(target)
    C.contact_sheet(sheet, job.game / "check_sheet.png", cols=3, tile=512, background=0.02)
