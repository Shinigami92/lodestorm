"""Quest nest: the nest a quest puts into a region ("clear nests"). A brood spire instead of the ordinary nest's low
mound: a slightly leaning, twisted column of stacked chitin ring plates rising from a flesh mound, crimson seams
spiralling up between the plates, a crown of curved horns around the glowing mouth on top, tendrils and slime on
the ground like the ordinary nest's. It must read as a vertical spike from the isometric camera, not as the mound.
Greybox quality (finished in the art pass), built and baked through the same pipeline as the ordinary nest.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/quest_nest/source/quest_nest_build.py wip r1 [iso,hero,close,top,low,far,...]
    tools/blender.sh assets/aliens/quest_nest/source/quest_nest_build.py final
    tools/blender.sh assets/aliens/quest_nest/source/quest_nest_build.py compare

Everything it writes goes to tmp/assets/quest_nest/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png; "final" renders iso/hero/back/far, a contact sheet (sheet.png) and saves the procedural
quest_nest_procedural.blend that quest_nest_bake.py turns into the game asset; "compare" renders the baked
ordinary nest (assets/aliens/nest/nest.glb) beside this one from the game's camera (compare_iso.png) and both from
the preview's far iso view (compare_far.png).

The shared parts (tube and crack builders, the procedural materials but the glow, slime) come from the ordinary
nest's nest_build.py; this script only builds the spire's own shape.

Game contract: the same as the ordinary nest's (see nest_build.py), so the game's AlienNest script works unchanged.
Objects under the root empty "QuestNest": Mound, Tendrils (share one texture atlas when baked), Slime, Mouth (own
glow material, the game pulses it), Glands (pustules and the spiralling seams, same glow material), the empty
"HatchPoint" in the mouth, Cracks1 and Cracks2 (glowing fissures in the plates for the two burst stages; Cracks2
also runs over the crown's flesh to the mouth). Origin at the ground center. The spire stands inside a cylinder of
r 1.5 m and is about 3.6 m tall to the horn tips; the mouth sits on top (MOUTH_CENTER, printed by the build), so
the game's collision and mouth center differ from the ordinary nest's. Glow color crimson, the game's
Color(1.0, 0.16, 0.12). Triangle budget ~15k (cracks ~2.5k on top), TBD (playtest).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "quest_nest"
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

ASSET = "QuestNest"
Z = Vector((0, 0, 1))

# --- layout (meters, Z-up, camera looks from +X/-Y) -----------------------------------------------

# Profile (radius, height) from the buried skirt over the base mound up the column, over the crown's crest and
# down into the crater; the end hides under the Mouth bowl. Smoothed and resampled by arc length into prof(t).
PROFILE = [
    (1.42, -0.03),
    (1.36, 0.05),
    (1.26, 0.15),
    (1.1, 0.28),
    (0.96, 0.42),
    (0.85, 0.6),
    (0.78, 0.85),
    (0.72, 1.2),
    (0.64, 1.6),
    (0.56, 2.0),
    (0.48, 2.4),
    (0.42, 2.7),
    (0.44, 2.88),
    (0.5, 3.0),
    (0.52, 3.1),
    (0.46, 3.14),
    (0.4, 3.06),
    (0.35, 2.97),
    (0.3, 2.89),
    (0.26, 2.83),
]
BODY_SEG, BODY_RINGS = 36, 48
TWIST = 0.25  # rad per m: the whole spire turns as it rises
LEAN = 0.28  # m the top leans over, toward LEAN_DIR (screen right from the game camera: shows in the silhouette)
LEAN_DIR = Vector((1.0, 1.0, 0.0)).normalized()
MOUTH_R = 0.37

# Ring plates: tiers stacked up the column (shingled: each tier's lower edge lifts over the one below), split into
# PLATES_PER_TIER plates by seams that spiral up (SPIRAL rad per tier, on top of the twist).
N_TIERS, PLATES_PER_TIER = 5, 3
Z_FIRST, TIER_H, TIER_STEP = 0.78, 0.46, 0.41
SPIRAL = 0.45
GAP = 0.36  # rad between the plates of a tier: the seam's groove
PH0 = 0.3

# Main tendrils: (angle deg, ground length m, radius at the start). They start under the lowest plates, run down
# the base mound and out over the ground; the tip reaches 1.5 + ground length from the center (<= ~4.4 m).
TENDRILS = [
    (15, 2.6, 0.17),
    (66, 1.8, 0.15),
    (118, 2.5, 0.17),
    (168, 1.7, 0.15),
    (216, 2.75, 0.18),
    (262, 2.0, 0.16),
    (312, 2.6, 0.17),
]
GROUND_START = 1.5

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


def t_in_crater(r: float) -> float:
    """Crater side: the t where the profile comes in to radius r."""
    return next(i / 800 for i in range(int(T_CREST * 800), 801) if prof(i / 800)[0] < r)


MOUTH_Z1 = prof(t_in_crater(MOUTH_R))[1] - 0.005  # bowl edge, tucked under the crater wall
MOUTH_Z0 = MOUTH_Z1 - 0.15  # bowl center


def axis(z: float) -> Vector:
    """The spire's lean: offset of its axis at height z (none on the base mound)."""
    s = max(0.0, min(1.0, (z - 0.45) / 2.65)) ** 1.7
    return LEAN_DIR * (LEAN * s)


def P(th: float, t: float) -> Vector:
    """Point on the body at angle th (rad, before the twist) and profile parameter t."""
    r0, z0 = prof(t)
    s = t * PROF_LEN
    crest_s = T_CREST * PROF_LEN
    base = 1.0 - NB._smoothstep(0.5, 0.95, z0)  # base mound lobes, fading into the column
    outer = NB._smoothstep(0.0, 0.26, s) * base
    lobe = 1.0 + outer * (0.05 * math.sin(3 * th + 0.6) + 0.03 * math.sin(5 * th + 2.2))
    ang = th + TWIST * z0
    z = z0 + 0.045 * math.sin(5 * th + 0.4) * math.exp(-(((s - crest_s) / 0.12) ** 2))  # lobed crown crest
    p = Vector((math.cos(ang) * r0 * lobe, math.sin(ang) * r0 * lobe, z))
    # Lumps along the profile normal (none at the ground ring and in the crater, where the mouth fits).
    dr, dz = (a - b for a, b in zip(prof(t + 0.002), prof(t - 0.002)))
    n2 = Vector((dz, -dr)).normalized()
    w = NB._smoothstep(0.05, 0.22, s) * (1.0 - NB._smoothstep(crest_s + 0.04, crest_s + 0.25, s))
    w *= 0.4 + 0.6 * base  # the plates cover the column: smaller lumps there
    d = w * (0.06 * noise.noise(p * 1.4) + 0.025 * noise.noise(p * 3.7 + Vector((5, 1, 2))))
    return p + Vector((math.cos(ang) * n2.x, math.sin(ang) * n2.x, n2.y)) * d + axis(z0)


def N(th: float, t: float) -> Vector:
    """Surface normal: out of the body (outward on the sides, up and inward in the crater)."""
    e = 0.002
    a = P(th + e, t) - P(th - e, t)
    b = P(th, t + e) - P(th, t - e)
    return a.cross(b).normalized()


def out_from_axis(p: Vector) -> Vector:
    """Horizontal direction from the spire's axis to p."""
    d = p - axis(p.z)
    d.z = 0.0
    return d.normalized()


# --- materials --------------------------------------------------------------------------------------

GLOW_COLOR = (1.0, 0.022, 0.014)  # linear for the quest nest's crimson Color(1.0, 0.16, 0.12)


def mat_glow() -> bpy.types.Material:
    """Crimson glow of the mouth, glands, seams and cracks (the game pulses it); the ordinary nest's glow in red."""
    mat, nt, bsdf = C._new_material("QuestNest_Glow")
    co = NB._coord(nt)
    churn = NB._noise(nt, co, 5.0, 4.0, 0.6, dist=1.5)
    col = C._mix_color(nt, churn.outputs["Fac"], (0.45, 0.006, 0.004), (1.0, 0.07, 0.04))
    glow = nt.nodes.new("ShaderNodeAttribute")  # radial falloff in the mouth (1 = full), see build_mouth
    glow.attribute_name = "glow"
    strength = C._math(nt, "MULTIPLY", C._mix_float(nt, churn.outputs["Fac"], 2.5, 9.0), glow.outputs["Fac"])
    nt.links.new(strength, bsdf.inputs["Emission Strength"])
    col = C._mix_color(nt, glow.outputs["Fac"], (0.15, 0.003, 0.002), col)
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
    for j, (a, b) in enumerate(itertools.pairwise(rows)):
        mi = M_RESIN if ts[j] > T_CREST + m(0.08) else M_FLESH
        faces = part.faces([a, b], mi, closed_u=True)
        c = faces[0].calc_center_median()
        NB.orient(part, faces, (c - axis(c.z) - Vector((0, 0, c.z - 0.3))) if ts[j] < T_CREST else Z, 0)


def body_sheet() -> NB.Sheet:
    """The body as build_body lays it out: a = th in segments (wraps), b = t in rings."""
    grid = [[P(i / BODY_SEG * math.tau, j / (BODY_RINGS - 1)) for i in range(BODY_SEG)] for j in range(BODY_RINGS)]
    return NB.Sheet(grid, wrap=True)


def seam_angle(j: float, z: float) -> float:
    """Angle (before the twist) of seam j, the gap after plate j of every tier, at height z: a helix."""
    return PH0 + (j + 0.5) * math.tau / PLATES_PER_TIER + SPIRAL * (z - Z_FIRST) / TIER_STEP


def ring_plate(part: NB.Part, k: int, j: int, rnd: random.Random) -> dict:
    """Plate j of tier k: a curved chitin shell wrapped around the column between two seams, sheared along the
    spiral, its corners rounded, its lower edge lifting off like a scale. Returns the plate for the cracks, its top
    surface as rows along the arc (b) of vertex positions from the top edge down (a), so the sheet's normal points
    out."""
    nu, nv = 6, 6
    zb = Z_FIRST + k * TIER_STEP
    zt = zb + TIER_H
    zm = (zb + zt) / 2
    hw = math.pi / PLATES_PER_TIER - GAP / 2 - rnd.uniform(0.0, 0.04)
    jitter = rnd.uniform(-0.04, 0.04)
    lift, thick = 0.11, 0.07
    top, bot = [], []
    for jj in range(nu):
        uu = -1 + 2 * jj / (nu - 1)
        rt, rb = [], []
        for ii in range(nv):
            v = 1 - ii / (nv - 1)  # 1 at the top edge
            z = zm + (v - 0.5) * TIER_H * (0.62 + 0.38 * math.sqrt(max(0.0, 1 - uu * uu)))
            th = seam_angle(j - 0.5, z) + jitter + uu * hw  # plate center halfway between seams j - 1 and j
            t = t_at_z(z)
            p, n = P(th, t), N(th, t)
            off = 0.014 + lift * (1 - v) ** 1.6 + 0.02 * (1 - uu * uu) + 0.015 * math.sin(math.pi * v)
            th_k = thick * (0.4 + 0.6 * (1 - uu * uu))
            rt.append(part.bm.verts.new(p + n * off))
            rb.append(part.bm.verts.new(p + n * (off - th_k)))
        top.append(rt)
        bot.append(rb)
    faces = part.faces(top, M_CHITIN, closed_u=False) + part.faces(bot, M_CHITIN, closed_u=False, flip=True)
    ring_t = top[0] + [r[-1] for r in top[1:]] + top[-1][-2::-1] + [r[0] for r in top[-2:0:-1]]
    ring_b = bot[0] + [r[-1] for r in bot[1:]] + bot[-1][-2::-1] + [r[0] for r in bot[-2:0:-1]]
    faces += part.faces([ring_t, ring_b], M_CHITIN, closed_u=True)
    bmesh.ops.recalc_face_normals(part.bm, faces=faces)
    # A short thorn from the middle of the lower edge, out and down: a spikier silhouette than smooth bands.
    th, t = seam_angle(j - 0.5, zb + 0.08) + jitter + rnd.uniform(-0.3, 0.3) * hw, t_at_z(zb + 0.08)
    b, n = P(th, t), N(th, t)
    b += n * (0.014 + lift * 0.8)
    tip = b + (n * 0.85 - Z * 0.35).normalized() * rnd.uniform(0.17, 0.27)
    pts = NB.catmull([b - n * 0.06, b + n * 0.03, tip], 6)
    r0 = rnd.uniform(0.045, 0.06)
    radii = [r0 * (1 - i / 5) ** 0.9 for i in range(6)]
    NB.tube(part, pts, radii, [Z.copy()] * 6, 5, flat=0.8, mi_fn=lambda f: M_CHITIN, kind=1.0)
    grid = [[v.co.copy() for v in row] for row in top]
    sheet = NB.Sheet(grid)
    p, n, _pa, _pb = sheet.frame(2.5, 2.5)
    assert n.dot(out_from_axis(p)) > 0, ("plate sheet normal points in", k, j)
    return dict(k=k, j=j, zb=zb, zt=zt, th=seam_angle(j - 0.5, zt) + jitter, top=grid)


def build_plates(part: NB.Part, rnd: random.Random) -> list:
    return [ring_plate(part, k, j, rnd) for k in range(N_TIERS) for j in range(PLATES_PER_TIER)]


def build_seams(part: NB.Part) -> None:
    """Glowing seams in the grooves between the plates, spiralling up the column (in the Glands mesh)."""
    z0, z1 = Z_FIRST - 0.02, Z_FIRST + (N_TIERS - 1) * TIER_STEP + TIER_H + 0.02
    n = int((z1 - z0) / 0.075) + 1
    for j in range(PLATES_PER_TIER):
        pts, refs = [], []
        for i in range(n):
            z = z0 + (z1 - z0) * i / (n - 1)
            th, t = seam_angle(j, z), t_at_z(z)
            nn = N(th, t)
            pts.append(P(th, t) + nn * 0.012)
            refs.append(nn)
        radii = [0.038 * min(1.0, i / 3, (n - 1 - i) / 3) ** 0.6 for i in range(n)]
        faces = NB.tube(part, pts, radii, refs, 5, flat=0.5)
        for v in {v for f in faces for v in f.verts}:
            v[part.glow] = 1.0


def build_horns(part: NB.Part, rnd: random.Random) -> None:
    """Crown of big curved chitin horns around the mouth: out over the crest, up, curling back in."""
    n = 5
    for k in range(n):
        th = k / n * math.tau + 0.4 + rnd.uniform(-0.18, 0.18)
        t = T_CREST - m(0.05)
        b, nn = P(th, t), N(th, t)
        rd = out_from_axis(b)
        h = rnd.uniform(0.42, 0.52)
        ctrl = [b - nn * 0.1, b + nn * 0.06 + Z * 0.06, b + Z * h * 0.45 + rd * 0.3, b + Z * h + rd * 0.12]
        pts = NB.catmull(ctrl, 10)
        r0 = rnd.uniform(0.13, 0.16)
        radii = [r0 * (1 - (i / 9) ** 1.3) for i in range(10)]
        radii[-1] = 0.0
        NB.tube(part, pts, radii, [rd] * 10, 7, flat=0.65, mi_fn=lambda f: M_CHITIN, kind=1.0)


def build_sacs(part: NB.Part) -> None:
    """Egg sac clusters on the base mound in two gaps between the tendrils (one on the camera side)."""
    for mid in (math.radians(287), math.radians(142)):
        for dth, z, r in ((-0.22, 0.3, 0.26), (0.2, 0.22, 0.21), (0.0, 0.5, 0.18)):
            th, t = mid + dth, t_at_z(z)
            p, n = P(th, t), N(th, t)
            c = p - n * (r * 0.15)
            verts = bmesh.ops.create_uvsphere(
                part.bm, u_segments=12, v_segments=7, radius=r, matrix=T(c, basis(n, Z), (0.85, 0.95, 0.8))
            )["verts"]
            for f in {f for v in verts for f in v.link_faces}:
                f.material_index = M_SAC
                f.smooth = True


def build_tendrils(part: NB.Part, glands: list, rnd: random.Random) -> list:
    """Main tendrils from under the lowest plates down the base mound and out over the ground, with side branches
    (the ordinary nest's, started lower); returns their tip positions (slime fingers follow them)."""
    tips = []
    for deg, glen, r0 in TENDRILS:
        th0 = math.radians(deg)
        pts, refs = [], []
        t = t_at_z(rnd.uniform(0.82, 0.95))
        dt = 0.11 / PROF_LEN
        ph = rnd.uniform(0, 6.28)
        while t > 0.0:
            th = th0 + 0.07 * math.sin(t * 20 + ph)
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
        gi = n_mound // 2
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
        g = NB.ground_path(th, GROUND_START - 0.05, rnd.uniform(0.9, 1.6), rnd, 0.12)
        rr = [0.065 * (1 - i / (len(g) - 1)) ** 0.8 for i in range(len(g))]
        rr[-1] = 0.0
        for i, p in enumerate(g):
            p.z = rr[i] * 0.42 + 0.006
        g = [P(th, t_at_z(0.12))] + g
        rr = [0.07] + rr
        NB.tube(part, g, rr, [Z.copy() for _ in g], 5, flat=0.72)
    return tips


def build_glands(nest, glands: list, rnd: random.Random) -> None:
    part = NB.Part("Glands", [GLOW])
    for _ in range(3):  # a few on the base mound under the lowest plates
        th = rnd.uniform(0, math.tau)
        t = t_at_z(rnd.uniform(0.45, 0.7))
        glands.append((P(th, t) + N(th, t) * 0.03, rnd.uniform(0.05, 0.07)))
    for c, r in glands:
        for v in bmesh.ops.create_uvsphere(part.bm, u_segments=8, v_segments=5, radius=r, matrix=T(c))["verts"]:
            v[part.glow] = 1.0
    build_seams(part)
    for f in part.bm.faces:
        f.smooth = True
    part.finish(nest)


def mouth_center() -> Vector:
    return axis(MOUTH_Z0) + Vector((0, 0, MOUTH_Z0))


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
            v = part.bm.verts.new(axis(z) + Vector((math.cos(a) * r, math.sin(a) * r, z)))
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


# --- cracks (the nest bursting open: the game shows Cracks1, then Cracks2 as well) -------------------------


def crown_crack(part: NB.Part, body: NB.Sheet, pl: dict, rnd: random.Random, width: float) -> None:
    """From under a top plate's upper edge up the crown, over the crest and down into the mouth."""
    a0 = (pl["th"] % math.tau) / math.tau * BODY_SEG
    start = (a0, t_at_z(pl["zt"] - 0.04) * (BODY_RINGS - 1))
    stop = (a0 + rnd.uniform(-0.6, 0.6), t_in_crater(MOUTH_R + 0.02) * (BODY_RINGS - 1))
    path = NB.crack_walk(body, start, stop, rnd)
    widths = NB.crack_widths(path, body, width, rnd, taper=(0.0, 0.15), w_end=0.25)
    NB.ribbon(part, body, path, widths, 0.006)
    NB.add_branches(part, body, path, widths, rnd, 2)


def build_cracks(nest, plates: list) -> None:
    """Glowing fissures in the ring plates: Cracks1 on a third of them (spread around and up the spire), Cracks2
    on all the others (a second, shorter one on every other tier), the top tier's running on over the crown into
    the mouth."""
    rnd = random.Random(29)
    body = body_sheet()
    stage1, stage2 = NB.Part("Cracks1", [GLOW]), NB.Part("Cracks2", [GLOW])
    for pl in plates:
        if (pl["k"] + pl["j"]) % 3 == 0:
            NB.plate_crack(
                stage1, pl, rnd, rnd.uniform(0.08, 0.15), rnd.uniform(0.85, 0.92), rnd.uniform(0.06, 0.07), 3
            )
            continue
        NB.plate_crack(stage2, pl, rnd, rnd.uniform(0.05, 0.1), rnd.uniform(0.9, 0.95), rnd.uniform(0.055, 0.07), 2)
        if pl["k"] == N_TIERS - 1:
            crown_crack(stage2, body, pl, rnd, rnd.uniform(0.05, 0.065))
        elif pl["k"] % 2 == 0:
            NB.plate_crack(stage2, pl, rnd, rnd.uniform(0.35, 0.5), rnd.uniform(0.75, 0.85), rnd.uniform(0.04, 0.05), 1)
    stage1.finish(nest)
    stage2.finish(nest)


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    rnd = random.Random(17)
    nest = C.asset_root(ASSET)
    mound = NB.Part("Mound", [FLESH, CHITIN, RESIN, SAC])
    build_body(mound)
    plates = build_plates(mound, rnd)
    build_sacs(mound)
    build_horns(mound, rnd)
    tendrils = NB.Part("Tendrils", [FLESH, CHITIN])
    glands: list = []
    tips = build_tendrils(tendrils, glands, rnd)
    mound.finish(nest)
    tendrils.finish(nest)
    build_glands(nest, glands, rnd)
    build_mouth(nest)
    NB.build_slime(nest, tips, rnd)
    C.empty("HatchPoint", tuple(mouth_center() + Vector((0, 0, 0.02))), nest)
    build_cracks(nest, plates)
    return nest


def report() -> None:
    print("STATS per object", C.tris_per_object())
    mound = bpy.data.objects["Mound"]
    reach = max((v.co.xy.length for v in mound.data.vertices if v.co.z > 0.1), default=0.0)
    top = max(v.co.z for v in mound.data.vertices)
    c = mouth_center()
    print(f"STATS mound radius above 0.1 m: {reach:.2f} (fits r 1.5), height {top:.2f}, crest {CREST_Z:.2f}")
    print(f"STATS mouth center (Blender Z-up) {tuple(round(x, 3) for x in c)}, edge z {MOUTH_Z1:.3f}")
    print(f"STATS mouth center (Godot Y-up) Vector3({c.x:.3f}, {c.z:.3f}, {-c.y:.3f})")


CLOSE_VIEWS = {
    "close": ((2.4, -2.9, 4.4), (0, 0, 2.7), 35),
    "top": ((0.01, -0.01, 18.0), (0, 0, 0), 40),
    "low": ((3.4, -4.2, 1.0), (0, 0, 1.4), 30),
}


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    if view in CLOSE_VIEWS:
        loc, target, lens = CLOSE_VIEWS[view]
        C.render_from(path, loc, target, lens, samples, size)
    elif view == "far":  # game distance (~18 m), framed like the ordinary nest's far view
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.35)
    elif view == "iso":
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 1.2), zoom=1.05)
    else:
        C.render(path, view=view, samples=samples, size=size, target=(0, 0, 1.5), zoom=1.3)


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


def compare(quest: bpy.types.Object) -> None:
    """The baked ordinary nest beside this one, both unhurt (no cracks): from the game camera, and both from the far
    preview view."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets" / "aliens" / "nest" / "nest.glb"))
    nest = next(o for o in set(bpy.data.objects) - before if o.parent is None and o.type == "EMPTY")
    for o in [*quest.children_recursive, *nest.children_recursive]:
        if o.name.startswith("Cracks"):
            o.hide_render = True
    side = Vector((1, 1, 0)).normalized() * 4.6  # screen right from the game camera
    quest.location, nest.location = side, -side
    render_game_view(OUT / "compare_iso.png", Vector((0, 0, 1.0)), 64, 1280, 720, 85)
    quest.location = nest.location = Vector()
    set_hidden(nest, True)
    render_view(OUT / "compare_quest_far.png", "far", 64, 768)
    set_hidden(nest, False)
    set_hidden(quest, True)
    render_view(OUT / "compare_nest_far.png", "far", 64, 768)
    C.contact_sheet([OUT / "compare_nest_far.png", OUT / "compare_quest_far.png"], OUT / "compare_far.png", cols=2)


def main() -> None:
    C.reset(ASSET)
    make_materials()
    quest = build()
    report()
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(1.0, -1.0, 0.0) if MODE == "compare" else (2.5, 2.1, 0.0))
    NB.clear_preview_rubble(99.0 if MODE == "compare" else 4.7)
    if MODE == "final":
        paths = []
        for view in ("iso", "hero", "back", "far"):
            p = OUT / f"render_{view}.png"
            render_view(p, view, 96, 1024)
            paths.append(p)
        C.contact_sheet(paths, OUT / "sheet.png", cols=2)
        C.save_blend(OUT / "quest_nest_procedural.blend")
    elif MODE == "compare":
        compare(quest)
    else:
        for view in VIEWS:
            if view != "none":
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, 24, 512)


if __name__ == "__main__":
    main()
