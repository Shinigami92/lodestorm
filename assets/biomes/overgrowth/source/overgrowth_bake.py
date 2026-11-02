"""Game-ready Overgrowth kit: bake the procedural look of overgrowth_procedural.blend into one shared texture set.

Run from the repo root, after overgrowth_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/biomes/overgrowth/source/overgrowth_bake.py          # bake, export, check renders
    tools/blender.sh assets/biomes/overgrowth/source/overgrowth_bake.py verify   # only re-import and render checks

Writes the game asset assets/biomes/overgrowth/overgrowth.glb (textures embedded) and its source
assets/biomes/overgrowth/source/overgrowth.blend; the separate PNGs and check renders go to
tmp/assets/overgrowth/game/.

The shared flow (tools/blender/bake.py) bakes all eight parts into one 2048 texture set (at 2x and scaled down:
cheap anti-aliasing for the plates' cracks), including the bulbs' and tube throats' dim glow as an emission map,
so one "Overgrowth" material covers everything. The bake runs with the parts in their row along X (no AO from a
neighbor) over a ground plane at z = 0 (cavity darkening and AO see the ground); the faces that only exist below
ground get a speck of the atlas. The parts move to the origin for the export.
Texture size: one 2048 set for the whole kit, per the asset budget, TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "overgrowth"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Overgrowth"
TALL = ["Growth_Stalk_a", "Growth_Stalk_b", "Growth_Cap_a", "Growth_Cap_b"]
SMALL = ["Growth_Root_a", "Growth_Root_b", "Grove_Stalk_a", "Grove_Cap_a"]
PARTS = TALL + SMALL
BURIED_Z = -0.12  # a face whose corners all lie below this is never seen (the parts sink at most ~0.1 m)
ROW_DIR = Vector((math.sqrt(0.5), math.sqrt(0.5), 0))  # check layout: across the iso view
GROUND = ((0.018, 0.019, 0.011), (0.045, 0.047, 0.026))


def prepare(job: B.Job) -> list:
    root = bpy.data.objects[ASSET]
    root.location = (0, 0, 0)
    xs = []
    for name in PARTS:
        o = bpy.data.objects[name]
        assert o.type == "MESH" and not o.modifiers and o.parent == root, o.name
        assert len(o.data.materials) == 1, o.name
        assert tuple(o.rotation_euler) == (0, 0, 0) and tuple(o.scale) == (1, 1, 1), o.name
        xs.append(o.location.x)
    mid = (min(xs) + max(xs)) / 2
    return [B.bake_plane("BakeGround", location=(mid, 0, 0), scale=(max(xs) - min(xs) + 20, 20, 1))]


def buried(obj: bpy.types.Object, poly) -> float | None:
    """UV scale for faces nobody sees: entirely below ground."""
    if all(obj.data.vertices[i].co.z < BURIED_Z for i in poly.vertices):
        return 0.08
    return None


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row was layout only: every part's origin is its ground contact


JOB = B.Job(
    name="overgrowth",
    asset=ASSET,
    source=OUT / "overgrowth_procedural.blend",
    glb=ROOT / "assets" / "biomes" / "overgrowth" / "overgrowth.glb",
    blend=ROOT / "assets" / "biomes" / "overgrowth" / "source" / "overgrowth.blend",
    game=OUT / "game",
    atlas=PARTS,
    material=ASSET,
    supersample=2,
    samples={"Base Color": 64, "Roughness": 64},  # the cavity AO node in the albedo needs the samples
    ao_distance=0.6,
    emission_strength=3.0,  # glTF emissive strength of the material; the texture holds color * glow / 3
    shrink=buried,
    drop_attributes=("grad", "glow", "plate"),
    prepare=prepare,
    finish=finish,
)


# --- checks -------------------------------------------------------------------------------------------


def ground_color() -> None:
    lo, hi = GROUND
    for node in bpy.data.materials["PreviewGround"].node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            node.inputs[6].default_value = (*lo, 1.0)
            node.inputs[7].default_value = (*hi, 1.0)


def light_scale(f: float, base: dict) -> None:
    """Scale the preview lights' rig (set up for ~2 m) for the 8 m parts."""
    for o in C.collection("Preview").all_objects:
        if o.type != "LIGHT":
            continue
        if o.name not in base:
            base[o.name] = (o.location.copy(), o.data.energy)
        loc, energy = base[o.name]
        o.location = loc * f
        o.data.energy = energy * f * f
        o.rotation_euler = (Vector((0, 0, 1.6 * f)) - o.location).to_track_quat("-Z", "Y").to_euler()


def show_only(objs: dict, visible: list) -> None:
    for name, o in objs.items():
        o.hide_render = name not in visible


def checks(job: B.Job, meshes: list) -> None:
    assert sorted(o.name for o in meshes) == sorted(PARTS), sorted(o.name for o in meshes)
    objs = {o.name: o for o in meshes}
    for o in meshes:
        o.rotation_mode = "XYZ"
    C.preview_scene(crystals=False, figure_location=(0, 0, 0))
    for o in list(C.collection("Preview").all_objects):
        if o.type == "MESH" and o.name.startswith("Ico"):
            bpy.data.objects.remove(o)
    bpy.data.objects["PreviewGround"].scale = (2.5, 2.5, 1)
    ground_color()
    fig = bpy.data.objects["PreviewFigure"]
    base = {}
    for group, names, step, zoom, tz, f in (("tall", TALL, 5.6, 2.75, 3.0, 2.6), ("small", SMALL, 4.2, 2.6, 1.6, 2.0)):
        row = [*names, "figure"]
        for i, name in enumerate(row):
            loc = ROW_DIR * ((i - (len(row) - 1) / 2) * step)
            if name == "figure":
                fig.location = loc
            else:
                objs[name].location = loc
        show_only(objs, names)
        light_scale(f, base)
        for view, z in (("iso", zoom), ("hero", zoom * 1.15)):
            C.render(
                job.game / f"check_{group}_{view}.png", view=view, samples=64, size=1024, target=(0, 0, tz), zoom=z
            )
    for name, o in objs.items():  # close-ups
        o.location = (0, 0, 0)
        show_only(objs, [name])
        h, w = o.dimensions.z, max(o.dimensions.x, o.dimensions.y)
        fig.location = ROW_DIR * (w / 2 + 0.8)
        light_scale(max(1.0, h / 3.0), base)
        for view in ("iso", "hero"):
            zoom = (max(w, h) * 1.25 + 1.2) / (9.9 if view == "iso" else 6.3)
            C.render(
                job.game / f"check_{name}_{view}.png",
                view=view,
                samples=48,
                size=512,
                target=(0, 0, h * 0.42),
                zoom=zoom,
            )
    paths = [job.game / f"check_{g}_{v}.png" for g in ("tall", "small") for v in ("iso", "hero")]
    paths += [job.game / f"check_{n}_{v}.png" for n in PARTS for v in ("iso", "hero")]
    C.contact_sheet(paths, job.game / "sheet.png", tile=512)


B.run(JOB, checks)
