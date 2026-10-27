"""Game-ready ravager: bake the procedural look of ravager_procedural.blend into one texture set.

Run from the repo root, after ravager_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/ravager/source/ravager_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/ravager/source/ravager_bake.py verify   # only re-import and render the checks

Writes the game asset assets/aliens/ravager/ravager.glb (textures, skeleton and animations embedded) and its source
assets/aliens/ravager/source/ravager.blend; the separate PNGs and check renders go to tmp/assets/ravager/game/.

The shared flow (tools/blender/bake.py) bakes "Creature" (Sinew, Chitin, Bone, Mouth) into one 2048 texture set with
one "Ravager" PBR material. "Eyes" and "Glands" (the brood pods and the seams between the plates) keep constant
emissive materials in the hive's yellow-green. The armature modifiers are taken off for the bake (the rest pose is
baked) and put back before the export. Texture size 2048: the apex is huge and rare (at most one per mission), TBD
(playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "ravager"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Ravager"
SKINNED = ("Creature", "Eyes", "Glands")
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)


def prepare(job: B.Job) -> list:
    for name in SKINNED:
        obj = bpy.data.objects[name]
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
    return [B.bake_plane("BakeGround", scale=(10, 10, 1))]


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Eyes"], B.mat_constant("Eyes", EYE_COLOR, roughness=0.2, emission=6.0))
    C.assign(bpy.data.objects["Glands"], B.mat_constant("Glands", EYE_COLOR, roughness=0.2, emission=3.0))
    for name in SKINNED:
        obj = bpy.data.objects[name]
        obj.modifiers.new("Armature", "ARMATURE").object = bpy.data.objects["Skeleton"]


JOB = B.Job(
    name="ravager",
    asset=ASSET,
    source=OUT / "ravager_procedural.blend",
    glb=ROOT / "assets" / "aliens" / "ravager" / "ravager.glb",
    blend=ROOT / "assets" / "aliens" / "ravager" / "source" / "ravager.blend",
    game=OUT / "game",
    atlas=["Creature"],
    material="Ravager",
    size=2048,  # final texture size (budget: one 2048 set for the apex, TBD (playtest))
    supersample=1,  # its smallest parts (teeth, nails, the pods' creases) are several cm wide: 2048 resolves them
    island_margin=0.003,
    ao_distance=0.15,  # a huge creature: the gaps between its heavy plates darken further
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    print("CHECK actions", sorted(a.name for a in bpy.data.actions))
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:  # the importer's bone shape
        bpy.data.objects.remove(obj)
    C.preview_scene(crystals=False, figure_location=(2.3, -1.4, 0))
    target = (0, -0.2, 1.2)
    for view, zoom in (("iso", 0.75), ("hero", 0.95), ("back", 0.95)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=target, zoom=zoom)
    C.render_from(job.game / "check_head.png", Vector((2.2, -6.2, 2.2)), (0, -2.0, 1.2), 50, 64, 768)


B.run(JOB, checks)
