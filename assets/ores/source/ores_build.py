"""Ore crystal clusters: per ore type two ground variants and one wall cluster (concept: ores_v1..v4).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/ores/source/ores_build.py wip r1                        # every ore, iso + hero
    tools/blender.sh assets/ores/source/ores_build.py wip r2 kyrite_a,olvane iso,miner
    tools/blender.sh assets/ores/source/ores_build.py wip r3 all types              # the "a" variants side by side
    tools/blender.sh assets/ores/source/ores_build.py final kyrite                  # one ore, for ores_bake.py
    tools/blender.sh assets/ores/source/ores_build.py sheet kyrite                  # only lineup, grid, sheet
    tools/blender.sh assets/ores/source/ores_build.py icon kyrite,olvane            # badge icons (or "all")

Everything except the icons goes to tmp/assets/ores/: "wip <tag> [ores|variants] [views]" renders quick previews into
wip/<tag>_<variant>_<view>.png (an ore id selects all its variants); "final <ore>" saves <ore>/ores_procedural.blend
(that ores_bake.py turns into the game asset), renders the final previews and a contact sheet (<ore>/sheet.png).
"icon" renders each ore's badge icon to assets/ores/icons/<ore>.png: the crystals of its "a" variant as a white
silhouette with dark facet lines on a transparent background, which the game tints in the ore's color (OreBadge).

Every ore type is a module ore_types/<id>.py with an `ORE = OreSpec(...)` (ore_geo.py): its crystal shape, how the
crystals group, the preview color and the three variants. ORDER lists them (commonest first, the order of
scenes/mining/ores/all_ores.tres); missing modules are skipped.

Each variant is a root empty Ore_<ore>_<a|b|wall> holding one rocky base mesh Base_<ore>_<variant> (baked later
into the ore's texture atlas) and the crystals as separate meshes Crystal_<ore>_<n> (numbered per ore across its
variants). The crystals only carry geometry: they share the neutral placeholder material "OreCrystal", the game
puts the ore type's glowing material on them (OreType.get_material()). Every crystal mesh has its origin at its
root, so it can be scaled down from there (e.g. when mined out).

Ground variants: origin at the ground contact point in the center of the ore node (deposit radius ~1.35 m). The
miner stands on the node (MinerMount 0.08 m up) with its drill in the center and four legs around it; ore nodes are
rotated randomly while the miner always faces the camera, so the crystals have to clear the legs at every angle:
CLEARANCE is the worst case over all leg angles (from miner_glow_build.py), crystals are scaled down until they fit.
Wall variants: crystals grow toward -Y out of a rock chunk whose flat back lies on the wall plane y = 0; origin at
the bottom center of that back face.

The game camera looks from the +X/-Y diagonal: each ore has its own silhouette there (see the type modules).
"""

import importlib
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "ores"
ICONS = ROOT / "assets" / "ores" / "icons"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import common as C
from common import T, basis, polar
from ore_geo import (
    BASE_CLEARANCE,
    CLEARANCE,
    DISC_R,
    MAX_HEIGHT,
    MAX_RADIUS,
    OreSpec,
    append_bm,
    clip_poly,
    cut,
    finish_normals,
    geode,
    rand_unit,
    rock_hull,
    slab,
    table,
    tilted,
)

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
if MODE in ("final", "sheet", "icon"):
    TAG = ""
    ONLY = ARGV[1].split(",") if len(ARGV) > 1 and ARGV[1] != "all" else None
    VIEWS = []
else:
    TAG = ARGV[1] if len(ARGV) > 1 else "r0"
    ONLY = ARGV[2].split(",") if len(ARGV) > 2 and ARGV[2] != "all" else None
    VIEWS = ARGV[3].split(",") if len(ARGV) > 3 else ["iso", "hero"]

ASSET = "Ores"
# Commonest first (common: biome ores; mid; signature: one per planet, outermost to innermost).
ORDER = (
    "kyrite",
    "olvane",
    "pallin",
    "tessar",
    "vyrel",
    "duskine",
    "halcyne",
    "ressa",
    "meridine",
    "emerin",
    "indral",
    "selyx",
    "noctile",
    "aethrine",
)


def load_types() -> dict[str, OreSpec]:
    specs = {}
    for name in ORDER:
        try:
            module = importlib.import_module(f"ore_types.{name}")
        except ModuleNotFoundError as e:
            if e.name != f"ore_types.{name}":
                raise
            continue
        specs[name] = module.ORE
    return specs


SPECS = load_types()
TYPES = tuple(SPECS)
if MODE in ("final", "sheet") and (ONLY is None or len(ONLY) != 1 or ONLY[0] not in SPECS):
    raise SystemExit(f"{MODE} takes exactly one ore id: {', '.join(TYPES)}")
VARIANT_KEYS = ("a", "b", "wall")
LAYOUT_SPACING = 3.4
PREVIEW_GLOW = 1.0
ICON_GROUP_RADIUS = 0.45  # crystals rooted this close to the tallest one make the icon (m)
LINEUP_ZOOM = 0.9  # roots are laid out on a grid in the .blend (no cross-occlusion in the AO bake)


def variant_names() -> list[str]:
    """Selected variants: ONLY lists ore ids (all their variants) or variant names (<ore>_<a|b|wall>)."""
    names = []
    for t in TYPES:
        for v in VARIANT_KEYS:
            n = f"{t}_{v}"
            if ONLY is None or n in ONLY or t in ONLY:
                names.append(n)
    return names


# --- materials --------------------------------------------------------------------------------------


def mat_rock() -> bpy.types.Material:
    """Dark, cracked rock: grey-brown blotches and grain, mineral crust near the crystals (color attribute
    "Crust": rgb = crust color, alpha = amount), dust on top faces, lighter chipped edges (Bevel node),
    dark cracks (Voronoi edges) and cavities (AO)."""
    mat, nt, bsdf = C._new_material("OreRock")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    big = C._noise(nt, 1.4, 6.0, 0.55)
    grain = C._noise(nt, 16.0, 8.0, 0.7)
    col = C._mix_color(nt, big.outputs["Fac"], (0.017, 0.016, 0.015), (0.048, 0.043, 0.038))
    col = C._mix_color(
        nt, C._math(nt, "MULTIPLY", C._ramp(nt, 0.35, 0.7, grain.outputs["Fac"]), 0.35), col, (0.068, 0.062, 0.055)
    )
    # Mineral crust around the crystal roots.
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_type = "GEOMETRY"
    attr.attribute_name = "Crust"
    crust_noise = C._noise(nt, 7.0, 5.0, 0.6)
    crust = C._math(nt, "MULTIPLY", attr.outputs["Alpha"], C._ramp(nt, 0.3, 0.6, crust_noise.outputs["Fac"]))
    col = C._mix_color(nt, crust, col, attr.outputs["Color"])
    # Dust on up-facing surfaces, broken up.
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    dust_noise = C._noise(nt, 3.5, 6.0, 0.6)
    dust = C._math(
        nt, "MULTIPLY", C._ramp(nt, 0.55, 0.95, sep.outputs["Z"]), C._ramp(nt, 0.4, 0.7, dust_noise.outputs["Fac"])
    )
    dust = C._math(nt, "MULTIPLY", dust, C._math(nt, "SUBTRACT", 1.0, crust, clamp=True))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", dust, 0.75), col, (0.078, 0.07, 0.06))
    # Chipped edges: convex edges found with the Bevel node (works on low-poly facets, unlike Pointiness).
    edge = C._ramp(nt, 0.015, 0.1, C._bevel_edge(nt, 0.02, geo))
    edge_noise = C._noise(nt, 12.0, 6.0, 0.6)
    edge = C._math(nt, "MULTIPLY", edge, C._ramp(nt, 0.4, 0.6, edge_noise.outputs["Fac"]))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", edge, 0.7), col, (0.105, 0.1, 0.094))
    # Cracks: two layers of Voronoi cell edges, slightly warped.
    warp = nt.nodes.new("ShaderNodeVectorMath")
    warp.operation = "MULTIPLY_ADD"
    warp_noise = C._noise(nt, 2.0, 3.0, 0.5)
    nt.links.new(warp_noise.outputs["Color"], warp.inputs[0])
    warp.inputs[1].default_value = (0.25, 0.25, 0.25)
    nt.links.new(coord.outputs["Object"], warp.inputs[2])
    cracks = None
    for scale, width, weight in ((2.6, 0.025, 1.0), (7.0, 0.02, 0.35)):
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = scale
        nt.links.new(warp.outputs["Vector"], vor.inputs["Vector"])
        c = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.0, width, vor.outputs["Distance"]))
        cracks = c if cracks is None else C._math(nt, "MAXIMUM", cracks, C._math(nt, "MULTIPLY", c, weight))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cracks, 0.85), col, (0.008, 0.007, 0.006))
    # Cavities.
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.2
    cavity = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.3, 0.95, ao.outputs["AO"]))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cavity, 0.75), col, (0.01, 0.009, 0.008))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, grain.outputs["Fac"], 0.74, 0.92)
    rough = C._mix_float(nt, crust, rough, 0.42)
    rough = C._mix_float(nt, dust, rough, 0.95)
    rough = C._mix_float(nt, cracks, rough, 1.0)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bump1 = nt.nodes.new("ShaderNodeBump")
    bump1.inputs["Strength"].default_value = 0.7
    bump1.inputs["Distance"].default_value = 0.015
    nt.links.new(C._math(nt, "SUBTRACT", 1.0, cracks), bump1.inputs["Height"])
    fine = C._noise(nt, 45.0, 6.0, 0.7)
    bump2 = nt.nodes.new("ShaderNodeBump")
    bump2.inputs["Strength"].default_value = 0.3
    bump2.inputs["Distance"].default_value = 0.004
    nt.links.new(fine.outputs["Fac"], bump2.inputs["Height"])
    nt.links.new(bump1.outputs["Normal"], bump2.inputs["Normal"])
    nt.links.new(bump2.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def mat_crystal_placeholder() -> bpy.types.Material:
    """Neutral stand-in on every crystal; the game replaces it (material_override)."""
    mat, _nt, bsdf = C._new_material("OreCrystal")
    bsdf.inputs["Base Color"].default_value = (0.55, 0.57, 0.6, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.25
    return mat


def mat_crystal_preview(typ: str) -> bpy.types.Material:
    """Like OreType.get_material() (albedo = emission = ore color, roughness 0.2), but dimmer than its energy 2.5:
    Cycles + AgX burns that to white and hides the facets (renders only)."""
    mat = C.mat_emissive(f"PreviewOre_{typ}", SPECS[typ].color, PREVIEW_GLOW)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Base Color"].default_value = (*(c * 0.3 for c in SPECS[typ].color), 1.0)
    if SPECS[typ].dark_body:  # near-black crystal: only a faint glow here, the game shader draws the veins
        bsdf.inputs["Base Color"].default_value = (0.012, 0.012, 0.014, 1.0)
        bsdf.inputs["Emission Strength"].default_value = PREVIEW_GLOW * 0.12
    return mat


# --- assembly ---------------------------------------------------------------------------------------

COUNTERS = {t: 0 for t in TYPES}


class Variant:
    def __init__(self, name: str, spec: dict, root: bpy.types.Object):
        self.name, self.spec, self.root = name, spec, root
        self.typ, self.var = name.split("_")
        self.rnd = random.Random(spec["seed"])
        self.base = bmesh.new()
        self.roots: list[Vector] = []  # crystal roots, for the crust and the rubble
        self.crystals: list[bpy.types.Object] = []
        self.ground = not spec.get("wall")

    # Crystals.

    def crystal(self, root: Vector, direction: Vector, u: float) -> bpy.types.Object | None:
        rnd, typ = self.rnd, self.typ
        bm = bmesh.new()
        spin = rand_unit(rnd)
        append_bm(bm, SPECS[typ].shape(rnd, u), T(root, basis(direction, spin)))
        counts, (f0, f1) = SPECS[typ].buddies
        for _ in range(rnd.choice(counts)):
            off = tilted(direction, rand_unit(rnd), 90) * rnd.uniform(0.04, 0.12) * (0.5 + u)
            d = tilted(direction, off, rnd.uniform(25, 55))
            append_bm(
                bm,
                SPECS[typ].shape(rnd, u * rnd.uniform(f0, f1)),
                T(root + off - direction * 0.02, basis(d, rand_unit(rnd))),
            )
        if self.ground and not self.fit(bm, root):
            bm.free()
            return None
        COUNTERS[typ] += 1
        name = f"Crystal_{typ}_{COUNTERS[typ]}"
        bmesh.ops.translate(bm, verts=bm.verts[:], vec=-root)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        if SPECS[typ].smooth:
            me.shade_smooth()
        bm.free()
        obj = bpy.data.objects.new(name, me)
        obj.location = root
        C.link(obj, self.root)
        C.assign(obj, CRYSTAL)
        self.crystals.append(obj)
        self.roots.append(root)
        return obj

    def fit(self, bm: bmesh.types.BMesh, root: Vector) -> bool:
        """Scale the crystal down around its root until it clears the miner (CLEARANCE, MAX_*)."""
        orig = [v.co.copy() for v in bm.verts]
        s = 1.0
        while s > 0.3:
            ok = True
            for v, co in zip(bm.verts, orig):
                p = root + (co - root) * s
                r = math.hypot(p.x, p.y)
                if p.z > 0.04 and (r > MAX_RADIUS or p.z > min(MAX_HEIGHT, table(CLEARANCE, r))):
                    ok = False
                    break
            if ok:
                for v, co in zip(bm.verts, orig):
                    v.co = root + (co - root) * s
                return True
            s *= 0.94
        return False

    def surface(self, x: float, y: float) -> float:
        bvh = BVHTree.FromBMesh(self.base)
        hit = bvh.ray_cast(Vector((x, y, 3.0)), Vector((0, 0, -1)))
        return hit[0].z if hit[0] is not None else 0.0

    def on_surface(self, p: Vector) -> Vector:
        """Crystal root slightly inside the rock under (ground) or behind (wall) p."""
        if self.ground:
            return Vector((p.x, p.y, self.surface(p.x, p.y) - 0.04))
        hit = BVHTree.FromBMesh(self.base).ray_cast(Vector((p.x, -3.0, p.z)), Vector((0, 1, 0)))
        return hit[0] + Vector((0, 0.05, 0)) if hit[0] is not None else p

    def group(
        self, center: Vector, n: int, size: tuple, tilt: float, spread: float = 0.2, up: Vector | None = None
    ) -> None:
        rnd = self.rnd
        up = up or Vector((0, 0, 1))
        sizes = sorted((rnd.uniform(*size) for _ in range(n - 1)), reverse=True)
        sizes = [size[1]] + sizes
        outward = Vector((center.x, center.y, 0))
        for k, u in enumerate(sizes):
            if k == 0:
                off = Vector()
            else:
                off = tilted(up, rand_unit(rnd), 90) * rnd.uniform(0.35, 1.0) * spread
            root = center + off
            root = self.on_surface(root)
            away = off if off.length > 1e-3 else rand_unit(rnd)
            t = rnd.uniform(0, 8) if k == 0 else rnd.uniform(0.35, 1.0) * tilt
            d = tilted(up, away, t)
            if self.ground and outward.length > 0.05:
                d = tilted(d, outward, rnd.uniform(3, 9))
            self.crystal(root, d, u)

    # Rock.

    def rock(
        self, center: Vector, size: Vector, cuts: int = 2, clamp: bool = True, tilt: float = 0.35, points: int = 16
    ) -> None:
        rnd = self.rnd
        bm = rock_hull(rnd, size, cuts, points)
        m = T(
            center,
            Matrix.Rotation(rnd.uniform(0, math.tau), 3, "Z") @ Matrix.Rotation(rnd.uniform(-tilt, tilt), 3, "X"),
        )
        verts = append_bm(self.base, bm, m)
        bm.free()
        if clamp and self.ground:  # squash vertically until it clears the miner
            s = 1.0
            for v in verts:
                if v.co.z > 0.02:
                    lim = table(BASE_CLEARANCE, math.hypot(v.co.x, v.co.y))
                    s = min(s, lim / v.co.z)
            for v in verts:
                v.co.z = v.co.z * s if v.co.z > 0 else v.co.z

    def foundation(self, heave: list) -> None:
        """Cracked rock pad over the deposit disc: Voronoi cells as low slabs with gaps, heaved up and tilted
        where crystals push through (heave: list of (center, strength))."""
        rnd = self.rnd
        seeds: list[Vector] = []
        while len(seeds) < 15:
            p = Vector((rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2)))
            if p.length < 1.2 and all((p - q).length > 0.42 for q in seeds):
                seeds.append(p)
        disc = [Vector((math.cos(a) * DISC_R, math.sin(a) * DISC_R)) for a in (i / 22 * math.tau for i in range(22))]
        for i, s in enumerate(seeds):
            poly = disc[:]
            for j, q in enumerate(seeds):
                if i != j:
                    n = (q - s).normalized()
                    poly = clip_poly(poly, n, n.dot((s + q) / 2) - rnd.uniform(0.012, 0.03))
            if len(poly) < 3:
                continue
            poly = [p * rnd.uniform(0.9, 1.03) if p.length > DISC_R - 0.1 else p for p in poly]
            cen = sum(poly, Vector((0, 0))) / len(poly)
            near = min(((cen - hc.xy).length for hc, _hs in heave), default=9.0)
            if cen.length > 0.55 and near > 0.5 and rnd.random() < 0.3:
                continue  # missing plate: the ground shows through
            h0 = rnd.uniform(0.03, 0.09)
            grad = Vector((rnd.uniform(-0.1, 0.1), rnd.uniform(-0.1, 0.1)))
            for hc, hs in heave:
                d = (cen - hc.xy).length
                if d < 0.75:
                    w = (1 - d / 0.75) ** 2
                    h0 += 0.16 * hs * w
                    grad += (hc.xy - cen).normalized() * 0.45 * hs * w
            heights = []
            for p in poly:
                h = h0 + grad.dot(p - cen) + rnd.uniform(-0.01, 0.01)
                heights.append(max(0.02, min(h, table(BASE_CLEARANCE, p.length))))
            slab(self.base, rnd, poly, heights)

    def rubble(self) -> None:
        """Rock chunks hiding the crystal roots, and loose bits over the pad."""
        rnd = self.rnd
        for root in self.roots:
            for _ in range(rnd.choice((0, 1, 1, 2))):
                off = tilted(Vector((0, 0, 1)), rand_unit(rnd), 90) * rnd.uniform(0.05, 0.14)
                s = rnd.uniform(0.07, 0.15)
                self.rock(
                    root + off + Vector((0, 0, rnd.uniform(0.0, 0.04))),
                    Vector((s, s * rnd.uniform(0.7, 1.2), s * rnd.uniform(0.5, 0.9))),
                    1,
                    points=11,
                )
        if not self.ground:
            return
        for _ in range(9):
            p = polar(rnd.uniform(0, 360), rnd.uniform(0.35, 1.2))
            s = rnd.uniform(0.035, 0.09)
            self.rock(
                p + Vector((0, 0, self.surface(p.x, p.y) - s * 0.2)),
                Vector((s, s * rnd.uniform(0.7, 1.3), s * rnd.uniform(0.4, 0.8))),
                1,
                points=9,
            )

    def mound(self, center: Vector, spread: float) -> None:
        """Upheaved angular blocks around a crystal group: the crystals burst out of jagged rock."""
        rnd = self.rnd
        for k in range(rnd.choice((3, 4, 5))):
            p = center + polar(k * 360 / 4.5 + rnd.uniform(-30, 30), rnd.uniform(0.6, 1.3) * spread + 0.08)
            s = rnd.uniform(0.14, 0.28)
            p.z = self.surface(p.x, p.y) + s * rnd.uniform(-0.1, 0.25)
            self.rock(p, Vector((s, s * rnd.uniform(0.6, 1.1), s * rnd.uniform(0.45, 0.85))), 2, tilt=0.6, points=13)

    def crust(self) -> None:
        """Color attribute "Crust" on the base: mineral color near the crystal roots and inside geodes."""
        me = self.base_obj.data
        attr = me.color_attributes.new("Crust", "FLOAT_COLOR", "POINT")
        col = SPECS[self.typ].crust
        loc = self.base_obj.location
        for i, v in enumerate(me.vertices):
            p = v.co + loc
            d = min(((p - r).length for r in self.roots), default=9.0)
            w = max(0.0, 1.0 - d / 0.45) ** 1.5
            for c, gr in self.geodes:  # inside the geode
                if (p.xy - c.xy).length < gr * 0.8 and p.z > 0.0:
                    w = max(w, 0.9)
            attr.data[i].color = (*col, min(1.0, w))

    def finish_base(self) -> None:
        name = f"Base_{self.typ}_{self.var}"
        me = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.base, verts=self.base.verts[:], dist=1e-5)
        self.base.to_mesh(me)
        self.base.free()
        for p in me.polygons:
            p.use_smooth = False
        obj = bpy.data.objects.new(name, me)
        C.link(obj, self.root)
        C.assign(obj, ROCK)
        self.base_obj = obj

    # Builders.

    def build_ground(self) -> None:
        spec, rnd = self.spec, self.rnd
        geodes = spec.get("geodes", [])
        heave = [(polar(a, r), 1.0) for a, r, *_ in spec["groups"]] + [(polar(a, r), 0.6) for a, r, *_ in geodes]
        self.foundation(heave)
        shard_sites = []
        for a, r, gr, n in geodes:
            c = polar(a, r, 0.02)
            height = min(table(BASE_CLEARANCE, r) * 0.85, 0.42)
            pts = geode(self.base, rnd, c, gr, height, a + 180 + rnd.uniform(-40, 40))  # open toward the node center
            shard_sites.append((c, gr, n, pts))
        self.geodes = [(c, gr) for c, gr, _n, _pts in shard_sites]
        for a, r, n, size, tilt in spec["groups"]:
            center = polar(a, r)
            center.z = self.surface(center.x, center.y)
            self.group(center, n, size, tilt, spread=SPECS[self.typ].spread)
            self.mound(center, SPECS[self.typ].spread)
        for c, gr, n, pts in shard_sites:
            sizes = sorted((rnd.uniform(0.4, 0.95) for _ in range(n)), reverse=True)
            for k, u in enumerate(sizes):
                p = pts[0] if k == 0 else rnd.choice(pts[1:])
                root = p + (c - p) * 0.15 - Vector((0, 0, 0.03))
                away = (p - c) if (p - c).length > 0.02 else rand_unit(rnd)
                d = tilted(Vector((0, 0, 1)), away, rnd.uniform(10, 42) if k else rnd.uniform(0, 12))
                self.crystal(root, d, u)
        self.chips()
        self.rubble()
        self.finish_base()
        self.crust()

    def chips(self) -> None:
        """A few tiny loose crystals lying around the pad (one object)."""
        rnd = self.rnd
        bm = bmesh.new()
        first = None
        for _ in range(5):
            p = polar(rnd.uniform(0, 360), rnd.uniform(0.75, 1.0))
            p.z = self.surface(p.x, p.y) - 0.01
            if first is None:
                first = p.copy()
            d = tilted(Vector((0, 0, 1)), rand_unit(rnd), rnd.uniform(40, 75))
            append_bm(bm, SPECS[self.typ].shape(rnd, 0.0), T(p, basis(d, rand_unit(rnd)), (0.35, 0.35, 0.35)))
        COUNTERS[self.typ] += 1
        name = f"Crystal_{self.typ}_{COUNTERS[self.typ]}"
        bmesh.ops.translate(bm, verts=bm.verts[:], vec=-first)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        if SPECS[self.typ].smooth:
            me.shade_smooth()
        bm.free()
        obj = bpy.data.objects.new(name, me)
        obj.location = first
        obj["chips"] = True  # loose bits around the pad: not part of a group (icons skip it)
        C.link(obj, self.root)
        C.assign(obj, CRYSTAL)
        self.crystals.append(obj)

    def build_wall(self) -> None:
        """Rock chunk with a flat back on the wall plane (y = 0) and a flat bottom; crystals grow out of its
        front toward -Y, fanning up and sideways."""
        rnd = self.rnd
        chunks = [
            ((0.0, -0.26, 0.68), (0.85, 0.45, 0.7)),
            ((-0.6, -0.16, 0.32), (0.48, 0.34, 0.4)),
            ((0.55, -0.18, 1.05), (0.45, 0.32, 0.4)),
            ((0.45, -0.2, 0.3), (0.4, 0.32, 0.33)),
        ]
        for c, s in chunks:
            bm = rock_hull(rnd, Vector(s), 2, 18)
            append_bm(self.base, bm, T(c, Matrix.Rotation(rnd.uniform(-0.3, 0.3), 3, "Y")))
            bm.free()
        cut(self.base, Vector((0, 0, 0)), Vector((0, 1, 0)))  # flat back on the wall
        cut(self.base, Vector((0, 0, 0)), Vector((0, 0, -1)))  # flat bottom
        bmesh.ops.dissolve_limit(
            self.base, angle_limit=math.radians(2), verts=self.base.verts[:], edges=self.base.edges[:]
        )
        finish_normals(self.base)
        bvh = BVHTree.FromBMesh(self.base)
        self.geodes = []
        sizes = SPECS[self.typ].wall_sizes
        tilt = SPECS[self.typ].wall_tilt
        # One big group in the middle, a few smaller around it.
        sites = [
            (0.05, 0.62, self.spec["count"] - 3, sizes[1]),
            (-0.5, 0.35, 2, sizes[0] + 0.15),
            (0.48, 0.98, 1, sizes[0]),
        ]
        for x, z, n, umax in sites:
            hit = bvh.ray_cast(Vector((x, -3, z)), Vector((0, 1, 0)))
            if hit[0] is None:
                continue
            center = hit[0] + Vector((0, 0.05, 0))
            out = (hit[1] * 0.3 + Vector((0, -0.45, 0.85))).normalized()  # out of the face, mostly upward
            self.group(center, n, (sizes[0], umax), tilt, spread=SPECS[self.typ].spread + 0.05, up=out)
        self.rubble()
        self.finish_base()
        self.crust()


def build_variant(name: str, column: int) -> Variant:
    """Builds one variant; the .blend lays the roots out on a grid: a column per ore, a row per variant."""
    typ, var = name.split("_")
    root = C.asset_root(f"Ore_{typ}_{var}")
    row = VARIANT_KEYS.index(var)
    root.location = (column * LAYOUT_SPACING, (row - 1) * LAYOUT_SPACING, 0)
    root["layout_offset"] = list(root.location)  # zero it before export
    v = Variant(name, SPECS[typ].variants[var], root)
    if v.ground:
        v.build_ground()
    else:
        v.build_wall()
    return v


def tri_count(obj: bpy.types.Object) -> int:
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def report(variants: list[Variant]) -> None:
    for v in variants:
        crys = sum(tri_count(o) for o in v.crystals)
        base = tri_count(v.base_obj)
        top = 0.0
        rad = 0.0
        for o in v.crystals:
            for vert in o.data.vertices:
                p = vert.co + o.location
                if p.z > 0.04:
                    top = max(top, p.z)
                    rad = max(rad, math.hypot(p.x, p.y))
        dims = v.base_obj.dimensions
        print(
            f"STATS {v.root.name}: base {base} tris, {len(v.crystals)} crystal objects {crys} tris, total {base + crys}; "
            f"crystal top {top:.2f} m, crystal radius {rad:.2f} m, base dims {dims.x:.2f} x {dims.y:.2f} x {dims.z:.2f}"
        )


# --- previews ---------------------------------------------------------------------------------------


def variant_objects(v: Variant) -> list:
    return [v.root] + list(v.root.children_recursive)


def solo(variants: list[Variant], keep: Variant | None) -> None:
    """Show only `keep` (moved to the origin for the shared preview lights), or all at their layout spots."""
    for v in variants:
        hide = keep is not None and v is not keep
        for o in variant_objects(v):
            o.hide_render = hide
        v.root.location = (0, 0, 0) if v is keep else Vector(v.root["layout_offset"])


def set_preview_materials(variants: list[Variant], preview: bool) -> None:
    for v in variants:
        for o in v.crystals:
            C.assign(o, mat_crystal_preview(v.typ) if preview else CRYSTAL)


def backdrop(show: bool) -> None:
    """Cliff stand-in behind the wall clusters (preview only)."""
    obj = bpy.data.objects.get("PreviewCliff")
    if obj is None:
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        for c in obj.users_collection:
            c.objects.unlink(obj)
        C.link(obj, None, "Preview")
        obj.name = "PreviewCliff"
        obj.scale = (5.0, 1.0, 3.2)
        obj.location = (0, 0.5, 1.6)
        C.assign(obj, bpy.data.materials["PreviewRock"])
    obj.hide_render = not show


def import_miner(yaw_deg: float) -> list:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets" / "miners" / "miner_glow.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        C.collection("Preview").objects.link(o)
    top = [o for o in new if o.parent is None]
    for o in top:
        o.location = (0, 0, 0.08)  # MinerMount
        o.rotation_mode = "XYZ"
        o.rotation_euler = (0, 0, math.radians(yaw_deg))
    return new


def render_view(path: pathlib.Path, v: Variant, view: str, samples: int, size: int) -> None:
    tz = 0.35 if v.ground else 0.65
    if view == "iso":
        C.render(path, "iso", samples, size, target=(0, -0.3 * (not v.ground), tz), zoom=0.4)
    elif view == "hero":
        C.render(path, "hero", samples, size, target=(0, -0.3 * (not v.ground), tz + 0.07), zoom=0.48)
    elif view == "top":
        C.render(path, "iso", samples, size, target=(0, 0, 0.3), zoom=0.4)
        cam = bpy.context.scene.camera
        cam.location = (0, 0, 7)
        cam.rotation_euler = (0, 0, 0)
        bpy.ops.render.render(write_still=True)
    elif view in ("miner", "minerhero"):
        new = import_miner(25.0 if v.var == "a" else 70.0)
        if view == "miner":
            C.render(path, "iso", samples, size, target=(0, 0, 1.0), zoom=0.62)
        else:
            C.render(path, "hero", samples, size, target=(0, 0, 0.9), zoom=0.75)
        for o in new:
            bpy.data.objects.remove(o)
    else:
        raise ValueError(view)


def lineup(
    variants: list[Variant],
    shown: list[Variant],
    path: pathlib.Path,
    samples: int,
    size: int,
    zoom: float,
    target_z: float = 0.4,
) -> None:
    """The `shown` variants side by side along the screen's horizontal (same depth), iso camera."""
    right = Vector((1, 1, 0)).normalized()
    solo(variants, None)
    for v in variants:
        for o in variant_objects(v):
            o.hide_render = v not in shown
    variants = shown
    n = len(variants)
    for k, v in enumerate(variants):
        v.root.location = right * (k - (n - 1) / 2) * 3.0
    C.render(path, "iso", samples, size, target=(0, 0, target_z), zoom=zoom)


def grid_view(variants: list[Variant], path: pathlib.Path, samples: int, size: int) -> None:
    """All variants at their layout spots from roughly the game's camera distance."""
    solo(variants, None)
    C.render(path, "iso", samples, size, target=(0, 0, 0.3), zoom=1.45)


# --- main -------------------------------------------------------------------------------------------


def mat_icon() -> bpy.types.Material:
    """White, lit from the upper left by its normal only (no shadows, no light objects), so every facet gets its own
    flat grey: the game tints the icon in the ore color and the facets keep the crystal shape readable."""
    if "OreIcon" in bpy.data.materials:
        return bpy.data.materials["OreIcon"]
    mat, nt, bsdf = C._new_material("OreIcon")
    nt.nodes.remove(bsdf)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    light = nt.nodes.new("ShaderNodeVectorMath")
    light.operation = "DOT_PRODUCT"
    nt.links.new(geo.outputs["Normal"], light.inputs[0])
    light.inputs[1].default_value = Vector((-0.2, -0.75, 0.65)).normalized()
    shade = C._math(nt, "MULTIPLY_ADD", light.outputs["Value"], 0.6, 0.45, clamp=True)
    emission = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(shade, emission.inputs["Strength"])
    nt.links.new(emission.outputs["Emission"], out.inputs["Surface"])
    return mat


def render_icon(variants: list[Variant], v: Variant, path: pathlib.Path, size: int = 256) -> None:
    """The variant's main crystal group (around its tallest crystal, without the rock and the loose chips) from the
    game camera's direction, orthographic, framed tightly, on a transparent background: one group still reads at
    badge size (~24 px), the whole cluster doesn't."""
    solo(variants, v)
    for o in variant_objects(v):
        o.hide_render = True
    icon = mat_icon()
    shown = []
    tallest = max(
        (o for o in v.crystals if not o.get("chips")),
        key=lambda o: max((o.matrix_world @ p.co).z for p in o.data.vertices),
    )
    for o in v.crystals:
        top = max((o.matrix_world @ p.co).z for p in o.data.vertices)
        if o.get("chips") or top <= 0.15:
            continue
        if (o.location - tallest.location).xy.length < ICON_GROUP_RADIUS:
            o.hide_render = False
            C.assign(o, icon)
            shown.append(o)
    bpy.context.view_layer.update()
    direction = Vector((7.0, -7.0, 9.5)).normalized()  # like C.render's iso view
    cam = C._camera("custom")
    cam.data.type = "ORTHO"
    rot = (-direction).to_track_quat("-Z", "Y")
    cam.rotation_euler = rot.to_euler()
    inv = rot.to_matrix().inverted()
    pts = [inv @ (o.matrix_world @ p.co) for o in shown for p in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = rot.to_matrix() @ ((lo + hi) / 2)
    cam.data.ortho_scale = max(hi.x - lo.x, hi.y - lo.y) * 1.08
    cam.location = center + direction * 10.0
    bpy.context.scene.camera = cam
    scene = bpy.context.scene
    C._render_settings(16, size)
    scene.render.film_transparent = True
    scene.cycles.use_denoising = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    for name in ("PreviewGround", "PreviewFigure"):
        if name in bpy.data.objects:
            bpy.data.objects[name].hide_render = True
    C._write_render(path)


def main() -> None:
    global ROCK, CRYSTAL
    C.reset(ASSET)
    ROCK = mat_rock()
    CRYSTAL = mat_crystal_placeholder()
    names = variant_names()
    if MODE == "icon":
        names = [n for n in names if n.endswith("_a")]
    columns = [t for t in TYPES if any(n.startswith(f"{t}_") for n in names)]
    variants = [build_variant(n, columns.index(n.split("_")[0])) for n in names]
    report(variants)
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(1.7, 1.7, 0.0))
    backdrop(False)
    if MODE == "icon":
        for v in variants:
            render_icon(variants, v, ICONS / f"{v.typ}.png")
    elif MODE in ("final", "sheet"):
        out = OUT / columns[0]
        if MODE == "final":
            bpy.context.preferences.filepaths.save_version = 0
            C.save_blend(out / "ores_procedural.blend")
        set_preview_materials(variants, True)
        for v in variants if MODE == "final" else []:
            solo(variants, v)
            backdrop(not v.ground)
            views = ["iso", "hero", "miner"] if v.ground else ["iso", "hero"]
            for view in views:
                render_view(out / f"render_{v.name}_{view}.png", v, view, 64, 768)
        backdrop(False)
        bpy.data.objects["PreviewFigure"].location = (4.6, 4.6, 0)
        lineup(variants, variants, out / "render_lineup.png", 64, 1024, LINEUP_ZOOM)
        solo(variants, None)
        C.render(out / "render_game_distance.png", "iso", 64, 1024, target=(0, 0, 0.3), zoom=1.0)
        order = [out / f"render_{v.name}_{x}.png" for v in variants for x in ("iso", "hero")]
        order += [out / f"render_{v.name}_miner.png" for v in variants if v.ground]
        order += [out / "render_lineup.png", out / "render_game_distance.png"]
        C.contact_sheet(order, out / "sheet.png", 4, 384)
    else:
        set_preview_materials(variants, True)
        for v in variants:
            solo(variants, v)
            backdrop(not v.ground)
            for view in VIEWS:
                if view in ("lineup", "grid", "types"):
                    continue
                if view.startswith("miner") and not v.ground:
                    continue
                render_view(OUT / "wip" / f"{TAG}_{v.name}_{view}.png", v, view, 24, 512)
        backdrop(False)
        if "lineup" in VIEWS:
            for t in columns:
                vs = [v for v in variants if v.typ == t]
                lineup(variants, vs, OUT / "wip" / f"{TAG}_lineup_{t}.png", 24, 768, LINEUP_ZOOM)
        if "types" in VIEWS:
            vs = [v for v in variants if v.var == "a"]
            lineup(variants, vs, OUT / "wip" / f"{TAG}_types.png", 32, 1600, LINEUP_ZOOM * max(1.0, len(vs) / 3))
        if "grid" in VIEWS:
            grid_view(variants, OUT / "wip" / f"{TAG}_grid.png", 24, 768)


main()
