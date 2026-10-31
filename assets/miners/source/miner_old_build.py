"""Miner, "old" variant: Hollis' old miner, a static prop. The glow miner's shape, about twenty years older and kept
running alone in an overgrown bog: faded, sun-bleached paint, chipped edges and scratches down to bare metal, rust
streaks running down from the seams and bolts, mud caked on the feet and the lower legs, the front panel of the right
side box gone (its wiring and parts exposed), a primer patch plate bolted over the left box's vents, a dented leg
plate, a few bolts missing, the hose taped up in three places, half the status lights dead and the lamp off; the
column holds a little dull ore.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/miners/source/miner_old_build.py wip r1 [views, e.g. iso,isoclose,hero,boxes,leg,tape]
    tools/blender.sh assets/miners/source/miner_old_build.py final

Everything it writes goes to tmp/miner_assets/old/: "wip <tag> [views]" renders quick previews into wip/<tag>_*.png;
"final" renders iso/hero/back at full quality and saves the procedural miner_old.blend that miner_old_bake.py turns
into the game asset. The preview scene is dark and the worn paint shows little in it: env var PREVIEW_EXPOSURE=1.5
renders brighter (wip only).

The geometry comes from the glow miner's build (miner_glow_build.py): its part builders run unchanged with this
script's Part, which drops a few of their primitives, dents one, and adds the repairs and the damage before each part
is finished. The materials are this script's own (worn versions of the glow miner's).
"""

import itertools
import math
import os
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "miner_assets" / "old"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "assets" / "miners" / "source"))

import bmesh
import bpy
from mathutils import Vector

import common as C
import miner_glow_build as G
from common import basis, rx, ry

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["iso", "hero"]

FILL_LEVEL = 0.3  # the column is mostly empty
# Heights of the seams, flanges and bolt rows rust runs down from (the column, the boxes, the leg joints).
SEAMS = (3.30, 3.16, 2.79, 2.70, 2.22, 1.98, 1.76, 1.47, 1.13, 1.04, 0.93, 0.86, 0.77, 1.32)
M_PAINT, M_DARK, M_STEEL, M_PRIMER, M_TAPE, M_WIRE_RED, M_WIRE_YEL, M_MUD = range(8)

# --- node helpers -------------------------------------------------------------------------------------------------


class Nodes:
    """Shorthands for one material's node tree (object coordinates are world coordinates: every part sits at the
    origin)."""

    def __init__(self, nt: bpy.types.NodeTree):
        self.nt = nt
        self.geo = nt.nodes.new("ShaderNodeNewGeometry")
        self.coord = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        pos = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(self.geo.outputs["Position"], pos.inputs["Vector"])
        self.z = pos.outputs["Z"]
        nrm = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(self.geo.outputs["Normal"], nrm.inputs["Vector"])
        self.nz = nrm.outputs["Z"]

    def noise(self, scale, detail=6.0, rough=0.6, vec=None, distortion=0.0) -> bpy.types.NodeSocket:
        return C._noise(self.nt, scale, detail, rough, vec or self.coord, distortion).outputs["Fac"]

    def stretched(self, scale, rot=(0.0, 0.0, 0.0)) -> bpy.types.NodeSocket:
        m = self.nt.nodes.new("ShaderNodeMapping")
        m.inputs["Scale"].default_value = scale
        m.inputs["Rotation"].default_value = rot
        self.nt.links.new(self.coord, m.inputs["Vector"])
        return m.outputs["Vector"]

    def remap(self, src, a, b, c=0.0, d=1.0) -> bpy.types.NodeSocket:
        """Clamped linear map of src from a..b to c..d."""
        n = self.nt.nodes.new("ShaderNodeMapRange")
        n.clamp = True
        self.nt.links.new(src, n.inputs["Value"])
        for name, v in (("From Min", a), ("From Max", b), ("To Min", c), ("To Max", d)):
            n.inputs[name].default_value = v
        return n.outputs["Result"]

    def m(self, op, a, b=None, clamp=False) -> bpy.types.NodeSocket:
        return C._math(self.nt, op, a, b, clamp=clamp)

    def mix(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_float(self.nt, fac, a, b)

    def ao(self, distance) -> bpy.types.NodeSocket:
        n = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        n.inputs["Distance"].default_value = distance
        return n.outputs["AO"]

    def mud(self) -> bpy.types.NodeSocket:
        """Caked mud: solid up to a wobbly line about 0.3 m up, splashes fading out by 1.2 m, more on what faces up."""
        wobble = self.m("MULTIPLY", self.m("SUBTRACT", self.noise(2.5, 6.0), 0.5), 0.55)
        line = self.remap(self.m("ADD", self.z, wobble), 0.3, 0.62, 1.0, 0.0)
        splash = self.m(
            "MULTIPLY", C._ramp(self.nt, 0.56, 0.62, self.noise(6.0, 10.0, 0.7)), self.remap(self.z, 0.3, 1.4, 1, 0)
        )
        up = self.remap(self.nz, 0.2, 0.9, 0.0, 0.35)
        return self.m("ADD", self.m("MAXIMUM", line, splash), self.m("MULTIPLY", up, line), clamp=True)

    def mud_layer(self, mud, col, rough, height):
        """Lay the mud over a layer stack (color, roughness, bump height sockets)."""
        # Wet and dark at the bottom, drying to a lighter crust toward the top of the mud line and on the splashes.
        dry = self.m("ADD", self.remap(self.z, 0.0, 0.25), self.m("MULTIPLY", self.noise(5.0, 6.0), 0.5), clamp=True)
        dry = self.m("MULTIPLY", C._ramp(self.nt, 0.35, 0.75, dry), self.remap(mud, 0.3, 1.0, 1.0, 0.6))
        mud_col = self.mix(dry, (0.04, 0.027, 0.014), (0.095, 0.068, 0.036))
        mud_col = self.mix(
            self.m("MULTIPLY", C._ramp(self.nt, 0.55, 0.7, self.noise(1.6)), 0.5), mud_col, (0.045, 0.045, 0.016)
        )
        col = self.mix(mud, col, mud_col)
        rough = self.mixf(mud, rough, self.mixf(dry, 0.55, 0.95))
        lump = self.m("MULTIPLY", mud, self.m("ADD", 0.5, self.noise(30.0, 8.0, 0.7)))
        return col, rough, self.m("ADD", height, self.m("MULTIPLY", lump, 1.4))

    def rust_streaks(self, amount) -> bpy.types.NodeSocket:
        """Vertical streaks hanging from the seam heights and from under overhangs (AO), on the steep faces."""
        streak = C._ramp(self.nt, 0.57, 0.7, self.noise(1.0, 3.0, 0.5, self.stretched((26.0, 26.0, 1.4))))
        streak = self.m(
            "MULTIPLY",
            streak,
            C._ramp(self.nt, 0.35, 0.65, self.noise(1.0, 4.0, 0.5, self.stretched((70.0, 70.0, 5.0)))),
        )
        seam = None
        for h in SEAMS:
            below = self.m("LESS_THAN", self.z, h)
            f = self.m("MULTIPLY", below, self.remap(self.m("SUBTRACT", h, self.z), 0.0, 0.42, 1.0, 0.0))
            seam = f if seam is None else self.m("MAXIMUM", seam, f)
        under = self.remap(self.ao(0.3), 0.45, 0.95, 1.0, 0.0)
        source = self.m("ADD", seam, self.m("MULTIPLY", under, 0.8), clamp=True)
        steep = self.remap(self.m("ABSOLUTE", self.nz), 0.35, 0.75, 1.0, 0.0)
        return self.m("MULTIPLY", self.m("MULTIPLY", streak, source), self.m("MULTIPLY", steep, amount), clamp=True)

    def scratches(self) -> bpy.types.NodeSocket:
        """Thin wandering lines in two directions, in patches."""
        lines = None
        for scale, rot in (((2.0, 2.0, 30.0), (0.4, 0.9, 0.3)), ((30.0, 2.5, 2.0), (0.2, -0.5, 1.1))):
            s = self.noise(1.0, 2.0, 0.5, self.stretched(scale, rot))
            line = self.remap(self.m("ABSOLUTE", self.m("SUBTRACT", s, 0.5)), 0.0, 0.006, 1.0, 0.0)
            lines = line if lines is None else self.m("MAXIMUM", lines, line)
        return self.m("MULTIPLY", lines, C._ramp(self.nt, 0.55, 0.66, self.noise(2.2, 3.0)))


# --- materials ----------------------------------------------------------------------------------------------------


def mat_old_paint(name: str, color, wear=1.0, rust=1.0, fade=1.0) -> bpy.types.Material:
    """Old painted steel: paint bleached by the sun (most on what faces up) and dusty, grime in the cavities, rust
    streaks, chipped edges and flaking spots down to steel (old chips rusted), scratches, mud low on the body."""
    mat, nt, bsdf = C._new_material(name)
    n = Nodes(nt)
    # Paint: mottled, bleached toward a chalky grey on the upper faces and in large blotches.
    mottle = n.noise(6.0, 8.0, 0.65)
    paint = n.mix(mottle, tuple(c * 0.82 for c in color), tuple(c * 1.12 for c in color))
    bleach = n.m(
        "ADD", n.remap(n.nz, -0.3, 0.95, 0.15, 0.85), n.m("MULTIPLY", C._ramp(nt, 0.4, 0.75, n.noise(1.8, 5.0)), 0.4)
    )
    bleached = tuple(c * 0.5 + g for c, g in zip(color, (0.13, 0.13, 0.125)))
    col = n.mix(n.m("MULTIPLY", bleach, fade, clamp=True), paint, bleached)
    # Dust on the upward faces.
    dust = n.m("MULTIPLY", n.remap(n.nz, 0.5, 0.9), C._ramp(nt, 0.35, 0.7, n.noise(5.0, 6.0)))
    col = n.mix(n.m("MULTIPLY", dust, 0.45), col, (0.1, 0.095, 0.085))
    # Grime in the cavities.
    cavity = n.remap(n.ao(0.12), 0.3, 0.95, 0.85, 0.0)
    col = n.mix(cavity, col, (0.03, 0.028, 0.024))
    # Rust streaks.
    streak = n.rust_streaks(rust)
    rust_col = n.mix(n.noise(12.0, 6.0), (0.2, 0.075, 0.025), (0.4, 0.16, 0.05))
    col = n.mix(streak, col, rust_col)
    # Chips: along the edges (Bevel node) and flaking spots on the flat faces; some rusted through.
    edge = n.remap(C._bevel_edge(nt, 0.015, n.geo), 0.008, 0.05)
    edge_chip = n.m("MULTIPLY", edge, C._ramp(nt, 0.44, 0.52, n.noise(24.0, 10.0, 0.7)))
    flake = n.m("MULTIPLY", C._ramp(nt, 0.62, 0.635, n.noise(8.0, 12.0, 0.72)), C._ramp(nt, 0.45, 0.62, n.noise(1.4)))
    chip = n.m("MULTIPLY", n.m("MAXIMUM", edge_chip, flake), wear, clamp=True)
    rusted = C._ramp(nt, 0.62, 0.72, n.noise(14.0, 6.0))
    steel = n.mix(n.m("MULTIPLY", edge, 0.8), (0.3, 0.3, 0.295), (0.55, 0.55, 0.54))
    col = n.mix(chip, col, n.mix(rusted, steel, (0.14, 0.05, 0.02)))
    # Scratches through the paint: bright steel.
    scratch = n.m("MULTIPLY", n.scratches(), wear * 0.9)
    col = n.mix(scratch, col, (0.36, 0.35, 0.34))
    metal = n.m("MULTIPLY", n.m("MAXIMUM", n.m("MULTIPLY", chip, n.m("SUBTRACT", 1.0, rusted)), scratch), 0.8)
    rough = n.mixf(mottle, 0.62, 0.8)
    rough = n.mixf(n.m("MULTIPLY", streak, 0.85), rough, 0.85)
    rough = n.mixf(chip, rough, n.mixf(rusted, 0.5, 0.88))
    rough = n.mixf(scratch, rough, 0.42)
    height = n.m("SUBTRACT", n.m("MULTIPLY", n.noise(60.0, 4.0), 0.15), n.m("MULTIPLY", chip, 0.6))
    height = n.m("SUBTRACT", height, n.m("MULTIPLY", scratch, 0.35))
    mud = n.mud()
    col, rough, height = n.mud_layer(mud, col, rough, height)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    nt.links.new(n.m("MULTIPLY", metal, n.m("SUBTRACT", 1.0, mud)), bsdf.inputs["Metallic"])
    C._bump(nt, bsdf, height, 0.5, 0.004)
    return mat


def mat_old_steel(name: str) -> bpy.types.Material:
    """Bare steel that has been out in the wet for decades: dull, rust in patches and in the cavities, mud low."""
    mat, nt, bsdf = C._new_material(name)
    n = Nodes(nt)
    mottle = n.noise(30.0, 6.0)
    col = n.mix(mottle, (0.2, 0.195, 0.19), (0.36, 0.35, 0.34))
    cavity = n.remap(n.ao(0.08), 0.4, 0.95, 1.0, 0.0)
    rust = n.m("ADD", C._ramp(nt, 0.5, 0.6, n.noise(7.0, 8.0, 0.7)), cavity, clamp=True)
    col = n.mix(rust, col, n.mix(n.noise(15.0), (0.1, 0.035, 0.015), (0.23, 0.085, 0.03)))
    rough = n.mixf(rust, n.mixf(mottle, 0.4, 0.6), 0.88)
    height = n.m("MULTIPLY", rust, n.noise(80.0, 6.0))
    mud = n.mud()
    col, rough, height = n.mud_layer(mud, col, rough, height)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    met = n.m("MULTIPLY", n.m("SUBTRACT", 1.0, rust), n.m("SUBTRACT", 1.0, mud))
    nt.links.new(met, bsdf.inputs["Metallic"])
    C._bump(nt, bsdf, height, 0.4, 0.003)
    return mat


def mat_old_rubber(name: str, color=(0.03, 0.03, 0.03)) -> bpy.types.Material:
    """Sun-baked rubber: greyed in a dusty bloom, fine cracks, mud low."""
    mat, nt, bsdf = C._new_material(name)
    n = Nodes(nt)
    col = n.mix(C._ramp(nt, 0.35, 0.7, n.noise(5.0, 6.0)), color, tuple(c * 0.6 + 0.04 for c in color))
    cracks = C._voronoi_lines(nt, n.stretched((1.0, 1.0, 1.0)), 45.0, 0.04)
    col = n.mix(n.m("MULTIPLY", C._bw(nt, cracks), 0.7), col, (0.012, 0.012, 0.012))
    rough = n.mixf(n.noise(20.0), 0.75, 0.92)
    height = n.m("MULTIPLY", C._bw(nt, cracks), -0.6)
    mud = n.mud()
    col, rough, height = n.mud_layer(mud, col, rough, height)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    C._bump(nt, bsdf, height, 0.4, 0.002)
    return mat


def mat_tape(name: str) -> bpy.types.Material:
    """Grey cloth tape, dirty, the wraps' edges darker."""
    mat, nt, bsdf = C._new_material(name)
    n = Nodes(nt)
    col = n.mix(C._ramp(nt, 0.3, 0.75, n.noise(9.0, 6.0)), (0.3, 0.295, 0.28), (0.13, 0.12, 0.105))
    cavity = n.remap(n.ao(0.03), 0.4, 0.95, 0.8, 0.0)
    col = n.mix(cavity, col, (0.03, 0.028, 0.024))
    rough = n.mixf(n.noise(40.0), 0.38, 0.65)
    weave = n.noise(1.0, 2.0, 0.5, n.stretched((400.0, 400.0, 120.0)))
    mud = n.mud()
    col, rough, height = n.mud_layer(mud, col, rough, n.m("MULTIPLY", weave, 0.3))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    C._bump(nt, bsdf, height, 0.3, 0.002)
    return mat


def mat_mud(name: str) -> bpy.types.Material:
    """The clumps caked on the feet: all mud."""
    mat, nt, bsdf = C._new_material(name)
    n = Nodes(nt)
    col, rough, height = n.mud_layer(n.remap(n.z, 0.0, 1.0, 1.0, 1.0), (0.05, 0.04, 0.03), 0.9, 0.0)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    C._bump(nt, bsdf, height, 0.5, 0.006)
    return mat


def make_materials() -> None:
    """The glow miner's material slots (the module globals its builders read), worn; plus the repair materials."""
    G.PAINT = mat_old_paint("Paint_Main", (0.095, 0.098, 0.1))
    G.PAINT_DARK = mat_old_paint("Paint_Dark", (0.043, 0.045, 0.047), wear=0.85)
    G.STEEL = mat_old_steel("BareMetal")
    G.RUBBER = mat_old_rubber("Rubber")
    primer = mat_old_paint("Primer", (0.13, 0.05, 0.03), wear=0.45, rust=0.6, fade=0.5)
    tape = mat_tape("Tape")
    wire_red = mat_old_rubber("Wire_Red", (0.16, 0.03, 0.02))
    wire_yel = mat_old_rubber("Wire_Yellow", (0.25, 0.18, 0.03))
    G.FRAME_MATS = [G.PAINT, G.PAINT_DARK, G.STEEL, primer, tape, wire_red, wire_yel, mat_mud("Mud")]
    # Constant materials (outside the atlas): dirty glass, a little dull ore, dim lights, the lamp off.
    G.GLASS = C.mat_glass("Glass", tint=(0.62, 0.66, 0.56))
    G.GLASS.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.22
    G.ORE = C.mat_emissive("OreFill", (0.03, 0.3, 0.33), 0.4)
    G.CYAN = C.mat_emissive("Glow_Cyan", (0.08, 0.8, 1.0), 1.6)
    G.CYAN_SOFT = G.CYAN
    G.ORANGE = C.mat_emissive("Glow_Orange", (1.0, 0.38, 0.06), 4.0)
    G.LAMP = C.mat_emissive("FullLamp", (0.22, 0.17, 0.11), 0.0)
    global DEAD
    DEAD = C.mat_emissive("Lights_Dead", (0.035, 0.035, 0.035), 0.0)


# --- the old part: the glow miner's primitives, edited --------------------------------------------------------------


class OldPart(C.Part):
    """common.Part for the glow miner's builders: RULES[name] may drop a primitive ("skip") or edit it after it's
    made (a function (part, verts, args)); EXTRA[name](part) adds this miner's own geometry before the part is
    finished. Primitives are counted per kind (the rules can pick e.g. the 5th bolt)."""

    def __init__(self, name: str, mats: list, bevel: tuple[float, int] | None = (0.012, 2)):
        super().__init__(name, mats, bevel)
        self.count: dict[str, int] = {}
        self.prims: list = []  # (kind, verts)
        self.own = False  # set while EXTRA adds geometry: no rules

    def _prim(self, kind: str, make, args, kw):
        act = None
        if not self.own:
            i = self.count.get(kind, 0)
            self.count[kind] = i + 1
            act = next((a for rule in RULES.get(self.name, ()) if (a := rule(kind, i, args, kw))), None)
        if act == "skip":
            return []
        verts = make(*args, **kw)
        if callable(act):
            act(self, verts, args)
        self.prims.append((kind, verts))
        return verts

    def box(self, *args, **kw):
        return self._prim("box", super().box, args, kw)

    def cyl(self, *args, **kw):
        return self._prim("cyl", super().cyl, args, kw)

    def beam(self, *args, **kw):
        return self._prim("beam", super().beam, args, kw)

    def rod(self, *args, **kw):
        return self._prim("rod", super().rod, args, kw)

    def finish(self, parent) -> bpy.types.Object:
        if self.name in EXTRA:
            self.own = True
            EXTRA[self.name](self)
        return super().finish(parent)


def near(a, b, eps=1e-4) -> bool:
    return (Vector(a) - Vector(b)).length < eps


SX, SY, SZ = G.BOX_SIZE
FRONT_Y = G.BOX_Y - SY / 2  # front face of the side boxes


def rule_boxes(kind, i, args, kw):
    if kind != "box":
        return None
    loc = Vector(args[0])
    if loc.y < FRONT_Y - 0.001:  # both boxes' vent panels and slats: one torn off, one patched over
        return "skip"
    if near(loc, (G.BOX_X, G.BOX_Y, G.BOX_Z)):  # the right box: rebuilt open at the front
        return "skip"
    return None


def rule_bolts(kind, i, args, kw):
    return "skip" if kind == "cyl" and i in (4, 9, 15, 22, 23) else None


def rule_legs(kind, i, args, kw):
    # The armor plate on the right leg's lower segment (leg along +X, facing the game camera): dented.
    if kind == "beam" and args[2] == 0.21 and args[3] == 0.05 and Vector(args[0]).x > 0.5:
        return dent_plate
    return None


def dent_plate(part: OldPart, verts, args) -> None:
    """Rebuild the plate subdivided (in its own bmesh, then merged into the part) with two dents in its outer face and
    its lower end bent outward a little."""
    bmesh.ops.delete(part.bm, geom=list(verts), context="VERTS")
    p0, p1, side = Vector(args[0]), Vector(args[1]), Vector(args[4]).normalized()
    d = (p1 - p0).normalized()
    out = d.cross(side).normalized()
    if out.dot(Vector((p0.x, p0.y, 0)).normalized() + Vector((0, 0, 0.3))) < 0:
        out = -out
    plate = C.Part("DentedPlate", [])
    plate.beam(*args)
    bm = plate.bm
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=7, use_grid_fill=True)
    length = (p1 - p0).length
    for v in bm.verts:
        rel = v.co - p0
        t = rel.dot(d) / length
        s = rel.dot(side)
        depth = 0.0
        for tc, sc, r, dd in ((0.42, 0.03, 0.07, 0.036), (0.7, -0.05, 0.045, 0.02)):
            dist2 = ((t - tc) * length) ** 2 + (s - sc) ** 2
            depth += dd * math.exp(-dist2 / (2 * r * r))
        outer = rel.dot(out) > 0.0
        v.co -= out * depth * (1.0 if outer else 0.55)
        v.co += out * 0.03 * max(0.0, t - 0.75) / 0.25  # bent out at the lower end
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new("DentedPlate")
    bm.to_mesh(me)
    bm.free()
    part.bm.from_mesh(me)  # appends to the part's geometry
    bpy.data.meshes.remove(me)


def extra_boxes(part: OldPart) -> None:
    rnd = random.Random(11)
    # Right box: the front panel is gone. The body stops short of the front, a frame keeps the old outline, and the
    # parts behind the panel show: a fan, a module, capacitors, wiring (a cut wire hangs out).
    cx, cz = G.BOX_X, G.BOX_Z
    depth = 0.09
    back_y = FRONT_Y + depth
    part.box((cx, (back_y + G.BOX_Y + SY / 2) / 2, cz), (SX, G.BOX_Y + SY / 2 - back_y, SZ), mi=M_PAINT)
    ow, oh, oz = 0.34, 0.36, cz - 0.02  # opening (the old panel's size)
    fy = FRONT_Y + depth / 2
    side_w = (SX - ow) / 2
    for s in (-1, 1):
        part.box((cx + s * (ow + side_w) / 2, fy, cz), (side_w, depth, SZ), mi=M_PAINT)
    bot_h = (oz - oh / 2) - (cz - SZ / 2)
    top_h = (cz + SZ / 2) - (oz + oh / 2)
    part.box((cx, fy, cz - SZ / 2 + bot_h / 2), (ow, depth, bot_h), mi=M_PAINT)
    part.box((cx, fy, cz + SZ / 2 - top_h / 2), (ow, depth, top_h), mi=M_PAINT)
    part.box((cx, back_y - 0.004, oz), (ow + 0.01, 0.012, oh + 0.01), mi=M_DARK)
    # Fan with hub and guard bars, a module box, a row of capacitors.
    fan = Vector((cx - 0.075, back_y - 0.02, oz + 0.08))
    part.cyl(fan, 0.085, 0.03, 20, rot=rx(90), mi=M_DARK)
    part.cyl(fan - Vector((0, 0.02, 0)), 0.028, 0.02, 12, rot=rx(90), mi=M_STEEL)
    for k in range(5):
        a = k * 72 + 10
        tip = fan + Vector((math.cos(math.radians(a)) * 0.07, -0.018, math.sin(math.radians(a)) * 0.07))
        part.beam(fan - Vector((0, 0.018, 0)), tip, 0.03, 0.006, Vector((0, 1, 0)), M_STEEL)
    part.box((cx + 0.09, back_y - 0.03, oz + 0.07), (0.11, 0.05, 0.15), mi=M_DARK)
    part.box((cx + 0.09, back_y - 0.056, oz + 0.1), (0.07, 0.006, 0.04), mi=M_STEEL)
    for k in range(4):
        part.cyl((cx - 0.12 + k * 0.05, back_y - 0.03, oz - 0.11), 0.02, 0.07, 10, mi=M_STEEL if k % 2 else M_DARK)
    # Wiring: a few runs bending across the back, one cut wire hanging out of the opening.
    for mi, z0, x0, x1 in (
        (M_WIRE_RED, 0.12, -0.15, 0.15),
        (M_WIRE_YEL, -0.03, -0.15, 0.14),
        (M_DARK, -0.05, -0.14, 0.15),
    ):
        pts = [Vector((cx + x0, back_y - 0.015, oz + z0))]
        for k in range(1, 5):
            x = x0 + (x1 - x0) * k / 4
            pts.append(Vector((cx + x, back_y - 0.015 - 0.02 * rnd.random(), oz + z0 + rnd.uniform(-0.04, 0.04))))
        for a, b in itertools.pairwise(pts):
            part.rod(a, b, 0.009, 6, mi=mi)
    hang = [
        Vector((cx + 0.02, back_y - 0.02, oz - 0.05)),
        Vector((cx + 0.04, FRONT_Y - 0.01, oz - 0.12)),
        Vector((cx + 0.05, FRONT_Y - 0.05, oz - 0.2)),
        Vector((cx + 0.045, FRONT_Y - 0.06, oz - 0.3)),
    ]
    for a, b in itertools.pairwise(hang):
        part.rod(a, b, 0.009, 6, mi=M_WIRE_YEL)
    part.rod(hang[-1], hang[-1] + Vector((0, 0, -0.012)), 0.006, 6, mi=M_STEEL)
    # The torn panel's last shard, still bolted at the top left corner and bent out; bolt stubs in the other corners.
    corner = Vector((cx - ow / 2 - 0.01, FRONT_Y - 0.006, oz + oh / 2 + 0.01))
    m = C.T(corner, basis(Vector((0, -1, 0)), Vector((1, 0, 0))) @ ry(-14) @ rx(10))
    part.prism([(0.0, 0.0), (0.0, -0.085), (0.13, 0.0)], -0.004, 0.004, m, mi=M_DARK)
    for sx, sz in ((-1, 1), (1, 1), (-1, -1), (1, -1)):
        p = Vector((cx + sx * (ow / 2 + 0.025), FRONT_Y - 0.004, oz + sz * (oh / 2 + 0.025)))
        part.cyl(p, 0.009, 0.012, 6, rot=rx(90), mi=M_STEEL)
    # Left box: a primer plate bolted over the vents, a bit askew.
    lx = -G.BOX_X
    plate = Vector((lx + 0.012, FRONT_Y - 0.008, cz - 0.03))
    tilt = ry(3.5)
    part.box(plate, (0.4, 0.012, 0.4), rot=tilt, mi=M_PRIMER)
    for k in range(10):
        a = k / 10 * math.tau
        off = Vector((max(-1, min(1, math.cos(a) * 1.5)) * 0.17, 0, max(-1, min(1, math.sin(a) * 1.5)) * 0.17))
        part.cyl(plate + tilt @ off - Vector((0, 0.008, 0)), 0.013, 0.012, 6, rot=rx(90), mi=M_STEEL)


def build_mud(miner) -> None:
    """Mud caked around the feet (an own object without a bevel, which would bevel the lumps all over)."""
    part = C.Part("Mud", [G.FRAME_MATS[M_MUD]], bevel=None)
    rnd = random.Random(5)
    for deg in G.LEG_ANGLES:
        foot = C.polar(deg, G.FOOT_R)
        for _k in range(8):
            a = rnd.uniform(0, 360)
            r = rnd.uniform(0.06, 0.11)
            p = foot + C.polar(a, rnd.uniform(0.25, 0.32), rnd.uniform(0.0, 0.04))
            verts = part.sphere(p, r, 8, 5, scale=(1.4, 1.0, 0.4), rot=C.rz(a + 90))
            for v in verts:
                v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * r * 0.18
    part.finish(miner)


def cable_frame(near_point) -> tuple[Vector, Vector]:
    """Center and direction of the cable near a point (from the Cable mesh's vertices around it)."""
    import numpy as np

    me = bpy.data.objects["Cable"].data
    pts = np.array([v.co[:] for v in me.vertices if (v.co - Vector(near_point)).length < 0.1])
    c = pts.mean(axis=0)
    _vals, vecs = np.linalg.eigh(np.cov((pts - c).T))
    return Vector(c), Vector(vecs[:, -1]).normalized()


def extra_clamps(part: OldPart) -> None:
    """Taped-up stretches of the hose, each with a hose clamp at both ends and a loose tape end."""
    rnd = random.Random(3)
    for spot, n in (((-0.5, 0.25, 3.19), 5), ((-0.61, 0.95, 0.22), 4), ((-0.89, 1.56, 0.05), 3)):
        c, a = cable_frame(spot)
        step = 0.05
        for k in range(n):
            off = (k - (n - 1) / 2) * step
            tilt = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * 0.12
            ax = (a + tilt).normalized()
            r = 0.054 + rnd.uniform(0.0, 0.007)
            part.rod(c + a * off - ax * 0.034, c + a * off + ax * 0.034, r, 12, mi=M_TAPE)
        half = (n - 1) / 2 * step + 0.045
        for s in (-1, 1):
            part.rod(c + a * s * half - a * 0.008, c + a * s * half + a * 0.008, 0.052, 12, mi=M_STEEL)
        side = a.cross(Vector((0, 0, 1)))
        side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
        flap = c + side * 0.064 + a * rnd.uniform(-0.02, 0.02)
        part.box(flap, (0.004, 0.06, 0.07), rot=basis(a, side) @ ry(90) @ rx(25), mi=M_TAPE)


def extra_lights(part: OldPart) -> None:
    """About half the status lights dead."""
    rnd = random.Random(17)
    for i, (_kind, verts) in enumerate(part.prims):
        if i == 0 or rnd.random() < 0.5:  # the collar ring and every other light
            for f in {f for v in verts for f in v.link_faces}:
                f.material_index = 2


RULES = {"Frame_Boxes": [rule_boxes], "Frame_Bolts": [rule_bolts], "Frame_Legs": [rule_legs]}
EXTRA = {"Frame_Boxes": extra_boxes, "Frame_Clamps": extra_clamps, "Lights": extra_lights}

# --- main ---------------------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    G.Part = OldPart
    miner = C.miner_root()
    lights = OldPart("Lights", [G.CYAN, G.ORANGE, DEAD], bevel=None)
    G.build_column(miner, lights)
    G.build_glass(miner)
    G.build_drill(miner)
    G.build_legs(miner, lights)
    build_mud(miner)
    G.build_boxes(miner, lights)
    G.build_cable(miner)
    lights.finish(miner)
    bub = bpy.data.objects["Bubbles"]  # nothing bubbles in the near-empty column
    me = bub.data
    bpy.data.objects.remove(bub)
    bpy.data.meshes.remove(me)
    fill = bpy.data.objects["Fill"]
    fill.data.transform(C.T(scale=(1, 1, FILL_LEVEL)))
    return miner


VIEWS_OWN = {
    "boxes": ((1.2, -2.2, 2.2), (0.3, 0, 1.65), 40),
    "leg": ((2.6, -1.6, 1.3), (1.15, 0, 0.75), 40),
    "tape": ((-1.9, -1.2, 3.9), (-0.5, 0.3, 3.1), 35),
    "tape2": ((-2.4, -0.2, 1.2), (-0.7, 1.1, 0.2), 35),
}


def main() -> None:
    C.reset()
    make_materials()
    build()
    print("STATS per object", C.tris_per_object())
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(2.4, -0.6, 0.0))
    if MODE != "final":
        bpy.context.scene.view_settings.exposure = float(os.environ.get("PREVIEW_EXPOSURE", "0"))
    if MODE == "final":
        for view in ("iso", "hero", "back"):
            C.render(OUT / f"render_{view}.png", view=view, samples=96, size=1024)
        C.save_blend(OUT / "miner_old.blend")
        return
    for view in VIEWS:
        path = OUT / "wip" / f"{TAG}_{view}.png"
        if view in G.CLOSE_VIEWS:
            G.render_close(path, view)
        elif view == "isoclose":  # the game's angle, closer
            C.render(path, view="iso", samples=32, size=640, zoom=0.42)
        elif view in VIEWS_OWN:
            loc, target, lens = VIEWS_OWN[view]
            C.render_from(path, loc, target, lens, 32, 640)
        elif view != "none":
            C.render(path, view=view, samples=24, size=512)


main()
