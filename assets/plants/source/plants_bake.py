"""Game-ready biome scatter kit: bake the procedural look of plants_procedural.blend into one shared texture set.

Run from the repo root, after plants_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/plants/source/plants_bake.py          # bake, export, check renders
    tools/blender.sh assets/plants/source/plants_bake.py verify   # only re-import and render the checks
    tools/blender.sh assets/plants/source/plants_bake.py verify noclose   # without the per-variant close-ups

Writes the game asset assets/plants/plants.glb (textures embedded) and its source assets/plants/source/plants.blend;
the separate PNGs and check renders go to tmp/assets/scatter/game/.

The shared flow (tools/blender/bake.py) bakes all ten variants into one 2048 texture set (at 2x and scaled down:
cheap anti-aliasing for the thin blades), including the bulbs' glow as an emission map, so one shared "Plants"
material covers the dim bulbs too. The bakes run with the variants still in their preview rows (they would occlude
each other at the origin) and with a ground plane at z = 0, as in the procedural previews (cavity darkening and AO
see the ground); the variants move to the origin for the export.
Texture size: one 2048 set for the whole kit, per the asset budget, TBD (playtest).
"""

import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Plants"
DUST = ["Dust_Debris_a", "Dust_Shrub_a", "Dust_Spire_a", "Dust_Shrub_b", "Dust_Debris_b"]
OVERGROWTH = [
    "Overgrowth_Frond_b",
    "Overgrowth_Fungus_a",
    "Overgrowth_Tube_a",
    "Overgrowth_Fungus_b",
    "Overgrowth_Frond_a",
]
VARIANTS = DUST + OVERGROWTH

# Check-render layout, as in plants_build.py (rows perpendicular to the iso view).
ROW_STEP = 2.1
ROW_DIR = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))
ROW_CENTER = {"dust": Vector((2.0, -2.0, 0)), "overgrowth": Vector((-2.0, 2.0, 0))}
GROUND = {
    "dust": ((0.055, 0.042, 0.03), (0.11, 0.085, 0.06)),
    "overgrowth": ((0.018, 0.019, 0.011), (0.045, 0.047, 0.026)),
}


def prepare(job: B.Job) -> list:
    root = bpy.data.objects[ASSET]
    root.location = (0, 0, 0)
    for name in VARIANTS:
        o = bpy.data.objects[name]
        assert o.type == "MESH" and not o.modifiers and o.parent == root, o.name
        assert len(o.data.materials) == 1, o.name
        assert tuple(o.rotation_euler) == (0, 0, 0) and tuple(o.scale) == (1, 1, 1), o.name
    return [B.bake_plane("BakeGround", scale=(40, 40, 1))]


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the preview rows were layout only: every variant's origin is its base center


JOB = B.Job(
    name="plants",
    asset=ASSET,
    source=ROOT / "tmp" / "assets" / "plants" / "plants_procedural.blend",
    glb=ROOT / "assets" / "plants" / "plants.glb",
    blend=ROOT / "assets" / "plants" / "source" / "plants.blend",
    game=ROOT / "tmp" / "assets" / "scatter" / "game",
    atlas=VARIANTS,
    material=ASSET,
    supersample=2,
    samples={"Base Color": 64, "Roughness": 64},  # the cavity AO node in the albedo needs the samples
    emission_strength=3.0,  # glTF emissive strength of the shared material; the texture holds color * glow / 3
    normal_min_z=0.7,  # the undersides of the thin smooth-shaded fronds bake garbage normals
    prepare=prepare,
    finish=finish,
)


# --- checks -------------------------------------------------------------------------------------------


def row_location(name: str) -> Vector:
    group, names = ("dust", DUST) if name in DUST else ("overgrowth", OVERGROWTH)
    k = names.index(name) - (len(names) - 1) / 2
    return ROW_CENTER[group] + ROW_DIR * (k * ROW_STEP)


def ground_color(biome: str) -> None:
    lo, hi = GROUND[biome]
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*lo, 1.0)
            node.inputs[7].default_value = (*hi, 1.0)


def scatter(objs: dict, biome: str, seed: int) -> list:
    """Game-like scatter of linked copies, as in plants_build.py."""
    rnd = random.Random(seed)
    counts = (
        {"Dust_Shrub_a": 9, "Dust_Shrub_b": 12, "Dust_Spire_a": 4, "Dust_Debris_a": 8, "Dust_Debris_b": 3}
        if biome == "dust"
        else {
            "Overgrowth_Frond_b": 24,
            "Overgrowth_Fungus_a": 8,
            "Overgrowth_Tube_a": 4,
            "Overgrowth_Fungus_b": 5,
            "Overgrowth_Frond_a": 9,
        }
    )
    copies, placed = [], []
    for name, count in counts.items():
        for _ in range(count):
            for _try in range(30):
                x, y = rnd.uniform(-7, 7), rnd.uniform(-7, 7)
                if (
                    all((x - px) ** 2 + (y - py) ** 2 > 1.0 for px, py in placed)
                    and (x - 1.5) ** 2 + (y + 1.5) ** 2 > 2.0
                ):
                    break
            placed.append((x, y))
            o = objs[name].copy()
            o.parent = None
            C.link(o, None, "Preview")
            o.name = f"Scatter_{biome}"
            o.location = (x, y, 0)
            o.rotation_euler = (rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06), rnd.uniform(0, math.tau))
            s = rnd.uniform(0.7, 1.3)
            o.scale = (s, s, s)
            copies.append(o)
    return copies


def show_only(visible: list) -> None:
    vis = {o.name for o in visible}
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and (o.name in VARIANTS or o.name.startswith("Scatter")):
            o.hide_render = o.name not in vis


def checks(job: B.Job, meshes: list) -> None:
    assert sorted(o.name for o in meshes) == sorted(VARIANTS), sorted(o.name for o in meshes)
    objs = {n: bpy.data.objects[n] for n in VARIANTS}
    for n, o in objs.items():
        o.location = row_location(n)
    C.preview_scene(crystals=False, figure_location=(0, 0, 0))
    for o in list(C.collection("Preview").all_objects):
        if o.type == "MESH" and o.name.startswith("Ico"):
            bpy.data.objects.remove(o)
    fig = bpy.data.objects["PreviewFigure"]
    sets = {"dust": scatter(objs, "dust", 5), "overgrowth": scatter(objs, "overgrowth", 9)}
    for biome, names in (("dust", DUST), ("overgrowth", OVERGROWTH)):
        ground_color(biome)
        center = ROW_CENTER[biome]
        show_only([objs[n] for n in names])
        fig.location = center + ROW_DIR * (ROW_STEP * 2.9)
        tgt = tuple(center + Vector((0, 0, 0.5)))
        C.render(job.game / f"check_{biome}_iso.png", view="iso", samples=64, size=1024, target=tgt, zoom=1.12)
        C.render(job.game / f"check_{biome}_hero.png", view="hero", samples=64, size=1024, target=tgt, zoom=1.7)
        show_only(sets[biome])
        fig.location = (1.5, -1.5, 0)
        C.render(
            job.game / f"check_{biome}_scatter.png", view="iso", samples=48, size=768, target=(0, 0, 0.3), zoom=1.45
        )
        if "noclose" in sys.argv:
            continue
        for name in names:  # close-ups like plants_build.py's final_<Variant>_<view>.png
            obj = objs[name]
            h = obj.dimensions.z
            show_only([obj])
            fig.location = obj.location + Vector((1.3, 0.9, 0))
            tgt = tuple(obj.location + Vector((0, 0, max(0.15, h * 0.45))))
            zoom = max(0.2, min(0.62, 0.12 + h * 0.16))
            for view in ("iso", "hero"):
                C.render(
                    job.game / f"check_{name}_{view}.png",
                    view=view,
                    samples=48,
                    size=384,
                    target=tgt,
                    zoom=zoom * (0.9 if view == "iso" else 1.0),
                )


B.run(JOB, checks)
