"""Game-ready darter: bake the procedural look of darter_procedural.blend into one texture set.

Run from the repo root, after darter_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/darter/source/darter_bake.py          # bake, export, check renders
    tools/blender.sh assets/aliens/darter/source/darter_bake.py verify   # only re-import and render the checks

Writes the game asset assets/aliens/darter/darter.glb (textures, skeleton and animations embedded) and its source
assets/aliens/darter/source/darter.blend; the separate PNGs and check renders go to tmp/assets/darter/game/.

The shared flow (tools/blender/bake.py) bakes "Creature" (Sinew, Chitin, Bone, Mouth) into one 1024 texture set with
one "Darter" PBR material. "Eyes" and "Glands" (the sting's tip and the slits along the abdomen) keep constant
emissive materials in the hive's yellow-green. "Wings" is not baked: it keeps its plain translucent "Wing" material
(constant color, alpha blended) and stays double-sided; it is hidden from the bake, so the membranes don't shade the
thorax's AO. The darter flies (its origin is the thorax center), so there is no ground plane under it for the AO.
The armature modifiers are taken off for the bake (the rest pose is baked) and put back before the export. Texture
size 1024 per the asset budget (a tier 5 hunter in packs), TBD (playtest).
"""

import json
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "darter"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Darter"
SKINNED = ("Creature", "Eyes", "Glands", "Wings")
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)
FLIGHT = 1.3  # height of the check renders only


def prepare(job: B.Job) -> list:
    for name in SKINNED:
        obj = bpy.data.objects[name]
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
    bpy.data.objects["Wings"].hide_render = True
    return []


def finish(job: B.Job, objs: list) -> None:
    C.assign(bpy.data.objects["Eyes"], B.mat_constant("Eyes", EYE_COLOR, roughness=0.2, emission=6.0))
    C.assign(bpy.data.objects["Glands"], B.mat_constant("Glands", EYE_COLOR, roughness=0.3, emission=3.0))
    wings = bpy.data.objects["Wings"]
    wings.hide_render = False
    wing = wings.data.materials[0]
    assert wing.name == "Wing" and B.is_constant(wing), wing.name
    wing.use_backface_culling = False
    wing.surface_render_method = "BLENDED"
    for name in SKINNED:
        obj = bpy.data.objects[name]
        obj.modifiers.new("Armature", "ARMATURE").object = bpy.data.objects["Skeleton"]


JOB = B.Job(
    name="darter",
    asset=ASSET,
    source=OUT / "darter_procedural.blend",
    glb=ROOT / "assets" / "aliens" / "darter" / "darter.glb",
    blend=ROOT / "assets" / "aliens" / "darter" / "source" / "darter.blend",
    game=OUT / "game",
    atlas=["Creature"],
    material="Darter",
    size=1024,  # final texture size (budget: one 1024 set, TBD (playtest))
    supersample=2,  # the wings' leading edges, claws, mandibles and the sting are small in the atlas
    island_margin=0.003,
    ao_distance=0.04,  # small creature: only close cavities darken
    double_sided=("Wings",),  # the membranes are single surfaces, seen from both sides
    prepare=prepare,
    finish=finish,
)


def glb_material(job: B.Job, name: str) -> dict:
    data = job.glb.read_bytes()
    n = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20 : 20 + n])
    return next(m for m in j["materials"] if m["name"] == name)


def checks(job: B.Job, meshes: list) -> None:
    print("CHECK actions", sorted(a.name for a in bpy.data.actions))
    print("CHECK Wing material", json.dumps(glb_material(job, "Wing")))
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:  # the importer's bone shape
        bpy.data.objects.remove(obj)
    for obj in C.collection(job.asset).all_objects:
        if obj.parent is None:
            obj.location.z += FLIGHT  # in the air, like in the game (the origin is the thorax center)
    C.preview_scene(crystals=False, figure_location=(1.0, 1.0, 0))
    target = (0, 0.08, FLIGHT)
    for view, zoom in (("iso", 0.22), ("hero", 0.26), ("back", 0.26)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=target, zoom=zoom)
    C.render_from(job.game / "check_top.png", Vector((0, 0.08, FLIGHT + 3.2)), target, 50, 64, 768)
    C.render_from(job.game / "check_head.png", Vector((0.45, -0.95, FLIGHT + 0.25)), (0, -0.28, FLIGHT), 50, 64, 768)


B.run(JOB, checks)
