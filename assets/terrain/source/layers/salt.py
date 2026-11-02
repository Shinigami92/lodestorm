"""Salt pans: polygonal salt crust with pressure ridges, broken crust scree, layered evaporite cliffs.

A layer module of terrain_textures.py: `LAYERS` maps each layer's name to its function, which models the tile's
geometry and materials and returns the tile's size in m (see the conventions in terrain_textures.py).
"""

import math

import numpy as np
from terrain_textures import (
    Nodes,
    _mesh_object,
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


def _ridged_crust(
    rng: np.random.Generator,
    tile: float,
    cells: int,
    ridge_h: float,
    ridge_w: float,
    knob_k: float = 0.3,
    crack_k: float = 0.6,
):
    """Polygonal salt crust: `cells` plates (wrapped Voronoi, edges bent a little) whose rims are pushed up into
    ridges about `ridge_h` m high and `ridge_w` m wide, split along their crest by a thin crack, the plates' middles
    dished a little, crystal knobs crowding the ridges (`knob_k`, `crack_k`: their height and the crack's depth
    relative to the ridge). Returns (height, distance to the nearest rim in m, ridge
    0..1, crest crack 0..1, cell index)."""
    bend = (0.01 * blobs(rng, tile, 0.7, 2), 0.01 * blobs(rng, tile, 0.7, 2))
    f1, f2, cell = voronoi(rng, cells, warp=bend)
    rim = (f2 - f1) * tile / 2  # about the distance to the plate's edge, in m
    along = blobs(rng, tile, 0.5, 2)  # the ridges rise and fall along their length
    height_k = ridge_h * np.clip(0.8 + 0.35 * along, 0.4, 1.4)
    width = ridge_w * np.clip(0.85 + 0.3 * blobs(rng, tile, 0.4), 0.5, 1.5)
    ridge = np.exp(-((rim / width) ** 2))
    knobs = smoothstep(0.3, 1.6, blobs(rng, tile, 0.025, 2)) * np.exp(-((rim / (width * 2.2)) ** 2))
    crack_w = 0.004 + 0.004 * (blobs(rng, tile, 0.3) * 0.5 + 0.5).clip(0, 1)
    crack = (1.0 - smoothstep(0.0, crack_w, rim)) * smoothstep(-1.4, -0.4, along)
    dish = -0.012 * smoothstep(0.05, 0.6, rim)
    height = height_k * ridge + knobs * ridge_h * knob_k + dish - crack * ridge_h * crack_k
    return height, rim, np.maximum(ridge, knobs * 0.7), crack, cell


def salt_ground(rng: np.random.Generator) -> float:
    """Salt pans: white-grey salt crust broken into polygonal plates with raised, ridged rims, a faint dusty
    grey-brown film in the plates' middles, fine crystalline grain and a few grey pebbles."""
    tile = 6.0
    height = 0.02 * blobs(rng, tile, 1.5, 2)
    # Big plates, low soft ridges: from the game camera a calm polygon network, not a crinkle.
    crust, rim, ridge, crack, cell = _ridged_crust(rng, tile, 12, 0.022, 0.1, knob_k=0.12, crack_k=0.2)
    # Faint second generation of thin cracks inside the plates (not raised).
    bend = (0.012 * blobs(rng, tile, 0.4, 2), 0.012 * blobs(rng, tile, 0.4, 2))
    g1, g2, _ = voronoi(rng, 90, warp=bend)
    fine_mask = 0.4 * smoothstep(0.4, 1.0, blobs(rng, tile, 0.8))
    fine_cracks = (1.0 - smoothstep(0.0, 0.0012, g2 - g1)) * fine_mask * smoothstep(0.05, 0.12, rim)
    lumps = 0.0015 * blobs(rng, tile, 0.08, 2) + 0.0007 * blobs(rng, tile, 0.02)
    height = height + crust + lumps - fine_cracks * 0.002
    film = smoothstep(0.15, 0.6, rim) * smoothstep(-0.8, 0.6, blobs(rng, tile, 0.6, 2))
    plate_tone = np.random.default_rng(int(rng.integers(1 << 30))).random(cell.max() + 1)[cell]
    tone = blobs(rng, tile, 0.4, 3, 0.6)
    dark = specks(rng, tile, 0.006, 0.02)
    bright = specks(rng, tile, 0.004, 0.03)

    n = Nodes("SaltCrust", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    film_s = n.scalar(float_image("film", film))
    plate_s = n.scalar(float_image("plates", plate_tone))
    ridge_s = n.scalar(float_image("ridge", ridge))
    crack_s = n.scalar(float_image("crack", np.maximum(crack, fine_cracks * 0.6)))
    dark_s = n.scalar(float_image("dark", dark))
    bright_s = n.scalar(float_image("bright", bright))
    grain = n.noise(140.0, 3.0, 0.75)
    salt = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.48, 0.49, 0.49), srgb(0.535, 0.54, 0.54))
    salt = n.mix(n.math("MULTIPLY", plate_s, 0.5), salt, srgb(0.505, 0.51, 0.51))
    salt = n.mix(n.unit(grain, 0.12), srgb(0.45, 0.455, 0.455), salt)
    color = n.mix(n.math("MULTIPLY", film_s, 0.45), salt, srgb(0.44, 0.435, 0.425))
    color = n.mix(n.math("MULTIPLY", ridge_s, 0.6), color, srgb(0.60, 0.605, 0.61))
    color = n.mix(n.math("MULTIPLY", dark_s, 0.6), color, srgb(0.30, 0.29, 0.27))
    color = n.mix(n.math("MULTIPLY", bright_s, 0.6), color, srgb(0.70, 0.70, 0.69))
    color = n.mix(n.math("MULTIPLY", crack_s, 0.5), color, srgb(0.32, 0.32, 0.32))
    rough = n.lerp(film_s, n.lerp(n.unit(grain), 0.92, 0.96), 0.96)  # the ridges as matte as the plates
    detail = n.math("MULTIPLY", grain, 0.0003)
    crust_mat = n.finish(color, rough, detail, bump=0.5, ao_distance=0.15)

    s = Nodes("SaltPebble", tile)
    base = s.palette(
        s.attribute("rand"),
        [(0.36, 0.36, 0.35), (0.42, 0.41, 0.39), (0.31, 0.31, 0.31), (0.47, 0.45, 0.42), (0.38, 0.36, 0.33)],
    )
    speck = s.noise(60.0, 4.0, 0.6)
    color = s.mix(s.ramp(speck, 0.5, 2.0), base, srgb(0.24, 0.24, 0.23))
    crusted = s.ramp(s.noise(12.0, 2.0), 0.4, 1.4)
    color = s.mix(s.math("MULTIPLY", crusted, 0.7), color, srgb(0.58, 0.58, 0.565))
    pebble_mat = s.finish(color, s.lerp(crusted, 0.78, 0.93), s.math("MULTIPLY", speck, 0.0005), ao_distance=0.1)

    ground_grid(height, tile, crust_mat)
    placed: list = []
    kw = dict(flat=(0.45, 0.8), sink=0.3, cuts=5)
    stones(rng, "Stones", tile, height, 12, (0.035, 0.07), pebble_mat, spacing=1.5, others=placed, **kw)
    stones(rng, "Pebbles", tile, height, 140, (0.008, 0.025), pebble_mat, others=placed, **kw)
    return tile


def _rotation(axis: np.ndarray, angle: float) -> np.ndarray:
    """Rotation matrix about a unit `axis` by `angle` (Rodrigues)."""
    x, y, z = axis
    k = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return np.eye(3) + math.sin(angle) * k + (1 - math.cos(angle)) * (k @ k)


def crust_plates(
    rng: np.random.Generator,
    name: str,
    tile: float,
    ground: np.ndarray,
    count: int,
    radius: tuple[float, float],
    thick: tuple[float, float],
    tilt: tuple[float, float],
    mat,
    others: list | None = None,
    spacing: float = 0.75,
):
    """`count` broken crust plates: thin irregular polygon slabs (log-uniform radius), tilted up by `tilt` degrees
    around a random horizontal axis with their low edge buried in `ground`, kept apart like stones()."""
    placed = others if others is not None else []
    all_verts, all_faces, rand = [], [], []
    offset = 0
    made = tries = 0
    while made < count and tries < count * 30:
        tries += 1
        r = math.exp(rng.uniform(math.log(radius[0]), math.log(radius[1])))
        x, y = rng.uniform(0, tile, 2)
        if placed:
            p = np.array(placed)
            dx = np.abs(p[:, 0] - x)
            dy = np.abs(p[:, 1] - y)
            d = np.hypot(np.minimum(dx, tile - dx), np.minimum(dy, tile - dy))
            if np.any(d < (p[:, 2] + r) * spacing):
                continue
        placed.append((x, y, r))
        made += 1
        sides = int(rng.integers(5, 9))
        ang = np.sort(rng.uniform(0, math.tau, sides))
        rad = r * rng.uniform(0.72, 1.0, sides)
        ring = np.stack([np.cos(ang) * rad, np.sin(ang) * rad * rng.uniform(0.7, 1.0)], axis=1)
        t = rng.uniform(*thick) * (r / radius[1]) ** 0.3
        top = np.column_stack([ring, np.full(sides, t / 2)])
        bottom = np.column_stack([ring * 0.97, np.full(sides, -t / 2)])
        v = np.concatenate([top, bottom, [[0, 0, t / 2], [0, 0, -t / 2]]])
        faces = []
        for i in range(sides):
            j = (i + 1) % sides
            faces += [(2 * sides, i, j), (2 * sides + 1, sides + j, sides + i), (i, sides + i, sides + j)]
            faces.append((i, sides + j, j))
        a = rng.uniform(0, math.tau)
        axis = np.array([math.cos(a), math.sin(a), 0.0])
        lean = math.radians(rng.uniform(*tilt))
        v = v @ _rotation(axis, lean).T @ _rotation(np.array([0.0, 0.0, 1.0]), rng.uniform(0, math.tau)).T
        v += np.array([x, y, sample(ground, tile, x, y) + math.sin(lean) * r * rng.uniform(0.05, 0.35)])
        all_verts.append(v)
        all_faces.append(np.array(faces) + offset)
        rand.append(np.full(len(v), rng.random()))
        offset += len(v)
    obj = _mesh_object(name, np.concatenate(all_verts), np.concatenate(all_faces), smooth=False)
    attr = obj.data.attributes.new("rand", "FLOAT", "POINT")
    attr.data.foreach_set("value", np.concatenate(rand).astype(np.float32))
    obj.data.materials.append(mat)
    return obj


def _plate_material(name: str, tile: float):
    """Broken salt crust: white-grey crystalline top, grey-brown layered underside and broken edges."""
    p = Nodes(name, tile)
    geo = p.nt.nodes.new("ShaderNodeNewGeometry")
    up = p.ramp(p.node("ShaderNodeSeparateXYZ", Vector=geo.outputs["Normal"]).outputs["Z"], 0.3, 0.8)
    grain = p.noise(120.0, 3.0, 0.7)
    top = p.mix(p.attribute("rand"), srgb(0.55, 0.55, 0.535), srgb(0.65, 0.645, 0.63))
    top = p.mix(p.unit(grain, 0.15), srgb(0.44, 0.44, 0.43), top)
    under = p.mix(p.attribute("rand"), srgb(0.32, 0.30, 0.27), srgb(0.40, 0.38, 0.345))
    color = p.mix(up, under, top)
    return p.finish(color, p.lerp(up, 0.93, 0.85), p.math("MULTIPLY", grain, 0.0005), ao_distance=0.1)


def salt_scree(rng: np.random.Generator) -> float:
    """Salt pans scree: broken, upturned salt crust plates and grey pebbles on salt (cliff feet)."""
    tile = 4.0
    height = 0.03 * blobs(rng, tile, 0.9, 2)
    crust, _rim, _ridge, crack, _ = _ridged_crust(rng, tile, 30, 0.025, 0.045)
    height = height + crust
    tone = blobs(rng, tile, 0.4, 2)
    film = smoothstep(-0.2, 0.8, blobs(rng, tile, 0.5, 2))

    n = Nodes("ScreeSalt", tile)
    tone_s = n.scalar(float_image("tone", tone * 0.15 + 0.5))
    film_s = n.scalar(float_image("film", film))
    crack_s = n.scalar(float_image("crack", crack))
    grain = n.noise(130.0, 3.0, 0.7)
    color = n.mix(n.ramp(tone_s, 0.25, 0.75), srgb(0.45, 0.45, 0.44), srgb(0.52, 0.515, 0.50))
    color = n.mix(n.unit(grain, 0.15), srgb(0.41, 0.41, 0.40), color)
    color = n.mix(n.math("MULTIPLY", film_s, 0.6), color, srgb(0.37, 0.35, 0.32))
    color = n.mix(n.math("MULTIPLY", crack_s, 0.8), color, srgb(0.2, 0.19, 0.18))
    salt_mat = n.finish(color, 0.92, n.math("MULTIPLY", grain, 0.0006), ao_distance=0.1)

    plate_mat = _plate_material("CrustPlate", tile)

    s = Nodes("ScreePebble", tile)
    base = s.palette(
        s.attribute("rand"),
        [
            (0.34, 0.34, 0.33),
            (0.41, 0.40, 0.38),
            (0.29, 0.29, 0.29),
            (0.46, 0.44, 0.41),
            (0.37, 0.35, 0.32),
            (0.33, 0.33, 0.34),
        ],
    )
    speck = s.noise(50.0, 4.0, 0.6)
    color = s.mix(s.math("MULTIPLY", s.ramp(speck, 0.8, 2.2), 0.7), base, srgb(0.2, 0.2, 0.19))
    crusted = s.ramp(s.noise(10.0, 2.0), 0.5, 1.5)
    color = s.mix(s.math("MULTIPLY", crusted, 0.6), color, srgb(0.56, 0.56, 0.545))
    stone_mat = s.finish(color, s.lerp(crusted, 0.8, 0.93), s.math("MULTIPLY", speck, 0.0006), ao_distance=0.12)

    ground_grid(height, tile, salt_mat)
    placed: list = []
    crust_plates(rng, "Plates", tile, height, 40, (0.14, 0.36), (0.025, 0.05), (5, 40), plate_mat, placed, 0.75)
    crust_plates(rng, "Chips", tile, height, 170, (0.04, 0.12), (0.012, 0.025), (3, 45), plate_mat, placed, 0.8)
    kw = dict(flat=(0.5, 0.85), sink=0.25, cuts=6)
    stones(rng, "Stones", tile, height, 70, (0.03, 0.08), stone_mat, spacing=0.85, others=placed, **kw)
    stones(rng, "Gravel", tile, height, 500, (0.01, 0.03), stone_mat, spacing=0.8, others=placed, **kw)
    return tile


def salt_rock(rng: np.random.Generator) -> float:
    """Salt pans cliff (a wall, image up = world up): pale layered evaporite, thin horizontal bands of grey, buff
    and off-white, the soft bands weathered back and crusted with salt, split by a few vertical joints."""
    tile = 8.0
    _xs, ys = coords(tile)
    bounds = [0.0]
    while bounds[-1] < tile - 0.15:
        bounds.append(bounds[-1] + (rng.uniform(0.05, 0.2) if rng.random() < 0.6 else rng.uniform(0.25, 0.55)))
    bounds[-1] = tile
    bands = len(bounds) - 1
    soft = rng.random(bands) < 0.45
    recess = np.where(soft, rng.uniform(0.03, 0.09, bands), rng.uniform(0.0, 0.015, bands))
    shade = rng.random(bands)
    profile_y = np.linspace(0, tile, 4096, endpoint=False)
    band_of = np.searchsorted(bounds, profile_y, side="right") - 1
    f = np.fft.fftfreq(4096, d=tile / 4096)
    profile = np.fft.ifft(np.fft.fft(-recess[band_of]) * np.exp(-((f * 0.03) ** 2) * 2)).real
    warped = (ys + 0.08 * blobs(rng, tile, 3.0) + 0.012 * blobs(rng, tile, 0.4)) % tile
    index = (warped / tile * 4096).astype(int) % 4096
    strata = profile[index]
    band = band_of[index]
    band_shade = shade[band]
    band_soft = soft[band].astype(float)
    bend = (0.008 * blobs(rng, tile, 0.6, 2), 0.003 * blobs(rng, tile, 0.6, 2))
    f1, f2, _ = voronoi(rng, 9, stretch=(1.0, 0.25), warp=bend)
    width = 0.0009 + 0.0012 * (blobs(rng, tile, 1.0) * 0.5 + 0.5).clip(0, 1)
    joints = 1.0 - smoothstep(0.0, width, f2 - f1)
    # Salt crust growing out of the soft bands: lumpy, bright, patchy.
    efflor = band_soft * smoothstep(-1.0, 0.2, blobs(rng, tile, 0.35, 2))
    crust_lumps = efflor * (0.007 + 0.006 * blobs(rng, tile, 0.02, 2)).clip(0, None)
    lamination = np.sin(math.tau * 400 * warped / tile) * 0.0015
    bulge = 0.12 * blobs(rng, tile, 3.0) + 0.03 * blobs(rng, tile, 0.8, 2)
    erosion = 0.012 * blobs(rng, tile, 0.2, 3)
    height = bulge + strata + erosion + crust_lumps - joints * 0.05
    fine = lamination - joints * 0.004
    dark = smoothstep(0.01, 0.06, -strata) * (1.0 - efflor)

    n = Nodes("Evaporite", tile)
    shade_s = n.scalar(float_image("shade", band_shade))
    joint_s = n.scalar(float_image("joints", joints))
    dark_s = n.scalar(float_image("recess", dark))
    efflor_s = n.scalar(float_image("efflor", efflor))
    fine_s = n.scalar(float_image("fine", fine))
    grain = n.noise(60.0, 5.0, 0.65)
    mottle = n.noise(3.0, 3.0, 0.6)
    color = n.palette(
        n.math("ADD", shade_s, n.math("MULTIPLY", mottle, 0.03)),
        [
            (0.36, 0.355, 0.345),
            (0.42, 0.395, 0.355),
            (0.47, 0.465, 0.45),
            (0.33, 0.325, 0.32),
            (0.45, 0.42, 0.375),
            (0.40, 0.395, 0.385),
        ],
    )
    color = n.mix(n.math("MULTIPLY", dark_s, 0.5), color, srgb(0.24, 0.23, 0.215))
    color = n.mix(n.math("MULTIPLY", n.ramp(grain, 0.5, 2.0), 0.35), color, srgb(0.27, 0.265, 0.25))
    color = n.mix(n.math("MULTIPLY", efflor_s, 0.8), color, srgb(0.56, 0.555, 0.54))
    color = n.mix(n.math("MULTIPLY", joint_s, 0.75), color, srgb(0.15, 0.145, 0.14))
    rough = n.lerp(n.unit(grain), 0.82, 0.95)
    detail = n.math("ADD", fine_s, n.math("MULTIPLY", grain, 0.0012))
    ground_grid(height, tile, n.finish(color, rough, detail, ao_distance=0.3))
    return tile


LAYERS = {
    "salt_ground": salt_ground,
    "salt_scree": salt_scree,
    "salt_rock": salt_rock,
}
