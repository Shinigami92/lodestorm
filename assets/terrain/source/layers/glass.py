"""Glass plains: ground vitrified by the star's flares (dull, crazed glass pools between patches of grit), glass
scree with splinters and slag, and rock fused in layers of stone and smoky glass.

A layer module of terrain_textures.py: `LAYERS` maps each layer's name to its function, which models the tile's
geometry and materials and returns the tile's size in m (see the conventions in terrain_textures.py).
"""

import math

import numpy as np
from terrain_textures import (
    SIZE,
    Nodes,
    _mesh_object,
    _rot_x,
    _rot_y,
    _rot_z,
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

# Octahedron (tips along x, edges along y, ridge and keel along z): the template of a glass splinter.
_SPLINTER_VERTS = np.array([(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)], dtype=float)
_SPLINTER_FACES = np.array(
    [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)], dtype=np.int32
)


def splat(field: np.ndarray, tile: float, x: float, y: float, r: float, profile, aspect=(1.0, 1.0)) -> None:
    """Add `profile(d)` (d = distance from (x, y) in units of `r`, x and y stretched by `aspect`; 0 beyond 1 is up
    to the profile) to `field` in a small wrapped window around the point (bubbles, scoops)."""
    n = field.shape[0]
    px = tile / n
    reach = int(r * max(aspect) / px) + 2
    cols = np.arange(int(x / px) - reach, int(x / px) + reach + 1)
    rows = np.arange(int(y / px) - reach, int(y / px) + reach + 1)
    dx = (cols + 0.5) * px - x
    dy = (rows + 0.5) * px - y
    d = np.hypot(dx[None, :] / aspect[0], dy[:, None] / aspect[1]) / r
    field[np.ix_(rows % n, cols % n)] += profile(d)


def splinters(
    rng: np.random.Generator,
    name: str,
    tile: float,
    ground: np.ndarray,
    count: int,
    length: tuple[float, float],
    mat,
    width: tuple[float, float] = (0.12, 0.35),
    sink: float = 0.35,
    where=None,
):
    """`count` sharp glass splinters (log-uniform length; skewed, flattened octahedra: two points, a keel and a
    ridge) lying on `ground`, partly sunk. `where(x, y)` -> 0..1 thins them out."""
    all_verts, all_faces, rand = [], [], []
    made = 0
    tries = 0
    while made < count and tries < count * 20:
        tries += 1
        x, y = rng.uniform(0, tile, 2)
        if where is not None and rng.random() > where(x, y):
            continue
        made += 1
        size = math.exp(rng.uniform(math.log(length[0]), math.log(length[1])))
        w = size * rng.uniform(*width)
        t = w * rng.uniform(0.35, 0.7)
        v = _SPLINTER_VERTS * np.array([size / 2, w / 2, t / 2])
        v[0, 0] *= rng.uniform(0.6, 1.0)  # uneven points
        v[1, 0] *= rng.uniform(0.3, 1.0)
        v[2:4, 0] += rng.uniform(-0.3, 0.3, 2) * size / 2  # skewed edges: no diamond symmetry
        v[4:6, 0] += rng.uniform(-0.3, 0.3, 2) * size / 2
        v[5, 2] *= 0.5
        yaw = rng.uniform(0, math.tau)
        tilt = rng.normal(scale=0.2, size=2)
        v = v @ (_rot_z(yaw) @ _rot_x(tilt[0]) @ _rot_y(tilt[1])).T
        v += np.array([x, y, sample(ground, tile, x, y) + t * (0.5 - sink)])
        all_verts.append(v)
        all_faces.append(_SPLINTER_FACES + 6 * (made - 1))
        rand.append(np.full(6, rng.random()))
    obj = _mesh_object(name, np.concatenate(all_verts), np.concatenate(all_faces), smooth=False)
    attr = obj.data.attributes.new("rand", "FLOAT", "POINT")
    attr.data.foreach_set("value", np.concatenate(rand).astype(np.float32))
    obj.data.materials.append(mat)
    return obj


def crack_lines(rng: np.random.Generator, tile: float, count: int, width: tuple[float, float], bend: float):
    """Wrapped Voronoi cell borders as 0..1 lines (`count` cells, line width in tile units between `width`'s
    values, borders bent by `bend` tile units)."""
    warp = (bend * blobs(rng, tile, 0.5, 2), bend * blobs(rng, tile, 0.5, 2))
    f1, f2, _ = voronoi(rng, count, warp=warp)
    w = width[0] + (width[1] - width[0]) * np.clip(blobs(rng, tile, 0.3) * 0.5 + 0.5, 0, 1)
    return 1.0 - smoothstep(0.0, w, f2 - f1)


def glass_material(name: str, tile: float, tones: list, rough: tuple[float, float]):
    """Smoky glass for chips and splinters: a dark grey-teal per piece, paler on its steep facets (thin edges seen
    through), a dull glaze, a faint grain."""
    s = Nodes(name, tile)
    base = s.palette(s.attribute("rand"), tones)
    grain = s.noise(70.0, 3.0, 0.6)
    color = s.mix(s.math("MULTIPLY", s.unit(grain, 0.5), 0.25), base, srgb(0.3, 0.35, 0.36))
    up = s.node("ShaderNodeSeparateXYZ", Vector=s.node("ShaderNodeNewGeometry").outputs["Normal"]).outputs["Z"]
    color = s.mix(s.math("MULTIPLY", s.ramp(up, 0.85, 0.4), 0.7), color, srgb(0.42, 0.5, 0.52))
    return s.finish(color, s.lerp(s.unit(grain, 0.2), rough[0], rough[1]), s.math("MULTIPLY", grain, 0.0002))


GLASS_TONES = [(0.16, 0.2, 0.21), (0.22, 0.27, 0.28), (0.19, 0.22, 0.22), (0.27, 0.32, 0.33), (0.14, 0.17, 0.18)]
# Loose chips and splinters: mostly pale (thin glass), some smoky.
CHIP_TONES = [(0.38, 0.45, 0.47), (0.3, 0.36, 0.37), (0.2, 0.24, 0.25), (0.46, 0.52, 0.53), (0.27, 0.31, 0.32)]


def glass_ground(rng: np.random.Generator) -> float:
    """Glass plains: a fused crust of dull, sand-blasted grey-teal glass pools, crazed by fine crack networks, with
    frozen bubbles and flow ripples, between dull patches of unfused grit; tiny glass chips everywhere."""
    tile = 6.0
    # Glass pools: the crust's bulk, a few mm proud of the grit, ragged at the edges, broken into plates by
    # shrinkage cracks that grit has filled.
    pools = blobs(rng, tile, 1.6, 2, 0.35) + 0.15 * blobs(rng, tile, 0.2)
    gaps = crack_lines(rng, tile, 12, (0.002, 0.006), 0.012)
    glass = smoothstep(-0.6, -0.2, pools) * (1.0 - gaps)
    rim = glass * (1.0 - glass) * 4.0
    base = 0.025 * blobs(rng, tile, 1.6, 3)
    grit = 0.0025 * blobs(rng, tile, 0.04, 2)
    height = base + 0.006 * glass
    # Flow ripples: contour lines of a smooth field, like frozen lobes of melt, only in some pools.
    flow = blobs(rng, tile, 1.2, 2, 0.4)
    flowing = smoothstep(0.0, 1.0, blobs(rng, tile, 1.0))
    ripples = np.sin(math.tau * flow * 4.0) * 0.001 * glass * flowing
    # Crazing: a coarse network of cracks and a fine one, denser in some pools.
    cracks_big = crack_lines(rng, tile, 120, (0.0012, 0.0022), 0.004) * glass
    dense = smoothstep(-0.3, 0.8, blobs(rng, tile, 0.8))
    cracks_fine = crack_lines(rng, tile, 420, (0.0008, 0.0013), 0.002) * glass * dense
    cracks = np.maximum(cracks_big, 0.55 * cracks_fine)
    # Frozen bubbles: little domes, some burst into pits with a rim.
    bubbles = np.zeros((SIZE, SIZE))
    pits = np.zeros((SIZE, SIZE))
    for _ in range(700):
        x, y = rng.uniform(0, tile, 2)
        if rng.random() > sample(glass, tile, x, y):
            continue
        r = math.exp(rng.uniform(math.log(0.004), math.log(0.03)))
        if rng.random() < 0.35:
            splat(pits, tile, x, y, r, lambda d: np.where(d < 1.0, 1.0 - d * d, 0.0))
            splat(
                bubbles,
                tile,
                x,
                y,
                r,
                lambda d, r=r: -r * 0.5 * np.clip(1.0 - d * d, 0, 1) + r * 0.15 * np.exp(-((d - 1.05) ** 2) * 40),
            )
        else:
            splat(bubbles, tile, x, y, r, lambda d, r=r: r * 0.35 * np.sqrt(np.clip(1.0 - d * d, 0, 1)))
    fine = ripples + grit * (1.0 - glass) + bubbles - cracks * 0.0015
    tone = blobs(rng, tile, 0.5, 3, 0.6)
    # Smoky streaks in the glass, drawn along the melt's flow.
    swirl = 0.35 * smoothstep(0.4, 1.0, np.sin(math.tau * (flow * 2.0 + 0.25 * blobs(rng, tile, 0.4))) * 0.5 + 0.5)
    film = smoothstep(0.4, 1.4, blobs(rng, tile, 0.6, 2))  # dust settled on the glass: duller
    grit_dark = specks(rng, tile, 0.01, 0.04)
    grit_light = specks(rng, tile, 0.006, 0.025)

    n = Nodes("GlassCrust", tile)
    glass_s = n.scalar(float_image("glass", glass))
    rim_s = n.scalar(float_image("rim", rim))
    crack_s = n.scalar(float_image("cracks", cracks))
    pit_s = n.scalar(float_image("pits", np.clip(pits, 0, 1)))
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    swirl_s = n.scalar(float_image("swirl", swirl))
    film_s = n.scalar(float_image("film", film))
    gdark_s = n.scalar(float_image("grit_dark", grit_dark))
    glight_s = n.scalar(float_image("grit_light", grit_light))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(80.0, 3.0, 0.7)
    smoke = n.math("MAXIMUM", n.ramp(tone_s, 0.45, 0.8), n.math("MULTIPLY", swirl_s, 0.7))
    glass_color = n.mix(smoke, srgb(0.33, 0.36, 0.365), srgb(0.25, 0.28, 0.29))
    glass_color = n.mix(n.math("MULTIPLY", rim_s, 0.3), glass_color, srgb(0.35, 0.38, 0.385))
    glass_color = n.mix(n.math("MULTIPLY", film_s, 0.55), glass_color, srgb(0.33, 0.35, 0.35))
    grit_color = n.mix(n.unit(grain, 0.18), srgb(0.31, 0.315, 0.31), srgb(0.37, 0.375, 0.37))
    grit_color = n.mix(n.math("MULTIPLY", gdark_s, 0.5), grit_color, srgb(0.24, 0.26, 0.26))
    grit_color = n.mix(n.math("MULTIPLY", glight_s, 0.4), grit_color, srgb(0.48, 0.5, 0.49))
    color = n.mix(glass_s, grit_color, glass_color)
    color = n.mix(n.math("MULTIPLY", crack_s, 0.5), color, srgb(0.4, 0.44, 0.45))
    color = n.mix(n.math("MULTIPLY", pit_s, 0.45), color, srgb(0.15, 0.17, 0.175))
    # A dull, sand-blasted glaze, not a mirror (sharp sky glints all over the ground outshone the ores).
    glass_rough = n.lerp(n.unit(grain, 0.15), 0.45, 0.55)
    glass_rough = n.lerp(film_s, glass_rough, 0.68)
    glass_rough = n.lerp(n.math("MULTIPLY", crack_s, 0.8), glass_rough, 0.7)
    rough = n.lerp(glass_s, n.lerp(n.unit(grain, 0.1), 0.88, 0.95), glass_rough)
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, n.lerp(glass_s, 0.0005, 0.00005)))
    crust_mat = n.finish(color, rough, detail, ao_distance=0.08)

    chip_mat = glass_material("GlassChip", tile, CHIP_TONES, (0.4, 0.55))
    s = Nodes("GlassSlag", tile)
    slag = s.palette(s.attribute("rand"), [(0.2, 0.2, 0.2), (0.27, 0.26, 0.25), (0.16, 0.17, 0.17), (0.31, 0.3, 0.29)])
    speck = s.noise(60.0, 4.0, 0.6)
    slag_mat = s.finish(
        s.mix(s.ramp(speck, 0.6, 2.0), slag, srgb(0.12, 0.12, 0.12)), 0.75, s.math("MULTIPLY", speck, 0.0004)
    )

    ground_grid(height, tile, crust_mat)
    splinters(rng, "Chips", tile, height, 700, (0.012, 0.07), chip_mat)
    placed: list = []
    kw = dict(flat=(0.4, 0.75), sink=0.3, cuts=3, lumps=0.2, smooth=True)
    grit_only = lambda x, y: 1.0 - sample(glass, tile, x, y)
    stones(rng, "Slag", tile, height, 160, (0.01, 0.04), slag_mat, others=placed, where=grit_only, **kw)
    return tile


def glass_scree(rng: np.random.Generator) -> float:
    """Glass plains scree: glass chips, splinters and fused slag lumps on gritty ground (cliff feet, patches)."""
    tile = 4.0
    height = 0.035 * blobs(rng, tile, 1.0, 2)
    tone = blobs(rng, tile, 0.25, 2)
    sand = blobs(rng, tile, 0.012)  # coarse grit grains
    melt = smoothstep(1.5, 2.0, blobs(rng, tile, 0.35, 2))  # a few small fused puddles

    n = Nodes("GlassGrit", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.12 + 0.5))
    sand_s = n.scalar(float_image("sand", sand * 0.2 + 0.5))
    melt_s = n.scalar(float_image("melt", melt))
    grain = n.noise(90.0, 3.0, 0.7)
    color = n.mix(n.ramp(tone_s, 0.3, 0.7), srgb(0.3, 0.305, 0.3), srgb(0.36, 0.365, 0.36))
    color = n.mix(n.ramp(sand_s, 0.3, 0.7), srgb(0.23, 0.24, 0.24), color)
    color = n.mix(n.math("MULTIPLY", n.ramp(sand_s, 0.72, 0.85), 0.7), color, srgb(0.5, 0.52, 0.51))
    color = n.mix(melt_s, color, srgb(0.2, 0.24, 0.25))
    rough = n.lerp(melt_s, 0.94, 0.5)
    fine = n.math("ADD", n.math("MULTIPLY", grain, 0.0004), n.math("MULTIPLY", sand_s, 0.004))
    grit_mat = n.finish(color, rough, fine, ao_distance=0.1)

    chip_mat = glass_material("ScreeGlass", tile, CHIP_TONES, (0.4, 0.55))
    s = Nodes("ScreeSlag", tile)
    slag = s.palette(
        s.attribute("rand"),
        [(0.27, 0.27, 0.26), (0.35, 0.34, 0.33), (0.22, 0.23, 0.23), (0.4, 0.39, 0.37), (0.3, 0.32, 0.32)],
    )
    speck = s.noise(50.0, 4.0, 0.6)
    pores = s.ramp(s.noise(30.0, 2.0, 0.5), 0.9, 2.2)  # vesicles: dark pits
    color = s.mix(s.math("MULTIPLY", pores, 0.8), slag, srgb(0.08, 0.08, 0.08))
    glaze = s.ramp(s.noise(6.0, 2.0), 0.4, 1.3)  # glassy skin on parts of the lumps
    color = s.mix(s.math("MULTIPLY", glaze, 0.6), color, srgb(0.17, 0.2, 0.21))
    slag_mat = s.finish(
        color,
        s.lerp(glaze, 0.8, 0.5),
        s.math("SUBTRACT", s.math("MULTIPLY", speck, 0.0005), s.math("MULTIPLY", pores, 0.002)),
    )

    ground_grid(height, tile, grit_mat)
    placed: list = []
    stones(
        rng,
        "Lumps",
        tile,
        height,
        22,
        (0.07, 0.14),
        slag_mat,
        flat=(0.45, 0.75),
        sink=0.3,
        cuts=2,
        lumps=0.25,
        smooth=True,
        spacing=1.2,
        others=placed,
    )
    stones(
        rng,
        "Chunks",
        tile,
        height,
        40,
        (0.04, 0.09),
        chip_mat,
        flat=(0.35, 0.6),
        sink=0.25,
        cuts=7,
        spacing=1.0,
        others=placed,
    )
    stones(
        rng,
        "Clinker",
        tile,
        height,
        260,
        (0.012, 0.04),
        slag_mat,
        flat=(0.4, 0.8),
        sink=0.25,
        cuts=3,
        lumps=0.2,
        spacing=0.9,
        others=placed,
    )
    splinters(rng, "Splinters", tile, height, 800, (0.025, 0.18), chip_mat)
    splinters(rng, "Flakes", tile, height, 1400, (0.006, 0.025), chip_mat, width=(0.3, 0.6))
    return tile


def glass_rock(rng: np.random.Generator) -> float:
    """Glass plains cliff (a wall, image up = world up): rock fused in layers, rough grey stone strata with lenses
    of dull smoky glass between them that swell and pinch out, glass running down the face from the lenses in
    drips and curtains, conchoidal fracture scoops in the glass."""
    tile = 8.0
    _xs, ys = coords(tile)
    px = tile / SIZE
    s_px = (np.arange(SIZE) + 0.5) * px
    f = np.fft.fftfreq(SIZE, d=px)
    # Stone strata in "strata space" (rows: s, the height along the strata; warped onto the image below).
    bounds = [0.0]
    while bounds[-1] < tile - 0.3:
        bounds.append(bounds[-1] + rng.uniform(0.12, 0.7))
    bounds[-1] = tile
    bands = len(bounds) - 1
    recess = rng.uniform(0.0, 0.08, bands) * (rng.random(bands) < 0.6)
    shade = rng.random(bands)
    band_of = np.searchsorted(bounds, s_px, side="right") - 1
    profile = np.fft.ifft(np.fft.fft(-recess[band_of]) * np.exp(-((f * 0.04) ** 2) * 2)).real
    stone = np.repeat(profile[:, None], SIZE, axis=1)
    # Glass lenses: a center line and a thickness that wander along x; they swell, thin and pinch out.
    lenses = []
    s0 = rng.uniform(0, tile)
    for k in range(10):
        c = (s0 + k * tile / 10 + rng.uniform(-0.2, 0.2)) % tile
        th = math.exp(rng.uniform(math.log(0.025), math.log(0.2)))
        along = blobs(rng, tile, 1.4, 2, 0.4)[0]
        half = th * np.clip(0.85 + 0.5 * along, 0.0, 1.5)
        center = c + 0.3 * th * blobs(rng, tile, 1.5)[0]
        lenses.append((center, half, rng.uniform(-0.01, 0.025)))
    glass_map = np.zeros((SIZE, SIZE))
    lens_relief = np.zeros((SIZE, SIZE))
    rim = np.zeros((SIZE, SIZE))
    for center, half, rel in lenses:
        ds = (s_px[:, None] - center[None, :] + tile / 2) % tile - tile / 2
        d = np.abs(ds) / np.maximum(half[None, :], 1e-4)
        g = 1.0 - smoothstep(0.85, 1.0, d)
        glass_map = np.maximum(glass_map, g)
        lens_relief += rel * (1.0 - smoothstep(0.55, 1.0, d))
        rim = np.maximum(rim, np.exp(-(((d - 0.88) / 0.08) ** 2)) * (half[None, :] > 0.02))
    # Drips and curtains: glass run down from a lens' lower edge, tapering, with a bead at the end.
    drips = np.zeros((SIZE, SIZE))
    for center, half, _rel in lenses:
        for _ in range(9):
            xc = rng.uniform(0, tile)
            for _ in range(int(rng.integers(1, 7))):
                x0 = (xc + rng.normal(scale=0.12)) % tile
                h0 = half[int(x0 / px) % SIZE]
                if h0 < 0.03:
                    continue
                foot = center[int(x0 / px) % SIZE] - h0 * 0.8
                length = math.exp(rng.uniform(math.log(0.06), math.log(1.1)))
                w = rng.uniform(0.015, 0.06)
                bulge = w * rng.uniform(0.35, 0.7)
                wander = rng.uniform(-0.05, 0.05)
                rows = np.arange(int((foot - length - w) / px), int((foot + h0 * 0.6) / px) + 1)
                s = (rows + 0.5) * px
                t = np.clip((foot - s) / length, 0, 1)  # 0 at the lens, 1 at the tip
                mid = x0 + wander * t * t
                wide = w * (1.0 - 0.55 * t) + w * 0.8 * np.exp(-(((t - 0.95) / 0.05) ** 2))
                cols = np.arange(int((x0 - 2 * w - 0.06) / px), int((x0 + 2 * w + 0.06) / px) + 1)
                dx = (cols[None, :] + 0.5) * px - mid[:, None]
                across = np.clip(1.0 - (dx / wide[:, None]) ** 2, 0, 1)
                alive = (s >= foot - length - w * 0.4)[:, None]
                win = np.ix_(rows % SIZE, cols % SIZE)
                drips[win] = np.maximum(drips[win], np.sqrt(across) * bulge * alive)
    drip_mask = smoothstep(0.0, 0.004, drips)
    flow = np.sin(math.tau * (s_px[:, None] * 9.0 + 0.6 * blobs(rng, tile, 0.7))) * 0.002  # flow wrinkles
    # Onto the image: warp the strata space, then the joints and fracture scoops in image space.
    warped = (ys + 0.1 * blobs(rng, tile, 3.0) + 0.015 * blobs(rng, tile, 0.4)) % tile
    row = (warped / tile * SIZE).astype(int) % SIZE
    col = np.arange(SIZE)[None, :].repeat(SIZE, axis=0)
    stone, glass_map, lens_relief, rim, drips, drip_mask, flow = (
        a[row, col] for a in (stone, glass_map, lens_relief, rim, drips, drip_mask, flow)
    )
    band_shade = shade[band_of[row]]
    glassy = np.maximum(glass_map, drip_mask)
    bend = (0.01 * blobs(rng, tile, 0.6, 2), 0.004 * blobs(rng, tile, 0.6, 2))
    f1, f2, _ = voronoi(rng, 14, stretch=(1.0, 0.3), warp=bend)
    joints = (1.0 - smoothstep(0.0, 0.0018, f2 - f1)) * (1.0 - glassy)
    scoops = np.zeros((SIZE, SIZE))
    edges = np.zeros((SIZE, SIZE))
    for _ in range(160):
        x, y = rng.uniform(0, tile, 2)
        if rng.random() > sample(glass_map, tile, x, y):
            continue
        r = math.exp(rng.uniform(math.log(0.04), math.log(0.2)))
        aspect = (rng.uniform(1.0, 1.8), rng.uniform(0.5, 0.8))
        depth = r * rng.uniform(0.08, 0.15)
        splat(
            scoops,
            tile,
            x,
            y,
            r,
            lambda d, depth=depth: np.where(d < 1, -depth * (1 - d * d) * (1 + 0.1 * np.sin(d * 30)), 0.0),
            aspect,
        )
        splat(edges, tile, x, y, r, lambda d: np.exp(-(((d - 1.0) / 0.07) ** 2)), aspect)
    bulge = 0.14 * blobs(rng, tile, 3.0) + 0.03 * blobs(rng, tile, 0.8, 2)
    erosion = 0.025 * blobs(rng, tile, 0.2, 3)
    rock = stone + erosion - joints * 0.05
    height = bulge + rock * (1.0 - glass_map) + lens_relief + drips + scoops * glass_map
    lamination = np.sin(math.tau * 180 * warped / tile) * 0.0015
    fine = (lamination + 0.003 * blobs(rng, tile, 0.05)) * (1.0 - glassy) + flow * glass_map - joints * 0.004
    dark = smoothstep(0.02, 0.07, -stone) * (1.0 - glassy)

    n = Nodes("FusedRock", tile)
    shade_s = n.scalar(float_image("shade", band_shade))
    glass_s = n.scalar(float_image("glassy", glassy))
    joint_s = n.scalar(float_image("joints", joints))
    dark_s = n.scalar(float_image("recess", dark))
    edge_s = n.scalar(float_image("edges", np.clip(np.maximum(edges * glass_map, rim), 0, 1)))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(40.0, 5.0, 0.65)
    mottle = n.noise(2.5, 3.0, 0.6)
    color = n.palette(
        n.math("ADD", shade_s, n.math("MULTIPLY", mottle, 0.04)),
        [(0.3, 0.305, 0.3), (0.36, 0.36, 0.35), (0.26, 0.27, 0.27), (0.39, 0.39, 0.38), (0.32, 0.32, 0.31)],
    )
    color = n.mix(n.math("MULTIPLY", dark_s, 0.45), color, srgb(0.18, 0.19, 0.19))
    color = n.mix(n.math("MULTIPLY", n.ramp(grain, 0.5, 2.0), 0.4), color, srgb(0.2, 0.21, 0.21))
    smoke = n.mix(n.unit(mottle, 0.3), srgb(0.12, 0.15, 0.16), srgb(0.2, 0.24, 0.25))
    smoke = n.mix(n.math("MULTIPLY", edge_s, 0.5), smoke, srgb(0.33, 0.38, 0.39))
    color = n.mix(glass_s, color, smoke)
    color = n.mix(n.math("MULTIPLY", joint_s, 0.7), color, srgb(0.12, 0.12, 0.12))
    rough = n.lerp(glass_s, n.lerp(n.unit(grain), 0.84, 0.96), n.lerp(n.unit(mottle, 0.3), 0.42, 0.55))
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, n.lerp(glass_s, 0.0015, 0.0001)))
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


LAYERS = {
    "glass_ground": glass_ground,
    "glass_scree": glass_scree,
    "glass_rock": glass_rock,
}
