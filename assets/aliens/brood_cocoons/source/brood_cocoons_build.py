"""Brood nest, cocoon cluster: the nest a quest's hunt goal puts at its site, hatching the hunted strain in packs (a
small boss fight). Four upright, fat, ribbed cocoons of different heights, leaning outward, fused at a shared flesh
base; chitin bands wrap each cocoon, a vertical violet slit (where the strain splits out) runs up its front between
the bands' ends. The mouth sits low in the base where the cocoons meet, open toward the game camera; tendrils and
slime on the ground like the ordinary nest's. From the isometric camera it must read as a group of thick pods side
by side, not as the ordinary nest's low mound nor as the quest nest's single spire. Greybox quality (finished in
the art pass), built and baked through the same pipeline as the ordinary nest.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/aliens/brood_cocoons/source/brood_cocoons_build.py wip r1 [iso,hero,close,top,low,far,...]
    tools/blender.sh assets/aliens/brood_cocoons/source/brood_cocoons_build.py final
    tools/blender.sh assets/aliens/brood_cocoons/source/brood_cocoons_build.py compare

Everything it writes goes to tmp/assets/brood_cocoons/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png ("cracks" in the views shows all crack stages); "final" renders iso/hero/back/far, a contact sheet
(sheet.png) and saves the procedural brood_cocoons_procedural.blend that brood_cocoons_bake.py turns into the game
asset; "compare" renders the baked ordinary nest (assets/aliens/nest/nest.glb), the baked quest nest
(assets/aliens/quest_nest/quest_nest.glb) and this one side by side from the game's camera (compare_iso.png) and
each from the preview's far iso view (compare_far.png).

The shared parts (tube and crack builders, the procedural materials but the glow, slime) come from the ordinary
nest's nest_build.py; this script only builds the cluster's own shape.

Game contract: the same as the ordinary nest's (see nest_build.py), so the game's AlienNest script works unchanged.
Objects under the root empty "BroodCocoons": Mound (the base and the cocoons), Tendrils (share one texture atlas when
baked), Slime, Mouth (own glow material, the game pulses it), Glands (the cocoons' slits and the pustules, same glow
material), the empty "HatchPoint" in the mouth, Cracks1, Cracks2 and Cracks3 (glowing fissures over the cocoons for
the three burst stages, more and wider each stage; Cracks3 also runs over the base's flesh into the mouth). Origin
at the ground center. The cluster stands inside a cylinder of r 1.9 m and is about 2.85 m tall; the mouth sits low
between the cocoons (MOUTH_CENTER, printed by the build). Glow color the brood nests' violet, the game's
Color(0.72, 0.28, 1.0). Triangle budget ~18k (cracks ~3k on top), TBD (playtest).
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "brood_cocoons"
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

ASSET = "BroodCocoons"
Z = Vector((0, 0, 1))
CAM = math.radians(-45)  # direction from the center toward the game camera (+X/-Y)

# --- layout (meters, Z-up, camera looks from +X/-Y) -----------------------------------------------

# Base profile (radius, height) from the buried skirt up to the crest around the crater and down into it; the end
# hides under the Mouth bowl. Smoothed and resampled by arc length into prof(t).
BASE_PROFILE = [
    (1.86, -0.03),
    (1.78, 0.05),
    (1.6, 0.16),
    (1.36, 0.3),
    (1.1, 0.44),
    (0.86, 0.6),
    (0.68, 0.72),
    (0.56, 0.78),
    (0.48, 0.77),
    (0.42, 0.71),
    (0.36, 0.64),
    (0.3, 0.58),
]
BASE_SEG, BASE_RINGS = 36, 20
FRONT_DROP = 0.22  # the base is this much (share of its height) lower toward the camera: the mouth tilts into view
MOUTH_R = 0.38

# Cocoons: (angle deg of the foot around the center, height m, max radius m, outward lean of the top m, slit angle
# deg). A crescent open toward the camera (the mouth shows between them), the slits turned toward the camera.
PODS = [
    (235, 2.4, 0.5, 0.58, 285),
    (166, 2.85, 0.56, 0.28, 335),
    (100, 2.58, 0.53, 0.42, 300),
    (30, 2.25, 0.48, 0.62, 350),
]
POD_DIST = 0.94  # foot from the center
POD_Z0 = 0.1  # bottom of the cocoon (buried in the base)
# Radius along the cocoon (u 0 at the bottom, 1 at the tip), share of its max radius: a fat pod.
POD_PROFILE = [
    (0.0, 0.62),
    (0.1, 0.82),
    (0.25, 0.97),
    (0.4, 1.0),
    (0.55, 0.98),
    (0.68, 0.9),
    (0.79, 0.76),
    (0.88, 0.56),
    (0.94, 0.36),
    (0.98, 0.17),
    (1.0, 0.0),
]
POD_SEG, POD_RINGS = 24, 25
U_TOP = 0.975  # last ring; the tip vertex above it
U_CAP = 0.86  # chitin cap from here up
SLIT = (0.2, 0.78)  # u range of the slit
SLIT_W = 0.12  # rad: half width of the slit's groove
SLIT_DEPTH, SLIT_LIP = 0.09, 0.035
BAND_GAP = 0.34  # rad: the bands stop this far from the slit
BAND_PINCH = 0.1  # the bands constrict the cocoon (share of its radius): the flesh bulges between them

# Main tendrils: (angle deg, ground length m, radius at the start). They start on the base's slope and run out over
# the ground; the tip reaches 1.8 + ground length from the center (<= ~4.4 m).
TENDRILS = [
    (8, 2.5, 0.16),
    (62, 1.8, 0.15),
    (118, 2.4, 0.17),
    (172, 1.7, 0.15),
    (214, 2.55, 0.17),
    (262, 2.0, 0.16),
    (318, 2.3, 0.16),
]
GROUND_START = 1.8

# --- base profile and surface ---------------------------------------------------------------------------

_PTS = NB._chaikin(BASE_PROFILE)
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


def front_scale(th: float, r: float) -> float:
    """Height factor of the base at angle th and radius r: lower toward the camera (none at the center)."""
    w = ((1 + math.cos(th - CAM)) / 2) ** 2
    return 1.0 - FRONT_DROP * w * min(1.0, r / 0.6)


MOUTH_Z1_RAW = prof(t_in_crater(MOUTH_R))[1] - 0.005  # bowl edge (before the front scale), under the crater wall
MOUTH_Z0 = MOUTH_Z1_RAW - 0.15  # bowl center


def P(th: float, t: float) -> Vector:
    """Point on the base at angle th (rad) and profile parameter t."""
    r0, z0 = prof(t)
    s = t * PROF_LEN
    crest_s = T_CREST * PROF_LEN
    outer = NB._smoothstep(0.0, 0.3, s) * (1.0 - NB._smoothstep(crest_s - 0.1, crest_s + 0.05, s))
    lobe = 1.0 + outer * (0.05 * math.sin(4 * th + 0.3) + 0.03 * math.sin(7 * th + 1.9))
    z = z0 * front_scale(th, r0)
    z += 0.035 * math.sin(6 * th + 0.4) * math.exp(-(((s - crest_s) / 0.1) ** 2))  # lobed crest
    p = Vector((math.cos(th) * r0 * lobe, math.sin(th) * r0 * lobe, z))
    # Lumps along the profile normal (none at the ground ring and in the crater, where the mouth fits).
    dr, dz = (a - b for a, b in zip(prof(t + 0.002), prof(t - 0.002)))
    n2 = Vector((dz, -dr)).normalized()
    w = NB._smoothstep(0.05, 0.25, s) * (1.0 - NB._smoothstep(crest_s + 0.02, crest_s + 0.2, s))
    d = w * (0.06 * noise.noise(p * 1.4) + 0.025 * noise.noise(p * 3.7 + Vector((5, 1, 2))))
    return p + Vector((math.cos(th) * n2.x, math.sin(th) * n2.x, n2.y)) * d


def N(th: float, t: float) -> Vector:
    """Base surface normal: out of the body (outward on the slope, up and inward in the crater)."""
    e = 0.002
    a = P(th + e, t) - P(th - e, t)
    b = P(th, t + e) - P(th, t - e)
    return a.cross(b).normalized()


# --- cocoons ----------------------------------------------------------------------------------------

_POD_PTS = NB._chaikin(POD_PROFILE)


def pod_shape(u: float) -> float:
    u = max(0.0, min(1.0, u))
    for a, b in itertools.pairwise(_POD_PTS):
        if b[0] >= u:
            f = (u - a[0]) / max(b[0] - a[0], 1e-9)
            return a[1] + (b[1] - a[1]) * f
    return _POD_PTS[-1][1]


def make_pods(rnd: random.Random) -> list:
    pods = []
    for i, (deg, h, r, lean, slit) in enumerate(PODS):
        out = Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0.0))
        n_bands = 6 if h > 2.5 else 5
        bands = []
        for k in range(n_bands):
            uc = 0.19 + (0.83 - 0.19) * k / (n_bands - 1) + rnd.uniform(-0.015, 0.015)
            bands.append(
                dict(uc=uc, hu=rnd.uniform(0.027, 0.034), tilt=rnd.uniform(0.01, 0.025), ph=rnd.uniform(0, 6.28))
            )
        pods.append(
            dict(
                i=i,
                out=out,
                foot=out * POD_DIST,
                h=h,
                R=r,
                lean=lean,
                slit=math.radians(slit),
                bands=bands,
                seed=i * 7.3,
            )
        )
    return pods


def pod_axis(pod: dict, u: float) -> Vector:
    return pod["foot"] + Z * (POD_Z0 + u * (pod["h"] - POD_Z0)) + pod["out"] * (pod["lean"] * u**1.8)


def band_u(band: dict, th: float) -> float:
    """Height (u) of a band's middle at angle th: the bands wrap slightly tilted."""
    return band["uc"] + band["tilt"] * math.sin(th + band["ph"])


def ang_diff(a: float, b: float) -> float:
    return math.atan2(math.sin(a - b), math.cos(a - b))


def slit_env(u: float) -> float:
    return NB._smoothstep(SLIT[0] - 0.02, SLIT[0] + 0.06, u) * (1.0 - NB._smoothstep(SLIT[1] - 0.06, SLIT[1] + 0.02, u))


def pod_P(pod: dict, th: float, u: float) -> Vector:
    """Point on cocoon `pod` at angle th and height parameter u."""
    r = pod["R"] * pod_shape(u)
    d = ang_diff(th, pod["slit"])
    gap = NB._smoothstep(BAND_GAP * 0.6, BAND_GAP * 1.1, abs(d))  # no constriction in the bands' gap
    pinch = sum(math.exp(-(((u - band_u(b, th)) / (b["hu"] * 1.1)) ** 2)) for b in pod["bands"])
    r *= 1.0 - BAND_PINCH * min(pinch, 1.0) * gap
    s = slit_env(u)
    r += s * (
        -SLIT_DEPTH * math.exp(-((d / SLIT_W) ** 2)) + SLIT_LIP * math.exp(-(((abs(d) - 1.5 * SLIT_W) / SLIT_W) ** 2))
    )
    c = pod_axis(pod, u)
    rad = Vector((math.cos(th), math.sin(th), 0.0))
    p = c + rad * r
    lump = 0.025 * noise.noise(p * 1.7 + Vector((pod["seed"], 0, 0))) * NB._smoothstep(0.05, 0.2, u) * (1 - u)
    return p + rad * lump


def pod_N(pod: dict, th: float, u: float) -> Vector:
    e = 0.002
    a = pod_P(pod, th + e, u) - pod_P(pod, th - e, u)
    b = pod_P(pod, th, u + e) - pod_P(pod, th, u - e)
    return a.cross(b).normalized()


def pod_thetas(pod: dict) -> list:
    """Angles around a cocoon, denser at the slit (index POD_SEG // 2 is the slit), increasing."""
    out = []
    for k in range(POD_SEG):
        v = -math.pi + math.tau * k / POD_SEG
        out.append(pod["slit"] + v - 0.62 * math.sin(v))
    return out


def pod_us() -> list:
    return [U_TOP * j / (POD_RINGS - 1) for j in range(POD_RINGS)]


# --- materials --------------------------------------------------------------------------------------

GLOW_COLOR = (0.477, 0.0648, 1.0)  # linear for the brood nests' violet Color(0.72, 0.28, 1.0)


def mat_glow() -> bpy.types.Material:
    """Violet glow of the mouth, slits, glands and cracks (the game pulses it); the ordinary nest's glow in violet."""
    mat, nt, bsdf = C._new_material("BroodCocoons_Glow")
    co = NB._coord(nt)
    churn = NB._noise(nt, co, 5.0, 4.0, 0.6, dist=1.5)
    col = C._mix_color(nt, churn.outputs["Fac"], (0.2, 0.02, 0.5), (0.6, 0.12, 1.0))
    glow = nt.nodes.new("ShaderNodeAttribute")  # radial falloff in the mouth (1 = full), see build_mouth
    glow.attribute_name = "glow"
    strength = C._math(nt, "MULTIPLY", C._mix_float(nt, churn.outputs["Fac"], 2.5, 9.0), glow.outputs["Fac"])
    nt.links.new(strength, bsdf.inputs["Emission Strength"])
    col = C._mix_color(nt, glow.outputs["Fac"], (0.05, 0.006, 0.12), col)
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


def build_base(part: NB.Part) -> None:
    rows, ts = [], []
    for j in range(BASE_RINGS):
        t = j / (BASE_RINGS - 1)
        ts.append(t)
        rows.append([part.bm.verts.new(P(i / BASE_SEG * math.tau, t)) for i in range(BASE_SEG)])
    for j, (a, b) in enumerate(itertools.pairwise(rows)):
        mi = M_RESIN if ts[j] > T_CREST + m(0.06) else M_FLESH
        faces = part.faces([a, b], mi, closed_u=True)
        c = faces[0].calc_center_median()
        NB.orient(part, faces, (c - Vector((0, 0, 0.3))) if ts[j] < T_CREST else Z, 0)


def base_sheet() -> NB.Sheet:
    """The base as build_base lays it out: a = th in segments (wraps), b = t in rings."""
    grid = [[P(i / BASE_SEG * math.tau, j / (BASE_RINGS - 1)) for i in range(BASE_SEG)] for j in range(BASE_RINGS)]
    return NB.Sheet(grid, wrap=True)


def build_pod_body(part: NB.Part, pod: dict) -> None:
    """The cocoon's flesh skin (closed by a pointed chitin cap), open at the buried bottom."""
    ths, us = pod_thetas(pod), pod_us()
    rows = [[part.bm.verts.new(pod_P(pod, th, u)) for th in ths] for u in us]
    for j, (a, b) in enumerate(itertools.pairwise(rows)):
        mi = M_CHITIN if us[j] >= U_CAP else M_FLESH
        faces = part.faces([a, b], mi, closed_u=True)
        c = faces[0].calc_center_median()
        NB.orient(part, faces, c - pod_axis(pod, us[j]), 0)
    tip = part.bm.verts.new(pod_axis(pod, 1.0) + pod["out"] * 0.02 + Z * 0.02)
    last = rows[-1]
    faces = []
    for k in range(POD_SEG):
        f = part.bm.faces.new((last[k], last[(k + 1) % POD_SEG], tip))
        f.material_index, f.smooth = M_CHITIN, True
        faces.append(f)
    NB.orient(part, faces, Z, 0)
    pod["sheet"] = NB.Sheet([[v.co.copy() for v in row] for row in rows], wrap=True)
    pod["slit_a"] = POD_SEG // 2
    pod["ring_u"] = us


def build_band(part: NB.Part, pod: dict, band: dict, rnd: random.Random) -> dict:
    """A chitin band wrapped around the cocoon, open at the slit: a shell thickest in its middle, the lower edge
    lifting off a little, the ends near the slit thinner. Returns the band for the cracks, its top surface as rows
    (b, bottom to top) of vertex positions around the cocoon (a), so the sheet's normal points out."""
    na, nb = 12, 3
    gap = BAND_GAP + rnd.uniform(-0.03, 0.05)
    top, bot = [], []
    for jb in range(nb):
        v = jb / (nb - 1)
        rt, rb = [], []
        for ia in range(na):
            w = ia / (na - 1)
            th = pod["slit"] + gap + w * (math.tau - 2 * gap)
            end = NB._smoothstep(0.0, 0.1, min(w, 1 - w))
            u = band_u(band, th) + (v - 0.5) * 2 * band["hu"] * (0.75 + 0.25 * end)
            p, n = pod_P(pod, th, u), pod_N(pod, th, u)
            off = (0.014 + 0.05 * math.sin(math.pi * v) ** 0.7 + 0.03 * (1 - v) ** 2) * (0.55 + 0.45 * end)
            thick = 0.05 * (0.5 + 0.5 * math.sin(math.pi * v)) * (0.6 + 0.4 * end)
            rt.append(part.bm.verts.new(p + n * off))
            rb.append(part.bm.verts.new(p + n * (off - thick - 0.01)))
        top.append(rt)
        bot.append(rb)
    faces = part.faces(top, M_CHITIN, closed_u=False) + part.faces(bot, M_CHITIN, closed_u=False, flip=True)
    ring_t = top[0] + [r[-1] for r in top[1:]] + top[-1][-2::-1] + [r[0] for r in top[-2:0:-1]]
    ring_b = bot[0] + [r[-1] for r in bot[1:]] + bot[-1][-2::-1] + [r[0] for r in bot[-2:0:-1]]
    faces += part.faces([ring_t, ring_b], M_CHITIN, closed_u=True)
    bmesh.ops.recalc_face_normals(part.bm, faces=faces)
    grid = [[v.co.copy() for v in row] for row in top]
    sheet = NB.Sheet(grid, a_lim=(0.8, na - 1.8), b_lim=(0.3, nb - 1.05))
    p, n, _pa, _pb = sheet.frame(na / 2, 1.5)
    d = p - pod_axis(pod, band["uc"])
    assert n.dot(d) > 0, ("band sheet normal points in", pod["i"], band["uc"])
    return dict(pod=pod["i"], sheet=sheet, na=na, nb=nb, uc=band["uc"])


def build_cap_spike(part: NB.Part, pod: dict, rnd: random.Random) -> None:
    """A short hooked chitin point on the cocoon's tip, curling outward."""
    b = pod_axis(pod, 0.95)
    up = (pod_axis(pod, 1.0) - pod_axis(pod, 0.9)).normalized()
    h = rnd.uniform(0.22, 0.3)
    ctrl = [b, b + up * h * 0.5, b + up * h + pod["out"] * h * 0.35]
    pts = NB.catmull(ctrl, 7)
    radii = [0.07 * (1 - (i / 6) ** 1.2) for i in range(7)]
    radii[-1] = 0.0
    NB.tube(part, pts, radii, [pod["out"]] * 7, 6, flat=0.8, mi_fn=lambda f: M_CHITIN, kind=1.0)


def build_bridges(part: NB.Part, pods: list, rnd: random.Random) -> None:
    """Sinew bridges between neighboring cocoons: the cluster grew together."""
    order = sorted(pods, key=lambda p: math.atan2(p["out"].y, p["out"].x) % math.tau)
    for a, b in itertools.pairwise(order):
        for u in (rnd.uniform(0.12, 0.16), rnd.uniform(0.3, 0.36)):
            ca, cb = pod_axis(a, u), pod_axis(b, u)
            tha = math.atan2(cb.y - ca.y, cb.x - ca.x)
            thb = math.atan2(ca.y - cb.y, ca.x - cb.x)
            pa = pod_P(a, tha, u) - pod_N(a, tha, u) * 0.06
            pb = pod_P(b, thb, u) - pod_N(b, thb, u) * 0.06
            mid = (pa + pb) / 2 - Z * rnd.uniform(0.04, 0.09)
            pts = NB.catmull([pa, mid, pb], 9)
            r0 = rnd.uniform(0.07, 0.09)
            radii = [r0 * (0.65 + 0.35 * abs(1 - 2 * i / 8) ** 1.5) for i in range(9)]
            NB.tube(part, pts, radii, [Z.copy()] * 9, 6, flat=0.8, mi_fn=lambda f: M_FLESH, kind=1.0)


def build_sacs(part: NB.Part) -> None:
    """Egg sac clusters on the base beside the mouth, on the camera side's flanks."""
    for mid in (math.radians(268), math.radians(5)):
        for dth, z, r in ((-0.15, 0.3, 0.22), (0.14, 0.24, 0.18), (0.0, 0.46, 0.15)):
            th, t = mid + dth, t_at_z(z)
            p, n = P(th, t), N(th, t)
            c = p - n * (r * 0.15)
            verts = bmesh.ops.create_uvsphere(
                part.bm, u_segments=10, v_segments=6, radius=r, matrix=T(c, basis(n, Z), (0.85, 0.95, 0.8))
            )["verts"]
            for f in {f for v in verts for f in v.link_faces}:
                f.material_index = M_SAC
                f.smooth = True


def build_tendrils(part: NB.Part, glands: list, rnd: random.Random) -> list:
    """Main tendrils from the base's slope out over the ground, with side branches (the ordinary nest's); returns
    their tip positions (slime fingers follow them)."""
    tips = []
    for deg, glen, r0 in TENDRILS:
        th0 = math.radians(deg)
        pts, refs = [], []
        t = t_at_z(rnd.uniform(0.42, 0.52))
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
        n_base = len(pts) - len(ground) + 1
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
        n_base += 2
        for i in range(n_base, len(pts)):
            pts[i].z = radii[i] * 0.42 + 0.006
        pts[-1].z = 0.008
        NB.tube(part, pts, radii, refs, 7, flat=0.66, mi_fn=lambda f: M_CHITIN if f > 0.9 else M_FLESH)
        tips.append(pts[-1].copy())
        gi = n_base // 2
        side = (pts[gi + 1] - pts[gi - 1]).normalized().cross(refs[gi]).normalized()
        glands.append((pts[gi] + side * radii[gi] * 0.85 + refs[gi] * 0.02, rnd.uniform(0.055, 0.075)))
        ng = len(pts) - n_base
        picks = [n_base + int(ng * rnd.uniform(0.3, 0.45)), n_base + int(ng * rnd.uniform(0.62, 0.72))]
        if glen > 2.0:
            picks.append(n_base + int(ng * rnd.uniform(0.5, 0.58)))
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


def build_slit(part: NB.Part, pod: dict) -> None:
    """The glowing slit in the cocoon's groove: a flat lens, widest in the middle (in the Glands mesh)."""
    n = 18
    pts, refs, radii = [], [], []
    for i in range(n):
        f = i / (n - 1)
        u = SLIT[0] + 0.01 + (SLIT[1] - SLIT[0] - 0.02) * f
        nn = pod_N(pod, pod["slit"], u)
        pts.append(pod_P(pod, pod["slit"], u) + nn * 0.012)
        refs.append(nn)
        radii.append(0.07 * math.sin(math.pi * f) ** 0.5)
    radii[0] = radii[-1] = 0.0
    faces = NB.tube(part, pts, radii, refs, 6, flat=0.4)
    for v in {v for f in faces for v in f.verts}:
        v[part.glow] = 1.0


def build_glands(nest, glands: list, pods: list, rnd: random.Random) -> None:
    part = NB.Part("Glands", [GLOW])
    for _ in range(3):  # a few on the base below the crest
        th = rnd.uniform(0, math.tau)
        t = t_at_z(rnd.uniform(0.3, 0.5))
        glands.append((P(th, t) + N(th, t) * 0.03, rnd.uniform(0.05, 0.07)))
    for pod in pods:  # pustules on the slit's lips
        for k in range(2):
            u = rnd.uniform(SLIT[0] + 0.05, SLIT[1] - 0.05)
            th = pod["slit"] + (1 if (k + pod["i"]) % 2 else -1) * 1.7 * SLIT_W
            glands.append((pod_P(pod, th, u) + pod_N(pod, th, u) * 0.015, rnd.uniform(0.035, 0.05)))
    for c, r in glands:
        for v in bmesh.ops.create_uvsphere(part.bm, u_segments=8, v_segments=5, radius=r, matrix=T(c))["verts"]:
            v[part.glow] = 1.0
    for pod in pods:
        build_slit(part, pod)
    for f in part.bm.faces:
        f.smooth = True
    part.finish(nest)


def mouth_center() -> Vector:
    return Vector((0, 0, MOUTH_Z0))


def build_mouth(nest) -> None:
    """Glowing bowl filling the crater: radial folds like a sphincter, rising to the edge under the wall (which is
    lower toward the camera)."""
    part = NB.Part("Mouth", [GLOW])
    seg, rings = 32, 6
    center = part.bm.verts.new(mouth_center() - Vector((0, 0, 0.04)))
    center[part.glow] = 1.0
    rows = []
    for j in range(1, rings + 1):
        f = j / rings
        r = MOUTH_R * f
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            fold = 0.03 * math.sin(9 * a + 0.5) * math.sin(math.pi * f) ** 1.5
            z = MOUTH_Z0 + (MOUTH_Z1_RAW - MOUTH_Z0) * f**2 + fold - 0.04 * (1 - f) ** 3
            z *= front_scale(a, r) if f > 0 else 1.0
            v = part.bm.verts.new((math.cos(a) * r, math.sin(a) * r, z))
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


# --- cracks (the nest bursting open: the game shows Cracks1, then Cracks2, then Cracks3 as well) --------------


def band_crack(part: NB.Part, band: dict, rnd: random.Random, width: float, branches: int, span: float) -> None:
    """A fissure along a band, zig-zagging from its lower to its upper edge over `span` grid steps around."""
    sheet, na = band["sheet"], band["na"]
    a0 = rnd.uniform(1.5, na - 2.5 - span)
    lo, hi = (0.4, band["nb"] - 1.15) if rnd.random() < 0.5 else (band["nb"] - 1.15, 0.4)
    path = NB.crack_walk(sheet, (a0, lo), (a0 + span, hi), rnd, step=(0.045, 0.11))
    widths = NB.crack_widths(path, sheet, width, rnd)
    NB.ribbon(part, sheet, path, widths, 0.0045)
    NB.add_branches(part, sheet, path, widths, rnd, branches)


def slit_crack(part: NB.Part, pod: dict, rnd: random.Random, width: float, up: bool) -> None:
    """The slit tearing on: from its upper end toward the cap, or from its lower end down to the base."""
    sheet, us, a = pod["sheet"], pod["ring_u"], pod["slit_a"]

    def j(u: float) -> int:
        return min(range(len(us)), key=lambda k: abs(us[k] - u))

    if up:
        start, end = (a, j(SLIT[1]) - 0.5), (a + rnd.uniform(-1.5, 1.5), j(U_CAP + 0.02))
    else:
        start, end = (a, j(SLIT[0]) + 0.5), (a + rnd.uniform(-1.5, 1.5), j(0.11))
    path = NB.crack_walk(sheet, start, end, rnd, step=(0.04, 0.1))
    widths = NB.crack_widths(path, sheet, width, rnd, taper=(0.0, 0.3))
    NB.ribbon(part, sheet, path, widths, 0.006)
    NB.add_branches(part, sheet, path, widths, rnd, 1)


def base_crack(part: NB.Part, base: NB.Sheet, th: float, rnd: random.Random, width: float) -> None:
    """From the base's slope by the cocoons' feet up over the crest and down into the mouth."""
    a0 = (th % math.tau) / math.tau * BASE_SEG
    start = (a0, t_at_z(0.3) * (BASE_RINGS - 1))
    stop = (a0 + rnd.uniform(-0.8, 0.8), t_in_crater(MOUTH_R + 0.02) * (BASE_RINGS - 1))
    path = NB.crack_walk(base, start, stop, rnd, step=(0.04, 0.1))
    widths = NB.crack_widths(path, base, width, rnd, taper=(0.15, 0.15), w_end=0.3)
    NB.ribbon(part, base, path, widths, 0.006)
    NB.add_branches(part, base, path, widths, rnd, 1)


def build_cracks(nest, pods: list, bands: list) -> None:
    """Glowing fissures, more and wider each stage: Cracks1 on one band of every cocoon (the camera side's first),
    Cracks2 on two more bands each and the slits tearing up toward the caps, Cracks3 on all the other bands, the
    slits tearing down to the base and fissures over the base's crest into the mouth."""
    rnd = random.Random(29)
    stages = [NB.Part(f"Cracks{k}", [GLOW]) for k in (1, 2, 3)]
    for pod in pods:
        own = [b for b in bands if b["pod"] == pod["i"]]
        order = [own[k] for k in (2, 4, 1, 3, 0, 5) if k < len(own)]
        band_crack(stages[0], order[0], rnd, rnd.uniform(0.05, 0.06), 2, rnd.uniform(3.5, 4.5))
        for b in order[1:3]:
            band_crack(stages[1], b, rnd, rnd.uniform(0.06, 0.07), 1, rnd.uniform(4.0, 5.5))
        slit_crack(stages[1], pod, rnd, rnd.uniform(0.06, 0.07), True)
        for b in order[3:]:
            band_crack(stages[2], b, rnd, rnd.uniform(0.075, 0.09), 1, rnd.uniform(5.0, 7.0))
        slit_crack(stages[2], pod, rnd, rnd.uniform(0.075, 0.085), False)
    base = base_sheet()
    for deg in (200, 135, 66, 285, 345):
        base_crack(stages[2], base, math.radians(deg), rnd, rnd.uniform(0.07, 0.085))
    for part in stages:
        part.finish(nest)


# --- main -------------------------------------------------------------------------------------------


def build() -> bpy.types.Object:
    rnd = random.Random(17)
    nest = C.asset_root(ASSET)
    mound = NB.Part("Mound", [FLESH, CHITIN, RESIN, SAC])
    build_base(mound)
    pods = make_pods(rnd)
    bands = []
    for pod in pods:
        build_pod_body(mound, pod)
        bands += [build_band(mound, pod, b, rnd) for b in pod["bands"]]
        build_cap_spike(mound, pod, rnd)
    build_bridges(mound, pods, rnd)
    build_sacs(mound)
    tendrils = NB.Part("Tendrils", [FLESH, CHITIN])
    glands: list = []
    tips = build_tendrils(tendrils, glands, rnd)
    mound.finish(nest)
    tendrils.finish(nest)
    build_glands(nest, glands, pods, rnd)
    build_mouth(nest)
    NB.build_slime(nest, tips, rnd)
    C.empty("HatchPoint", tuple(mouth_center() + Vector((0, 0, 0.02))), nest)
    build_cracks(nest, pods, bands)
    return nest


def report() -> None:
    print("STATS per object", C.tris_per_object())
    mound = bpy.data.objects["Mound"]
    reach = max((v.co.xy.length for v in mound.data.vertices if v.co.z > 0.02), default=0.0)
    top = max(v.co.z for v in mound.data.vertices)
    c = mouth_center()
    print(f"STATS mound radius above 0.02 m: {reach:.2f} (fits r 1.9), height {top:.2f}, crest {CREST_Z:.2f}")
    print(f"STATS mouth center (Blender Z-up) {tuple(round(x, 3) for x in c)}, edge z {MOUTH_Z1_RAW:.3f}")
    print(f"STATS mouth center (Godot Y-up) Vector3({c.x:.3f}, {c.z:.3f}, {-c.y:.3f})")


CLOSE_VIEWS = {
    "close": ((2.6, -3.1, 3.4), (0, 0, 1.3), 35),
    "top": ((0.01, -0.01, 18.0), (0, 0, 0), 40),
    "low": ((3.4, -4.2, 1.0), (0, 0, 1.2), 30),
}


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    if view in CLOSE_VIEWS:
        loc, target, lens = CLOSE_VIEWS[view]
        C.render_from(path, loc, target, lens, samples, size)
    elif view == "far":  # game distance (~18 m), framed like the ordinary nest's far view
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 0.5), zoom=1.35)
    elif view == "iso":
        C.render(path, view="iso", samples=samples, size=size, target=(0, 0, 1.1), zoom=1.05)
    else:
        C.render(path, view=view, samples=samples, size=size, target=(0, 0, 1.3), zoom=1.3)


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


def compare(brood: bpy.types.Object) -> None:
    """The baked ordinary nest, the baked quest nest and this one side by side, all unhurt (no cracks): from the game
    camera, and each from the far preview view."""
    nest = import_root(ROOT / "assets" / "aliens" / "nest" / "nest.glb")
    quest = import_root(ROOT / "assets" / "aliens" / "quest_nest" / "quest_nest.glb")
    roots = [nest, quest, brood]
    for root in roots:
        set_hidden(root, False)
    side = Vector((1, 1, 0)).normalized() * 6.0  # screen right from the game camera
    nest.location, quest.location, brood.location = -side, Vector(), side
    render_game_view(OUT / "compare_iso.png", Vector((0, 0, 1.0)), 64, 1600, 720, 62)
    paths = []
    for root in roots:
        for other in roots:
            other.location = Vector()
            set_hidden(other, other is not root)
        p = OUT / f"compare_{root.name.split('.')[0].lower()}_far.png"
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
    brood = build()
    report()
    print("STATS", C.stats())
    figure = (2.0, -2.6, 0.0) if MODE == "compare" else (2.5, 2.1, 0.0)
    C.preview_scene(crystals=False, figure_location=figure)
    NB.clear_preview_rubble(99.0 if MODE == "compare" else 4.7)
    if MODE == "final":
        set_hidden(brood, False)
        paths = []
        for view in ("iso", "hero", "back", "far"):
            p = OUT / f"render_{view}.png"
            render_view(p, view, 96, 1024)
            paths.append(p)
        C.contact_sheet(paths, OUT / "sheet.png", cols=2)
        show_cracks()
        C.save_blend(OUT / "brood_cocoons_procedural.blend")
    elif MODE == "compare":
        compare(brood)
    else:
        if "cracks" not in VIEWS:
            set_hidden(brood, False)
        for view in VIEWS:
            if view not in ("none", "cracks"):
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, 24, 512)


if __name__ == "__main__":
    main()
