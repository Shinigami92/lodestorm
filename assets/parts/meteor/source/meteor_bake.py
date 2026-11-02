"""Game-ready meteor crater kit: bake the procedural look of meteor_procedural.blend (crust, metal interior, cracks
and rock) into one shared texture set.

Run from the repo root, after meteor_build.py final (see docs/technical/assets.md):
    tools/blender.sh assets/parts/meteor/source/meteor_bake.py          # bake, export, check renders
    tools/blender.sh assets/parts/meteor/source/meteor_bake.py verify   # only re-import and render the checks

Writes the game asset assets/parts/meteor/meteor.glb (textures embedded) and its source
assets/parts/meteor/source/meteor.blend; the separate PNGs and check renders go to tmp/assets/parts/meteor/game/.

The shared flow (tools/blender/bake.py) bakes the five pieces into one 2048 texture set with one "Meteor" PBR
material: base color, ORM (metallic baked: the interior is metal), normal, and the faint dull-red ember deep in the
meteorite's cracks as an emission map (emission strength EMBER). UV unwrap `bake.chart_unwrap`, as the biome kits':
charts grown over the faces and flattened conformally, folded faces split off, the never-seen bottom caps shrunk.
The pieces stand in a row for the bake (no AO from a neighbor); their locations are zeroed for the export.

Every piece is its own mesh node at the kit's root, origin at its ground contact point (z = 0, the meteorite buried
1.2 m below it); the part's scene places them by name. Texel density and budgets are TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "parts" / "meteor"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import bpy
import meteor_build as build  # the kit's pieces and layout (importing it doesn't run the build)
from mathutils import Vector

import bake as B
import common as C

SIZE = 2048
EMBER = 1.0  # emission strength the ember map is scaled by (the procedural ember stays below it)


# --- bake job -----------------------------------------------------------------------------------------


def finish(job: B.Job, objs: list) -> None:
    for o in objs:
        o.location = (0, 0, 0)  # the bake row layout; in the game every piece sits at its own origin
        o.rotation_euler = (0, 0, 0)


JOB = B.Job(
    name="meteor",
    asset="Meteor",
    source=OUT / "meteor_procedural.blend",
    glb=ROOT / "assets" / "parts" / "meteor" / "meteor.glb",
    blend=ROOT / "assets" / "parts" / "meteor" / "source" / "meteor.blend",
    game=OUT / "game",
    atlas=build.PIECES,
    material="Meteor",
    size=SIZE,
    unwrap=B.chart_unwrap(by_material=True),
    # The base color carries AO cavity grime and Bevel-node edges (both ray traced): more samples than flat colors.
    samples={"Base Color": 64, "Emission": 64},
    ao_distance=0.4,
    emission_strength=EMBER,
    drop_attributes=("facet",),
    finish=finish,
)


# --- check renders ---------------------------------------------------------------------------------------

FRONT_Y = ()


def checks(job: B.Job, parts: list) -> None:
    assert sorted(o.name for o in parts) == sorted(build.PIECES), [o.name for o in parts]
    C.preview_scene(crystals=False)
    for obj in list(C.collection("Preview").objects):  # drop the placeholder pebbles, like the build previews
        if obj.type == "MESH" and obj.data.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj)
    for o in parts:
        o.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    for name in build.PIECES:
        for view in ("iso", "hero"):
            B.render_closeup(job, bpy.data.objects[name], parts, view, math.pi if name in FRONT_Y else 0.0)
    # The part's layout from the game's angle (front side), the studio lights.
    for name, pos, rot, scale in build.LAYOUT:
        obj = bpy.data.objects[name]
        obj.location = (pos[0], -pos[2], pos[1])
        obj.rotation_euler = (0, 0, math.radians(rot))
        obj.scale = (scale,) * 3
    bpy.data.objects["PreviewFigure"].location = (2.4, 4.6, 0)
    center = Vector((0, 0, 0.8))
    a, pitch = math.radians(45), math.radians(50)
    loc = center + Vector((math.cos(a) * math.cos(pitch), math.sin(a) * math.cos(pitch), math.sin(pitch))) * 24.0
    C.render_from(job.game / "check_layout.png", loc, center, lens=42.0, samples=64, size=1024)


if __name__ == "__main__":
    B.run(JOB, checks)
