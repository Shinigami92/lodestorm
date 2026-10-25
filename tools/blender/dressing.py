"""A person made of two (see docs/TECHNICAL.md, People): a MakeHuman body (people.py) wearing a generated outfit
(TRELLIS.2 on an A-pose concept: what they wear and their hair), fitted over it. A person's build script describes
the body, the export looks and a Fit (the outfit's file and how it's fitted), then calls make():

    import dressing as D
    FIT = D.Fit(SOURCE / "trellis" / "nell_trellis.glb", skirt=(0.03, 0.07))
    PERSON = D.Person("Nell", BODY, LOOKS, FIT, ROOT / "assets" / "npcs" / "nell")
    D.make(PERSON, props, clips, work, MODE, TAG)  # props(arm), clips(body), work(body): the person's own

The outfit is cut open where the body's face is (the generated face and the skin around it, from the chin up; or
the generated head stays and the body's goes), its leftover skin moved to the body's tone, its hair fitted over the
skull, the body posed into its pose (arms and legs), its arms shortened to the body's, its hands and gloves' cuffs
cut at the body's wrists (the body's hands have finger bones), its weights taken from the body under it (loose cloth
below the waist from the hips into both thighs), both back in the rest pose, the body's skin it covers deleted and
gloves painted on the body's hands.
"""

import dataclasses
import pathlib

import bpy
import numpy as np
from mathutils import Vector

import common as C
import generated as G
import humanoid as H
import people as P

ROOT = pathlib.Path(__file__).resolve().parents[2]

FINGERLESS = ("Hand", "ThumbMetacarpal")  # a glove's bones: the palm, the back of the hand and the thumb's root
FULL = (*FINGERLESS, *(f"{f}{j}" for f, js in H.FINGERS.items() for j in js))  # and every finger


@dataclasses.dataclass
class Fit:
    """How a generated outfit is fitted over the body (lengths in m, colors sRGB)."""

    outfit: pathlib.Path  # the TRELLIS.2 model (source/trellis/<name>_trellis.glb)
    tris: int = 40000  # the outfit decimated to this many triangles
    band: tuple = (1.0, 1.3)  # heights of the torso the outfit is centered on front to back
    hair_above_skull: float = 0.02  # the outfit's hair top above the body's head top
    hair_margin: float = 0.008  # the hair cap's gap over the skull
    skin_match: float = 0.12  # how close to the generated face's skin a texel must be to count as skin
    skirt: tuple | None = None  # loose cloth below the waist: from how far to how far off the body it blends into
    skirt_width: float = 0.22  # the skirt's weights: half its width (the thighs' share across it)
    arms_from: float = 0.24  # the arms' faces: this far from the middle and farther (in the outfit's A-pose)
    chin: float = 0.07  # the generated skin is cut from this far above the neck's joint up
    arm_root: float = 0.1  # the outfit's arms are shortened from this far past the shoulder's joint
    arm_reach: float = 0.2  # an arm's points lie this close to its line
    hand_reach: float = 0.16  # a hand's points lie this close to its arm's line
    cuff: float = 0.08  # the generated gloves' cuffs reach this far up the forearm: cut, the body's forearm shows
    glove_dark: float = 0.13  # a face this dark near the wrist is the generated glove
    glove: tuple = (0.07, 0.065, 0.065)  # the gloves painted on the body's hands
    gloved: tuple = FINGERLESS  # which bones of each hand the gloves cover
    glove_up: float = 0.0  # the gloves reach this far up the forearm from the wrist (the skin kept that far in)
    stray: int = 300  # pieces of the outfit with fewer faces left at the hands are the generated hand's: dropped
    center_cuffs: float = 0.0  # this far up the forearm the outfit moves so its cut sleeve is around the wrist
    bare_arms: bool = True  # generated skin left on the arms and the neck: moved to the body's tone
    own_head: bool = False  # the generated head stays (face, hair, beard; on the Head bone), the body's goes
    head_blend: tuple = (0.02, 0.06)  # own head: from how far to how far above the neck's joint it's the Head's


@dataclasses.dataclass
class Person:
    name: str  # the asset's name (its root object), e.g. "Nell"
    body: dict  # people.build()'s person: the sliders and the assets
    looks: dict  # each body part's export material: tint (sRGB), roughness, whether its alpha cuts
    fit: Fit
    out: pathlib.Path  # assets/npcs/<name>/: the .glb there, its .blend in source/
    wrist_out: float = 0.05  # the hanging wrists this far outside the shoulders (m; wider over a bulky outfit)

    @property
    def renders(self) -> pathlib.Path:
        return ROOT / "tmp" / self.out.relative_to(ROOT)


KEEP = (
    "Head",
    "Neck",
    "LeftHand",
    "RightHand",
    *(f"{s}{f}{j}" for s in ("Left", "Right") for f, js in H.FINGERS.items() for j in js),
)  # the body's skin that stays (the rest is under the outfit)


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


def skin_like(outfit: bpy.types.Object, tone, fit: Fit) -> tuple:
    """Per texel how much it looks like the generated skin (1: within skin_match of its tone, fading out), and per
    face (at its UV center)."""
    rgba = G.image_pixels(G.base_color_image(outfit.data.materials[0]))
    d = np.abs(rgba[..., :3] - tone).max(2)
    texels = np.clip(1 - (d - fit.skin_match) / fit.skin_match, 0, 1)
    return texels, G.face_values(outfit.data, texels)


def cut_skin(outfit: bpy.types.Object, m: dict, fit: Fit) -> tuple:
    """Cuts the generated face and the skin around it off (forehead, ears, throat: what looks like the face's skin
    from the collar up), keeping the hair (with its own head: nothing). Returns the skin's tone and the texels that
    look like it."""
    centers = P.face_centers(outfit)
    skull = m["skull"]
    middle_y = float((skull[:, 1].min() + skull[:, 1].max()) / 2)
    face = (centers[:, 2] > m["neck"] + 0.03) & (centers[:, 2] < m["eye"] + 0.045) & (centers[:, 1] < middle_y)
    face &= np.abs(centers[:, 0]) < 0.085
    tone = skin_tone(outfit, [p for p in outfit.data.polygons if face[p.index]])
    texels, per_face = skin_like(outfit, tone, fit)
    if not fit.own_head:
        head = centers[:, 2] > m["neck"] + fit.chin
        print("FACE cut", P.delete_faces(outfit, face | (head & (per_face > 0.5))), "faces")
    return tone, texels


def match_skin(outfit: bpy.types.Object, skin: bpy.types.Object, tone, texels, neck_z: float, fit: Fit) -> None:
    """Shifts the generated skin left (the forearms) to the body's skin tone: the texels that look like skin, under
    the arms' and the neck's faces whose centers do (not an apron's stains)."""
    target = G.image_pixels(G.base_color_image(skin.data.materials[0]))[..., :3]
    target = target[target.mean(2) > 0.25].mean(0)  # skin, not the texture's empty background
    img = G.base_color_image(outfit.data.materials[0])
    rgba = G.image_pixels(img)
    looks = G.face_values(outfit.data, texels)
    centers = P.face_centers(outfit)
    arms = np.abs(centers[:, 0]) > fit.arms_from
    neck = (centers[:, 2] > neck_z - 0.12) & (np.abs(centers[:, 0]) < 0.12)
    faces = [p for p in outfit.data.polygons if looks[p.index] > 0.3 and (arms[p.index] or neck[p.index])]
    k = (texels * G.uv_cover(outfit.data, faces, img.size[0], grow=2))[..., None]
    rgba[..., :3] = np.clip(rgba[..., :3] + (target - tone) * k, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    print("SKIN tone", tone.round(3), "->", target.round(3), "on", len(faces), "faces")


def fit_hair(outfit: bpy.types.Object, m: dict, fit: Fit) -> None:
    """Fits the hair over the skull: the outfit's head (above the eyes, fading out down to the collar) scaled and
    moved per axis so it covers the skull with a small gap."""
    co = G.vertices(outfit.data)
    skull = m["skull"][m["skull"][:, 2] > m["eye"]]
    cap = co[co[:, 2] > m["eye"]]
    lo_s, hi_s = skull.min(0) - fit.hair_margin, skull.max(0) + fit.hair_margin
    hi_s[2] = m["top"] + fit.hair_above_skull
    lo_c, hi_c = cap.min(0), cap.max(0)
    lo_c[2] = lo_s[2] = m["eye"]
    scale = (hi_s - lo_s) / (hi_c - lo_c)
    fitted = (co - lo_c) * scale + lo_s
    f = np.clip((co[:, 2] - m["neck"] - 0.03) / (m["eye"] - m["neck"] - 0.03), 0, 1)[:, None]
    f = f * f * (3 - 2 * f)
    G.set_vertices(outfit.data, co * (1 - f) + fitted * f)
    print("HAIR scale", scale.round(3))


def dress(arm: bpy.types.Object, parts: dict, m: dict, person: Person) -> None:
    """The outfit over the body: posed into it, its weights taken, both back in the rest pose, the covered skin
    deleted."""
    fit = person.fit
    skin = parts["Skin"]
    names = m["names"]
    root = C.collection(person.name).objects[person.name]
    outfit = P.load_outfit(fit.outfit, root, skin, m["top"] + fit.hair_above_skull, fit.band)
    decimate(outfit, fit.tris)
    tone, texels = cut_skin(outfit, m, fit)
    if fit.bare_arms:
        match_skin(outfit, skin, tone, texels, m["neck"], fit)
    if not fit.own_head:
        fit_hair(outfit, m, fit)
    directions, _palms = P.limb_directions(outfit, arm, m["waist"])
    P.pose_limbs(arm, directions)
    fit_arms(outfit, arm, directions, fit)
    body = P.posed_vertices(skin)
    body_w = P.weight_matrix(skin, names)
    hands = beyond_wrists(arm, directions, fit)
    rgba = G.image_pixels(G.base_color_image(outfit.data.materials[0]))
    dark = G.face_values(outfit.data, rgba[..., :3].mean(2)) < fit.glove_dark
    reach = hands(P.face_centers(outfit))
    cut = (reach > -0.005) | ((reach > -fit.cuff) & dark)  # the hands and the gloves' cuffs
    print("HANDS cut", P.delete_faces(outfit, cut), "faces")
    drop_strays(outfit, arm, fit)
    if fit.center_cuffs:
        center_cuffs(outfit, arm, directions, hands, fit)
    in_cuffs = hands(body) > -max(fit.cuff, fit.glove_up)
    co = G.vertices(outfit.data)
    w, near = P.transfer_weights(co, body, body_w)
    if fit.skirt:
        loose = (co[:, 2] < m["waist"]) & (co[:, 2] > m["hem"] - 0.1) & (np.abs(co[:, 0]) < fit.arms_from)
        k = np.where(loose, np.clip((near - fit.skirt[0]) / (fit.skirt[1] - fit.skirt[0]), 0, 1), 0)[:, None]
        skirt = P.skirt_weights(co, names, m["waist"], m["hem"], fit.skirt_width)
        w = w * (1 - k) + skirt * k
        print("OUTFIT loose", int((k > 0.5).sum()), "of", len(co), "vertices")
    if fit.own_head:  # the head turns as one, blending into the neck below
        k = G.smoothstep(m["neck"] + fit.head_blend[0], m["neck"] + fit.head_blend[1], co[:, 2])[:, None]
        k *= (np.abs(co[:, 0]) < fit.arms_from)[:, None]
        w = w * (1 - k) + np.eye(len(names))[names.index("Head")] * k
    P.unskin(outfit, arm, names, w)
    for i, name in enumerate(names):
        g = outfit.vertex_groups.new(name=name)
        for vi in np.nonzero(w[:, i] > 1e-4)[0]:
            g.add([int(vi)], float(w[vi, i]), "REPLACE")
    outfit.parent = arm
    outfit.modifiers.new("Armature", "ARMATURE").object = arm
    H.rest_pose(arm)
    gloves(skin, names, fit, hands(body) > -fit.glove_up if fit.glove_up else None)
    keep = [names.index(b) for b in KEEP if not (fit.own_head and b in ("Head", "Neck"))]
    owner = body_w.argmax(1)
    shown = np.isin(owner, keep) | in_cuffs  # the head and neck, the hands from inside the cuffs
    centers = P.face_centers(skin)
    under = (centers[:, 2] < m["neck"] + fit.chin - 0.03) & (centers[:, 2] > m["neck"] - 0.3)  # in the generated neck
    covered = np.array([not shown[list(p.vertices)].all() for p in skin.data.polygons]) | under
    print("SKIN covered", P.delete_faces(skin, covered), "faces")
    if fit.own_head:  # its eyes, brows and lashes are the generated head's
        for name in ("Eyes", "Brows", "Lashes"):
            if name in parts:
                bpy.data.objects.remove(parts.pop(name))
    parts["Outfit"] = outfit


def fit_arms(outfit: bpy.types.Object, arm: bpy.types.Object, directions: dict, fit: Fit) -> None:
    """Shortens the outfit's arms to the body's (posed into them): from a little past the shoulder out, its points
    move in along the arm, so its fingertips meet the body's (the generator makes arms too long)."""
    co = G.vertices(outfit.data)
    for side, s in H.SIDES:
        d = np.array(directions[f"{side}LowerArm"])
        shoulder = np.array(arm.pose.bones[f"{side}UpperArm"].head)
        rel = co - shoulder
        along = rel @ d
        near = (s * co[:, 0] > abs(shoulder[0])) & (np.linalg.norm(rel - along[:, None] * d, axis=1) < fit.arm_reach)
        tip = float(along[near].max())
        body = float((np.array(arm.pose.bones[f"{side}MiddleDistal"].tail) - shoulder) @ d)
        k = (body - fit.arm_root) / (tip - fit.arm_root)
        moved = near & (along > fit.arm_root)
        co[moved] -= ((along[moved] - fit.arm_root) * (1 - k))[:, None] * d
        print("ARM", side, "fingertips", round(tip, 3), "->", round(body, 3), "m from the shoulder")
    G.set_vertices(outfit.data, co)


def beyond_wrists(arm: bpy.types.Object, directions: dict, fit: Fit):
    """How far points near the arms (within hand_reach of their lines, up to a hand beyond the wrist) lie beyond the
    posed wrists along them (m; negative: on the arm's side; -1 elsewhere): the hands are the body's, the generated
    ones are cut there."""
    planes = []
    for side, s in H.SIDES:
        wrist = np.array(arm.pose.bones[f"{side}Hand"].head)
        planes.append((s, wrist, np.array(directions[f"{side}LowerArm"])))

    def beyond(points: np.ndarray) -> np.ndarray:
        out = np.full(len(points), -1.0)
        for s, wrist, d in planes:
            rel = points - wrist
            along = rel @ d
            off_axis = np.linalg.norm(rel - along[:, None] * d, axis=1)
            mine = (s * points[:, 0] > 0.15) & (off_axis < fit.hand_reach) & (along < 0.25)
            out[mine] = np.maximum(out[mine], along[mine])
        return out

    return beyond


def center_cuffs(outfit: bpy.types.Object, arm: bpy.types.Object, directions: dict, hands, fit: Fit) -> None:
    """Moves the outfit's sleeve ends across the arm so their cut edges are around the wrists: the body's hand comes
    out of the middle of the cuff (a bulky sleeve or a heavy gauntlet pulls the outfit's arm line off its opening).
    Fades in over fit.center_cuffs up the forearm."""
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(outfit.data)
    edge = np.zeros(len(bm.verts), bool)
    for e in bm.edges:
        if e.is_boundary:
            edge[e.verts[0].index] = edge[e.verts[1].index] = True
    bm.free()
    co = G.vertices(outfit.data)
    reach = hands(co)
    for side, s in H.SIDES:
        wrist = np.array(arm.pose.bones[f"{side}Hand"].head)
        d = np.array(directions[f"{side}LowerArm"])
        mine = (s * co[:, 0] > 0.15) & (reach > -fit.center_cuffs)
        rim = mine & edge & (reach > -0.04)
        if not rim.any():
            continue
        off = wrist - co[rim].mean(0)
        off -= (off @ d) * d  # across the arm only
        k = G.smoothstep(-fit.center_cuffs, -0.02, reach)
        co[mine] += k[mine, None] * off
        print("CUFF", side, "moved", round(float(np.linalg.norm(off)), 3), "m onto the wrist")
    G.set_vertices(outfit.data, co)


def drop_strays(outfit: bpy.types.Object, arm: bpy.types.Object, fit: Fit) -> None:
    """Drops what's left of the generated hands: small pieces (fewer than fit.stray faces) whose middle lies within
    30 cm of a posed wrist (splayed fingers beyond the cut)."""
    me = outfit.data
    parent = np.arange(len(me.vertices))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for p in me.polygons:
        root = find(p.vertices[0])
        for v in p.vertices[1:]:
            other = find(v)
            if other != root:
                parent[other] = root
    piece = np.array([find(p.vertices[0]) for p in me.polygons])
    ids, counts = np.unique(piece, return_counts=True)
    centers = P.face_centers(outfit)
    wrists = [np.array(arm.pose.bones[f"{side}Hand"].head) for side, _s in H.SIDES]
    stray = np.zeros(len(piece), bool)
    for i in ids[counts < fit.stray]:
        mine = piece == i
        middle = centers[mine].mean(0)
        if min(np.linalg.norm(middle - wrist) for wrist in wrists) < 0.3:
            stray |= mine
    print("HANDS strays", P.delete_faces(outfit, stray), "faces")


def gloves(skin: bpy.types.Object, names: list, fit: Fit, up: np.ndarray | None) -> None:
    """Gloves painted on the body's hands: dark worn leather over the faces of the gloved bones (and where `up` is
    set for all of a face's vertices: up the forearm)."""
    w = P.weight_matrix(skin, names)
    gloved = [names.index(f"{side}{b}") for side, _s in H.SIDES for b in fit.gloved]
    owner = w.argmax(1)
    faces = [
        p
        for p in skin.data.polygons
        if np.isin(owner[list(p.vertices)], gloved).all() or (up is not None and up[list(p.vertices)].all())
    ]
    img = G.base_color_image(skin.data.materials[0])
    size = img.size[0]
    cover = G.uv_cover(skin.data, faces, size, grow=1)
    grain = P.noise(size, 64, 21, 3)[..., None]
    leather = np.array(fit.glove)[None, None, :] * (0.8 + 0.4 * grain)
    rgba = G.image_pixels(img)
    rgba[cover, :3] = leather[cover]
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    print("GLOVES on", len(faces), "faces")


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


def preview(arm: bpy.types.Object, body: H.Body, out: pathlib.Path, tag: str, work: list) -> None:
    """Check renders to out/wip/<tag>_*.png and a contact sheet: front, side and back in the rest pose, idle,
    walking and the `work` poses ((name, pose) each); a hand at rest and idle; the face, a forearm and the waist."""
    C.preview_scene(crystals=False, figure_location=(30, 30, 0))
    shots = []
    for name, pose in (("rest", None), ("idle", H.idle(body, 0.25)), ("walk0", H.walk(body, 0.0)), *work):
        if pose:
            H.apply(arm, pose)
        else:
            H.rest_pose(arm)
        bpy.context.view_layer.update()
        for view, loc in (("front", (0, -3.4, 1.0)), ("side", (3.4, -0.4, 1.0)), ("back", (-1.2, 3.2, 1.2))):
            path = out / "wip" / f"{tag}_{name}_{view}.png"
            C.render_from(path, loc, (0, 0, 0.85), 40, 32, 512)
            shots.append(path)
    for side, s in H.SIDES:
        for name, pose in ((f"hand_{side.lower()}_rest", None), (f"hand_{side.lower()}_idle", H.idle(body, 0.25))):
            if pose:
                H.apply(arm, pose)
            else:
                H.rest_pose(arm)
            bpy.context.view_layer.update()
            at = arm.pose.bones[f"{side}Hand"].head
            path = out / "wip" / f"{tag}_{name}.png"
            C.render_from(path, at + Vector((0.1 * s, -0.7, 0.15)), at, 50, 32, 512)
            shots.append(path)
    H.apply(arm, H.idle(body, 0.25))
    bpy.context.view_layer.update()
    for name, loc, target in (
        ("face", (0.25, -0.9, 1.6), (0, 0, 1.55)),
        ("forearm", (0.75, -0.75, 1.2), (0.25, -0.05, 0.95)),
        ("waist", (-0.3, 1.3, 1.1), (0, 0, 1.0)),
    ):
        path = out / "wip" / f"{tag}_{name}.png"
        C.render_from(path, loc, target, 50, 48, 512)
        shots.append(path)
    H.rest_pose(arm)
    C.contact_sheet(shots, out / "wip" / f"{tag}_sheet.png", cols=3, tile=384)


def make(person: Person, extras, clips, work, mode: str, tag: str) -> None:
    """Builds the person: the body, its export materials, the outfit over it, the head's top, then `extras(arm)`
    (prop grips), renders the checks (`work(body)`: the work poses to render) and in `final` mode bakes the clips
    (`clips(body)`: {name: (frames, pose at t)}) and writes <out>/<name>.glb and source/<name>.blend."""
    C.reset(person.name)
    P.enable()
    root = C.asset_root(person.name)
    arm, parts = P.build(person.body, root)
    for name, (tint, roughness, clip) in person.looks.items():
        P.export_material(parts[name], tint, roughness, clip, 2048 if name == "Skin" else 1024)
    m = measure(arm, parts)
    dress(arm, parts, m, person)
    head_top(arm, parts)
    extras(arm)
    body = P.body_of(arm, wrist_out=person.wrist_out)
    print("STATS", C.stats(), C.tris_per_object())
    preview(arm, body, person.renders, tag if mode == "wip" else "final", work(body))
    if mode == "final":
        H.bake_clips(arm, clips(body), body.props)
        bpy.context.scene.render.fps = H.FPS
        file = person.name.lower()
        C.save_blend(person.out / "source" / f"{file}.blend")
        C.export_glb(person.out / f"{file}.glb")
