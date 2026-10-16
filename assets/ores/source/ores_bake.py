"""Game-ready ore clusters: bake the procedural rock of one ore's ores_procedural.blend into its texture atlas.

Run from the repo root, after ores_build.py final <ore> (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/ores/source/ores_bake.py kyrite          # bake, export, check renders
    tools/blender.sh assets/ores/source/ores_bake.py kyrite verify   # only re-import and render the checks

One model kit per ore, so ores can be added and re-baked one at a time (and two at once, in parallel). Writes the
game asset assets/ores/<ore>.glb (textures embedded) and its source assets/ores/source/<ore>.blend; the separate
PNGs, check renders and the procedural-vs-baked comparison sheets go to tmp/assets/ores/<ore>/game/.

The shared flow (tools/blender/bake.py) bakes the three Base_* rocks into one 512 atlas (at 2x, filtered down) with
one "OreRock" PBR material; the crystals keep the constant "OreCrystal" placeholder (the game overrides it). A
temporary ground plane and cliff wall let the AO see what the previews saw; faces buried under the ground or pressed
against the cliff get almost no texture space. The roots are exported at the origin (the .blend keeps the grid).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "assets" / "ores"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import bake as B  # noqa: E402
import common as C  # noqa: E402

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import importlib  # noqa: E402

ARGV = [a for a in C.args() if a != "verify"]
if not ARGV:
    raise SystemExit("usage: ores_bake.py <ore> [verify]")
ORE = ARGV[0]
SPEC = importlib.import_module(f"ore_types.{ORE}").ORE
VARIANTS = ("a", "b", "wall")
NAMES = [f"{ORE}_{v}" for v in VARIANTS]
OUT = OUT / ORE
LAYOUT_SPACING = 3.4  # roots sit on this grid in the procedural .blend (ores_build.py)
PREVIEW_GLOW = 1.0


def bake_props(job: B.Job) -> list:
    """Ground plane at z = 0 under everything and the cliff face behind the wall row (y = +LAYOUT_SPACING), as in
    the previews: the rock's AO picks up the contact shadow where it meets terrain and cliff."""
    return [
        B.bake_plane("BakeGround", scale=(12, 12, 1)),
        B.bake_plane("BakeCliff", (0, LAYOUT_SPACING, 1.6), (math.radians(90), 0, 0), (12, 1.6, 1)),
    ]


def hidden_face(obj: bpy.types.Object, poly) -> float | None:
    """Faces the camera never sees shrink to 3 %: fully under the ground (z <= 0), or the flat back of a wall
    cluster that lies on the cliff plane (y = 0, facing +Y)."""
    zs = [obj.data.vertices[i].co.z for i in poly.vertices]
    if max(zs) < 0.003:
        return 0.03
    if obj.name.endswith("_wall"):
        ys = [obj.data.vertices[i].co.y for i in poly.vertices]
        if poly.normal.y > 0.95 and max(abs(y) for y in ys) < 0.003:
            return 0.03
    return None


JOB = B.Job(
    name=ORE,
    asset="Ores",
    source=OUT / "ores_procedural.blend",
    glb=ROOT / "assets" / "ores" / f"{ORE}.glb",
    blend=ROOT / "assets" / "ores" / "source" / f"{ORE}.blend",
    game=OUT / "game",
    atlas=[f"Base_{n}" for n in NAMES],
    material="OreRock",
    size=512,  # the ore's three bases; TBD (playtest)
    supersample=2,  # anti-aliased cracks and edges
    # The bases are faceted rock, so smart project makes many small islands: a scaled margin would eat most of the
    # atlas. 2 px at 512.
    island_margin=0.0,
    pack_margin=0.004,
    shrink=hidden_face,
    drop_attributes=("Crust",),  # baked; keep it out of the glb
    export_at_origin=tuple(f"Ore_{n}" for n in NAMES),  # the game places each cluster by its root
    prepare=bake_props,
)


# --- checks -------------------------------------------------------------------------------------------


def bounds(objs: list) -> tuple:
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return Vector(map(min, *pts)), Vector(map(max, *pts))


def preview_crystal() -> bpy.types.Material:
    """Like ores_build.py: the game's ore material, dimmer (Cycles + AgX burns the real energy to white)."""
    mat = C.mat_emissive(f"PreviewOre_{ORE}", SPEC.color, PREVIEW_GLOW)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Base Color"].default_value = (*(c * 0.3 for c in SPEC.color), 1.0)
    if SPEC.dark_body:
        bsdf.inputs["Base Color"].default_value = (0.012, 0.012, 0.014, 1.0)
        bsdf.inputs["Emission Strength"].default_value = PREVIEW_GLOW * 0.12
    return mat


def cliff(show: bool) -> None:
    """Same stand-in cliff as ores_build.py's previews (its front face on the wall plane y = 0)."""
    obj = bpy.data.objects.get("PreviewCliff")
    if obj is None:
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        for c in obj.users_collection:
            c.objects.unlink(obj)
        C.link(obj, None, "Preview")
        obj.name = "PreviewCliff"
        obj.scale = (5.0, 1.0, 3.2)
        obj.location = (0, 0.5, 1.6)
        C.assign(obj, bpy.data.materials["PreviewRock"])
    obj.hide_render = not show


def checks(job: B.Job, meshes: list) -> None:
    roots = [bpy.data.objects[f"Ore_{n}"] for n in NAMES]
    for root in roots:
        base = [o for o in root.children if o.name.startswith("Base_")]
        crys = [o for o in root.children if o.name.startswith("Crystal_")]
        other = [o.name for o in root.children if o not in base and o not in crys]
        lo, hi = bounds(base)
        _clo, chi = bounds(crys)
        rad = max(math.hypot(*(o.matrix_world @ v.co).xy) for o in crys for v in o.data.vertices if (o.matrix_world @ v.co).z > 0.04)
        print(
            f"CHECK {root.name}: root at {tuple(round(x, 3) for x in root.location)}, {len(crys)} crystals, base min"
            f" {tuple(round(x, 2) for x in lo)} max {tuple(round(x, 2) for x in hi)}; crystal top {chi.z:.2f} radius"
            f" {rad:.2f}; other {other}"
        )
    crystals = [o for o in meshes if o.name.startswith("Crystal_")]
    print("CHECK crystals", len(crystals), "names ok", all(o.name.split("_")[1] == ORE for o in crystals))

    C.preview_scene(crystals=False, figure_location=(1.7, 1.7, 0.0))
    for o in crystals:
        C.assign(o, preview_crystal())
    cliff(False)

    def solo(keep) -> None:
        for r in roots:
            for o in [r] + list(r.children_recursive):
                o.hide_render = r is not keep and keep is not None

    for r in roots:
        solo(r)
        ground = not r.name.endswith("_wall")
        cliff(not ground)
        tz = 0.35 if ground else 0.65
        ty = 0.0 if ground else -0.3
        stem = r.name[len("Ore_") :]
        C.render(job.game / f"check_{stem}_iso.png", "iso", 64, 768, target=(0, ty, tz), zoom=0.4)
        C.render(job.game / f"check_{stem}_hero.png", "hero", 64, 768, target=(0, ty, tz + 0.07), zoom=0.48)
    cliff(False)
    solo(None)
    bpy.data.objects["PreviewFigure"].location = (4.6, 4.6, 0)
    for r in roots:  # the build's layout grid, game-camera distance
        v = r.name.split("_")[2]
        r.location = (0, (VARIANTS.index(v) - 1) * LAYOUT_SPACING, 0)
    C.render(job.game / "check_game_distance.png", "iso", 64, 1024, target=(0, 0, 0.3), zoom=1.45)
    C.render(job.game / "check_iso.png", "iso", 96, 1024, target=(0, 0, 0.3), zoom=1.0)
    C.render(job.game / "check_hero.png", "hero", 96, 1024, target=(0, 0, 0.3), zoom=1.3)
    # Procedural previews (left) next to the baked checks (right).
    for view in ("iso", "hero"):
        paths = []
        for n in NAMES:
            paths += [OUT / f"render_{n}_{view}.png", job.game / f"check_{n}_{view}.png"]
        C.contact_sheet(paths, job.game / f"compare_{view}.png", 2, 384)


B.run(JOB, checks)
