"""Overgrowth: damp soil under olive moss, mossy scree, mossy rock.

A layer module of terrain_textures.py: `LAYERS` maps each layer's name to its function, which models the tile's
geometry and materials and returns the tile's size in m (see the conventions in terrain_textures.py).
"""

import math

import numpy as np
from terrain_textures import (
    SIZE,
    Nodes,
    blobs,
    coords,
    float_image,
    ground_grid,
    roots,
    sample,
    smoothstep,
    specks,
    srgb,
    stones,
    voronoi,
)


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
    base = s.palette(
        s.attribute("rand"), [(0.25, 0.25, 0.24), (0.30, 0.29, 0.27), (0.22, 0.22, 0.21), (0.34, 0.33, 0.30)]
    )
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
    stones(
        rng,
        "Buds",
        tile,
        height,
        160,
        (0.004, 0.009),
        bud_mat,
        flat=(0.7, 1.0),
        subdivisions=2,
        cuts=0,
        lumps=0.05,
        smooth=True,
        sink=0.2,
        others=placed,
        where=lambda x, y: 1.0 if sample(moss, tile, x, y) > 0.5 else 0.05,
    )
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
    base = s.palette(
        s.attribute("rand"),
        [(0.24, 0.24, 0.23), (0.30, 0.29, 0.27), (0.21, 0.21, 0.21), (0.35, 0.34, 0.31), (0.27, 0.26, 0.22)],
    )
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
    blocks = (
        tilt[cell, 0] * np.sin(math.tau * xs / tile) + tilt[cell, 1] * np.sin(math.tau * ys / tile)
    ) * tile * 0.3 + lift[cell]
    rounded = smoothstep(0.0, 0.03, edge)
    height = blocks * rounded - (1.0 - rounded) * 0.05 + 0.15 * blobs(rng, tile, 3.0) + 0.015 * blobs(rng, tile, 0.3, 3)
    ledge = -np.gradient(height, axis=0) * SIZE / tile  # facing up (+Y) on the wall
    moss = np.clip(
        smoothstep(0.2, 0.9, 1.0 - rounded)
        + smoothstep(0.1, 0.5, ledge) * smoothstep(-0.3, 0.5, blobs(rng, tile, 0.5)),
        0,
        1,
    )
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
    detail = n.math(
        "ADD", n.math("MULTIPLY", grain, 0.0015), n.math("MULTIPLY", n.math("MULTIPLY", moss_s, fuzz), 0.0015)
    )
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


LAYERS = {
    "overgrowth_ground": overgrowth_ground,
    "overgrowth_scree": overgrowth_scree,
    "overgrowth_rock": overgrowth_rock,
}
