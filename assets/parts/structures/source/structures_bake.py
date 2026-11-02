"""Game-ready colony structures kit: bake the procedural look of structures_procedural.blend into one texture set.

Run from the repo root, after structures_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/structures/source/structures_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/structures/source/structures_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/structures/structures.glb (textures embedded) and its source
assets/parts/structures/source/structures.blend; the separate PNGs and check renders go to
tmp/assets/parts/structures/game/.

The shared flow (tools/blender/bake.py) bakes all eleven pieces into one 2048 texture set (base color, ORM, normal
and emission: the mast's red light, the beacon lens, the pad's lights and the shelter's lit window glow) with one
"Structures" PBR material (emissive strength EMISSION; the emission texture holds color * glow / EMISSION).
Smart-project unwrap; faces looking down (bottoms, undersides nobody sees from the game camera) and the skirts below
ground are shrunk. The pieces stand in a row on a ground plane for the bake (contact AO, no AO from a neighbor);
their locations are zeroed for the export.

Every piece is its own mesh node at the kit's root, origin at its ground contact point (the lens at its center);
the map parts place them by name (ModelParts). Texel density and budgets are TBD (playtest).
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import structures_build as S

import bake as B
import common as C

DOWN_UV_SCALE = 0.12  # faces looking down: never seen from the game camera
BURIED_UV_SCALE = 0.3  # faces below ground (skids, skirts, footings)


SPLIT_UV_SCALE = 0.85  # faces of hollow rings (rib sides, flat bands): each its own island, no empty frames


def hidden_scale(obj: bpy.types.Object, poly: bpy.types.MeshPolygon) -> float | None:
    """UV scale for faces nobody sees (looking down, below ground) and for the faces of hollow rings, which pack as
    empty frames otherwise (scaling a face around its own center makes it its own island)."""
    if poly.normal.z < -0.7:
        return DOWN_UV_SCALE
    if obj.name != "Expedition_lens" and max(obj.data.vertices[v].co.z for v in poly.vertices) < -0.02:
        return BURIED_UV_SCALE
    if obj.data.attributes["split"].data[poly.index].value:
        return SPLIT_UV_SCALE
    return None


def prepare(job: B.Job) -> list:
    """A ground plane under the row of pieces: the AO picks up the contact shadow at their feet."""
    return B.row_ground(S.PIECES, 20)


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every piece sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.kit_job(
    __file__,
    S.OUT,
    asset=S.ASSET,
    atlas=S.PIECES,
    material="Structures",
    size=2048,
    # Thousands of small islands (rods, ribs, stencils): a 2 px gap instead of 6 px doubles the texel density.
    pack_margin=0.001,
    shrink=hidden_scale,
    # The base color carries AO grime and Bevel-node chips (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    emission_strength=S.EMISSION,
    drop_attributes=("split",),
    prepare=prepare,
    finish=finish,
)


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(S.PIECES), [o.name for o in parts]
    for o in parts:
        o.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    S.setup_preview()
    rel = job.game.relative_to(S.OUT) if job.game.is_relative_to(S.OUT) else None
    sheet = []
    for name in S.PIECES:
        if name == "Expedition_lens":
            continue
        paths = S.render_piece(name, f"{rel.as_posix()}/check_" if rel else "check_", ("iso",), 32, 640, parts)
        sheet += paths
    for name in S.LAYOUTS:
        sheet.append(S.render_layout(name, job.game / f"check_layout_{name}.png", 64, 1024, parts))
    C.contact_sheet(sheet, job.game / "check_sheet.png", cols=4, tile=480, background=0.02)


B.run(JOB, checks)
