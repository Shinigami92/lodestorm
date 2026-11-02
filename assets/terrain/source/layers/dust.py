"""Dust flats: sandy regolith with cracked crust, angular scree, layered sandstone cliffs.

A layer module of terrain_textures.py: `LAYERS` maps each layer's name to its function, which models the tile's
geometry and materials and returns the tile's size in m (see the conventions in terrain_textures.py).
"""

import math

import numpy as np
from terrain_textures import Nodes, blobs, coords, float_image, ground_grid, smoothstep, specks, srgb, stones, voronoi


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
    base = s.palette(
        s.attribute("rand"),
        [(0.38, 0.34, 0.30), (0.45, 0.38, 0.31), (0.33, 0.30, 0.27), (0.50, 0.45, 0.38), (0.41, 0.32, 0.25)],
    )
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
    base = s.palette(
        s.attribute("rand"),
        [
            (0.36, 0.32, 0.29),
            (0.44, 0.38, 0.32),
            (0.31, 0.28, 0.26),
            (0.50, 0.44, 0.37),
            (0.40, 0.31, 0.25),
            (0.35, 0.34, 0.33),
        ],
    )
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
    _xs, ys = coords(tile)
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
    color = n.palette(
        n.math("ADD", shade_s, n.math("MULTIPLY", mottle, 0.04)),
        [(0.30, 0.25, 0.20), (0.36, 0.29, 0.22), (0.27, 0.24, 0.21), (0.40, 0.32, 0.24), (0.32, 0.26, 0.21)],
    )
    color = n.mix(n.math("MULTIPLY", dark_s, 0.4), color, srgb(0.21, 0.18, 0.15))
    color = n.mix(n.math("MULTIPLY", n.ramp(grain, 0.5, 2.0), 0.4), color, srgb(0.22, 0.19, 0.16))
    color = n.mix(n.math("MULTIPLY", joint_s, 0.7), color, srgb(0.15, 0.13, 0.11))
    rough = n.lerp(n.unit(grain), 0.85, 0.97)
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, 0.0015))
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


LAYERS = {
    "dust_ground": dust_ground,
    "dust_scree": dust_scree,
    "dust_rock": dust_rock,
}
