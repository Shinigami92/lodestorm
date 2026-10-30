"""Blueprint fragment: the quest item, one piece of a lost weapon blueprint. A cracked, scorched engineering data plate
with one corner broken off, held upright in a dark gunmetal sleeve that covers its lower third; an amber data trace
(a thin vertical strip with a few etched branches) glows on the exposed face, a small status lamp on the sleeve.
Found in crates out in the field and carried clicked into a slotted holder on the player's backpack, so it must read
at a tiny size from the isometric camera: the amber glow carries the read.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/quests/blueprint_fragment/source/blueprint_fragment_build.py wip r1 [views]
    tools/blender.sh assets/quests/blueprint_fragment/source/blueprint_fragment_build.py final

Everything it writes goes to tmp/assets/blueprint_fragment/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (views: iso, hero, back, front, game = the game camera's distance, game4 = the same camera zoomed in
4x); "final" renders the preview set, a contact sheet (sheet.png) and saves the procedural
blueprint_fragment_procedural.blend that blueprint_fragment_bake.py turns into the game asset.

Layout (Blender Z-up meters; glTF turns it into Godot's Y-up): the origin is the bottom center of the sleeve, the
fragment stands upright with the plate's face towards -Y. Meshes: "Plate" and "Sleeve" (baked into one atlas) and
"Glow" (the amber trace and the lamp, one constant emissive material the game may override).

The plate's face detail (etched circuit traces, cracks, scorch) is a raster drawn here with numpy and projected onto
the face along Y; the bake turns it into the atlas like any other procedural material.
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "blueprint_fragment"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import common as C
from common import T, rx, ry

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["iso", "hero", "game4"]

ASSET = "BlueprintFragment"
AMBER = (1.0, 0.522, 0.073)  # linear for sRGB Color(1.0, 0.75, 0.3)
GLOW_STRENGTH = 2.5

# --- layout (meters, Z-up, face towards -Y, origin = bottom center of the sleeve) ------------------------------

PLATE_W = 0.16
PLATE_T = 0.025
PLATE_Z = (0.062, 0.232)  # the plate's hidden bottom sits deep in the sleeve; 0.22 m tall from its real bottom
SLEEVE_W = 0.18
SLEEVE_D = 0.052
SLEEVE_H = 0.086  # covers the plate's lower third
FRONT_Y = -PLATE_T / 2  # the plate's face

# Plate outline in the face plane (x, z), counter-clockwise; the top right corner is broken off along a jagged line.
# Each point starts an edge of the given kind: "rim" (machined edge) or "break" (fracture).
X0, X1 = -PLATE_W / 2, PLATE_W / 2
Z0, Z1 = PLATE_Z
OUTLINE = [
    ((X0, Z0), "rim"),
    ((X1, Z0), "rim"),
    ((X1, 0.158), "break"),
    ((0.073, 0.170), "break"),
    ((0.0765, 0.177), "break"),
    ((0.064, 0.189), "break"),
    ((0.0585, 0.1915), "break"),
    ((0.060, 0.199), "break"),
    ((0.047, 0.2105), "break"),
    ((0.0425, 0.209), "break"),
    ((0.037, 0.221), "break"),
    ((0.026, Z1), "rim"),
    ((X0 + 0.006, Z1), "rim"),
    ((X0, Z1 - 0.006), "rim"),
]
BREAK = [p for p, _k in OUTLINE[2:12]]

# Glowing data trace: the vertical strip in a dark bezel, branches as polylines (x, z), pads at some ends.
STRIP_X = -0.046
STRIP_Z = (0.100, 0.214)
STRIP_W = 0.011
BEZEL = (0.018, (0.094, 0.220))  # width, z range
TRACE_W = 0.0028
TRACES = [  # (points, pad at the end); the top one runs into the break
    ([(-0.040, 0.202), (-0.004, 0.202), (0.006, 0.212), (0.040, 0.212)], False),
    ([(-0.040, 0.172), (0.016, 0.172), (0.028, 0.160), (0.056, 0.160)], True),
    ([(-0.040, 0.128), (0.006, 0.128), (0.016, 0.138), (0.044, 0.138)], True),
    ([(-0.052, 0.152), (-0.066, 0.152)], True),
]
LAMP = (0.064, 0.050)  # (x, z) on the sleeve's front

# Face raster: a square in the face plane (x, z) covering the plate.
RX0, RZ0, RS, RN = -0.09, 0.056, 0.18, 1024
PX = RS / RN

# --- mesh builder ----------------------------------------------------------------------------------------------


class Part(C.Part):
    """common.Part with weighted bevels (only the hard edges of the big forms get one; small parts, detail = True,
    stay sharp and cheap), plus the plate's slab (outline extruded along Y, its edges by kind) and boxes along a
    polyline in the face plane."""

    def __init__(self, name: str, mats: list, bevel: tuple[float, int] | None = (0.002, 1)):
        super().__init__(name, mats, bevel)
        self.weight = self.bm.edges.layers.float.new("bevel_weight_edge")
        self.detail = False

    def _weights(self, faces) -> None:
        for e in {e for f in faces for e in f.edges}:
            hard = e.is_manifold and e.calc_face_angle(0.0) > math.radians(35)
            e[self.weight] = 1.0 if hard and not self.detail else 0.0
            e.smooth = not (hard and self.detail)

    def _tag(self, verts, mi: int, smooth: bool = True):
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = mi
            f.smooth = smooth
        self._weights(faces)
        return verts

    def _bevel(self, obj: bpy.types.Object) -> None:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = self.bev[0]
        mod.segments = self.bev[1]
        mod.limit_method = "WEIGHT"
        mod.harden_normals = True
        obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL").keep_sharp = True

    def slab(self, outline: list, depth: float, mi_face: int, mi_kind: dict, y: float = 0.0) -> list:
        m = T((0, y, 0), rx(90))  # local (a, b, c) -> world (a, -c, b): the outline in (x, z), extruded along Y
        back = [self.bm.verts.new(m @ Vector((x, z, -depth / 2))) for (x, z), _k in outline]
        front = [self.bm.verts.new(m @ Vector((x, z, depth / 2))) for (x, z), _k in outline]
        n = len(outline)
        faces = []
        for i, (_p, kind) in enumerate(outline):
            f = self.bm.faces.new((back[i], back[(i + 1) % n], front[(i + 1) % n], front[i]))
            f.material_index = mi_kind[kind]
            faces.append(f)
        for cap in (self.bm.faces.new(list(reversed(back))), self.bm.faces.new(front)):
            cap.material_index = mi_face
            faces.append(cap)
        for f in faces:
            f.normal_update()
            f.smooth = True
        self._weights(faces)
        return back + front

    def strip(self, pts: list, width: float, y: float, depth: float, mi: int = 0) -> None:
        """Flat boxes along a polyline (x, z) in the face plane, centered at y."""
        for (ax, az), (bx, bz) in itertools.pairwise(pts):
            length = math.hypot(bx - ax, bz - az)
            ang = math.degrees(math.atan2(bz - az, bx - ax))
            self.box(((ax + bx) / 2, y, (az + bz) / 2), (length + width, depth, width), rot=ry(-ang), mi=mi)

    def finish(self, parent) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        return super().finish(parent)


SIDE = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0)))  # profiles drawn in the side view (y, z), extruded across X


def side_prism(part: Part, pts: list, width: float, x: float = 0.0, mi: int = 0) -> list:
    return part.prism(pts, x - width / 2, x + width / 2, T((0, 0, 0)) @ SIDE.to_4x4(), mi)


def inset_faces(part: Part, verts, axis, thickness: float, depth: float, mi: int | None = None) -> None:
    """Panel line: inset the faces of a fresh primitive whose normal points along +axis."""
    axis = Vector(axis).normalized()
    faces = [f for f in {f for v in verts for f in v.link_faces} if f.normal.dot(axis) > 0.9]
    bmesh.ops.inset_individual(part.bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)
    if mi is not None:
        for f in faces:
            f.material_index = mi


# --- face raster (numpy) ---------------------------------------------------------------------------------------

GX, GZ = np.meshgrid(RX0 + (np.arange(RN) + 0.5) * PX, RZ0 + (np.arange(RN) + 0.5) * PX)  # rows go up in z


def _window(lo: np.ndarray, hi: np.ndarray, pad: float) -> tuple[slice, slice]:
    i0 = max(int((lo[0] - pad - RX0) / PX), 0)
    i1 = min(int((hi[0] + pad - RX0) / PX) + 2, RN)
    j0 = max(int((lo[1] - pad - RZ0) / PX), 0)
    j1 = min(int((hi[1] + pad - RZ0) / PX) + 2, RN)
    return slice(j0, j1), slice(i0, i1)


def stroke(acc: np.ndarray, pts: list, w0: float, w1: float | None = None) -> None:
    """Draw a polyline into acc (max), anti-aliased, its width tapering from w0 to w1 along its length."""
    w1 = w0 if w1 is None else w1
    p = np.asarray(pts, dtype=np.float64)
    seg = np.linalg.norm(p[1:] - p[:-1], axis=1)
    start = np.concatenate(([0.0], np.cumsum(seg)))
    total = max(start[-1], 1e-9)
    for k in range(len(p) - 1):
        a, b = p[k], p[k + 1]
        rows, cols = _window(np.minimum(a, b), np.maximum(a, b), max(w0, w1))
        x, z = GX[rows, cols], GZ[rows, cols]
        ab = b - a
        t = np.clip(((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / max(ab @ ab, 1e-12), 0.0, 1.0)
        d = np.hypot(x - (a[0] + t * ab[0]), z - (a[1] + t * ab[1]))
        w = w0 + (w1 - w0) * (start[k] + t * seg[k]) / total
        acc[rows, cols] = np.maximum(acc[rows, cols], np.clip((w / 2 - d) / PX + 0.5, 0.0, 1.0))


def dot(acc: np.ndarray, c, r: float) -> None:
    c = np.asarray(c, dtype=np.float64)
    rows, cols = _window(c, c, r)
    d = np.hypot(GX[rows, cols] - c[0], GZ[rows, cols] - c[1])
    acc[rows, cols] = np.maximum(acc[rows, cols], np.clip((r - d) / PX + 0.5, 0.0, 1.0))


def value_noise(rng: np.random.Generator, cells: int) -> np.ndarray:
    """Smooth value noise over the raster, 0..1."""
    g = rng.random((cells + 2, cells + 2))
    t = np.linspace(0, cells, RN, endpoint=False)
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    fx, fz = np.meshgrid(f, f)
    ix, iz = np.meshgrid(i, i)
    top = g[iz, ix] * (1 - fx) + g[iz, ix + 1] * fx
    bot = g[iz + 1, ix] * (1 - fx) + g[iz + 1, ix + 1] * fx
    return top * (1 - fz) + bot * fz


def fbm(rng: np.random.Generator, cells: int, octaves: int = 3) -> np.ndarray:
    out, amp, norm = np.zeros((RN, RN)), 1.0, 0.0
    for o in range(octaves):
        out += amp * value_noise(rng, cells * 2**o)
        norm += amp
        amp *= 0.5
    return out / norm


S2 = math.sqrt(0.5)
DIRS = [(1, 0), (S2, S2), (0, 1), (-S2, S2), (-1, 0), (-S2, -S2), (0, -1), (S2, -S2)]
TRACE_BOX = ((-0.074, 0.092), (0.074, 0.226))  # etched traces stay inside (they may run into the break)


def offset_polyline(pts: list, off: float) -> list:
    """Parallel polyline (mitered corners), for buses of traces."""
    p = [Vector(q) for q in pts]
    out = []
    for i in range(len(p)):
        d0 = (p[i] - p[i - 1]).normalized() if i > 0 else (p[1] - p[0]).normalized()
        d1 = (p[i + 1] - p[i]).normalized() if i < len(p) - 1 else d0
        n0, n1 = Vector((-d0.y, d0.x)), Vector((-d1.y, d1.x))
        n = (n0 + n1).normalized()
        out.append(tuple(p[i] + n * off / max(n.dot(n0), 0.3)))
    return out


def route(rng: np.random.Generator) -> list:
    """A circuit trace: orthogonal runs joined by short 45 degree jogs."""
    (lx, lz), (hx, hz) = TRACE_BOX
    p = Vector((rng.uniform(lx, hx), rng.uniform(lz, hz)))
    d = int(rng.choice([0, 2, 4, 6]))
    pts = [tuple(p)]
    for _ in range(int(rng.integers(2, 6))):
        diag = d % 2 == 1
        step = Vector(DIRS[d]) * (rng.uniform(0.003, 0.007) if diag else rng.uniform(0.008, 0.032))
        q = p + step
        if not (lx <= q.x <= hx and lz <= q.y <= hz):
            break
        p = q
        pts.append(tuple(p))
        d = (d + int(rng.choice([-1, 1]))) % 8 if diag else (d + int(rng.choice([-1, 0, 1]))) % 8
    return pts


def face_raster() -> np.ndarray:
    """RGBA raster of the plate's face: R etched traces, G cracks, B scorch, A the chipped halo around the cracks."""
    rng = np.random.default_rng(11)
    trace = np.zeros((RN, RN))
    for _ in range(30):
        pts = route(rng)
        if len(pts) < 2:
            continue
        lines = int(rng.choice([1, 1, 2, 3, 4]))
        for j in range(lines):
            line = offset_polyline(pts, (j - (lines - 1) / 2) * 0.0024)
            stroke(trace, line, 0.0008)
            dot(trace, line[0], 0.0012)
            dot(trace, line[-1], 0.0012)
    # Two chip footprints: outline and contact pads.
    for (cx, cz), (w, h) in (((0.004, 0.106), (0.024, 0.014)), ((-0.068, 0.198), (0.012, 0.022))):
        x0, x1, z0, z1 = cx - w / 2, cx + w / 2, cz - h / 2, cz + h / 2
        stroke(trace, [(x0, z0), (x1, z0), (x1, z1), (x0, z1), (x0, z0)], 0.0008)
        n = int(w / 0.003) if w > h else int(h / 0.003)
        for k in range(n):
            u = (k + 0.5) / n
            if w > h:
                for z in (z0 - 0.0018, z1 + 0.0018):
                    stroke(trace, [(x0 + u * w, z - 0.0008), (x0 + u * w, z + 0.0008)], 0.0012)
            else:
                for x in (x0 - 0.0018, x1 + 0.0018):
                    stroke(trace, [(x - 0.0008, z0 + u * h), (x + 0.0008, z0 + u * h)], 0.0012)

    # Cracks: jagged random walks from the break into the plate, tapering, a branch each; one hairline from the left.
    crack = np.zeros((RN, RN))
    halo = np.zeros((RN, RN))
    starts = [(BREAK[1], 198.0, 13, 0.0022), (BREAK[4], 222.0, 11, 0.0019), (BREAK[7], 250.0, 9, 0.0017)]
    starts.append(((X0, 0.216), -15.0, 6, 0.0009))
    for (sx, sz), heading, steps, width in starts:
        pts = [(sx, sz)]
        ang = math.radians(heading)
        for k in range(steps):
            ang = math.radians(heading) + float(np.clip(ang - math.radians(heading) + rng.normal(0, 0.5), -0.7, 0.7))
            ln = rng.uniform(0.005, 0.011)
            nxt = (pts[-1][0] + math.cos(ang) * ln, pts[-1][1] + math.sin(ang) * ln)
            if heading > 90 and nxt[0] < STRIP_X + 0.014:  # stop short of the glowing strip
                break
            pts.append(nxt)
            if k == steps // 3:
                b_ang, b_pts = ang + float(rng.choice([-0.8, 0.8])), [pts[-1]]
                for _ in range(steps // 2):
                    b_ang += rng.normal(0, 0.4)
                    bl = rng.uniform(0.003, 0.007)
                    b_pts.append((b_pts[-1][0] + math.cos(b_ang) * bl, b_pts[-1][1] + math.sin(b_ang) * bl))
                stroke(crack, b_pts, width * 0.55, 0.00015)
                stroke(halo, b_pts, width * 2.2, 0.0006)
        stroke(crack, pts, width, 0.0002)
        stroke(halo, pts, width * 3.0, 0.0008)

    # Scorch: soot along the break and the edges, blotchy, plus a char mark low on the left.
    d_break = np.full((RN, RN), 1.0)
    for a, b in itertools.pairwise(BREAK):
        a, b = np.asarray(a), np.asarray(b)
        ab = b - a
        t = np.clip(((GX - a[0]) * ab[0] + (GZ - a[1]) * ab[1]) / (ab @ ab), 0, 1)
        d_break = np.minimum(d_break, np.hypot(GX - (a[0] + t * ab[0]), GZ - (a[1] + t * ab[1])))
    d_edge = np.minimum(np.minimum(GX - X0, X1 - GX), Z1 - GZ)
    blotch = fbm(rng, 6)
    fine = fbm(rng, 24, 2)
    scorch = np.exp(-d_break / 0.026) * (0.6 + 0.9 * blotch)
    scorch += 0.4 * np.exp(-np.maximum(d_edge, 0) / 0.005) * fine
    scorch += 0.55 * np.exp(-np.hypot(GX + 0.058, GZ - 0.108) / 0.016) * fine
    scorch += 0.15 * np.clip((blotch - 0.62) * 5, 0, 1)
    scorch = np.clip(scorch * (0.75 + 0.5 * fine), 0, 1)

    return np.stack([trace, crack, scorch, halo], axis=-1).astype(np.float32)


def face_image() -> bpy.types.Image:
    img = bpy.data.images.new("FragmentFace", RN, RN, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.alpha_mode = "CHANNEL_PACKED"
    img.pixels.foreach_set(face_raster().ravel())
    img.filepath_raw = str(OUT / "face_raster.png")
    img.file_format = "PNG"
    OUT.mkdir(parents=True, exist_ok=True)
    img.save()
    img.pack()  # the bake opens the procedural .blend without tmp/ files
    return img


# --- materials -------------------------------------------------------------------------------------------------


def rescale(mat: bpy.types.Material, noise_factor: float, ao_distance: float) -> None:
    """common's materials are tuned for a 3.6 m machine: shrink their noise and cavity sizes to a 0.2 m prop."""
    for n in mat.node_tree.nodes:
        if n.bl_idname == "ShaderNodeTexNoise":
            n.inputs["Scale"].default_value *= noise_factor
        elif n.bl_idname == "ShaderNodeAmbientOcclusion":
            n.inputs["Distance"].default_value = ao_distance
        elif n.bl_idname == "ShaderNodeBump":
            n.inputs["Distance"].default_value *= 0.25


def _sep(nt, vec: bpy.types.NodeSocket) -> bpy.types.Node:
    node = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vec, node.inputs[0])
    return node


def _scratches(nt, coord: bpy.types.NodeSocket, angle: float, scale: float) -> bpy.types.NodeSocket:
    """Thin straight scratches: noise stretched along one direction in the face plane, thresholded."""
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (0.0, math.radians(angle), 0.0)
    mp.inputs["Scale"].default_value = (scale * 0.02, scale, scale)
    nt.links.new(coord, mp.inputs["Vector"])
    noise = C._noise(nt, 1.0, 3.0, 0.5, vector=mp.outputs["Vector"])
    return C._math(nt, "MULTIPLY", C._bw(nt, C._ramp(nt, 0.66, 0.7, noise.outputs["Fac"])), 1.0)


def mat_face(img: bpy.types.Image) -> bpy.types.Material:
    """The data plate's face: dark ceramic composite, etched gold traces (front only), cracks with chipped rims,
    soot, fine scratches; the masks come from the face raster projected along Y."""
    mat, nt, bsdf = C._new_material("PlateFace")
    coord = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    xyz = _sep(nt, coord)
    uv = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(C._math(nt, "MULTIPLY_ADD", xyz.outputs["X"], 1 / RS, -RX0 / RS), uv.inputs["X"])
    nt.links.new(C._math(nt, "MULTIPLY_ADD", xyz.outputs["Z"], 1 / RS, -RZ0 / RS), uv.inputs["Y"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.extension = "EXTEND"
    tex.interpolation = "Cubic"
    nt.links.new(uv.outputs[0], tex.inputs["Vector"])
    rgb = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], rgb.inputs[0])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    front = C._math(nt, "LESS_THAN", _sep(nt, geo.outputs["Normal"]).outputs["Y"], 0.0)
    trace = C._math(nt, "MULTIPLY", rgb.outputs["Red"], front)
    crack, scorch, halo = rgb.outputs["Green"], rgb.outputs["Blue"], tex.outputs["Alpha"]
    scratch = C._math(
        nt, "MAXIMUM", _scratches(nt, coord, 12.0, 260.0), C._math(nt, "MULTIPLY", _scratches(nt, coord, -31, 190), 0.7)
    )
    scratch = C._math(nt, "MULTIPLY", scratch, C._math(nt, "SUBTRACT", 1.0, scorch))
    mottle = C._noise(nt, 90.0, 5.0, 0.6).outputs["Fac"]

    base = C._mix_color(nt, mottle, (0.04, 0.044, 0.05), (0.062, 0.067, 0.075))
    base = C._mix_color(nt, C._math(nt, "MULTIPLY", scratch, 0.6), base, (0.13, 0.135, 0.14))
    base = C._mix_color(nt, trace, base, (0.36, 0.25, 0.1))
    base = C._mix_color(nt, C._math(nt, "MULTIPLY", halo, 0.75), base, (0.17, 0.165, 0.16))
    base = C._mix_color(nt, C._bw(nt, C._ramp(nt, 0.08, 0.4, scorch)), base, (0.075, 0.045, 0.024))  # heat tint
    base = C._mix_color(nt, C._bw(nt, C._ramp(nt, 0.35, 0.85, scorch)), base, (0.007, 0.006, 0.005))  # soot
    base = C._mix_color(nt, crack, base, (0.002, 0.002, 0.002))
    nt.links.new(base, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, mottle, 0.24, 0.36)
    rough = C._mix_float(nt, scratch, rough, 0.18)
    rough = C._mix_float(nt, trace, rough, 0.4)
    rough = C._mix_float(nt, scorch, rough, 0.82)
    rough = C._mix_float(nt, crack, rough, 0.95)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    metal = C._math(nt, "MULTIPLY", trace, C._math(nt, "MULTIPLY_ADD", scorch, -0.8, 1.0))
    nt.links.new(metal, bsdf.inputs["Metallic"])
    height = C._math(nt, "MULTIPLY_ADD", trace, -0.35, C._math(nt, "MULTIPLY", crack, -1.0))
    height = C._math(nt, "MULTIPLY_ADD", halo, -0.15, height)
    height = C._math(nt, "MULTIPLY_ADD", scratch, -0.12, height)
    C._bump(nt, bsdf, height, 0.6, 0.0008)
    return mat


def mat_fracture() -> bpy.types.Material:
    """The broken edge: rough, laminated core (pale and dark layers through the thickness, a copper sheet in the
    middle), sooty."""
    mat, nt, bsdf = C._new_material("PlateFracture")
    coord = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
    y = _sep(nt, coord).outputs["Y"]
    layers = C._math(nt, "SINE", C._math(nt, "MULTIPLY", y, 2 * math.pi * 4.5 / PLATE_T))
    grain = C._noise(nt, 900.0, 4.0, 0.7)
    copper = C._math(nt, "LESS_THAN", C._math(nt, "ABSOLUTE", y), 0.0012)
    soot = C._ramp(nt, 0.4, 0.75, C._noise(nt, 160.0, 4.0, 0.6).outputs["Fac"])
    base = C._mix_color(nt, C._ramp(nt, -0.3, 0.6, layers), (0.035, 0.034, 0.033), (0.15, 0.142, 0.13))
    base = C._mix_color(nt, C._bw(nt, soot), base, (0.012, 0.01, 0.009))
    base = C._mix_color(nt, copper, base, (0.45, 0.22, 0.09))
    nt.links.new(base, bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, copper, 0.88, 0.45), bsdf.inputs["Roughness"])
    nt.links.new(copper, bsdf.inputs["Metallic"])
    C._bump(nt, bsdf, grain.outputs["Fac"], 0.9, 0.0006)
    return mat


def mat_chips(mat: bpy.types.Material, amount: float, scale: float) -> None:
    """Paint chips and scuffs on the flat faces too (common's wear only reaches the edges): a fine noise
    thresholded inside a large worn-area mask shows bare metal."""
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    fine = C._noise(nt, scale, 10.0, 0.72)
    area = C._noise(nt, scale / 12.0, 3.0, 0.5)
    chip = C._math(
        nt,
        "MULTIPLY",
        C._bw(nt, C._ramp(nt, 0.64 - 0.06 * amount, 0.67 - 0.06 * amount, fine.outputs["Fac"])),
        C._bw(nt, C._ramp(nt, 0.45, 0.6, area.outputs["Fac"])),
    )
    for name, val in (("Base Color", (0.3, 0.3, 0.31)), ("Roughness", 0.34)):
        sock = bsdf.inputs[name]
        src = sock.links[0].from_socket
        mixed = C._mix_color(nt, chip, src, val) if name == "Base Color" else C._mix_float(nt, chip, src, val)
        nt.links.new(mixed, sock)
    nt.links.new(C._math(nt, "MAXIMUM", bsdf.inputs["Metallic"].links[0].from_socket, chip), bsdf.inputs["Metallic"])


def make_materials(img: bpy.types.Image) -> None:
    global PLATE_MATS, SLEEVE_MATS, GLOW
    face = mat_face(img)
    rim = C.mat_bare_metal("PlateRim", (0.07, 0.07, 0.075), 0.5)
    rescale(rim, 12.0, 0.01)
    black = C.mat_rubber("Black", (0.012, 0.012, 0.013))
    black.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.55
    gunmetal = C.mat_painted_metal("Gunmetal", (0.05, 0.052, 0.056), wear=0.45, grime=0.45, roughness=0.45)
    rescale(gunmetal, 12.0, 0.012)
    C.bevel_wear(gunmetal, lo=0.012, hi=0.05, radius=0.002)
    mat_chips(gunmetal, 0.5, 320.0)
    steel = C.mat_bare_metal("Steel", (0.38, 0.38, 0.39), 0.32)
    rescale(steel, 12.0, 0.01)
    PLATE_MATS = [face, rim, mat_fracture(), black]
    SLEEVE_MATS = [gunmetal, steel, black]
    GLOW = C.mat_emissive("BlueprintFragment_Glow", AMBER, GLOW_STRENGTH)


M_FACE, M_RIM, M_FRACTURE, M_BLACK = 0, 1, 2, 3  # Plate
M_GUN, M_STEEL, M_SBLACK = 0, 1, 2  # Sleeve


# --- parts -----------------------------------------------------------------------------------------------------


def build_plate(root) -> None:
    plate = Part("Plate", PLATE_MATS, bevel=(0.0015, 1))
    plate.slab(OUTLINE, PLATE_T, M_FACE, {"rim": M_RIM, "break": M_FRACTURE})
    w, (z0, z1) = BEZEL
    plate.detail = True
    plate.box((STRIP_X, FRONT_Y, (z0 + z1) / 2), (w, 0.0016, z1 - z0), mi=M_BLACK)
    plate.finish(root)


def build_sleeve(root) -> None:
    s = Part("Sleeve", SLEEVE_MATS, bevel=(0.0025, 2))
    s.detail = False
    d, h = SLEEVE_D / 2, SLEEVE_H
    body = side_prism(
        s,
        [(-d, 0.0), (d, 0.0), (d, h - 0.006), (d - 0.004, h), (-d + 0.005, h), (-d, h - 0.011)],
        SLEEVE_W,
        mi=M_GUN,
    )
    inset_faces(s, body, (0, -1, 0), 0.006, -0.0012)
    fy = -d + 0.0012  # recessed front panel
    # Collar around the slot: gaskets against the plate, raised lips, end blocks.
    for sy in (-1, 1):
        s.detail = True
        s.box((0, sy * (PLATE_T / 2 + 0.00125), h + 0.0015), (PLATE_W + 0.004, 0.0025, 0.005), mi=M_SBLACK)
        s.detail = False
        s.box((0, sy * 0.0175, h + 0.0025), (PLATE_W + 0.012, 0.005, 0.007), mi=M_GUN)
    for sx in (-1, 1):
        s.box((sx * 0.0845, 0, h + 0.0025), (0.009, 0.04, 0.007), mi=M_GUN)
        # Clamp blocks on the ends, a hex screw each.
        s.box((sx * (SLEEVE_W / 2 + 0.003), 0, 0.042), (0.006, 0.038, 0.062), mi=M_GUN)
        s.detail = True
        s.cyl((sx * (SLEEVE_W / 2 + 0.0072), 0, 0.058), 0.0042, 0.003, 6, rot=ry(90), mi=M_STEEL)
        s.cyl((sx * (SLEEVE_W / 2 + 0.0072), 0, 0.026), 0.0042, 0.003, 6, rot=ry(90), mi=M_STEEL)
        # Latch tabs on the back for the backpack's holder.
        s.box((sx * 0.066, d + 0.002, 0.042), (0.012, 0.004, 0.018), mi=M_STEEL)
        s.detail = False
    s.box((0, d + 0.0035, 0.04), (0.11, 0.007, 0.024), mi=M_GUN)  # mounting rail
    # Front: grip ribs on the left, contact pads, the lamp's bezel.
    s.detail = True
    for k in range(3):
        s.box((-0.072 + k * 0.007, fy - 0.0015, 0.036), (0.0035, 0.003, 0.044), mi=M_GUN)
    for k in range(6):
        s.box((-0.018 + k * 0.007, fy - 0.0008, 0.016), (0.0045, 0.0016, 0.004), mi=M_STEEL)
    s.cyl((LAMP[0], fy - 0.0015, LAMP[1]), 0.0075, 0.003, 12, rot=rx(90), mi=M_SBLACK)
    s.finish(root)


def build_glow(root) -> None:
    g = Part("Glow", [GLOW], bevel=None)
    g.box((STRIP_X, FRONT_Y - 0.0013, (STRIP_Z[0] + STRIP_Z[1]) / 2), (STRIP_W, 0.001, STRIP_Z[1] - STRIP_Z[0]))
    for pts, pad in TRACES:
        g.strip(pts, TRACE_W, FRONT_Y - 0.0002, 0.0012)
        if pad:
            x, z = pts[-1]
            g.box((x, FRONT_Y - 0.0002, z), (0.0055, 0.0012, 0.0055))
    fy = -SLEEVE_D / 2 + 0.0012
    g.cyl((LAMP[0], fy - 0.0032, LAMP[1]), 0.0045, 0.0016, 10, rot=rx(90))
    g.finish(root)


# --- main ------------------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    root = C.asset_root(ASSET)
    build_plate(root)
    build_sleeve(root)
    build_glow(root)
    return root


TARGET = (0.0, 0.0, 0.12)
GAME_OFFSET = Vector((7.0, -7.0, 9.5)) * 1.35  # the game camera, about 18 m away
CLOSE = {  # own cameras: location relative to TARGET, lens
    "front": ((0.04, -0.42, 0.03), 50),
}


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    fig = bpy.data.objects["PreviewFigure"]
    for child in fig.children:
        child.hide_render = view not in ("game", "game4")
    if view in ("iso", "hero", "back"):
        C.render(path, view=view, samples=samples, size=size, target=TARGET, zoom=0.028 if view == "iso" else 0.055)
    elif view in ("game", "game4"):
        target = Vector((-0.3, 0.3, 0.3))
        C.render_from(path, target + GAME_OFFSET, target, 50 if view == "game" else 200, samples, size)
    else:
        offset, lens = CLOSE[view]
        C.render_from(path, Vector(TARGET) + Vector(offset), TARGET, lens, samples, size)


FINAL_VIEWS = ["iso", "hero", "back", "front", "game", "game4"]


def main() -> None:
    C.reset(ASSET)
    make_materials(face_image())
    build()
    print("STATS per object", C.tris_per_object())
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(-0.75, 0.75, 0.0))
    if MODE == "final":
        for view in FINAL_VIEWS:
            render_view(OUT / f"render_{view}.png", view, samples=96, size=1024)
        C.contact_sheet([OUT / f"render_{view}.png" for view in FINAL_VIEWS], OUT / "sheet.png", cols=3, tile=512)
        C.save_blend(OUT / "blueprint_fragment_procedural.blend")
    else:
        for view in VIEWS:
            if view != "none":
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, samples=48, size=768)


main()
