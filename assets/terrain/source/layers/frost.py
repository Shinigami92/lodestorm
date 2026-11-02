"""Frost fields: wind-packed snow over ice, frosted scree of ice chunks and dark stones, blue-grey rock with ice in
its joints and rime on its ledges.

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
    smoothstep,
    srgb,
    stones,
    voronoi,
)


def streaks(rng: np.random.Generator, tile: float, along: float, across: float, angle: float) -> np.ndarray:
    """Periodic noise (mean 0, std 1) stretched along a direction: features about `along` m long and `across` m wide,
    the long side at `angle` (radians from +x). Filtered white noise like blobs(), only with an elliptic filter."""
    f = np.fft.fftfreq(SIZE, d=tile / SIZE)
    fx, fy = f[None, :], f[:, None]
    c, s = math.cos(angle), math.sin(angle)
    fa = fx * c + fy * s  # frequency along the streaks
    fc = -fx * s + fy * c  # across them
    layer = np.fft.ifft2(
        np.fft.fft2(rng.standard_normal((SIZE, SIZE))) * np.exp(-2.0 * (fa**2 * along**2 + fc**2 * across**2))
    ).real
    return layer / (layer.std() + 1e-12)


def gradient_y(height: np.ndarray, tile: float) -> np.ndarray:
    """Slope of a periodic map along the image's up (+y, rows grow upward in Blender images), rise per m."""
    step = tile / height.shape[0]
    return (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2.0 * step)


def soften(field: np.ndarray, tile: float, size_m: float) -> np.ndarray:
    """A periodic map blurred over about `size_m` (Gaussian filter through the FFT)."""
    f = np.fft.fftfreq(field.shape[0], d=tile / field.shape[0])
    f2 = f[None, :] ** 2 + f[:, None] ** 2
    return np.fft.ifft2(np.fft.fft2(field) * np.exp(-f2 * size_m * size_m * 2.0)).real


def _frosted_stone(name: str, tile: float, colors: list, frost: float) -> object:
    """Dark angular stone with frost settled on its upward faces (a share `frost` of them white) and in its pits."""
    s = Nodes(name, tile)
    base = s.palette(s.attribute("rand"), colors)
    speck = s.noise(60.0, 4.0, 0.6)
    color = s.mix(s.math("MULTIPLY", s.ramp(speck, 0.7, 2.2), 0.6), base, srgb(0.12, 0.13, 0.15))
    geo = s.nt.nodes.new("ShaderNodeNewGeometry")
    up = s.node("ShaderNodeSeparateXYZ", Vector=geo.outputs["Normal"]).outputs["Z"]
    rime = s.math("MULTIPLY", s.ramp(up, 0.35, 0.8), s.ramp(s.noise(18.0, 3.0, 0.6), -0.6, 0.6))
    rime = s.math("MULTIPLY", rime, frost)
    color = s.mix(rime, color, srgb(0.62, 0.66, 0.71))
    rough = s.lerp(rime, s.lerp(s.unit(speck), 0.7, 0.85), 0.92)
    return s.finish(color, rough, s.math("MULTIPLY", speck, 0.0005), ao_distance=0.1)


def frost_ground(rng: np.random.Generator) -> float:
    """Frost fields: calm, even wind-packed snow with faint, low wind ridges, a few large soft-edged patches where
    the wind has polished it down to bluish-grey ice (about an eighth of the tile, barely lower than the snow, faint
    cracks, matte enough not to glint), and a few small dark stones. Seen from the game camera it reads as one quiet
    surface: weak low-frequency variation, nothing high-contrast."""
    tile = 6.0
    wind = math.radians(20.0)
    base = 0.015 * blobs(rng, tile, 1.8, 2)
    # Bare ice: the top ~12 % of a large, smooth field, its edge a little ragged and stretched along the wind.
    bare = blobs(rng, tile, 1.6, 1) + 0.3 * streaks(rng, tile, 0.8, 0.25, wind) + 0.08 * blobs(rng, tile, 0.15)
    cut = np.quantile(bare, 0.88)
    ice = smoothstep(cut - 0.15, cut + 0.35, bare)
    # Faint sastrugi (long low ridges along the wind), only on the snow.
    ridges = streaks(rng, tile, 0.9, 0.12, wind)
    sastrugi = smoothstep(0.6, 2.2, ridges) * smoothstep(-0.4, 0.6, blobs(rng, tile, 1.4))
    height = base + (0.008 + 0.003 * sastrugi) * (1.0 - ice)
    # Ice: a few faint cracks, no bubbles.
    bend = (0.012 * blobs(rng, tile, 0.5, 2), 0.012 * blobs(rng, tile, 0.5, 2))
    f1, f2, _ = voronoi(rng, 24, warp=bend)
    cracks = (1.0 - smoothstep(0.0, 0.0008, f2 - f1)) * smoothstep(0.5, 1.0, ice)
    height = height - cracks * 0.0015
    fine = 0.001 * sastrugi * (1.0 - ice)
    tone = blobs(rng, tile, 1.2, 2, 0.5)

    n = Nodes("FrostSnow", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    ice_s = n.scalar(float_image("ice", ice))
    crack_s = n.scalar(float_image("cracks", cracks))
    ridge_s = n.scalar(float_image("ridges", sastrugi))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(110.0, 3.0, 0.7)
    # Snow: even blue-grey, weak large variation, the ridge crests barely lighter.
    snow = n.mix(n.ramp(tone_s, 0.2, 0.8), srgb(0.465, 0.5, 0.55), srgb(0.495, 0.53, 0.58))
    snow = n.mix(n.unit(grain, 0.1), srgb(0.455, 0.49, 0.54), snow)
    snow = n.mix(n.math("MULTIPLY", ridge_s, 0.25), snow, srgb(0.525, 0.555, 0.6))
    # Ice: a slightly bluer, darker grey than the snow, its cracks a touch lighter.
    ice_color = n.mix(n.ramp(tone_s, 0.2, 0.8), srgb(0.39, 0.44, 0.505), srgb(0.41, 0.46, 0.525))
    ice_color = n.mix(n.math("MULTIPLY", crack_s, 0.4), ice_color, srgb(0.47, 0.515, 0.57))
    color = n.mix(ice_s, snow, ice_color)
    rough = n.lerp(ice_s, 0.93, 0.62)
    detail = n.math(
        "ADD", fine_s, n.math("MULTIPLY", n.math("MULTIPLY", grain, 0.0003), n.math("SUBTRACT", 1.0, ice_s))
    )
    snow_mat = n.finish(color, rough, detail, bump=0.6, ao_distance=0.15)

    stone_mat = _frosted_stone(
        "FrostPebble", tile, [(0.24, 0.25, 0.27), (0.28, 0.29, 0.31), (0.22, 0.23, 0.25), (0.26, 0.26, 0.27)], 0.8
    )
    ground_grid(height, tile, snow_mat)
    placed: list = []
    kw = dict(flat=(0.4, 0.65), sink=0.5, cuts=6)
    stones(rng, "Stones", tile, height, 4, (0.04, 0.08), stone_mat, spacing=2.5, others=placed, **kw)
    stones(rng, "Pebbles", tile, height, 25, (0.012, 0.03), stone_mat, spacing=1.5, others=placed, **kw)
    return tile


def frost_scree(rng: np.random.Generator) -> float:
    """Frost fields scree: broken ice chunks and frost-coated dark angular stones half sunk in snow (cliff feet)."""
    tile = 4.0
    height = 0.04 * blobs(rng, tile, 1.0, 2)
    tone = blobs(rng, tile, 0.4, 2)

    n = Nodes("ScreeSnow", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    grain = n.noise(110.0, 3.0, 0.7)
    color = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.4, 0.44, 0.5), srgb(0.47, 0.51, 0.57))
    color = n.mix(n.unit(grain, 0.12), srgb(0.38, 0.42, 0.48), color)
    snow_mat = n.finish(color, 0.92, n.math("MULTIPLY", grain, 0.0006), ao_distance=0.12)

    stone_mat = _frosted_stone(
        "ScreeStone",
        tile,
        [(0.2, 0.21, 0.24), (0.25, 0.26, 0.29), (0.16, 0.17, 0.19), (0.29, 0.29, 0.31), (0.22, 0.23, 0.25)],
        0.5,
    )

    c = Nodes("ScreeIce", tile)
    facet = c.attribute("rand")
    vein = c.noise(14.0, 3.0, 0.6)
    ice = c.mix(facet, srgb(0.36, 0.45, 0.53), srgb(0.48, 0.57, 0.64))
    ice = c.mix(c.math("MULTIPLY", c.ramp(vein, 0.6, 1.8), 0.6), ice, srgb(0.25, 0.34, 0.44))
    geo = c.nt.nodes.new("ShaderNodeNewGeometry")
    up = c.node("ShaderNodeSeparateXYZ", Vector=geo.outputs["Normal"]).outputs["Z"]
    frost = c.math("MULTIPLY", c.ramp(up, 0.5, 0.9), c.ramp(c.noise(20.0, 3.0, 0.6), -0.4, 0.8))
    ice = c.mix(c.math("MULTIPLY", frost, 0.7), ice, srgb(0.62, 0.67, 0.72))
    ice_mat = c.finish(ice, c.lerp(frost, 0.2, 0.75), c.math("MULTIPLY", vein, 0.0004), ao_distance=0.1)

    ground_grid(height, tile, snow_mat)
    placed: list = []
    sharp = dict(flat=(0.45, 0.8), sink=0.3, cuts=7, lumps=0.05)
    stones(rng, "IceChunks", tile, height, 14, (0.12, 0.22), ice_mat, spacing=1.0, others=placed, **sharp)
    stones(rng, "Rocks", tile, height, 28, (0.13, 0.26), stone_mat, spacing=1.0, others=placed, **sharp)
    stones(rng, "IceShards", tile, height, 140, (0.04, 0.1), ice_mat, spacing=0.85, others=placed, **sharp)
    stones(rng, "Stones", tile, height, 450, (0.04, 0.11), stone_mat, spacing=0.85, others=placed, **sharp)
    stones(rng, "Gravel", tile, height, 2200, (0.012, 0.04), stone_mat, spacing=0.8, others=placed, **sharp)
    return tile


def frost_rock(rng: np.random.Generator) -> float:
    """Frost fields cliff (a wall, image up = world up): dark blue-grey rock in horizontal strata, its joints and
    cracks filled with ice, rime and snow lodged on the ledges (the parts facing up)."""
    tile = 8.0
    _xs, ys = coords(tile)
    bounds = [0.0]
    while bounds[-1] < tile - 0.4:
        bounds.append(bounds[-1] + rng.uniform(0.25, 0.9))
    bounds[-1] = tile
    bands = len(bounds) - 1
    recess = rng.uniform(0.0, 0.14, bands) * (rng.random(bands) < 0.65)
    shade = rng.random(bands)
    profile_y = np.linspace(0, tile, 4096, endpoint=False)
    band_of = np.searchsorted(bounds, profile_y, side="right") - 1
    f = np.fft.fftfreq(4096, d=tile / 4096)
    profile = np.fft.ifft(np.fft.fft(-recess[band_of]) * np.exp(-((f * 0.035) ** 2) * 2)).real
    warped = (ys + 0.1 * blobs(rng, tile, 3.0) + 0.02 * blobs(rng, tile, 0.4)) % tile
    index = (warped / tile * 4096).astype(int) % 4096
    strata = profile[index]
    band_shade = shade[band_of[index]]
    bend = (0.012 * blobs(rng, tile, 0.6, 2), 0.005 * blobs(rng, tile, 0.6, 2))
    # Joints split the strata into tall blocks, each set a little forward or back (its edges softly broken).
    f1, f2, block = voronoi(rng, 16, stretch=(1.0, 0.35), warp=bend)
    width = 0.0025 + 0.003 * (blobs(rng, tile, 1.0) * 0.5 + 0.5).clip(0, 1)
    joints = 1.0 - smoothstep(0.0, width, f2 - f1)
    offsets = np.random.default_rng(int(rng.integers(1 << 30))).uniform(-0.05, 0.05, block.max() + 1)
    blocks = soften(offsets[block], tile, 0.03)
    g1, g2, _ = voronoi(rng, 50, warp=bend)
    cracks = (1.0 - smoothstep(0.0, 0.0014, g2 - g1)) * smoothstep(0.2, 0.9, blobs(rng, tile, 0.8))
    bulge = 0.16 * blobs(rng, tile, 3.0) + 0.04 * blobs(rng, tile, 0.8, 2)
    erosion = 0.012 * blobs(rng, tile, 0.25, 3)
    large = bulge + strata + blocks
    rock = large + erosion - joints * 0.06 - cracks * 0.015
    # Ledges: where the face steps back going up it faces the sky; snow and rime lie there (a few cm thick), in
    # strips along the strata and block tops, broken where the wind has cleared them.
    slope = -gradient_y(soften(large, tile, 0.01), tile)
    ledge = smoothstep(0.3, 1.0, slope) * smoothstep(-0.8, 0.2, blobs(rng, tile, 0.6, 2))
    # The snow lies in a strip just below each step (on the ledge's lip, seen from the front), its lower edge
    # ragged: the distance below the nearest step decides, against a depth of 3-11 cm varying along it.
    rows = ledge.shape[0]
    reach = int(0.12 / tile * rows)
    below = np.full(ledge.shape, np.inf)
    for k in range(reach):
        below = np.where((np.roll(ledge, -k, axis=0) > 0.4) & np.isinf(below), k * tile / rows, below)
    depth = 0.07 + 0.04 * blobs(rng, tile, 0.15, 2)
    snow = smoothstep(0.01, -0.01, below - depth)
    ice_fill = np.maximum(joints, cracks * 0.45)
    height = rock + snow * 0.025 + ice_fill * 0.045  # ice fills the joints back up close to the face
    lamination = np.sin(math.tau * 200 * warped / tile) * 0.0015
    fine = lamination * (1.0 - snow)

    n = Nodes("FrostRock", tile)
    shade_s = n.scalar(float_image("shade", band_shade))
    ice_s = n.scalar(float_image("ice", ice_fill))
    snow_s = n.scalar(float_image("snow", snow))
    dark_s = n.scalar(float_image("recess", smoothstep(0.03, 0.12, -strata)))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(40.0, 5.0, 0.65)
    mottle = n.noise(3.0, 3.0, 0.6)
    color = n.palette(
        n.math("ADD", shade_s, n.math("MULTIPLY", mottle, 0.04)),
        [(0.2, 0.22, 0.25), (0.25, 0.27, 0.3), (0.18, 0.2, 0.23), (0.28, 0.3, 0.32), (0.22, 0.23, 0.26)],
    )
    color = n.mix(n.math("MULTIPLY", dark_s, 0.5), color, srgb(0.13, 0.14, 0.16))
    color = n.mix(n.math("MULTIPLY", n.ramp(grain, 0.5, 2.0), 0.4), color, srgb(0.15, 0.16, 0.18))
    ice_color = n.mix(n.unit(mottle, 0.3), srgb(0.3, 0.37, 0.45), srgb(0.4, 0.48, 0.56))
    color = n.mix(n.math("MULTIPLY", ice_s, 0.75), color, ice_color)
    snow_color = n.mix(n.unit(grain, 0.2), srgb(0.55, 0.59, 0.64), srgb(0.64, 0.67, 0.71))
    color = n.mix(snow_s, color, snow_color)
    rough = n.lerp(n.unit(grain), 0.8, 0.94)
    rough = n.lerp(ice_s, rough, 0.3)
    rough = n.lerp(snow_s, rough, 0.9)
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, 0.0015))
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


LAYERS = {
    "frost_ground": frost_ground,
    "frost_scree": frost_scree,
    "frost_rock": frost_rock,
}
