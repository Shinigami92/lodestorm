"""Game-ready drill rig kit: bake the procedural look of drill_rig_procedural.blend (the colony's paint, the hazard
stripes, the pipes' steel, the Frost kit's ice and the beacon's lens) into one shared texture set.

Run from the repo root, after drill_rig_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/drill_rig/source/drill_rig_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/drill_rig/source/drill_rig_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/drill_rig/drill_rig.glb (textures embedded) and its source
assets/parts/drill_rig/source/drill_rig.blend; the separate PNGs and check renders go to
tmp/assets/parts/drill_rig/game/.

The shared flow (tools/blender/bake.py) bakes the three pieces into one 2048 texture set with one "DrillRig" PBR
material, with an emission map for the beacon's red lens (the only glow). The pieces stand in a row along X over a
ground plane (AO and cavity grime see the ground); faces below ground get a speck of the atlas. Their locations are
zeroed for the export: every piece's origin is its ground contact. Texel density is TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "drill_rig"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import drill_rig_build as RB

import bake as B
import common as C

BURIED_Z = -0.12  # a face whose corners all lie below this is never seen


def prepare(job: B.Job) -> list:
    xs = [bpy.data.objects[n].location.x for n in RB.PIECES]
    mid = (min(xs) + max(xs)) / 2
    return [B.bake_plane("BakeGround", location=(mid, 0, 0), scale=(max(xs) - min(xs) + 30, 30, 1))]


def buried(obj: bpy.types.Object, poly) -> float | None:
    """UV scale for faces nobody sees: entirely below ground."""
    if all(obj.data.vertices[i].co.z < BURIED_Z for i in poly.vertices):
        return 0.08
    return None


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row was layout only


JOB = B.Job(
    name="drill_rig",
    asset=RB.ASSET,
    source=OUT / "drill_rig_procedural.blend",
    glb=ROOT / "assets" / "parts" / "drill_rig" / "drill_rig.glb",
    blend=ROOT / "assets" / "parts" / "drill_rig" / "source" / "drill_rig.blend",
    game=OUT / "game",
    atlas=RB.PIECES,
    material="DrillRig",
    island_margin=0.003,
    pack_margin=0.002,
    samples={"Base Color": 64, "Roughness": 48},  # AO-driven grime and Bevel-node wear in the albedo
    ao_distance=0.5,
    emission_strength=RB.LAMP_STRENGTH,
    shrink=buried,
    drop_attributes=("facet",),
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    assert sorted(o.name for o in meshes) == sorted(RB.PIECES), [o.name for o in meshes]
    for o in meshes:
        o.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    RB.setup_preview()
    paths = []
    for name in RB.PIECES:
        paths += RB.render_piece(name, "game/check_", ("iso", "hero"), 48, 768)
    paths.append(RB.render_layout(job.game / "check_layout_a.png", "a", 64, 1024))
    paths.append(RB.render_layout(job.game / "check_layout_b.png", "b", 64, 1024))
    C.contact_sheet(paths, job.game / "sheet.png", cols=4, tile=512, background=0.02)


B.run(JOB, checks)
