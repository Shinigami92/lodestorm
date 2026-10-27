"""Game-ready player: bake the procedural look of player_procedural.blend into one texture set.

Run from the repo root, after player_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/player/source/player_bake.py          # bake, export, check renders
    tools/blender.sh assets/player/source/player_bake.py verify   # only re-import and render the checks
    tools/blender.sh assets/player/source/player_bake.py clips    # only add new clips, without baking again

"clips" takes the clips player_build.py added since the last bake (in player_procedural.blend, not yet in
player.blend) into player.blend and exports the .glb again, keeping the baked textures (the skeleton has to be
unchanged).

Writes the game asset assets/player/player.glb (textures, skeleton and animations embedded) and its source
assets/player/source/player.blend; the separate PNGs and check renders go to tmp/assets/player/game/.

The shared flow (tools/blender/bake.py) bakes "Suit" into one 2048 texture set with one "Suit" PBR material
(its glowing lamps and panels baked into its emission), keeping the generated mesh's UV layout (same size: its
textures aren't resampled). "SuitLight" keeps its constant emissive material (the game
drives its color by health). The armature modifiers are taken off for the bake (the rest pose is baked) and put
back before the export. Texture size 2048 per the asset budget, TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "player"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import bake as B
import common as C

ASSET = "Player"
SKINNED = ("Suit", "SuitLight")


def prepare(job: B.Job) -> list:
    for name in SKINNED:
        obj = bpy.data.objects[name]
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
    return [B.bake_plane("BakeGround", scale=(4, 4, 1))]


def keep_uvs(job: B.Job, objs: list) -> None:
    """The generated suit comes unwrapped and textured: bake into its own layout."""
    for o in objs:
        o.data.uv_layers.active.name = "UVMap"


def finish(job: B.Job, objs: list) -> None:
    for name in SKINNED:
        obj = bpy.data.objects[name]
        obj.modifiers.new("Armature", "ARMATURE").object = bpy.data.objects["Skeleton"]


JOB = B.Job(
    name="player",
    asset=ASSET,
    source=OUT / "player_procedural.blend",
    glb=ROOT / "assets" / "player" / "player.glb",
    blend=ROOT / "assets" / "player" / "source" / "player.blend",
    game=OUT / "game",
    atlas=["Suit"],
    material="Suit",
    size=2048,  # final texture size (budget: one 2048 set, TBD (playtest))
    unwrap=keep_uvs,
    ao_distance=0.06,  # the suit is small: only close cavities darken
    emission_strength=6.0,
    prepare=prepare,
    finish=finish,
)


def add_clips(job: B.Job) -> None:
    """Appends the build's clips missing from the game source, each in its own muted NLA track like the build's,
    then exports the .glb and saves the source again."""
    bpy.ops.wm.open_mainfile(filepath=str(job.blend))
    C.ASSET = job.asset
    have = {a.name for a in bpy.data.actions}
    with bpy.data.libraries.load(str(job.source), link=False) as (src, dst):
        dst.actions = [name for name in src.actions if name not in have]
    ad = bpy.data.objects["Skeleton"].animation_data_create()
    for act in dst.actions:
        track = ad.nla_tracks.new()
        track.name = act.name
        strip = track.strips.new(act.name, 0, act)
        if act.slots:
            strip.action_slot = act.slots[0]
        track.mute = True
        print("CLIP added", act.name)
    C.export_glb(job.glb)
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backup next to the source
    bpy.ops.wm.save_as_mainfile(filepath=str(job.blend))


def checks(job: B.Job, meshes: list) -> None:
    print("CHECK actions", sorted(a.name for a in bpy.data.actions))
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:  # the importer's bone shape
        bpy.data.objects.remove(obj)
    C.preview_scene(crystals=False, figure_location=(30, 30, 0))
    target = (0, 0, 0.95)
    for view, zoom in (("iso", 0.42), ("hero", 0.62), ("back", 0.6)):
        C.render(job.game / f"check_{view}.png", view=view, samples=64, size=1024, target=target, zoom=zoom)
    C.render_from(job.game / "check_close.png", Vector((0.5, -1.2, 1.55)), (0, 0, 1.45), 40, 64, 768)


if "clips" in sys.argv:
    add_clips(B.redirected(JOB))
    sys.argv.append("verify")
B.run(JOB, checks)
