"""Game-ready wreck kit: bake the procedural look of wreck_procedural.blend into one shared texture set.

Run from the repo root, after wreck_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/wreck/source/wreck_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/wreck/source/wreck_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/wreck/wreck.glb (textures embedded) and its source
assets/parts/wreck/source/wreck.blend; the separate PNGs and check renders go to tmp/assets/parts/wreck/game/.

The shared flow (tools/blender/bake.py) bakes all seven pieces into one 2048 texture set (base color, ORM, normal; no
emission, nothing on the wreck still glows) with one "Wreck" PBR material. Smart-project unwrap; the faces nobody
sees (the hull's buried belly, everything well below ground) are shrunk to specks. Each shrunk face becomes its own
island, so only faces that are never seen are shrunk (thin visible faces would bake as smeared slivers). The
pieces stand in a row for the bake (no AO from a neighbor); their locations are zeroed for the export.

Every piece is its own mesh node under the "Wreck" root, origin at its ground contact (the hull: its underside's
middle); the game reads each one by name (ModelParts). Texel density and budgets are TBD (playtest).
"""

import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT / "tmp" / "assets" / "parts" / "wreck"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(HERE))

import bpy
import wreck_build as W

import bake as B
import common as C

BURIED_UV_SCALE = 0.06  # the hull's belly and everything deep below ground: in the atlas, but tiny


def hidden_scale(obj: bpy.types.Object, poly: bpy.types.MeshPolygon) -> float | None:
    """UV scale for faces the camera sees little of (see the module docstring), else None."""
    if obj.name == "Wreck_hull":
        return BURIED_UV_SCALE if poly.normal.z < -0.9 and poly.center.z < 0.2 else None
    return BURIED_UV_SCALE if poly.center.z < -0.25 else None


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every piece sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="wreck",
    asset=W.ASSET,
    source=OUT / "wreck_procedural.blend",
    glb=ROOT / "assets" / "parts" / "wreck" / "wreck.glb",
    blend=ROOT / "assets" / "parts" / "wreck" / "source" / "wreck.blend",
    game=OUT / "game",
    atlas=W.PARTS,
    material=W.MATERIAL,
    size=2048,
    shrink=hidden_scale,
    # The base color carries AO grime and Bevel-node chips (both ray traced): more samples than flat colors.
    samples={"Base Color": 64},
    ao_distance=0.4,
    drop_attributes=("facet", "kind", "soot"),
    finish=finish,
)


def checks(job: B.Job, parts: list) -> None:
    """The baked kit in the proposed layout from the game's angle (far and close), the kit from the preview angles
    and every piece alone, as one contact sheet."""
    assert sorted(o.name for o in parts) == sorted(W.PARTS), [o.name for o in parts]
    W.OUT = job.game
    W.setup_preview()
    paths = W.render_layout("check_", 64, 1024)
    paths += W.render_kit("check_", ("iso", "hero"), 48, 1024)
    for name in W.PARTS:
        paths += W.render_part(name, "check_", ("iso",), 32, 640)
    C.contact_sheet(paths, job.game / "check_sheet.png", tile=512, background=0.02)


B.run(JOB, checks)
