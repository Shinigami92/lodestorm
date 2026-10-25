"""The ship's exterior (blockout): the skin around the rooms' box with its window belts and dorsal trench,
the nose with the cockpit's canopy, two nacelles on sponsons at the tail, six legs and the ramp (see
docs/planned/ship-exterior.md).

Run from the repo root (see docs/TECHNICAL.md, Asset pipeline):
    tools/blender.sh assets/ship/source/ship_exterior_build.py wip <tag> [variant] [views] [legs]
    tools/blender.sh assets/ship/source/ship_exterior_build.py final

variant: "ct" (taller and rounder with a dorsal trench, default), "b" (the box's skin with the trench) or
"c" (round without it); views: comma-separated from iso, ramp, title, side, top, front (default all);
legs: "down" (landed, default) or "up" (in flight, in space). Renders go to
tmp/ship_exterior/<tag>_<variant>_<view>.png. "final" exports the default variant to
assets/ship/ship_exterior.glb (legs down; the game moves them).

The layout comes from game/ship/hull_layout.py (Godot axes: +x tail, +z towards the camera, y up). Here
Blender's axes: +x tail, -y towards the camera, z up. Sections are (w, h): w across (|y|), h up.
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "tmp" / "ship_exterior"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
sys.path.insert(0, str(ROOT / "game" / "ship"))

import itertools

import bmesh
import bpy
import hull_layout as L
from mathutils import Matrix, Vector

import common as C

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VARIANT = ARGV[2] if len(ARGV) > 2 else "ct"
VIEWS = ARGV[3].split(",") if len(ARGV) > 3 else ["iso", "ramp", "title", "side", "top", "front"]
LEGS_DOWN = (ARGV[4] if len(ARGV) > 4 else "down") == "down"
C.reset("Ship")

# --- materials -------------------------------------------------------------------------------------


def flat(name: str, color, roughness: float = 0.55, metallic: float = 0.3, emission=None, strength: float = 0.0):
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


MATS = [
    flat("Hull", (0.30, 0.30, 0.29)),
    flat("Machinery", (0.07, 0.07, 0.075), 0.45, 0.6),
    flat("Glass", (0.02, 0.03, 0.04), 0.08, 0.0),
    flat("RoomGlow", (0.2, 0.15, 0.1), 0.5, 0.0, (1.0, 0.72, 0.42), 2.5),
    flat("SensorEye", (0.05, 0.1, 0.12), 0.2, 0.0, (0.3, 0.85, 1.0), 4.0),
    flat("Amber", (0.3, 0.18, 0.05), 0.4, 0.0, (1.0, 0.55, 0.12), 6.0),
    flat("Nozzle", (0.04, 0.04, 0.045), 0.4, 0.8, (0.35, 0.75, 1.0), 0.0 if LEGS_DOWN else 3.0),
    flat("HullDark", (0.17, 0.17, 0.17), 0.6, 0.3),
]
M_HULL, M_DARK, M_GLASS, M_GLOW, M_EYE, M_AMBER, M_NOZZLE, M_HULL2 = range(len(MATS))

# --- the box the skin wraps ------------------------------------------------------------------------

X0, X1 = L.BOX_X
W_BOX = L.BOX_Z
H0, H1 = L.BOX_Y
MARGIN = 0.3  # the skin's thickness: it keeps this far outside the box everywhere
BELLY = H0 - MARGIN
# Window belts: dark recessed bands along each deck, the windows in them.
BELTS = [(L.LOW + 0.7, L.LOW + 3.3), (L.UP + 0.8, L.UP + 3.2)]
BELT_DEPTH = 0.45

# Half sections from the belly's middle round to the top's middle (mirrored for the other side): (w, h,
# material of the stretch up to the next point).
PROFILES = {
    # The box's skin: a flat belly, the lower sides bulging out, the upper sides leaning in, the shoulders
    # rising into two ridges with a dark trench between them along the top.
    "b": [
        (0.0, BELLY, M_HULL2),
        (13.0, BELLY, M_HULL2),
        (15.7, BELLY + 0.05, M_HULL),
        (16.5, 2.6, M_HULL),
        (16.6, BELTS[0][0] - 0.2, M_DARK),
        (16.6 - BELT_DEPTH, BELTS[0][0], M_DARK),
        (16.6 - BELT_DEPTH, BELTS[0][1], M_DARK),
        (16.6, BELTS[0][1] + 0.2, M_HULL),
        (16.4, BELTS[1][0] - 0.2, M_DARK),
        (16.4 - BELT_DEPTH, BELTS[1][0], M_DARK),
        (16.2 - BELT_DEPTH, BELTS[1][1], M_DARK),
        (16.2, BELTS[1][1] + 0.2, M_HULL),
        (15.5, 12.0, M_HULL),
        (14.0, 13.5, M_HULL),
        (9.6, 13.7, M_DARK),
        (8.9, 12.8, M_DARK),
        (0.0, 12.8, M_DARK),
    ],
    # Taller and rounder: the box sits low in it, the round top well above the roof.
    "c": [
        (0.0, BELLY, M_HULL2),
        (12.5, BELLY, M_HULL2),
        (15.6, BELLY + 0.1, M_HULL),
        (16.9, 2.6, M_HULL),
        (17.3, BELTS[0][0] - 0.2, M_DARK),
        (17.3 - BELT_DEPTH, BELTS[0][0], M_DARK),
        (17.4 - BELT_DEPTH, BELTS[0][1], M_DARK),
        (17.5, BELTS[0][1] + 0.2, M_HULL),
        (17.4, BELTS[1][0] - 0.2, M_DARK),
        (17.4 - BELT_DEPTH, BELTS[1][0], M_DARK),
        (17.2 - BELT_DEPTH, BELTS[1][1], M_DARK),
        (17.2, BELTS[1][1] + 0.2, M_HULL),
        (16.6, 12.6, M_HULL),
        (15.3, 14.4, M_HULL),
        (12.8, 16.0, M_HULL),
        (8.8, 17.0, M_HULL),
        (4.2, 17.5, M_HULL),
        (0.0, 17.6, M_HULL),
    ],
}
# Round like c, with b's trench along the top between two rounded ridges.
PROFILES["ct"] = PROFILES["c"][:15] + [(10.8, 16.6, M_DARK), (10.1, 15.9, M_DARK), (0.0, 15.9, M_DARK)]
PROFILE = PROFILES[VARIANT]
TRENCH = VARIANT in ("b", "ct")
TRENCH_FLOOR = PROFILE[-1][1]
TOP_H = max(h for _, h, _ in PROFILE)


def check_profile() -> None:
    """Fails if the box (with the skin's thickness) isn't inside the section."""
    poly = [(w, h) for w, h, _ in PROFILE] + [(-w, h) for w, h, _ in reversed(PROFILE)]

    def inside(x: float, y: float) -> bool:
        hit = False
        for i in range(len(poly)):
            (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
            if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
                hit = not hit
        return hit

    for h in [H0 - MARGIN * 0.7] + [H0 + (H1 - H0) * i / 10 for i in range(11)] + [H1 + MARGIN * 0.7]:
        assert inside(W_BOX + MARGIN * 0.7, h), f"variant {VARIANT}: the box pokes out of the skin at h {h:.2f}"


check_profile()
assert max(h for _, h, _ in PROFILE) <= L.TAIL_TOP, "the hull outgrows the tail's top"
assert max(w for w, h, _ in PROFILE if h < 7.0) <= L.LOWER_SIDE, "the lower sides outgrow the clamps"


def offset(profile, d: float):
    """The profile pushed out by d along its normals (for raised rings)."""
    out = []
    for i, (w, h, m) in enumerate(profile):
        pw, ph, _ = profile[max(0, i - 1)]
        nw, nh, _ = profile[min(len(profile) - 1, i + 1)]
        tw, th = nw - pw, nh - ph
        ln = math.hypot(tw, th) or 1.0
        out.append((w + d * th / ln, h - d * tw / ln, m))
    return out


# --- lofts -----------------------------------------------------------------------------------------


def closed_ring(half) -> tuple[list[tuple[float, float]], list[int]]:
    """A half section mirrored into a closed ring (from the top's middle down the camera's side, along
    the belly, up the back) and the material of each stretch."""
    n = len(half)
    pts = [(-w, h) for w, h, _ in reversed(half)] + [(w, h) for w, h, _ in half[1:-1]]
    mats = []
    for k in range(2 * n - 2):
        seg = n - 2 - k if k < n - 1 else k - n + 1
        mats.append(half[seg][2])
    return pts, mats


def loft(name: str, stations, caps=(True, True), bevel=None, solid: float = 0.0) -> bpy.types.Object:
    """Joins sections along x: stations = [(x, half section)], all with the same number of points; a
    station's section may be scaled per station already. Caps close the ends."""
    bm = bmesh.new()
    rings = []
    mats = None
    for x, half in stations:
        pts, mats = closed_ring(half)
        rings.append([bm.verts.new((x, -w, h)) for w, h in pts])
    m = len(rings[0])
    for a, b in itertools.pairwise(rings):
        for i in range(m):
            j = (i + 1) % m
            f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mats[i]
    cap_faces = []
    if caps[0]:
        cap_faces.append(bm.faces.new(list(reversed(rings[0]))))
    if caps[1]:
        cap_faces.append(bm.faces.new(rings[-1]))
    for f in cap_faces:
        f.material_index = M_HULL
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    C.link(obj, ROOT_OBJ)
    for mat in MATS:
        me.materials.append(mat)
    if solid:
        mod = obj.modifiers.new("Solidify", "SOLIDIFY")
        mod.thickness = solid
        mod.offset = -1.0
        mod.use_even_offset = True
    if bevel:
        C.bevel(obj, bevel[0], bevel[1])
    return obj


# --- the skin --------------------------------------------------------------------------------------

NOSE_X0 = X0 - 0.4  # the taper starts in front of the box's nose wall
NOSE_TIP = X0 - 25.0
NOSE_HC = 5.6  # the height the nose closes towards (the sensor eye's center)
NOSE_MIN = (0.28, 0.4)  # the tip's section, as a share of the full one (across, up)
TAIL_X = X1 + MARGIN


def nose_scale(x: float) -> tuple[float, float]:
    """The section's scale (across, up) at x: in the nose, rounded in the top view, the top sloping down
    to the eye in the side view."""
    if x >= NOSE_X0:
        return 1.0, 1.0
    t = min(1.0, (NOSE_X0 - x) / (NOSE_X0 - NOSE_TIP))
    across = math.sqrt(max(0.0, 1 - t**2.2))
    up = 1 - t**1.25
    return NOSE_MIN[0] + (1 - NOSE_MIN[0]) * across, NOSE_MIN[1] + (1 - NOSE_MIN[1]) * up


def section_at(x: float, profile=None):
    sw, sh = nose_scale(x)
    return [(w * sw, NOSE_HC + (h - NOSE_HC) * sh, m) for w, h, m in (profile or PROFILE)]


def skin_h_top(x: float) -> float:
    """The skin's highest point at x."""
    return max(h for _, h, _ in section_at(x))


def skin() -> bpy.types.Object:
    n = 16
    xs = [TAIL_X, X1 - 4.0, X0 + 6.0, NOSE_X0]
    xs += [NOSE_X0 - (NOSE_X0 - NOSE_TIP) * (i / n) ** 0.85 for i in range(1, n + 1)]
    obj = loft("Skin", [(x, section_at(x)) for x in xs], solid=MARGIN)
    return obj


def rings() -> None:
    """Raised structural rings round the hull at the section walls."""
    for i, x in enumerate([-66.0, -51.75, -27.5, -3.25]):
        sec = offset(PROFILE, 0.18)
        sec = [(w, h, M_HULL2) for w, h, _ in sec]
        loft(f"Ring{i}", [(x - 0.5, sec), (x + 0.5, sec)], bevel=(0.06, 1))


SPONSON_X = (-10.0, TAIL_X)


def windows():
    """Every room window (where a sponson covers one, it looks out at the nacelle)."""
    for deck, floor in (("Lower", L.LOW), ("Upper", L.UP)):
        for side in (-1, 1):
            for x, width in L.outer_windows(deck, side):
                yield deck, floor, side, x, width


def cut_skin(obj: bpy.types.Object) -> None:
    """Cuts the ramp door and the windows (from the layout) through the skin."""
    coll = bpy.data.collections.new("Cutters")
    bpy.context.scene.collection.children.link(coll)
    boxes = [((X1 + 1.0, 0.0, L.LOW + L.RAMP_DOOR_HEIGHT / 2), (4.0, L.RAMP_WIDTH, L.RAMP_DOOR_HEIGHT))]
    for _deck, floor, side, x, width in windows():
        # Godot +z (side +1) is Blender -y.
        boxes.append(((x, -side * (W_BOX + 3.0), floor + 2.0), (width, 6.0, 2.0)))
    for i, (loc, size) in enumerate(boxes):
        me = bpy.data.meshes.new(f"Cutter{i}")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=C.T(loc, None, size))
        bm.to_mesh(me)
        bm.free()
        cube = bpy.data.objects.new(f"Cutter{i}", me)
        cube.hide_render = True
        cube.display_type = "WIRE"
        coll.objects.link(cube)
    mod = obj.modifiers.new("Openings", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    mod.solver = "EXACT"


def room_glow() -> None:
    """Warm panes where the rooms' windows are (the greybox walls' glass), seen through the holes."""
    p = C.Part("RoomGlow", MATS, bevel=None)
    for _deck, floor, side, x, width in windows():
        p.box((x, -side * (W_BOX - 0.4), floor + 2.0), (width, 0.1, 2.0), mi=M_GLOW)
    p.box((X1 - 0.6, 0.0, L.LOW + L.RAMP_DOOR_HEIGHT / 2), (0.1, L.RAMP_WIDTH, L.RAMP_DOOR_HEIGHT), mi=M_GLOW)
    # Only in the renders: in the game the rooms themselves show through.
    preview_obj(p.finish(None))


# --- parts on the skin -----------------------------------------------------------------------------


def dorsal() -> None:
    """The machinery along the top: radiators and vents in the trench (b) or on the round top (c), the
    sensor dome and the antenna mast."""
    p = C.Part("Dorsal", MATS, bevel=(0.05, 2))
    if TRENCH:
        floor = TRENCH_FLOOR
        ridge = max(w for w, h, _ in PROFILE if h > floor + 0.5 and w < 13.0)
        ridge_h = max(h for _, h, _ in PROFILE)
        for i in range(7):
            x = -66.0 + i * 9.0
            p.box((x, 0.0, floor + 0.4), (6.5, 6.0, 0.8), mi=M_HULL2)
            for k in range(5):
                p.box((x - 2.4 + k * 1.2, 0.0, floor + 0.95), (0.25, 5.2, 0.4), mi=M_DARK)
        p.sphere((-70.0, ridge - 1.0, ridge_h), 1.5, seg=16, rings=8, mi=M_HULL)
        p.rod((-8.0, -(ridge - 1.0), ridge_h), (-8.0, -(ridge - 1.0), ridge_h + 6.5), 0.15, mi=M_DARK)
        p.box((-8.0, -(ridge - 1.0), ridge_h + 4.5), (0.1, 2.2, 0.1), mi=M_DARK)
    else:
        for i in range(6):
            x = -64.0 + i * 10.0
            for s in (-1, 1):
                p.box((x, s * 6.0, TOP_H - 0.6), (7.0, 3.6, 1.0), mi=M_DARK)
        p.sphere((-70.0, 0.0, TOP_H - 0.2), 1.6, seg=16, rings=8, mi=M_HULL)
        p.rod((-8.0, 2.0, TOP_H - 0.5), (-8.0, 2.0, TOP_H + 6.0), 0.15, mi=M_DARK)
    p.finish(ROOT_OBJ)


def canopy() -> None:
    """The cockpit's canopy on the nose: a raised hood with framed panes sloping down to the front."""
    p = C.Part("Canopy", MATS, bevel=(0.05, 2))
    x_back, x_front = X0 + 4.0, X0 - 11.0
    top = skin_h_top(X0) + 0.6
    low = skin_h_top(x_front) - 0.6
    half_back, half_front = 8.5, 5.0
    # The hood: a wedge from its back (at the roof) to its front edge low on the nose.
    side = [(x_back, top - 4.0), (x_back, top), (x_front + 4.0, top), (x_front, low)]
    m = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    verts = p.prism([(x, h) for x, h in side], -half_back, half_back, m, mi=M_HULL)
    # Narrow the hood towards its front.
    for v in verts:
        k = (x_back - v.co.x) / (x_back - x_front)
        v.co.y *= 1 - k * (1 - half_front / half_back)
    # Panes on the sloping front: dark glass with frames between them.
    slope = Vector((4.0, 0, top - low))
    length = slope.length
    rot = Matrix.Rotation(-math.atan2(slope.z, slope.x), 4, "Y")
    mid = Vector((x_front + 2.0, 0, (top + low) / 2))
    normal = Vector((-slope.z, 0, slope.x)).normalized()
    width = 2 * (half_front + (half_back - half_front) * 0.25)
    p.box(mid + normal * 0.06, (length * 0.9, width * 0.86, 0.06), rot=rot, mi=M_GLASS)
    for k in range(5):
        y = -width * 0.43 + k * width * 0.86 / 4
        p.box(mid + normal * 0.1 + Vector((0, y, 0)), (length * 0.92, 0.22, 0.12), rot=rot, mi=M_DARK)
    bmesh.ops.recalc_face_normals(p.bm, faces=p.bm.faces)
    p.finish(ROOT_OBJ)


def nose_details() -> None:
    p = C.Part("NoseDetails", MATS, bevel=(0.03, 2))
    tip = section_at(NOSE_TIP)
    w_tip = max(w for w, _, _ in tip)
    along = Matrix.Rotation(math.pi / 2, 4, "Y")
    eye_r = min(w_tip * 0.8, 2.6)
    p.cyl((NOSE_TIP - 0.35, 0.0, NOSE_HC), eye_r, 0.7, seg=32, rot=along, mi=M_DARK)
    p.cyl((NOSE_TIP - 0.72, 0.0, NOSE_HC), eye_r * 0.62, 0.06, seg=32, rot=along, mi=M_EYE)
    for s in (-1, 1):
        p.box((NOSE_TIP + 0.6, s * (eye_r + 1.0), NOSE_HC - 1.6), (0.3, 0.9, 0.35), mi=M_AMBER)
    p.finish(ROOT_OBJ)


def stripes() -> None:
    """A thin amber stripe along both sides between the decks' belts."""
    p = C.Part("Stripes", MATS, bevel=None)
    h = (BELTS[0][1] + BELTS[1][0]) / 2
    w = max(w for w, hh, _ in PROFILE if BELTS[0][1] < hh < BELTS[1][0]) + 0.02
    for s in (-1, 1):
        p.box(((X0 + 2.0 + SPONSON_X[0]) / 2, s * w, h), (SPONSON_X[0] - X0 - 2.0, 0.06, 0.14), mi=M_AMBER)
    p.finish(ROOT_OBJ)


# --- the tail: sponsons and nacelles -----------------------------------------------------------------

NACELLE_R = 4.5
NACELLE_LENGTH = 32.0


def nacelle_center() -> tuple[float, float]:
    return (21.5, 11.0) if VARIANT == "b" else (22.4, 12.0)


def sponsons() -> None:
    """Blocks on the tail's sides carrying the nacelles, growing out of the hull towards the tail."""
    wc, hc = nacelle_center()
    base = [
        (15.4, hc - 5.0, M_HULL),
        (wc - 1.5, hc - 4.2, M_HULL),
        (wc, hc - 1.4, M_HULL),
        (wc, hc + 1.4, M_HULL),
        (wc - 1.5, hc + 3.2, M_HULL),
        (15.0, hc + 3.0, M_HULL),
    ]
    for s in (-1, 1):
        stations = []
        for x, k in [(SPONSON_X[0], 0.0), (SPONSON_X[0] + 9.0, 1.0), (SPONSON_X[1], 1.0)]:
            sec = [(15.0 + (w - 15.0) * max(k, 0.05), hc + (h - hc) * max(k, 0.3), m) for w, h, m in base]
            # A one-sided section: mirror it into a closed ring around its own center.
            stations.append((x, sec))
        bm = bmesh.new()
        rings_ = []
        for x, sec in stations:
            rings_.append([bm.verts.new((x, s * w, h)) for w, h, _ in sec])
        n = len(base)
        for a, b in itertools.pairwise(rings_):
            for i in range(n):
                j = (i + 1) % n
                bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new(rings_[0])
        bm.faces.new(list(reversed(rings_[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new(f"Sponson{s}")
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(f"Sponson{'Front' if s < 0 else 'Back'}", me)
        C.link(obj, ROOT_OBJ)
        for mat in MATS:
            me.materials.append(mat)
        C.bevel(obj, 0.12, 2)


def nacelles() -> None:
    """Two big thrusters on the sponsons; the nozzles end at the tail, never past it on the camera's side,
    so they don't hide the ramp."""
    p = C.Part("Nacelles", MATS, bevel=(0.06, 2))
    r = NACELLE_R
    wc, hc = nacelle_center()
    x1 = TAIL_X + 0.3
    x0 = x1 - NACELLE_LENGTH
    # A station's hangar is built around the tail (game/ship/hull_layout.py).
    assert wc + r * 1.04 <= L.TAIL_HALF_WIDTH and hc + r * 1.04 <= L.TAIL_TOP, "the nacelles outgrow the tail"
    along = Matrix.Rotation(math.pi / 2, 4, "Y")
    for s in (-1, 1):
        y = s * wc
        # Body, tapered cowl at the front, the intake's dark lip.
        body = x1 - 3.5 - (x0 + 7.0)
        p.cyl((x0 + 7.0 + body / 2, y, hc), r, body, seg=40, rot=along, mi=M_HULL)
        p.cyl((x0 + 4.0, y, hc), r * 0.82, 6.0, seg=40, rot=along, mi=M_HULL, r2=r)
        p.cyl((x0 + 0.5, y, hc), r * 0.7, 1.0, seg=40, rot=along, mi=M_DARK, r2=r * 0.82)
        p.cyl((x0 + 0.02, y, hc), r * 0.62, 0.05, seg=40, rot=along, mi=M_DARK)
        # The nozzle: a dark ring, the bell narrowing to the tail, the throat glowing in flight.
        p.cyl((x1 - 2.75, y, hc), r * 1.04, 1.5, seg=40, rot=along, mi=M_DARK)
        p.cyl((x1 - 1.0, y, hc), r * 0.98, 2.0, seg=40, rot=along, mi=M_DARK, r2=r * 0.86)
        p.cyl((x1 - 0.05, y, hc), r * 0.76, 0.1, seg=40, rot=along, mi=M_NOZZLE)
        for k in range(5):
            p.cyl((x0 + 10.0 + k * 4.0, y, hc), r + 0.07, 0.35, seg=40, rot=along, mi=M_DARK)
        # Service hatches and a running light on the outside.
        p.box((x0 + 16.0, y + s * (r - 0.1), hc + 1.0), (5.0, 0.5, 2.0), mi=M_HULL2)
        p.box((x1 - 4.0, y + s * (r + 0.05), hc), (0.4, 0.15, 0.4), mi=M_AMBER)
    p.finish(ROOT_OBJ)


# --- legs and ramp ---------------------------------------------------------------------------------

LEG_RETRACT = 1.5  # how far each leg's strut and pad pull up into its housing in flight


def legs() -> None:
    """Six legs: a housing on the hull's lower side (part of the hull) and, as its own object, the strut
    with its pad, which pulls up into the housing in flight (origin at the housing, moved along z)."""
    house = C.Part("LegHousings", MATS, bevel=(0.06, 2))
    w_side = max(w for w, h, _ in PROFILE if h < BELTS[0][0])
    assert L.LEG_Z > w_side + 1.5, "the legs' pads must stand clear of the hull's side"
    for i, x in enumerate(L.LEG_X):
        for j, s in enumerate((-1, 1)):
            wc = L.LEG_Z
            # Housing: a block under the bulge, braced up to the hull below the window belt.
            house.box((x, s * wc, 2.35), (5.0, 4.4, 1.5), mi=M_DARK)
            house.box((x, s * (w_side + 0.3), 2.3), (4.0, 2.0, 1.8), mi=M_HULL2)
            for dx in (-1.6, 1.6):
                top = (x + dx, s * (w_side - 0.2), BELTS[0][0] - 0.2)
                house.beam((x + dx, s * (wc + 1.6), 3.0), top, 0.8, 0.7, (1, 0, 0))
            leg = C.Part(f"Leg{2 * i + j + 1}", MATS, bevel=(0.04, 2))
            leg.box((0, 0, -0.6), (2.4, 2.4, 1.6), mi=M_HULL)  # strut, mostly inside the housing
            leg.rod((0, 0, -1.2), (0, 0, -1.55), 0.8, mi=M_DARK)
            leg.box((0, 0, -1.6 - 0.15), (*L.LEG_PAD, 0.3), mi=M_DARK)  # pad
            obj = leg.finish(ROOT_OBJ)
            obj.location = (x, s * wc, 1.6 + 0.35 + (0.0 if LEGS_DOWN else LEG_RETRACT))
    house.finish(ROOT_OBJ)


def ramp() -> None:
    p = C.Part("Ramp", MATS, bevel=(0.03, 2))
    length, width = L.RAMP_LENGTH, L.RAMP_WIDTH
    p.box((length / 2, 0, -0.1), (length, width, 0.2), mi=M_DARK)
    for k in range(6):  # ribs
        p.box((0.5 + k * 0.8, 0, 0.03), (0.12, width - 1.0, 0.06), mi=M_HULL)
    for s in (-1, 1):  # side rails and their lit edges
        p.box((length / 2, s * (width / 2 - 0.2), 0.15), (length, 0.4, 0.5), mi=M_HULL)
        p.box((length / 2, s * (width / 2 - 0.2), 0.42), (length, 0.42, 0.05), mi=M_AMBER)
    # Only in the renders: the game's ramp moves on its own (its model comes with the details).
    obj = p.finish(None)
    preview_obj(obj)
    obj.location = (X1, 0, L.LOW)
    obj.rotation_euler = (0, math.asin(L.LOW / length) if LEGS_DOWN else -math.pi / 2, 0)
    # The door's frame on the tail and the status light over it.
    f = C.Part("DoorFrame", MATS, bevel=(0.05, 2))
    dh = L.RAMP_DOOR_HEIGHT
    for s in (-1, 1):
        f.box((TAIL_X + 0.2, s * (width / 2 + 0.5), L.LOW + dh / 2), (0.4, 1.0, dh + 0.4), mi=M_DARK)
    f.box((TAIL_X + 0.2, 0, L.LOW + dh + 0.5), (0.4, width + 2.0, 1.0), mi=M_DARK)
    f.box((TAIL_X + 0.42, 0, L.LOW + dh + 0.5), (0.06, 3.0, 0.25), mi=M_AMBER)
    f.finish(ROOT_OBJ)


# --- preview ---------------------------------------------------------------------------------------


def preview_obj(obj: bpy.types.Object) -> None:
    for c in obj.users_collection:
        c.objects.unlink(obj)
    bpy.data.collections["Preview"].objects.link(obj)


def preview() -> None:
    bpy.ops.mesh.primitive_plane_add(size=800)
    ground = bpy.context.active_object
    ground.data.materials.append(flat("Ground", (0.09, 0.075, 0.06), 0.95, 0.0))
    ground.hide_render = not LEGS_DOWN
    preview_obj(ground)
    # Players for scale: two at the ramp's foot, one beside the nose.
    for loc in [(X1 + 7.0, -2.0), (X1 + 9.0, 3.0), (X0 - 6.0, -22.0)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=1.8, location=(loc[0], loc[1], 0.9))
        fig = bpy.context.active_object
        fig.data.materials.append(flat("Figure", (0.8, 0.4, 0.1), 0.5, 0.0, (1.0, 0.5, 0.1), 2.0))
        preview_obj(fig)
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.5
    sun.angle = math.radians(2)
    sun_obj = bpy.data.objects.new("Sun", sun)
    sun_obj.rotation_euler = Vector((0.5, 0.75, -0.9)).to_track_quat("-Z", "Y").to_euler()
    bpy.data.collections["Preview"].objects.link(sun_obj)
    rim = bpy.data.lights.new("Rim", "SUN")
    rim.energy = 1.2
    rim_obj = bpy.data.objects.new("Rim", rim)
    rim_obj.rotation_euler = Vector((-0.6, -0.2, -0.4)).to_track_quat("-Z", "Y").to_euler()
    bpy.data.collections["Preview"].objects.link(rim_obj)
    world = bpy.data.worlds.new("World")
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.03, 0.035, 0.045, 1) if LEGS_DOWN else (0.003, 0.004, 0.006, 1)
    bg.inputs["Strength"].default_value = 1.4
    bpy.context.scene.world = world


def camera(location: Vector, target: Vector, fov: float = 30.0, ortho: float | None = None) -> None:
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.data.collections["Preview"].objects.link(cam)
    cam.location = location
    cam.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    else:
        # The game's camera: 30° vertical field of view.
        cam_data.sensor_fit = "VERTICAL"
        cam_data.angle_y = math.radians(fov)
    cam_data.clip_end = 3000
    bpy.context.scene.camera = cam


def iso_from(target: Vector, distance: float) -> Vector:
    """Where the game's camera stands: straight along Godot -z (Blender +y), 35° down."""
    pitch = math.radians(35)
    return target + Vector((0, -math.cos(pitch), math.sin(pitch))) * distance


def render(view: str) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.image_settings.file_format = "PNG"
    mid = Vector(((X0 + X1) / 2 - 8, 0, 5))
    if view == "iso":
        camera(iso_from(mid, 250), mid)
    elif view == "ramp":
        t = Vector((X1 + 6.0, 0, 1.0))
        camera(iso_from(t, 40), t)
    elif view == "title":
        t = mid + Vector((0, 0, 2))
        camera(t + Vector((-120, -150, 55)), t)
    elif view == "side":
        camera(Vector((mid.x, -200, 9)), Vector((mid.x, 0, 9)), ortho=135)
    elif view == "top":
        camera(Vector((mid.x, 0, 200)), Vector((mid.x, 0.001, 0)), ortho=135)
    elif view == "front":
        camera(Vector((X1 + 150, 0, 9)), Vector((X1, 0, 9)), ortho=60)
    path = OUT / f"{TAG}_{VARIANT}_{view}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


# --- build -----------------------------------------------------------------------------------------

ROOT_OBJ = C.asset_root("Ship")
cut_skin(skin())
rings()
room_glow()
dorsal()
canopy()
nose_details()
stripes()
sponsons()
nacelles()
legs()
ramp()
preview()
if MODE == "wip":
    for v in VIEWS:
        render(v)
    C.save_blend(OUT / f"{TAG}_{VARIANT}.blend")
elif MODE == "final":
    C.export_glb(ROOT / "assets" / "ship" / "ship_exterior.glb")
    print("tris", C.stats())
