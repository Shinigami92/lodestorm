"""Game-ready habitat kit: bake the procedural look of habitat_procedural.blend (the colony's paint grown over with
moss, the hazard bands, the Overgrowth kit's growth with its faint glow, the status light's lens) into one shared
texture set.

Run from the repo root, after habitat_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/habitat/source/habitat_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/habitat/source/habitat_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/habitat/habitat.glb (textures embedded) and its source
assets/parts/habitat/source/habitat.blend; the separate PNGs and check renders go to tmp/assets/parts/habitat/game/.

The shared flow (tools/blender/bake.py) bakes the three pieces into one 2048 texture set (at 2x and scaled down, as the
Overgrowth kit: the plates' cracks) with one "Habitat" PBR material, with an emission map for the growth's bulbs and
tube throats and the red status light. The pieces stand in a row along X over a ground plane (AO and cavity grime see
the ground); faces below ground get a speck of the atlas. Their locations are zeroed for the export: every piece's
origin is its ground contact. Texel density is TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "habitat"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import habitat_build as HB

import bake as B
import common as C

BURIED_Z = -0.12  # a face whose corners all lie below this is never seen


def prepare(job: B.Job) -> list:
    xs = [bpy.data.objects[n].location.x for n in HB.PIECES]
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
    name="habitat",
    asset=HB.ASSET,
    source=OUT / "habitat_procedural.blend",
    glb=ROOT / "assets" / "parts" / "habitat" / "habitat.glb",
    blend=ROOT / "assets" / "parts" / "habitat" / "source" / "habitat.blend",
    game=OUT / "game",
    atlas=HB.PIECES,
    material="Habitat",
    island_margin=0.003,
    pack_margin=0.002,
    samples={"Base Color": 64, "Roughness": 48},  # AO-driven grime and Bevel-node wear in the albedo
    ao_distance=0.5,
    emission_strength=HB.LAMP_STRENGTH,
    shrink=buried,
    drop_attributes=("grad", "glow", "plate"),
    supersample=2,
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, meshes: list) -> None:
    assert sorted(o.name for o in meshes) == sorted(HB.PIECES), [o.name for o in meshes]
    for o in meshes:
        o.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    HB.setup_preview()
    paths = []
    for name in HB.PIECES:
        paths += HB.render_piece(name, "game/check_", ("iso", "hero"), 48, 768)
    paths.append(HB.render_layout(job.game / "check_layout_a.png", "a", 64, 1024))
    paths.append(HB.render_layout(job.game / "check_layout_b.png", "b", 64, 1024))
    C.contact_sheet(paths, job.game / "sheet.png", cols=4, tile=512, background=0.02)


B.run(JOB, checks)
