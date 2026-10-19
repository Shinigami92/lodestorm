"""Alien nest: a low organic mound of chitin plates, sinew and resin with a glowing mouth on top, tendrils
spreading over a slimy ground layer (concept: nest_v1..v4).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/nest/source/nest_build.py wip r1 [iso,hero,close,...]
    tools/blender.sh assets/aliens/nest/source/nest_build.py final

Everything it writes goes to tmp/assets/nest/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png; "final" renders iso/hero/back/far, a contact sheet (sheet.png) and saves the procedural
nest_procedural.blend that the bake stage turns into the game asset.

Game contract (game/aliens/nest/alien_nest.tscn): collision cylinder r 1.6 m x 2.4 m, the mound stays inside it;
tendrils and slime spread to ~4.5 m; aliens hatch at settings.hatch_radius (3.5 m). Objects under the root
empty "Nest": Mound, Tendrils (share one texture atlas when baked), Slime and Mouth (own simple materials, the
game pulses the Mouth's glow), Glands (small glowing pustules, same glow material as the Mouth), the empty
"HatchPoint" in the mouth, and Cracks1 and Cracks2: glowing fissures in the plates (same glow material) that the
game shows per burst stage (stage 1 Cracks1, stage 2 Cracks2 as well; Cracks2 also runs over the flesh to the
mouth). Origin at the ground center. Tube meshes carry a point attribute "flow" (arc length in m, 0..1 along the
tube, 1 = tube) that the procedural materials read for ribbing and tips. Triangle budget ~15k (cracks ~2.5k on
top), TBD (playtest).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "nest"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import itertools

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import common as C
from common import T, basis

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["iso", "hero"]

ASSET = "Nest"
Z = Vector((0, 0, 1))

# --- layout (meters, Z-up, camera looks from +X/-Y) -----------------------------------------------

# Mound profile (radius, height) from the buried skirt over the rim crest down into the crater; the end
# hides under the Mouth bowl. Smoothed and resampled by arc length into prof(t), t 0..1.
PROFILE = [
    (1.62, -0.03),
    (1.5, 0.04),
    (1.39, 0.16),
    (1.33, 0.34),
    (1.26, 0.62),
    (1.12, 0.92),
    (0.94, 1.16),
    (0.8, 1.3),
    (0.67, 1.37),
    (0.59, 1.33),
    (0.52, 1.24),
    (0.46, 1.13),
    (0.41, 1.04),
    (0.36, 0.96),
]
MOUTH_R = 0.47  # glowing bowl: edge tucked under the crater wall
MOUTH_Z0, MOUTH_Z1 = 0.96, 1.15  # bowl center, bowl edge
HATCH = (0.0, 0.0, 0.98)
MOUND_SEG, MOUND_RINGS = 56, 25

# Main tendrils: (angle deg, ground length m, radius at the rim). They start in the rim, run down the mound
# and out over the ground; the tip reaches 1.75 + ground length from the center (<= ~4.4 m).
TENDRILS = [
    (8, 2.45, 0.19),
    (57, 1.7, 0.16),
    (101, 2.3, 0.18),
    (152, 1.55, 0.15),
    (197, 2.6, 0.19),
    (244, 1.9, 0.17),
    (290, 2.55, 0.19),
    (333, 1.6, 0.16),
]
SLIME_R = 3.25  # base radius of the slime layer between the tendril fingers

# --- profile and surface ------------------------------------------------------------------------------


def _chaikin(pts: list, n: int = 3) -> list:
    for _ in range(n):
        out = [pts[0]]
        for a, b in itertools.pairwise(pts):
            out.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            out.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        out.append(pts[-1])
        pts = out
    return pts


_PTS = _chaikin(PROFILE)
_ARC = [0.0]
for _a, _b in itertools.pairwise(_PTS):
    _ARC.append(_ARC[-1] + math.dist(_a, _b))
PROF_LEN = _ARC[-1]


def prof(t: float) -> tuple[float, float]:
    s = max(0.0, min(1.0, t)) * PROF_LEN
    for i in range(1, len(_ARC)):
        if _ARC[i] >= s:
            f = (s - _ARC[i - 1]) / max(_ARC[i] - _ARC[i - 1], 1e-9)
            a, b = _PTS[i - 1], _PTS[i]
            return a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
    return _PTS[-1]


T_CREST = max((i / 400 for i in range(401)), key=lambda t: prof(t)[1])


def t_at_z(z: float) -> float:
    """Outer side of the mound: the t where the profile reaches height z."""
    lo, hi = 0.0, T_CREST
    for _ in range(40):
        mid = (lo + hi) / 2
        if prof(mid)[1] < z:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def _smoothstep(a: float, b: float, x: float) -> float:
    x = max(0.0, min(1.0, (x - a) / (b - a)))
    return x * x * (3 - 2 * x)


def P(th: float, t: float) -> Vector:
    """Point on the mound surface at angle th (rad) and profile parameter t."""
    r0, z0 = prof(t)
    outer = _smoothstep(0.0, 0.12, t) * (1.0 - _smoothstep(T_CREST - 0.02, T_CREST + 0.08, t))
    lobe = 1.0 + outer * (0.05 * math.sin(3 * th + 0.6) + 0.03 * math.sin(5 * th + 2.2))
    r = r0 * lobe
    z = z0 * (1.0 + 0.05 * math.cos(th - 1.0) * outer)
    z += 0.05 * math.sin(7 * th + 0.4) * math.exp(-(((t - T_CREST) / 0.06) ** 2))  # lobed rim crest
    p = Vector((math.cos(th) * r, math.sin(th) * r, z))
    # Lumps along the profile normal (none at the ground ring and in the crater, where the mouth fits).
    dr, dz = (a - b for a, b in zip(prof(t + 0.004), prof(t - 0.004)))
    n2 = Vector((dz, -dr)).normalized()
    w = _smoothstep(0.02, 0.1, t) * (1.0 - _smoothstep(T_CREST + 0.02, T_CREST + 0.12, t))
    d = w * (0.06 * noise.noise(p * 1.4) + 0.025 * noise.noise(p * 3.7 + Vector((5, 1, 2))))
    return p + Vector((math.cos(th) * n2.x, math.sin(th) * n2.x, n2.y)) * d


def N(th: float, t: float) -> Vector:
    e = 0.004
    a = P(th + e, t) - P(th - e, t)
    b = P(th, t + e) - P(th, t - e)
    n = b.cross(a).normalized()
    if n.dot(Vector((math.cos(th), math.sin(th), 0.6))) < 0 and t < T_CREST:
        n = -n
    return n


def radial(th: float) -> Vector:
    return Vector((math.cos(th), math.sin(th), 0.0))


# --- mesh builder -----------------------------------------------------------------------------------


class Part:
    """Accumulates geometry into one bmesh, one object at the end (keeps the draw calls low)."""

    def __init__(self, name: str, mats: list):
        self.name, self.mats = name, mats
        self.bm = bmesh.new()
        self.flow = self.bm.verts.layers.float_vector.new("flow")
        self.glow = self.bm.verts.layers.float.new("glow")

    def faces(self, rows: list, mi: int, closed_u: bool, flip: bool = False) -> list:
        """Quad grid between consecutive rows of verts (each row the same length)."""
        out = []
        for a, b in itertools.pairwise(rows):
            n = len(a)
            for i in range(n if closed_u else n - 1):
                j = (i + 1) % n
                quad = (a[i], a[j], b[j], b[i])
                f = self.bm.faces.new(quad[::-1] if flip else quad)
                f.material_index = mi
                f.smooth = True
                out.append(f)
        return out

    def finish(self, parent) -> bpy.types.Object:
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, me)
        C.link(obj, parent)
        for mat in self.mats:
            me.materials.append(mat)
        return obj


def orient(part: Part, faces: list, outward: Vector, sample: int | None = None) -> None:
    """Flip a face set if its sample face points against `outward`."""
    f = faces[len(faces) // 2 if sample is None else sample]
    f.normal_update()
    if f.normal.dot(outward) < 0:
        bmesh.ops.reverse_faces(part.bm, faces=faces)


def smooth_path(pts: list, refs: list, iters: int = 3) -> None:
    for _ in range(iters):
        pts[1:-1] = [(pts[i - 1] + pts[i] * 2 + pts[i + 1]) / 4 for i in range(1, len(pts) - 1)]
        refs[1:-1] = [(refs[i - 1] + refs[i] * 2 + refs[i + 1]).normalized() for i in range(1, len(refs) - 1)]


def catmull(ctrl: list, n: int) -> list:
    """n points on a Catmull-Rom spline through ctrl (end points repeated)."""
    c = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    out = []
    for k in range(n):
        u = k / (n - 1) * (len(ctrl) - 1)
        i = min(int(u), len(ctrl) - 2)
        f = u - i
        p0, p1, p2, p3 = c[i], c[i + 1], c[i + 2], c[i + 3]
        out.append(
            0.5
            * (
                (2 * p1)
                + (-p0 + p2) * f
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                + (-p0 + 3 * p1 - 3 * p2 + p3) * f**3
            )
        )
    return out


def tube(
    part: Part, pts: list, radii: list, refs: list, sides: int, flat: float = 1.0, mi_fn=None, kind: float = 1.0
) -> list:
    """Swept tube along pts with per-point radius; cross-section squashed to `flat` along refs (e.g. the
    surface normal, so tubes hug the surface). Radius 0 at the end makes a pointed tip; the start is open
    (start it buried in another surface)."""
    bm = part.bm
    total = sum((b - a).length for a, b in itertools.pairwise(pts))
    rows, faces, s = [], [], 0.0
    tip = start = None
    for i, p in enumerate(pts):
        if i > 0:
            s += (p - pts[i - 1]).length
        tan = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        b = tan.cross(refs[i])
        if b.length < 1e-4:
            b = tan.orthogonal()
        b.normalize()
        n = b.cross(tan)
        u = s / total
        if i == 0 and radii[0] < 1e-4:
            start = bm.verts.new(p)
            start[part.flow] = (0.0, 0.0, kind)
            continue
        if radii[i] < 1e-4:
            tip = bm.verts.new(p)
            tip[part.flow] = (s, 1.0, kind)
            break
        row = []
        for k in range(sides):
            a = k / sides * math.tau
            v = bm.verts.new(p + (b * math.cos(a) + n * (math.sin(a) * flat)) * radii[i])
            v[part.flow] = (s, u, kind)
            row.append(v)
        rows.append(row)
    for j, (ra, rb) in enumerate(itertools.pairwise(rows)):
        mi = mi_fn(j / max(len(rows) - 1, 1)) if mi_fn else 0
        faces += part.faces([ra, rb], mi, closed_u=True)
    if start is not None:
        first = rows[0]
        for k in range(sides):
            f = bm.faces.new((first[(k + 1) % sides], first[k], start))
            f.material_index = mi_fn(0.0) if mi_fn else 0
            f.smooth = True
            faces.append(f)
    if tip is not None:
        last = rows[-1]
        for k in range(sides):
            f = bm.faces.new((last[k], last[(k + 1) % sides], tip))
            f.material_index = mi_fn(1.0) if mi_fn else 0
            f.smooth = True
            faces.append(f)
    # Orientation check on a mid-tube face: outward = away from its ring center.
    if len(rows) > 1:
        mid = len(rows) // 2
        ring_c = sum((v.co for v in rows[mid]), Vector()) / sides
        f = next(fc for fc in rows[mid][0].link_faces if fc in set(faces))
        f.normal_update()
        if f.normal.dot(f.calc_center_median() - ring_c) < 0:
            bmesh.ops.reverse_faces(bm, faces=faces)
    return faces


# --- materials --------------------------------------------------------------------------------------


def _coord(nt, out: str = "Object") -> bpy.types.NodeSocket:
    return nt.nodes.new("ShaderNodeTexCoord").outputs[out]


def _noise(nt, vec, scale: float, detail: float = 4.0, rough: float = 0.55, dist: float = 0.0) -> bpy.types.Node:
    return C._noise(nt, scale, detail, rough, vector=vec, distortion=dist)


def _veins(nt, vec, scale: float, width: float) -> bpy.types.NodeSocket:
    """1 on thin branching vein lines: Voronoi cell edges, warped by noise."""
    warp = _noise(nt, vec, 1.8, 3.0, 0.5)
    add = nt.nodes.new("ShaderNodeVectorMath")
    add.operation = "MULTIPLY_ADD"
    nt.links.new(warp.outputs["Color"], add.inputs[0])
    add.inputs[1].default_value = (0.35, 0.35, 0.35)
    nt.links.new(vec, add.inputs[2])
    return C._voronoi_lines(nt, add.outputs[0], scale, width)


def _cavity(nt, distance: float = 0.25, lo: float = 0.35, hi: float = 0.95) -> bpy.types.NodeSocket:
    """1 in cavities (AO), 0 in the open."""
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = distance
    ao.samples = 16
    return C._math(nt, "SUBTRACT", 1.0, C._bw(nt, C._ramp(nt, lo, hi, ao.outputs["AO"])))


def _edges(nt, radius: float = 0.02, lo: float = 0.02, hi: float = 0.12) -> bpy.types.NodeSocket:
    """1 on convex edges (Bevel node normal vs the true normal; independent of the mesh density)."""
    return C._bw(nt, C._ramp(nt, lo, hi, C._bevel_edge(nt, radius)))


def _flow(nt) -> tuple[bpy.types.NodeSocket, bpy.types.NodeSocket, bpy.types.NodeSocket]:
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "flow"
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(attr.outputs["Vector"], sep.inputs[0])
    return sep.outputs[0], sep.outputs[1], sep.outputs[2]


def mat_flesh() -> bpy.types.Material:
    """Sinew: dark red to purple flesh with raised veins, ribbed along tubes, black glossy resin pooling in
    the cavities (wet: low roughness there)."""
    mat, nt, bsdf = C._new_material("Flesh")
    co = _coord(nt)
    big = _noise(nt, co, 1.3, 4.0, 0.5)
    col = C._mix_color(nt, big.outputs["Fac"], (0.095, 0.02, 0.013), (0.05, 0.013, 0.014))
    veins = C._bw(nt, _veins(nt, co, 2.6, 0.045))
    col = C._mix_color(nt, veins, col, (0.03, 0.007, 0.018))
    s, _u, kind = _flow(nt)
    jitter = _noise(nt, co, 3.0, 2.0, 0.5)
    phase = C._math(nt, "MULTIPLY_ADD", jitter.outputs["Fac"], 3.0, C._math(nt, "MULTIPLY", s, math.tau / 0.15))
    ribs = C._math(nt, "SINE", phase)  # -1..1 along tubes, irregular spacing
    ribs01 = C._math(nt, "MULTIPLY", C._math(nt, "ADD", ribs, 1.0), 0.5)
    groove = C._math(nt, "MULTIPLY", C._bw(nt, C._ramp(nt, 0.6, 1.0, ribs01)), kind)  # 1 in the grooves between rings
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", groove, 0.35), col, (0.02, 0.005, 0.008))
    # Lighter, drier tone on the crowns of bulges: subtle so the flesh doesn't go flat.
    edge = _edges(nt, 0.015, 0.03, 0.2)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", edge, 0.3), col, (0.2, 0.075, 0.06))
    cav = _cavity(nt, 0.3)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.9), col, (0.012, 0.004, 0.006))
    nt.links.new(col, bsdf.inputs["Base Color"])
    wet = _noise(nt, co, 3.0, 3.0, 0.5)
    rough = C._mix_float(nt, wet.outputs["Fac"], 0.22, 0.5)
    rough = C._mix_float(nt, cav, rough, 0.07)
    rough = C._mix_float(nt, veins, rough, 0.18)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    fine = _noise(nt, co, 28.0, 4.0, 0.6)
    h = C._math(nt, "ADD", C._math(nt, "MULTIPLY", veins, 0.6), C._math(nt, "MULTIPLY", groove, -0.4))
    h = C._math(nt, "ADD", h, C._math(nt, "MULTIPLY", fine.outputs["Fac"], 0.15))
    C._bump(nt, bsdf, h, 0.45, 0.012)
    return mat


def mat_chitin() -> bpy.types.Material:
    """Chitin plates and spikes: near-black red-brown shell with growth bands, bone-colored worn edges and
    tips, glossy (wet) in the gaps."""
    mat, nt, bsdf = C._new_material("Chitin")
    co = _coord(nt)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 7.0
    wave.inputs["Distortion"].default_value = 5.0
    wave.inputs["Detail"].default_value = 3.0
    nt.links.new(co, wave.inputs["Vector"])
    bands = C._ramp(nt, 0.25, 0.8, wave.outputs["Fac"])
    big = _noise(nt, co, 2.2, 4.0, 0.5)
    shell = C._mix_color(nt, big.outputs["Fac"], (0.025, 0.012, 0.012), (0.055, 0.024, 0.02))
    shell = C._mix_color(nt, C._math(nt, "MULTIPLY", C._bw(nt, bands), 0.35), shell, (0.085, 0.045, 0.035))
    _s, u, kind = _flow(nt)
    tip = C._math(nt, "MULTIPLY", C._ramp(nt, 0.7, 1.0, u), kind)
    edge = _edges(nt, 0.012, 0.03, 0.16)
    breakup = _noise(nt, co, 9.0, 6.0, 0.6)
    bone_mask = C._math(nt, "ADD", C._bw(nt, tip), edge, clamp=True)
    bone_mask = C._math(nt, "MULTIPLY", bone_mask, C._bw(nt, C._ramp(nt, 0.3, 0.55, breakup.outputs["Fac"])))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", bone_mask, 0.8), shell, (0.3, 0.24, 0.17))
    cav = _cavity(nt, 0.2)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.85), col, (0.01, 0.004, 0.004))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, big.outputs["Fac"], 0.22, 0.36)
    rough = C._mix_float(nt, bone_mask, rough, 0.55)
    rough = C._mix_float(nt, cav, rough, 0.08)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    fine = _noise(nt, co, 40.0, 3.0, 0.6)
    h = C._math(
        nt, "ADD", C._math(nt, "MULTIPLY", C._bw(nt, bands), 0.5), C._math(nt, "MULTIPLY", fine.outputs["Fac"], 0.2)
    )
    C._bump(nt, bsdf, h, 0.3, 0.008)
    return mat


def mat_resin() -> bpy.types.Material:
    """Hardened resin lining the crater and filling gaps: black-amber, glassy."""
    mat, nt, bsdf = C._new_material("Resin")
    co = _coord(nt)
    streak = _noise(nt, co, 4.0, 6.0, 0.6, dist=2.0)
    col = C._mix_color(
        nt, C._bw(nt, C._ramp(nt, 0.45, 0.75, streak.outputs["Fac"])), (0.016, 0.006, 0.005), (0.09, 0.035, 0.012)
    )
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, streak.outputs["Fac"], 0.06, 0.2), bsdf.inputs["Roughness"])
    C._bump(nt, bsdf, streak.outputs["Fac"], 0.25, 0.01)
    return mat


def mat_sac() -> bpy.types.Material:
    """Egg sacs: pale, sickly membrane with dark red veins, very glossy."""
    mat, nt, bsdf = C._new_material("EggSac")
    co = _coord(nt)
    big = _noise(nt, co, 3.0, 3.0, 0.5)
    col = C._mix_color(nt, big.outputs["Fac"], (0.11, 0.09, 0.04), (0.2, 0.16, 0.075))
    veins = C._bw(nt, _veins(nt, co, 5.0, 0.05))
    col = C._mix_color(nt, veins, col, (0.09, 0.012, 0.015))
    cav = _cavity(nt, 0.15)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.85), col, (0.02, 0.006, 0.004))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, veins, 0.1, 0.25), bsdf.inputs["Roughness"])
    C._bump(nt, bsdf, veins, 0.35, 0.006)
    return mat


def mat_slime() -> bpy.types.Material:
    """Slime layer on the ground: near-black wine, wet, barely varying (cheap in game)."""
    mat, nt, bsdf = C._new_material("Slime")
    co = _coord(nt)
    big = _noise(nt, co, 0.9, 3.0, 0.5)
    nt.links.new(
        C._mix_color(nt, big.outputs["Fac"], (0.012, 0.004, 0.005), (0.032, 0.008, 0.011)), bsdf.inputs["Base Color"]
    )
    nt.links.new(C._mix_float(nt, big.outputs["Fac"], 0.04, 0.14), bsdf.inputs["Roughness"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.6
    ripple = _noise(nt, co, 2.5, 2.0, 0.4)
    C._bump(nt, bsdf, ripple.outputs["Fac"], 0.12, 0.02)
    return mat


GLOW_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)


def mat_glow() -> bpy.types.Material:
    """Sickly yellow-green glow of the mouth and glands (the game pulses it)."""
    mat, nt, bsdf = C._new_material("Nest_Glow")
    co = _coord(nt)
    churn = _noise(nt, co, 5.0, 4.0, 0.6, dist=1.5)
    col = C._mix_color(nt, churn.outputs["Fac"], (0.35, 0.75, 0.005), (0.9, 1.0, 0.12))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(col, bsdf.inputs["Emission Color"])
    glow = nt.nodes.new("ShaderNodeAttribute")  # radial falloff in the mouth (1 = full), see build_mouth
    glow.attribute_name = "glow"
    strength = C._math(nt, "MULTIPLY", C._mix_float(nt, churn.outputs["Fac"], 2.5, 9.0), glow.outputs["Fac"])
    nt.links.new(strength, bsdf.inputs["Emission Strength"])
    col = C._mix_color(nt, glow.outputs["Fac"], (0.15, 0.3, 0.004), col)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(col, bsdf.inputs["Emission Color"])
    bsdf.inputs["Roughness"].default_value = 0.15
    return mat


def make_materials() -> None:
    global FLESH, CHITIN, RESIN, SAC, SLIME, GLOW
    FLESH, CHITIN, RESIN, SAC = mat_flesh(), mat_chitin(), mat_resin(), mat_sac()
    SLIME, GLOW = mat_slime(), mat_glow()


M_FLESH, M_CHITIN, M_RESIN, M_SAC = 0, 1, 2, 3


# --- parts ------------------------------------------------------------------------------------------


def build_mound_body(part: Part) -> None:
    rows, ts = [], []
    for j in range(MOUND_RINGS):
        t = j / (MOUND_RINGS - 1)
        ts.append(t)
        rows.append([part.bm.verts.new(P(i / MOUND_SEG * math.tau, t)) for i in range(MOUND_SEG)])
    for j, (a, b) in enumerate(itertools.pairwise(rows)):
        mi = M_RESIN if ts[j] > T_CREST + 0.04 else M_FLESH
        faces = part.faces([a, b], mi, closed_u=True)
        orient(part, faces, (faces[0].calc_center_median() - Vector((0, 0, 0.3))) if ts[j] < T_CREST else Z, 0)


def plate_width(v: float) -> float:
    """Plate half width (share of hw) at v: narrow at the pointed lower end (v 0), full from v 0.6, 0.7 at the top."""
    return (0.15 + 0.85 * math.sin(min(v / 0.6, 1.0) * math.pi / 2)) * (1 - 0.3 * max(0.0, (v - 0.7) / 0.3))


def plate(part: Part, th_c: float, hw: float, t0: float, t1: float, lift: float, thick: float) -> list:
    """Shield-shaped chitin plate following the mound surface; the pointed lower end lifts off like a scale.
    Returns the top surface as rows (along v) of vertex positions (across, uu -1..1), for the cracks."""
    nu, nv = 6, 6
    top, bot = [], []
    for j in range(nv):
        v = j / (nv - 1)
        t = t0 + v * (t1 - t0)
        w = plate_width(v)
        rt, rb = [], []
        for i in range(nu):
            uu = -1 + 2 * i / (nu - 1)
            th = th_c + uu * hw * w
            p, n = P(th, t), N(th, t)
            off = 0.012 + lift * (1 - v) ** 1.6 + 0.03 * (1 - uu * uu) * (0.3 + 0.7 * v)
            th_k = thick * (0.35 + 0.65 * (1 - uu * uu))
            rt.append(part.bm.verts.new(p + n * off))
            rb.append(part.bm.verts.new(p + n * (off - th_k)))
        top.append(rt)
        bot.append(rb)
    faces = part.faces(top, M_CHITIN, closed_u=False) + part.faces(bot, M_CHITIN, closed_u=False, flip=True)
    ring_t = top[0] + [r[-1] for r in top[1:]] + top[-1][-2::-1] + [r[0] for r in top[-2:0:-1]]
    ring_b = bot[0] + [r[-1] for r in bot[1:]] + bot[-1][-2::-1] + [r[0] for r in bot[-2:0:-1]]
    faces += part.faces([ring_t, ring_b], M_CHITIN, closed_u=True)
    bmesh.ops.recalc_face_normals(part.bm, faces=faces)
    return [[v.co.copy() for v in row] for row in top]


def build_plates(part: Part, rnd: random.Random, plates: list) -> list:
    """Two rows of plates in the gaps between the tendrils; returns gaps left free for egg sacs and adds each
    plate to `plates` (gap index, upper row, center angle, half width, t range, top surface grid)."""
    angs = sorted(math.radians(a) for a, _, _ in TENDRILS)
    sac_gaps = []
    for k, a in enumerate(angs):
        b = angs[(k + 1) % len(angs)] + (math.tau if k == len(angs) - 1 else 0)
        gap = b - a
        mid = (a + b) / 2
        hw = gap / 2 - 0.17
        if k in (6, 2):  # front-right (camera side) and one side: egg sacs instead of the lower plate
            sac_gaps.append((mid, hw))
        else:
            th, t0, t1 = mid + rnd.uniform(-0.04, 0.04), t_at_z(0.2), t_at_z(0.8)
            top = plate(part, th, hw, t0, t1, 0.07, 0.05)
            plates.append(dict(k=k, upper=False, th=th, hw=hw, t0=t0, t1=t1, top=top))
        th, t0, t1 = mid + rnd.uniform(-0.05, 0.05), t_at_z(0.62), t_at_z(1.2)
        top = plate(part, th, hw * 0.92, t0, t1, 0.07, 0.045)
        plates.append(dict(k=k, upper=True, th=th, hw=hw * 0.92, t0=t0, t1=t1, top=top))
    return sac_gaps


def build_sacs(part: Part, gaps: list, rnd: random.Random) -> None:
    for mid, hw in gaps:
        for th, t, r in (
            (mid - hw * 0.35, t_at_z(0.32), 0.27),
            (mid + hw * 0.45, t_at_z(0.26), 0.22),
            (mid + hw * 0.05, t_at_z(0.62), 0.18),
        ):
            p, n = P(th, t), N(th, t)
            c = p - n * (r * 0.15)
            rot = basis(n, Z)
            verts = bmesh.ops.create_uvsphere(
                part.bm, u_segments=14, v_segments=8, radius=r, matrix=T(c, rot, (0.85, 0.95, 0.8))
            )["verts"]
            for f in {f for v in verts for f in v.link_faces}:
                f.material_index = M_SAC
                f.smooth = True


def build_teeth(part: Part, rnd: random.Random) -> None:
    """Crown of curved chitin horns around the crater rim, leaning out and curling back in."""
    n = 10
    for k in range(n):
        th = k / n * math.tau + rnd.uniform(-0.15, 0.15)
        t = T_CREST - 0.015
        b, nn, rd = P(th, t), N(th, t), radial(th)
        h = rnd.uniform(0.26, 0.5)
        ctrl = [b - nn * 0.08, b + nn * 0.03 + Z * 0.05, b + Z * h * 0.55 + rd * 0.12, b + Z * h + rd * 0.08]
        pts = catmull(ctrl, 9)
        r0 = rnd.uniform(0.085, 0.125)
        radii = [r0 * (1 - (i / 8) ** 1.3) for i in range(9)]
        radii[-1] = 0.0
        tube(part, pts, radii, [rd] * 9, 6, flat=0.6, mi_fn=lambda f: M_CHITIN, kind=1.0)


def ground_path(th0: float, start: float, length: float, rnd: random.Random, ds: float = 0.12) -> list:
    """XY points on the ground going outward from radius `start` at angle th0, meandering sideways."""
    phase, amp, freq = rnd.uniform(0, 6.28), rnd.uniform(0.12, 0.3), rnd.uniform(1.2, 2.2)
    pts, d = [], 0.0
    while d <= length + 1e-6:
        rho = start + d
        lat = amp * math.sin(d * freq + phase) * min(1.0, d / 0.6)
        th = th0 + lat / rho
        pts.append(Vector((math.cos(th) * rho, math.sin(th) * rho, 0.0)))
        d += ds
    return pts


def taper(u: float, r0: float, s: float) -> float:
    r = r0 * (1.0 - 0.3 * u) * (1.0 + 0.07 * math.sin(math.tau * s / 0.32))
    if u > 0.62:
        r *= ((1 - u) / 0.38) ** 0.85
    return r


def build_tendrils(part: Part, mound: Part, glands: list, rnd: random.Random) -> list:
    """Main tendrils from the rim down the mound and out over the ground, with side branches; returns their
    tip positions (slime fingers follow them)."""
    tips = []
    for deg, glen, r0 in TENDRILS:
        th0 = math.radians(deg)
        pts, refs = [], []
        t = t_at_z(rnd.uniform(1.12, 1.22))
        dt = 0.11 / PROF_LEN
        ph = rnd.uniform(0, 6.28)
        while t > 0.0:
            th = th0 + 0.07 * math.sin(t * 9 + ph)
            n = N(th, t)
            pts.append(P(th, t) + n * (r0 * 0.5))
            refs.append(n)
            t -= dt
        ground = ground_path(th0, 1.68, glen, rnd)
        pts += ground[1:]
        refs += [Z.copy() for _ in ground[1:]]
        n_mound = len(pts) - len(ground) + 1
        smooth_path(pts, refs, 2)
        # Radii by arc length; ground points sit half sunk into the slime.
        arcs = [0.0]
        for a, b in itertools.pairwise(pts):
            arcs.append(arcs[-1] + (b - a).length)
        radii = [taper(s / arcs[-1], r0, s) for s in arcs]
        radii[-1] = 0.0
        # Rounded start: the first two rings shrink to a point pulled back up the mound.
        back = (pts[0] - pts[1]).normalized()
        pts[:0] = [pts[0] + back * r0 * 0.75, pts[0] + back * r0 * 0.45]
        refs[:0] = [refs[0], refs[0]]
        radii[:0] = [0.0, r0 * 0.75]
        n_mound += 2
        for i in range(n_mound, len(pts)):
            pts[i].z = radii[i] * 0.42 + 0.006
        pts[-1].z = 0.008
        tube(part, pts, radii, refs, 7, flat=0.66, mi_fn=lambda f: M_CHITIN if f > 0.9 else M_FLESH)
        tips.append(pts[-1].copy())
        # Glands where the tendril leaves the rim and along the ground part.
        gi = n_mound // 3
        side = (pts[gi + 1] - pts[gi - 1]).normalized().cross(refs[gi]).normalized()
        glands.append((pts[gi] + side * radii[gi] * 0.85 + refs[gi] * 0.02, rnd.uniform(0.055, 0.075)))
        # Side branches off the ground part.
        ng = len(pts) - n_mound
        picks = [n_mound + int(ng * rnd.uniform(0.3, 0.45)), n_mound + int(ng * rnd.uniform(0.62, 0.72))]
        if glen > 2.0:
            picks.append(n_mound + int(ng * rnd.uniform(0.5, 0.58)))
        for b, i in enumerate(picks):
            tan = (pts[i + 1] - pts[i - 1]).normalized()
            sgn = 1 if (b + deg) % 2 == 0 else -1
            d = Matrix.Rotation(sgn * rnd.uniform(0.6, 0.95), 3, "Z") @ tan
            d.z = 0
            d.normalize()
            blen = rnd.uniform(0.45, 0.95) if b != 1 else rnd.uniform(0.35, 0.6)
            rb = radii[i] * 0.6
            bp = [pts[i] + d * (k * 0.12) for k in range(int(blen / 0.12) + 1)]
            bend = Matrix.Rotation(-sgn * 1.3, 3, "Z") @ d
            bp = [p + bend * ((k * 0.12) ** 2) * 0.45 for k, p in enumerate(bp)]
            br = [rb * (1 - k / (len(bp) - 1)) ** 0.6 for k in range(len(bp))]
            br[-1] = 0.0
            for k in range(len(bp)):
                bp[k].z = br[k] * 0.42 + 0.006
            tube(part, bp, br, [Z.copy() for _ in bp], 5, flat=0.66, mi_fn=lambda f: M_FLESH)
    # Thin roots from the skirt between the main tendrils.
    angs = sorted(math.radians(a) for a, _, _ in TENDRILS)
    for k, a in enumerate(angs):
        b = angs[(k + 1) % len(angs)] + (math.tau if k == len(angs) - 1 else 0)
        th = (a + b) / 2 + rnd.uniform(-0.1, 0.1)
        g = ground_path(th, 1.62, rnd.uniform(0.9, 1.6), rnd, 0.12)
        rr = [0.065 * (1 - i / (len(g) - 1)) ** 0.8 for i in range(len(g))]
        rr[-1] = 0.0
        for i, p in enumerate(g):
            p.z = rr[i] * 0.42 + 0.006
        start = P(th, t_at_z(0.12))
        g = [start] + g
        rr = [0.07] + rr
        tube(part, g, rr, [Z.copy() for _ in g], 5, flat=0.72)
    return tips


def build_glands(nest, glands: list, rnd: random.Random) -> None:
    part = Part("Glands", [GLOW])
    # A few more on the mound between the plates and the crater rim.
    for k in range(2):
        th = rnd.uniform(0, math.tau)
        t = t_at_z(rnd.uniform(0.9, 1.25))
        glands.append((P(th, t) + N(th, t) * 0.03, rnd.uniform(0.045, 0.065)))
    for c, r in glands:
        for v in bmesh.ops.create_uvsphere(part.bm, u_segments=8, v_segments=5, radius=r, matrix=T(c))["verts"]:
            v[part.glow] = 1.0
    for f in part.bm.faces:
        f.smooth = True
    part.finish(nest)


def build_mouth(nest) -> None:
    """Glowing bowl filling the crater: radial folds like a sphincter, rising to the edge under the wall."""
    part = Part("Mouth", [GLOW])
    seg, rings = 32, 6
    center = part.bm.verts.new((0, 0, MOUTH_Z0 - 0.04))
    center[part.glow] = 1.0
    rows = []
    for j in range(1, rings + 1):
        f = j / rings
        r = MOUTH_R * f
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            fold = 0.03 * math.sin(9 * a + 0.5) * math.sin(math.pi * f) ** 1.5
            z = MOUTH_Z0 + (MOUTH_Z1 - MOUTH_Z0) * f**2 + fold - 0.04 * (1 - f) ** 3
            v = part.bm.verts.new((math.cos(a) * r, math.sin(a) * r, z))
            v[part.glow] = 1.0 - 0.6 * f**2 + 0.15 * fold / 0.03 * f  # hot core, dimmer toward the wall
            row.append(v)
        rows.append(row)
    faces = []
    for i in range(seg):
        faces.append(part.bm.faces.new((center, rows[0][i], rows[0][(i + 1) % seg])))
    faces += part.faces(rows, 0, closed_u=True)
    for f in faces:
        f.smooth = True
    orient(part, faces, Z, 0)
    orient(part, faces[seg:], Z, 0)
    part.finish(nest)


def build_slime(nest, tips: list, rnd: random.Random) -> None:
    """Flat glossy layer on the ground, fingers reaching out along the tendrils, a rounded lip at the edge."""
    part = Part("Slime", [SLIME])
    seg = 96
    fr = [0.0, 0.3, 0.55, 0.75, 0.88, 0.95, 1.0]
    r_in = 1.3
    tip_ang = [(math.atan2(p.y, p.x), p.xy.length) for p in tips]
    rows = []
    for j, f in enumerate(fr):
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            edge = (
                SLIME_R
                + 0.3 * noise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, 0.5)))
                + 0.08 * math.sin(11 * a)
            )
            for ta, reach in tip_ang:
                d = math.atan2(math.sin(a - ta), math.cos(a - ta))
                edge += max(0.0, reach - 0.05 - edge) * math.exp(-((d / 0.24) ** 2))
            edge = min(edge, 4.5)
            r = r_in + (edge - r_in) * f
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
            p.z = 0.004 + 0.028 * (1 - f**4) + 0.006 * noise.noise(p * 2.0) * (1 - f)
            row.append(part.bm.verts.new(p))
        rows.append(row)
    faces = part.faces(rows, 0, closed_u=True)
    for f in faces:
        f.smooth = True
    orient(part, faces, Z, 0)
    part.finish(nest)


# --- cracks (the nest bursting open: the game shows Cracks1, then Cracks2 as well) -------------------------


class Sheet:
    """A surface the cracks lie on, as built: bilinear over a grid of vertex positions (rows along b, columns
    along a; a, b in grid steps), so they sit on the faces and not on the smooth formula between them."""

    def __init__(self, grid: list, wrap: bool = False, a_lim: tuple = (0.0, 1e9), b_lim: tuple = (0.0, 1e9)):
        self.grid, self.wrap = grid, wrap
        self.na, self.nb = len(grid[0]), len(grid)
        self.a_lim = (max(a_lim[0], 0.0), min(a_lim[1], self.na - 1.0))
        self.b_lim = (max(b_lim[0], 0.0), min(b_lim[1], self.nb - 1.0))

    def clamp(self, a: float, b: float) -> tuple[float, float]:
        if not self.wrap:
            a = max(self.a_lim[0], min(self.a_lim[1], a))
        return a, max(self.b_lim[0], min(self.b_lim[1], b))

    def pos(self, a: float, b: float) -> Vector:
        a, b = self.clamp(a, b)
        if self.wrap:
            a %= self.na
        i, j = min(int(a), self.na - (1 if self.wrap else 2)), min(int(b), self.nb - 2)
        fa, fb = a - i, b - j
        i1 = (i + 1) % self.na
        r0, r1 = self.grid[j], self.grid[j + 1]
        return (r0[i] * (1 - fa) + r0[i1] * fa) * (1 - fb) + (r1[i] * (1 - fa) + r1[i1] * fa) * fb

    def frame(self, a: float, b: float) -> tuple[Vector, Vector, Vector, Vector]:
        """Point, normal (a x b: away from the mound outside, up in the crater) and the tangents along a and b."""
        e = 0.02
        pa = (self.pos(a + e, b) - self.pos(a - e, b)) / (2 * e)
        pb = (self.pos(a, b + e) - self.pos(a, b - e)) / (2 * e)
        return self.pos(a, b), pa.cross(pb).normalized(), pa, pb

    def move(self, a: float, b: float, d: Vector) -> tuple[float, float]:
        """Parameters of the point a step d (in the tangent plane) away."""
        _p, _n, pa, pb = self.frame(a, b)
        g11, g12, g22 = pa.dot(pa), pa.dot(pb), pb.dot(pb)
        r1, r2 = pa.dot(d), pb.dot(d)
        det = g11 * g22 - g12 * g12
        return self.clamp(a + (r1 * g22 - r2 * g12) / det, b + (g11 * r2 - g12 * r1) / det)


def plate_sheet(pl: dict) -> Sheet:
    """A plate's top surface: a 0..5 across (uu -1..1), b 0..5 from the pointed lower end to the top; cracks
    keep off the side edges."""
    return Sheet(pl["top"], a_lim=(0.8, 4.2), b_lim=(0.25, 4.97))


def mound_sheet() -> Sheet:
    """The mound body: a = th in segments (wraps), b = t in rings, as build_mound_body lays it out."""
    grid = [[P(i / MOUND_SEG * math.tau, j / (MOUND_RINGS - 1)) for i in range(MOUND_SEG)] for j in range(MOUND_RINGS)]
    return Sheet(grid, wrap=True)


def crack_walk(sheet: Sheet, start: tuple, end: tuple, rnd: random.Random, step=(0.025, 0.08)) -> list:
    """Jagged path over the sheet from start to end (parameters): straight steps of mixed length, kinked off a
    slowly wandering heading toward the end (irregular, not an even zig-zag)."""
    pts, cur = [start], start
    sign, drift = rnd.choice((-1, 1)), 0.0
    for _ in range(80):
        p, n, _pa, _pb = sheet.frame(*cur)
        to = sheet.pos(*end) - p
        to -= n * to.dot(n)
        if to.length < step[1] * 1.3:
            break
        drift = max(-0.5, min(0.5, drift + rnd.uniform(-0.3, 0.3)))
        d = Matrix.Rotation(drift + sign * rnd.uniform(0.05, 0.65), 3, n) @ to.normalized()
        if rnd.random() < 0.6:
            sign = -sign
        cur = sheet.move(*cur, d * rnd.uniform(*step))
        pts.append(cur)
    pts.append(end)
    return pts


def crack_branch(sheet: Sheet, start: tuple, heading: Vector, steps: int, rnd: random.Random) -> list:
    """Short side crack: a few jagged steps from start, meandering around heading."""
    pts, cur = [start], start
    for _ in range(steps):
        _p, n, _pa, _pb = sheet.frame(*cur)
        heading = (heading - n * heading.dot(n)).normalized()
        d = Matrix.Rotation(rnd.uniform(-0.5, 0.5), 3, n) @ heading
        cur = sheet.move(*cur, d * rnd.uniform(0.035, 0.06))
        pts.append(cur)
    return pts


def ribbon(part: Part, sheet: Sheet, path: list, widths: list, lift: float) -> None:
    """Thin strip along path just above the sheet: three verts across (glowing middle, dim edges, each edge
    its own jagged width), a single vert where the width is 0 (pointed ends)."""
    bm = part.bm
    pos = [sheet.pos(*q) for q in path]
    rows, normals = [], []
    for k, (a, b) in enumerate(path):
        p, n, _pa, _pb = sheet.frame(a, b)
        t_in = (pos[k] - pos[k - 1]).normalized() if k > 0 else None
        t_out = (pos[k + 1] - pos[k]).normalized() if k < len(path) - 1 else None
        tan = (t_in if t_in is not None else t_out) + (t_out if t_out is not None else t_in)
        tan.normalize()
        miter = 1.0 / max(tan.dot(t_in), 0.6) if t_in is not None and t_out is not None else 1.0
        side = n.cross(tan)
        side = (side - n * side.dot(n)).normalized()
        wl, wr, glow = widths[k]
        mid = bm.verts.new(p + n * lift)
        mid[part.glow] = glow
        if wl + wr < 1e-4:
            rows.append([mid])
        else:
            row = []
            for sgn, w in ((-1, wl), (1, wr)):
                q = sheet.move(a, b, side * (sgn * w * miter))
                _q, nq, _qa, _qb = sheet.frame(*q)
                v = bm.verts.new(sheet.pos(*q) + nq * lift)
                v[part.glow] = glow * 0.12
                row.append(v)
            rows.append([row[0], mid, row[1]])
        normals.append(n)
    for k, (ra, rb) in enumerate(itertools.pairwise(rows)):
        if len(ra) == 3 and len(rb) == 3:
            quads = [(ra[0], ra[1], rb[1], rb[0]), (ra[1], ra[2], rb[2], rb[1])]
        elif len(ra) == 3:
            quads = [(ra[0], ra[1], rb[0]), (ra[1], ra[2], rb[0])]
        elif len(rb) == 3:
            quads = [(ra[0], rb[1], rb[0]), (ra[0], rb[2], rb[1])]
        else:
            continue
        for q in quads:
            f = bm.faces.new(q)
            f.smooth = True
            f.normal_update()
            if f.normal.dot(normals[k] + normals[k + 1]) < 0:
                f.normal_flip()


def crack_widths(path: list, sheet: Sheet, width: float, rnd: random.Random, taper=(0.2, 0.25), w_end=0.0) -> list:
    """(left, right, glow) per path point: full width in the middle, tapering to points (or to w_end at the
    end), both edges jagged on their own; the glow dims toward the tips."""
    pos = [sheet.pos(*q) for q in path]
    arcs = [0.0]
    for a, b in itertools.pairwise(pos):
        arcs.append(arcs[-1] + (b - a).length)
    out = []
    for s in arcs:
        u = s / arcs[-1]
        env = min(1.0, u / taper[0] if taper[0] else 1.0, w_end + (1 - w_end) * (1 - u) / taper[1])
        env = max(env, 0.0) ** 0.7
        out.append(
            (0.5 * width * env * rnd.uniform(0.6, 1.2), 0.5 * width * env * rnd.uniform(0.6, 1.2), 0.5 + 0.5 * env)
        )
    return out


def add_branches(part: Part, sheet: Sheet, path: list, widths: list, rnd: random.Random, count: int) -> None:
    """Side cracks off a fissure, alternating sides, a bit below it so they don't fight over the overlap."""
    if len(path) < 5:
        return
    picks = sorted(rnd.sample(range(1, len(path) - 2), min(count, len(path) - 3)))
    sgn = rnd.choice((-1, 1))
    for k in picks:
        a, b = path[k]
        p, n, _pa, _pb = sheet.frame(a, b)
        tan = (sheet.pos(*path[k + 1]) - p).normalized()
        heading = Matrix.Rotation(sgn * rnd.uniform(0.7, 1.15), 3, n) @ tan
        sgn = -sgn
        bp = crack_branch(sheet, path[k], heading, rnd.randint(3, 5), rnd)
        w0 = (widths[k][0] + widths[k][1]) * 0.6
        bw = []
        for i in range(len(bp)):
            f = 1 - i / (len(bp) - 1)
            bw.append((0.5 * w0 * f**0.8, 0.5 * w0 * f**0.8, 0.6 + 0.3 * f))
        ribbon(part, sheet, bp, bw, 0.0035)


def plate_crack(part: Part, pl: dict, rnd: random.Random, v0: float, v1: float, width: float, branches: int) -> tuple:
    """Main fissure along a plate from v0 to v1 (zig-zagging across it) with side cracks; returns its end
    parameters (a, b)."""
    sheet = plate_sheet(pl)
    start = sheet.clamp(rnd.uniform(1.6, 3.4), v0 * 5)
    end = sheet.clamp(rnd.uniform(1.5, 3.5), v1 * 5)
    path = crack_walk(sheet, start, end, rnd)
    keep_end = v1 > 0.97  # runs out over the plate's top edge (onto the flesh): no pointed end
    widths = crack_widths(path, sheet, width, rnd, w_end=0.5 if keep_end else 0.0)
    ribbon(part, sheet, path, widths, 0.0045)
    add_branches(part, sheet, path, widths, rnd, branches)
    return path[-1]


def flesh_crack(part: Part, mound: Sheet, pl: dict, end: tuple, rnd: random.Random, width: float) -> None:
    """Continues an upper plate's fissure from under its top edge over the rim crest down to the mouth."""
    uu = end[0] / 2.5 - 1.0
    th = pl["th"] + uu * pl["hw"] * plate_width(1.0)
    t_mouth = next(i / 400 for i in range(400, 0, -1) if prof(i / 400)[0] > 0.49)
    a0 = th / math.tau * MOUND_SEG
    start = (a0, (pl["t1"] - 0.02) * (MOUND_RINGS - 1))
    stop = (a0 + rnd.uniform(-0.6, 0.6), t_mouth * (MOUND_RINGS - 1))
    path = crack_walk(mound, start, stop, rnd)
    widths = crack_widths(path, mound, width, rnd, taper=(0.0, 0.15), w_end=0.25)
    ribbon(part, mound, path, widths, 0.006)
    add_branches(part, mound, path, widths, rnd, 2)


# Which plates crack open when, as (gap index, upper row): stage 1 about a third of them, spread around the nest
# (the camera side and the back), stage 2 all the others, the upper ones in FLESH_CRACKS running on to the mouth.
CRACKS1 = [(0, True), (2, True), (3, False), (5, False), (6, True)]
FLESH_CRACKS = [1, 3, 5, 7]


def build_cracks(nest, plates: list) -> None:
    """Glowing fissures in the chitin plates (same glow material as the Mouth): Cracks1 on a third of the plates,
    Cracks2 more and longer ones on all the others, some running over the flesh to the mouth."""
    rnd = random.Random(29)  # own sequence: the nest above stays the same
    mound = mound_sheet()
    stage1, stage2 = Part("Cracks1", [GLOW]), Part("Cracks2", [GLOW])
    for pl in plates:
        if (pl["k"], pl["upper"]) in CRACKS1:
            plate_crack(stage1, pl, rnd, rnd.uniform(0.08, 0.15), rnd.uniform(0.85, 0.92), rnd.uniform(0.06, 0.07), 3)
            continue
        to_mouth = pl["upper"] and pl["k"] in FLESH_CRACKS
        v1 = 0.995 if to_mouth else rnd.uniform(0.9, 0.95)
        end = plate_crack(stage2, pl, rnd, rnd.uniform(0.05, 0.1), v1, rnd.uniform(0.055, 0.07), 3)
        if to_mouth:
            flesh_crack(stage2, mound, pl, end, rnd, rnd.uniform(0.05, 0.065))
        else:  # a second, shorter fissure across the plate
            plate_crack(stage2, pl, rnd, rnd.uniform(0.35, 0.5), rnd.uniform(0.75, 0.85), rnd.uniform(0.04, 0.05), 1)
    stage1.finish(nest)
    stage2.finish(nest)


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    rnd = random.Random(11)
    nest = C.asset_root(ASSET)
    mound = Part("Mound", [FLESH, CHITIN, RESIN, SAC])
    build_mound_body(mound)
    plates: list = []
    gaps = build_plates(mound, rnd, plates)
    build_sacs(mound, gaps, rnd)
    build_teeth(mound, rnd)
    tendrils = Part("Tendrils", [FLESH, CHITIN])
    glands: list = []
    tips = build_tendrils(tendrils, mound, glands, rnd)
    mound.finish(nest)
    tendrils.finish(nest)
    build_glands(nest, glands, rnd)
    build_mouth(nest)
    build_slime(nest, tips, rnd)
    C.empty("HatchPoint", HATCH, nest)
    build_cracks(nest, plates)
    return nest


def per_object_tris() -> None:
    print("STATS per object", C.tris_per_object())
    mound = bpy.data.objects["Mound"]
    reach = max((v.co.xy.length for v in mound.data.vertices if v.co.z > 0.1), default=0.0)
    print(f"STATS mound radius above 0.1 m: {reach:.2f} (collision 1.6)")


def clear_preview_rubble(radius: float = 4.7) -> None:
    """The shared preview scatters rubble up to 6 m out; keep it off the nest (preview only)."""
    for obj in list(C.collection("Preview").objects):
        if obj.type == "MESH" and obj.name.startswith("Icosphere") and obj.location.xy.length < radius:
            bpy.data.objects.remove(obj)


CLOSE_VIEWS = {
    "close": ((2.6, -3.2, 3.2), (0, 0, 0.9), 35),
    "top": ((0.01, -0.01, 16.0), (0, 0, 0), 40),
    "low": ((3.2, -4.0, 0.9), (0, 0, 0.6), 30),
}


def render_close(path: pathlib.Path, view: str, samples: int = 32, size: int = 640) -> None:
    loc, target, lens = CLOSE_VIEWS[view]
    C.render_from(path, loc, target, lens, samples, size)


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    if view in CLOSE_VIEWS:
        render_close(path, view, samples, size)
    elif view == "far":  # game distance (~18 m), to judge the read
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.35)
    elif view == "iso":
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=0.95)
    else:
        C.render(path, view=view, samples=samples, size=size, target=(0, 0, 0.7), zoom=1.05)


def main() -> None:
    C.reset(ASSET)
    make_materials()
    build()
    per_object_tris()
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(2.5, 2.1, 0.0))
    clear_preview_rubble()
    if MODE == "final":
        paths = []
        for view in ("iso", "hero", "back", "far"):
            p = OUT / f"render_{view}.png"
            render_view(p, view, 96, 1024)
            paths.append(p)
        C.contact_sheet(paths, OUT / "sheet.png", cols=2)
        C.save_blend(OUT / "nest_procedural.blend")
    else:
        for view in VIEWS:
            if view != "none":
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, 24, 512)


main()
