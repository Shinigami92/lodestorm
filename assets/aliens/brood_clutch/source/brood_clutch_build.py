"""Brood nest, variant egg clutch: the nest a quest's hunt goal puts at its site, hatching the hunted strain in packs
(a small boss fight). Low and broad instead of the ordinary nest's mound or the quest nest's spire: a swollen
central sac held by chitin ribs that hook over the glowing mouth on top, on a lumpy flesh base, ringed by a clutch of
big egg pods glowing violet from inside (some fused, some leaning out), each sitting in a fleshy cup and laced with
dark veins; tendrils and slime on the ground like the ordinary nest's. It must read as wide and lumpy from the
isometric camera, not as the mound or the spike. Greybox quality (finished in the art pass), built and baked through
the same pipeline as the other nests.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/brood_clutch/source/brood_clutch_build.py wip r1 [iso,hero,close,top,low,far,...]
    tools/blender.sh assets/aliens/brood_clutch/source/brood_clutch_build.py final
    tools/blender.sh assets/aliens/brood_clutch/source/brood_clutch_build.py compare

Everything it writes goes to tmp/assets/brood_clutch/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png (the view "cracks" shows all three crack stages); "final" renders iso/hero/back/far, a contact sheet
(sheet.png) and saves the procedural brood_clutch_procedural.blend that brood_clutch_bake.py turns into the game
asset; "compare" renders the baked ordinary nest (assets/aliens/nest/nest.glb) and quest nest
(assets/aliens/quest_nest/quest_nest.glb) beside this one from the game's camera (compare_iso.png) and all three from
the preview's far iso view (compare_far.png).

The shared parts (tube, ground path and crack builders, the procedural materials but the glow, slime material) come
from the ordinary nest's nest_build.py; this script only builds the clutch's own shape.

Game contract: the ordinary nest's (see nest_build.py) with a third crack stage, so the game's AlienNest script works
unchanged. Objects under the root empty "BroodClutch": Mound, Tendrils (share one texture atlas when baked), Slime,
Mouth (own glow material, the game pulses it), Glands (the egg pods and the pustules, same glow material), the empty
"HatchPoint" in the mouth, Cracks1, Cracks2 and Cracks3 (glowing fissures in the sac's swellings for the three burst
stages, more and wider each stage; Cracks3 runs over the shoulder into the mouth). Origin at the ground center. The
clutch stands inside a cylinder of r 2.5 m and is about 2.2 m tall to the rib hooks; the mouth sits on top
(MOUTH_CENTER, printed by the build). Glow color the brood nests' violet, the game's Color(0.72, 0.28, 1.0).
Triangle budget ~18k (cracks ~3k on top), TBD (playtest).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "brood_clutch"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "assets" / "aliens" / "nest" / "source"))

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import common as C
import nest_build as NB
from common import T, basis

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["iso", "hero"]

ASSET = "BroodClutch"
Z = Vector((0, 0, 1))

# --- layout (meters, Z-up, camera looks from +X/-Y) -----------------------------------------------

# Profile (radius, height) from the buried skirt over the low base the eggs sit on, in at the sac's neck, out over
# its swollen belly, over the shoulder to the lip and down into the crater; the end hides under the Mouth bowl.
# Smoothed and resampled by arc length into prof(t).
PROFILE = [
    (2.3, -0.03),
    (2.22, 0.05),
    (2.05, 0.15),
    (1.8, 0.25),
    (1.5, 0.34),
    (1.2, 0.42),
    (0.98, 0.52),
    (0.95, 0.66),
    (1.06, 0.88),
    (1.16, 1.15),
    (1.14, 1.42),
    (1.0, 1.68),
    (0.8, 1.88),
    (0.62, 2.0),
    (0.55, 2.04),
    (0.49, 2.02),
    (0.45, 1.96),
    (0.41, 1.9),
    (0.37, 1.85),
]
BODY_SEG, BODY_RINGS = 40, 36
MOUTH_R = 0.42

# Chitin ribs holding the sac: N_RIBS bands from the neck up over the belly, hooking over the mouth's lip; the
# sac swells between them (grooves under the ribs). They turn a little as they rise (RIB_TWIST rad per m).
N_RIBS = 6
RIB0 = math.radians(5)
RIB_TWIST = 0.22
GROOVE = 0.13  # rad: half width of a rib's groove

# Egg pods on the base: (angle deg, distance from the center m, radius m, lean out deg). Pairs close together fuse.
EGGS = [
    (26, 1.62, 0.5, 14),
    (44, 1.86, 0.32, 34),
    (82, 1.64, 0.52, 10),
    (120, 1.7, 0.4, 24),
    (136, 1.5, 0.34, 6),
    (176, 1.66, 0.5, 16),
    (213, 1.82, 0.34, 34),
    (229, 1.56, 0.44, 10),
    (271, 1.66, 0.54, 12),
    (307, 1.62, 0.42, 20),
    (321, 1.86, 0.3, 38),
    (357, 1.62, 0.38, 24),
]
EGG_LEN = 1.4  # half length / radius: egg-shaped, not round

# Main tendrils between the egg groups: (angle deg, ground length m, radius at the start). They start at the sac's
# neck, run down the base between the eggs and out over the ground; the tip reaches GROUND_START + ground length.
TENDRILS = [
    (8, 2.3, 0.17),
    (60, 1.7, 0.15),
    (103, 2.4, 0.17),
    (155, 1.8, 0.16),
    (196, 2.5, 0.18),
    (250, 1.9, 0.16),
    (290, 2.4, 0.17),
    (338, 1.8, 0.15),
]
GROUND_START = 2.3
SLIME_R = 3.9  # base radius of the slime layer between the tendril fingers
SLIME_MAX = 5.2

# --- profile and surface ------------------------------------------------------------------------------

_PTS = NB._chaikin(PROFILE)
_ARC = [0.0]
for _a, _b in itertools.pairwise(_PTS):
    _ARC.append(_ARC[-1] + math.dist(_a, _b))
PROF_LEN = _ARC[-1]


def prof(t: float) -> tuple[float, float]:
    s = max(0.0, min(1.0, t)) * PROF_LEN
    for i in range(1, len(_ARC)):
        if _ARC[i] >= s:
            f = (s - _ARC[i - 1]) / max(_ARC[i] - _ARC[i - 1], 1e-9)
            a, b = _PTS[i - 1], _PTS[i]
            return a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
    return _PTS[-1]


T_CREST = max((i / 800 for i in range(801)), key=lambda t: prof(t)[1])
CREST_Z = prof(T_CREST)[1]
T_NECK = min((i / 800 for i in range(int(T_CREST * 800)) if 0.3 < prof(i / 800)[1] < 1.0), key=lambda t: prof(t)[0])


def m(meters: float) -> float:
    """A length along the profile in t."""
    return meters / PROF_LEN


def t_at_z(z: float) -> float:
    """Outer side: the t where the profile reaches height z."""
    lo, hi = 0.0, T_CREST
    for _ in range(40):
        mid = (lo + hi) / 2
        if prof(mid)[1] < z:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def t_on_base(r: float) -> float:
    """On the base (skirt to neck): the t where the profile comes in to radius r."""
    lo, hi = 0.0, T_NECK
    for _ in range(40):
        mid = (lo + hi) / 2
        if prof(mid)[0] > r:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def t_in_crater(r: float) -> float:
    """Crater side: the t where the profile comes in to radius r."""
    return next(i / 800 for i in range(int(T_CREST * 800), 801) if prof(i / 800)[0] < r)


MOUTH_Z1 = prof(t_in_crater(MOUTH_R))[1] - 0.005  # bowl edge, tucked under the crater wall
MOUTH_Z0 = MOUTH_Z1 - 0.14  # bowl center


def rib_angle(k: float, z: float) -> float:
    """Angle of rib k (fractions: between the ribs) at height z."""
    return RIB0 + k * math.tau / N_RIBS + RIB_TWIST * (z - 0.6)


def _wrap(a: float) -> float:
    return math.atan2(math.sin(a), math.cos(a))


def groove(th: float, z: float) -> float:
    """1 under a rib, 0 on the swellings between them."""
    d = min(abs(_wrap(th - rib_angle(k, z))) for k in range(N_RIBS))
    return math.exp(-((d / GROOVE) ** 2))


def P(th: float, t: float) -> Vector:
    """Point on the body at angle th (rad) and profile parameter t."""
    r0, z0 = prof(t)
    s = t * PROF_LEN
    crest_s = T_CREST * PROF_LEN
    base = 1.0 - NB._smoothstep(0.4, 0.62, z0)  # lumpy base, fading into the sac
    outer = NB._smoothstep(0.0, 0.3, s) * base
    lobe = 1.0 + outer * (0.06 * math.sin(4 * th + 1.0) + 0.035 * math.sin(7 * th + 0.3))
    # The sac: swollen between the ribs, pulled in under them, a little lopsided.
    sac = NB._smoothstep(0.55, 0.85, z0) * (1.0 - NB._smoothstep(crest_s - 0.3, crest_s - 0.05, s))
    lobe *= 1.0 + sac * (0.045 * math.sin(th + 0.8) + 0.03 - 0.13 * groove(th, z0))
    z = z0 + 0.035 * math.sin(6 * th + 0.4) * math.exp(-(((s - crest_s) / 0.1) ** 2))  # lobed lip
    p = Vector((math.cos(th) * r0 * lobe, math.sin(th) * r0 * lobe, z))
    # Lumps along the profile normal (none at the ground ring and in the crater, where the mouth fits).
    dr, dz = (a - b for a, b in zip(prof(t + 0.002), prof(t - 0.002)))
    n2 = Vector((dz, -dr)).normalized()
    w = NB._smoothstep(0.05, 0.25, s) * (1.0 - NB._smoothstep(crest_s + 0.03, crest_s + 0.2, s))
    d = w * (0.07 * noise.noise(p * 1.2) + 0.03 * noise.noise(p * 3.3 + Vector((5, 1, 2))))
    return p + Vector((math.cos(th) * n2.x, math.sin(th) * n2.x, n2.y)) * d


def N(th: float, t: float) -> Vector:
    """Surface normal: out of the body (outward on the sides, up and inward in the crater)."""
    e = 0.002
    a = P(th + e, t) - P(th - e, t)
    b = P(th, t + e) - P(th, t - e)
    return a.cross(b).normalized()


def radial(th: float) -> Vector:
    return Vector((math.cos(th), math.sin(th), 0.0))


# --- materials --------------------------------------------------------------------------------------

GLOW_COLOR = (0.477, 0.0648, 1.0)  # linear for the brood nests' violet Color(0.72, 0.28, 1.0)


def mat_glow() -> bpy.types.Material:
    """Violet glow of the mouth, egg pods, glands and cracks (the game pulses it); the ordinary nest's glow in
    violet."""
    mat, nt, bsdf = C._new_material("BroodClutch_Glow")
    co = NB._coord(nt)
    churn = NB._noise(nt, co, 5.0, 4.0, 0.6, dist=1.5)
    col = C._mix_color(nt, churn.outputs["Fac"], (0.09, 0.006, 0.32), (0.42, 0.05, 1.0))
    glow = nt.nodes.new("ShaderNodeAttribute")  # falloff (1 = full), see build_mouth and egg_pod
    glow.attribute_name = "glow"
    strength = C._math(nt, "MULTIPLY", C._mix_float(nt, churn.outputs["Fac"], 1.0, 3.5), glow.outputs["Fac"])
    nt.links.new(strength, bsdf.inputs["Emission Strength"])
    col = C._mix_color(nt, glow.outputs["Fac"], (0.03, 0.004, 0.08), col)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(col, bsdf.inputs["Emission Color"])
    bsdf.inputs["Roughness"].default_value = 0.15
    return mat


def make_materials() -> None:
    global FLESH, CHITIN, RESIN, SAC, GLOW
    FLESH, CHITIN, RESIN, SAC = NB.mat_flesh(), NB.mat_chitin(), NB.mat_resin(), NB.mat_sac()
    NB.SLIME = NB.mat_slime()
    GLOW = mat_glow()


M_FLESH, M_CHITIN, M_RESIN, M_SAC = NB.M_FLESH, NB.M_CHITIN, NB.M_RESIN, NB.M_SAC


# --- parts ------------------------------------------------------------------------------------------


def build_body(part: NB.Part) -> None:
    rows, ts = [], []
    for j in range(BODY_RINGS):
        t = j / (BODY_RINGS - 1)
        ts.append(t)
        rows.append([part.bm.verts.new(P(i / BODY_SEG * math.tau, t)) for i in range(BODY_SEG)])
    for j, (a, b) in enumerate(itertools.pairwise(rows)):
        mi = M_RESIN if ts[j] > T_CREST + m(0.06) else M_FLESH
        faces = part.faces([a, b], mi, closed_u=True)
        c = faces[0].calc_center_median()
        NB.orient(part, faces, (c - Vector((0, 0, c.z - 0.3))) if ts[j] < T_CREST else Z, 0)


def body_sheet() -> NB.Sheet:
    """The body as build_body lays it out: a = th in segments (wraps), b = t in rings."""
    grid = [[P(i / BODY_SEG * math.tau, j / (BODY_RINGS - 1)) for i in range(BODY_SEG)] for j in range(BODY_RINGS)]
    return NB.Sheet(grid, wrap=True)


def build_ribs(part: NB.Part, rnd: random.Random) -> None:
    """Chitin ribs in the sac's grooves, from the neck up over the belly; over the lip they rise free and hook
    in over the mouth like claws. Short teeth on the lip between them."""
    for k in range(N_RIBS):
        pts, refs = [], []
        t0, t1 = t_at_z(0.6), T_CREST - m(0.06)
        n = 16
        for i in range(n):
            t = t0 + (t1 - t0) * i / (n - 1)
            th = rib_angle(k, prof(t)[1])
            nn = N(th, t)
            pts.append(P(th, t) + nn * 0.035)
            refs.append(nn)
        top = pts[-1]
        rd = radial(rib_angle(k, CREST_Z))
        h = rnd.uniform(0.14, 0.2)
        hook = NB.catmull(
            [top, top + Z * h * 0.7 + rd * 0.03, top + Z * h - rd * 0.14, top + Z * h * 0.6 - rd * 0.28], 6
        )
        pts += hook[1:]
        refs += [rd.copy() for _ in hook[1:]]
        r0 = rnd.uniform(0.085, 0.1)
        nt = len(pts)
        radii = [r0 * (0.75 + 0.25 * math.sin(math.pi * min(i / (n - 1), 1.0))) for i in range(n)]
        radii += [r0 * 0.75 * (1 - i / (nt - n)) ** 0.8 for i in range(1, nt - n + 1)]
        radii[0] = 0.0
        radii[-1] = 0.0
        NB.tube(part, pts, radii, refs, 7, flat=0.55, mi_fn=lambda f: M_CHITIN, kind=1.0)
        # A tooth on the lip between this rib and the next.
        th = rib_angle(k + 0.5, CREST_Z) + rnd.uniform(-0.1, 0.1)
        t = T_CREST - m(0.02)
        b, nn, rd = P(th, t), N(th, t), radial(th)
        h = rnd.uniform(0.1, 0.16)
        ctrl = [b - nn * 0.05, b + Z * h * 0.5 + rd * 0.05, b + Z * h - rd * 0.04]
        pts = NB.catmull(ctrl, 6)
        r1 = rnd.uniform(0.045, 0.06)
        NB.tube(part, pts, [r1 * (1 - i / 5) ** 0.9 for i in range(6)], [rd] * 6, 5, flat=0.7, mi_fn=lambda f: M_CHITIN)


def egg_pod(
    mound: NB.Part, glands: NB.Part, deg: float, dist: float, r: float, lean: float, rnd: random.Random
) -> None:
    """An egg pod on the base: the egg (in Glands, glowing violet from inside) in a fleshy cup whose lobed rim
    reaches up its sides, dark veins running from the rim up over it."""
    th = math.radians(deg)
    t = t_on_base(dist)
    p = P(th, t)
    side = Vector((-math.sin(th), math.cos(th), 0.0))
    ax = (Z * math.cos(math.radians(lean)) + radial(th) * math.sin(math.radians(lean))).normalized()
    ax = (Matrix.Rotation(rnd.uniform(-0.15, 0.15), 3, radial(th)) @ ax).normalized()
    length = r * EGG_LEN
    c = p + ax * (length * 0.72) - Z * 0.03
    rot = basis(ax, side)
    seg, rings = 12, 9

    def shell(u: float, a: float, off: float) -> Vector:
        """Egg surface at u (-1 bottom .. 1 top along the axis) and angle a, pushed out by off."""
        rad = r * math.sqrt(max(0.0, 1 - u * u)) * (1 - 0.12 * u) * (1 + 0.04 * math.sin(3 * a + deg))
        return c + rot @ Vector((math.cos(a) * (rad + off), math.sin(a) * (rad + off), u * length + off * u))

    # The egg: rows of rings between the poles.
    bm = glands.bm
    bottom = bm.verts.new(c - ax * length)
    top = bm.verts.new(c + ax * length)
    rows = []
    for j in range(1, rings):
        u = -math.cos(math.pi * j / rings)
        row = []
        for i in range(seg):
            v = bm.verts.new(shell(u, i / seg * math.tau, 0.0))
            v[glands.glow] = 0.55 + 0.45 * (u + 1) / 2  # dimmer low in the cup
            row.append(v)
        rows.append(row)
    bottom[glands.glow], top[glands.glow] = 0.5, 1.0
    faces = glands.faces(rows, 0, closed_u=True)
    for i in range(seg):
        i1 = (i + 1) % seg
        faces.append(bm.faces.new((bottom, rows[0][i1], rows[0][i])))
        faces.append(bm.faces.new((top, rows[-1][i], rows[-1][i1])))
    for f in faces:
        f.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    # The cup: from below the ground up the egg's sides, its rim in lobes (higher at the lobes' middles).
    lobes = rnd.choice((4, 5))
    ph = rnd.uniform(0, math.tau)
    us = [-0.98, -0.8, -0.6, -0.4, -0.2, 0.0]
    cup = []
    for j, f in enumerate(us):
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            rim = -0.22 + 0.55 * max(0.0, math.cos(lobes * a / 2 + ph)) ** 1.5 + 0.05 * math.sin(7 * a)
            u = -0.98 + (rim + 0.98) * (j / (len(us) - 1))
            off = 0.035 * (1 - j / (len(us) - 1)) + 0.008
            row.append(mound.bm.verts.new(shell(u, a, off)))
        cup.append(row)
    faces = mound.faces(cup, M_FLESH, closed_u=True)
    bmesh.ops.recalc_face_normals(mound.bm, faces=faces)
    NB.orient(mound, faces, (faces[seg * 3].calc_center_median() - c), seg * 3)
    # Veins from the rim up over the egg, meandering, thinning to their ends.
    for k in range(rnd.choice((3, 4))):
        a0 = ph + k * math.tau / 4 + rnd.uniform(-0.3, 0.3)
        u1 = rnd.uniform(0.55, 0.85)
        pts, refs = [], []
        for i in range(7):
            u = -0.1 + (u1 + 0.1) * i / 6
            a = a0 + 0.25 * math.sin(i * 1.3 + k)
            q = shell(u, a, 0.012)
            pts.append(q)
            refs.append((q - c - ax * (ax.dot(q - c))).normalized())
        rv = rnd.uniform(0.035, 0.045)
        radii = [rv * (1 - i / 6) ** 0.7 for i in range(7)]
        NB.tube(mound, pts, radii, refs, 4, flat=0.55, mi_fn=lambda f: M_FLESH)


def build_eggs(mound: NB.Part, glands: NB.Part, rnd: random.Random) -> None:
    for deg, dist, r, lean in EGGS:
        egg_pod(mound, glands, deg, dist, r, lean, rnd)


def build_tendrils(part: NB.Part, glands: list, rnd: random.Random) -> list:
    """Main tendrils from the sac's neck down the base between the eggs and out over the ground, with side branches
    (the ordinary nest's); returns their tip positions (slime fingers follow them)."""
    tips = []
    for deg, glen, r0 in TENDRILS:
        th0 = math.radians(deg)
        pts, refs = [], []
        t = t_at_z(rnd.uniform(0.62, 0.75))
        dt = 0.11 / PROF_LEN
        ph = rnd.uniform(0, 6.28)
        while t > 0.0:
            th = th0 + 0.04 * math.sin(t * 20 + ph)
            n = N(th, t)
            pts.append(P(th, t) + n * (r0 * 0.5))
            refs.append(n)
            t -= dt
        ground = NB.ground_path(th0, GROUND_START, glen, rnd)
        pts += ground[1:]
        refs += [Z.copy() for _ in ground[1:]]
        n_mound = len(pts) - len(ground) + 1
        NB.smooth_path(pts, refs, 2)
        arcs = [0.0]
        for a, b in itertools.pairwise(pts):
            arcs.append(arcs[-1] + (b - a).length)
        radii = [NB.taper(s / arcs[-1], r0, s) for s in arcs]
        radii[-1] = 0.0
        back = (pts[0] - pts[1]).normalized()
        pts[:0] = [pts[0] + back * r0 * 0.75, pts[0] + back * r0 * 0.45]
        refs[:0] = [refs[0], refs[0]]
        radii[:0] = [0.0, r0 * 0.75]
        n_mound += 2
        for i in range(n_mound, len(pts)):
            pts[i].z = radii[i] * 0.42 + 0.006
        pts[-1].z = 0.008
        NB.tube(part, pts, radii, refs, 7, flat=0.66, mi_fn=lambda f: M_CHITIN if f > 0.9 else M_FLESH)
        tips.append(pts[-1].copy())
        gi = n_mound - 3
        side = (pts[gi + 1] - pts[gi - 1]).normalized().cross(refs[gi]).normalized()
        glands.append((pts[gi] + side * radii[gi] * 0.85 + refs[gi] * 0.02, rnd.uniform(0.055, 0.075)))
        ng = len(pts) - n_mound
        picks = [n_mound + int(ng * rnd.uniform(0.3, 0.45)), n_mound + int(ng * rnd.uniform(0.62, 0.72))]
        if glen > 2.0:
            picks.append(n_mound + int(ng * rnd.uniform(0.5, 0.58)))
        for b, i in enumerate(picks):
            tan = (pts[i + 1] - pts[i - 1]).normalized()
            sgn = 1 if (b + deg) % 2 == 0 else -1
            d = Matrix.Rotation(sgn * rnd.uniform(0.6, 0.95), 3, "Z") @ tan
            d.z = 0
            d.normalize()
            blen = rnd.uniform(0.45, 0.95) if b != 1 else rnd.uniform(0.35, 0.6)
            rb = radii[i] * 0.6
            bp = [pts[i] + d * (k * 0.12) for k in range(int(blen / 0.12) + 1)]
            bend = Matrix.Rotation(-sgn * 1.3, 3, "Z") @ d
            bp = [p + bend * ((k * 0.12) ** 2) * 0.45 for k, p in enumerate(bp)]
            br = [rb * (1 - k / (len(bp) - 1)) ** 0.6 for k in range(len(bp))]
            br[-1] = 0.0
            for k in range(len(bp)):
                bp[k].z = br[k] * 0.42 + 0.006
            NB.tube(part, bp, br, [Z.copy() for _ in bp], 5, flat=0.66, mi_fn=lambda f: M_FLESH)
    # Thin roots from the skirt between the main tendrils.
    angs = sorted(math.radians(a) for a, _, _ in TENDRILS)
    for k, a in enumerate(angs):
        b = angs[(k + 1) % len(angs)] + (math.tau if k == len(angs) - 1 else 0)
        th = (a + b) / 2 + rnd.uniform(-0.1, 0.1)
        g = NB.ground_path(th, GROUND_START - 0.05, rnd.uniform(0.9, 1.5), rnd, 0.12)
        rr = [0.065 * (1 - i / (len(g) - 1)) ** 0.8 for i in range(len(g))]
        rr[-1] = 0.0
        for i, p in enumerate(g):
            p.z = rr[i] * 0.42 + 0.006
        g = [P(th, t_at_z(0.1))] + g
        rr = [0.07] + rr
        NB.tube(part, g, rr, [Z.copy() for _ in g], 5, flat=0.72)
    return tips


def build_glands(glands: NB.Part, spots: list, rnd: random.Random) -> None:
    """Pustules on the tendrils and a few on the sac's swellings."""
    for k in range(4):
        th = rib_angle(k * 1.5 + 0.5, 1.0) + rnd.uniform(-0.15, 0.15)
        t = t_at_z(rnd.uniform(0.75, 1.5))
        spots.append((P(th, t) + N(th, t) * 0.03, rnd.uniform(0.05, 0.07)))
    for c, r in spots:
        for v in bmesh.ops.create_uvsphere(glands.bm, u_segments=8, v_segments=5, radius=r, matrix=T(c))["verts"]:
            v[glands.glow] = 1.0
            for f in v.link_faces:
                f.smooth = True


def mouth_center() -> Vector:
    return Vector((0, 0, MOUTH_Z0))


def build_mouth(nest) -> None:
    """Glowing bowl filling the crater on top: radial folds like a sphincter, rising to the edge under the wall."""
    part = NB.Part("Mouth", [GLOW])
    seg, rings = 32, 6
    c = mouth_center()
    center = part.bm.verts.new(c - Vector((0, 0, 0.04)))
    center[part.glow] = 1.0
    rows = []
    for j in range(1, rings + 1):
        f = j / rings
        r = MOUTH_R * f
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            fold = 0.03 * math.sin(9 * a + 0.5) * math.sin(math.pi * f) ** 1.5
            z = MOUTH_Z0 + (MOUTH_Z1 - MOUTH_Z0) * f**2 + fold - 0.04 * (1 - f) ** 3
            v = part.bm.verts.new(Vector((math.cos(a) * r, math.sin(a) * r, z)))
            v[part.glow] = 1.0 - 0.6 * f**2 + 0.15 * fold / 0.03 * f
            row.append(v)
        rows.append(row)
    faces = [part.bm.faces.new((center, rows[0][i], rows[0][(i + 1) % seg])) for i in range(seg)]
    faces += part.faces(rows, 0, closed_u=True)
    for f in faces:
        f.smooth = True
    NB.orient(part, faces, Z, 0)
    NB.orient(part, faces[seg:], Z, 0)
    part.finish(nest)


def build_slime(nest, tips: list) -> None:
    """Flat glossy layer on the ground, fingers reaching out along the tendrils, a rounded lip at the edge (the
    ordinary nest's, wider)."""
    part = NB.Part("Slime", [NB.SLIME])
    seg = 112
    fr = [0.0, 0.3, 0.55, 0.75, 0.88, 0.95, 1.0]
    r_in = 2.0
    tip_ang = [(math.atan2(p.y, p.x), p.xy.length) for p in tips]
    rows = []
    for f in fr:
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            edge = (
                SLIME_R
                + 0.35 * noise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, 0.5)))
                + 0.09 * math.sin(11 * a)
            )
            for ta, reach in tip_ang:
                d = math.atan2(math.sin(a - ta), math.cos(a - ta))
                edge += max(0.0, reach - 0.05 - edge) * math.exp(-((d / 0.2) ** 2))
            edge = min(edge, SLIME_MAX)
            r = r_in + (edge - r_in) * f
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
            p.z = 0.004 + 0.028 * (1 - f**4) + 0.006 * noise.noise(p * 2.0) * (1 - f)
            row.append(part.bm.verts.new(p))
        rows.append(row)
    faces = part.faces(rows, 0, closed_u=True)
    NB.orient(part, faces, Z, 0)
    part.finish(nest)


# --- cracks (the nest bursting open: the game shows Cracks1, then Cracks2, then Cracks3 as well) ----------------


def swell_crack(part: NB.Part, body: NB.Sheet, k: int, z0: float, z1, width: float, branches: int, rnd) -> None:
    """A fissure up the swelling between ribs k and k + 1 from height z0 to z1 (None: over the lip into the mouth),
    wandering across it."""

    def at(z: float) -> float:
        return (rib_angle(k + 0.5, z) + rnd.uniform(-0.12, 0.12)) % math.tau / math.tau * BODY_SEG

    start = (at(z0), t_at_z(z0) * (BODY_RINGS - 1))
    if z1 is None:
        stop = (at(CREST_Z), t_in_crater(MOUTH_R + 0.02) * (BODY_RINGS - 1))
        if stop[0] - start[0] > BODY_SEG / 2:
            stop = (stop[0] - BODY_SEG, stop[1])
        elif start[0] - stop[0] > BODY_SEG / 2:
            stop = (stop[0] + BODY_SEG, stop[1])
        path = NB.crack_walk(body, start, stop, rnd)
        widths = NB.crack_widths(path, body, width, rnd, taper=(0.15, 0.12), w_end=0.3)
    else:
        stop = (at(z1), t_at_z(z1) * (BODY_RINGS - 1))
        if stop[0] - start[0] > BODY_SEG / 2:
            stop = (stop[0] - BODY_SEG, stop[1])
        elif start[0] - stop[0] > BODY_SEG / 2:
            stop = (stop[0] + BODY_SEG, stop[1])
        path = NB.crack_walk(body, start, stop, rnd)
        widths = NB.crack_widths(path, body, width, rnd)
    NB.ribbon(part, body, path, widths, 0.006)
    NB.add_branches(part, body, path, widths, rnd, branches)


def build_cracks(nest) -> None:
    """Glowing fissures in the sac's swellings: Cracks1 short ones on every other swelling (the camera side among
    them), Cracks2 longer ones on the others and a second on the first ones, Cracks3 wide ones up every swelling
    over the shoulder into the mouth."""
    rnd = random.Random(29)
    body = body_sheet()
    stages = [NB.Part(f"Cracks{i}", [GLOW]) for i in (1, 2, 3)]
    for k in range(N_RIBS):
        if k % 2 == 0:
            swell_crack(
                stages[0], body, k, rnd.uniform(0.8, 0.9), rnd.uniform(1.3, 1.45), rnd.uniform(0.07, 0.08), 2, rnd
            )
            swell_crack(
                stages[1], body, k, rnd.uniform(0.62, 0.7), rnd.uniform(1.0, 1.1), rnd.uniform(0.05, 0.06), 1, rnd
            )
        else:
            swell_crack(
                stages[1], body, k, rnd.uniform(0.7, 0.8), rnd.uniform(1.5, 1.65), rnd.uniform(0.075, 0.085), 3, rnd
            )
        swell_crack(stages[2], body, k, rnd.uniform(1.15, 1.35), None, rnd.uniform(0.1, 0.12), 3, rnd)
    for part in stages:
        part.finish(nest)


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    rnd = random.Random(23)
    nest = C.asset_root(ASSET)
    mound = NB.Part("Mound", [FLESH, CHITIN, RESIN, SAC])
    glands = NB.Part("Glands", [GLOW])
    build_body(mound)
    build_ribs(mound, rnd)
    build_eggs(mound, glands, rnd)
    tendrils = NB.Part("Tendrils", [FLESH, CHITIN])
    spots: list = []
    tips = build_tendrils(tendrils, spots, rnd)
    build_glands(glands, spots, rnd)
    mound.finish(nest)
    tendrils.finish(nest)
    glands.finish(nest)
    build_mouth(nest)
    build_slime(nest, tips)
    C.empty("HatchPoint", tuple(mouth_center() + Vector((0, 0, 0.02))), nest)
    build_cracks(nest)
    return nest


def report() -> None:
    print("STATS per object", C.tris_per_object())
    reach = 0.0
    top = 0.0
    for name in ("Mound", "Glands"):
        verts = bpy.data.objects[name].data.vertices
        reach = max(reach, max((v.co.xy.length for v in verts if v.co.z > 0.1), default=0.0))
        top = max(top, max(v.co.z for v in verts))
    c = mouth_center()
    print(f"STATS body radius above 0.1 m: {reach:.2f} (fits r 2.5), height {top:.2f}, crest {CREST_Z:.2f}")
    print(f"STATS mouth center (Blender Z-up) {tuple(round(x, 3) for x in c)}, edge z {MOUTH_Z1:.3f}")
    print(f"STATS mouth center (Godot Y-up) Vector3({c.x:.3f}, {c.z:.3f}, {-c.y:.3f})")


CLOSE_VIEWS = {
    "close": ((3.6, -4.3, 4.0), (0, 0, 1.0), 35),
    "top": ((0.01, -0.01, 22.0), (0, 0, 0), 40),
    "low": ((4.6, -5.6, 1.0), (0, 0, 0.9), 30),
}


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    if view in CLOSE_VIEWS:
        loc, target, lens = CLOSE_VIEWS[view]
        C.render_from(path, loc, target, lens, samples, size)
    elif view == "far":  # game distance (~18 m), framed like the other nests' far views
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.35)
    elif view == "iso":
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.6), zoom=1.3)
    else:
        C.render(path, view=view, samples=samples, size=size, target=(0, 0, 0.8), zoom=1.55)


def render_game_view(path: pathlib.Path, target: Vector, samples: int, width: int, height: int, lens: float) -> None:
    """The game's camera: perspective, 40 m away along the +X/-Y diagonal, 35 degrees down (a long lens crops it)."""
    C._render_settings(samples, width)
    bpy.context.scene.render.resolution_y = height
    cam = C._camera("custom")
    cam.data.lens = lens
    down = math.radians(35)
    cam.location = target + Vector((math.cos(down) / math.sqrt(2), -math.cos(down) / math.sqrt(2), math.sin(down))) * 40
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    C._write_render(path)


def set_hidden(root: bpy.types.Object, hidden: bool) -> None:
    for o in [root, *root.children_recursive]:
        o.hide_render = hidden or o.name.startswith("Cracks")


def import_root(path: pathlib.Path) -> bpy.types.Object:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return next(o for o in set(bpy.data.objects) - before if o.parent is None and o.type == "EMPTY")


def compare(clutch: bpy.types.Object) -> None:
    """The baked ordinary nest (left) and quest nest (right) beside this one, all unhurt (no cracks): from the game
    camera, and each from the far preview view."""
    nests = ROOT / "assets" / "aliens"
    nest = import_root(nests / "nest" / "nest.glb")
    quest = import_root(nests / "quest_nest" / "quest_nest.glb")
    roots = {"nest": nest, "clutch": clutch, "quest": quest}
    for root in roots.values():
        set_hidden(root, False)
    side = Vector((1, 1, 0)).normalized()  # screen right from the game camera
    nest.location, clutch.location, quest.location = side * -9.0, side * 0.0, side * 9.0  # the clutch in the light
    render_game_view(OUT / "compare_iso.png", Vector((0, 0, 1.0)), 64, 1920, 800, 50)
    paths = []
    for name, root in roots.items():
        root.location = Vector()
        for other in roots.values():
            set_hidden(other, other is not root)
        p = OUT / f"compare_{name}_far.png"
        render_view(p, "far", 64, 768)
        paths.append(p)
    C.contact_sheet(paths, OUT / "compare_far.png", cols=3)


def show_cracks() -> None:
    for o in bpy.data.objects:
        if o.name.startswith("Cracks"):
            o.hide_render = False


def main() -> None:
    C.reset(ASSET)
    make_materials()
    clutch = build()
    report()
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(4.2, 2.4, 0.0) if MODE != "compare" else (3.3, 3.3, 0.0))
    NB.clear_preview_rubble(99.0 if MODE == "compare" else 5.6)
    if MODE == "final":
        paths = []
        for view in ("iso", "hero", "back", "far"):
            p = OUT / f"render_{view}.png"
            render_view(p, view, 96, 1024)
            paths.append(p)
        C.contact_sheet(paths, OUT / "sheet.png", cols=2)
        C.save_blend(OUT / "brood_clutch_procedural.blend")
    elif MODE == "compare":
        compare(clutch)
    else:
        for o in bpy.data.objects:
            if o.name.startswith("Cracks"):
                o.hide_render = True
        for view in VIEWS:
            if view == "cracks":
                show_cracks()
                render_view(OUT / "wip" / f"{TAG}_cracks.png", "close", 24, 512)
                for o in bpy.data.objects:
                    if o.name.startswith("Cracks"):
                        o.hide_render = True
            elif view != "none":
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, 24, 512)


if __name__ == "__main__":
    main()
