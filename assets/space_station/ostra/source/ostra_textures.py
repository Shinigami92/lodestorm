"""Tileable texture sets for Waypost Ostra (assets/shaders/ship_shell.gdshader projects them, as the ship's), made
from numpy maps, Blender 5.2 only for writing the PNGs. Older and dirtier than the ship's:

    paint   4 m: weathered paint on steel: chipped to the bare metal at the edges of worn patches, rust spots
                 with streaks running down from them, scratches, grime (walls: the image's up is up)
    deck    2 m: a worn steel deck plate: its seams at the tile's edges with rivets along them, polished walking
                 wear, oil stains, scratches, dirt in the seams

Two PNGs per set, as the ship's (assets/ship/source/ship_textures.py):

    assets/space_station/ostra/textures/<set>_albedo.png   RGB base color (sRGB), A metalness
    assets/space_station/ostra/textures/<set>_nra.png      RG normal X/Y (0.5 flat), B roughness, A AO

Run: tools/blender.sh assets/space_station/ostra/source/ostra_textures.py [set ...]
"""

import pathlib
import sys

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "assets" / "terrain" / "source"))
import terrain_textures as T

import bake as B
import common as C

OUT = ROOT / "assets" / "space_station" / "ostra" / "textures"
SIZE = T.SIZE


def scratches(rng: np.random.Generator, tile: float, count: int, length: float, width: float, vertical=0.0):
    """Thin straight scratches (wrapped), 0..1; `vertical` > 0 leans them towards up and down."""
    xs, ys = T.coords(tile)
    mask = np.zeros((SIZE, SIZE))
    for _ in range(count):
        cx, cy = rng.random(2) * tile
        a = rng.random() * np.pi
        a = a + (np.pi / 2 - a) * vertical * rng.random()
        dx, dy = np.cos(a), np.sin(a)
        rx = (xs - cx + tile / 2) % tile - tile / 2
        ry = (ys - cy + tile / 2) % tile - tile / 2
        along = rx * dx + ry * dy
        across = np.abs(-rx * dy + ry * dx)
        ln = length * (0.3 + rng.random())
        line = (1 - T.smoothstep(0, width, across)) * (1 - T.smoothstep(ln * 0.4, ln / 2, np.abs(along)))
        mask = np.maximum(mask, line)
    return mask


def streaks(source: np.ndarray, rng: np.random.Generator, keep: float = 0.992) -> np.ndarray:
    """Runs down from `source` (rows top-down), fading, wrapped round the tile; broken up per column."""
    out = source.copy()
    for _ in range(2):
        for y in range(1, SIZE):
            out[y] = np.maximum(out[y], out[y - 1] * keep)
        out[0] = np.maximum(out[0], out[-1] * keep)
    column = np.convolve(np.tile(rng.random(SIZE), 3), np.ones(5) / 5, mode="same")[SIZE : 2 * SIZE]
    return out * (0.35 + 0.65 * column[None, :])


def normal_from(height: np.ndarray, tile: float, strength: float) -> np.ndarray:
    px = tile / SIZE
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength / (2 * px)
    gy = (np.roll(height, 1, axis=0) - np.roll(height, -1, axis=0)) * strength / (2 * px)
    normal = np.stack([-gx, -gy, np.ones_like(height)], axis=-1)
    return normal / np.linalg.norm(normal, axis=-1, keepdims=True)


def save(name: str, color: np.ndarray, metal: np.ndarray, rough: np.ndarray, height: np.ndarray, ao, tile, bump):
    """Rows top-down here; Blender's images run bottom-up."""
    albedo = np.empty((SIZE, SIZE, 4))
    albedo[..., :3] = T.to_srgb(np.clip(color, 0, 1))
    albedo[..., 3] = np.clip(metal, 0, 1)
    normal = normal_from(height, tile, bump)
    nra = np.empty((SIZE, SIZE, 4))
    nra[..., 0] = normal[..., 0] * 0.5 + 0.5
    nra[..., 1] = normal[..., 1] * 0.5 + 0.5
    nra[..., 2] = np.clip(rough, 0.05, 1)
    nra[..., 3] = np.clip(ao, 0, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    B.save_png(T.rgba_image(f"{name}_albedo", albedo[::-1].copy(), non_color=False), OUT / f"{name}_albedo.png")
    B.save_png(T.rgba_image(f"{name}_nra", nra[::-1].copy(), non_color=True), OUT / f"{name}_nra.png")
    print(f"SET {name} albedo {T.to_srgb(color).reshape(-1, 3).mean(0).round(3)} rough {rough.mean():.3f}")


def lin(r: float, g: float, b: float) -> np.ndarray:
    return np.array(T.srgb(r, g, b))


def paint() -> None:
    tile = 4.0
    rng = np.random.default_rng(4111)
    tone = T.blobs(rng, tile, 0.6, 3)
    wear = T.blobs(rng, tile, 0.25, 4, 0.6)
    chips = T.smoothstep(2.1, 2.25, wear)
    chip_edge = T.smoothstep(1.7, 2.1, wear) * (1 - chips)
    rust_src = T.smoothstep(2.4, 2.9, T.blobs(rng, tile, 0.12, 3, 0.6))
    rust_spots = np.maximum(rust_src, chips * T.smoothstep(0.5, 1.5, T.blobs(rng, tile, 0.08, 2)))
    rust_run = streaks(rust_spots * 0.8, rng)
    grime = T.smoothstep(-0.5, 2.0, T.blobs(rng, tile, 1.2, 2))
    scratch = scratches(rng, tile, 90, 0.3, 0.0012, vertical=0.4)
    paint_col = lin(0.47, 0.46, 0.43) * (1 + tone[..., None] * 0.035)
    metal_col = lin(0.36, 0.35, 0.34)
    rust_col = lin(0.36, 0.2, 0.11) * (1 + T.blobs(rng, tile, 0.05)[..., None] * 0.15)
    color = paint_col * (1 - 0.08 * chip_edge[..., None])
    color = color * (1 - grime[..., None] * 0.22)
    color = color + (rust_col - color) * np.clip(rust_run * 0.55, 0, 1)[..., None]
    color = color + (metal_col - color) * np.maximum(chips, scratch * 0.6)[..., None]
    color = color + (rust_col * 0.8 - color) * (rust_spots * 0.85)[..., None]
    metal = np.maximum(chips, scratch * 0.7) * (1 - rust_spots)
    rough = 0.62 + 0.06 * tone + 0.12 * grime - 0.18 * chips + 0.2 * rust_spots + 0.1 * rust_run
    height = -0.0003 * chips - 0.00008 * scratch + 0.00015 * rust_spots * T.blobs(rng, tile, 0.02)
    save("paint", color, metal, rough, height, 1 - 0.25 * chips - 0.1 * grime, tile, 2.0)


def deck() -> None:
    tile = 2.0
    rng = np.random.default_rng(2207)
    xs, ys = T.coords(tile)
    edge = np.minimum(np.minimum(xs, tile - xs), np.minimum(ys, tile - ys))
    seam = 1 - T.smoothstep(0.003, 0.007, edge)
    near_seam = 1 - T.smoothstep(0.0, 0.12, edge)
    # Rivets along the seams, 5 cm in, every 0.25 m.
    rivets = np.zeros((SIZE, SIZE))
    for along in np.arange(0.125, tile, 0.25):
        for cx, cy in ((along, 0.05), (along, tile - 0.05), (0.05, along), (tile - 0.05, along)):
            d = np.hypot(xs - cx, ys - cy)
            rivets = np.maximum(rivets, 1 - T.smoothstep(0.008, 0.012, d))
    tone = T.blobs(rng, tile, 0.5, 3)
    polish = T.smoothstep(0.2, 1.6, T.blobs(rng, tile, 0.35, 2))
    oil = T.smoothstep(2.2, 2.8, T.blobs(rng, tile, 0.12, 3, 0.6))
    dirt = T.smoothstep(-0.5, 2.0, T.blobs(rng, tile, 0.5, 3)) * 0.25 + near_seam * 0.45
    scratch = scratches(rng, tile, 50, 0.3, 0.001)
    base = lin(0.36, 0.36, 0.35) * (1 + tone[..., None] * 0.04)
    color = base * (1 - dirt[..., None] * 0.3)
    color = color * (1 + polish[..., None] * 0.12)
    color = color * (1 - oil[..., None] * 0.12)
    color = color * (1 - seam[..., None] * 0.8)
    color = color + (lin(0.48, 0.48, 0.47) - color) * (scratch * 0.35)[..., None]
    color = color + (lin(0.42, 0.42, 0.41) - color) * (rivets * 0.6)[..., None]
    metal = 0.45 + 0.08 * polish + 0.2 * scratch - 0.12 * dirt
    rough = 0.56 - 0.08 * polish + 0.08 * dirt - 0.2 * oil - 0.12 * scratch
    height = -0.0025 * seam + 0.0015 * rivets - 0.00006 * scratch + 0.00008 * T.blobs(rng, tile, 0.03)
    save("deck", color, metal, rough, height, 1 - 0.55 * seam - 0.15 * near_seam, tile, 1.0)


SETS = {"paint": paint, "deck": deck}
C.reset("Tile")
for name in [a for a in C.args() if a in SETS] or list(SETS):
    SETS[name]()
