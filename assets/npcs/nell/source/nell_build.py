"""Nell, the bartender at Waypost Ostra: a sturdy woman in her forties with a brown braid, a slate work jacket with
rolled sleeves, tattooed forearms, fingerless gloves, a stained canvas apron with leather straps, a belt with a
holster, cargo trousers with knee pads and lace-up boots (reference: the batch-8 concept "nell_v2", see
GAME_DESIGN.md, Art direction).

Run from the repo root (see docs/TECHNICAL.md, People):
    tools/blender.sh assets/npcs/nell/source/nell_build.py wip r1   # quick renders
    tools/blender.sh assets/npcs/nell/source/nell_build.py final    # renders, nell.blend and the game asset

Made of two (tools/blender/people.py): her body is MakeHuman's (MPFB's sliders, a CC0 skin, eyes, brows and lashes:
her face, her skeleton and its weights); what she wears and her hair are generated (source/trellis/: the A-pose
concept, the TRELLIS.2 model and trellis.json with how). The outfit is cut open where her face is, its hair fitted
over her head, its skin tone matched to the body's; it takes the weights of the body under it, the apron's skirt
from the hips into both thighs. Skeleton "Skeleton" (Godot's humanoid bone names, MPFB's A-pose rest), clips "Idle"
and "Walk" from the shared pose code. Meshes: "Skin" (her head, neck and hands are what's left of it), "Eyes",
"Brows", "Lashes", "Outfit"; empty "HeadTop" on the head (where the name plate and the bubbles go).

Writes assets/npcs/nell/nell.glb and its source assets/npcs/nell/source/nell.blend; renders go to tmp/assets/npcs/nell/.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "npcs" / "nell"
SOURCE = ROOT / "assets" / "npcs" / "nell" / "source"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
import numpy as np
from mathutils import Vector

import common as C
import generated as G
import humanoid as H
import people as P

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
    ],
}
# Each part's export material: tint (sRGB), roughness, whether its alpha cuts (cards).
LOOKS = {
    "Skin": ((1.0, 1.0, 1.0), 0.55, False),
    "Eyes": ((1.0, 1.0, 1.0), 0.2, False),
    "Brows": ((0.8, 0.65, 0.5), 0.8, True),
    "Lashes": ((1.0, 1.0, 1.0), 0.8, True),
}
OUTFIT = SOURCE / "trellis" / "nell_trellis.glb"
OUTFIT_TRIS = 24000
HAIR_ABOVE_SKULL = 0.02  # the outfit's hair top above the body's head top (m)
HAIR_MARGIN = 0.008  # the hair cap's gap over the skull (m)
SKIN_MATCH = 0.12  # how close (in sRGB) to the generated face's skin a texel must be to count as skin
SKIRT_LOOSE = (0.03, 0.07)  # loose cloth below the waist: how far from the body it blends into the skirt's weights
ARMS_FROM = 0.24  # the arms' faces: this far (m) from the middle and farther (in the outfit's A-pose)
CHIN = 0.07  # the generated skin is cut from this far above the neck's joint up; the neck below keeps its own
KEEP = ("Head", "Neck")  # the body's skin that stays (the rest is under the outfit)


def measure(arm: bpy.types.Object, parts: dict) -> dict:
    """Heights and the head's shape on the body (rest pose)."""
    head = {b.name: b.head_local for b in arm.data.bones}
    skin = parts["Skin"]
    names = [b.name for b in arm.data.bones]
    co = G.vertices(skin.data)
    w = P.weight_matrix(skin, names)
    skull = co[w[:, names.index("Head")] > 0.5]
    eyes = G.vertices(parts["Eyes"].data)
    m = {
        "waist": (head["Spine"].z + head["Chest"].z) / 2,
        "hem": head["LeftLowerLeg"].z,
        "neck": head["Neck"].z,
        "eye": float(eyes[:, 2].mean()),
        "top": float(co[:, 2].max()),
        "skull": skull,
        "names": names,
    }
    print("MEASURE", {k: round(v, 3) for k, v in m.items() if isinstance(v, float)})
    return m


def skin_tone(outfit: bpy.types.Object, faces: list) -> tuple:
    """The generated skin's color (mean, sRGB) where the given faces are in its texture (its face: no eyes, no
    glare)."""
    img = G.base_color_image(outfit.data.materials[0])
    rgba = G.image_pixels(img)
    px = rgba[G.uv_cover(outfit.data, faces, img.size[0], grow=0), :3]
    bright = px.mean(1)
    return px[(bright > np.percentile(bright, 30)) & (bright < np.percentile(bright, 90))].mean(0)


def skin_like(outfit: bpy.types.Object, tone) -> tuple:
    """Per texel how much it looks like the generated skin (1: within SKIN_MATCH of its tone, fading out), and per
    face (at its UV center)."""
    rgba = G.image_pixels(G.base_color_image(outfit.data.materials[0]))
    d = np.abs(rgba[..., :3] - tone).max(2)
    texels = np.clip(1 - (d - SKIN_MATCH) / SKIN_MATCH, 0, 1)
    return texels, G.face_values(outfit.data, texels)


def cut_skin(outfit: bpy.types.Object, m: dict) -> tuple:
    """Cuts the generated face and the skin around it off (forehead, ears, throat: what looks like the face's skin
    from the collar up), keeping the hair. Returns the skin's tone and the texels that look like it."""
    centers = P.face_centers(outfit)
    skull = m["skull"]
    middle_y = float((skull[:, 1].min() + skull[:, 1].max()) / 2)
    face = (centers[:, 2] > m["neck"] + 0.03) & (centers[:, 2] < m["eye"] + 0.045) & (centers[:, 1] < middle_y)
    face &= np.abs(centers[:, 0]) < 0.085
    tone = skin_tone(outfit, [p for p in outfit.data.polygons if face[p.index]])
    texels, per_face = skin_like(outfit, tone)
    head = centers[:, 2] > m["neck"] + CHIN
    cut = face | (head & (per_face > 0.5))
    print("FACE cut", P.delete_faces(outfit, cut), "faces")
    return tone, texels


def match_skin(outfit: bpy.types.Object, skin: bpy.types.Object, tone, texels: np.ndarray, neck_z: float) -> None:
    """Shifts the generated skin left (the forearms) to the body's skin tone: the texels that look like skin, under
    the arms' and the neck's faces whose centers do (not the apron's stains)."""
    target = G.image_pixels(G.base_color_image(skin.data.materials[0]))[..., :3]
    target = target[target.mean(2) > 0.25].mean(0)  # skin, not the texture's empty background
    img = G.base_color_image(outfit.data.materials[0])
    rgba = G.image_pixels(img)
    looks = G.face_values(outfit.data, texels)
    centers = P.face_centers(outfit)
    arms = np.abs(centers[:, 0]) > ARMS_FROM
    neck = (centers[:, 2] > neck_z - 0.12) & (np.abs(centers[:, 0]) < 0.12)
    faces = [p for p in outfit.data.polygons if looks[p.index] > 0.3 and (arms[p.index] or neck[p.index])]
    k = (texels * G.uv_cover(outfit.data, faces, img.size[0], grow=2))[..., None]
    rgba[..., :3] = np.clip(rgba[..., :3] + (target - tone) * k, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    print("SKIN tone", tone.round(3), "->", target.round(3), "on", len(faces), "faces")


def fit_hair(outfit: bpy.types.Object, m: dict) -> None:
    """Fits the hair over the skull: the outfit's head (above the eyes, fading out down to the collar) scaled and
    moved per axis so it covers the skull with a small gap."""
    co = G.vertices(outfit.data)
    skull = m["skull"][m["skull"][:, 2] > m["eye"]]
    cap = co[co[:, 2] > m["eye"]]
    lo_s, hi_s = skull.min(0) - HAIR_MARGIN, skull.max(0) + HAIR_MARGIN
    hi_s[2] = m["top"] + HAIR_ABOVE_SKULL
    lo_c, hi_c = cap.min(0), cap.max(0)
    lo_c[2] = lo_s[2] = m["eye"]
    scale = (hi_s - lo_s) / (hi_c - lo_c)
    fitted = (co - lo_c) * scale + lo_s
    f = np.clip((co[:, 2] - m["neck"] - 0.03) / (m["eye"] - m["neck"] - 0.03), 0, 1)[:, None]
    f = f * f * (3 - 2 * f)
    G.set_vertices(outfit.data, co * (1 - f) + fitted * f)
    print("HAIR scale", scale.round(3))


def dress(arm: bpy.types.Object, parts: dict, m: dict) -> None:
    """The outfit over the body: posed into it, its weights taken, both back in the rest pose, the covered skin
    deleted."""
    skin = parts["Skin"]
    names = m["names"]
    outfit = P.load_outfit(OUTFIT, C.collection(ASSET).objects[ASSET], skin, m["top"] + HAIR_ABOVE_SKULL, (1.0, 1.3))
    decimate(outfit, OUTFIT_TRIS)
    tone, texels = cut_skin(outfit, m)
    match_skin(outfit, skin, tone, texels, m["neck"])
    fit_hair(outfit, m)
    P.pose_limbs(arm, P.limb_directions(outfit, arm, m["waist"]))
    body = P.posed_vertices(skin)
    body_w = P.weight_matrix(skin, names)
    co = G.vertices(outfit.data)
    w, near = P.transfer_weights(co, body, body_w)
    loose = (co[:, 2] < m["waist"]) & (co[:, 2] > m["hem"] - 0.1) & (np.abs(co[:, 0]) < ARMS_FROM)
    k = np.where(loose, np.clip((near - SKIRT_LOOSE[0]) / (SKIRT_LOOSE[1] - SKIRT_LOOSE[0]), 0, 1), 0)[:, None]
    skirt = P.skirt_weights(co, names, m["waist"], m["hem"], 0.22)
    w = w * (1 - k) + skirt * k
    print("OUTFIT loose", int((k > 0.5).sum()), "of", len(co), "vertices")
    P.unskin(outfit, arm, names, w)
    for i, name in enumerate(names):
        g = outfit.vertex_groups.new(name=name)
        for vi in np.nonzero(w[:, i] > 1e-4)[0]:
            g.add([int(vi)], float(w[vi, i]), "REPLACE")
    outfit.parent = arm
    outfit.modifiers.new("Armature", "ARMATURE").object = arm
    H.rest_pose(arm)
    keep = [names.index(b) for b in KEEP]
    owner = body_w.argmax(1)
    under = P.face_centers(skin)[:, 2] < m["neck"] + CHIN - 0.03  # the body's neck inside the generated one
    covered = np.array([not np.isin(owner[list(p.vertices)], keep).all() for p in skin.data.polygons]) | under
    print("SKIN covered", P.delete_faces(skin, covered), "faces")
    parts["Outfit"] = outfit


def decimate(obj: bpy.types.Object, tris: int) -> None:
    obj.data.calc_loop_triangles()
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = tris / len(obj.data.loop_triangles)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="Decimate")


def head_top(arm: bpy.types.Object, parts: dict) -> None:
    """An empty on the head at the top of the hair (the name plate and the bubbles sit above it)."""
    top = float(G.vertices(parts["Outfit"].data)[:, 2].max())
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
    for name, pose in (("hand_rest", None), ("hand_idle", H.idle(body, 0.25))):
        if pose:
            H.apply(arm, pose)
        else:
            H.rest_pose(arm)
        bpy.context.view_layer.update()
        at = arm.pose.bones["LeftHand"].head
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render_from(path, at + Vector((0.1, -0.7, 0.15)), at, 50, 32, 512)
        shots.append(path)
    H.apply(arm, H.idle(body, 0.25))
    bpy.context.view_layer.update()
    for name, loc, target in (
        ("face", (0.25, -0.9, 1.6), (0, 0, 1.55)),
        ("forearm", (0.75, -0.75, 1.2), (0.25, -0.05, 0.95)),
        ("waist", (-0.3, 1.3, 1.1), (0, 0, 1.0)),
    ):
        path = OUT / "wip" / f"{tag}_{name}.png"
        C.render_from(path, loc, target, 50, 48, 512)
        shots.append(path)
    H.rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=3, tile=384)


def main() -> None:
    C.reset(ASSET)
    P.enable()
    root = C.asset_root(ASSET)
    arm, parts = P.build(PERSON, root)
    for name, (tint, roughness, clip) in LOOKS.items():
        P.export_material(parts[name], tint, roughness, clip, 2048 if name == "Skin" else 1024)
    m = measure(arm, parts)
    dress(arm, parts, m)
    head_top(arm, parts)
    body = P.body_of(arm)
    print("STATS", C.stats(), C.tris_per_object())
    preview(arm, body, TAG if MODE == "wip" else "final")
    if MODE == "final":
        H.bake_clips(arm, clips(body))
        bpy.context.scene.render.fps = H.FPS
        C.save_blend(SOURCE / "nell.blend")
        C.export_glb(ROOT / "assets" / "npcs" / "nell" / "nell.glb")


main()
