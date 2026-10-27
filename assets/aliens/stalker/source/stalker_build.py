"""Stalker: the hive's ambusher (tier 5 hunter), see-through until it strikes. A tall, hunched biped, lean and sinewy:
the torso leans forward over the hips on two strong digitigrade legs (thigh, shin, a long raised metatarsus and
splayed clawed toes), a short tail stub behind. Two huge scything talons rise over its shoulders, folded up and back
like raised scythes (its silhouette from the game's camera), and two smaller grasping claws fold under them at chest
height. A narrow, elongated armored head under a bony crest sweeping back over the neck, small deep-set glowing eyes
and a cluster of short feeding tendrils around the mouth. Its chitin is darker than the other strains' and mottled
with small overlapping scales: plates over the back, the shoulders and the limbs, sinew showing between. The glow is
sparse: the eyes, thin seams along the talons' inner edges and a few slits on the back. Rigged and animated.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/stalker/source/stalker_build.py wip v2r1   # quick renders of the poses
    tools/blender.sh assets/aliens/stalker/source/stalker_build.py stats      # measures and pose bounds, no renders
    tools/blender.sh assets/aliens/stalker/source/stalker_build.py final      # renders + stalker_procedural.blend

Everything it writes goes to tmp/assets/stalker/; stalker_bake.py turns stalker_procedural.blend into the game asset.

Layout (Blender Z-up meters; the stalker faces -Y, its left is +X). Toes on the ground, the origin on the ground
under the hips; standing at rest the head is at about 1.95 m, the crest and the talons' tips at about 2.4-2.5 m.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rump) with the tail stub
(Tail1) and the legs, Spine, Chest with the talons and the claws, Neck, Head (skull, crest, the mouth tendrils
MouthTendril<1..6>A/B: odd numbers on the left) and Jaw. Talons (Arm<Side>Upper, rising from the shoulder to the
elbow; Arm<Side>Lower, the forearm folded back up to the wrist; Arm<Side>Blade, the scythe sweeping back over the
back from the wrist, its tail at the blade's tip) and grasping claws (Claw<Side>Upper, Claw<Side>Lower,
Claw<Side>Hand, its tail at the fingertips) under Chest: only the clips move them. Legs (Hind<Side>UpperLeg = thigh,
LowerLeg = shin, Foot = the raised metatarsus with the toes, its head the ankle about 0.44 m above the ground): the
game moves them by IK (two bones reaching the ankle, the Foot keeps its angle; the knees bend forward), so the clips
leave them at rest and keep the feet level; only "Die" moves them.
Meshes: "Creature" (one skinned object: trunk, neck, legs and arm roots weighted to the nearest bones; plates, the
head, blades, claws and toes rigid or nearly), "Eyes" (constant emissive, deep under the brows) and "Glands"
(constant emissive: seams along the talons' inner edges, slits along the back).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop, 3 s: hunched and breathing, the
head turning, the talons twitching, the mouth tendrils writhing), "Run" (loop: a low, fast lope, the trunk leaning
further forward and bobbing, the talons held back; the legs come from the game), "Attack" (once, 0.5 s: the talons
cock up and back, then both scythe down and forward with a lunge, the hit at frame HIT_FRAME, then they fold back)
and "Die" (once, 1.5 s: the knees buckle, then it falls forward onto its left side, the talons sprawl, the legs fold).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "stalker"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Matrix, Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "v2r0"

ASSET = "Stalker"
FPS = 30
GLAND_GLOW = 1.5  # sparse and faint: the eyes (8) stay the main glow
SINEW_SHADE = 0.7  # darker than the other strains (docs/design/aliens.md, Alien look: stalkers have darker chitin)
I3 = Matrix.Identity(3)
X = Vector((1, 0, 0))

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, -0.16, 1.36))
PELVIS = Vector((0, 0.14, 1.1))
SHOULDER = Vector((0, -0.4, 1.62))
WITHERS = Vector((0, -0.57, 1.78))
SKULL = Vector((0, -0.72, 1.94))
SNOUT = Vector((0, -1.14, 1.82))
JAW_PIVOT = Vector((0, -0.8, 1.87))
JAW_TIP = Vector((0, -1.05, 1.8))
TAIL_TIP = Vector((0, 0.46, 0.9))
# Leg joints (left): hip, knee, ankle, ball of the foot. Digitigrade: the thigh reaches forward and down to the knee,
# the shin back and down to the ankle, the raised metatarsus forward and down to the ball of the foot, the toes on
# the ground in front of it.
HIND = [
    Vector((0.15, 0.06, 1.08)),
    Vector((0.22, -0.22, 0.7)),
    Vector((0.27, 0.2, 0.44)),
    Vector((0.29, -0.05, 0.075)),
]
# Talon joints (left): shoulder, elbow (the upper arm rises forward), wrist (the forearm folds back up); the blade
# sweeps back over the back from the wrist and curls up at its tip, its sharp (concave) edge up.
TALON = [
    Vector((0.21, -0.5, 1.76)),
    Vector((0.3, -0.62, 1.98)),
    Vector((0.32, -0.46, 2.1)),
]
BLADE = [
    TALON[2],
    Vector((0.36, -0.27, 2.06)),
    Vector((0.43, -0.04, 2.08)),
    Vector((0.51, 0.19, 2.16)),
    Vector((0.58, 0.38, 2.3)),
    Vector((0.62, 0.5, 2.45)),
]
# Grasping claw joints (left): shoulder, elbow, wrist, fingertips; folded in front of the chest.
CLAW = [
    Vector((0.15, -0.6, 1.5)),
    Vector((0.21, -0.63, 1.27)),
    Vector((0.15, -0.84, 1.33)),
    Vector((0.11, -0.96, 1.25)),
]
# Mouth tendrils (left; the right ones mirrored): root, middle, tip. They hang around the mouth under the snout.
TENDRILS = [
    (Vector((0.035, -1.08, 1.8)), Vector((0.05, -1.13, 1.73)), Vector((0.025, -1.14, 1.66))),
    (Vector((0.06, -0.99, 1.8)), Vector((0.085, -1.04, 1.72)), Vector((0.06, -1.07, 1.65))),
    (Vector((0.06, -0.9, 1.81)), Vector((0.085, -0.94, 1.74)), Vector((0.065, -0.98, 1.68))),
]
# Eyes (left): center and radius; deep under the brow.
EYES = [(Vector((0.064, -0.9, 1.94)), 0.021), (Vector((0.052, -0.98, 1.915)), 0.016)]


def tendril_name(k: int, s: float) -> str:
    return f"MouthTendril{2 * k + (1 if s > 0 else 2)}"


BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, 0.04)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, SHOULDER, "Body"),
    ("Chest", SHOULDER, WITHERS, "Spine"),
    ("Neck", WITHERS, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, JAW_TIP, "Head"),
    ("Tail1", PELVIS, TAIL_TIP, "Hips"),
]
for _side, _s in K.SIDES:
    _t = [K.mirror(p, _s) for p in TALON] + [K.mirror(BLADE[-1], _s)]
    BONES += [
        (f"Arm{_side}Upper", _t[0], _t[1], "Chest"),
        (f"Arm{_side}Lower", _t[1], _t[2], f"Arm{_side}Upper"),
        (f"Arm{_side}Blade", _t[2], _t[3], f"Arm{_side}Lower"),
    ]
    _c = [K.mirror(p, _s) for p in CLAW]
    BONES += [
        (f"Claw{_side}Upper", _c[0], _c[1], "Chest"),
        (f"Claw{_side}Lower", _c[1], _c[2], f"Claw{_side}Upper"),
        (f"Claw{_side}Hand", _c[2], _c[3], f"Claw{_side}Lower"),
    ]
    _h = [K.mirror(p, _s) for p in HIND]
    BONES += [
        (f"Hind{_side}UpperLeg", _h[0], _h[1], "Hips"),
        (f"Hind{_side}LowerLeg", _h[1], _h[2], f"Hind{_side}UpperLeg"),
        (f"Hind{_side}Foot", _h[2], _h[3], f"Hind{_side}LowerLeg"),
    ]
for _k in range(len(TENDRILS)):
    for _side, _s in K.SIDES:
        _n = tendril_name(_k, _s)
        _r, _m, _e = (K.mirror(p, _s) for p in TENDRILS[_k])
        BONES += [(f"{_n}A", _r, _m, "Head"), (f"{_n}B", _m, _e, f"{_n}A")]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest"]
LEG_POLE = {}  # rest side each knee bends to (as AlienLegs measures it)
for _side, _s in K.SIDES:
    _hip, _knee, _ankle = (K.mirror(HIND[i], _s) for i in range(3))
    _axis = (_ankle - _hip).normalized()
    _off = _knee - _hip
    LEG_POLE[_side] = (_off - _axis * _off.dot(_axis)).normalized()

# --- shapes -----------------------------------------------------------------------------------------

# Trunk from the base of the neck down to the rump: center y, z, half-width, top (the back: up and back), bottom (the
# chest and belly: forward and down). Broad hunched shoulders, a deep rib cage, a narrow waist, the pelvis.
TRUNK = [
    (-0.62, 1.8, 0.12, 0.11, 0.11),
    (-0.52, 1.72, 0.22, 0.18, 0.19),
    (-0.39, 1.59, 0.21, 0.17, 0.25),
    (-0.24, 1.44, 0.155, 0.13, 0.18),
    (-0.08, 1.29, 0.13, 0.1, 0.12),
    (0.06, 1.17, 0.17, 0.13, 0.14),
    (0.18, 1.09, 0.14, 0.11, 0.1),
    (0.25, 1.05, 0.07, 0.05, 0.05),
]
# Skull with the upper jaw, from the back of the head to the snout: y, center z, half-width, top, bottom.
SKULL_PROFILE = [
    (-0.64, 1.95, 0.07, 0.07, 0.06),
    (-0.72, 1.965, 0.088, 0.085, 0.068),
    (-0.82, 1.945, 0.084, 0.075, 0.064),
    (-0.92, 1.91, 0.07, 0.06, 0.055),
    (-1.02, 1.87, 0.054, 0.045, 0.045),
    (-1.1, 1.838, 0.04, 0.033, 0.034),
    (-1.145, 1.822, 0.022, 0.018, 0.02),
]
# Lower jaw from the hinge to the chin.
JAW_PROFILE = [
    (-0.79, 1.86, 0.062, 0.02, 0.04),
    (-0.88, 1.84, 0.06, 0.02, 0.036),
    (-0.97, 1.82, 0.05, 0.018, 0.03),
    (-1.04, 1.805, 0.034, 0.015, 0.022),
    (-1.08, 1.8, 0.02, 0.01, 0.014),
]
# The crest: a bony fin from the brow sweeping up and back over the neck (center line, height, half-width).
CREST = [
    (Vector((0, -1.0, 1.905)), 0.025, 0.018),
    (Vector((0, -0.89, 1.99)), 0.05, 0.026),
    (Vector((0, -0.77, 2.09)), 0.075, 0.034),
    (Vector((0, -0.65, 2.21)), 0.075, 0.034),
    (Vector((0, -0.54, 2.32)), 0.055, 0.028),
    (Vector((0, -0.45, 2.39)), 0.02, 0.014),
]
# The blade along its length (t = 0 at the wrist): full width (spine to the inner edge) and the spine's thickness.
BLADE_WIDTH = [0.09, 0.15, 0.17, 0.165, 0.14, 0.1, 0.055, 0.016]
BLADE_THICK = [0.05, 0.05, 0.046, 0.04, 0.034, 0.027, 0.02, 0.008]
BLADE_CANT = 50  # degrees the inner edge turns in toward the body, so the flat shows from above


class Trunk:
    """A body's profile bent along its center line in the YZ plane (s = 0 at the neck, 1 at the rump): like
    K.Profile, but the cross-sections stand perpendicular to the center line; K.shell takes it (s for y)."""

    def __init__(self, rows: list):
        self.table = [list(r) for r in rows]

    def at(self, s: float) -> tuple:
        """Center, top direction (perpendicular to the center line, up and back), half-width, top, bottom."""
        y, z, w, top, bot = K.catmull(self.table, s)
        a = K.catmull(self.table, max(s - 0.01, 0.0))
        b = K.catmull(self.table, min(s + 0.01, 1.0))
        d = Vector((0, b[0] - a[0], b[1] - a[1])).normalized()
        return Vector((0, y, z)), Vector((0, -d.z, d.y)), w, top, bot

    def surface(self, s: float, a: float, out: float = 0.0) -> Vector:
        """Point at s and angle a (0 = left side, 90 = the back), pushed out by `out`."""
        c, up, w, top, bot = self.at(s)
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        x = math.copysign(abs(ca) ** 0.85, ca) * (w + out)
        h = math.copysign(abs(sa) ** 0.9, sa) * ((top if sa > 0 else bot) + out)
        return c + X * x + up * h


TRUNK_SHAPE = Trunk(TRUNK)
SKULL_SHAPE = K.Profile(SKULL_PROFILE)

# --- materials ----------------------------------------------------------------------------------------


def mat_chitin() -> bpy.types.Material:
    """The stalker's chameleon chitin (named "Chitin" like the kit's, which it replaces): near-black, mottled in
    blotches, covered in small overlapping scales (Voronoi cells, each its own shade: dark wine, near-black or a dark
    bronze sheen, a hint of iridescence that survives the bake), the hive's crimson in faint growth bands, the scale
    edges dark, glossy."""
    mat, nt, bsdf = C._new_material("Chitin")
    co = K._coord(nt)
    scales = nt.nodes.new("ShaderNodeTexVoronoi")
    scales.inputs["Scale"].default_value = 42.0
    scales.inputs["Randomness"].default_value = 0.8
    nt.links.new(co, scales.inputs["Vector"])
    cell = C._bw(nt, scales.outputs["Color"])
    dist = scales.outputs["Distance"]
    blotch = K._noise(nt, co, 3.2, 3.0, 0.5, dist=0.6)
    col = C._mix_color(
        nt, C._bw(nt, C._ramp(nt, 0.42, 0.62, blotch.outputs["Fac"])), (0.026, 0.009, 0.014), (0.006, 0.005, 0.006)
    )
    sheen = C._math(nt, "MULTIPLY", C._bw(nt, C._ramp(nt, 0.55, 0.85, cell)), 0.85)
    col = C._mix_color(nt, sheen, col, (0.034, 0.03, 0.012))
    wine = C._math(nt, "MULTIPLY", C._bw(nt, C._ramp(nt, 0.0, 0.22, cell)), 0.8)
    col = C._mix_color(nt, wine, col, (0.046, 0.009, 0.028))
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Y"
    wave.inputs["Scale"].default_value = 14.0
    wave.inputs["Distortion"].default_value = 5.0
    wave.inputs["Detail"].default_value = 3.0
    nt.links.new(co, wave.inputs["Vector"])
    bands = C._bw(nt, C._ramp(nt, 0.4, 0.85, wave.outputs["Fac"]))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", bands, 0.45), col, (0.07, 0.01, 0.016))
    rim = C._bw(nt, C._ramp(nt, 0.32, 0.5, dist))  # 1 at the scales' edges
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", rim, 0.85), col, (0.003, 0.002, 0.002))
    edge = K._edges(nt, 0.006, 0.03, 0.16)
    breakup = K._noise(nt, co, 25.0, 6.0, 0.6)
    worn = C._math(nt, "MULTIPLY", edge, C._bw(nt, C._ramp(nt, 0.35, 0.6, breakup.outputs["Fac"])))
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", worn, 0.5), col, (0.11, 0.06, 0.05))
    cav = K._cavity(nt, 0.05)
    col = C._mix_color(nt, C._math(nt, "MULTIPLY", cav, 0.85), col, (0.003, 0.002, 0.002))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, blotch.outputs["Fac"], 0.14, 0.3)
    rough = C._mix_float(nt, rim, rough, 0.45)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Coat Weight"].default_value = 0.35
    dome = C._math(nt, "SUBTRACT", 1.0, C._math(nt, "MULTIPLY", dist, 2.0, clamp=True))
    fine = K._noise(nt, co, 90.0, 3.0, 0.6)
    h = C._math(nt, "ADD", C._math(nt, "MULTIPLY", dome, 0.7), C._math(nt, "MULTIPLY", fine.outputs["Fac"], 0.15))
    h = C._math(nt, "ADD", h, C._math(nt, "MULTIPLY", bands, 0.2))
    C._bump(nt, bsdf, h, 0.4, 0.004)
    return mat


def darken(mat: bpy.types.Material, factor: float) -> bpy.types.Material:
    """Scales the material's constant colors."""
    for node in mat.node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.data_type == "RGBA":
            for sock in (node.inputs[6], node.inputs[7]):
                if not sock.is_linked:
                    r, g, b, a = sock.default_value
                    sock.default_value = (r * factor, g * factor, b * factor, a)
    return mat


def materials() -> list:
    """The hive's materials (SINEW, CHITIN, BONE, MOUTH), the chitin the stalker's own, the sinew darker."""
    chitin = mat_chitin()  # first, so the kit's "Chitin" isn't made
    return [darken(K.mat_sinew(), SINEW_SHADE), chitin, darken(K.mat_bone(), 0.75), K.mat_mouth()]


# --- parts ------------------------------------------------------------------------------------------


def slab(sk: K.Skin, top: list, bottom: list, mi: int) -> list:
    """A closed slab between two grids of points (rows of the same length)."""
    top_v = [[sk.bm.verts.new(p) for p in row] for row in top]
    bot_v = [[sk.bm.verts.new(p) for p in row] for row in bottom]
    return K.close_grid(sk, top_v, bot_v, mi)


def side_angle(a: float, s: float) -> float:
    """An angle around the trunk (0 = left side, 90 = the back) for side s."""
    return a if s > 0 else 180 - a


def build_trunk(sk: K.Skin, glands: K.Skin) -> None:
    n = 20
    rings = []
    for i in range(n + 1):
        s = i / n
        rings.append([TRUNK_SHAPE.surface(s, 360 * k / 16, 0.0) for k in range(16)])
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # Back plates from the neck down to the rump, overlapping like shingles, the lower edge of each lifting off; the
    # ones over the shoulders broad, the waist's narrow so the sinew shows at the flanks.
    stations = [0.02, 0.1, 0.18, 0.26, 0.34, 0.43, 0.52, 0.61, 0.7, 0.79, 0.88, 0.97]
    for s0, s1 in itertools.pairwise(stations):
        width = 40 if s0 < 0.3 else (30 if s0 < 0.6 else 36)
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, s0 - 0.01, s1 + 0.03, 90 - width, 90 + width, 0.006, 0.022, K.CHITIN, 4, 2, 0.02),
            TRUNK_BONES,
            8.0,
        )
    # Rib bands down the flanks of the rib cage, sinew between them.
    for side, s in K.SIDES:
        for s0 in (0.16, 0.24, 0.32, 0.4, 0.48):
            b0, b1 = sorted((side_angle(-48, s), side_angle(36, s)))
            sk.auto(
                K.shell(sk, TRUNK_SHAPE, s0, s0 + 0.045, b0, b1, 0.002, 0.016, K.CHITIN, 4, 1, 0.006),
                TRUNK_BONES,
                8.0,
            )
        # The back's glowing slits: dashes in the gap between the back plates and the ribs.
        for s0, s1 in ((0.22, 0.32), (0.42, 0.52), (0.63, 0.72)):
            pts = [TRUNK_SHAPE.surface(s0 + (s1 - s0) * k / 3, side_angle(47, s), 0.004) for k in range(4)]
            glands.auto(K.tube_path(glands, pts, [0.009, 0.013, 0.013, 0.009], 6, 6, 0, 0.8), TRUNK_BONES, 8.0)
    # Breast plates down the front of the rib cage, belly plates down the abdomen.
    for s0, s1 in itertools.pairwise([0.1, 0.2, 0.3, 0.4]):
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, s0, s1 + 0.03, 240, 300, 0.004, 0.018, K.CHITIN, 4, 2, 0.012), TRUNK_BONES, 8.0
        )
    for s0, s1 in itertools.pairwise([0.5, 0.6, 0.7, 0.8, 0.9]):
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, s0, s1 + 0.02, 235, 305, 0.003, 0.012, K.CHITIN, 4, 2, 0.008), TRUNK_BONES, 8.0
        )
    # Tail stub: short, blunt and banded.
    pts = [PELVIS + Vector((0, 0.02, 0.0)), PELVIS.lerp(TAIL_TIP, 0.5) + Vector((0, 0, 0.02)), TAIL_TIP]
    sk.auto(K.tube_path(sk, pts, [0.1, 0.07, 0.025], 12, 8, K.SINEW, 0.9), ["Hips", "Tail1"])
    for t, r in ((0.15, 0.1), (0.4, 0.083), (0.65, 0.062)):
        c = K.path_point(pts, t)
        d = K.path_point(pts, t + 0.03) - K.path_point(pts, t - 0.03)
        o = d.normalized()
        rings = [
            K.section(c + o * x, d, r + dr, (r + dr) * 0.9, (r + dr) * 0.9, 12) for x, dr in ((-0.03, 0), (0.04, 0.012))
        ]
        sk.auto(sk.loft(rings, K.CHITIN), ["Hips", "Tail1"], 8.0)


def build_neck(sk: K.Skin) -> None:
    pts = [WITHERS + Vector((0, 0.04, -0.03)), WITHERS.lerp(SKULL, 0.5) + Vector((0, 0.01, 0.005)), SKULL]
    sk.auto(K.tube_path(sk, pts, [0.1, 0.082, 0.07], 14, 6, K.SINEW, 0.95), ["Chest", "Neck", "Head"])
    # Overlapping plates along the top of the neck.
    for t0, t1 in ((0.0, 0.42), (0.3, 0.72), (0.6, 1.0)):
        a, b = K.path_point(pts, t0), K.path_point(pts, t1)
        r = 0.088 - 0.02 * t0
        sk.auto(K.limb_plate(sk, a, b, r, -75, 75, 0.02, K.CHITIN, Vector((0, 0.5, 1))), ["Chest", "Neck"], 8.0)


def build_head(sk: K.Skin, eyes: K.Skin) -> None:
    # Skull and upper jaw (the underside is the roof of the mouth).
    rings = []
    n = 12
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in SKULL_PROFILE], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 14, 0.003, 3 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    _mouth_faces(sk, verts, below=True)
    # Armor plates down the snout and a heavy brow over the eyes on each side.
    for y0, y1, a in ((-0.9, -1.02, 56), (-0.98, -1.1, 54)):
        sk.rigid(K.shell(sk, SKULL_SHAPE, y1, y0, 90 - a, 90 + a, 0.003, 0.014, K.CHITIN, 5, 2, -0.004), "Head")
    for _side, s in K.SIDES:
        a0, a1 = sorted((side_angle(18, s), side_angle(62, s)))
        sk.rigid(K.shell(sk, SKULL_SHAPE, -0.995, -0.84, a0, a1, 0.006, 0.026, K.CHITIN, 3, 3, 0.012), "Head")
    # The crest: a bony fin from the brow up and back over the neck, a few knobs along its ridge.
    rings = []
    for i in range(13):
        t = i / 12
        c = K.path_point([p for p, _h, _w in CREST], t)
        d = K.path_point([p for p, _h, _w in CREST], min(t + 0.04, 1)) - K.path_point(
            [p for p, _h, _w in CREST], max(t - 0.04, 0)
        )
        h, w = K.catmull([[h, w] for _p, h, w in CREST], t)
        rings.append(K.section(c, d, w, h * 0.6, h * 0.4 + 0.05 * (1 - t), 8))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    for t in (0.3, 0.5, 0.7, 0.9):
        c = K.path_point([p for p, _h, _w in CREST], t)
        h = K.catmull([[h] for _p, h, _w in CREST], t)[0]
        top = c + Vector((0, 0.01, h * 0.6))
        sk.rigid(sk.cone(top - Vector((0, 0.02, 0.01)), top + Vector((0, 0.05, 0.035)), 0.016, 5, K.BONE, 0.6), "Head")
    # Throat under the head, from the neck into the lower jaw.
    pts = [Vector((0, -0.62, 1.78)), Vector((0, -0.72, 1.84)), Vector((0, -0.82, 1.85))]
    sk.auto(K.tube_path(sk, pts, [0.075, 0.065, 0.05], 12, 4, K.SINEW), ["Neck", "Head", "Jaw"])
    # Lower jaw.
    rings = []
    for i in range(9):
        y, z, w, top, bot = K.catmull([list(r) for r in JAW_PROFILE], i / 8)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 12, 0.002, 9 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Jaw")
    _mouth_faces(sk, verts, below=False)
    for side, s in K.SIDES:
        # Swept-back horns from the back of the skull, beside the crest.
        base = Vector((s * 0.06, -0.7, 2.0))
        sk.rigid(sk.cone(base, base + Vector((s * 0.07, 0.2, 0.08)), 0.028, 6, K.BONE, 0.8), "Head")
        # Teeth along the upper jaw's edge, half hidden by the tendrils.
        for y in (-0.94, -1.0, -1.06):
            c, w, _top, bot = SKULL_SHAPE.at((SKULL_PROFILE[0][0] - y) / (SKULL_PROFILE[0][0] - SKULL_PROFILE[-1][0]))
            base = Vector((s * w * 0.75, y, c.z - bot * 0.7))
            sk.rigid(sk.cone(base, base + Vector((0, -0.006, -0.03)), 0.01, 4, K.BONE), "Head")
        # Eyes: small glowing beads sunk into sockets under the brow.
        for c, r in EYES:
            c = K.mirror(c, s)
            sk.rigid(sk.sphere(c + Vector((s * -0.004, 0, 0)), r + 0.01, 10, 5, mi=K.MOUTH), "Head")
            eyes.rigid(eyes.sphere(c + Vector((s * 0.006, 0, 0)), r, 10, 5), "Head")
        # Feeding tendrils around the mouth: fleshy, ringed, thickest at the root.
        for k, (r0, r1, r2) in enumerate(TENDRILS):
            name = tendril_name(k, s)
            pts = [K.mirror(r0, s) + Vector((0, 0, 0.01)), K.mirror(r1, s), K.mirror(r2, s)]
            sk.auto(K.tube_path(sk, pts, [0.026, 0.018, 0.015], 8, 8, K.SINEW), ["Head", f"{name}A", f"{name}B"], 6.0)
            c = K.path_point(pts, 0.12)
            d = K.path_point(pts, 0.15) - K.path_point(pts, 0.09)
            collar = [K.section(c + d.normalized() * x, d, r, r, r, 8) for x, r in ((-0.015, 0.03), (0.015, 0.026))]
            sk.auto(sk.loft(collar, K.CHITIN), ["Head", f"{name}A"], 8.0)


def _mouth_faces(sk: K.Skin, verts: list, below: bool) -> None:
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        n = f.normal
        if ((n.z < -0.5) if below else (n.z > 0.5)) and f.calc_center_median().y < -0.84:
            f.material_index = K.MOUTH


def build_legs(sk: K.Skin) -> None:
    for side, s in K.SIDES:
        hip, knee, ankle, ball = (K.mirror(p, s) for p in HIND)
        up, low, foot = (f"Hind{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
        # Thigh: a heavy muscle from the hip down to the knee, armored on the outside.
        pts = [hip + Vector((s * -0.03, 0.05, 0.08)), hip.lerp(knee, 0.45) + Vector((s * 0.03, 0.03, 0.0)), knee]
        sk.auto(K.tube_path(sk, pts, [0.165, 0.15, 0.092], 12, 8, K.SINEW, 1.0, 0.006), ["Hips", up, low])
        for a, b, face in ((0.1, 0.55, Vector((s, -0.3, 0.3))), (0.45, 0.88, Vector((s, -0.5, 0.0)))):
            sk.rigid(
                K.limb_plate(
                    sk, hip.lerp(knee, a), hip.lerp(knee, b), 0.135 - 0.04 * a, -70, 70, 0.022, K.CHITIN, face
                ),
                up,
            )
        sk.rigid(sk.sphere(knee + Vector((0, -0.03, 0.0)), 0.085, 10, 5, scale=(0.95, 1.0, 1.05), mi=K.CHITIN), low)
        # Shin: back and down to the ankle, a plate along its front.
        mid = knee.lerp(ankle, 0.5) + Vector((0, 0.0, -0.01))
        sk.auto(K.tube_path(sk, [knee, mid, ankle], [0.086, 0.07, 0.056], 10, 6, K.SINEW), [up, low, foot])
        front = Vector((s * 0.4, -0.53, -0.85))
        sk.rigid(
            K.limb_plate(sk, knee.lerp(ankle, 0.1), knee.lerp(ankle, 0.85), 0.072, -75, 75, 0.018, K.CHITIN, front), low
        )
        # Ankle with a backward spur, then the raised metatarsus down to the ball of the foot.
        sk.rigid(sk.sphere(ankle, 0.064, 10, 5, mi=K.CHITIN), foot)
        sk.rigid(
            sk.cone(ankle + Vector((0, 0.01, 0.0)), ankle + Vector((s * 0.01, 0.11, 0.02)), 0.026, 5, K.BONE), foot
        )
        mid = ankle.lerp(ball, 0.5)
        sk.auto(K.tube_path(sk, [ankle, mid, ball], [0.06, 0.05, 0.052], 10, 5, K.SINEW), [low, foot], 8.0)
        front = Vector((s * 0.3, -0.83, 0.56))
        sk.rigid(
            K.limb_plate(sk, ankle.lerp(ball, 0.08), ankle.lerp(ball, 0.9), 0.052, -80, 80, 0.016, K.CHITIN, front),
            foot,
        )
        # Ball of the foot and three thick toes splayed forward, each with a hooked claw; a short toe behind.
        sk.rigid(sk.sphere(ball + Vector((0, 0, -0.01)), 0.06, 10, 5, scale=(1.1, 1.15, 0.75), mi=K.SINEW), foot)
        fwd = Vector((s * 0.12, -1, 0)).normalized()
        for ang, reach in ((-32, 0.21), (0, 0.25), (32, 0.21), (160, 0.1)):
            a = math.radians(ang * s)
            toe = Vector((fwd.x * math.cos(a) - fwd.y * math.sin(a), fwd.x * math.sin(a) + fwd.y * math.cos(a), 0))
            toe.normalize()
            back = abs(ang) > 90
            base = ball + toe * 0.03 + Vector((0, 0, -0.01))
            knuckle = ball + toe * (reach * 0.6) + Vector((0, 0, -0.05 if not back else -0.035))
            r = 0.022 if back else 0.03
            sk.rigid(
                K.tube_path(
                    sk,
                    [base, base.lerp(knuckle, 0.5) + Vector((0, 0, 0.006)), knuckle],
                    [r, r * 0.92, r * 0.85],
                    7,
                    3,
                    K.SINEW,
                ),
                foot,
            )
            sk.rigid(sk.sphere(knuckle + Vector((0, 0, 0.004)), r * 0.95, 8, 4, mi=K.CHITIN), foot)
            tip = ball + toe * reach
            tip.z = 0.0
            sk.rigid(
                K.tube_path(
                    sk,
                    [knuckle + Vector((0, 0, 0.012)), knuckle.lerp(tip, 0.5) + Vector((0, 0, 0.022)), tip],
                    [r * 0.75, r * 0.5, 0.004],
                    6,
                    3,
                    K.BONE,
                    0.85,
                ),
                foot,
            )


def build_talons(sk: K.Skin, glands: K.Skin) -> None:
    """The scything talons: a pauldron over the shoulder, the upper arm rising to a spiked elbow, the forearm folding
    back up to the wrist and the blade sweeping back over the back, its sharp edge pale bone with a glowing seam."""
    for side, s in K.SIDES:
        sh, el, wr = (K.mirror(p, s) for p in TALON)
        up, low, blade = (f"Arm{side}{b}" for b in ("Upper", "Lower", "Blade"))
        out = Vector((s, 0, 0))
        # Shoulder: a muscle knot and layered pauldron plates over it.
        sk.auto(
            sk.sphere(sh + Vector((s * -0.02, 0.02, -0.02)), 0.1, 12, 6, scale=(1.0, 1.1, 0.9), mi=K.SINEW),
            ["Chest", up],
            2.0,
        )
        for k, (r, lift) in enumerate(((0.12, 0.0), (0.105, 0.05), (0.085, 0.095))):
            a = sh + Vector((s * -0.1, 0.05 + lift * 0.4, lift - 0.02))
            b = sh + Vector((s * 0.1, 0.05 + lift * 0.4, lift - 0.04))
            sk.auto(
                K.limb_plate(sk, a, b, r, -85, 85, 0.024 - 0.004 * k, K.CHITIN, Vector((0, 0.4, 1))),
                ["Chest", up],
                8.0,
            )
        # Upper arm: sinew core under a plate.
        sk.auto(
            K.tube_path(sk, [sh, sh.lerp(el, 0.45) + Vector((0, 0.025, 0)), el], [0.1, 0.082, 0.056], 10, 6, K.SINEW),
            ["Chest", up, low],
        )
        for a, b, r in ((0.15, 0.6, 0.088), (0.5, 0.97, 0.07)):
            sk.rigid(
                K.limb_plate(sk, sh.lerp(el, a), sh.lerp(el, b), r, -95, 95, 0.02, K.CHITIN, Vector((s, -0.6, 0.2))), up
            )
        # Elbow knob with a spike forward, the forearm (all chitin) back up to the wrist.
        sk.rigid(sk.sphere(el, 0.065, 10, 5, mi=K.CHITIN), low)
        sk.rigid(
            sk.cone(el + Vector((0, -0.02, 0.0)), el + Vector((s * 0.02, -0.14, -0.04)), 0.032, 6, K.BONE, 0.8), low
        )
        sk.rigid(
            K.tube_path(sk, [el, el.lerp(wr, 0.5) + out * 0.006, wr], [0.058, 0.05, 0.048], 10, 4, K.SINEW, 0.9), low
        )
        sk.rigid(
            K.limb_plate(sk, el.lerp(wr, 0.1), el.lerp(wr, 0.9), 0.05, -90, 90, 0.018, K.CHITIN, Vector((s, 0, 1))), low
        )
        sk.rigid(sk.sphere(wr, 0.058, 10, 5, mi=K.CHITIN), blade)
        # Blade: the path is its thick spine; the inner (sharp, concave) edge faces up and in, the back edge down
        # and out with a few spurs. Chitin body, a pale bone edge, the glowing seam along the boundary.
        pts = [K.mirror(p, s) for p in BLADE]
        n = 18
        body_t, body_b, edge_t, edge_b, seam, spurs = [], [], [], [], [], []
        for i in range(n + 1):
            t = i / n
            c = K.path_point(pts, t)
            d = (K.path_point(pts, min(t + 0.02, 1)) - K.path_point(pts, max(t - 0.02, 0))).normalized()
            inner = X.cross(d).normalized()  # in the arm's plane, towards the concave side
            if inner.z < 0:
                inner = -inner
            cant = math.radians(BLADE_CANT)
            wdir = (inner * math.cos(cant) - out * math.sin(cant)).normalized()
            tdir = d.cross(wdir).normalized()
            w = K.catmull([[x] for x in BLADE_WIDTH], t)[0]
            th = K.catmull([[x] for x in BLADE_THICK], t)[0]
            back = c - wdir * w * 0.25
            mid = c + wdir * w * 0.35
            inner_end = c + wdir * w * 0.6
            edge = c + wdir * w * 0.75
            body = [(back, 0.5), (c, 1.0), (mid, 0.7), (inner_end, 0.45)]
            body_t.append([p + tdir * th * f * 0.5 for p, f in body])
            body_b.append([p - tdir * th * f * 0.5 for p, f in body])
            strip = [(mid + wdir * w * 0.1, 0.55), (inner_end, 0.4), (edge, 0.12)]
            edge_t.append([p + tdir * max(th * f * 0.5, 0.002) for p, f in strip])
            edge_b.append([p - tdir * max(th * f * 0.5, 0.002) for p, f in strip])
            if 0.06 < t < 0.86:
                seam.append((c + wdir * w * 0.55, th * 0.22 + 0.006))
            if i in (4, 7, 10):
                spurs.append((back, -wdir, d))
        sk.rigid(slab(sk, body_t, body_b, K.CHITIN), blade)
        sk.rigid(slab(sk, edge_t, edge_b, K.BONE), blade)
        for p, o, d in spurs:
            sk.rigid(sk.cone(p + o * -0.01, p + o * 0.05 + d * 0.035, 0.018, 5, K.BONE, 0.6), blade)
        seam_pts = [p for p, _r in seam[:: max(len(seam) // 6, 1)]]
        seam_r = [r for _p, r in seam[:: max(len(seam) // 6, 1)]]
        glands.rigid(K.tube_path(glands, seam_pts, seam_r, 6, 16, 0, 0.9), blade)


def build_claws(sk: K.Skin) -> None:
    """The grasping claws folded in front of the chest: a sinewy upper arm, a plated forearm and a hand of three hooked
    fingers curling back towards the chest."""
    for side, s in K.SIDES:
        sh, el, wr, tip = (K.mirror(p, s) for p in CLAW)
        up, low, hand = (f"Claw{side}{b}" for b in ("Upper", "Lower", "Hand"))
        sk.auto(
            K.tube_path(sk, [sh + Vector((0, 0.03, 0.02)), sh.lerp(el, 0.5), el], [0.06, 0.05, 0.042], 10, 5, K.SINEW),
            ["Chest", up, low],
        )
        sk.rigid(
            K.limb_plate(
                sk, sh.lerp(el, 0.25), sh.lerp(el, 0.9), 0.048, -80, 80, 0.014, K.CHITIN, Vector((s, -0.5, 0))
            ),
            up,
        )
        sk.rigid(sk.sphere(el, 0.045, 8, 4, mi=K.CHITIN), low)
        sk.rigid(K.tube_path(sk, [el, el.lerp(wr, 0.5), wr], [0.042, 0.038, 0.034], 8, 4, K.CHITIN, 0.9), low)
        sk.rigid(sk.sphere(wr, 0.04, 8, 4, mi=K.SINEW), hand)
        d = (tip - wr).normalized()
        across = d.cross(Vector((0, 0, 1))).normalized()
        for k, off in enumerate((-0.035, 0.0, 0.035)):
            base = wr + across * off
            knuckle = base + d * 0.08 + Vector((0, 0, 0.01))
            end = knuckle + d * 0.05 + Vector((0, 0.03, -0.06))
            sk.rigid(
                K.tube_path(sk, [base, base.lerp(knuckle, 0.5), knuckle], [0.022, 0.02, 0.018], 6, 2, K.SINEW), hand
            )
            sk.rigid(
                K.tube_path(
                    sk, [knuckle, knuckle.lerp(end, 0.5) + d * 0.01, end], [0.017, 0.012, 0.003], 6, 3, K.BONE, 0.85
                ),
                hand,
            )
            if k == 1:
                sk.rigid(sk.sphere(knuckle, 0.022, 6, 3, mi=K.CHITIN), hand)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    sk = K.Skin("Creature", materials(), RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk, glands)
    build_neck(sk)
    build_head(sk, eyes)
    build_legs(sk)
    build_talons(sk, glands)
    build_claws(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


def posed_head(p: K.Pose, bone: str) -> Vector:
    """Where the head of `bone` is in pose p."""
    parent = RIG.parent[bone]
    if parent is None:
        return RIG.head[bone].copy()
    h = posed_point(p, parent, RIG.head[bone])
    return h + p.offset if bone == "Body" else h


def posed_point(p: K.Pose, bone: str, point: Vector) -> Vector:
    """Where a point that moves with `bone` (at rest at `point`) is in pose p."""
    return p.world(bone) @ (Vector(point) - RIG.head[bone]) + posed_head(p, bone)


def arc(a: Vector, b: Vector) -> Matrix:
    return a.rotation_difference(b).to_matrix()


def two_bone(root: Vector, target: Vector, a: float, b: float, pole: Vector) -> tuple:
    """Knee and end of a two-bone chain from root reaching for target, bending towards pole (as AlienLegs does)."""
    off = target - root
    dist = min(max(off.length, abs(a - b) + 0.001), (a + b) * 0.999)
    d = off.normalized()
    side = (pole - d * pole.dot(d)).normalized()
    cos_a = (a * a + dist * dist - b * b) / (2 * a * dist)
    sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
    return root + (d * cos_a + side * sin_a) * a, root + d * dist


def leg_ik(p: K.Pose, side: str, ankle: Vector, foot_world: Matrix | None = I3) -> None:
    """Bends the leg so its ankle reaches `ankle` (world), the knee towards its rest side (turned with the hips), the
    Foot with the world rotation foot_world (None: it keeps its angle to the lower leg)."""
    up, low, foot = (f"Hind{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
    hip_r, knee_r, ankle_r = RIG.head[up], RIG.head[low], RIG.head[foot]
    wp = p.world("Hips")
    hip = posed_head(p, up)
    knee, end = two_bone(hip, ankle, (knee_r - hip_r).length, (ankle_r - knee_r).length, wp @ LEG_POLE[side])
    w_up = arc(wp @ (knee_r - hip_r), knee - hip) @ wp
    w_low = arc(w_up @ (ankle_r - knee_r), end - knee) @ w_up
    p.set(up, wp.transposed() @ w_up)
    p.set(low, w_up.transposed() @ w_low)
    if foot_world is not None:
        p.set(foot, w_low.transposed() @ foot_world)


def level_feet(p: K.Pose) -> None:
    """Keeps the feet at their rest angle in the world (the game keeps the Foot's animated angle, so a trunk that
    leans must not tip the toes into the ground)."""
    for side, _s in K.SIDES:
        p.set(f"Hind{side}Foot", p.world(f"Hind{side}LowerLeg").transposed())


def talon(p: K.Pose, side: str, upper: float, lower: float = 0.0, blade: float = 0.0, spread: float = 0.0) -> None:
    """One talon: each joint pitched (degrees, + = swings forward over the top), spread swings it out."""
    s = 1.0 if side == "Left" else -1.0
    p.set(f"Arm{side}Upper", ry(s * spread) @ rx(upper))
    p.set(f"Arm{side}Lower", rx(lower))
    p.set(f"Arm{side}Blade", rx(blade))


def talons(p: K.Pose, upper: float, lower: float = 0.0, blade: float = 0.0, spread: float = 0.0) -> None:
    for side, _s in K.SIDES:
        talon(p, side, upper, lower, blade, spread)


def claws(p: K.Pose, upper: float, lower: float = 0.0, hand: float = 0.0, spread: float = 0.0) -> None:
    """Both grasping claws: each joint pitched (degrees, + = forward end down), spread swings them out."""
    for side, s in K.SIDES:
        p.set(f"Claw{side}Upper", rz(s * spread) @ rx(upper))
        p.set(f"Claw{side}Lower", rx(lower))
        p.set(f"Claw{side}Hand", rx(hand))


def tendrils(p: K.Pose, a: float, amount: float = 1.0, swing: float = 0.0, spread: float = 0.0) -> None:
    """The mouth tendrils writhing at phase a (radians), each on its own rhythm; swing: all swing back (+, degrees);
    spread: they flare out (degrees)."""
    for k in range(len(TENDRILS)):
        for side, s in K.SIDES:
            n = tendril_name(k, s)
            ph = 1.3 * k + (0.0 if s > 0 else 2.1)
            p.set(
                f"{n}A",
                ry(s * -spread) @ rx(swing + amount * 9 * math.sin(2 * a + ph)) @ ry(amount * 8 * math.sin(a + ph)),
            )
            p.set(
                f"{n}B",
                rx(swing * 0.6 + amount * 18 * math.sin(3 * a + ph + 0.8)) @ ry(amount * 12 * math.sin(2 * a + ph)),
            )


def pulse(t: float, at: float, width: float = 0.05) -> float:
    """A short bump around t = at."""
    return math.exp(-(((t - at) / width) ** 2))


def idle(t: float) -> K.Pose:
    """Hunched, breathing; the head turns from side to side, the talons twitch now and then (one, then the other),
    the claws fidget, the mouth tendrils writhe."""
    a = math.tau * t
    breath = math.sin(2 * a)
    turn = math.sin(a)
    p = K.Pose(RIG, (0, 0, 0.008 * breath))
    p.set("Spine", rx(-1.0 * breath)).set("Chest", rx(-1.2 * breath))
    p.set("Neck", rz(13 * turn) @ rx(2 * math.sin(a + 0.4)))
    p.set("Head", rz(8 * math.sin(a - 0.5)) @ rx(3 * math.sin(2 * a + 1.0)))
    p.set("Jaw", rx(2 + 2 * breath))
    p.set("Tail1", rz(-5 * turn))
    for side, at in (("Left", 0.3), ("Right", 0.7)):
        tw = pulse(t, at) - 0.6 * pulse(t, at + 0.06)
        talon(p, side, 1.5 * breath - 6 * tw, 4 * tw, -9 * tw)
    claws(p, 2 * math.sin(a + 1.0), 3 * math.sin(2 * a), 8 * math.sin(3 * a + 0.5))
    tendrils(p, a)
    level_feet(p)
    return p


def run(t: float) -> K.Pose:
    """The trunk's motion in the lope (legs at rest, the game steps them): low and leaning further forward, bobbing
    twice per cycle (one stride of each leg) and swaying, the head held level, the talons swept back low, the claws
    tucked, the tendrils streaming back."""
    a = math.tau * t
    w = math.sin(a)
    bob = math.cos(2 * a)
    p = K.Pose(RIG, (0, -0.02, -0.1 + 0.03 * bob))
    p.set("Body", rz(4 * w) @ rx(12 + 2 * bob))
    p.set("Hips", rz(-7 * w))
    p.set("Spine", rx(3) @ rz(-3 * w))
    p.set("Chest", rx(-2 * bob))
    p.set("Neck", rz(-4 * w) @ rx(-16 - 2 * bob))
    p.set("Head", rx(-4))
    p.set("Jaw", rx(6))
    p.set("Tail1", rz(-9 * math.sin(a - 0.8)) @ rx(-6))
    talons(p, -16 - 3 * bob, -6, -8, 4)
    claws(p, -20, 14, 10)
    tendrils(p, 2 * a, 0.6, 28)
    level_feet(p)
    return p


def attack(t: float) -> K.Pose:
    """The scything strike (0.5 s): the talons rise high over the head while it rears (to 0.3), then both scythe over and
    down in front with a lunge, the hit at HIT_FRAME (fully down by then), held a moment, then they fold back."""
    cock = K.smooth(t / 0.3) * (1 - K.smooth((t - 0.3) / 0.23))
    strike = K.smooth((t - 0.3) / 0.23) * (1 - K.smooth((t - 0.66) / 0.34))
    p = K.Pose(RIG, (0, 0.05 * cock - 0.22 * strike, 0.03 * cock - 0.12 * strike))
    p.set("Body", rx(-7 * cock + 14 * strike))
    p.set("Neck", rx(-10 * cock - 8 * strike))
    p.set("Head", rx(4 * cock - 6 * strike))
    p.set("Jaw", rx(10 * cock + 18 * strike))
    talons(
        p, 28 * cock + STRIKE[0] * strike, -14 * cock + STRIKE[1] * strike, 22 * cock + STRIKE[2] * strike, 10 * cock
    )
    claws(p, -18 * cock + 24 * strike, 12 * cock - 30 * strike, -20 * strike, 6 * strike)
    tendrils(p, math.tau * t, 0.5 * (cock + strike), -10 * strike, 18 * (cock + strike))
    level_feet(p)
    return p


def die(t: float) -> K.Pose:
    """The knees buckle (the body sinks on its planted feet, to 0.35), then it falls forward onto its left side
    (1.0): the trunk pitches down and rolls, the talons sprawl out, the claws curl, the head hits the ground, the
    legs fold up. The legs are solved like AlienLegs does it (the game switches it off on death)."""
    k = K.smooth(t / 0.35)
    f = K.smooth((t - 0.25) / 0.6)
    body = ry(DIE_ROLL * f) @ rx(10 * k * (1 - f) + DIE_PITCH * f)
    p = K.Pose(
        RIG, Vector((0, -0.04, -0.3)) * k * (1 - f) + DIE_SHIFT * f + Vector((0, 0, 0.08)) * math.sin(math.pi * f)
    )
    p.set("Body", body)
    p.set("Spine", rx(6 * k))
    p.set("Neck", rx(16 * k - 10 * f) @ ry(-12 * f) @ rz(-14 * f))
    p.set("Head", rx(-8 * f))
    p.set("Jaw", rx(26 * k))
    p.set("Tail1", rx(-10 * f) @ rz(8 * f))
    tendrils(p, 0.0, 0.0, -10 * k, 20 * k)
    talon(p, "Left", 70 * f, 20 * f, 40 * f, -50 * f)  # it falls onto the left one: it sprawls out in front
    talon(p, "Right", 25 * k + 15 * f, -10 * f, 20 * f, -40 * f)  # on top: it flops over the back
    claws(p, 30 * k, -50 * k, -40 * k)
    g = K.smooth((t - 0.5) / 0.4)  # the feet stay planted until the body is down, then the legs draw up
    for side, s in K.SIDES:
        rest = K.mirror(HIND[2], s)
        ankle = rest.lerp(posed_point(p, "Hips", K.mirror(DIE_ANKLE[side], s)), g)
        ankle.z = max(ankle.z, 0.44 * (1 - g) + 0.12 * g + 0.2 * math.sin(math.pi * g))
        foot = I3.to_quaternion().slerp((body @ DIE_FOOT[side]).to_quaternion(), g).to_matrix()
        leg_ik(p, side, ankle, foot)
    return p


HIT_FRAME = 8  # the talon tips' hit in the 15-frame Attack (0.27 s)
STRIKE = (100, 45, 64)  # degrees the talons' upper arm, forearm and blade swing forward in the strike
DIE_ROLL = 70  # degrees onto its left side
DIE_PITCH = 42  # degrees it pitches forward, so the trunk lies flat
DIE_SHIFT = Vector((0.3, -0.34, -0.92))  # where the Body ends up, so it rests on the ground
DIE_ANKLE = {  # where each ankle ends up, in the hips' rest space (x for the left side): the legs drawn up, the one
    # it lies on tucked in under the other
    "Left": Vector((0.06, -0.05, 0.62)),
    "Right": Vector((0.26, -0.12, 0.66)),
}
DIE_FOOT = {"Left": rz(-30) @ rx(-40), "Right": rx(-40)}  # the feet's end rotation relative to the body's

CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (20, run),
    "Attack": (15, attack),
    "Die": (45, die),
}

# --- preview ----------------------------------------------------------------------------------------


def bounds() -> tuple:
    """Bounds of the posed meshes (after the armature)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for name in ("Creature", "Eyes", "Glands"):
        ev = bpy.data.objects[name].evaluated_get(depsgraph)
        me = ev.to_mesh()
        for v in me.vertices:
            w = ev.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        ev.to_mesh_clear()
    return tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi)


def lowest(below: float = -0.01) -> dict:
    """The lowest point per bone (the vertex's main bone) of the posed Creature, for the bones under `below`."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    obj = bpy.data.objects["Creature"]
    names = {g.index: g.name for g in obj.vertex_groups}
    ev = obj.evaluated_get(depsgraph)
    me = ev.to_mesh()
    low: dict = {}
    for v, rest in zip(me.vertices, obj.data.vertices):
        z = (ev.matrix_world @ v.co).z
        bone = names[max(rest.groups, key=lambda g: g.weight).group]
        if z < below and z < low.get(bone, 1e9):
            low[bone] = round(z, 3)
    ev.to_mesh_clear()
    return low


def rnd(v: Vector) -> tuple:
    return tuple(round(x, 3) for x in v)


def tips(arm: bpy.types.Object) -> str:
    return " ".join(f"{s}={rnd(arm.matrix_world @ arm.pose.bones[f'Arm{s}Blade'].tail)}" for s in ("Left", "Right"))


def measures(arm: bpy.types.Object) -> None:
    """The positions the game needs (rest pose): the talon tips, the chest point between the claws, the head, the
    ankle height; and the knees' bend."""
    body = bpy.data.objects["Creature"].data
    names = {g.index: g.name for g in bpy.data.objects["Creature"].vertex_groups}

    def owned(bones: list) -> list:
        return [v.co for v in body.vertices if v.groups and names[max(v.groups, key=lambda g: g.weight).group] in bones]

    trunk = owned(["Hips", "Spine", "Chest"])
    print("HALF-WIDTH trunk", round(max(abs(c.x) for c in trunk), 3), "top", round(max(c.z for c in trunk), 3))
    head = owned(["Head", "Jaw"])
    print("HEAD center", rnd(sum(head, Vector()) / len(head)), "snout", rnd(min(head, key=lambda c: c.y)))
    print("HEAD bone", rnd(RIG.head["Head"]), "BODY bone", rnd(RIG.head["Body"]))
    print("TALON TIPS rest", tips(arm))
    hands = [RIG.head[f"Claw{s}Hand"] for s in ("Left", "Right")]
    chest = (hands[0] + hands[1]) / 2
    print("CHEST hook point (between the claws' wrists)", rnd(chest), "claw tips", rnd(RIG.tail["ClawLeftHand"]))
    hip, knee, ankle = (RIG.head[f"HindLeft{b}"] for b in ("UpperLeg", "LowerLeg", "Foot"))
    print("LEG ankle", rnd(ankle), "knee off the hip-ankle line", round(K.seg_dist(knee, hip, ankle), 3))
    print(
        "LEG lengths",
        round((knee - hip).length, 3),
        round((ankle - knee).length, 3),
        "hip-ankle",
        round((ankle - hip).length, 3),
    )
    feet = [v.co for v in body.vertices if v.co.z < 0.02]
    print("FEET low points", len(feet), "min z", round(min(v.co.z for v in body.vertices), 4))
    gl = [v.co for v in bpy.data.objects["Glands"].data.vertices]
    print("GLANDS center", rnd(sum(gl, Vector()) / len(gl)))


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.4, 1.0, 0))
    shots = []
    target = (0, -0.1, 1.15)
    K.rest_pose(arm)
    print("BOUNDS rest", bounds())
    for view, zoom in (("iso", 0.42), ("hero", 0.5), ("back", 0.5), ("iso", 1.4)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((5.6, -0.1, 1.25)), (0, -0.1, 1.2), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.9, -2.2, 2.2)), (0, -0.92, 1.92), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    C.render_from(OUT / "wip" / f"{tag}_top.png", Vector((0.0, -0.1, 7.5)), (0, -0.1, 0.0), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_top.png")
    for name, pose in (
        ("idle", idle(0.3)),
        ("run", run(0.25)),
        ("attack_cock", attack(4 / 15)),
        ("attack_hit", attack(HIT_FRAME / 15)),
        ("die", die(1.0)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        print("BOUNDS", name, bounds(), "tips", tips(arm))
        path = OUT / "wip" / f"{tag}_{name}.png"
        aim = (0, -0.8, 0.4) if name == "die" else target
        C.render(path, view="hero", samples=24, size=512, target=aim, zoom=0.5)
        shots.append(path)
    K.apply(arm, attack(HIT_FRAME / 15))
    bpy.context.view_layer.update()
    C.render_from(OUT / "wip" / f"{tag}_strike_side.png", Vector((5.6, -0.7, 1.2)), (0, -0.7, 1.1), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_strike_side.png")
    K.apply(arm, die(0.45))
    bpy.context.view_layer.update()
    C.render_from(OUT / "wip" / f"{tag}_die_mid.png", Vector((5.6, -0.6, 1.0)), (0, -0.6, 0.8), 50, 24, 512)
    shots.append(OUT / "wip" / f"{tag}_die_mid.png")
    K.apply(arm, die(1.0))
    bpy.context.view_layer.update()
    C.render(OUT / "wip" / f"{tag}_die_iso.png", view="iso", samples=24, size=512, target=(0, -0.8, 0.3), zoom=0.42)
    shots.append(OUT / "wip" / f"{tag}_die_iso.png")
    C.render_from(OUT / "wip" / f"{tag}_die_front.png", Vector((0.0, -5.6, 0.5)), (0, -0.8, 0.3), 50, 24, 512)
    shots.append(OUT / "wip" / f"{tag}_die_front.png")
    K.rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def stats(arm: bpy.types.Object) -> None:
    """The bounds and the lowest points of the clips' key poses (nothing more than about 2 cm under the ground)."""
    for name, pose in (
        ("rest", K.Pose(RIG)),
        ("idle", idle(0.3)),
        ("run", run(0.25)),
        ("attack_cock", attack(4 / 15)),
        ("attack_hit", attack(HIT_FRAME / 15)),
    ):
        K.apply(arm, pose)
        bpy.context.view_layer.update()
        print("BOUNDS", name, bounds(), "tips", tips(arm))
        print("  LOW", lowest())
    for f in range(0, 46, 3):
        K.apply(arm, die(f / 45))
        bpy.context.view_layer.update()
        print("DIE", f, bounds(), "LOW", lowest(-0.02))
    K.rest_pose(arm)


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    measures(arm)
    stats(arm)
    if MODE == "stats":  # only the measures and the bounds of the poses, no renders
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "stalker_procedural.blend")
        C.export_glb(OUT / "stalker_draft.glb")


main()
