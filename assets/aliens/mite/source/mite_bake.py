"""Game-ready mite: bake the procedural look of mite_procedural.blend into one texture set.

Run from the repo root, after mite_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/mite/source/mite_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/mite/source/mite_bake.py verify   # only re-import and render the checks

Writes the game asset assets/aliens/mite/mite.glb (textures, skeleton and animations embedded) and its source
assets/aliens/mite/source/mite.blend; the separate PNGs and check renders go to tmp/assets/mite/game/.

The shared flow (tools/blender/bake.py) bakes "Creature" (Sinew, Chitin, Bone, Mouth) into one 512 texture set with one
"Mite" PBR material. "Eyes" and "Glands" keep their constant emissive materials. The armature modifiers are taken off
for the bake (the rest pose is baked) and put back before the export. Texture size 512 per the asset budget (a tiny
alien in packs, many on screen), TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "mite"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C
import creature as K

ASSET = "Mite"
SKINNED = ("Creature", "Eyes", "Glands")
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)


def prepare(job: B.Job) -> list:
    K.unbind(SKINNED)
    return [B.bake_plane("BakeGround", scale=(2, 2, 1))]


def finish(job: B.Job, objs: list) -> None:
    K.glow(EYE_COLOR, glands=(0.3, 2.5))
    K.rebind(SKINNED)


JOB = B.kit_job(
    __file__,
    OUT,
    asset=ASSET,
    atlas=["Creature"],
    material="Mite",
    size=512,  # final texture size (budget: one 512 set, TBD (playtest))
    supersample=2,  # claws, mandibles and the thin legs are small in the atlas
    island_margin=0.003,
    ao_distance=0.03,  # tiny creature: only close cavities darken
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    print("CHECK actions", sorted(a.name for a in bpy.data.actions))
    K.drop_bone_shapes()
    C.preview_scene(crystals=False, figure_location=(0.9, 0.8, 0))
    target = (0, -0.02, 0.14)
    for view, zoom in (("iso", 0.13), ("hero", 0.15), ("back", 0.17)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=target, zoom=zoom)
    C.render_from(job.game / "check_head.png", Vector((0.32, -0.72, 0.33)), (0, -0.22, 0.14), 50, 64, 768)


B.run(JOB, checks)
