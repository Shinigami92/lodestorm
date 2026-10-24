"""Nell, the bartender at Waypost Ostra: a sturdy woman in her forties with a braid, a work shirt, cargo trousers
tucked into boots, an apron and a belt (reference: the batch-8 concept "nell_v2", see GAME_DESIGN.md, Art direction).

Run from the repo root (see docs/TECHNICAL.md, People):
    tools/blender.sh assets/npcs/nell/source/nell_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/nell/source/nell_build.py final    # renders, nell.blend and the game asset

Made with MakeHuman (tools/blender/people.py): the body from MPFB's sliders, the shirt, trousers, boots, hair, eyes,
brows and lashes from installed CC0 asset packs (retinted here), the apron and the belt made here. Skeleton
"Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle" and "Walk" from the shared pose code.
Meshes: "Skin", "Eyes", "Brows", "Lashes", "Hair", "Shirt", "Trousers", "Boots", "Apron", "Strap", "Belt"; empty "HeadTop" on
the head (where the name plate and the bubbles go).

Writes assets/npcs/nell/nell.glb and its source assets/npcs/nell/source/nell.blend; renders go to tmp/assets/npcs/nell/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "npcs" / "nell"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
import numpy as np
import people as P

import common as C
import generated as G
import humanoid as H

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Nell"
PERSON = {
    "macro": {
        "gender": 0.0,
        "age": 0.65,  # about 45
        "muscle": 0.6,
        "weight": 0.6,
        "proportions": 0.5,
        "height": 0.6,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05},
    },
    "skin": "middleage_caucasian_female",
    "assets": [
        ("eyes", "low-poly", "Eyes"),
        ("eyebrows", "eyebrow010", "Brows"),
        ("eyelashes", "eyelashes04", "Lashes"),
        ("hair", "braid01", "Hair"),
        ("clothes", "toigo_basic_tucked_t-shirt", "Shirt"),
        ("clothes", "cortu_cargo_pants", "Trousers"),
        ("clothes", "culturalibre_male_boots", "Boots"),
    ],
}
# Each part's export material: its texture multiplied by a tint (sRGB), its roughness, whether its alpha cuts (cards):
# the concept's dark slate shirt, dark grey trousers, worn brown boots, her brown hair.
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
    "Eyes": ((1.0, 1.0, 1.0), 0.2, False),
    "Brows": ((1.0, 1.0, 1.0), 0.8, True),
    "Lashes": ((1.0, 1.0, 1.0), 0.8, True),
    "Hair": (((0.2, 0.14, 0.09), (0.6, 0.47, 0.33)), 0.6, True),
    "Shirt": ((0.26, 0.29, 0.33), 0.9, False),
    "Trousers": ((0.75, 0.75, 0.8), 0.85, False),
    "Boots": ((0.8, 0.72, 0.62), 0.7, False),
}
BOOTS_TRIS = 3000  # the asset's boots are 31k triangles
TUCK = 0.8  # the trousers' legs inside the boots, narrowed to this share (around the leg's middle)
APRON_WIDTHS = (0.12, 0.17, 0.22)  # half-widths (m) at the bib's top, the waist and the hem
POUCHES = ((55, (0.09, 0.1, 0.05)), (305, (0.09, 0.1, 0.05)), (95, (0.06, 0.16, 0.06)))  # angle, size (m)
CANVAS = ((0.5, 0.48, 0.44), (0.3, 0.26, 0.22))  # the apron: worn pale canvas with dark stains
LEATHER = ((0.25, 0.16, 0.1), (0.12, 0.08, 0.05))
TATTOO_INK = (0.12, 0.15, 0.17)  # faded blue-black
TATTOO_STRENGTH = 0.6
TATTOO_SPAN = (0.2, 0.8)  # along the forearm, elbow to wrist


def decimate(obj: bpy.types.Object, tris: int) -> None:
    obj.data.calc_loop_triangles()
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = tris / len(obj.data.loop_triangles)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
    bpy.ops.object.modifier_apply(modifier="Decimate")


def tuck(trousers: bpy.types.Object, boots: bpy.types.Object) -> None:
    """Narrows the trousers' legs below the boots' tops, so the boots show over them."""
    bco = G.vertices(boots.data)
    co = G.vertices(trousers.data)
    for s in (1.0, -1.0):
        side = bco[bco[:, 0] * s > 0]
        top = float(np.percentile(side[:, 2], 98))
        legs = (co[:, 0] * s > 0) & (co[:, 2] < top + 0.02)
        mid = side[side[:, 2] > top - 0.1, :2].mean(0)
        co[legs, :2] = mid + (co[legs, :2] - mid) * TUCK
        print("TUCK", "left" if s > 0 else "right", "boot top", round(top, 3), int(legs.sum()), "vertices")
    G.set_vertices(trousers.data, co)


def lengthen(shirt: bpy.types.Object, below: float, by: float) -> None:
    """Pulls the shirt's hem down (its lower part, below `below`, stretched by up to `by`), so no skin shows
    between it and the belt."""
    co = G.vertices(shirt.data)
    low = co[:, 2] < below
    bottom = co[low, 2].min()
    co[low, 2] -= by * (1 - (co[low, 2] - bottom) / (below - bottom))
    G.set_vertices(shirt.data, co)


def tattoos(skin: bpy.types.Object, arm: bpy.types.Object, body: H.Body) -> None:
    """Ink on the backs of her forearms (the concept's tattoos): swirling lines from noise contours, painted into the
    skin texture where the forearms' backs are (from a fifth to four fifths of the way to the wrist)."""
    me = skin.data
    names = [f"{side}LowerArm" for side, _s in H.SIDES]
    w = P.weight_matrix(skin, names)
    co = G.vertices(me)
    faces = []
    for (side, _s), col in zip(H.SIDES, range(2), strict=True):
        elbow = np.array(arm.data.bones[f"{side}LowerArm"].head_local)
        wrist = np.array(arm.data.bones[f"{side}Hand"].head_local)
        axis = wrist - elbow
        back = -np.array(body.rest[f"{side}Hand"][1])
        for poly in me.polygons:
            idx = list(poly.vertices)
            if w[idx, col].mean() < 0.6:
                continue
            t = float(np.dot(co[idx].mean(0) - elbow, axis) / np.dot(axis, axis))
            if TATTOO_SPAN[0] < t < TATTOO_SPAN[1] and np.dot(poly.normal, back) > 0.2:
                faces.append(poly)
    img = G.base_color_image(me.materials[0])
    size = img.size[0]
    cover = G.uv_cover(me, faces, size, grow=1)
    lines = np.abs(P.noise(size, 64, 11, 3) - 0.5) < 0.022
    lines |= np.abs(P.noise(size, 128, 12, 2) - 0.5) < 0.012
    ink = (cover & lines)[..., None].astype(np.float32) * TATTOO_STRENGTH
    rgba = G.image_pixels(img)
    rgba[..., :3] = rgba[..., :3] * (1 - ink) + np.array(TATTOO_INK, dtype=np.float32) * ink
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    print("TATTOOS on", len(faces), "faces,", int((cover & lines).sum()), "pixels")


def garments(arm: bpy.types.Object, parts: dict) -> None:
    """The apron with its neck strap, and the belt over it with the pouches."""
    head = {b.name: b.head_local for b in arm.data.bones}
    names = [b.name for b in arm.data.bones]
    top = head["LeftUpperArm"].z - 0.08
    waist = (head["Spine"].z + head["Chest"].z) / 2
    hem = head["LeftLowerLeg"].z + 0.06
    neck = head["Neck"].z
    print("APRON top", round(top, 3), "waist", round(waist, 3), "hem", round(hem, 3), "neck", round(neck, 3))
    body = P.Surface([parts[n] for n in ("Skin", "Shirt", "Trousers")], names)
    parts["Apron"] = P.apron(arm, body, top=top, waist=waist, hem=hem, widths=APRON_WIDTHS, drop=0.025)
    half = APRON_WIDTHS[0] - 0.015
    path = [(half, -0.2, top), (0.08, -0.1, (top + neck) / 2), (0.07, 0.0, neck), (0.0, 0.1, neck + 0.02)]
    path += [(-x, y, z) for x, y, z in reversed(path[:-1])]
    parts["Strap"] = P.strap(arm, body, path)
    over = P.Surface([parts[n] for n in ("Skin", "Shirt", "Trousers", "Apron")], names)
    parts["Belt"] = P.belt(arm, over, z=waist - 0.01, height=0.085, pouches=POUCHES)
    parts["Apron"].data.materials.append(P.worn_material("Apron", *CANVAS, seed=3, seam=0.015))
    leather = P.worn_material("Leather", *LEATHER, size=512, seed=5, roughness=0.6)
    for name in ("Strap", "Belt"):
        parts[name].data.materials.append(leather)


def head_top(arm: bpy.types.Object, parts: dict) -> None:
    """An empty on the head at the top of the hair (the name plate and the bubbles sit above it)."""
    co = np.vstack([G.vertices(parts[n].data) for n in ("Skin", "Hair")])
    top = float(co[:, 2].max())
    e = bpy.data.objects.new("HeadTop", None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = 0.1
    C.link(e)
    e.parent = arm
    e.parent_type = "BONE"
    e.parent_bone = "Head"
    bpy.context.view_layer.update()
    e.matrix_world = C.T((0, 0, top))
    print("HEAD top", round(top, 3))


def clips(body: H.Body) -> dict:
    return {
        "Idle": (60, lambda t: H.idle(body, t)),
        "Walk": (H.WALK_FRAMES, lambda t: H.walk(body, t)),
    }


def preview(arm: bpy.types.Object, body: H.Body, tag: str) -> None:
    C.preview_scene(crystals=False, figure_location=(30, 30, 0))
    shots = []
    for name, pose in (("rest", None), ("idle", H.idle(body, 0.25)), ("walk0", H.walk(body, 0.0))):
        if pose:
            H.apply(arm, pose)
        else:
            H.rest_pose(arm)
        bpy.context.view_layer.update()
        for view, loc in (("front", (0, -3.4, 1.0)), ("side", (3.4, -0.4, 1.0)), ("back", (-1.2, 3.2, 1.2))):
            path = OUT / "wip" / f"{tag}_{name}_{view}.png"
            C.render_from(path, loc, (0, 0, 0.85), 40, 32, 512)
            shots.append(path)
    H.rest_pose(arm)
    for name, loc, target in (
        ("face", (0.25, -0.9, 1.6), (0, 0, 1.55)),
        ("forearm", (0.75, -0.55, 1.35), (0.36, -0.08, 1.02)),
        ("waist", (-0.3, 1.3, 1.1), (0, 0, 1.0)),
    ):
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render_from(path, loc, target, 50, 48, 512)
        shots.append(path)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=3, tile=384)


def main() -> None:
    C.reset(ASSET)
    P.enable()
    root = C.asset_root(ASSET)
    arm, parts = P.build(PERSON, root)
    for name, (tint, roughness, clip) in LOOKS.items():
        P.export_material(parts[name], tint, roughness, clip, 2048 if name == "Skin" else 1024)
    decimate(parts["Boots"], BOOTS_TRIS)
    tuck(parts["Trousers"], parts["Boots"])
    lengthen(parts["Shirt"], below=1.15, by=0.12)
    garments(arm, parts)
    head_top(arm, parts)
    body = P.body_of(arm)
    tattoos(parts["Skin"], arm, body)
    print("BODY foot_x", round(body.foot_x, 3), "wrist", round(body.wrist_x, 3), round(body.wrist_z, 3))
    print("STATS", C.stats(), C.tris_per_object())
    preview(arm, body, TAG if MODE == "wip" else "final")
    if MODE == "final":
        H.bake_clips(arm, clips(body))
        bpy.context.scene.render.fps = H.FPS
        C.save_blend(ROOT / "assets" / "npcs" / "nell" / "source" / "nell.blend")
        C.export_glb(ROOT / "assets" / "npcs" / "nell" / "nell.glb")


main()
