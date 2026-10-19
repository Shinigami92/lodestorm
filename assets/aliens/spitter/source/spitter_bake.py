"""Game-ready spitter: bake the procedural look of spitter_procedural.blend into one texture set.

Run from the repo root, after spitter_build.py final (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/spitter/source/spitter_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/spitter/source/spitter_bake.py verify   # only re-import and render the checks

Writes the game asset assets/aliens/spitter/spitter.glb (textures, skeleton and animations embedded) and its source
assets/aliens/spitter/source/spitter.blend; the separate PNGs and check renders go to tmp/assets/spitter/game/.

The shared flow (tools/blender/bake.py) bakes "Creature" (Sinew, Chitin, Bone, Mouth) into one 1024 texture set with one
"Spitter" PBR material. "Eyes" and "Glands" (the acid sac and the glow in the throat) keep constant emissive materials
in the hive's yellow-green, the sac the strongest glow of the hive (strength TBD (playtest)). The armature modifiers
are taken off for the bake (the rest pose is baked) and put back before the export. Texture size 1024 per the asset
budget (many aliens at once, small on screen), TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "spitter"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Spitter"
SKINNED = ("Creature", "Eyes", "Glands")
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)


def prepare(job: B.Job) -> list:
    for name in SKINNED:
        obj = bpy.data.objects[name]
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
    return [B.bake_plane("BakeGround", scale=(4, 4, 1))]


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Eyes"], B.mat_constant("Eyes", EYE_COLOR, roughness=0.2, emission=6.0))
    C.assign(bpy.data.objects["Glands"], B.mat_constant("Glands", EYE_COLOR, roughness=0.15, emission=4.0))
    for name in SKINNED:
        obj = bpy.data.objects[name]
        obj.modifiers.new("Armature", "ARMATURE").object = bpy.data.objects["Skeleton"]


JOB = B.Job(
    name="spitter",
    asset=ASSET,
    source=OUT / "spitter_procedural.blend",
    glb=ROOT / "assets" / "aliens" / "spitter" / "spitter.glb",
    blend=ROOT / "assets" / "aliens" / "spitter" / "source" / "spitter.blend",
    game=OUT / "game",
    atlas=["Creature"],
    material="Spitter",
    size=1024,  # final texture size (budget: one 1024 set, TBD (playtest))
    supersample=2,  # claws, spurs and the mandibles' teeth are small in the atlas
    island_margin=0.003,
    ao_distance=0.05,  # small creature: only close cavities darken
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    print("CHECK actions", sorted(a.name for a in bpy.data.actions))
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:  # the importer's bone shape
        bpy.data.objects.remove(obj)
    C.preview_scene(crystals=False, figure_location=(1.6, 1.2, 0))
    target = (0, 0, 0.55)
    for view, zoom in (("iso", 0.3), ("hero", 0.36), ("back", 0.4)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=target, zoom=zoom)
    C.render_from(job.game / "check_head.png", Vector((0.8, -1.7, 0.85)), (0, -0.6, 0.45), 50, 64, 768)


B.run(JOB, checks)
