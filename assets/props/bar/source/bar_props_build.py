"""Small things at the bar, one model each: a glass, a bottle, a rag (held by Nell while she works, see
assets/npcs/nell/source/nell_clips.py; for the bar's dressing later).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/props/bar/source/bar_props_build.py

Each one stands on the frame a hand holds it by (see tools/blender/people.py, things in the hands): its origin where
it's held, its up along +Z (Godot: +Y). Writes assets/props/bar/<name>.glb; renders go to tmp/assets/props/bar/.
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "props" / "bar"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
import numpy as np
from mathutils import Vector

import common as C


def lathe(name: str, profile: list, segments: int = 20) -> bpy.types.Mesh:
    """A round mesh from a profile ((radius, z) pairs, bottom to top) turned about +Z, closed at both ends."""
    verts = [(0.0, 0.0, profile[0][1])]
    for r, z in profile:
        for k in range(segments):
            a = 2 * math.pi * k / segments
            verts.append((r * math.cos(a), r * math.sin(a), z))
    verts.append((0.0, 0.0, profile[-1][1]))
    faces = [(0, 1 + (k + 1) % segments, 1 + k) for k in range(segments)]
    for i in range(len(profile) - 1):
        a, b = 1 + i * segments, 1 + (i + 1) * segments
        faces += [(a + k, a + (k + 1) % segments, b + (k + 1) % segments, b + k) for k in range(segments)]
    top, last = len(verts) - 1, 1 + (len(profile) - 1) * segments
    faces += [(top, last + k, last + (k + 1) % segments) for k in range(segments)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    return me


def cloth_lump(name: str, size: tuple, seed: int = 1) -> bpy.types.Mesh:
    """A crumpled cloth: a squashed, dented ball of `size` (m, x y z)."""
    rnd = np.random.default_rng(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.5)
    for v in bm.verts:
        v.co *= 1.0 + float(rnd.uniform(-0.25, 0.2))
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def material(name: str, color, roughness: float, alpha: float = 1.0) -> bpy.types.Material:
    """A plain material (sRGB color); alpha below 1 is see-through glass."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[c**2.2 for c in color], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = "BLENDED"
    return mat


PROPS = {  # name: (mesh, material)
    "Glass": (
        lambda: lathe("Glass", [(0.028, -0.045), (0.034, 0.05), (0.031, 0.05), (0.025, -0.04)]),
        lambda: material("Glass", (0.75, 0.85, 0.9), 0.05, alpha=0.35),
    ),
    "Bottle": (
        lambda: lathe("Bottle", [(0.033, -0.11), (0.035, 0.05), (0.014, 0.1), (0.012, 0.15), (0.014, 0.155)]),
        lambda: material("Bottle", (0.42, 0.24, 0.08), 0.15, alpha=0.85),
    ),
    "Rag": (
        lambda: cloth_lump("Rag", (0.1, 0.08, 0.035)),
        lambda: material("Rag", (0.55, 0.52, 0.46), 0.95),
    ),
}


def main() -> None:
    shots = []
    for name, (mesh, mat) in PROPS.items():
        C.reset(name)
        root = C.asset_root(name)
        me = mesh()
        me.materials.append(mat())
        obj = C.link(bpy.data.objects.new(name, me), root)
        for p in me.polygons:
            p.use_smooth = True
        print("PROP", name, C.stats())
        C.export_glb(ROOT / "assets" / "props" / "bar" / f"{name.lower()}.glb")
        C.preview_scene(crystals=False, figure_location=(30, 30, 0))
        obj.location.z = 0.25
        path = OUT / f"{name.lower()}.png"
        C.render_from(path, (0.3, -0.45, 0.45), (0, 0, 0.25), 50, 32, 384)
        shots.append(path)
    C.contact_sheet(shots, OUT / "sheet.png", cols=3, tile=384)


main()
