"""Tileable ground texture sets for the terrain shader (assets/shaders/terrain.gdshader), Blender 5.2.

Each layer is modeled as a small square of real geometry (a displaced ground grid plus stones, roots, ...) with
procedural Cycles materials, surrounded by eight instances of itself so it tiles seamlessly (also its AO and its
stones reaching over the edge). An orthographic camera looks straight down on the middle tile and renders the
material channels as emission passes (32-bit EXR in tmp/terrain/), which are packed into two textures per layer:

    assets/terrain/<layer>_albedo.png   RGB base color (sRGB), A height (0 = lowest, 1 = highest point)
    assets/terrain/<layer>_nra.png      RG normal X/Y (0.5 = flat; +X right, +Y up in the image), B roughness, A AO

The rock layers are walls: the image's up is the world's up (strata run horizontally). Everything else is ground
seen from above (the image's up is north, -Z in Godot). Procedural noise is periodic over the tile: the shaders
use 4D noise on a torus (x and y each mapped to a circle with the tile as its circumference), the numpy maps are
filtered white noise (periodic through the FFT) and wrapped Voronoi cells.

Run: tools/blender.sh assets/terrain/source/terrain_textures.py [layer ...] [preview]
     (no layer: all of them; "preview" also renders a lit 2x2 tile check to tmp/terrain/<layer>_lit.png)
"""

import math
import pathlib
import sys

import bmesh
import bpy
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "blender"))
import bake as B  # noqa: E402
import common as C  # noqa: E402

OUT = ROOT / "assets" / "terrain"
TMP = ROOT / "tmp" / "terrain"
SIZE = 1024  # texture size; the numpy maps have the same size
MESH = 512  # grid squares per side of the displaced ground
SAMPLES = {"albedo": 16, "rough": 16, "normal": 16, "height": 16, "ao": 256}

# Sockets of each material, for routing the passes: name -> {color, rough, normal, height, ao_distance}.
SOCKETS: dict = {}


# --- numpy maps (periodic over the tile) -----------------------------------------------------------


def blobs(rng: np.random.Generator, tile: float, size_m: float, octaves: int = 1, gain: float = 0.5, n: int = SIZE):
    """Smooth periodic noise (mean 0, std 1) with features about `size_m` across, plus finer octaves."""
    f = np.fft.fftfreq(n, d=tile / n)
    f2 = f[None, :] ** 2 + f[:, None] ** 2
    total = np.zeros((n, n))
    amp = 1.0
    for octave in range(octaves):
        size = size_m / 2**octave
        layer = np.fft.ifft2(np.fft.fft2(rng.standard_normal((n, n))) * np.exp(-f2 * size * size * 2.0)).real
        total += layer / (layer.std() + 1e-12) * amp
        amp *= gain
    return total / total.std()


def voronoi(rng: np.random.Generator, count: int, stretch=(1.0, 1.0), warp=None, n: int = SIZE):
    """Wrapped Voronoi cells of `count` random points: (distance to the nearest, to the second nearest, cell index),
    distances in tile units. `stretch` scales x, y distances (cells get longer along the smaller one); `warp`
    (x, y offset maps in tile units) bends the cell borders."""
    points = rng.random((count, 2))
    ys, xs = (np.mgrid[0:n, 0:n] + 0.5) / n
    if warp is not None:
        xs = (xs + warp[0]) % 1.0
        ys = (ys + warp[1]) % 1.0
    f1 = np.full((n, n), np.inf)
    f2 = np.full((n, n), np.inf)
    cell = np.zeros((n, n), dtype=np.int32)
    for i, (px, py) in enumerate(points):
        dx = np.abs(xs - px)
        dy = np.abs(ys - py)
        d = np.hypot(np.minimum(dx, 1 - dx) * stretch[0], np.minimum(dy, 1 - dy) * stretch[1])
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        cell = np.where(closer, i, cell)
        f1 = np.where(closer, d, f1)
    return f1, f2, cell


def smoothstep(a: float, b: float, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def coords(tile: float, n: int = SIZE):
    """Meters of each pixel center: (x, y) arrays, row 0 at y = 0 (Blender images are bottom-up)."""
    ys, xs = (np.mgrid[0:n, 0:n] + 0.5) / n * tile
    return xs, ys


def sample(height: np.ndarray, tile: float, x: float, y: float) -> float:
    n = height.shape[0]
    return float(height[int(y / tile * n) % n, int(x / tile * n) % n])


def srgb(r: float, g: float, b: float) -> tuple[float, float, float]:
    """Linear color from sRGB values (Blender shader colors are linear)."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))


def to_srgb(linear: np.ndarray) -> np.ndarray:
    c = np.clip(linear, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def float_image(name: str, arr: np.ndarray) -> bpy.types.Image:
    """Non-color float image of a scalar map (row 0 at the bottom)."""
    img = bpy.data.images.new(name, arr.shape[1], arr.shape[0], alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    rgba = np.ones((*arr.shape, 4), dtype=np.float32)
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = arr
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


# --- geometry ------------------------------------------------------------------------------------------


def _mesh_object(name: str, verts: np.ndarray, faces: np.ndarray, smooth: bool) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    corners = faces.shape[1]
    mesh.vertices.add(len(verts))
    mesh.vertices.foreach_set("co", verts.astype(np.float32).ravel())
    mesh.loops.add(faces.size)
    mesh.loops.foreach_set("vertex_index", faces.astype(np.int32).ravel())
    mesh.polygons.add(len(faces))
    mesh.polygons.foreach_set("loop_start", (np.arange(len(faces)) * corners).astype(np.int32))
    mesh.update(calc_edges=True)
    mesh.validate()
    if smooth:
        mesh.shade_smooth()
    else:
        mesh.shade_flat()
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections["Tile"].objects.link(obj)
    return obj


def ground_grid(height: np.ndarray, tile: float, mat: bpy.types.Material) -> bpy.types.Object:
    """The tile's ground: a grid displaced by `height` (meters, any size; resampled to MESH squares per side)."""
    step = height.shape[0] // MESH
    h = np.pad(height[::step, ::step], ((0, 1), (0, 1)), mode="wrap")
    m = MESH + 1
    ys, xs = np.mgrid[0:m, 0:m] / MESH * tile
    verts = np.stack([xs.ravel(), ys.ravel(), h.ravel()], axis=1)
    i = np.arange(MESH)
    a = (i[:, None] * m + i[None, :]).ravel()
    faces = np.stack([a, a + 1, a + m + 1, a + m], axis=1)
    obj = _mesh_object("Ground", verts, faces, smooth=True)
    obj.data.materials.append(mat)
    return obj


def _template(subdivisions: int):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
    verts = np.array([v.co[:] for v in bm.verts])
    faces = np.array([[v.index for v in f.verts] for f in bm.faces])
    bm.free()
    return verts, faces


def stones(
    rng: np.random.Generator,
    name: str,
    tile: float,
    ground: np.ndarray,
    count: int,
    radius: tuple[float, float],
    mat: bpy.types.Material,
    flat: tuple[float, float] = (0.35, 0.6),
    sink: float = 0.35,
    subdivisions: int = 1,
    cuts: int = 4,
    lumps: float = 0.12,
    spacing: float = 0.9,
    smooth: bool = False,
    where=None,
    others: list | None = None,
) -> bpy.types.Object:
    """`count` stones (log-uniform radius) lying on `ground`, half buried, kept apart from each other and from
    `others` (x, y, r, filled in), chipped by random planar cuts. `where(x, y)` -> 0..1 thins them out."""
    base, tris = _template(subdivisions)
    dirs = base / np.linalg.norm(base, axis=1, keepdims=True)
    placed = others if others is not None else []
    all_verts, all_faces, rand = [], [], []
    offset = 0
    tries = 0
    made = 0
    while made < count and tries < count * 30:
        tries += 1
        r = math.exp(rng.uniform(math.log(radius[0]), math.log(radius[1])))
        x, y = rng.uniform(0, tile, 2)
        if where is not None and rng.random() > where(x, y):
            continue
        if placed:
            p = np.array(placed)
            dx = np.abs(p[:, 0] - x)
            dy = np.abs(p[:, 1] - y)
            d = np.hypot(np.minimum(dx, tile - dx), np.minimum(dy, tile - dy))
            if np.any(d < (p[:, 2] + r) * spacing):
                continue
        placed.append((x, y, r))
        made += 1
        v = dirs.copy()
        bulge = np.ones(len(v))
        for _ in range(3):
            w = rng.normal(size=3) * rng.uniform(1.5, 3.5)
            bulge += lumps * np.cos(v @ w + rng.uniform(0, math.tau))
        v *= bulge[:, None]
        for _ in range(cuts):
            normal = rng.normal(size=3)
            normal /= np.linalg.norm(normal)
            off = rng.uniform(0.55, 0.85)
            d = v @ normal
            over = d > off
            v[over] -= normal * (d[over] - off)[:, None]
        squash = rng.uniform(*flat)
        v *= np.array([1.0, rng.uniform(0.6, 1.0), squash]) * r
        yaw = rng.uniform(0, math.tau)
        tilt = rng.normal(scale=0.15, size=2)
        rot = _rot_z(yaw) @ _rot_x(tilt[0]) @ _rot_y(tilt[1])
        v = v @ rot.T
        v += np.array([x, y, sample(ground, tile, x, y) - sink * squash * r])
        all_verts.append(v)
        all_faces.append(tris + offset)
        rand.append(np.full(len(v), rng.random()))
        offset += len(v)
    obj = _mesh_object(name, np.concatenate(all_verts), np.concatenate(all_faces), smooth)
    attr = obj.data.attributes.new("rand", "FLOAT", "POINT")
    attr.data.foreach_set("value", np.concatenate(rand).astype(np.float32))
    obj.data.materials.append(mat)
    return obj


def roots(
    rng: np.random.Generator,
    name: str,
    tile: float,
    ground: np.ndarray,
    count: int,
    length: tuple[float, float],
    radius: tuple[float, float],
    mat: bpy.types.Material,
    bury: float = 0.45,
) -> bpy.types.Object:
    """Tapering tubes wandering over `ground`, partly buried (roots, tendrils)."""
    sides = 8
    all_verts, all_faces, rand = [], [], []
    offset = 0
    ring = np.linspace(0, math.tau, sides, endpoint=False)
    for _ in range(count):
        steps = int(rng.uniform(*length) / 0.02)
        r0 = rng.uniform(*radius)
        x, y = rng.uniform(0, tile, 2)
        heading = rng.uniform(0, math.tau)
        turn = 0.0
        path = []
        for _ in range(steps):
            turn = turn * 0.95 + rng.normal(scale=0.004)
            heading += turn
            x += math.cos(heading) * 0.02
            y += math.sin(heading) * 0.02
            path.append((x, y))
        verts = []
        for i, (px, py) in enumerate(path):
            t = i / max(steps - 1, 1)
            r = r0 * (1.0 - 0.85 * t) * (0.85 + 0.3 * math.sin(i * 0.37))
            j = min(i + 1, steps - 1)
            k = max(i - 1, 0)
            tx, ty = path[j][0] - path[k][0], path[j][1] - path[k][1]
            norm = math.hypot(tx, ty) or 1.0
            nx, ny = -ty / norm, tx / norm
            z = sample(ground, tile, px, py) + r * (1.0 - 2.0 * bury)
            for a in ring:
                verts.append((px + nx * math.cos(a) * r, py + ny * math.cos(a) * r, z + math.sin(a) * r))
        quads = []
        for i in range(steps - 1):
            for s in range(sides):
                a = i * sides + s
                b = i * sides + (s + 1) % sides
                quads.append((a, b, b + sides, a + sides))
        all_verts.append(np.array(verts))
        all_faces.append(np.array(quads) + offset)
        rand.append(np.full(len(verts), rng.random()))
        offset += len(verts)
    obj = _mesh_object(name, np.concatenate(all_verts), np.concatenate(all_faces), smooth=True)
    attr = obj.data.attributes.new("rand", "FLOAT", "POINT")
    attr.data.foreach_set("value", np.concatenate(rand).astype(np.float32))
    obj.data.materials.append(mat)
    return obj


def _rot_x(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def _rot_y(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def _rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


# --- shader nodes --------------------------------------------------------------------------------------


class Nodes:
    """Node helpers for one material; numbers passed as inputs are set, sockets are linked."""

    def __init__(self, name: str, tile: float):
        self.mat = bpy.data.materials.new(name)
        self.nt = self.mat.node_tree
        self.nt.nodes.clear()
        self.tile = tile
        obj = self.node("ShaderNodeTexCoord").outputs["Object"]
        xyz = self.node("ShaderNodeSeparateXYZ", Vector=obj)
        k = math.tau / tile
        r = tile / math.tau
        u = self.math("MULTIPLY", xyz.outputs["X"], k)
        v = self.math("MULTIPLY", xyz.outputs["Y"], k)
        ring = [self.math("MULTIPLY", self.math(op, a), r) for op, a in (("COSINE", u), ("SINE", u), ("COSINE", v))]
        self.torus = self.node("ShaderNodeCombineXYZ", X=ring[0], Y=ring[1], Z=ring[2]).outputs["Vector"]
        self.w = self.math("MULTIPLY", self.math("SINE", v), r)
        self.uv = self.node("ShaderNodeVectorMath", operation="SCALE", Vector=obj, Scale=1.0 / tile).outputs["Vector"]

    def node(self, kind: str, operation: str | None = None, props: dict | None = None, **inputs) -> bpy.types.Node:
        node = self.nt.nodes.new(kind)
        if operation:
            node.operation = operation
        for key, val in (props or {}).items():
            setattr(node, key, val)
        for key, val in inputs.items():
            self.set(node.inputs[key], val)
        return node

    def set(self, sock: bpy.types.NodeSocket, val) -> None:
        if isinstance(val, bpy.types.NodeSocket):
            self.nt.links.new(val, sock)
        elif isinstance(val, tuple) and len(val) == 3:
            sock.default_value = (*val, 1.0) if len(sock.default_value) == 4 else val
        else:
            sock.default_value = val

    def math(self, op: str, a, b=None, clamp: bool = False, c=None) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeMath")
        node.operation = op
        node.use_clamp = clamp
        for sock, val in zip(node.inputs, (a, b, c)):
            if val is not None:
                self.set(sock, val)
        return node.outputs[0]

    def noise(self, scale: float, detail: float = 4.0, roughness: float = 0.55, distortion: float = 0.0):
        """Periodic 4D noise, `scale` features per meter (about), standardized: mean 0, std about 1 (the node's
        Fac has std ~0.09 around 0.5)."""
        tex = self.node(
            "ShaderNodeTexNoise", props={"noise_dimensions": "4D"}, Vector=self.torus, W=self.w, Scale=scale, Detail=detail
        )
        tex.inputs["Roughness"].default_value = roughness
        tex.inputs["Distortion"].default_value = distortion
        return self.math("MULTIPLY", self.math("SUBTRACT", tex.outputs["Fac"], 0.5), 11.0)

    def unit(self, value, spread: float = 0.25) -> bpy.types.NodeSocket:
        """0..1 factor from a standardized value: 0.5 + spread * value, clamped."""
        return self.math("MULTIPLY_ADD", value, spread, clamp=True, c=0.5)

    def image(self, img: bpy.types.Image) -> bpy.types.NodeSocket:
        tex = self.node("ShaderNodeTexImage", Vector=self.uv)
        tex.image = img
        tex.interpolation = "Cubic"
        tex.extension = "REPEAT"
        return tex.outputs["Color"]

    def scalar(self, img: bpy.types.Image) -> bpy.types.NodeSocket:
        sep = self.node("ShaderNodeSeparateColor", Color=self.image(img))
        return sep.outputs[0]

    def attribute(self, name: str) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeAttribute")
        node.attribute_name = name
        return node.outputs["Fac"]

    def ramp(self, fac, a: float, b: float) -> bpy.types.NodeSocket:
        """0 below `a`, 1 above `b`, smooth in between."""
        node = self.node("ShaderNodeMapRange", props={"interpolation_type": "SMOOTHSTEP"}, Value=fac)
        node.inputs["From Min"].default_value = a
        node.inputs["From Max"].default_value = b
        return node.outputs["Result"]

    def mix(self, fac, a, b) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        self.set(node.inputs["Factor"], fac)
        self.set(node.inputs[6], a)
        self.set(node.inputs[7], b)
        return node.outputs[2]

    def lerp(self, fac, a, b) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeMix")
        node.data_type = "FLOAT"
        self.set(node.inputs["Factor"], fac)
        self.set(node.inputs[2], a)
        self.set(node.inputs[3], b)
        return node.outputs[0]

    def palette(self, fac, colors: list) -> bpy.types.NodeSocket:
        """Color ramp through `colors` (sRGB tuples) evenly spaced (constant steps)."""
        node = self.node("ShaderNodeValToRGB", Fac=fac)
        ramp = node.color_ramp
        ramp.interpolation = "CONSTANT"
        while len(ramp.elements) < len(colors):
            ramp.elements.new(0.5)
        for i, c in enumerate(colors):
            ramp.elements[i].position = i / len(colors)
            ramp.elements[i].color = (*srgb(*c), 1.0)
        return node.outputs["Color"]

    def finish(self, color, rough, height, bump: float = 1.0, ao_distance: float = 0.1) -> bpy.types.Material:
        """Wire up the lit material and remember the sockets for the passes. `height` is fine detail in meters
        (on top of the geometry): it drives the bump and is added to the height pass."""
        if not isinstance(rough, bpy.types.NodeSocket):
            value = self.nt.nodes.new("ShaderNodeValue")
            value.outputs[0].default_value = rough
            rough = value.outputs[0]
        geo = self.nt.nodes.new("ShaderNodeNewGeometry")
        bump_node = self.node("ShaderNodeBump", Strength=bump, Distance=1.0, Height=height)
        normal = bump_node.outputs["Normal"]
        bsdf = self.node("ShaderNodeBsdfPrincipled", **{"Base Color": color, "Roughness": rough, "Normal": normal})
        out = self.node("ShaderNodeOutputMaterial", Surface=bsdf.outputs["BSDF"])
        z = self.node("ShaderNodeSeparateXYZ", Vector=geo.outputs["Position"]).outputs["Z"]
        ao = self.node("ShaderNodeAmbientOcclusion", Distance=ao_distance, Normal=normal)
        ao.samples = 16
        enc = self.node("ShaderNodeVectorMath", operation="MULTIPLY_ADD", Vector=normal)
        enc.inputs[1].default_value = (0.5, 0.5, 0.5)
        enc.inputs[2].default_value = (0.5, 0.5, 0.5)
        SOCKETS[self.mat.name] = {
            "bsdf": bsdf.outputs["BSDF"],
            "out": out,
            "albedo": color,
            "rough": rough,
            "normal": enc.outputs["Vector"],
            "height": self.math("ADD", z, height),
            "ao": ao.outputs["AO"],
            "emit": self.nt.nodes.new("ShaderNodeEmission"),
        }
        return self.mat


def route(kind: str) -> None:
    """Every material shows `kind` as unlit emission ("lit": the normal BSDF)."""
    for sockets in SOCKETS.values():
        mat_out = sockets["out"]
        nt = mat_out.id_data
        surface = mat_out.inputs["Surface"]
        for link in list(surface.links):
            nt.links.remove(link)
        if kind == "lit":
            nt.links.new(sockets["bsdf"], surface)
            continue
        emit = sockets["emit"]
        for link in list(emit.inputs["Color"].links):
            nt.links.remove(link)
        nt.links.new(sockets[kind], emit.inputs["Color"])
        nt.links.new(emit.outputs["Emission"], surface)


# --- layers ----------------------------------------------------------------------------------------------
# Conventions: n.noise() is standardized (mean 0, std about 1), so thresholds are in standard deviations and
# `noise * k` as fine height is k meters std; n.unit() turns it into a 0..1 factor. Rare spots (specks) come from
# numpy (thresholded far out in the tail, the shader noise's density would vary over the tile).


def specks(rng: np.random.Generator, tile: float, size_m: float, share: float) -> np.ndarray:
    """Soft spots about `size_m` across covering `share` of the tile (0..1 map)."""
    field = blobs(rng, tile, size_m)
    cut = np.quantile(field, 1.0 - share)
    return smoothstep(cut, cut + 0.6, field)


def dust_ground(rng: np.random.Generator) -> float:
    """Dust flats: dry sandy regolith with patches of cracked crust, faint wind ripples and sparse pebbles."""
    tile = 6.0
    xs, ys = coords(tile)
    height = 0.03 * blobs(rng, tile, 1.4, 3)
    warp = blobs(rng, tile, 0.8)
    ripple_mask = smoothstep(-0.2, 0.8, blobs(rng, tile, 1.2))
    ripples = np.sin(math.tau * (9 * xs + 4 * ys) / tile + 1.2 * warp) * 0.004 * ripple_mask
    crust = smoothstep(0.3, 0.9, blobs(rng, tile, 1.2) + 0.35 * blobs(rng, tile, 0.25))
    bend = (0.017 * blobs(rng, tile, 0.5, 2), 0.017 * blobs(rng, tile, 0.5, 2))
    f1, f2, cell = voronoi(rng, 110, warp=bend)
    width = 0.0017 + 0.0013 * (blobs(rng, tile, 0.3) * 0.5 + 0.5)
    edge = f2 - f1
    cracks = (1.0 - smoothstep(0.0, width, edge)) * crust
    # Crust plates: a few mm proud of the sand, their edges curling up a little at the cracks.
    plates = crust * (0.004 + 0.003 * smoothstep(0.03, width, edge) * (1.0 - smoothstep(0.0, 0.013, edge - width)))
    plate_tone = np.random.default_rng(int(rng.integers(1 << 30))).random(cell.max() + 1)[cell]
    height = height + plates - cracks * 0.01
    fine = ripples * (1.0 - crust)
    tone = blobs(rng, tile, 0.35, 3, 0.6)
    dark = specks(rng, tile, 0.008, 0.03)
    light = specks(rng, tile, 0.006, 0.015)

    n = Nodes("DustSand", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    crust_s = n.scalar(float_image("crust", crust))
    crack_s = n.scalar(float_image("cracks", cracks))
    plate_s = n.scalar(float_image("plates", plate_tone))
    dark_s = n.scalar(float_image("dark", dark))
    light_s = n.scalar(float_image("light", light))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(90.0, 3.0, 0.7)
    sand = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.33, 0.295, 0.25), srgb(0.38, 0.335, 0.28))
    sand = n.mix(n.unit(grain, 0.12), srgb(0.31, 0.275, 0.235), sand)
    crust_color = n.mix(plate_s, srgb(0.355, 0.315, 0.265), srgb(0.385, 0.34, 0.285))
    color = n.mix(n.math("MULTIPLY", crust_s, 0.7), sand, crust_color)
    color = n.mix(n.math("MULTIPLY", dark_s, 0.7), color, srgb(0.22, 0.20, 0.18))
    color = n.mix(n.math("MULTIPLY", light_s, 0.6), color, srgb(0.55, 0.50, 0.44))
    color = n.mix(n.math("MULTIPLY", crack_s, 0.9), color, srgb(0.18, 0.16, 0.14))
    rough = n.lerp(crust_s, 0.97, 0.88)
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, 0.0006))
    sand_mat = n.finish(color, rough, detail, ao_distance=0.15)

    s = Nodes("DustPebble", tile)
    base = s.palette(s.attribute("rand"), [(0.38, 0.34, 0.30), (0.45, 0.38, 0.31), (0.33, 0.30, 0.27), (0.50, 0.45, 0.38), (0.41, 0.32, 0.25)])
    speck = s.noise(60.0, 4.0, 0.6)
    color = s.mix(s.ramp(speck, 0.5, 2.0), base, srgb(0.25, 0.22, 0.2))
    dust = s.ramp(s.noise(14.0, 2.0), 0.3, 1.2)
    color = s.mix(s.math("MULTIPLY", dust, 0.7), color, srgb(0.37, 0.33, 0.28))
    pebble_mat = s.finish(color, s.lerp(dust, 0.75, 0.95), s.math("MULTIPLY", speck, 0.0005), ao_distance=0.1)

    ground_grid(height, tile, sand_mat)
    placed: list = []
    kw = dict(flat=(0.45, 0.8), sink=0.25, cuts=5)
    stones(rng, "Rocks", tile, height, 10, (0.09, 0.15), pebble_mat, spacing=1.6, others=placed, **kw)
    stones(rng, "Stones", tile, height, 65, (0.035, 0.08), pebble_mat, spacing=1.2, others=placed, **kw)
    stones(rng, "Pebbles", tile, height, 580, (0.008, 0.03), pebble_mat, others=placed, **kw)
    return tile


def dust_scree(rng: np.random.Generator) -> float:
    """Dust flats scree: angular stones of all sizes on dark sand (cliff feet, transitions)."""
    tile = 4.0
    height = 0.04 * blobs(rng, tile, 1.0, 2)
    tone = blobs(rng, tile, 0.4, 2)

    n = Nodes("ScreeSand", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    grain = n.noise(90.0, 3.0, 0.7)
    color = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.31, 0.275, 0.235), srgb(0.36, 0.32, 0.27))
    color = n.mix(n.unit(grain, 0.12), srgb(0.29, 0.26, 0.22), color)
    sand_mat = n.finish(color, 0.96, n.math("MULTIPLY", grain, 0.0006), ao_distance=0.1)

    s = Nodes("ScreeStone", tile)
    base = s.palette(s.attribute("rand"), [(0.36, 0.32, 0.29), (0.44, 0.38, 0.32), (0.31, 0.28, 0.26), (0.50, 0.44, 0.37), (0.40, 0.31, 0.25), (0.35, 0.34, 0.33)])
    speck = s.noise(50.0, 4.0, 0.6)
    color = s.mix(s.math("MULTIPLY", s.ramp(speck, 0.8, 2.2), 0.7), base, srgb(0.2, 0.18, 0.16))
    dust = s.ramp(s.noise(10.0, 2.0), 0.5, 1.5)
    color = s.mix(s.math("MULTIPLY", dust, 0.6), color, srgb(0.36, 0.32, 0.27))
    stone_mat = s.finish(color, s.lerp(dust, 0.78, 0.95), s.math("MULTIPLY", speck, 0.0006), ao_distance=0.12)

    ground_grid(height, tile, sand_mat)
    placed: list = []
    kw = dict(flat=(0.5, 0.85), sink=0.2, cuts=6)
    stones(rng, "Rocks", tile, height, 25, (0.12, 0.2), stone_mat, spacing=1.0, others=placed, **kw)
    stones(rng, "Stones", tile, height, 390, (0.04, 0.1), stone_mat, spacing=0.85, others=placed, **kw)
    stones(rng, "Gravel", tile, height, 2500, (0.012, 0.04), stone_mat, spacing=0.8, others=placed, **kw)
    return tile


def dust_rock(rng: np.random.Generator) -> float:
    """Dust flats cliff (a wall, image up = world up): sandstone strata of different hardness, the soft ones
    weathered back, finely laminated and split by a few vertical joints."""
    tile = 8.0
    xs, ys = coords(tile)
    # Strata: bands of random thickness filling the tile's height, each recessed by its softness.
    bounds = [0.0]
    while bounds[-1] < tile - 0.3:
        bounds.append(bounds[-1] + rng.uniform(0.12, 0.7))
    bounds[-1] = tile
    bands = len(bounds) - 1
    recess = rng.uniform(0.0, 0.1, bands) * (rng.random(bands) < 0.6)
    shade = rng.random(bands)
    profile_y = np.linspace(0, tile, 4096, endpoint=False)
    band_of = np.searchsorted(bounds, profile_y, side="right") - 1
    f = np.fft.fftfreq(4096, d=tile / 4096)
    profile = np.fft.ifft(np.fft.fft(-recess[band_of]) * np.exp(-((f * 0.05) ** 2) * 2)).real
    warped = (ys + 0.12 * blobs(rng, tile, 3.0) + 0.02 * blobs(rng, tile, 0.4)) % tile
    index = (warped / tile * 4096).astype(int) % 4096
    strata = profile[index]
    band_shade = shade[band_of[index]]
    bend = (0.01 * blobs(rng, tile, 0.6, 2), 0.004 * blobs(rng, tile, 0.6, 2))
    f1, f2, _ = voronoi(rng, 12, stretch=(1.0, 0.3), warp=bend)
    width = 0.001 + 0.0015 * (blobs(rng, tile, 1.0) * 0.5 + 0.5).clip(0, 1)
    joints = 1.0 - smoothstep(0.0, width, f2 - f1)
    lamination = np.sin(math.tau * 260 * warped / tile) * 0.002
    bulge = 0.15 * blobs(rng, tile, 3.0) + 0.04 * blobs(rng, tile, 0.8, 2)
    erosion = 0.02 * blobs(rng, tile, 0.25, 3)
    height = bulge + strata + erosion - joints * 0.06
    fine = lamination - joints * 0.005
    dark = smoothstep(0.02, 0.09, -strata)

    n = Nodes("Sandstone", tile)
    shade_s = n.scalar(float_image("shade", band_shade))
    joint_s = n.scalar(float_image("joints", joints))
    dark_s = n.scalar(float_image("recess", dark))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(40.0, 5.0, 0.65)
    mottle = n.noise(3.0, 3.0, 0.6)
    color = n.palette(n.math("ADD", shade_s, n.math("MULTIPLY", mottle, 0.04)), [(0.30, 0.25, 0.20), (0.36, 0.29, 0.22), (0.27, 0.24, 0.21), (0.40, 0.32, 0.24), (0.32, 0.26, 0.21)])
    color = n.mix(n.math("MULTIPLY", dark_s, 0.4), color, srgb(0.21, 0.18, 0.15))
    color = n.mix(n.math("MULTIPLY", n.ramp(grain, 0.5, 2.0), 0.4), color, srgb(0.22, 0.19, 0.16))
    color = n.mix(n.math("MULTIPLY", joint_s, 0.7), color, srgb(0.15, 0.13, 0.11))
    rough = n.lerp(n.unit(grain), 0.85, 0.97)
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, 0.0015))
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


def overgrowth_ground(rng: np.random.Generator) -> float:
    """Overgrowth: dark damp soil under mats of olive moss, roots crawling over it, a few stones and pale fungus
    buds."""
    tile = 6.0
    height = 0.03 * blobs(rng, tile, 1.2, 3)
    moss = smoothstep(-0.15, 0.35, blobs(rng, tile, 0.9, 2) + 0.35 * blobs(rng, tile, 0.2))
    lumps = 0.01 * blobs(rng, tile, 0.06, 2)
    height = height + moss * (0.015 + lumps)
    tone = blobs(rng, tile, 0.5, 2)

    n = Nodes("Soil", tile)
    moss_s = n.scalar(float_image("moss", moss))
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    fuzz = n.noise(120.0, 2.0, 0.8)
    grain = n.noise(60.0, 4.0, 0.6)
    soil = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.17, 0.16, 0.135), srgb(0.22, 0.205, 0.17))
    soil = n.mix(n.unit(grain, 0.12), srgb(0.15, 0.14, 0.12), soil)
    moss_color = n.mix(n.ramp(tone_s, 0.3, 0.7), srgb(0.17, 0.19, 0.105), srgb(0.25, 0.27, 0.14))
    moss_color = n.mix(n.unit(fuzz, 0.2), srgb(0.12, 0.14, 0.08), moss_color)
    color = n.mix(moss_s, soil, moss_color)
    rough = n.lerp(moss_s, 0.82, 0.96)
    detail = n.lerp(moss_s, n.math("MULTIPLY", grain, 0.0005), n.math("MULTIPLY", fuzz, 0.0012))
    soil_mat = n.finish(color, rough, detail, ao_distance=0.1)

    r = Nodes("Root", tile)
    bark = r.noise(80.0, 3.0, 0.6)
    color = r.mix(r.attribute("rand"), srgb(0.19, 0.15, 0.12), srgb(0.25, 0.20, 0.155))
    color = r.mix(r.math("MULTIPLY", r.ramp(bark, 0.3, 1.5), 0.5), color, srgb(0.13, 0.10, 0.08))
    root_mat = r.finish(color, r.lerp(r.unit(bark), 0.45, 0.7), r.math("MULTIPLY", bark, 0.0004), ao_distance=0.08)

    s = Nodes("SoilStone", tile)
    lichen = s.ramp(s.noise(8.0, 3.0, 0.6), 0.3, 0.9)
    base = s.palette(s.attribute("rand"), [(0.25, 0.25, 0.24), (0.30, 0.29, 0.27), (0.22, 0.22, 0.21), (0.34, 0.33, 0.30)])
    color = s.mix(lichen, base, srgb(0.25, 0.28, 0.14))
    stone_mat = s.finish(color, s.lerp(lichen, 0.55, 0.9), s.math("MULTIPLY", s.noise(50.0), 0.0005), ao_distance=0.08)

    b = Nodes("Bud", tile)
    bud_color = b.mix(b.attribute("rand"), srgb(0.48, 0.46, 0.38), srgb(0.60, 0.56, 0.45))
    bud_mat = b.finish(bud_color, 0.5, b.math("MULTIPLY", b.noise(200.0), 0.0002), ao_distance=0.05)

    ground_grid(height, tile, soil_mat)
    roots(rng, "Roots", tile, height, 8, (1.2, 3.0), (0.015, 0.03), root_mat, bury=0.5)
    placed: list = []
    kw = dict(subdivisions=2, cuts=2, smooth=True, flat=(0.5, 0.8))
    stones(rng, "Stones", tile, height, 50, (0.03, 0.11), stone_mat, sink=0.35, others=placed, spacing=1.5, **kw)
    stones(rng, "Buds", tile, height, 160, (0.004, 0.009), bud_mat, flat=(0.7, 1.0), subdivisions=2, cuts=0, lumps=0.05, smooth=True, sink=0.2, others=placed, where=lambda x, y: 1.0 if sample(moss, tile, x, y) > 0.5 else 0.05)
    return tile


def overgrowth_scree(rng: np.random.Generator) -> float:
    """Overgrowth scree: rounded dark stones, damp, with soil and moss in the gaps."""
    tile = 4.0
    height = 0.03 * blobs(rng, tile, 1.0, 2)
    moss = smoothstep(0.0, 0.5, blobs(rng, tile, 0.6, 2))
    tone = blobs(rng, tile, 0.4, 2)

    n = Nodes("GravelSoil", tile)
    moss_s = n.scalar(float_image("moss", moss))
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    fuzz = n.noise(120.0, 2.0, 0.8)
    soil = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.16, 0.15, 0.13), srgb(0.21, 0.195, 0.165))
    moss_color = n.mix(n.unit(fuzz, 0.2), srgb(0.13, 0.15, 0.08), srgb(0.22, 0.24, 0.12))
    color = n.mix(moss_s, soil, moss_color)
    soil_mat = n.finish(color, n.lerp(moss_s, 0.8, 0.95), n.math("MULTIPLY", fuzz, 0.0008), ao_distance=0.1)

    s = Nodes("WetStone", tile)
    base = s.palette(s.attribute("rand"), [(0.24, 0.24, 0.23), (0.30, 0.29, 0.27), (0.21, 0.21, 0.21), (0.35, 0.34, 0.31), (0.27, 0.26, 0.22)])
    speck = s.noise(40.0, 4.0, 0.6)
    lichen = s.ramp(s.noise(6.0, 3.0, 0.6), 0.6, 1.2)
    color = s.mix(s.math("MULTIPLY", s.ramp(speck, 0.8, 2.2), 0.6), base, srgb(0.15, 0.15, 0.14))
    color = s.mix(lichen, color, srgb(0.24, 0.27, 0.14))
    rough = s.lerp(lichen, s.lerp(s.unit(speck), 0.58, 0.75), 0.9)
    stone_mat = s.finish(color, rough, s.math("MULTIPLY", speck, 0.0005), ao_distance=0.12)

    ground_grid(height, tile, soil_mat)
    placed: list = []
    kw = dict(subdivisions=2, cuts=2, lumps=0.08, smooth=True, flat=(0.5, 0.8), sink=0.2)
    stones(rng, "Rocks", tile, height, 18, (0.12, 0.2), stone_mat, spacing=1.0, others=placed, **kw)
    stones(rng, "Stones", tile, height, 350, (0.04, 0.1), stone_mat, spacing=0.88, others=placed, **kw)
    stones(rng, "Gravel", tile, height, 1600, (0.012, 0.04), stone_mat, spacing=0.85, others=placed, **kw)
    return tile


def overgrowth_rock(rng: np.random.Generator) -> float:
    """Overgrowth cliff (a wall, image up = world up): dark massive rock broken into big blocks with rounded
    edges, moss and lichen in the joints and on the ledges."""
    tile = 8.0
    xs, ys = coords(tile)
    bend = (0.015 * blobs(rng, tile, 1.0, 2), 0.015 * blobs(rng, tile, 1.0, 2))
    f1, f2, cell = voronoi(rng, 12, stretch=(1.0, 0.8), warp=bend)
    edge = f2 - f1
    count = cell.max() + 1
    tilt = rng.normal(scale=0.04, size=(count, 2))
    lift = rng.uniform(-0.06, 0.06, count)
    blocks = (tilt[cell, 0] * np.sin(math.tau * xs / tile) + tilt[cell, 1] * np.sin(math.tau * ys / tile)) * tile * 0.3 + lift[cell]
    rounded = smoothstep(0.0, 0.03, edge)
    height = blocks * rounded - (1.0 - rounded) * 0.05 + 0.15 * blobs(rng, tile, 3.0) + 0.015 * blobs(rng, tile, 0.3, 3)
    ledge = -np.gradient(height, axis=0) * SIZE / tile  # facing up (+Y) on the wall
    moss = np.clip(smoothstep(0.2, 0.9, 1.0 - rounded) + smoothstep(0.1, 0.5, ledge) * smoothstep(-0.3, 0.5, blobs(rng, tile, 0.5)), 0, 1)
    joints = 1.0 - smoothstep(0.0, 0.004, edge)
    tone = blobs(rng, tile, 1.0, 2)
    spots = specks(rng, tile, 0.03, 0.06)

    n = Nodes("DarkRock", tile)
    moss_s = n.scalar(float_image("moss", moss))
    joint_s = n.scalar(float_image("joints", joints))
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    spot_s = n.scalar(float_image("spots", spots))
    grain = n.noise(35.0, 5.0, 0.65)
    fuzz = n.noise(110.0, 2.0, 0.8)
    rock = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.20, 0.20, 0.19), srgb(0.29, 0.28, 0.26))
    rock = n.mix(n.unit(grain, 0.15), srgb(0.17, 0.17, 0.16), rock)
    rock = n.mix(n.math("MULTIPLY", spot_s, 0.6), rock, srgb(0.40, 0.40, 0.33))
    color = n.mix(moss_s, rock, n.mix(n.unit(fuzz, 0.2), srgb(0.14, 0.16, 0.085), srgb(0.24, 0.26, 0.13)))
    color = n.mix(n.math("MULTIPLY", joint_s, 0.7), color, srgb(0.08, 0.08, 0.07))
    rough = n.lerp(moss_s, n.lerp(n.unit(grain), 0.7, 0.9), 0.95)
    detail = n.math("ADD", n.math("MULTIPLY", grain, 0.0015), n.math("MULTIPLY", n.math("MULTIPLY", moss_s, fuzz), 0.0015))
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


LAYERS = {
    "dust_ground": dust_ground,
    "dust_scree": dust_scree,
    "dust_rock": dust_rock,
    "overgrowth_ground": overgrowth_ground,
    "overgrowth_scree": overgrowth_scree,
    "overgrowth_rock": overgrowth_rock,
}


# --- render ------------------------------------------------------------------------------------------


def scene_setup(tile: float) -> None:
    scene = bpy.context.scene
    tile_coll = bpy.data.collections["Tile"]
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            if i == 0 and j == 0:
                continue
            inst = bpy.data.objects.new(f"Tile{i}{j}", None)
            inst.instance_type = "COLLECTION"
            inst.instance_collection = tile_coll
            inst.location = (i * tile, j * tile, 0.0)
            scene.collection.objects.link(inst)
    cam_data = bpy.data.cameras.new("Top")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = tile
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    cam = bpy.data.objects.new("Top", cam_data)
    cam.location = (tile / 2, tile / 2, 20.0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    world = bpy.data.worlds.new("World")
    world.color = (0, 0, 0)
    scene.world = world
    B.setup_cycles(16)
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.cycles.filter_width = 1.0
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def render_pass(kind: str, path: pathlib.Path) -> np.ndarray:
    scene = bpy.context.scene
    route(kind)
    scene.cycles.samples = SAMPLES[kind]
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.render.filepath = str(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(path), check_existing=False)
    arr = B.pixels(img).copy()
    bpy.data.images.remove(img)
    return arr


def render_lit(tile: float, path: pathlib.Path) -> None:
    """Lit check of 2x2 tiles under a low sun, to spot seams and judge the relief."""
    scene = bpy.context.scene
    route("lit")
    cam = scene.camera
    cam.data.ortho_scale = tile * 2
    cam.location = (tile, tile, 20.0)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.data.angle = math.radians(1.0)
    sun.rotation_euler = (math.radians(-55), 0, math.radians(30))  # from the top left
    scene.collection.objects.link(sun)
    scene.world.color = (0.03, 0.03, 0.035)
    scene.cycles.max_bounces = 4
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def rgba_image(name: str, arr: np.ndarray, non_color: bool) -> bpy.types.Image:
    img = bpy.data.images.new(name, arr.shape[1], arr.shape[0], alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(np.clip(arr, 0.0, 1.0).astype(np.float32).ravel())
    return img


def build(name: str, preview: bool) -> dict:
    C.reset("Tile")
    SOCKETS.clear()
    rng = np.random.default_rng(sum(map(ord, name)) * 7919)
    tile = LAYERS[name](rng)
    scene_setup(tile)
    passes = {kind: render_pass(kind, TMP / f"{name}_{kind}.exr") for kind in ("albedo", "rough", "normal", "height", "ao")}
    normal = passes["normal"][..., :3] * 2.0 - 1.0
    normal /= np.linalg.norm(normal, axis=2, keepdims=True) + 1e-9
    height = passes["height"][..., 0]
    lo, hi = np.percentile(height, [0.2, 99.8])
    height = np.clip((height - lo) / (hi - lo), 0.0, 1.0)
    albedo = np.empty((SIZE, SIZE, 4))
    albedo[..., :3] = to_srgb(passes["albedo"][..., :3])
    albedo[..., 3] = height
    nra = np.empty((SIZE, SIZE, 4))
    nra[..., 0] = normal[..., 0] * 0.5 + 0.5
    nra[..., 1] = normal[..., 1] * 0.5 + 0.5
    nra[..., 2] = passes["rough"][..., 0]
    nra[..., 3] = passes["ao"][..., 0]
    B.save_png(rgba_image(f"{name}_albedo", albedo, non_color=False), OUT / f"{name}_albedo.png")
    B.save_png(rgba_image(f"{name}_nra", nra, non_color=True), OUT / f"{name}_nra.png")
    if preview:
        render_lit(tile, TMP / f"{name}_lit.png")
    stats = {
        "tile_m": tile,
        "albedo_mean_srgb": [round(float(v), 3) for v in albedo[..., :3].reshape(-1, 3).mean(0)],
        "rough_mean": round(float(nra[..., 2].mean()), 3),
        "ao_mean": round(float(nra[..., 3].mean()), 3),
        "height_range_m": round(float(hi - lo), 3),
        "normal_z_min": round(float(normal[..., 2].min()), 3),
        "tris": sum(len(o.data.polygons) for o in bpy.data.collections["Tile"].objects),
    }
    print(f"LAYER {name} {stats}")
    return stats


def main() -> None:
    argv = C.args()
    preview = "preview" in argv
    names = [a for a in argv if a in LAYERS] or list(LAYERS)
    for name in names:
        build(name, preview)


main()
