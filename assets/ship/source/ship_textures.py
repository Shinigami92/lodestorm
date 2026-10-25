"""Tileable texture sets for the ship's shell (assets/shaders/ship_shell.gdshader), Blender 5.2, Cycles.

The walls' paint and the floors' epoxy are procedural Cycles materials on a flat tile, rendered from straight
above as emission passes and packed, the terrain's way (assets/terrain/source/terrain_textures.py, whose nodes and
passes this reuses: periodic noise on a torus, numpy maps for what is rare); the grating is a numpy height map. All
are seamless and calm: the panels' edges are the kit's geometry, the surfaces live from their sheen.

    paint     3 m: clean light-grey satin paint, fine scratches, a faint orange peel, slightly duller patches
    epoxy     3 m: a glossy grey epoxy floor that mirrors the lights, faint scuffs and duller walking paths
    grating   1 m: bars over a dark pit

Two PNGs per set:

    assets/ship/textures/<set>_albedo.png   RGB base color (sRGB), A metalness (bare metal 1)
    assets/ship/textures/<set>_nra.png      RG normal X/Y (0.5 flat; +X right, +Y up in the image), B roughness,
                                            A AO

Run: tools/blender.sh assets/ship/source/ship_textures.py [set ...] [preview]
     ("preview" also renders a lit 2x2 tile check to tmp/ship_textures/<set>_lit.png)
"""

import pathlib
import sys

import bpy
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "assets" / "terrain" / "source"))
import terrain_textures as T

import bake as B
import common as C

OUT = ROOT / "assets" / "ship" / "textures"
TMP = ROOT / "tmp" / "ship_textures"
SIZE = T.SIZE
T.SAMPLES["metal"] = 16


def scratches(rng: np.random.Generator, tile: float, count: int, length: float, width: float) -> np.ndarray:
    """Thin straight scratches (wrapped), 0..1."""
    xs, ys = T.coords(tile)
    mask = np.zeros((SIZE, SIZE))
    for _ in range(count):
        cx, cy = rng.random(2) * tile
        a = rng.random() * np.pi
        dx, dy = np.cos(a), np.sin(a)
        rx = (xs - cx + tile / 2) % tile - tile / 2
        ry = (ys - cy + tile / 2) % tile - tile / 2
        along = rx * dx + ry * dy
        across = np.abs(-rx * dy + ry * dx)
        ln = length * (0.3 + rng.random())
        line = (1 - T.smoothstep(0, width, across)) * (1 - T.smoothstep(ln * 0.4, ln / 2, np.abs(along)))
        mask = np.maximum(mask, line)
    return mask


def image(n: "T.Nodes", name: str, arr: np.ndarray):
    """A numpy map (rows top-down) as a scalar socket in the tile's material."""
    return n.scalar(T.float_image(name, np.ascontiguousarray(arr[::-1])))


def finish(n: "T.Nodes", color, rough, height, metal) -> bpy.types.Material:
    mat = n.finish(color, rough, height, bump=1.0, ao_distance=0.05)
    sockets = T.SOCKETS[mat.name]
    n.set(sockets["bsdf"].node.inputs["Metallic"], metal)
    sockets["metal"] = metal
    return mat


def flat_tile(mat: bpy.types.Material, tile: float) -> None:
    T.ground_grid(np.zeros((T.MESH, T.MESH)), tile, mat)


def paint(rng: np.random.Generator) -> float:
    """Clean light-grey satin paint: an even color, the life in its sheen (fine scratches, a faint orange peel,
    slightly duller patches), no blotches."""
    tile = 3.0
    n = T.Nodes("Paint", tile)
    tone = n.noise(0.5, 2)
    scratch = image(n, "scratch", scratches(rng, tile, 60, 0.25, 0.0008))
    dull = n.ramp(n.noise(1.4, 3), 0.5, 2.0)
    color = n.mix(n.unit(tone, 0.06), T.srgb(0.5, 0.505, 0.51), T.srgb(0.54, 0.545, 0.55))
    color = n.mix(n.math("MULTIPLY", scratch, 0.5), color, T.srgb(0.6, 0.6, 0.61))
    rough = n.math("MULTIPLY_ADD", dull, 0.12, c=0.38)
    rough = n.lerp(scratch, rough, 0.25)
    peel = n.math("MULTIPLY", n.noise(60.0, 2), 0.00004)
    height = n.math("ADD", peel, n.math("MULTIPLY", scratch, -0.00015))
    flat_tile(finish(n, color, rough, height, n.math("MULTIPLY", scratch, 0.6)), tile)
    return tile


def epoxy(rng: np.random.Generator) -> float:
    """A glossy grey epoxy floor: one even color that mirrors the lights, faint scuffs and walking paths that
    only take away some of the shine."""
    tile = 3.0
    n = T.Nodes("Epoxy", tile)
    tone = n.noise(0.4, 2)
    scuff = image(n, "scuff", scratches(rng, tile, 80, 0.4, 0.002))
    worn = n.ramp(n.noise(0.7, 3), 0.3, 1.8)
    color = n.mix(n.unit(tone, 0.05), T.srgb(0.4, 0.405, 0.41), T.srgb(0.43, 0.435, 0.44))
    color = n.mix(n.math("MULTIPLY", scuff, 0.3), color, T.srgb(0.36, 0.36, 0.36))
    rough = n.math("MULTIPLY_ADD", worn, 0.12, c=0.12)
    rough = n.lerp(n.math("MULTIPLY", scuff, 0.8), rough, 0.4)
    height = n.math("MULTIPLY", scuff, -0.0001)
    flat_tile(finish(n, color, rough, height, n.math("MULTIPLY", scuff, 0.0)), tile)
    return tile


def bake(name: str, layer, preview: bool) -> None:
    C.reset("Tile")
    T.SOCKETS.clear()
    rng = np.random.default_rng(sum(map(ord, name)) * 7919)
    tile = layer(rng)
    T.scene_setup(tile)
    kinds = ("albedo", "rough", "normal", "ao", "metal")
    passes = {kind: T.render_pass(kind, TMP / f"{name}_{kind}.exr") for kind in kinds}
    normal = passes["normal"][..., :3] * 2.0 - 1.0
    normal /= np.linalg.norm(normal, axis=2, keepdims=True) + 1e-9
    albedo = np.empty((SIZE, SIZE, 4))
    albedo[..., :3] = T.to_srgb(passes["albedo"][..., :3])
    albedo[..., 3] = passes["metal"][..., 0]
    nra = np.empty((SIZE, SIZE, 4))
    nra[..., 0] = normal[..., 0] * 0.5 + 0.5
    nra[..., 1] = normal[..., 1] * 0.5 + 0.5
    nra[..., 2] = passes["rough"][..., 0]
    nra[..., 3] = passes["ao"][..., 0]
    B.save_png(T.rgba_image(f"{name}_albedo", albedo, non_color=False), OUT / f"{name}_albedo.png")
    B.save_png(T.rgba_image(f"{name}_nra", nra, non_color=True), OUT / f"{name}_nra.png")
    if preview:
        T.render_lit(tile, TMP / f"{name}_lit.png")
    print(f"SET {name} albedo {albedo[..., :3].reshape(-1, 3).mean(0).round(3)} rough {nra[..., 2].mean():.3f}")


def grating() -> None:
    tile = 1.0
    rng = np.random.default_rng(31)
    xs, ys = T.coords(tile)
    bars = 1 - T.smoothstep(0.004, 0.007, np.minimum(np.mod(xs, 0.04), 0.04 - np.mod(xs, 0.04)))
    cross = 1 - T.smoothstep(0.006, 0.01, np.minimum(np.mod(ys, 0.25), 0.25 - np.mod(ys, 0.25)))
    solid = np.maximum(bars, cross)
    tone = T.blobs(rng, tile, 0.3, 2) * 0.06
    albedo = np.empty((SIZE, SIZE, 4))
    metal = np.array([0.42, 0.42, 0.41])
    albedo[..., :3] = T.to_srgb(metal * (1 + tone[..., None]) * solid[..., None] + 0.01 * (1 - solid[..., None]))
    albedo[..., 3] = solid
    height = solid * (0.8 + 0.2 * cross)
    px = tile / SIZE
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.03 / (2 * px)
    gy = (np.roll(height, 1, axis=0) - np.roll(height, -1, axis=0)) * 0.03 / (2 * px)
    normal = np.stack([-gx, -gy, np.ones_like(height)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    nra = np.empty((SIZE, SIZE, 4))
    nra[..., 0] = normal[..., 0] * 0.5 + 0.5
    nra[..., 1] = normal[..., 1] * 0.5 + 0.5
    nra[..., 2] = 0.4 + 0.08 * T.blobs(rng, tile, 0.2) + 0.45 * (1 - solid)
    nra[..., 3] = 0.35 + 0.65 * solid
    # Rows top-down here; Blender's images run bottom-up.
    B.save_png(T.rgba_image("grating_albedo", albedo[::-1].copy(), non_color=False), OUT / "grating_albedo.png")
    B.save_png(T.rgba_image("grating_nra", nra[::-1].copy(), non_color=True), OUT / "grating_nra.png")
    print("SET grating")


SETS = {"paint": paint, "epoxy": epoxy}
argv = C.args()
preview = "preview" in argv
for name in [a for a in argv if a in (*SETS, "grating")] or [*SETS, "grating"]:
    if name == "grating":
        grating()
    else:
        bake(name, SETS[name], preview)
