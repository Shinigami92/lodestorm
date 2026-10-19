"""Game-ready bloater: bake the procedural look of bloater_procedural.blend into one texture set.

Run from the repo root, after bloater_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/bloater/source/bloater_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/bloater/source/bloater_bake.py verify   # only re-import and render the checks

Writes the game asset assets/aliens/bloater/bloater.glb (textures, skeleton and animations embedded) and its source
assets/aliens/bloater/source/bloater.blend; the separate PNGs and check renders go to tmp/assets/bloater/game/.

The shared flow (tools/blender/bake.py) bakes "Creature" (Sinew, Chitin, Bone, Mouth) into one 1024 texture set with
one "Bloater" PBR material. "Eyes" and "Glands" (the veins and patches on the bladder) keep constant emissive
materials in the hive's yellow-green (strength TBD (playtest)). The armature modifiers are taken off for the bake
(the rest pose is baked) and put back before the export. Texture size 1024 per the asset budget (many aliens at once,
small on screen), TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "bloater"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Bloater"
SKINNED = ("Creature", "Eyes", "Glands")
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)


def prepare(job: B.Job) -> list:
    for name in SKINNED:
        obj = bpy.data.objects[name]
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
    return [B.bake_plane("BakeGround", scale=(5, 5, 1))]


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Eyes"], B.mat_constant("Eyes", EYE_COLOR, roughness=0.2, emission=6.0))
    C.assign(bpy.data.objects["Glands"], B.mat_constant("Glands", EYE_COLOR, roughness=0.15, emission=4.0))
    for name in SKINNED:
        obj = bpy.data.objects[name]
        obj.modifiers.new("Armature", "ARMATURE").object = bpy.data.objects["Skeleton"]


JOB = B.Job(
    name="bloater",
    asset=ASSET,
    source=OUT / "bloater_procedural.blend",
    glb=ROOT / "assets" / "aliens" / "bloater" / "bloater.glb",
    blend=ROOT / "assets" / "aliens" / "bloater" / "source" / "bloater.blend",
    game=OUT / "game",
    atlas=["Creature"],
    material="Bloater",
    size=1024,  # final texture size (budget: one 1024 set, TBD (playtest))
    supersample=2,  # claws, spurs and the mandibles are small in the atlas next to the big bladder
    island_margin=0.003,
    ao_distance=0.08,  # a big creature: the cavities between its plates darken a little further
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    print("CHECK actions", sorted(a.name for a in bpy.data.actions))
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:  # the importer's bone shape
        bpy.data.objects.remove(obj)
    C.preview_scene(crystals=False, figure_location=(2.3, 1.6, 0))
    target = (0, -0.05, 0.85)
    for view, zoom in (("iso", 0.62), ("hero", 0.7), ("back", 0.75)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=target, zoom=zoom)
    C.render_from(job.game / "check_head.png", Vector((1.2, -2.6, 1.2)), (0, -0.9, 0.62), 50, 64, 768)


B.run(JOB, checks)
