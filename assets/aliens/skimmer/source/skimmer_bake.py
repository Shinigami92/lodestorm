"""Game-ready skimmer: bake the procedural look of skimmer_procedural.blend into one texture set.

Run from the repo root, after skimmer_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/skimmer/source/skimmer_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/skimmer/source/skimmer_bake.py verify   # only re-import and render the checks

Writes the game asset assets/aliens/skimmer/skimmer.glb (textures, skeleton and animations embedded) and its source
assets/aliens/skimmer/source/skimmer.blend; the separate PNGs and check renders go to tmp/assets/skimmer/game/.

The shared flow (tools/blender/bake.py) bakes "Creature" (Sinew, Chitin, Bone, Mouth) into one 1024 texture set with
one "Skimmer" PBR material. "Eyes" and "Glands" (the throat sac, the spots along the wings' trailing edges and the
tail barb) keep constant emissive materials in the hive's yellow-green. The skimmer flies (its origin is the body
center), so there is no ground plane under it for the AO. The armature modifiers are taken off for the bake (the rest
pose is baked) and put back before the export. Texture size 1024 per the asset budget (a tier 6 hunter), TBD
(playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "skimmer"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Skimmer"
SKINNED = ("Creature", "Eyes", "Glands")
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)
FLIGHT = 1.6  # height of the check renders only


def prepare(job: B.Job) -> list:
    for name in SKINNED:
        obj = bpy.data.objects[name]
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
    return []


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Eyes"], B.mat_constant("Eyes", EYE_COLOR, roughness=0.2, emission=6.0))
    C.assign(bpy.data.objects["Glands"], B.mat_constant("Glands", EYE_COLOR, roughness=0.2, emission=3.5))
    for name in SKINNED:
        obj = bpy.data.objects[name]
        obj.modifiers.new("Armature", "ARMATURE").object = bpy.data.objects["Skeleton"]


JOB = B.Job(
    name="skimmer",
    asset=ASSET,
    source=OUT / "skimmer_procedural.blend",
    glb=ROOT / "assets" / "aliens" / "skimmer" / "skimmer.glb",
    blend=ROOT / "assets" / "aliens" / "skimmer" / "source" / "skimmer.blend",
    game=OUT / "game",
    atlas=["Creature"],
    material="Skimmer",
    size=1024,  # final texture size (budget: one 1024 set, TBD (playtest))
    supersample=2,  # the ribs, the leading edge plates, the teeth and the tail's spines are small in the atlas
    island_margin=0.003,
    ao_distance=0.06,  # only close cavities darken (between the plates, under the ribs)
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    print("CHECK actions", sorted(a.name for a in bpy.data.actions))
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:  # the importer's bone shape
        bpy.data.objects.remove(obj)
    for obj in C.collection(job.asset).all_objects:
        if obj.parent is None:
            obj.location.z += FLIGHT  # in the air, like in the game (the origin is the body center)
    C.preview_scene(crystals=False, figure_location=(2.3, 1.2, 0))
    target = (0, 0.55, FLIGHT)
    for view, zoom in (("iso", 0.42), ("hero", 0.5), ("back", 0.5)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=target, zoom=zoom)
    C.render_from(job.game / "check_top.png", Vector((0, 0.55, FLIGHT + 6.0)), target, 50, 64, 768)
    C.render_from(job.game / "check_head.png", Vector((0.7, -1.7, FLIGHT + 0.35)), (0, -0.5, FLIGHT), 50, 64, 768)


B.run(JOB, checks)
