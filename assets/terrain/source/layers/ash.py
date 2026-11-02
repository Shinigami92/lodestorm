"""Ash fields: dark volcanic ash with cinders and crusted patches, black clinker scree, basalt cliffs with columnar
jointing and vesicular flow layers.

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
    sample,
    smoothstep,
    specks,
    srgb,
    stones,
    voronoi,
)

# --- helpers (periodic over the tile, like the shared ones) -----------------------------------------------


def streaks(rng: np.random.Generator, tile: float, length_m: float, width_m: float, angle: float, n: int = SIZE):
    """Smooth periodic noise (mean 0, std 1) stretched along `angle` (radians from +X): features about `length_m`
    long and `width_m` wide (wind drifts, pale ash streaks, flow banding)."""
    f = np.fft.fftfreq(n, d=tile / n)
    fx, fy = f[None, :], f[:, None]
    c, s = math.cos(angle), math.sin(angle)
    along = fx * c + fy * s
    across = -fx * s + fy * c
    gauss = np.exp(-(along**2 * length_m**2 + across**2 * width_m**2) * 2.0)
    field = np.fft.ifft2(np.fft.fft2(rng.standard_normal((n, n))) * gauss).real
    return field / (field.std() + 1e-12)


def pits(n: Nodes, scale: float, radius: float = 0.3):
    """Vesicles: 0..1, 1 inside small round holes on a periodic 4D Voronoi grid, about `scale` holes per meter,
    `radius` of a cell wide (the cells are 1 / scale m)."""
    tex = n.node("ShaderNodeTexVoronoi", props={"voronoi_dimensions": "4D"}, Vector=n.torus, W=n.w, Scale=scale)
    return n.math("SUBTRACT", 1.0, n.ramp(tex.outputs["Distance"], radius * 0.55, radius))


def up_facing(n: Nodes, lo: float = 0.55, hi: float = 0.9):
    """0..1 on faces turned up (world Z), for ash dusting the tops of stones."""
    geo = n.nt.nodes.new("ShaderNodeNewGeometry")
    z = n.node("ShaderNodeSeparateXYZ", Vector=geo.outputs["Normal"]).outputs["Z"]
    return n.ramp(z, lo, hi)


def cinder_material(n: Nodes, colors: list, pit_scale: float, dust: float, ash: tuple) -> object:
    """Black and dark red-brown scoria: per-stone tone (`rand`), vesicle pits (darker, sunk), a little ash on the
    tops (`dust` 0..1 how much), glassy specks a bit less rough."""
    base = n.palette(n.attribute("rand"), colors)
    holes = pits(n, pit_scale, 0.32)
    holes_fine = pits(n, pit_scale * 2.6, 0.28)
    hole = n.math("MAXIMUM", holes, n.math("MULTIPLY", holes_fine, 0.7))
    speck = n.noise(70.0, 3.0, 0.6)
    color = n.mix(n.math("MULTIPLY", hole, 0.75), base, srgb(0.03, 0.028, 0.027))
    color = n.mix(n.math("MULTIPLY", n.ramp(speck, 1.0, 2.2), 0.5), color, srgb(0.2, 0.19, 0.185))
    dusting = n.math("MULTIPLY", up_facing(n), n.ramp(n.noise(9.0, 3.0, 0.6), 0.2, 1.4))
    dusting = n.math("MULTIPLY", n.math("MULTIPLY", dusting, n.math("SUBTRACT", 1.0, hole)), dust)
    color = n.mix(dusting, color, srgb(*ash))
    rough = n.lerp(n.ramp(speck, 0.0, 1.5), 0.9, 0.7)
    rough = n.lerp(dusting, rough, 0.98)
    detail = n.math("SUBTRACT", n.math("MULTIPLY", speck, 0.0004), n.math("MULTIPLY", hole, 0.004))
    return n.finish(color, rough, detail, ao_distance=0.08)


# --- layers ------------------------------------------------------------------------------------------------


def ash_ground(rng: np.random.Generator) -> float:
    """Ash fields: fine dark grey volcanic ash in soft wind drifts, scattered black and red-brown cinders, patches of
    cracked crusted ash and faint pale ash streaks."""
    tile = 6.0
    wind = rng.uniform(0, math.pi)
    height = 0.035 * blobs(rng, tile, 1.5, 3)
    drift = streaks(rng, tile, 1.6, 0.5, wind)
    height = height + 0.01 * drift
    crust = smoothstep(0.55, 1.05, blobs(rng, tile, 1.1) + 0.35 * blobs(rng, tile, 0.3))
    bend = (0.015 * blobs(rng, tile, 0.5, 2), 0.015 * blobs(rng, tile, 0.5, 2))
    f1, f2, cell = voronoi(rng, 80, warp=bend)
    edge = f2 - f1
    width = 0.0022 + 0.0016 * (blobs(rng, tile, 0.3) * 0.5 + 0.5).clip(0, 1)
    cracks = (1.0 - smoothstep(0.0, width, edge)) * crust
    # Crust plates: a few mm proud of the loose ash, each tilted a little, their edges broken down at the cracks.
    xs, ys = coords(tile)
    count = cell.max() + 1
    tilt = rng.normal(scale=0.012, size=(count, 2))
    plate_tilt = tilt[cell, 0] * np.sin(math.tau * xs / tile) + tilt[cell, 1] * np.sin(math.tau * ys / tile)
    plates = crust * (0.008 + plate_tilt) * smoothstep(0.0, width * 2.5, edge)
    plate_tone = np.random.default_rng(int(rng.integers(1 << 30))).random(count)[cell]
    height = height + plates - cracks * 0.012
    pale = streaks(rng, tile, 1.4, 0.22, wind + rng.uniform(-0.2, 0.2)) + 0.4 * blobs(rng, tile, 0.15)
    pale = smoothstep(1.2, 2.4, pale) * (1.0 - crust)
    fine = 0.0025 * blobs(rng, tile, 0.04, 2) * (1.0 - 0.6 * crust)
    tone = blobs(rng, tile, 0.4, 3, 0.6)
    dark = specks(rng, tile, 0.012, 0.05)

    n = Nodes("Ash", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    crust_s = n.scalar(float_image("crust", crust))
    crack_s = n.scalar(float_image("cracks", cracks))
    plate_s = n.scalar(float_image("plates", plate_tone))
    pale_s = n.scalar(float_image("pale", pale))
    dark_s = n.scalar(float_image("dark", dark))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(110.0, 3.0, 0.7)
    ash = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.205, 0.2, 0.195), srgb(0.25, 0.243, 0.235))
    ash = n.mix(n.unit(grain, 0.14), srgb(0.17, 0.166, 0.162), ash)
    crust_color = n.mix(plate_s, srgb(0.2, 0.19, 0.18), srgb(0.25, 0.235, 0.22))
    color = n.mix(n.math("MULTIPLY", crust_s, 0.85), ash, crust_color)
    color = n.mix(n.math("MULTIPLY", dark_s, 0.6), color, srgb(0.13, 0.125, 0.12))
    color = n.mix(n.math("MULTIPLY", pale_s, 0.5), color, srgb(0.34, 0.33, 0.315))
    color = n.mix(n.math("MULTIPLY", crack_s, 0.9), color, srgb(0.07, 0.065, 0.06))
    rough = n.lerp(crust_s, 0.99, 0.92)
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, 0.0007))
    ash_mat = n.finish(color, rough, detail, ao_distance=0.15)

    s = Nodes("Cinder", tile)
    cinders = [
        (0.075, 0.07, 0.068),
        (0.12, 0.085, 0.072),
        (0.095, 0.092, 0.09),
        (0.15, 0.1, 0.082),
        (0.06, 0.058, 0.058),
        (0.11, 0.1, 0.095),
    ]
    cinder_mat = cinder_material(s, cinders, 45.0, 0.55, (0.22, 0.213, 0.205))

    ground_grid(height, tile, ash_mat)
    placed: list = []
    kw = dict(flat=(0.55, 0.9), cuts=6, lumps=0.18, subdivisions=2)

    def not_crust(x: float, y: float) -> float:
        """Fewer cinders on the crust plates."""
        return 1.0 - 0.8 * sample(crust, tile, x, y)

    stones(rng, "Clasts", tile, height, 7, (0.07, 0.13), cinder_mat, sink=0.35, spacing=1.6, others=placed, **kw)
    stones(
        rng,
        "Scoria",
        tile,
        height,
        110,
        (0.025, 0.07),
        cinder_mat,
        sink=0.3,
        spacing=1.3,
        others=placed,
        where=not_crust,
        **kw,
    )
    stones(rng, "Cinders", tile, height, 900, (0.01, 0.028), cinder_mat, sink=0.3, others=placed, where=not_crust, **kw)
    return tile


def ash_scree(rng: np.random.Generator) -> float:
    """Ash fields scree: piles of black clinker and scoria, porous angular chunks of all sizes, ash in the gaps."""
    tile = 4.0
    height = 0.05 * blobs(rng, tile, 1.0, 2)
    tone = blobs(rng, tile, 0.4, 2)

    n = Nodes("ScreeAsh", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    grain = n.noise(110.0, 3.0, 0.7)
    color = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.19, 0.184, 0.178), srgb(0.235, 0.227, 0.218))
    color = n.mix(n.unit(grain, 0.14), srgb(0.165, 0.16, 0.155), color)
    ash_mat = n.finish(color, 0.99, n.math("MULTIPLY", grain, 0.0007), ao_distance=0.1)

    s = Nodes("Clinker", tile)
    clinker = [
        (0.085, 0.08, 0.078),
        (0.15, 0.1, 0.085),
        (0.12, 0.116, 0.112),
        (0.07, 0.068, 0.067),
        (0.18, 0.12, 0.095),
        (0.1, 0.095, 0.092),
        (0.14, 0.132, 0.125),
    ]
    clinker_mat = cinder_material(s, clinker, 20.0, 0.35, (0.21, 0.204, 0.197))

    ground_grid(height, tile, ash_mat)
    placed: list = []
    kw = dict(flat=(0.6, 0.95), sink=0.22, cuts=8, lumps=0.26, subdivisions=2)
    stones(rng, "Rocks", tile, height, 30, (0.12, 0.25), clinker_mat, spacing=0.9, others=placed, **kw)
    stones(rng, "Stones", tile, height, 650, (0.04, 0.12), clinker_mat, spacing=0.75, others=placed, **kw)
    stones(rng, "Gravel", tile, height, 3600, (0.012, 0.04), clinker_mat, spacing=0.75, others=placed, **kw)
    return tile


def _columns(rng: np.random.Generator, tile: float, xs: np.ndarray, ys: np.ndarray, lean: float) -> dict:
    """Relief of a colonnade over the whole tile (masked to its band later): vertical hexagonal columns 0.3-0.6 m
    wide, each showing two faces that meet at a ridge, at its own depth, broken into stacked segments by slightly
    tilted cross joints. Returns maps: height, joint (0..1 lines), tone (per column and segment)."""
    widths: list = []
    while sum(widths) < tile:
        widths.append(rng.uniform(0.3, 0.6))
    w = np.array(widths) * tile / sum(widths)
    left = np.concatenate([[0.0], np.cumsum(w)[:-1]])
    count = len(w)
    x = (xs - lean * ys - rng.uniform(0, tile)) % tile
    idx = np.clip(np.searchsorted(left, x, side="right") - 1, 0, count - 1)
    u = (x - left[idx]) / w[idx]  # 0..1 across the column
    ridge = rng.uniform(0.3, 0.7, count)
    slope = rng.uniform(0.18, 0.45, count)
    depth = rng.uniform(-0.1, 0.04, count)
    spacing = rng.uniform(0.35, 0.95, count)
    phase = rng.uniform(0, 1, count)
    tilt = rng.normal(scale=0.12, size=count)
    t = ys / spacing[idx] + phase[idx] + tilt[idx] * (u - 0.5) * w[idx] / spacing[idx]
    seg = np.floor(t).astype(np.int64)
    frac = t - seg
    table = rng.random(8192)
    key = (idx * 977 + seg * 131) % 8192
    seg_off = (table[key] - 0.5) * 0.06
    faces = depth[idx] + seg_off - slope[idx] * np.abs(u - ridge[idx]) * w[idx]
    side = np.minimum(u, 1.0 - u) * w[idx]  # m to the column's edge
    vertical = 1.0 - smoothstep(0.0, 0.012, side)
    across = 1.0 - smoothstep(0.0, 0.025, np.minimum(frac, 1.0 - frac) * spacing[idx])
    # Faces left and right of the ridge catch the light differently: tone them apart a little too.
    facet = np.where(u < ridge[idx], 0.0, 1.0)
    tone = 0.5 * table[(key * 7 + 3) % 8192] + 0.3 * table[(idx * 31) % 8192] + 0.2 * facet
    height = faces - vertical * 0.05 - across * 0.03
    return {"height": height, "joint": np.maximum(vertical, across * 0.8), "tone": tone}


def ash_rock(rng: np.random.Generator) -> float:
    """Ash fields cliff (a wall, image up = world up): black-grey basalt in bands, colonnades of vertical hexagonal
    columns between rough vesicular flow layers, a little rust-red oxidation, pale ash lodged on the ledges."""
    tile = 8.0
    xs, ys = coords(tile)
    # Bands: flow layers (thin, rough) between colonnades (thick), thicknesses scaled to fill the tile.
    kinds = ["flow", "columns", "flow", "flow", "columns", "flow"]
    thick = np.array([rng.uniform(0.3, 0.8) if k == "flow" else rng.uniform(1.8, 2.8) for k in kinds])
    bounds = np.concatenate([[0.0], np.cumsum(thick * tile / thick.sum())])
    warped = (ys + 0.07 * blobs(rng, tile, 3.0) + 0.02 * blobs(rng, tile, 0.5)) % tile
    band = np.clip(np.searchsorted(bounds, warped, side="right") - 1, 0, len(kinds) - 1)
    is_col = np.isin(band, [i for i, k in enumerate(kinds) if k == "columns"])
    recess = rng.uniform(-0.08, 0.04, len(kinds))
    height = np.zeros_like(xs)
    joint = np.zeros_like(xs)
    tone = np.zeros_like(xs)
    for i, k in enumerate(kinds):
        if k != "columns":
            continue
        cols = _columns(rng, tile, xs, warped, rng.uniform(-0.03, 0.03))
        mask = band == i
        height[mask] = cols["height"][mask] + recess[i]
        joint[mask] = cols["joint"][mask]
        tone[mask] = cols["tone"][mask]
    # Flow layers: lumpy, rubbly (autobreccia: blocks of their own height), faint banding along the flow.
    f1, f2, cell = voronoi(
        rng, 70, stretch=(1.0, 1.6), warp=(0.01 * blobs(rng, tile, 0.6), 0.01 * blobs(rng, tile, 0.6))
    )
    block = rng.uniform(-0.04, 0.04, cell.max() + 1)[cell] * smoothstep(0.0, 0.01, f2 - f1)
    banding = streaks(rng, tile, 2.0, 0.04, 0.0)
    flow = 0.03 * blobs(rng, tile, 0.15, 3) + block + 0.008 * banding - 0.06
    flow_tone = 0.5 + 0.25 * blobs(rng, tile, 0.5) + 0.15 * banding
    flow_mask = ~is_col
    height[flow_mask] = flow[flow_mask] + recess[band[flow_mask]]
    tone[flow_mask] = np.clip(flow_tone[flow_mask], 0, 1)
    joint[flow_mask] = (1.0 - smoothstep(0.0, 0.004, f2 - f1))[flow_mask] * 0.6
    # Soften the band edges a little (a step of a few cm stays), add the cliff's large bulges and erosion.
    k = np.fft.fftfreq(SIZE, d=tile / SIZE)
    soft = np.exp(-(k[None, :] ** 2 + k[:, None] ** 2) * 0.012**2 * 2.0)
    height = np.fft.ifft2(np.fft.fft2(height) * soft).real
    height = height + 0.15 * blobs(rng, tile, 3.0) + 0.012 * blobs(rng, tile, 0.3, 3)
    ledge = -np.gradient(height, axis=0) * SIZE / tile  # facing up (+Y) on the wall
    gate = smoothstep(-0.6, 0.6, blobs(rng, tile, 0.8)) * np.where(flow_mask, 0.6, 1.0)
    ash = np.clip(smoothstep(0.3, 0.9, ledge) * gate, 0, 1)
    # Oxidation: faint rust-red stains running down the face, mostly on the flow layers.
    rust = streaks(rng, tile, 0.7, 0.1, math.pi / 2) + 0.6 * blobs(rng, tile, 1.0) + 0.5 * flow_mask
    rust = smoothstep(1.2, 2.2, rust)
    flow_s_map = flow_mask.astype(float)

    n = Nodes("Basalt", tile)
    tone_s = n.scalar(float_image("tone", tone))
    joint_s = n.scalar(float_image("joints", np.clip(joint, 0, 1)))
    ash_s = n.scalar(float_image("ash", ash))
    rust_s = n.scalar(float_image("rust", rust))
    flow_s = n.scalar(float_image("flow", flow_s_map))
    grain = n.noise(45.0, 5.0, 0.65)
    mottle = n.noise(2.0, 3.0, 0.6)
    holes = n.math("MULTIPLY", pits(n, 28.0, 0.3), n.math("MULTIPLY_ADD", flow_s, 0.8, c=0.2))
    rock = n.mix(
        n.math("ADD", tone_s, n.math("MULTIPLY", mottle, 0.05)), srgb(0.1, 0.1, 0.106), srgb(0.19, 0.186, 0.185)
    )
    rock = n.mix(n.unit(grain, 0.15), srgb(0.1, 0.1, 0.104), rock)
    rock = n.mix(n.math("MULTIPLY", rust_s, 0.5), rock, srgb(0.2, 0.13, 0.1))
    color = n.mix(n.math("MULTIPLY", holes, 0.8), rock, srgb(0.04, 0.038, 0.038))
    color = n.mix(n.math("MULTIPLY", joint_s, 0.85), color, srgb(0.045, 0.043, 0.042))
    color = n.mix(n.math("MULTIPLY", ash_s, 0.8), color, srgb(0.29, 0.28, 0.27))
    rough = n.lerp(ash_s, n.lerp(n.unit(grain), 0.82, 0.95), 0.98)
    detail = n.math("SUBTRACT", n.math("MULTIPLY", grain, 0.0015), n.math("MULTIPLY", holes, 0.006))
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


LAYERS = {
    "ash_ground": ash_ground,
    "ash_scree": ash_scree,
    "ash_rock": ash_rock,
}
