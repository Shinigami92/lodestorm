"""Miner, "glow" variant: a glowing glass ore column on four splayed legs (concept: miner_glow_v2).

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/miners/source/miner_glow_build.py wip r1
    tools/blender.sh assets/miners/source/miner_glow_build.py final

Everything it writes goes to tmp/miner_assets/glow/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png; "final" renders iso/hero/back at full quality and saves the procedural miner_glow.blend that
miner_glow_bake.py turns into the game asset.
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "miner_assets" / "glow"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Vector

import common as C
from common import Part, basis, polar, rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["iso", "hero"]

# --- layout (meters, Z-up, front = -Y) ------------------------------------------------------------

GLASS_R = 0.28
GLASS_Z0, GLASS_Z1 = 1.10, 2.70
FILL_R = 0.245
FILL_Z0, FILL_Z1 = 1.13, 2.67
HEAD_R = 0.43  # octagon circumradius
HEAD_APO = HEAD_R * math.cos(math.pi / 8)
HEAD_Z0, HEAD_Z1 = 2.76, 3.16
EYE_Z = 2.97
LEG_ANGLES = (0.0, 90.0, 180.0, 270.0)  # legs on the axes: the iso camera (+X/-Y) looks between two legs
HIP = (0.47, 0.86)  # (radius, height) in the leg plane
KNEE = (1.00, 1.32)
ANKLE = (1.42, 0.30)
FOOT_R = 1.46
BOX_Z = 1.72
BOX_SIZE = (0.46, 0.52, 0.50)
BOX_X = 0.37 + BOX_SIZE[0] / 2
BOX_Y = 0.06

# --- mesh builder (common.Part) ---------------------------------------------------------------------


def inset_side_faces(part: Part, verts, thickness=0.035, depth=-0.012, mi=None, skip_normal: Vector | None = None):
    """Panel insets on the (roughly vertical) side faces of a freshly created primitive."""
    faces = {f for v in verts for f in v.link_faces if abs(f.normal.z) < 0.2}
    if skip_normal is not None:
        faces = {f for f in faces if f.normal.dot(skip_normal) < 0.9}
    res = bmesh.ops.inset_individual(part.bm, faces=list(faces), thickness=thickness, depth=depth, use_even_offset=True)
    if mi is not None:
        for f in faces:
            f.material_index = mi
    return res


# --- materials --------------------------------------------------------------------------------------


def mat_glass_glow() -> bpy.types.Material:
    mat = C.mat_glass("Glass", tint=(0.88, 0.97, 1.0))
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.04
    bsdf.inputs["Emission Color"].default_value = (0.2, 0.85, 1.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 0.0
    # Thin-walled look: no refraction (IOR 1, a refracting shell turns the fill into a lens-shaped blob),
    # reflections come from a clear coat instead.
    bsdf.inputs["IOR"].default_value = 1.0
    bsdf.inputs["Coat Weight"].default_value = 1.0
    bsdf.inputs["Coat IOR"].default_value = 1.5
    bsdf.inputs["Coat Roughness"].default_value = 0.03
    return mat


def mat_ore_fill() -> bpy.types.Material:
    """Packed ore chunks: Voronoi cells with dark seams and per-chunk brightness, deep saturated cyan so the
    column reads cyan instead of blowing out to white (in game the ore type's material replaces it)."""
    mat, nt, bsdf = C._new_material("OreFill")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    cells = nt.nodes.new("ShaderNodeTexVoronoi")
    cells.inputs["Scale"].default_value = 13.0
    edges = nt.nodes.new("ShaderNodeTexVoronoi")
    edges.feature = "DISTANCE_TO_EDGE"
    edges.inputs["Scale"].default_value = 13.0
    for v in (cells, edges):
        nt.links.new(coord.outputs["Object"], v.inputs["Vector"])
    rand = C._ramp(nt, 0.0, 1.0, cells.outputs["Color"])
    seam = C._ramp(nt, 0.0, 0.09, edges.outputs["Distance"])
    col = C._mix_color(nt, rand, (0.0, 0.3, 0.42), (0.12, 0.95, 0.95))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(col, bsdf.inputs["Emission Color"])
    strength = nt.nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY"
    nt.links.new(C._mix_float(nt, rand, 0.25, 3.2), strength.inputs[0])
    nt.links.new(seam, strength.inputs[1])
    nt.links.new(strength.outputs[0], bsdf.inputs["Emission Strength"])
    bsdf.inputs["Roughness"].default_value = 0.25
    C._bump(nt, bsdf, seam, 0.6, 0.02)  # seams recessed: chunks get some relief
    return mat


def make_materials() -> None:
    global PAINT, PAINT_DARK, STEEL, RUBBER, GLASS, ORE, CYAN, CYAN_SOFT, ORANGE, LAMP, FRAME_MATS
    PAINT = C.mat_painted_metal("Paint_Main", (0.07, 0.072, 0.076), wear=0.55, grime=0.6, roughness=0.55)
    PAINT_DARK = C.mat_painted_metal("Paint_Dark", (0.032, 0.033, 0.035), wear=0.45, grime=0.5, roughness=0.6)
    STEEL = C.mat_bare_metal("BareMetal", (0.45, 0.45, 0.46), 0.35)
    RUBBER = C.mat_rubber("Rubber")
    GLASS = mat_glass_glow()
    ORE = mat_ore_fill()
    CYAN = C.mat_emissive("Glow_Cyan", (0.08, 0.8, 1.0), 7.0)
    CYAN_SOFT = C.mat_emissive("Glow_CyanSoft", (0.15, 0.85, 1.0), 6.0)
    ORANGE = C.mat_emissive("Glow_Orange", (1.0, 0.38, 0.06), 14.0)
    LAMP = C.mat_emissive("FullLamp", (1.0, 0.86, 0.68), 40.0)
    FRAME_MATS = [PAINT, PAINT_DARK, STEEL]
    C.bevel_wear(PAINT)
    C.bevel_wear(PAINT_DARK)


M_PAINT, M_DARK, M_STEEL = 0, 1, 2


# --- parts ------------------------------------------------------------------------------------------


def build_column(miner, lights: Part) -> None:
    body = Part("Frame_Body", FRAME_MATS)
    bolts = Part("Frame_Bolts", FRAME_MATS, bevel=None)

    # Collar (top to bottom): glass flange, housing with vents, hip ring with leg mounts, gear ring, motor.
    body.ring(1.03, 1.12, 0.345, 24, M_DARK)
    for i in range(12):
        p = polar(i * 30 + 15, 0.318, 1.12)
        bolts.cyl(p + Vector((0, 0, 0.008)), 0.014, 0.016, 6, mi=M_STEEL)
    body.ring(0.92, 1.04, 0.37, 16, M_PAINT, r2=0.35)
    lights.ring(1.015, 1.035, 0.356, 24, mi=0)
    for side in (-1, 1):  # vent slats on the two front quarters of the housing
        ang = 270 + side * 32
        for k in range(4):
            z = 0.945 + k * 0.025
            p = polar(ang, 0.365, z)
            body.box(p, (0.2, 0.025, 0.012), rot=rz(ang + 90), mi=M_DARK)
        lights.cyl(polar(270 + side * 60, 0.362, 0.975), 0.016, 0.03, 8, rot=rz(270 + side * 60) @ ry(90), mi=1)
    hip = body.ring(0.76, 0.93, 0.43, 8, M_DARK, spin=22.5)
    inset_side_faces(body, hip, 0.03, -0.01)
    star = []
    for i in range(32):
        a = i / 32 * math.tau
        r = 0.30 if i % 2 == 0 else 0.275
        star.append((math.cos(a) * r, math.sin(a) * r))
    body.prism(star, 0.66, 0.77, mi=M_PAINT)
    body.ring(0.52, 0.67, 0.215, 12, M_DARK, r2=0.235)
    for i in range(6):
        p = polar(i * 60, 0.22, 0.595)
        body.box(p, (0.05, 0.035, 0.13), rot=rz(i * 60), mi=M_PAINT)

    # Glass struts and mounting band for the side boxes.
    for a in (45, 135, 225, 315):
        body.beam(polar(a, 0.302, GLASS_Z0), polar(a, 0.302, GLASS_Z1), 0.04, 0.03, polar(a + 90, 1, 0), M_PAINT)
    body.ring(BOX_Z - 0.04, BOX_Z + 0.04, 0.300, 24, M_DARK)
    body.ring(2.64, 2.76, 0.34, 24, M_DARK, r2=0.35)
    for a in (250, 290, 20, 160):
        lights.cyl(polar(a, 0.347, 2.70), 0.012, 0.02, 8, rot=rz(a) @ ry(90), mi=1)

    # Head: octagon with panel insets, chamfered top, bolt band, eye, side pod, hose outlet.
    body.ring(HEAD_Z0, HEAD_Z0 + 0.06, HEAD_R + 0.015, 8, M_DARK, spin=22.5)
    head = body.ring(HEAD_Z0 + 0.06, HEAD_Z1, HEAD_R, 8, M_PAINT, spin=22.5)
    inset_side_faces(body, head, 0.04, -0.014, skip_normal=Vector((0, -1, 0)))
    body.ring(HEAD_Z1, HEAD_Z1 + 0.1, HEAD_R, 8, M_PAINT, r2=HEAD_R * 0.76, spin=22.5)
    body.ring(HEAD_Z1 + 0.1, HEAD_Z1 + 0.14, HEAD_R * 0.76, 8, M_DARK, r2=HEAD_R * 0.72, spin=22.5)
    for i in range(8):
        for off in (-0.1, 0.1):
            a = i * 45
            n = polar(a, 1, 0)
            t = polar(a + 90, 1, 0)
            p = n * (HEAD_APO + 0.015) + t * off + Vector((0, 0, HEAD_Z0 + 0.03))
            bolts.cyl(p, 0.013, 0.014, 6, rot=basis(n, Vector((0, 0, 1))), mi=M_STEEL)
    # Eye housing on the front face.
    front = Vector((0, -1, 0))
    body.cyl((0, -HEAD_APO - 0.02, EYE_Z), 0.14, 0.05, 24, rot=rx(90), mi=M_DARK)
    body.cyl((0, -HEAD_APO - 0.05, EYE_Z), 0.118, 0.025, 24, rot=rx(90), mi=M_PAINT)
    for side in (-1, 1):
        lights.cyl((side * 0.11, -HEAD_APO - 0.006, HEAD_Z0 + 0.1), 0.014, 0.02, 8, rot=rx(90), mi=1)
    lights.cyl(polar(-45, HEAD_APO + 0.006, EYE_Z + 0.12), 0.014, 0.02, 8, rot=basis(polar(-45, 1, 0), front), mi=1)
    # Side pod (-X face) where the power cable leaves the head.
    pod = Vector((-HEAD_APO - 0.075, 0.05, 2.97))
    body.cyl(pod, 0.085, 0.3, 16, mi=M_DARK)
    body.cyl(pod + Vector((0, 0, 0.16)), 0.095, 0.035, 16, mi=M_PAINT)
    body.cyl(pod - Vector((0, 0, 0.16)), 0.095, 0.035, 16, mi=M_PAINT)
    body.box(pod + Vector((0.05, 0, 0)), (0.06, 0.12, 0.22), mi=M_PAINT)
    # Hose outlet coupling on the back face.
    out_z = 2.96
    body.cyl((0, HEAD_APO + 0.015, out_z), 0.11, 0.04, 16, rot=rx(90), mi=M_DARK)
    body.cyl((0, HEAD_APO + 0.08, out_z), 0.065, 0.11, 16, rot=rx(90), mi=M_STEEL)
    body.cyl((0, HEAD_APO + 0.14, out_z), 0.085, 0.04, 16, rot=rx(90), mi=M_PAINT)
    C.empty("HoseOutlet", (0, HEAD_APO + 0.16, out_z), miner)

    # Lamp post on top.
    top = HEAD_Z1 + 0.14
    body.ring(top - 0.01, top + 0.03, 0.2, 16, M_PAINT, r2=0.19)
    body.ring(top + 0.03, top + 0.06, 0.15, 16, M_DARK, r2=0.13)
    body.ring(top + 0.06, top + 0.15, 0.045, 12, M_PAINT)
    body.ring(top + 0.14, top + 0.18, 0.07, 16, M_DARK)
    cage_top = 3.593
    for i in range(4):
        a = i * 90 + 45
        body.beam(polar(a, 0.074, top + 0.17), polar(a, 0.074, cage_top), 0.014, 0.014, polar(a + 90, 1, 0), M_DARK)
    for a in (45, 135):
        body.beam(polar(a, -0.08, cage_top), polar(a, 0.08, cage_top), 0.014, 0.014, Vector((0, 0, 1)), M_DARK)

    body.finish(miner)
    bolts.finish(miner)

    lamp = Part("FullLamp", [LAMP], bevel=None)
    lamp.ring(top + 0.17, 3.545, 0.056, 16)
    lamp.sphere((0, 0, 3.545), 0.056, 16, 6, scale=(1, 1, 0.75))
    lamp.finish(miner)

    disp = Part("Display", [CYAN], bevel=None)
    disp.sphere((0, -HEAD_APO - 0.062, EYE_Z), 0.098, 20, 6, scale=(1, 0.35, 1))
    disp.finish(miner)


def build_glass(miner) -> None:
    glass = Part("Glass", [GLASS], bevel=None)
    glass.cyl((0, 0, (GLASS_Z0 + GLASS_Z1) / 2), GLASS_R, GLASS_Z1 - GLASS_Z0, 32, caps=False)
    obj = glass.finish(miner)
    sol = obj.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness = 0.012
    sol.offset = -1.0

    rnd = random.Random(7)
    fill = Part("Fill", [ORE], bevel=None)
    h = FILL_Z1 - FILL_Z0
    fill.cyl((0, 0, h / 2), FILL_R, h, 24)
    obj = fill.finish(miner)
    obj.location = (0, 0, FILL_Z0)

    bub = Part("Bubbles", [CYAN_SOFT], bevel=None)
    for i in range(16):
        r = rnd.uniform(0.012, 0.03)
        p = polar(rnd.uniform(0, 360), rnd.uniform(0.0, 0.24 - r), rnd.uniform(GLASS_Z0 + 0.2, GLASS_Z1 - 0.1))
        bub.sphere(p, r, 6, 4)
    bub.finish(miner)


def build_drill(miner) -> None:
    drill = Part("Drill", [STEEL, PAINT_DARK], bevel=None)
    bm = drill.bm
    top_z, levels, seg = 0.41, 12, 24
    rings = []
    for li in range(levels):
        z = top_z * (1 - li / levels)
        rr = 0.13 * (z / top_z) ** 0.9 + 0.004
        twist = z * 9.0
        ring = []
        for s in range(seg):
            a = s / seg * math.tau
            r = rr * (0.74 + 0.26 * math.cos(4 * (a - twist)))
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)
    tip = bm.verts.new((0, 0, 0))
    for li in range(levels - 1):
        a, b = rings[li], rings[li + 1]
        for s in range(seg):
            bm.faces.new((b[s], b[(s + 1) % seg], a[(s + 1) % seg], a[s]))
    last = rings[-1]
    for s in range(seg):
        bm.faces.new((last[s], last[(s + 1) % seg], tip))
    bm.faces.new(rings[0])
    for f in bm.faces:
        f.smooth = True
    drill.ring(0.40, 0.53, 0.15, 12, mi=1)
    drill.ring(0.44, 0.49, 0.165, 12, mi=0)
    drill.finish(miner)


def build_legs(miner, lights: Part) -> None:
    legs = Part("Frame_Legs", FRAME_MATS, bevel=(0.012, 1))
    for deg in LEG_ANGLES:
        u = polar(deg, 1, 0)
        t = polar(deg + 90, 1, 0)
        up = Vector((0, 0, 1))

        def P(r, z, u=u, up=up):
            return u * r + up * z

        hip, knee, ankle = P(*HIP), P(*KNEE), P(*ANKLE)
        rot = rz(deg)
        # Hip clevis + pin.
        for s in (-1, 1):
            legs.box(P(0.49, 0.86) + t * s * 0.085, (0.2, 0.03, 0.17), rot=rot, mi=M_DARK)
        legs.rod(hip - t * 0.115, hip + t * 0.115, 0.05, 8, mi=M_STEEL)
        # Upper segment.
        legs.beam(hip, knee, 0.16, 0.2, t, M_PAINT, taper=0.85)
        legs.beam(hip.lerp(knee, 0.15), hip.lerp(knee, 0.85), 0.17, 0.1, t, M_DARK, taper=0.9)
        # Knee.
        legs.rod(knee - t * 0.11, knee + t * 0.11, 0.12, 12, mi=M_DARK)
        legs.rod(knee - t * 0.135, knee + t * 0.135, 0.06, 8, mi=M_STEEL)
        for s in (-1, 1):
            lights.rod(knee + t * s * 0.135, knee + t * s * 0.14, 0.026, 8, mi=0)
        # Lower segment with an armor plate on the outside.
        d2 = (ankle - knee).normalized()
        n_out = (u * -d2.z + up * d2.dot(u)).normalized()  # in-plane normal of the lower segment, outward
        legs.beam(knee, ankle, 0.2, 0.24, t, M_PAINT, taper=0.72)
        legs.beam(
            knee.lerp(ankle, 0.12) + n_out * 0.09,
            knee.lerp(ankle, 0.7) + n_out * 0.065,
            0.21,
            0.05,
            t,
            M_DARK,
            taper=0.85,
        )
        # Ankle + foot.
        legs.rod(ankle - t * 0.1, ankle + t * 0.1, 0.085, 10, mi=M_DARK)
        for s in (-1, 1):
            legs.box(P(FOOT_R - 0.02, 0.27) + t * s * 0.1, (0.16, 0.03, 0.2), rot=rot, mi=M_PAINT)
        foot = u * FOOT_R
        legs.ring(0.0, 0.1, 0.3, 8, M_DARK, r2=0.26, spin=deg + 22.5, xy=(foot.x, foot.y))
        legs.ring(0.1, 0.22, 0.2, 8, M_PAINT, r2=0.17, spin=deg + 22.5, xy=(foot.x, foot.y))
        # Hydraulics: one piston over the upper segment, one along the outside of the lower segment.
        d1 = (knee - hip).normalized()
        n_up = (up - d1 * up.dot(d1)).normalized()
        a0, a1 = P(0.36, 1.04), knee + n_up * 0.15
        piston(legs, a0, a1, t)
        b0 = knee + n_out * 0.15 + d2 * 0.06
        b1 = ankle + n_out * 0.13 - d2 * 0.1
        piston(legs, b0, b1, t)
        legs.box(knee + n_out * 0.08 + d2 * 0.06, (0.06, 0.06, 0.06), rot=basis(d2, t), mi=M_DARK)
        legs.box(ankle + n_out * 0.07 - d2 * 0.1, (0.06, 0.06, 0.06), rot=basis(d2, t), mi=M_DARK)
    legs.finish(miner)


def piston(part: Part, p0: Vector, p1: Vector, side: Vector) -> None:
    mid = p0.lerp(p1, 0.55)
    part.rod(p0, mid, 0.045, 10, mi=M_DARK)
    part.rod(mid - (p1 - p0).normalized() * 0.02, p1, 0.024, 8, mi=M_STEEL)
    part.rod(mid - (p1 - p0).normalized() * 0.03, mid, 0.053, 10, mi=M_PAINT)
    for p in (p0, p1):
        part.rod(p - side * 0.045, p + side * 0.045, 0.035, 8, mi=M_DARK)


def build_boxes(miner, lights: Part) -> None:
    boxes = Part("Frame_Boxes", FRAME_MATS, bevel=(0.01, 1))
    sx, sy, sz = BOX_SIZE
    for s in (-1, 1):
        c = Vector((s * BOX_X, BOX_Y, BOX_Z))
        boxes.box(c, BOX_SIZE, mi=M_PAINT)
        boxes.box(c + Vector((0, 0, sz / 2 + 0.02)), (sx + 0.03, sy + 0.03, 0.04), mi=M_DARK)
        # Front panel with vertical vent slots.
        fy = BOX_Y - sy / 2
        boxes.box((c.x, fy - 0.006, c.z - 0.02), (sx - 0.1, 0.02, sz - 0.14), mi=M_DARK)
        for k in range(5):
            x = c.x - 0.12 + k * 0.06
            boxes.box((x, fy - 0.018, c.z - 0.02), (0.022, 0.012, sz - 0.2), mi=M_PAINT)
        lights.cyl((c.x + s * 0.17, fy - 0.01, c.z + sz / 2 - 0.05), 0.014, 0.02, 8, rot=rx(90), mi=1)
        lights.box((c.x - s * 0.17, fy - 0.012, c.z + sz / 2 - 0.05), (0.06, 0.012, 0.018), mi=0)
        # Cooling fins on the outer side.
        ox = c.x + s * sx / 2
        for k in range(7):
            boxes.box((ox + s * 0.02, c.y, c.z - 0.18 + k * 0.06), (0.05, sy - 0.08, 0.022), mi=M_PAINT)
        boxes.box((ox + s * 0.005, c.y, c.z), (0.012, sy - 0.04, sz - 0.04), mi=M_DARK)
        # Top vent block and a canister on the back.
        boxes.box((c.x, c.y + 0.04, c.z + sz / 2 + 0.07), (0.24, 0.3, 0.06), mi=M_PAINT)
        for k in range(4):
            boxes.box((c.x - 0.09 + k * 0.06, c.y + 0.04, c.z + sz / 2 + 0.1), (0.025, 0.28, 0.02), mi=M_DARK)
        can = Vector((c.x, BOX_Y + sy / 2 + 0.065, c.z - 0.02))
        boxes.cyl(can, 0.075, 0.38, 16, mi=M_DARK)
        for dz in (-0.14, 0.14):
            boxes.cyl(can + Vector((0, 0, dz)), 0.082, 0.03, 16, mi=M_PAINT)
        # Mount arms to the column band.
        for dy in (-0.13, 0.13):
            boxes.box((s * 0.33, BOX_Y + dy, BOX_Z), (0.1, 0.06, 0.1), mi=M_DARK)
    boxes.finish(miner)


def build_cable(miner) -> None:
    pts = [
        (-HEAD_APO - 0.075, 0.05, 3.13),
        (-0.53, 0.12, 3.21),
        (-0.47, 0.36, 3.16),
        (-0.33, 0.52, 2.90),
        (-0.26, 0.47, 2.40),
        (-0.25, 0.46, 1.60),
        (-0.30, 0.52, 1.00),
        (-0.52, 0.82, 0.36),
        (-0.70, 1.08, 0.06),
        (-0.86, 1.40, 0.05),
        (-0.92, 1.72, 0.05),
    ]
    cu = bpy.data.curves.new("CableCurve", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.045
    cu.bevel_resolution = 2
    cu.resolution_u = 6
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    tmp = bpy.data.objects.new("CableTmp", cu)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    for poly in me.polygons:
        poly.use_smooth = True
    cable = bpy.data.objects.new("Cable", me)
    C.link(cable, miner)
    C.assign(cable, RUBBER)

    # Clamps holding the cable to the column strut, and the plug at the far end.
    clamps = Part("Frame_Clamps", FRAME_MATS, bevel=(0.006, 1))
    for z, (x, y) in ((2.4, (-0.26, 0.47)), (1.6, (-0.25, 0.46))):
        p = Vector((x, y, z))
        clamps.cyl(p, 0.06, 0.06, 12, mi=M_DARK)
        clamps.beam(polar(135, 0.31, z), p, 0.04, 0.03, Vector((0, 0, 1)), M_PAINT)
    end = Vector(pts[-1])
    clamps.rod(end + Vector((0, -0.06, 0)), end + Vector((0, 0.1, 0)), 0.065, 12, mi=M_STEEL)
    clamps.rod(end + Vector((0, 0.1, 0)), end + Vector((0, 0.16, 0)), 0.05, 12, mi=M_DARK)
    clamps.cyl(Vector(pts[0]) + Vector((0, 0, 0.0)), 0.06, 0.05, 12, mi=M_STEEL)
    clamps.finish(miner)


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    miner = C.miner_root()
    lights = Part("Lights", [CYAN, ORANGE], bevel=None)
    build_column(miner, lights)
    build_glass(miner)
    build_drill(miner)
    build_legs(miner, lights)
    build_boxes(miner, lights)
    build_cable(miner)
    lights.finish(miner)
    return miner


CLOSE_VIEWS = {
    "close": ((2.3, -3.0, 2.6), (0, 0, 1.9), 35),
    "closeback": ((-2.4, 2.8, 2.4), (0, 0, 1.8), 35),
    "low": ((1.6, -2.4, 0.5), (0, 0, 0.8), 30),
}


def render_close(path: pathlib.Path, view: str, samples: int = 32, size: int = 640) -> None:
    """Close-up debug views (not part of the shared set)."""
    loc, target, lens = CLOSE_VIEWS[view]
    C.render_from(path, loc, target, lens, samples, size)


def main() -> None:
    C.reset()
    make_materials()
    build()
    print("STATS per object", C.tris_per_object())
    print("STATS", C.stats())
    C.preview_scene()
    import os

    if os.environ.get("DBG_FILL"):  # preview a fill level, e.g. DBG_FILL=0.6 (wip only; exports stay at 1)
        bpy.data.objects["Fill"].scale.z = float(os.environ["DBG_FILL"])
    if MODE == "final":
        for view in ("iso", "hero", "back"):
            C.render(OUT / f"render_{view}.png", view=view, samples=96, size=1024)
        C.save_blend(OUT / "miner_glow.blend")
    else:
        for view in VIEWS:
            if view in CLOSE_VIEWS:
                render_close(OUT / "wip" / f"{TAG}_{view}.png", view)
            elif view != "none":
                C.render(OUT / "wip" / f"{TAG}_{view}.png", view=view, samples=24, size=512)
    print("STATS", C.stats())


if __name__ == "__main__":  # the old miner's build imports the parts (miner_old_build.py)
    main()
