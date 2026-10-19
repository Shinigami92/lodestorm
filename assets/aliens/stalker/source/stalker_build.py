"""Stalker: the hive's ambusher (tier 5 hunter), see-through until it attacks. A low, long, slinking reptile like a
chameleon crossed with a monitor lizard, with mantis-like forearms: a narrow, deep body close to the ground on four
short, sturdy, sprawling legs with clawed toes, a long tapering tail curled at its tip, a narrow wedge head under a
bony casque, big turreted eyes that swivel on their own, and two folded blade-arms tucked under the throat that snap
forward in the attack. Its chitin is darker than the other strains' and mottled with small overlapping scales; the
glow is sparse: the eyes and thin seams along the flanks and the casque. Rigged and animated.

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/aliens/stalker/source/stalker_build.py wip r1     # quick renders of the poses
    tools/blender.sh assets/aliens/stalker/source/stalker_build.py stats      # measures and pose bounds, no renders
    tools/blender.sh assets/aliens/stalker/source/stalker_build.py final      # renders + stalker_procedural.blend

Everything it writes goes to tmp/assets/stalker/; stalker_bake.py turns stalker_procedural.blend into the game asset.

Layout (Blender Z-up meters; the stalker faces -Y, its left is +X). Feet on the ground at the origin, the origin under
the middle of the body; back about 0.7 m high (with the dorsal crest), snout to tail tip about 2.2 m.

Skeleton "Skeleton": Root, Body (center of the trunk: moves the whole body), Hips (to the rump) with the tail
(Tail1..4) and the hind legs, Spine, Chest with the front legs and the blade-arms (Arm<Side>Upper, the short coxa;
Arm<Side>Lower, the femur rising forward beside the jaw; Arm<Side>Blade, the scythe folded back under it, its tail at
the blade's tip; only the clips move them), Neck, Head (skull, casque, teeth), Jaw and the eye turrets (Eye<Side>,
under Head). Legs (<Front|Hind><Side>UpperLeg, LowerLeg, Foot): the game moves them by IK (two bones reaching the
ankle = the Foot bone's head, the Foot keeps its angle), so the clips leave them at rest; only "Die" folds them. The
legs sprawl: the upper legs reach out sideways, the knees and elbows stand out and up from the hip-ankle line (front
elbows a little back, hind knees a little forward).
Meshes: "Creature" (one skinned object: trunk, neck, head, tail and legs weighted to the nearest bones; scales,
casque, blade-arms, teeth and claws rigid or nearly), "Eyes" (constant emissive, in the turrets) and "Glands" (constant
emissive: dashed seams along the flanks and one along each side of the casque).

Animations (one action per clip, each in its own NLA track, 30 fps): "Idle" (loop, 3 s: low and still, the head
turning slowly, the eyes swivelling on their own, the tail tip curling), "Run" (loop: a low, sinuous slink, the spine
and tail swinging side to side in a travelling wave, the head held steady), "Attack" (once, 0.5 s: the blade-arms
cock up, then snap forward and down with a short lunge, the hit at frame HIT_FRAME, then fold back) and "Die" (once:
a jolt, it rolls onto its left side, the blades and the legs fold).
"""

import itertools
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "stalker"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bpy
from mathutils import Vector

import common as C
import creature as K
from common import rx, ry, rz

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"

ASSET = "Stalker"
FPS = 30
GLAND_GLOW = 1.5  # sparse and faint: the eyes (8) stay the main glow
SINEW_SHADE = 0.7  # darker than the other strains (docs/GAME_DESIGN.md, Alien look: stalkers have darker chitin)

# --- skeleton -------------------------------------------------------------------------------------

BODY = Vector((0, 0.0, 0.38))
PELVIS = Vector((0, 0.4, 0.372))
SHOULDER = Vector((0, -0.3, 0.39))
WITHERS = Vector((0, -0.46, 0.41))
SKULL = Vector((0, -0.6, 0.44))
SNOUT = Vector((0, -0.97, 0.37))
JAW_PIVOT = Vector((0, -0.63, 0.38))
JAW_TIP = Vector((0, -0.95, 0.34))
TAIL = [
    PELVIS,
    Vector((0, 0.62, 0.34)),
    Vector((0, 0.84, 0.245)),
    Vector((0, 1.03, 0.175)),
    Vector((0, 1.17, 0.12)),
]
# Eye turrets (left): the turret's center on the side of the head and the gaze.
EYE = Vector((0.07, -0.71, 0.495))
GAZE = Vector((0.78, -0.55, 0.22)).normalized()
# Blade-arm joints (left): mount under the throat, elbow (coxa to femur), knee (femur to blade), the blade's tip.
ARM = [
    Vector((0.08, -0.47, 0.28)),
    Vector((0.12, -0.57, 0.21)),
    Vector((0.14, -0.85, 0.32)),
    Vector((0.14, -0.66, 0.1)),
]
# Leg joints per side (x for the left side): hip/shoulder, knee/elbow, ankle, ball of the foot. The upper legs reach
# out sideways and a little down, the lower legs drop almost straight to the ground (sprawling, like a monitor's).
FRONT = [
    Vector((0.12, -0.32, 0.34)),
    Vector((0.4, -0.27, 0.3)),
    Vector((0.43, -0.34, 0.075)),
    Vector((0.46, -0.43, 0.032)),
]
HIND = [
    Vector((0.12, 0.32, 0.335)),
    Vector((0.41, 0.25, 0.3)),
    Vector((0.44, 0.34, 0.075)),
    Vector((0.48, 0.25, 0.032)),
]
LEGS = (("Front", FRONT, "Chest"), ("Hind", HIND, "Hips"))

BONES = [  # name, head, tail, parent
    ("Root", (0, 0, 0), (0, -0.2, 0), None),
    ("Body", BODY, BODY + Vector((0, -0.12, -0.04)), "Root"),
    ("Hips", BODY, PELVIS, "Body"),
    ("Spine", BODY, SHOULDER, "Body"),
    ("Chest", SHOULDER, WITHERS, "Spine"),
    ("Neck", WITHERS, SKULL, "Chest"),
    ("Head", SKULL, SNOUT, "Neck"),
    ("Jaw", JAW_PIVOT, JAW_TIP, "Head"),
]
for _i in range(4):
    BONES.append((f"Tail{_i + 1}", TAIL[_i], TAIL[_i + 1], "Hips" if _i == 0 else f"Tail{_i}"))
for _side, _s in K.SIDES:
    BONES.append((f"Eye{_side}", K.mirror(EYE, _s), K.mirror(EYE + GAZE * 0.07, _s), "Head"))
    _a = [K.mirror(p, _s) for p in ARM]
    BONES += [
        (f"Arm{_side}Upper", _a[0], _a[1], "Chest"),
        (f"Arm{_side}Lower", _a[1], _a[2], f"Arm{_side}Upper"),
        (f"Arm{_side}Blade", _a[2], _a[3], f"Arm{_side}Lower"),
    ]
    for _leg, _pts, _parent in LEGS:
        BONES += [
            (f"{_leg}{_side}UpperLeg", K.mirror(_pts[0], _s), K.mirror(_pts[1], _s), _parent),
            (f"{_leg}{_side}LowerLeg", K.mirror(_pts[1], _s), K.mirror(_pts[2], _s), f"{_leg}{_side}UpperLeg"),
            (f"{_leg}{_side}Foot", K.mirror(_pts[2], _s), K.mirror(_pts[3], _s), f"{_leg}{_side}LowerLeg"),
        ]
RIG = K.Rig(BONES)
TRUNK_BONES = ["Hips", "Spine", "Chest", "Neck"]
TAIL_BONES = ["Hips", "Tail1", "Tail2", "Tail3", "Tail4"]

# --- shapes -----------------------------------------------------------------------------------------

# Trunk profile from the rump forward: y, center z, half-width, top, bottom. Narrow and deep like a chameleon's (the
# flanks show from the side), tapering into the neck.
TRUNK = [
    (0.48, 0.362, 0.07, 0.072, 0.06),
    (0.42, 0.368, 0.11, 0.126, 0.095),
    (0.3, 0.38, 0.145, 0.185, 0.13),
    (0.15, 0.388, 0.16, 0.215, 0.15),
    (0.0, 0.39, 0.165, 0.225, 0.158),
    (-0.15, 0.392, 0.16, 0.22, 0.15),
    (-0.3, 0.4, 0.148, 0.202, 0.13),
    (-0.42, 0.41, 0.118, 0.162, 0.1),
    (-0.5, 0.422, 0.088, 0.114, 0.078),
    (-0.57, 0.434, 0.07, 0.09, 0.064),
]
# Skull with the upper jaw: a narrow wedge from the back of the head to the snout.
SKULL_PROFILE = [
    (-0.56, 0.45, 0.072, 0.07, 0.06),
    (-0.62, 0.458, 0.088, 0.078, 0.066),
    (-0.7, 0.455, 0.088, 0.07, 0.06),
    (-0.78, 0.438, 0.074, 0.056, 0.046),
    (-0.86, 0.415, 0.056, 0.04, 0.034),
    (-0.92, 0.395, 0.038, 0.027, 0.022),
    (-0.965, 0.384, 0.018, 0.013, 0.011),
]
# Lower jaw from the hinge to the chin.
JAW_PROFILE = [
    (-0.6, 0.372, 0.064, 0.022, 0.048),
    (-0.7, 0.362, 0.07, 0.022, 0.044),
    (-0.8, 0.352, 0.058, 0.02, 0.034),
    (-0.88, 0.346, 0.042, 0.017, 0.024),
    (-0.94, 0.346, 0.024, 0.012, 0.013),
]
TAIL_PATH = [
    Vector((0, 0.36, 0.378)),
    Vector((0, 0.5, 0.362)),
    Vector((0, 0.66, 0.33)),
    Vector((0, 0.84, 0.255)),
    Vector((0, 0.99, 0.185)),
    Vector((0, 1.1, 0.145)),
    Vector((0, 1.17, 0.12)),
    Vector((0, 1.21, 0.09)),
    Vector((0, 1.195, 0.06)),
    Vector((0, 1.16, 0.062)),
]
TAIL_RADII = [0.125, 0.105, 0.084, 0.064, 0.05, 0.04, 0.032, 0.026, 0.022, 0.018]
CASQUE = [
    Vector((0, -0.84, 0.45)),
    Vector((0, -0.74, 0.51)),
    Vector((0, -0.62, 0.59)),
    Vector((0, -0.52, 0.63)),
    Vector((0, -0.44, 0.6)),
]

TRUNK_SHAPE = K.Profile(TRUNK)
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
    """An angle around the trunk (0 = left side, 90 = top) for side s."""
    return a if s > 0 else 180 - a


def build_trunk(sk: K.Skin, glands: K.Skin) -> None:
    n = 18
    rings = []
    for i in range(n + 1):
        c, w, top, bot = TRUNK_SHAPE.at(i / n)
        rings.append(K.section(c, Vector((0, -1, 0)), w, top, bot, 16, 0.006, i * 0.9))
    sk.auto(sk.loft(rings, K.SINEW), TRUNK_BONES)
    # Dorsal scutes from the neck to the rump, overlapping, the rear edge of each lifting off.
    ys = [-0.58, -0.49, -0.4, -0.31, -0.22, -0.13, -0.04, 0.05, 0.14, 0.23, 0.32, 0.41]
    for y0, y1 in itertools.pairwise(ys):
        width = 30 if y0 < -0.45 else 27
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0 - 0.015, y1 + 0.03, 90 - width, 90 + width, 0.006, 0.02, K.CHITIN, 4, 2, 0.016),
            TRUNK_BONES,
            8.0,
        )
    # The dorsal crest: a row of short, blunt spines along the midline, tallest over the shoulders.
    for k, y in enumerate([-0.52, -0.42, -0.32, -0.22, -0.12, -0.02, 0.08, 0.18, 0.28, 0.37]):
        h = 0.068 - 0.03 * abs(y + 0.25) / 0.6
        base = TRUNK_SHAPE.surface(y, 90, 0.015)
        tip = base + Vector((0, 0.035, h))
        sk.auto(sk.cone(base, tip, 0.024, 5, K.CHITIN, 0.55), TRUNK_BONES, 8.0)
    # Flank scales in two staggered rows below the scutes and a row of belly plates; the gap between the scutes and
    # the upper row holds the glowing seam.
    rows = [(24, 57, 0.075, 0.0), (-14, 27, 0.08, 0.035)]
    for side, s in K.SIDES:
        for a0, a1, step, shift in rows:
            y = -0.47 + shift
            while y < 0.36:
                b0, b1 = sorted((side_angle(a0, s), side_angle(a1, s)))
                sk.auto(
                    K.shell(sk, TRUNK_SHAPE, y, y + step + 0.02, b0, b1, 0.004, 0.014, K.CHITIN, 3, 2, 0.012),
                    TRUNK_BONES,
                    8.0,
                )
                y += step
        # The seam: three dashes along each flank, sunk into the gap.
        for y0, y1 in ((-0.42, -0.2), (-0.13, 0.09), (0.16, 0.34)):
            pts = [TRUNK_SHAPE.surface(y0 + (y1 - y0) * k / 3, side_angle(59.5, s), -0.002) for k in range(4)]
            glands.auto(K.tube_path(glands, pts, [0.009, 0.014, 0.014, 0.009], 6, 6, 0, 0.8), TRUNK_BONES, 8.0)
    # Belly plates.
    for y0, y1 in itertools.pairwise([-0.4, -0.25, -0.1, 0.05, 0.2, 0.33]):
        sk.auto(
            K.shell(sk, TRUNK_SHAPE, y0, y1 + 0.02, 232, 308, 0.004, 0.012, K.CHITIN, 4, 2, 0.006), TRUNK_BONES, 8.0
        )


def build_head(sk: K.Skin, eyes: K.Skin, glands: K.Skin) -> None:
    # Skull and upper jaw (the underside is the roof of the mouth).
    rings = []
    n = 12
    for i in range(n + 1):
        y, z, w, top, bot = K.catmull([list(r) for r in SKULL_PROFILE], i / n)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 14, 0.003, 3 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    _mouth_faces(sk, verts, below=True)
    # Head plates: a brow over each eye and plates down the snout.
    for y0, y1, a in ((-0.84, -0.94, 50), (-0.76, -0.86, 54)):
        sk.rigid(K.shell(sk, SKULL_SHAPE, y1, y0, 90 - a, 90 + a, 0.003, 0.014, K.CHITIN, 5, 2, -0.004), "Head")
    # The casque: a tall bony helmet rising back from the brows over the neck, a ridge along its top.
    rings = []
    for i in range(9):
        t = i / 8
        c = K.path_point(CASQUE, t)
        d = K.path_point(CASQUE, min(t + 0.05, 1)) - K.path_point(CASQUE, max(t - 0.05, 0))
        h = 0.016 + 0.03 * math.sin(math.pi * min(t * 1.15, 1.0)) ** 0.7
        w = 0.026 + 0.03 * math.sin(math.pi * min(0.15 + t, 1.0)) * (1 - 0.6 * t)
        rings.append(K.section(c - Vector((0, 0, h * 0.4)), d, w, h, 0.05 * (1 - t) + 0.02, 8))
    sk.rigid(sk.loft(rings, K.CHITIN), "Head")
    for t in (0.2, 0.4, 0.6, 0.8):
        c = K.path_point(CASQUE, t)
        sk.rigid(sk.cone(c + Vector((0, 0, 0.005)), c + Vector((0, 0.04, 0.04)), 0.016, 5, K.BONE, 0.5), "Head")
    # Throat: under the head, from the neck into the lower jaw.
    pts = [Vector((0, -0.48, 0.36)), Vector((0, -0.56, 0.34)), Vector((0, -0.66, 0.335))]
    sk.auto(K.tube_path(sk, pts, [0.075, 0.068, 0.055], 12, 4, K.SINEW), ["Neck", "Head", "Jaw"])
    # Lower jaw.
    rings = []
    for i in range(9):
        y, z, w, top, bot = K.catmull([list(r) for r in JAW_PROFILE], i / 8)
        rings.append(K.section(Vector((0, y, z)), Vector((0, -1, 0)), w, top, bot, 12, 0.002, 9 + i))
    verts = sk.rigid(sk.loft(rings, K.CHITIN), "Jaw")
    _mouth_faces(sk, verts, below=False)
    for side, s in K.SIDES:
        # Teeth along the upper jaw's edge, pointing down, and a few on the lower jaw.
        for y in (-0.7, -0.76, -0.82, -0.88):
            c, w, _top, bot = SKULL_SHAPE.at((SKULL_PROFILE[0][0] - y) / (SKULL_PROFILE[0][0] - SKULL_PROFILE[-1][0]))
            base = Vector((s * w * 0.8, y, c.z - bot * 0.7))
            sk.rigid(sk.cone(base, base + Vector((0, -0.006, -0.024)), 0.009, 4, K.BONE), "Head")
        for y in (-0.73, -0.85):
            base = Vector((s * 0.05, y, 0.365))
            sk.rigid(sk.cone(base, base + Vector((0, -0.004, 0.02)), 0.008, 4, K.BONE), "Jaw")
        # Eye turret: a ball of scaly lids on the side of the head, narrowing to the pupil, which glows.
        c = K.mirror(EYE, s)
        g = K.mirror(GAZE, s)
        bone = f"Eye{side}"
        rings = [
            K.section(c + g * o, g, r, r, r, 12)
            for o, r in ((-0.03, 0.03), (-0.012, 0.05), (0.01, 0.053), (0.03, 0.044), (0.045, 0.03))
        ]
        sk.rigid(sk.loft(rings, K.CHITIN), bone)
        for o, r in ((0.0, 0.056), (0.024, 0.05)):  # ridges of the lids
            band = [K.section(c + g * (o + d), g, r, r, r, 12) for d in (-0.005, 0.005)]
            sk.rigid(sk.loft(band, K.CHITIN), bone)
        eyes.rigid(eyes.sphere(c + g * 0.04, 0.024, 10, 5), bone)
        # The casque's glowing seam: a slit along each side of the casque.
        seam = [
            K.path_point(CASQUE, t)
            + Vector((s * (0.02 + 0.03 * math.sin(math.pi * min(0.15 + t, 1.0)) * (1 - 0.6 * t)), 0, -0.012))
            for t in (0.12, 0.3, 0.48, 0.64)
        ]
        glands.rigid(K.tube_path(glands, seam, [0.009, 0.013, 0.013, 0.009], 6, 6, 0, 0.85), "Head")


def _mouth_faces(sk: K.Skin, verts: list, below: bool) -> None:
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        n = f.normal
        if ((n.z < -0.5) if below else (n.z > 0.5)) and f.calc_center_median().y < -0.66:
            f.material_index = K.MOUTH


def build_tail(sk: K.Skin) -> None:
    sk.auto(K.tube_path(sk, TAIL_PATH, TAIL_RADII, 12, 26, K.CHITIN, 0.92), TAIL_BONES)
    # Scale bands around the tail and a row of low spines along its top, both shrinking to the tip.
    for k in range(9):
        t = 0.04 + k * 0.08
        c = K.path_point(TAIL_PATH, t)
        d = K.path_point(TAIL_PATH, t + 0.02) - K.path_point(TAIL_PATH, t - 0.02)
        r = K.catmull([[x] for x in TAIL_RADII], t)[0]
        o = d.normalized()
        ring = [
            K.section(c + o * x, d, r + dr, (r + dr) * 0.92, (r + dr) * 0.92, 12)
            for x, dr in ((-0.025, 0.004), (0.02, 0.012 + r * 0.06))
        ]
        sk.auto(sk.loft(ring, K.CHITIN), TAIL_BONES, 8.0)
        if k < 7:
            top = c + Vector((0, 0, r * 0.92 + 0.006))
            sk.auto(
                sk.cone(
                    top - o * 0.01,
                    top + o * 0.04 + Vector((0, 0, 0.012 + r * 0.25)),
                    0.012 + r * 0.12,
                    5,
                    K.CHITIN,
                    0.55,
                ),
                TAIL_BONES,
                8.0,
            )


def build_legs(sk: K.Skin) -> None:
    for leg, pts, body in LEGS:
        hind = leg == "Hind"
        for side, s in K.SIDES:
            j = [K.mirror(p, s) for p in pts]
            up, low, foot = (f"{leg}{side}{b}" for b in ("UpperLeg", "LowerLeg", "Foot"))
            # Upper leg: a thick, muscular haunch / shoulder reaching out sideways from the flank.
            top = j[0] + Vector((s * -0.05, 0.0, 0.05))
            radii = [0.12, 0.108, 0.09, 0.076] if hind else [0.112, 0.1, 0.084, 0.072]
            mid = j[0].lerp(j[1], 0.5) + Vector((0, 0, 0.02))
            sk.auto(K.tube_path(sk, [top, mid, j[1]], radii, 10, 6, K.SINEW, 0.92, 0.004), [body, up, low])
            # Scales over the top of the upper leg.
            sk.rigid(
                K.limb_plate(
                    sk,
                    j[0].lerp(j[1], 0.3),
                    j[1].lerp(j[0], 0.1),
                    0.076 if hind else 0.072,
                    -70,
                    70,
                    0.016,
                    K.CHITIN,
                    Vector((0, 0, 1)),
                ),
                up,
            )
            # Knee / elbow: a chitin cap.
            sk.rigid(
                sk.sphere(j[1] + Vector((s * 0.01, 0, 0.012)), 0.068, 10, 5, scale=(1.0, 1.0, 0.85), mi=K.CHITIN), low
            )
            # Lower leg: short and thick, scaled on the outside.
            mid = j[1].lerp(j[2], 0.5) + Vector((s * 0.008, 0, 0))
            sk.auto(K.tube_path(sk, [j[1], mid, j[2]], [0.07, 0.06, 0.052], 10, 4, K.SINEW), [up, low, foot])
            sk.rigid(
                K.limb_plate(
                    sk, j[1].lerp(j[2], 0.12), j[1].lerp(j[2], 0.85), 0.058, -80, 80, 0.014, K.CHITIN, Vector((s, 0, 0))
                ),
                low,
            )
            # Foot: a broad, flat hand on the ground with four splayed, clawed toes pointing forward and out.
            sk.auto(
                K.tube_path(sk, [j[2], j[2].lerp(j[3], 0.5), j[3]], [0.054, 0.05, 0.045], 8, 3, K.SINEW), [low, foot]
            )
            sk.rigid(sk.sphere(j[3] + Vector((0, 0, 0.003)), 0.054, 10, 4, scale=(1.15, 1.2, 0.6), mi=K.SINEW), foot)
            fwd = Vector((s * (0.5 if hind else 0.3), -1, 0)).normalized()
            for k, ang in enumerate((-50, -18, 12, 42)):
                a = math.radians(ang)
                toe = Vector((fwd.x * math.cos(a) - fwd.y * math.sin(a), fwd.x * math.sin(a) + fwd.y * math.cos(a), 0))
                toe.normalize()
                reach = (0.085, 0.11, 0.115, 0.095)[k if s > 0 else 3 - k]
                base = j[3] + toe * 0.03 + Vector((0, 0, 0.004))
                knuckle = j[3] + toe * (reach * 0.62) + Vector((0, 0, 0.022))
                sk.rigid(
                    K.tube_path(
                        sk,
                        [base, base.lerp(knuckle, 0.5) + Vector((0, 0, 0.004)), knuckle],
                        [0.022, 0.019, 0.016],
                        5,
                        2,
                        K.SINEW,
                        0.85,
                    ),
                    foot,
                )
                tip = j[3] + toe * reach
                tip.z = 0.0
                sk.rigid(
                    K.tube_path(
                        sk,
                        [knuckle, knuckle.lerp(tip, 0.5) + Vector((0, 0, 0.008)), tip],
                        [0.016, 0.012, 0.004],
                        5,
                        2,
                        K.BONE,
                        0.8,
                    ),
                    foot,
                )
            # Spur at the back of the ankle.
            back = Vector((0, -0.05, 0.02)) if hind else Vector((0, 0.05, 0.02))
            sk.rigid(
                sk.cone(j[2] + Vector((s * 0.01, 0, -0.01)), j[2] + back + Vector((s * 0.02, 0, 0)), 0.014, 5, K.BONE),
                low,
            )


def build_arms(sk: K.Skin) -> None:
    """The mantis blade-arms, folded under the throat: a short coxa from the chest, the femur rising forward beside
    the jaw (spines along its underside) and the blade folded back under it, its sharp edge up against the spines."""
    for side, s in K.SIDES:
        m, e, k, tip = (K.mirror(p, s) for p in ARM)
        up, low, blade = (f"Arm{side}{b}" for b in ("Upper", "Lower", "Blade"))
        sk.auto(
            sk.sphere(m + Vector((0, 0.01, 0.01)), 0.05, 10, 5, scale=(1.0, 1.2, 0.9), mi=K.SINEW), ["Chest", up], 2.0
        )
        sk.rigid(K.tube_path(sk, [m, m.lerp(e, 0.5), e], [0.042, 0.04, 0.036], 8, 4, K.CHITIN), up)
        sk.rigid(sk.sphere(e, 0.04, 8, 4, mi=K.CHITIN), low)
        # Femur: flat (narrow sideways, tall), thickest in the middle.
        mid = e.lerp(k, 0.5) + Vector((s * 0.008, 0, 0.012))
        sk.rigid(K.tube_path(sk, [e, mid, k], [0.036, 0.042, 0.03], 8, 7, K.CHITIN, 1.0), low)
        d = (k - e).normalized()
        down = d.cross(Vector((s, 0, 0))).normalized()
        if down.z > 0:
            down = -down
        for t in (0.3, 0.5, 0.7, 0.88):
            base = e.lerp(k, t) + down * 0.025
            sk.rigid(sk.cone(base, base + down * 0.035 + d * 0.012, 0.01, 4, K.BONE, 0.6), low)
        sk.rigid(sk.sphere(k, 0.034, 8, 4, mi=K.CHITIN), blade)
        # Blade: a flat curved scythe folded back from the knee, hooking forward at the tip; its edge (up) is pale
        # bone, its back a row of short spurs.
        ctrl = [k, k + Vector((0, 0.07, -0.05)), k + Vector((0, 0.16, -0.1)), k + Vector((0, 0.205, -0.165)), tip]
        top_rows, bot_rows, spurs = [], [], []
        n = 12
        side_n = Vector((s, 0, 0))
        for i in range(n + 1):
            t = i / n
            c = K.path_point(ctrl, t)
            dd = (K.path_point(ctrl, min(t + 0.03, 1)) - K.path_point(ctrl, max(t - 0.03, 0))).normalized()
            edge_dir = dd.cross(side_n).normalized()  # toward the sharp edge: up, against the femur
            if edge_dir.dot(k - c + Vector((0, 0, 0.05))) < 0:
                edge_dir = -edge_dir
            width = 0.08 * math.sin(math.pi * min(0.2 + t, 1.0)) ** 0.5 * (1 - t) ** 0.4 + 0.008
            thick = 0.016 * (1 - t) + 0.004
            back = c - edge_dir * width * 0.4
            edge = c + edge_dir * width * 0.6
            top_rows.append([back + side_n * thick * 0.6, c + side_n * thick, edge + side_n * 0.002])
            bot_rows.append([back - side_n * thick * 0.6, c - side_n * thick, edge - side_n * 0.002])
            if 0.15 < t < 0.75 and i % 2 == 0:
                spurs.append((back, -edge_dir, dd))
        sk.rigid(slab(sk, top_rows, bot_rows, K.BONE), blade)
        for back, out, dd in spurs:
            sk.rigid(sk.cone(back, back + out * 0.03 + dd * 0.012, 0.009, 4, K.BONE, 0.5), blade)


def build(root: bpy.types.Object, arm: bpy.types.Object) -> tuple:
    sk = K.Skin("Creature", materials(), RIG)
    eyes = K.Skin("Eyes", [C.mat_emissive("Eyes", K.EYE_COLOR, 8.0)], RIG)
    glands = K.Skin("Glands", [C.mat_emissive("Glands", K.EYE_COLOR, GLAND_GLOW)], RIG)
    build_trunk(sk, glands)
    build_head(sk, eyes, glands)
    build_tail(sk)
    build_legs(sk)
    build_arms(sk)
    objs = (sk.finish(root), eyes.finish(root), glands.finish(root))
    for obj in objs:
        obj.modifiers.new("Armature", "ARMATURE").object = arm
        C.shade_smooth(obj)
    return objs


# --- posing -----------------------------------------------------------------------------------------


def arms(p: K.Pose, upper: float, lower: float, blade: float, spread: float = 0.0) -> None:
    """Both blade-arms: each joint pitched (degrees, + = forward end down), spread swings them out."""
    for side, s in K.SIDES:
        p.set(f"Arm{side}Upper", rz(s * spread) @ rx(upper))
        p.set(f"Arm{side}Lower", rx(lower))
        p.set(f"Arm{side}Blade", rx(blade))


def tail(p: K.Pose, sway: list, lift: list) -> None:
    for i in range(4):
        p.set(f"Tail{i + 1}", rz(sway[i]) @ rx(lift[i]))


def eyes(p: K.Pose, left: tuple, right: tuple) -> None:
    """Eye turrets: (turn, tilt) in degrees each."""
    p.set("EyeLeft", rz(left[0]) @ rx(left[1]))
    p.set("EyeRight", rz(right[0]) @ rx(right[1]))


def idle(t: float) -> K.Pose:
    """Low and still, breathing slowly; the head turns from side to side, the eyes swivel on their own, the tail tip
    curls up and sideways and uncurls."""
    a = math.tau * t
    breath = math.sin(2 * a)
    turn = math.sin(a)
    curl = 0.5 - 0.5 * math.cos(2 * a)
    p = K.Pose(RIG, (0, 0, 0.004 * breath))
    p.set("Spine", rx(-0.8 * breath)).set("Chest", rx(-0.8 * breath))
    p.set("Neck", rz(12 * turn) @ rx(1.5 * math.sin(a + 0.4)))
    p.set("Head", rz(7 * math.sin(a - 0.5)) @ rx(2 * math.sin(2 * a + 1.0)))
    p.set("Jaw", rx(1.5 + 1.5 * breath))
    eyes(
        p, (18 * math.sin(3 * a + 0.5), 10 * math.sin(2 * a)), (-16 * math.sin(2 * a + 1.8), -8 * math.sin(3 * a + 0.3))
    )
    tail(p, [-3 * turn, -2 * turn, 6 * math.sin(a + 1.0), 14 * math.sin(a + 1.6)], [0, 0, 6 * curl, 22 * curl])
    arms(p, 1.5 * breath, 0.0, -2 * math.sin(4 * a))
    return p


def run(t: float) -> K.Pose:
    """The trunk's motion while slinking (legs at rest, the game steps them): low, the spine and tail swinging side to
    side in a wave travelling back (one swing per stride), the head held steady and low, the blades tucked tight."""
    a = math.tau * t
    w = math.sin(a)
    p = K.Pose(RIG, (0, 0, -0.03 + 0.008 * math.cos(2 * a)))
    p.set("Body", ry(2.5 * w))
    p.set("Hips", rz(-9 * w))
    p.set("Spine", rz(8 * math.sin(a + 0.5)))
    p.set("Chest", rz(4 * math.sin(a + 0.9)))
    p.set("Neck", rz(-8 * math.sin(a + 0.7)) @ rx(5))
    p.set("Head", rz(-4 * math.sin(a + 1.0)) @ rx(-3))
    tail(
        p,
        [12 * math.sin(a - 0.9), 14 * math.sin(a - 1.7), 16 * math.sin(a - 2.5), 18 * math.sin(a - 3.3)],
        [3, 0, 0, 4],
    )
    eyes(p, (-8, 0), (8, 0))
    arms(p, -4, 6, 0)
    return p


def attack(t: float) -> K.Pose:
    """The strike (0.5 s): the blade-arms cock up high and the head pulls back (to 0.27), then both snap forward and
    down with a short lunge, the hit at HIT_FRAME (fully out by 0.47), held a moment, then they fold back."""
    cock = K.smooth(t / 0.27) * (1 - K.smooth((t - 0.27) / 0.2))
    strike = K.smooth((t - 0.27) / 0.2) * (1 - K.smooth((t - 0.62) / 0.38))
    p = K.Pose(RIG, (0, 0.03 * cock - 0.17 * strike, 0.02 * cock - 0.05 * strike))
    p.set("Body", rx(-3 * cock + 5 * strike))
    p.set("Hips", rx(3 * cock - 5 * strike))
    p.set("Chest", rx(-2 * cock + 3 * strike))
    p.set("Neck", rx(-10 * cock - 6 * strike))
    p.set("Head", rx(4 * cock - 4 * strike))
    p.set("Jaw", rx(8 * cock + 14 * strike))
    eyes(p, (-10 * (cock + strike), 0), (10 * (cock + strike), 0))
    tail(p, [0, 0, 0, 0], [6 * cock + 3 * strike, 2 * strike, 4 * cock, 10 * cock + 8 * strike])
    arms(p, -48 * cock - 29 * strike, -30 * cock + 35 * strike, -124 * strike, 14 * cock + 4 * strike)
    return p


def die(t: float) -> K.Pose:
    """A jolt, then it rolls onto its left side (1.0); the jaw hangs open, the blades fold in, the legs fold up."""
    jolt = K.smooth(t / 0.15) * (1 - K.smooth((t - 0.15) / 0.25))
    f = K.smooth((t - 0.1) / 0.7)
    k = K.smooth(t / 0.5)
    p = K.Pose(RIG, (DIE_SHIFT[0] * f, 0.0, 0.03 * jolt + DIE_SHIFT[1] * f))
    p.set("Body", ry(DIE_ROLL * f) @ rx(-5 * jolt))
    p.set("Neck", rx(-12 * jolt + 6 * f) @ ry(DIE_HEAD * f) @ rz(-10 * f))
    p.set("Head", rx(8 * f))
    p.set("Jaw", rx(26 * k))
    eyes(p, (25 * k, -15 * k), (-20 * k, 20 * k))
    tail(p, [-3 * f, -4 * f, -4 * f, -6 * f], [6 * f, 12 * f, 18 * f, 35 * f])
    arms(p, 25 * k, -25 * k, 15 * k, 10 * f)
    for side, s in K.SIDES:
        # The legs fold towards the belly: the upper legs swing down (the ones it lands on flat against the belly),
        # the lower legs tuck in, the feet curl.
        fold = 85 if s > 0 else 75
        p.set(f"Front{side}UpperLeg", ry(s * fold * k) @ rz(s * -20 * k))
        p.set(f"Front{side}LowerLeg", ry(s * 70 * k) @ rx(25 * k))
        p.set(f"Front{side}Foot", rx(-40 * k))
        p.set(f"Hind{side}UpperLeg", ry(s * fold * k) @ rz(s * 20 * k))
        p.set(f"Hind{side}LowerLeg", ry(s * 70 * k) @ rx(-25 * k))
        p.set(f"Hind{side}Foot", rx(40 * k))
    return p


HIT_FRAME = 7  # the blade tips' hit in the 15-frame Attack (0.23 s)
DIE_ROLL = 80  # degrees onto its left side
DIE_HEAD = 20  # the head turns over a little less than the body
DIE_SHIFT = (0.2, -0.13)  # where the Body ends up (sideways, down), so it rests on the ground

CLIPS = {  # name: (frames, pose(t) for t in 0..1)
    "Idle": (90, idle),
    "Run": (20, run),
    "Attack": (15, attack),
    "Die": (36, die),
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
    """The positions the game needs (rest pose): the blade tips, the body center, the head; and leg bends."""
    body = bpy.data.objects["Creature"].data
    names = {g.index: g.name for g in bpy.data.objects["Creature"].vertex_groups}

    def owned(bones: list) -> list:
        return [v.co for v in body.vertices if v.groups and names[max(v.groups, key=lambda g: g.weight).group] in bones]

    trunk = owned(["Hips", "Spine", "Chest"])
    print("HALF-WIDTH trunk", round(max(abs(c.x) for c in trunk), 3), "top", round(max(c.z for c in trunk), 3))
    head = owned(["Head", "Jaw", "EyeLeft", "EyeRight"])
    print("HEAD center", rnd(sum(head, Vector()) / len(head)), "snout", rnd(min(head, key=lambda c: c.y)))
    print("HEAD bone", rnd(RIG.head["Head"]), "BODY bone", rnd(RIG.head["Body"]))
    print("BLADE TIPS rest", tips(arm))
    for leg in ("FrontLeft", "HindLeft"):
        hip, knee, ankle = (RIG.head[f"{leg}{b}"] for b in ("UpperLeg", "LowerLeg", "Foot"))
        print("LEG", leg, "knee off the hip-ankle line", round(K.seg_dist(knee, hip, ankle), 3))
    gl = [v.co for v in bpy.data.objects["Glands"].data.vertices]
    print("GLANDS center", rnd(sum(gl, Vector()) / len(gl)))


def preview(arm: bpy.types.Object, tag: str) -> list:
    C.preview_scene(crystals=False, figure_location=(1.4, 1.2, 0))
    shots = []
    target = (0, 0.1, 0.32)
    K.rest_pose(arm)
    print("BOUNDS rest", bounds())
    for view, zoom in (("iso", 0.34), ("hero", 0.38), ("back", 0.4), ("iso", 1.0)):
        path = OUT / "wip" / f"{tag}_rest_{view}{zoom}.png"
        C.render(path, view=view, samples=32, size=512, target=target, zoom=zoom)
        shots.append(path)
    C.render_from(OUT / "wip" / f"{tag}_side.png", Vector((4.6, 0.12, 0.45)), (0, 0.12, 0.33), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_side.png")
    C.render_from(OUT / "wip" / f"{tag}_head.png", Vector((0.9, -2.0, 0.75)), (0, -0.7, 0.42), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_head.png")
    C.render_from(OUT / "wip" / f"{tag}_top.png", Vector((0.0, 0.12, 5.2)), (0, 0.12, 0.0), 50, 32, 512)
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
        C.render(path, view="hero", samples=24, size=512, target=target, zoom=0.38)
        shots.append(path)
    K.apply(arm, attack(HIT_FRAME / 15))
    bpy.context.view_layer.update()
    C.render_from(OUT / "wip" / f"{tag}_strike_side.png", Vector((3.6, -0.6, 0.5)), (0, -0.6, 0.3), 50, 32, 512)
    shots.append(OUT / "wip" / f"{tag}_strike_side.png")
    K.apply(arm, die(1.0))
    bpy.context.view_layer.update()
    C.render(OUT / "wip" / f"{tag}_die_iso.png", view="iso", samples=24, size=512, target=target, zoom=0.34)
    shots.append(OUT / "wip" / f"{tag}_die_iso.png")
    K.rest_pose(arm)
    C.contact_sheet(shots, OUT / "wip" / f"{tag}_sheet.png", cols=4, tile=384)
    return shots


def main() -> None:
    C.reset(ASSET)
    root = C.asset_root(ASSET)
    arm = RIG.build(root)
    build(root, arm)
    print("STATS", C.stats(), C.tris_per_object())
    measures(arm)
    if MODE == "stats":  # only the measures and the bounds of the poses, no renders
        for name, pose in (
            ("rest", K.Pose(RIG)),
            ("attack_cock", attack(4 / 15)),
            ("attack_hit", attack(HIT_FRAME / 15)),
            ("run", run(0.25)),
            ("die", die(1.0)),
        ):
            K.apply(arm, pose)
            bpy.context.view_layer.update()
            print("BOUNDS", name, bounds(), "tips", tips(arm))
            print("  LOW", lowest())
        return
    preview(arm, TAG if MODE == "wip" else "final")
    if MODE == "final":
        K.bake_clips(arm, CLIPS)
        bpy.context.scene.render.fps = FPS
        C.save_blend(OUT / "stalker_procedural.blend")
        C.export_glb(OUT / "stalker_draft.glb")


main()
