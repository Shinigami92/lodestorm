"""Shared helpers for the aliens' build scripts (e.g. assets/aliens/swarmer/source/swarmer_build.py): every strain
is one species, so they share the skeleton tools, the organic mesh builder, the hive's materials and the clip baking.

    import common as C
    import creature as K
    RIG = K.Rig([(name, head, tail, parent), ...])   # the skeleton, built with RIG.build(root)
    sk = K.Skin("Creature", K.materials(), RIG)      # organic parts weighted to the rig's bones
    sk.auto(K.tube_path(sk, pts, radii, 12, 6, K.SINEW), ["Hips", "Spine"])
    K.bake_clips(arm, RIG, {"Idle": (60, idle), ...})

Conventions (see docs/technical/assets.md): Blender Z-up meters, the creature faces -Y, its left is +X,
feet on the ground at the origin. Bones: Root, Body (moves the whole trunk), Hips, Spine, Chest, Neck, Head, Jaw and
legs named <Front|Mid|Hind><Left|Right><UpperLeg|LowerLeg|Foot>, which the game steps by IK (AlienLegs). Meshes:
"Creature" (the skinned body, baked into one texture set), "Eyes" and optionally "Glands" (constant emissive in the
hive's yellow-green; the game flares them during a wind-up).
"""

import itertools
import math

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import common as C

I3 = Matrix.Identity(3)
SIDES = (("Left", 1.0), ("Right", -1.0))
UP = Vector((0, 0, 1))
SINEW, CHITIN, BONE, MOUTH = range(4)
EYE_COLOR = (0.75, 1.0, 0.035)  # linear for the aliens' Color(0.9, 1, 0.2)


def mirror(v: Vector, s: float) -> Vector:
    return Vector((v.x * s, v.y, v.z))


# --- skeleton -------------------------------------------------------------------------------------


class Rig:
    """The bones as (name, head, tail, parent), parents before their children."""

    def __init__(self, bones: list):
        self.bones = bones
        self.head = {n: Vector(h) for n, h, _t, _p in bones}
        self.tail = {n: Vector(t) for n, _h, t, _p in bones}
        self.parent = {n: p for n, _h, _t, p in bones}
        self.index = {n: i for i, (n, *_r) in enumerate(bones)}

    def build(self, root: bpy.types.Object) -> bpy.types.Object:
        data = bpy.data.armatures.new("Skeleton")
        arm = bpy.data.objects.new("Skeleton", data)
        C.link(arm, root)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        for name, head, tail, parent in self.bones:
            eb = data.edit_bones.new(name)
            eb.head, eb.tail = head, tail
            eb.roll = 0.0
            if parent:
                eb.parent = data.edit_bones[parent]
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        data.display_type = "STICK"
        return arm


# --- mesh -------------------------------------------------------------------------------------------


def seg_dist(p: Vector, a: Vector, b: Vector) -> float:
    d = b - a
    t = min(max((p - a).dot(d) / max(d.length_squared, 1e-9), 0.0), 1.0)
    return (p - (a + d * t)).length


def catmull(table: list, t: float) -> list:
    """Smooth interpolation through the rows of `table` (lists of floats) at t in 0..1 (Catmull-Rom)."""
    n = len(table) - 1
    x = min(max(t, 0.0), 1.0) * n
    i = min(int(x), n - 1)
    u = x - i
    p0, p1, p2, p3 = table[max(i - 1, 0)], table[i], table[i + 1], table[min(i + 2, n)]
    return [
        0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (-a + 3 * b - 3 * c + d) * u * u * u)
        for a, b, c, d in zip(p0, p1, p2, p3)
    ]


def path_point(pts: list, t: float) -> Vector:
    return Vector(catmull([list(p) for p in pts], t))


class Skin(C.Part):
    """Organic part builder with vertex weights: rigid(verts, bone) or auto(verts, bones) (the two nearest of
    `bones` by distance to their segments, blended smoothly)."""

    def __init__(self, name: str, mats: list, rig: Rig):
        super().__init__(name, mats, None)
        self.rig = rig
        self.dl = self.bm.verts.layers.deform.verify()

    def rigid(self, verts, bone: str):
        for v in verts:
            v[self.dl].clear()
            v[self.dl][self.rig.index[bone]] = 1.0
        return verts

    def auto(self, verts, bones: list, power: float = 4.0):
        rig = self.rig
        for v in verts:
            ds = sorted((max(seg_dist(v.co, rig.head[b], rig.tail[b]), 1e-4), b) for b in bones)[:2]
            w = [1.0 / d**power for d, _b in ds]
            total = sum(w)
            v[self.dl].clear()
            for (_d, b), wi in zip(ds, w):
                v[self.dl][rig.index[b]] = wi / total
        return verts

    def loft(self, rings: list, mi: int = 0, caps: bool = True):
        """Closed tube through rings of points (same count each); caps close the ends."""
        loops = [[self.bm.verts.new(p) for p in ring] for ring in rings]
        n = len(loops[0])
        faces = []
        for a, b in itertools.pairwise(loops):
            for k in range(n):
                faces.append(self.bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k])))
        if caps:
            faces.append(self.bm.faces.new(list(reversed(loops[0]))))
            faces.append(self.bm.faces.new(loops[-1]))
        for f in faces:
            f.normal_update()
        return self._tag([v for lp in loops for v in lp], mi)

    def cone(self, base: Vector, tip: Vector, r: float, seg: int = 5, mi: int = 0, flat: float = 1.0):
        """Pointed cone (teeth, claws, spikes); flat squashes it sideways."""
        d = tip - base
        m = C.basis(d, Vector((1, 0, 0)) if abs(d.normalized().x) < 0.9 else Vector((0, 1, 0)))
        ring = [
            self.bm.verts.new(base + m @ Vector((math.cos(a) * r, math.sin(a) * r * flat, 0)))
            for a in (math.tau * k / seg for k in range(seg))
        ]
        top = self.bm.verts.new(tip)
        faces = [self.bm.faces.new((ring[k], ring[(k + 1) % seg], top)) for k in range(seg)]
        faces.append(self.bm.faces.new(list(reversed(ring))))
        for f in faces:
            f.normal_update()
        return self._tag(ring + [top], mi)

    def finish(self, parent) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        obj = super().finish(parent)
        for name, *_r in self.rig.bones:
            obj.vertex_groups.new(name=name)
        return obj


def frame_at(d: Vector, up: Vector = UP) -> tuple:
    """Side and up axes of a cross-section perpendicular to d."""
    d = d.normalized()
    side = d.cross(up)
    if side.length < 1e-4:
        side = d.cross(Vector((0, 1, 0)))
    side.normalize()
    return side, side.cross(d).normalized() * (1 if side.cross(d).z >= 0 else -1)


def section(
    c: Vector,
    d: Vector,
    w: float,
    top: float,
    bot: float,
    seg: int,
    wobble: float = 0.0,
    seed: float = 0.0,
    up=UP,
) -> list:
    """Cross-section around c (perpendicular to d): half-width w, top above, bot below; slightly squared."""
    side, upv = frame_at(d, up)
    pts = []
    for k in range(seg):
        a = math.tau * k / seg
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** 0.85, ca) * w
        y = math.copysign(abs(sa) ** 0.9, sa) * (top if sa > 0 else bot)
        p = c + side * x + upv * y
        if wobble:
            p += (p - c).normalized() * wobble * noise.noise(p * 9.0 + Vector((seed, seed, seed)))
        pts.append(p)
    return pts


def tube_path(
    sk: Skin,
    pts: list,
    radii: list,
    seg: int,
    rings: int,
    mi: int,
    flat: float = 1.0,
    wobble: float = 0.0,
    up=UP,
):
    """Tube along a smooth path through pts with radii interpolated along it; flat squashes it vertically."""
    out = []
    for i in range(rings + 1):
        t = i / rings
        c = path_point(pts, t)
        d = path_point(pts, min(t + 0.02, 1.0)) - path_point(pts, max(t - 0.02, 0.0))
        r = catmull([[x] for x in radii], t)[0]
        out.append(section(c, d, r, r * flat, r * flat, seg, wobble, i * 1.7, up))
    return sk.loft(out, mi)


class Profile:
    """A body's profile along its length (rows of y, center z, half-width, top, bottom, the first row at t = 0)."""

    def __init__(self, rows: list):
        self.rows = rows
        self._table = [list(r) for r in rows]

    def at(self, t: float) -> tuple:
        """Center, half-width, top and bottom at t in 0..1."""
        y, z, w, top, bot = catmull(self._table, t)
        return Vector((0, y, z)), w, top, bot

    def surface(self, y: float, a: float, out: float = 0.0) -> Vector:
        """Point on the surface at y and angle a (0 = left side, 90 = top), pushed out by `out`."""
        t = (self.rows[0][0] - y) / (self.rows[0][0] - self.rows[-1][0])
        c, w, top, bot = self.at(t)
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        x = math.copysign(abs(ca) ** 0.85, ca) * (w + out)
        z = math.copysign(abs(sa) ** 0.9, sa) * ((top if sa > 0 else bot) + out)
        return c + Vector((x, 0, z))


def shell(
    sk: Skin,
    profile: Profile,
    y0: float,
    y1: float,
    a0: float,
    a1: float,
    out: float,
    thick: float,
    mi: int,
    nu: int = 6,
    nv: int = 3,
    lift: float = 0.0,
):
    """Curved plate hugging `profile` between y0..y1 and angles a0..a1; its rear edge lifts off like a scale."""
    top_rows, bot_rows = [], []
    for i in range(nv + 1):
        v = i / nv
        y = y0 + (y1 - y0) * v
        bulge = math.sin(math.pi * v) * 0.6 + 0.4
        row_t, row_b = [], []
        for k in range(nu + 1):
            u = k / nu
            a = a0 + (a1 - a0) * u
            edge = math.sin(math.pi * u) ** 0.5
            o = out + lift * v * edge
            row_t.append(sk.bm.verts.new(profile.surface(y, a, o + thick * bulge * edge)))
            row_b.append(sk.bm.verts.new(profile.surface(y, a, o)))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return close_grid(sk, top_rows, bot_rows, mi)


def close_grid(sk: Skin, top_rows: list, bot_rows: list, mi: int):
    """A closed slab between two grids of verts (rows of the same length): top, bottom and the rim between them."""
    faces = []
    nv, nu = len(top_rows) - 1, len(top_rows[0]) - 1
    for i in range(nv):
        for k in range(nu):
            faces.append(
                sk.bm.faces.new((top_rows[i][k], top_rows[i][k + 1], top_rows[i + 1][k + 1], top_rows[i + 1][k]))
            )
            faces.append(
                sk.bm.faces.new((bot_rows[i][k], bot_rows[i + 1][k], bot_rows[i + 1][k + 1], bot_rows[i][k + 1]))
            )
    rim_t = (
        [r[0] for r in top_rows]
        + top_rows[-1][1:]
        + list(reversed([r[-1] for r in top_rows]))[1:]
        + list(reversed(top_rows[0]))[1:-1]
    )
    rim_b = (
        [r[0] for r in bot_rows]
        + bot_rows[-1][1:]
        + list(reversed([r[-1] for r in bot_rows]))[1:]
        + list(reversed(bot_rows[0]))[1:-1]
    )
    for k in range(len(rim_t)):
        k2 = (k + 1) % len(rim_t)
        faces.append(sk.bm.faces.new((rim_t[k], rim_b[k], rim_b[k2], rim_t[k2])))
    for f in faces:
        f.normal_update()
    verts = [v for r in top_rows + bot_rows for v in r]
    return sk._tag(verts, mi)


def limb_plate(sk: Skin, a: Vector, b: Vector, r: float, a0: float, a1: float, thick: float, mi: int, facing: Vector):
    """Curved plate wrapped around a limb segment a..b (radius r) on the side `facing` (angles a0..a1 around it)."""
    d = (b - a).normalized()
    side = facing - d * facing.dot(d)
    side.normalize()
    other = d.cross(side)
    top_rows, bot_rows = [], []
    for i in range(4):
        v = i / 3
        c = a.lerp(b, v)
        row_t, row_b = [], []
        for k in range(5):
            ang = math.radians(a0 + (a1 - a0) * k / 4)
            n = side * math.cos(ang) + other * math.sin(ang)
            bulge = thick * (0.5 + 0.5 * math.sin(math.pi * k / 4))
            row_t.append(sk.bm.verts.new(c + n * (r + bulge)))
            row_b.append(sk.bm.verts.new(c + n * r))
        top_rows.append(row_t)
        bot_rows.append(row_b)
    return close_grid(sk, top_rows, bot_rows, mi)


# --- materials ---------------------------------------------------------------------------------------
# The hive's look, shared by every strain: Sinew, Chitin, Bone, Mouth (material indices SINEW, CHITIN, BONE, MOUTH).


def _coord(nt, out: str = "Object") -> bpy.types.NodeSocket:
    return nt.nodes.new("ShaderNodeTexCoord").outputs[out]


def _noise(nt, vec, scale: float, detail: float = 4.0, rough: float = 0.55, dist: float = 0.0) -> bpy.types.Node:
    return C._noise(nt, scale, detail, rough, vector=vec, distortion=dist)


def _cavity(nt, distance: float = 0.08, lo: float = 0.35, hi: float = 0.95) -> bpy.types.NodeSocket:
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = distance
    ao.samples = 16
    return C._math(nt, "SUBTRACT", 1.0, C._bw(nt, C._ramp(nt, lo, hi, ao.outputs["AO"])))


def _edges(nt, radius: float = 0.01, lo: float = 0.02, hi: float = 0.12) -> bpy.types.NodeSocket:
    return C._bw(nt, C._ramp(nt, lo, hi, C._bevel_edge(nt, radius)))


def mat_sinew() -> bpy.types.Material:
    """Sinewy hide between the plates: dark wine-red flesh with fine muscle striation, wet in the folds (the nest's
    flesh, tuned for a small creature)."""
    mat, nt, bsdf = C._new_material("Sinew")
    co = _coord(nt)
    big = _noise(nt, co, 4.0, 4.0, 0.5)
    col = C._mix_color(nt, big.outputs["Fac"], (0.075, 0.016, 0.014), (0.035, 0.01, 0.012))
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 28.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 2.0
    nt.links.new(co, wave.inputs["Vector"])
    stri = C._ramp(nt, 0.35, 0.75, wave.outputs["Fac"])
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", C._bw(nt, stri), 0.4), col, (0.018, 0.005, 0.007))
    veins = C._bw(nt, C._voronoi_lines(nt, co, 9.0, 0.035))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", veins, 0.6), col, (0.13, 0.03, 0.02))
    edge = _edges(nt, 0.01, 0.03, 0.2)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", edge, 0.3), col, (0.16, 0.06, 0.05))
    cav = _cavity(nt, 0.06)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.9), col, (0.01, 0.003, 0.004))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, big.outputs["Fac"], 0.25, 0.45)
    rough = C._mix_float(nt, cav, rough, 0.08)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    fine = _noise(nt, co, 60.0, 3.0, 0.6)
    h = C._math(nt, "ADD", C._math(nt, "MULTIPLY", C._bw(nt, stri), 0.5), C._math(nt, "MULTIPLY", veins, 0.5))
    h = C._math(nt, "ADD", h, C._math(nt, "MULTIPLY", fine.outputs["Fac"], 0.2))
    C._bump(nt, bsdf, h, 0.35, 0.004)
    return mat


def mat_chitin() -> bpy.types.Material:
    """Chitin plates: near-black shell with deep crimson in the growth bands, glossy, worn lighter at the edges."""
    mat, nt, bsdf = C._new_material("Chitin")
    co = _coord(nt)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Y"
    wave.inputs["Scale"].default_value = 18.0
    wave.inputs["Distortion"].default_value = 4.0
    wave.inputs["Detail"].default_value = 3.0
    nt.links.new(co, wave.inputs["Vector"])
    bands = C._bw(nt, C._ramp(nt, 0.3, 0.8, wave.outputs["Fac"]))
    big = _noise(nt, co, 5.0, 4.0, 0.5)
    shell = C._mix_color(nt, big.outputs["Fac"], (0.018, 0.009, 0.01), (0.06, 0.012, 0.016))
    shell = C._mix_color(nt, C._math(nt, "MULTIPLY", bands, 0.55), shell, (0.12, 0.018, 0.022))
    edge = _edges(nt, 0.006, 0.03, 0.16)
    breakup = _noise(nt, co, 25.0, 6.0, 0.6)
    worn = C._math(nt, "MULTIPLY", edge, C._bw(nt, C._ramp(nt, 0.35, 0.6, breakup.outputs["Fac"])))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", worn, 0.6), shell, (0.2, 0.09, 0.07))
    cav = _cavity(nt, 0.05)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.85), col, (0.006, 0.003, 0.003))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, big.outputs["Fac"], 0.16, 0.3)
    rough = C._mix_float(nt, worn, rough, 0.5)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Coat Weight"].default_value = 0.3
    fine = _noise(nt, co, 90.0, 3.0, 0.6)
    h = C._math(nt, "ADD", C._math(nt, "MULTIPLY", bands, 0.4), C._math(nt, "MULTIPLY", fine.outputs["Fac"], 0.2))
    C._bump(nt, bsdf, h, 0.3, 0.003)
    return mat


def mat_bone() -> bpy.types.Material:
    """Blades, teeth, claws and horns: yellowed bone, dark at the base, sharp edges pale."""
    mat, nt, bsdf = C._new_material("Bone")
    co = _coord(nt)
    streak = _noise(nt, co, 12.0, 6.0, 0.6, dist=1.5)
    col = C._mix_color(nt, streak.outputs["Fac"], (0.32, 0.25, 0.16), (0.5, 0.42, 0.3))
    cav = _cavity(nt, 0.04)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.85), col, (0.05, 0.03, 0.02))
    grime = _noise(nt, co, 4.0, 3.0, 0.5)
    col = C._mix_color(
        nt,
        C._math(nt, "MULTIPLY", C._bw(nt, C._ramp(nt, 0.5, 0.7, grime.outputs["Fac"])), 0.6),
        col,
        (0.08, 0.04, 0.03),
    )
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, streak.outputs["Fac"], 0.3, 0.5), bsdf.inputs["Roughness"])
    C._bump(nt, bsdf, streak.outputs["Fac"], 0.25, 0.003)
    return mat


def mat_mouth() -> bpy.types.Material:
    """Gums and the inside of the mouth: raw, glossy red."""
    mat, nt, bsdf = C._new_material("Mouth")
    co = _coord(nt)
    big = _noise(nt, co, 30.0, 3.0, 0.5)
    nt.links.new(
        C._mix_color(nt, big.outputs["Fac"], (0.16, 0.012, 0.012), (0.3, 0.04, 0.035)), bsdf.inputs["Base Color"]
    )
    bsdf.inputs["Roughness"].default_value = 0.15
    C._bump(nt, bsdf, big.outputs["Fac"], 0.3, 0.003)
    return mat


def materials() -> list:
    """The hive's materials in the order of SINEW, CHITIN, BONE, MOUTH."""
    return [mat_sinew(), mat_chitin(), mat_bone(), mat_mouth()]


# --- posing -----------------------------------------------------------------------------------------


class Pose:
    """Rotations per bone relative to its parent, in world axes at rest (a bone without one follows its parent),
    plus the Body's offset."""

    def __init__(self, rig: Rig, offset=(0, 0, 0)):
        self.rig = rig
        self.offset = Vector(offset)
        self.rel: dict = {}

    def set(self, bone: str, rot: Matrix) -> "Pose":
        self.rel[bone] = rot
        return self

    def world(self, bone: str) -> Matrix:
        parent = self.rig.parent[bone]
        base = self.world(parent) if parent else I3
        return base @ self.rel.get(bone, I3)


def apply(arm: bpy.types.Object, pose: Pose) -> None:
    """Set the armature's pose bones from a Pose (local rotation q = R^-1 W_parent^-1 W R)."""
    for name, _h, _t, parent in pose.rig.bones:
        pb = arm.pose.bones[name]
        rest = arm.data.bones[name].matrix_local.to_3x3()
        w = pose.world(name)
        wp = pose.world(parent) if parent else I3
        q = (rest.transposed() @ wp.transposed() @ w @ rest).to_quaternion()
        if pb.rotation_quaternion.dot(q) < 0:
            q.negate()
        pb.rotation_quaternion = q
        pb.location = rest.transposed() @ pose.offset if name == "Body" else Vector()


def rest_pose(arm: bpy.types.Object) -> None:
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


def smooth(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def bake_clips(arm: bpy.types.Object, clips: dict) -> None:
    """Keys each clip (name: (frames, pose(t) for t in 0..1)) into its own action and muted NLA track."""
    ad = arm.animation_data_create()
    for name, (frames, fn) in clips.items():
        ad.action = None
        for f in range(frames + 1):
            apply(arm, fn(f / frames))
            for pb in arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                if pb.name == "Body":
                    pb.keyframe_insert("location", frame=f, group=pb.name)
        act = ad.action
        act.name = name
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        track.mute = True
        ad.action = None
    rest_pose(arm)
