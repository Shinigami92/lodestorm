"""Brood pit: the brood nest a quest's hunt goal puts at its site ("burrow mouth"). A raised crater ring instead of
the ordinary nest's mound or the quest nest's spire: overlapping chitin plates and flesh around a deep, wide pit, its
throat glowing violet from far down, a few short, thick chitin hooks curling in over the rim, glowing veins running
down the pit's walls into the throat, tendrils and slime on the ground like the ordinary nest's. From the isometric
camera it must read as a hollow ring with a glowing hole, not as the mound and not as the spire. Greybox quality
(finished in the art pass), built and baked through the same pipeline as the other nests.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/brood_pit/source/brood_pit_build.py wip r1 [iso,hero,game,close,top,low,far,...]
    tools/blender.sh assets/aliens/brood_pit/source/brood_pit_build.py final
    tools/blender.sh assets/aliens/brood_pit/source/brood_pit_build.py compare

Everything it writes goes to tmp/assets/brood_pit/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png ("game" is the game's camera, "cracks" the iso view with all crack stages shown); "final" renders
iso/hero/back/far, a contact sheet (sheet.png) and saves the procedural brood_pit_procedural.blend that
brood_pit_bake.py turns into the game asset; "compare" renders the baked ordinary nest
(assets/aliens/nest/nest.glb) and the baked quest nest (assets/aliens/quest_nest/quest_nest.glb) beside this one
from the game's camera (compare_iso.png) and all three from the preview's far iso view (compare_far.png).

The shared parts (tube and crack builders, the procedural materials but the glow, slime) come from the ordinary
nest's nest_build.py; this script only builds the pit's own shape.

Game contract: the same as the other nests' (see nest_build.py and quest_nest_build.py), so the game's AlienNest
script works unchanged. Objects under the root empty "BroodPit": Mound (the ring and the pit's walls), Tendrils
(share one texture atlas with Mound when baked), Slime, Mouth (the glowing throat deep in the pit; own glow
material, the game pulses it and scales it around its center for a burst warning), Glands (pustules and the veins
down the pit's walls, same glow material), the empty "HatchPoint" in the middle of the pit's rim, Cracks1, Cracks2
and Cracks3 (glowing fissures over the ring's plates for the three burst stages, more and wider each stage;
Cracks3 also runs down the pit's walls into the throat). Origin at the ground center. The ring stands inside a
cylinder of r 2.4 m and is about 1.2 m tall (the hooks a bit more); the pit's rim is about 2.4 m across and the
mouth sits deep in it (MOUTH_CENTER, printed by the build with the radii for the collision). Nothing goes below
the ground (the terrain would cover it). Glow color the brood nests' violet, the game's Color(0.72, 0.28, 1.0).
Triangle budget ~16k (cracks ~3k on top), TBD (playtest).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "brood_pit"
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

ASSET = "BroodPit"
Z = Vector((0, 0, 1))

# --- layout (meters, Z-up, camera looks from +X/-Y) -----------------------------------------------

# Profile (radius, height) from the buried skirt up the ring's outer wall, over the crest and down the pit's
# funnel into the throat, which ends in a short shaft under the Mouth bowl. Smoothed and resampled by arc length
# into prof(t).
PROFILE = [
    (2.36, -0.04),
    (2.28, 0.03),
    (2.16, 0.14),
    (2.02, 0.32),
    (1.88, 0.56),
    (1.74, 0.8),
    (1.6, 0.98),
    (1.46, 1.1),
    (1.33, 1.16),
    (1.22, 1.13),
    (1.15, 1.02),
    (1.1, 0.86),
    (1.02, 0.7),
    (0.9, 0.56),
    (0.76, 0.46),
    (0.62, 0.39),
    (0.52, 0.35),
    (0.46, 0.3),
    (0.44, 0.2),
    (0.44, 0.1),
]
BODY_SEG, BODY_RINGS = 52, 40
MOUTH_R = 0.5

# Main tendrils: (angle deg, ground length m, radius at the start). They start under the middle plates, run down
# the ring's outer wall and out over the ground; the tip reaches 2.3 + ground length from the center (<= ~4.4 m).
TENDRILS = [
    (12, 1.9, 0.18),
    (55, 1.4, 0.16),
    (101, 1.85, 0.18),
    (147, 1.3, 0.16),
    (192, 2.05, 0.19),
    (238, 1.5, 0.17),
    (284, 1.95, 0.18),
    (328, 1.35, 0.16),
]
GROUND_START = 2.3
SAC_GAPS = (6, 2)  # gaps (after tendril k) with egg sacs instead of the low plate: front right (camera side), back
HOOKS = (0, 1, 3, 4, 6)  # the tendrils whose angle gets a hook on the crest

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
CREST_S = T_CREST * PROF_LEN


def m(meters: float) -> float:
    """A length along the profile in t."""
    return meters / PROF_LEN


def t_at_z(z: float) -> float:
    """Outer wall: the t where the profile reaches height z."""
    lo, hi = 0.0, T_CREST
    for _ in range(40):
        mid = (lo + hi) / 2
        if prof(mid)[1] < z:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def t_pit_z(z: float) -> float:
    """Pit wall: the t where the profile comes down to height z."""
    return next(i / 800 for i in range(int(T_CREST * 800), 801) if prof(i / 800)[1] < z)


def t_pit_r(r: float) -> float:
    """Pit wall: the t where the profile comes in to radius r."""
    return next(i / 800 for i in range(int(T_CREST * 800), 801) if prof(i / 800)[0] < r)


MOUTH_Z1 = prof(t_pit_r(MOUTH_R))[1] - 0.01  # bowl edge, tucked under the throat's wall
MOUTH_Z0 = MOUTH_Z1 - 0.17  # bowl center
LIP_Z = 0.98  # where the pit's wall starts to fall steeply: the rim's inner edge
PIT_RIBS = 0.3  # m between the ring folds down the throat


def P(th: float, t: float) -> Vector:
    """Point on the body at angle th (rad) and profile parameter t."""
    r0, z0 = prof(t)
    s = t * PROF_LEN
    outer = NB._smoothstep(0.0, 0.3, s) * (1.0 - NB._smoothstep(CREST_S - 0.15, CREST_S + 0.1, s))
    lobe = 1.0 + outer * (0.035 * math.sin(3 * th + 0.6) + 0.02 * math.sin(5 * th + 2.2))
    # An uneven rim: the crest rises and dips around the ring, fading down both walls.
    crest = math.exp(-(((s - CREST_S) / 0.55) ** 2))
    z = z0 + crest * (0.045 * math.sin(2 * th + 1.1) + 0.025 * math.sin(5 * th + 0.4))
    p = Vector((math.cos(th) * r0 * lobe, math.sin(th) * r0 * lobe, z))
    # Along the profile normal (out of the body: outward on the ring, into the open pit on its walls): lumps on the
    # ring, ring folds down the throat (none at the ground ring and in the shaft under the mouth).
    dr, dz = (a - b for a, b in zip(prof(t + 0.002), prof(t - 0.002)))
    n2 = Vector((dz, -dr)).normalized()
    w = NB._smoothstep(0.05, 0.25, s) * (1.0 - NB._smoothstep(PROF_LEN - 0.45, PROF_LEN - 0.3, s))
    d = w * (0.06 * noise.noise(p * 1.4) + 0.025 * noise.noise(p * 3.7 + Vector((5, 1, 2))))
    pit = NB._smoothstep(CREST_S + 0.25, CREST_S + 0.5, s) * (1.0 - NB._smoothstep(PROF_LEN - 0.5, PROF_LEN - 0.3, s))
    d += pit * 0.035 * math.sin(math.tau * (s - CREST_S) / PIT_RIBS + 0.5 * math.sin(3 * th))
    return p + Vector((math.cos(th) * n2.x, math.sin(th) * n2.x, n2.y)) * d


def N(th: float, t: float) -> Vector:
    """Surface normal: out of the body (outward on the ring, up and inward on the pit's walls)."""
    e = 0.002
    a = P(th + e, t) - P(th - e, t)
    b = P(th, t + e) - P(th, t - e)
    return a.cross(b).normalized()


def radial(th: float) -> Vector:
    return Vector((math.cos(th), math.sin(th), 0.0))


# --- materials --------------------------------------------------------------------------------------

GLOW_COLOR = (0.477, 0.0648, 1.0)  # linear for the brood nests' violet Color(0.72, 0.28, 1.0)


def mat_glow() -> bpy.types.Material:
    """Violet glow of the throat, glands, veins and cracks (the game pulses it); the ordinary nest's glow in violet."""
    mat, nt, bsdf = C._new_material("BroodPit_Glow")
    co = NB._coord(nt)
    churn = NB._noise(nt, co, 5.0, 4.0, 0.6, dist=1.5)
    col = C._mix_color(nt, churn.outputs["Fac"], (0.2, 0.02, 0.5), (0.7, 0.16, 1.0))
    glow = nt.nodes.new("ShaderNodeAttribute")  # radial falloff in the mouth (1 = full), see build_mouth
    glow.attribute_name = "glow"
    strength = C._math(nt, "MULTIPLY", C._mix_float(nt, churn.outputs["Fac"], 2.5, 9.0), glow.outputs["Fac"])
    nt.links.new(strength, bsdf.inputs["Emission Strength"])
    col = C._mix_color(nt, glow.outputs["Fac"], (0.06, 0.008, 0.14), col)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(col, bsdf.inputs["Emission Color"])
    bsdf.inputs["Roughness"].default_value = 0.15
    return mat


def make_materials() -> None:
    global FLESH, CHITIN, RESIN, SAC, GLOW
    FLESH, CHITIN, RESIN, SAC = NB.mat_flesh(), NB.mat_chitin(), NB.mat_resin(), NB.mat_sac()
    NB.SLIME = NB.mat_slime()  # NB.build_slime reads it
    GLOW = mat_glow()


M_FLESH, M_CHITIN, M_RESIN, M_SAC = NB.M_FLESH, NB.M_CHITIN, NB.M_RESIN, NB.M_SAC


# --- parts ------------------------------------------------------------------------------------------


def build_body(part: NB.Part) -> None:
    rows, ts = [], []
    for j in range(BODY_RINGS):
        t = j / (BODY_RINGS - 1)
        ts.append(t)
        rows.append([part.bm.verts.new(P(i / BODY_SEG * math.tau, t)) for i in range(BODY_SEG)])
    t_resin = t_pit_z(0.62)  # the deep throat: black resin
    for j, (a, b) in enumerate(itertools.pairwise(rows)):
        mi = M_RESIN if ts[j] > t_resin else M_FLESH
        faces = part.faces([a, b], mi, closed_u=True)
        c = faces[0].calc_center_median()
        if ts[j] < T_CREST:
            out = c - Vector((0, 0, c.z - 0.3))
        else:
            out = Z - c.normalized() * 0.5
        NB.orient(part, faces, out, 0)


def body_sheet() -> NB.Sheet:
    """The body as build_body lays it out: a = th in segments (wraps), b = t in rings."""
    grid = [[P(i / BODY_SEG * math.tau, j / (BODY_RINGS - 1)) for i in range(BODY_SEG)] for j in range(BODY_RINGS)]
    return NB.Sheet(grid, wrap=True)


def plate(
    part: NB.Part, tier: int, k: int, th_c: float, hw: float, t0: float, t1: float, lift: float, thick: float
) -> dict:
    """Shield-shaped chitin plate on the ring (the ordinary nest's): from its pointed end at t0, which lifts off
    like a scale, to t1 (t1 < t0 for the crest plates, whose points hang into the pit). Returns the plate for the
    cracks: its top surface as rows (along v, from the point) of vertex positions across, the sheet's normal out."""
    nu, nv = 6, 6
    top, bot = [], []
    for j in range(nv):
        v = j / (nv - 1)
        t = t0 + v * (t1 - t0)
        w = NB.plate_width(v)
        rt, rb = [], []
        for i in range(nu):
            uu = -1 + 2 * i / (nu - 1)
            th = th_c + uu * hw * w
            p, n = P(th, t), N(th, t)
            off = 0.014 + lift * (1 - v) ** 1.6 + 0.03 * (1 - uu * uu) * (0.3 + 0.7 * v)
            th_k = thick * (0.35 + 0.65 * (1 - uu * uu))
            rt.append(part.bm.verts.new(p + n * off))
            rb.append(part.bm.verts.new(p + n * (off - th_k)))
        top.append(rt)
        bot.append(rb)
    faces = part.faces(top, M_CHITIN, closed_u=False) + part.faces(bot, M_CHITIN, closed_u=False, flip=True)
    ring_t = top[0] + [r[-1] for r in top[1:]] + top[-1][-2::-1] + [r[0] for r in top[-2:0:-1]]
    ring_b = bot[0] + [r[-1] for r in bot[1:]] + bot[-1][-2::-1] + [r[0] for r in bot[-2:0:-1]]
    faces += part.faces([ring_t, ring_b], M_CHITIN, closed_u=True)
    bmesh.ops.recalc_face_normals(part.bm, faces=faces)
    grid = [[v.co.copy() for v in (row if t1 > t0 else row[::-1])] for row in top]
    p, n, _pa, _pb = NB.Sheet(grid).frame(2.5, 2.5)
    assert n.dot(N(th_c, (t0 + t1) / 2)) > 0, ("plate sheet normal points in", tier, k)
    return dict(tier=tier, k=k, th=th_c, hw=hw, t0=t0, t1=t1, top=grid)


def tendril_angles() -> list:
    return sorted(math.radians(a) for a, _, _ in TENDRILS)


def build_plates(part: NB.Part, rnd: random.Random) -> list:
    """Three tiers of overlapping plates around the ring: low ones in the gaps between the tendrils (egg sacs in two
    of them), middle ones over the tendrils' roots, crest ones in the gaps again, over the crest with their points
    hanging into the pit."""
    angs = tendril_angles()
    plates = []
    for k, a in enumerate(angs):
        b = angs[(k + 1) % len(angs)] + (math.tau if k == len(angs) - 1 else 0)
        prev = angs[k - 1] - (math.tau if k == 0 else 0)
        mid, gap = (a + b) / 2, b - a
        if k not in SAC_GAPS:
            th = mid + rnd.uniform(-0.03, 0.03)
            plates.append(plate(part, 0, k, th, gap / 2 - 0.08, t_at_z(0.06), t_at_z(0.6), 0.08, 0.055))
        hw = (b - prev) / 4 - 0.02
        th = a + rnd.uniform(-0.03, 0.03)
        plates.append(plate(part, 1, k, th, hw, t_at_z(0.42), t_at_z(1.02), 0.09, 0.05))
        th = mid + rnd.uniform(-0.04, 0.04)
        plates.append(plate(part, 2, k, th, gap / 2 - 0.1, t_pit_z(0.78), t_at_z(0.88), 0.06, 0.045))
    return plates


def build_sacs(part: NB.Part) -> None:
    """Egg sac clusters low on the ring in the SAC_GAPS (one on the camera side)."""
    angs = tendril_angles()
    for k in SAC_GAPS:
        mid = (angs[k] + angs[(k + 1) % len(angs)] + (math.tau if k == len(angs) - 1 else 0)) / 2
        for dth, z, r in ((-0.16, 0.24, 0.27), (0.15, 0.18, 0.22), (0.0, 0.45, 0.19)):
            th, t = mid + dth, t_at_z(z)
            p, n = P(th, t), N(th, t)
            c = p - n * (r * 0.15)
            verts = bmesh.ops.create_uvsphere(
                part.bm, u_segments=12, v_segments=7, radius=r, matrix=T(c, basis(n, Z), (0.85, 0.95, 0.8))
            )["verts"]
            for f in {f for v in verts for f in v.link_faces}:
                f.material_index = M_SAC
                f.smooth = True


def build_hooks(part: NB.Part, rnd: random.Random) -> list:
    """A few short, thick chitin hooks on the crest: up out of the rim and curling in over the pit, tip down.
    Returns their tips."""
    angs = tendril_angles()
    tips = []
    for k in HOOKS:
        th = angs[k] + rnd.uniform(-0.08, 0.08)
        t = T_CREST + m(0.06)
        b, nn, rd = P(th, t), N(th, t), radial(th)
        h, reach = rnd.uniform(0.12, 0.17), rnd.uniform(0.42, 0.5)
        ctrl = [
            b - nn * 0.14,
            b + Z * 0.07 - rd * 0.06,
            b + Z * h - rd * reach * 0.55,
            b + Z * (h * 0.75) - rd * reach * 0.85,
            b - Z * 0.04 - rd * reach,
        ]
        pts = NB.catmull(ctrl, 11)
        r0 = rnd.uniform(0.15, 0.18)
        radii = [r0 * (1 - (i / 10) ** 1.4) for i in range(11)]
        radii[-1] = 0.0
        NB.tube(part, pts, radii, [Z.copy()] * 11, 7, flat=0.75, mi_fn=lambda f: M_CHITIN, kind=1.0)
        tips.append(pts[-1])
    return tips


def build_tendrils(part: NB.Part, glands: list, rnd: random.Random) -> list:
    """Main tendrils from under the middle plates down the ring's outer wall and out over the ground, with side
    branches (the ordinary nest's); returns their tip positions (slime fingers follow them)."""
    tips = []
    for deg, glen, r0 in TENDRILS:
        th0 = math.radians(deg)
        pts, refs = [], []
        t = t_at_z(rnd.uniform(0.6, 0.72))
        dt = 0.11 / PROF_LEN
        ph = rnd.uniform(0, 6.28)
        while t > 0.0:
            th = th0 + 0.035 * math.sin(t * 20 + ph)
            n = N(th, t)
            pts.append(P(th, t) + n * (r0 * 0.5))
            refs.append(n)
            t -= dt
        ground = NB.ground_path(th0, GROUND_START, glen, rnd)
        pts += ground[1:]
        refs += [Z.copy() for _ in ground[1:]]
        n_ring = len(pts) - len(ground) + 1
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
        n_ring += 2
        for i in range(n_ring, len(pts)):
            pts[i].z = radii[i] * 0.42 + 0.006
        pts[-1].z = 0.008
        NB.tube(part, pts, radii, refs, 7, flat=0.66, mi_fn=lambda f: M_CHITIN if f > 0.9 else M_FLESH)
        tips.append(pts[-1].copy())
        gi = n_ring + 2
        side = (pts[gi + 1] - pts[gi - 1]).normalized().cross(refs[gi]).normalized()
        glands.append((pts[gi] + side * radii[gi] * 0.85 + refs[gi] * 0.02, rnd.uniform(0.055, 0.075)))
        ng = len(pts) - n_ring
        picks = [n_ring + int(ng * rnd.uniform(0.3, 0.45)), n_ring + int(ng * rnd.uniform(0.62, 0.72))]
        if glen > 1.7:
            picks.append(n_ring + int(ng * rnd.uniform(0.5, 0.58)))
        for b, i in enumerate(picks):
            tan = (pts[i + 1] - pts[i - 1]).normalized()
            sgn = 1 if (b + deg) % 2 == 0 else -1
            d = Matrix.Rotation(sgn * rnd.uniform(0.6, 0.95), 3, "Z") @ tan
            d.z = 0
            d.normalize()
            blen = rnd.uniform(0.45, 0.9) if b != 1 else rnd.uniform(0.35, 0.6)
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
    angs = tendril_angles()
    for k, a in enumerate(angs):
        b = angs[(k + 1) % len(angs)] + (math.tau if k == len(angs) - 1 else 0)
        th = (a + b) / 2 + rnd.uniform(-0.1, 0.1)
        g = NB.ground_path(th, GROUND_START - 0.05, rnd.uniform(0.7, 1.3), rnd, 0.12)
        rr = [0.065 * (1 - i / (len(g) - 1)) ** 0.8 for i in range(len(g))]
        rr[-1] = 0.0
        for i, p in enumerate(g):
            p.z = rr[i] * 0.42 + 0.006
        g = [P(th, t_at_z(0.1))] + g
        rr = [0.07] + rr
        NB.tube(part, g, rr, [Z.copy() for _ in g], 5, flat=0.72)
    return tips


def build_veins(part: NB.Part, rnd: random.Random) -> None:
    """Glowing veins from the rim's inner edge down the pit's walls into the throat, brighter as they go down
    (in the Glands mesh): the pit glows from below."""
    angs = tendril_angles()
    t0, t1 = t_pit_z(LIP_Z + 0.04), t_pit_r(MOUTH_R - 0.02)
    n = 14
    for a in angs:
        for th0 in (a + 0.3 + rnd.uniform(-0.1, 0.1),):
            ph, sw = rnd.uniform(0, math.tau), rnd.uniform(0.04, 0.09)
            pts, refs = [], []
            for i in range(n):
                f = i / (n - 1)
                t = t0 + (t1 - t0) * f
                th = th0 + sw * math.sin(f * 7 + ph) * (1 - f) + 0.25 * f * f
                nn = N(th, t)
                pts.append(P(th, t) + nn * 0.01)
                refs.append(nn)
            r_top = rnd.uniform(0.014, 0.02)
            radii = [(r_top + 0.016 * i / (n - 1)) * min(1.0, i / 2) ** 0.6 for i in range(n)]
            faces = NB.tube(part, pts, radii, refs, 5, flat=0.45)
            z_top, z_bot = pts[0].z, pts[-1].z
            for v in {v for f in faces for v in f.verts}:
                v[part.glow] = 0.12 + 0.88 * max(0.0, min(1.0, (z_top - v.co.z) / (z_top - z_bot))) ** 1.6


def build_glands(nest, glands: list, rnd: random.Random) -> None:
    part = NB.Part("Glands", [GLOW])
    angs = tendril_angles()
    for k, a in enumerate(angs):  # pustules on the rim: clusters in the gaps between the crest plates
        if k in HOOKS and k % 2:
            continue
        for _ in range(rnd.randint(1, 3)):
            th = a + rnd.uniform(-0.12, 0.12)
            t = T_CREST + m(rnd.uniform(-0.15, 0.2))
            glands.append((P(th, t) + N(th, t) * 0.02, rnd.uniform(0.055, 0.085)))
    for c, r in glands:
        for v in bmesh.ops.create_uvsphere(part.bm, u_segments=8, v_segments=5, radius=r, matrix=T(c))["verts"]:
            v[part.glow] = 1.0
    build_veins(part, rnd)
    for f in part.bm.faces:
        f.smooth = True
    part.finish(nest)


def mouth_center() -> Vector:
    return Vector((0, 0, MOUTH_Z0))


def build_mouth(nest) -> None:
    """Glowing bowl closing the throat deep in the pit: radial folds like a sphincter, rising to the edge under the
    throat's wall, hottest in the middle."""
    part = NB.Part("Mouth", [GLOW])
    seg, rings = 32, 6
    center = part.bm.verts.new(mouth_center() - Vector((0, 0, 0.05)))
    center[part.glow] = 1.0
    rows = []
    for j in range(1, rings + 1):
        f = j / rings
        r = MOUTH_R * f
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            fold = 0.035 * math.sin(9 * a + 0.5) * math.sin(math.pi * f) ** 1.5
            z = MOUTH_Z0 + (MOUTH_Z1 - MOUTH_Z0) * f**2 + fold - 0.05 * (1 - f) ** 3
            v = part.bm.verts.new((math.cos(a) * r, math.sin(a) * r, z))
            v[part.glow] = 1.0 - 0.5 * f**2 + 0.15 * fold / 0.035 * f
            row.append(v)
        rows.append(row)
    faces = [part.bm.faces.new((center, rows[0][i], rows[0][(i + 1) % seg])) for i in range(seg)]
    faces += part.faces(rows, 0, closed_u=True)
    for f in faces:
        f.smooth = True
    NB.orient(part, faces, Z, 0)
    NB.orient(part, faces[seg:], Z, 0)
    part.finish(nest)


# --- cracks (the nest bursting open: the game shows Cracks1, then Cracks2, then Cracks3 as well) ----------------


def pit_crack(part: NB.Part, body: NB.Sheet, th: float, rnd: random.Random, width: float) -> None:
    """From under a crest plate's point down the pit's wall into the throat."""
    a0 = (th % math.tau) / math.tau * BODY_SEG
    start = (a0, t_pit_z(0.82) * (BODY_RINGS - 1))
    stop = (a0 + rnd.uniform(-1.2, 1.2), t_pit_r(MOUTH_R + 0.03) * (BODY_RINGS - 1))
    path = NB.crack_walk(body, start, stop, rnd)
    widths = NB.crack_widths(path, body, width, rnd, taper=(0.1, 0.15), w_end=0.3)
    NB.ribbon(part, body, path, widths, 0.008)
    NB.add_branches(part, body, path, widths, rnd, 2)


def crack_stage(pl: dict) -> int:
    """Which burst stage cracks this plate open: spread around the ring and over the tiers, a third each."""
    return (pl["k"] + 2 * pl["tier"]) % 3 + 1


def build_cracks(nest, plates: list) -> None:
    """Glowing fissures in the ring's plates: each stage cracks a third of them (spread around the ring), wider
    each stage; Cracks2 adds a second fissure to Cracks1's plates, Cracks3 to all the others, and Cracks3's crest
    plates crack on down the pit's walls into the throat."""
    rnd = random.Random(29)
    body = body_sheet()
    stages = [NB.Part(f"Cracks{i}", [GLOW]) for i in (1, 2, 3)]
    width = {1: (0.05, 0.06), 2: (0.06, 0.072), 3: (0.07, 0.085)}
    for pl in plates:
        s = crack_stage(pl)
        part = stages[s - 1]
        NB.plate_crack(part, pl, rnd, rnd.uniform(0.06, 0.14), rnd.uniform(0.85, 0.93), rnd.uniform(*width[s]), 3)
        later = stages[1] if s == 1 else stages[2]
        if s != 2 or pl["tier"] == 1:
            NB.plate_crack(later, pl, rnd, rnd.uniform(0.35, 0.5), rnd.uniform(0.75, 0.85), rnd.uniform(0.04, 0.05), 1)
        if s == 3 and pl["tier"] == 2:
            pit_crack(stages[2], body, pl["th"], rnd, rnd.uniform(0.06, 0.075))
    for part in stages:
        part.finish(nest)


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    rnd = random.Random(23)
    pit = C.asset_root(ASSET)
    mound = NB.Part("Mound", [FLESH, CHITIN, RESIN, SAC])
    build_body(mound)
    plates = build_plates(mound, rnd)
    build_sacs(mound)
    global HOOK_TIPS
    HOOK_TIPS = build_hooks(mound, rnd)
    tendrils = NB.Part("Tendrils", [FLESH, CHITIN])
    glands: list = []
    tips = build_tendrils(tendrils, glands, rnd)
    mound.finish(pit)
    tendrils.finish(pit)
    build_glands(pit, glands, rnd)
    build_mouth(pit)
    NB.SLIME_R = 3.55  # NB.build_slime reads it: the ring is wider than the ordinary nest's mound
    NB.build_slime(pit, tips, rnd)
    C.empty("HatchPoint", (0.0, 0.0, LIP_Z), pit)
    build_cracks(pit, plates)
    return pit


HOOK_TIPS: list = []


def report() -> None:
    print("STATS per object", C.tris_per_object())
    mound = bpy.data.objects["Mound"]
    reach = max((v.co.xy.length for v in mound.data.vertices if v.co.z > 0.1), default=0.0)
    top = max(v.co.z for v in mound.data.vertices)
    ring = max(P(i / 360 * math.tau, T_CREST).z for i in range(360))
    lip = min(P(i / 360 * math.tau, t_pit_z(LIP_Z)).xy.length for i in range(360))
    crest_r = prof(T_CREST)[0]
    hooks = min(p.xy.length for p in HOOK_TIPS)
    c = mouth_center()
    print(f"STATS ring radius above 0.1 m: {reach:.2f} (fits r 2.4), height {top:.2f}")
    print(f"STATS crest z {CREST_Z:.2f} at r {crest_r:.2f}")
    print(f"STATS ring body top (no plates or hooks) {ring:.2f}")
    print(f"STATS rim inner radius at z {LIP_Z}: {lip:.2f}, hook tips reach in to r {hooks:.2f}")
    print(f"STATS mouth center (Blender Z-up) {tuple(round(x, 3) for x in c)}, edge z {MOUTH_Z1:.3f}, r {MOUTH_R}")
    print(f"STATS mouth center (Godot Y-up) Vector3({c.x:.3f}, {c.z:.3f}, {-c.y:.3f})")


CLOSE_VIEWS = {
    "close": ((2.3, -2.8, 3.6), (0, 0, 0.5), 30),
    "top": ((0.01, -0.01, 18.0), (0, 0, 0), 40),
    "low": ((3.8, -4.6, 0.9), (0, 0, 0.7), 30),
}


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    if view in CLOSE_VIEWS:
        loc, target, lens = CLOSE_VIEWS[view]
        C.render_from(path, loc, target, lens, samples, size)
    elif view == "game":
        render_game_view(path, Vector((0, 0, 0.6)), samples, size, size * 2 // 3, 85)
    elif view == "far":  # game distance (~18 m), framed like the other nests' far views
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.35)
    elif view == "iso":
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.4), zoom=1.1)
    else:
        C.render(path, view=view, samples=samples, size=size, target=(0, 0, 0.6), zoom=1.3)


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


def set_hidden(root: bpy.types.Object, hidden: bool, cracks: bool = False) -> None:
    for o in [root, *root.children_recursive]:
        o.hide_render = hidden or (o.name.startswith("Cracks") and not cracks)


def compare(pit: bpy.types.Object) -> None:
    """The baked ordinary nest and quest nest beside this one, all unhurt (no cracks): from the game camera, and
    each from the far preview view."""
    others = []
    for name in ("nest", "quest_nest"):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets" / "aliens" / name / f"{name}.glb"))
        others.append(next(o for o in set(bpy.data.objects) - before if o.parent is None and o.type == "EMPTY"))
    nest, quest = others
    roots = [nest, pit, quest]
    for root in roots:
        set_hidden(root, False)
    side = Vector((1, 1, 0)).normalized() * 6.8  # screen right from the game camera
    nest.location, quest.location = -side, side
    render_game_view(OUT / "compare_iso.png", Vector((0, 0, 0.8)), 64, 1280, 720, 70)
    nest.location = quest.location = Vector()
    paths = []
    for root in roots:
        for other in roots:
            set_hidden(other, other is not root)
        p = OUT / f"compare_{root.name.lower()}_far.png"
        render_view(p, "far", 64, 768)
        paths.append(p)
    C.contact_sheet(paths, OUT / "compare_far.png", cols=3)


def main() -> None:
    C.reset(ASSET)
    make_materials()
    pit = build()
    report()
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(1.0, -4.2, 0.0) if MODE == "compare" else (2.9, 2.3, 0.0))
    NB.clear_preview_rubble(99.0 if MODE == "compare" else 4.7)
    set_hidden(pit, False)  # unhurt; the "cracks" view shows all three stages
    if MODE == "final":
        paths = []
        for view in ("iso", "hero", "back", "far", "game", "cracks"):
            p = OUT / f"render_{view}.png"
            render_preview(pit, p, view, 96, 1024)
            paths.append(p)
        C.contact_sheet(paths, OUT / "sheet.png", cols=3)
        C.save_blend(OUT / "brood_pit_procedural.blend")
    elif MODE == "compare":
        compare(pit)
    else:
        for view in VIEWS:
            if view != "none":
                render_preview(pit, OUT / "wip" / f"{TAG}_{view}.png", view, 24, 512)


def render_preview(pit: bpy.types.Object, path: pathlib.Path, view: str, samples: int, size: int) -> None:
    if view == "cracks":
        set_hidden(pit, False, cracks=True)
        render_view(path, "close", samples, size)
        set_hidden(pit, False)
    else:
        render_view(path, view, samples, size)


if __name__ == "__main__":
    main()
