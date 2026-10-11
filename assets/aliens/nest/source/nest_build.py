"""Alien nest: a low organic mound of chitin plates, sinew and resin with a glowing mouth on top, tendrils
spreading over a slimy ground layer (concept: nest_v1..v4).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/nest/source/nest_build.py wip r1 [iso,hero,close,...]
    tools/blender.sh assets/aliens/nest/source/nest_build.py final

Everything it writes goes to tmp/assets/nest/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png; "final" renders iso/hero/back/far, a contact sheet (sheet.png) and saves the procedural
nest_procedural.blend that the bake stage turns into the game asset.

Game contract (scenes/aliens/alien_nest.tscn): collision cylinder r 1.6 m x 2.4 m, the mound stays inside it;
tendrils and slime spread to ~4.5 m; aliens hatch at settings.hatch_radius (3.5 m). Objects under the root
empty "Nest": Mound, Tendrils (share one texture atlas when baked), Slime and Mouth (own simple materials, the
game pulses the Mouth's glow), Glands (small glowing pustules, same glow material as the Mouth) and the empty
"HatchPoint" in the mouth. Origin at the ground center. Tube meshes carry a point attribute "flow"
(arc length in m, 0..1 along the tube, 1 = tube) that the procedural materials read for ribbing and tips.
Triangle budget ~15k, TBD (playtest).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "nest"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

import common as C  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
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
        for a, b in zip(pts, pts[1:]):
            out.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            out.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        out.append(pts[-1])
        pts = out
    return pts


_PTS = _chaikin(PROFILE)
_ARC = [0.0]
for _a, _b in zip(_PTS, _PTS[1:]):
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


def T(loc=(0, 0, 0), rot: Matrix | None = None, scale=(1, 1, 1)) -> Matrix:
    m = Matrix.Translation(Vector(loc))
    if rot is not None:
        m = m @ rot.to_4x4()
    return m @ Matrix.Diagonal((*scale, 1.0))


def basis(z_dir: Vector, x_hint: Vector) -> Matrix:
    z = Vector(z_dir).normalized()
    x = Vector(x_hint)
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


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
        for a, b in zip(rows, rows[1:]):
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
            0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f**3)
        )
    return out


def tube(part: Part, pts: list, radii: list, refs: list, sides: int, flat: float = 1.0, mi_fn=None, kind: float = 1.0) -> list:
    """Swept tube along pts with per-point radius; cross-section squashed to `flat` along refs (e.g. the
    surface normal, so tubes hug the surface). Radius 0 at the end makes a pointed tip; the start is open
    (start it buried in another surface)."""
    bm = part.bm
    total = sum((b - a).length for a, b in zip(pts, pts[1:]))
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
    for j, (ra, rb) in enumerate(zip(rows, rows[1:])):
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
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = detail
    tex.inputs["Roughness"].default_value = rough
    tex.inputs["Distortion"].default_value = dist
    nt.links.new(vec, tex.inputs["Vector"])
    return tex


def _math(nt, op: str, a, b=None, c=None, clamp: bool = False) -> bpy.types.NodeSocket:
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = op
    m.use_clamp = clamp
    for sock, val in ((m.inputs[0], a), (m.inputs[1], b), (m.inputs[2], c)):
        if val is None:
            continue
        if isinstance(val, bpy.types.NodeSocket):
            nt.links.new(val, sock)
        else:
            sock.default_value = val
    return m.outputs[0]


def _veins(nt, vec, scale: float, width: float) -> bpy.types.NodeSocket:
    """1 on thin branching vein lines: Voronoi cell edges, warped by noise."""
    warp = _noise(nt, vec, 1.8, 3.0, 0.5)
    add = nt.nodes.new("ShaderNodeVectorMath")
    add.operation = "MULTIPLY_ADD"
    nt.links.new(warp.outputs["Color"], add.inputs[0])
    add.inputs[1].default_value = (0.35, 0.35, 0.35)
    nt.links.new(vec, add.inputs[2])
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = scale
    nt.links.new(add.outputs[0], vor.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
    ramp.color_ramp.elements[1].position = width
    ramp.color_ramp.elements[1].color = (0, 0, 0, 1)
    nt.links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
    return ramp.outputs["Color"]


def _cavity(nt, distance: float = 0.25, lo: float = 0.35, hi: float = 0.95) -> bpy.types.NodeSocket:
    """1 in cavities (AO), 0 in the open."""
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = distance
    ao.samples = 16
    return _math(nt, "SUBTRACT", 1.0, _bw(nt, C._ramp(nt, lo, hi, ao.outputs["AO"])))


def _bw(nt, color: bpy.types.NodeSocket) -> bpy.types.NodeSocket:
    rgb = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(color, rgb.inputs["Color"])
    return rgb.outputs["Val"]


def _edges(nt, radius: float = 0.02, lo: float = 0.02, hi: float = 0.12) -> bpy.types.NodeSocket:
    """1 on convex edges (Bevel node normal vs the true normal; independent of the mesh density)."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = radius
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    return _bw(nt, C._ramp(nt, lo, hi, _math(nt, "SUBTRACT", 1.0, dot.outputs["Value"])))


def _flow(nt) -> tuple[bpy.types.NodeSocket, bpy.types.NodeSocket, bpy.types.NodeSocket]:
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "flow"
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(attr.outputs["Vector"], sep.inputs[0])
    return sep.outputs[0], sep.outputs[1], sep.outputs[2]


def _bump(nt, bsdf, height: bpy.types.NodeSocket, strength: float, distance: float) -> None:
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = distance
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def mat_flesh() -> bpy.types.Material:
    """Sinew: dark red to purple flesh with raised veins, ribbed along tubes, black glossy resin pooling in
    the cavities (wet: low roughness there)."""
    mat, nt, bsdf = C._new_material("Flesh")
    co = _coord(nt)
    big = _noise(nt, co, 1.3, 4.0, 0.5)
    col = C._mix_color(nt, big.outputs["Fac"], (0.095, 0.02, 0.013), (0.05, 0.013, 0.014))
    veins = _bw(nt, _veins(nt, co, 2.6, 0.045))
    col = C._mix_color(nt, veins, col, (0.03, 0.007, 0.018))
    s, u, kind = _flow(nt)
    jitter = _noise(nt, co, 3.0, 2.0, 0.5)
    phase = _math(nt, "MULTIPLY_ADD", jitter.outputs["Fac"], 3.0, _math(nt, "MULTIPLY", s, math.tau / 0.15))
    ribs = _math(nt, "SINE", phase)  # -1..1 along tubes, irregular spacing
    ribs01 = _math(nt, "MULTIPLY", _math(nt, "ADD", ribs, 1.0), 0.5)
    groove = _math(nt, "MULTIPLY", _bw(nt, C._ramp(nt, 0.6, 1.0, ribs01)), kind)  # 1 in the grooves between rings
    col = C._mix_color(nt, _math(nt, "MULTIPLY", groove, 0.35), col, (0.02, 0.005, 0.008))
    # Lighter, drier tone on the crowns of bulges: subtle so the flesh doesn't go flat.
    edge = _edges(nt, 0.015, 0.03, 0.2)
    col = C._mix_color(nt, _math(nt, "MULTIPLY", edge, 0.3), col, (0.2, 0.075, 0.06))
    cav = _cavity(nt, 0.3)
    col = C._mix_color(nt, _math(nt, "MULTIPLY", cav, 0.9), col, (0.012, 0.004, 0.006))
    nt.links.new(col, bsdf.inputs["Base Color"])
    wet = _noise(nt, co, 3.0, 3.0, 0.5)
    rough = C._mix_float(nt, wet.outputs["Fac"], 0.22, 0.5)
    rough = C._mix_float(nt, cav, rough, 0.07)
    rough = C._mix_float(nt, veins, rough, 0.18)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    fine = _noise(nt, co, 28.0, 4.0, 0.6)
    h = _math(nt, "ADD", _math(nt, "MULTIPLY", veins, 0.6), _math(nt, "MULTIPLY", groove, -0.4))
    h = _math(nt, "ADD", h, _math(nt, "MULTIPLY", fine.outputs["Fac"], 0.15))
    _bump(nt, bsdf, h, 0.45, 0.012)
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
    shell = C._mix_color(nt, _math(nt, "MULTIPLY", _bw(nt, bands), 0.35), shell, (0.085, 0.045, 0.035))
    s, u, kind = _flow(nt)
    tip = _math(nt, "MULTIPLY", C._ramp(nt, 0.7, 1.0, u), kind)
    edge = _edges(nt, 0.012, 0.03, 0.16)
    breakup = _noise(nt, co, 9.0, 6.0, 0.6)
    bone_mask = _math(nt, "ADD", _bw(nt, tip), edge, clamp=True)
    bone_mask = _math(nt, "MULTIPLY", bone_mask, _bw(nt, C._ramp(nt, 0.3, 0.55, breakup.outputs["Fac"])))
    col = C._mix_color(nt, _math(nt, "MULTIPLY", bone_mask, 0.8), shell, (0.3, 0.24, 0.17))
    cav = _cavity(nt, 0.2)
    col = C._mix_color(nt, _math(nt, "MULTIPLY", cav, 0.85), col, (0.01, 0.004, 0.004))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, big.outputs["Fac"], 0.22, 0.36)
    rough = C._mix_float(nt, bone_mask, rough, 0.55)
    rough = C._mix_float(nt, cav, rough, 0.08)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    fine = _noise(nt, co, 40.0, 3.0, 0.6)
    h = _math(nt, "ADD", _math(nt, "MULTIPLY", _bw(nt, bands), 0.5), _math(nt, "MULTIPLY", fine.outputs["Fac"], 0.2))
    _bump(nt, bsdf, h, 0.3, 0.008)
    return mat


def mat_resin() -> bpy.types.Material:
    """Hardened resin lining the crater and filling gaps: black-amber, glassy."""
    mat, nt, bsdf = C._new_material("Resin")
    co = _coord(nt)
    streak = _noise(nt, co, 4.0, 6.0, 0.6, dist=2.0)
    col = C._mix_color(nt, _bw(nt, C._ramp(nt, 0.45, 0.75, streak.outputs["Fac"])), (0.016, 0.006, 0.005), (0.09, 0.035, 0.012))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, streak.outputs["Fac"], 0.06, 0.2), bsdf.inputs["Roughness"])
    _bump(nt, bsdf, streak.outputs["Fac"], 0.25, 0.01)
    return mat


def mat_sac() -> bpy.types.Material:
    """Egg sacs: pale, sickly membrane with dark red veins, very glossy."""
    mat, nt, bsdf = C._new_material("EggSac")
    co = _coord(nt)
    big = _noise(nt, co, 3.0, 3.0, 0.5)
    col = C._mix_color(nt, big.outputs["Fac"], (0.11, 0.09, 0.04), (0.2, 0.16, 0.075))
    veins = _bw(nt, _veins(nt, co, 5.0, 0.05))
    col = C._mix_color(nt, veins, col, (0.09, 0.012, 0.015))
    cav = _cavity(nt, 0.15)
    col = C._mix_color(nt, _math(nt, "MULTIPLY", cav, 0.85), col, (0.02, 0.006, 0.004))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, veins, 0.1, 0.25), bsdf.inputs["Roughness"])
    _bump(nt, bsdf, veins, 0.35, 0.006)
    return mat


def mat_slime() -> bpy.types.Material:
    """Slime layer on the ground: near-black wine, wet, barely varying (cheap in game)."""
    mat, nt, bsdf = C._new_material("Slime")
    co = _coord(nt)
    big = _noise(nt, co, 0.9, 3.0, 0.5)
    nt.links.new(C._mix_color(nt, big.outputs["Fac"], (0.012, 0.004, 0.005), (0.032, 0.008, 0.011)), bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, big.outputs["Fac"], 0.04, 0.14), bsdf.inputs["Roughness"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.6
    ripple = _noise(nt, co, 2.5, 2.0, 0.4)
    _bump(nt, bsdf, ripple.outputs["Fac"], 0.12, 0.02)
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
    strength = _math(nt, "MULTIPLY", C._mix_float(nt, churn.outputs["Fac"], 2.5, 9.0), glow.outputs["Fac"])
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
    for j, (a, b) in enumerate(zip(rows, rows[1:])):
        mi = M_RESIN if ts[j] > T_CREST + 0.04 else M_FLESH
        faces = part.faces([a, b], mi, closed_u=True)
        orient(part, faces, (faces[0].calc_center_median() - Vector((0, 0, 0.3))) if ts[j] < T_CREST else Z, 0)


def plate(part: Part, th_c: float, hw: float, t0: float, t1: float, lift: float, thick: float) -> None:
    """Shield-shaped chitin plate following the mound surface; the pointed lower end lifts off like a scale."""
    nu, nv = 6, 6
    top, bot = [], []
    for j in range(nv):
        v = j / (nv - 1)
        t = t0 + v * (t1 - t0)
        w = (0.15 + 0.85 * math.sin(min(v / 0.6, 1.0) * math.pi / 2)) * (1 - 0.3 * max(0.0, (v - 0.7) / 0.3))
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


def build_plates(part: Part, rnd: random.Random) -> list:
    """Two rows of plates in the gaps between the tendrils; returns gaps left free for egg sacs."""
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
            plate(part, mid + rnd.uniform(-0.04, 0.04), hw, t_at_z(0.2), t_at_z(0.8), 0.07, 0.05)
        plate(part, mid + rnd.uniform(-0.05, 0.05), hw * 0.92, t_at_z(0.62), t_at_z(1.2), 0.07, 0.045)
    return sac_gaps


def build_sacs(part: Part, gaps: list, rnd: random.Random) -> None:
    for mid, hw in gaps:
        for th, t, r in ((mid - hw * 0.35, t_at_z(0.32), 0.27), (mid + hw * 0.45, t_at_z(0.26), 0.22), (mid + hw * 0.05, t_at_z(0.62), 0.18)):
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
        for a, b in zip(pts, pts[1:]):
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
            edge = SLIME_R + 0.3 * noise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, 0.5))) + 0.08 * math.sin(11 * a)
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


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    rnd = random.Random(11)
    nest = C.asset_root(ASSET)
    mound = Part("Mound", [FLESH, CHITIN, RESIN, SAC])
    build_mound_body(mound)
    gaps = build_plates(mound, rnd)
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
    return nest


def per_object_tris() -> list:
    dg = bpy.context.evaluated_depsgraph_get()
    rows = []
    for obj in C.collection(ASSET).all_objects:
        if obj.type == "MESH":
            me = obj.evaluated_get(dg).to_mesh()
            me.calc_loop_triangles()
            rows.append((len(me.loop_triangles), obj.name))
            obj.evaluated_get(dg).to_mesh_clear()
    print("STATS per object", sorted(rows, reverse=True))
    mound = bpy.data.objects["Mound"]
    reach = max((v.co.xy.length for v in mound.data.vertices if v.co.z > 0.1), default=0.0)
    print(f"STATS mound radius above 0.1 m: {reach:.2f} (collision 1.6)")
    return rows


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
    C.render(path, view="hero", samples=1, size=16)  # applies common's render settings and creates "Cam"
    cam = bpy.context.scene.camera
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    scene.cycles.samples = samples
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    if view in CLOSE_VIEWS:
        render_close(path, view, samples, size)
    elif view == "far":  # game distance (~18 m), to judge the read
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.35)
    elif view == "iso":
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=0.95)
    else:
        C.render(path, view=view, samples=samples, size=size, target=(0, 0, 0.7), zoom=1.05)


def contact_sheet(paths: list, out: pathlib.Path, cols: int = 2) -> None:
    import numpy as np

    imgs = [bpy.data.images.load(str(p)) for p in paths]
    w, h = imgs[0].size
    rows = (len(imgs) + cols - 1) // cols
    sheet = np.zeros((rows * h, cols * w, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for k, img in enumerate(imgs):
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        r, c = rows - 1 - k // cols, k % cols  # Blender images start at the bottom row
        sheet[r * h : (r + 1) * h, c * w : (c + 1) * w] = px
    res = bpy.data.images.new("sheet", cols * w, rows * h, alpha=False)
    res.pixels.foreach_set(sheet.ravel())
    res.filepath_raw = str(out)
    res.file_format = "PNG"
    res.save()


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
        contact_sheet(paths, OUT / "sheet.png")
        C.save_blend(OUT / "nest_procedural.blend")
    else:
        for view in VIEWS:
            if view != "none":
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, 24, 512)


main()
