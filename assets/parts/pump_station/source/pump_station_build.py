"""Brine pump station (Salt pans point of interest): a squat colony pump house crusted white with salt, a
horizontal brine tank behind it, pipe runs with valves and supports around it, one into a flanged wellhead, one
along the tank down into the ground. Thick salt crust lumps on the pipes, edges and feet are its look.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/pump_station/source/pump_station_build.py wip p1 layout,pieces,sheet
    tools/blender.sh assets/parts/pump_station/source/pump_station_build.py wip p1 Pump_house
    tools/blender.sh assets/parts/pump_station/source/pump_station_build.py final

Everything it writes goes to tmp/assets/parts/pump_station/ (see crawler_build.py for the modes and views); "final"
saves pump_station_procedural.blend for pump_station_bake.py.

Game contract: one mesh object per piece at the kit's root, all sharing one baked material; origin at the bottom
center on z = 0, front towards -Y. Pump_pipes is the exception: it's laid out around the other pieces, so its origin
is the part's center (place it at the part's origin, unrotated) and the house, the tank and the wellhead stand where
LAYOUT puts them.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "blender"))  # the shared colony look

import colony as K
from mathutils import Matrix, Vector

from common import rx, ry, rz

LOOKS = K.Looks(
    "salt",
    {
        "bone": ("paint", K.BONE, {"wear": 0.45, "rust": 0.5, "salt_band": 1.3}),
        "olive": ("paint", K.OLIVE, {"wear": 0.45, "rust": 0.55, "salt_band": 1.3}),
        "gun": ("paint", K.GUNMETAL, {"wear": 0.55, "rust": 0.6, "rough": 0.55, "salt_band": 1.0}),
        "hazard": ("paint", K.AMBER, {"hazard": True, "wear": 0.55}),
        "amber": ("paint", K.AMBER, {"wear": 0.6, "rust": 0.4}),
        "steel": ("steel", K.STEEL, {"rust": 0.6, "salt_band": 0.5}),
        "crust": ("crust", None, {}),
        "lamp": ("lamp", K.LAMP_RED, {"strength": 6.0}),
    },
)
M = LOOKS

# Layout (Blender axes, the part's way in towards +Y): the house in the middle with its hatch towards the way in,
# the tank behind it, the wellhead front left.
HOUSE = ((0.0, 0.4, 0.0), 180.0)
TANK = ((0.2, -3.9, 0.0), 0.0)
WELL = ((-4.9, 2.4, 0.0), 0.0)
PIPE_R = 0.15


def place(local, at) -> Vector:
    """A point of a piece (local) where the layout puts the piece (location, yaw)."""
    (x, y, z), yaw = at
    return Vector((x, y, z)) + rz(yaw) @ Vector(local)


def crust_line(p: K.Piece, a, b, n: int, size: float, rnd: random.Random, flat: float = 0.6) -> None:
    """Salt crust lumps along a line (a ledge, a pipe's underside), stretched along it and overlapping, so they
    read as one grown crust rather than loose stones."""
    a, b = Vector(a), Vector(b)
    d = b - a
    yaw = math.degrees(math.atan2(d.y, d.x))
    step = d.length / n
    for i in range(n):
        t = (i + 0.5 + rnd.uniform(-0.25, 0.25)) / n
        s = size * rnd.uniform(0.75, 1.2)
        c = a.lerp(b, t)
        along = max(step * 1.9, s * 1.2)
        p.blob(c, (along, s, s * flat), rnd, M["crust"], rot=rz(yaw + rnd.uniform(-12, 12)) @ rx(rnd.uniform(-8, 8)))


def berm(p: K.Piece, a, b, out, width: float, height: float, rnd: random.Random, n: int = 6) -> None:
    """A salt crust berm grown against a wall's foot from a to b (on the ground): a wedge `width` m out (towards
    `out`) and `height` m up the wall, its face uneven, with lumps on it."""
    a, b, out = Vector(a), Vector(b), Vector(out).normalized()
    pts = []
    for i in range(n + 1):
        q = a.lerp(b, i / n)
        w = width * rnd.uniform(0.7, 1.25)
        h = height * rnd.uniform(0.7, 1.3)
        pts += [
            q + out * w + Vector((0, 0, -0.12)),
            q - out * 0.08 + Vector((0, 0, -0.12)),
            q - out * 0.05 + Vector((0, 0, h)),
        ]
        pts.append(q + out * w * 0.45 + Vector((0, 0, h * 0.55)))
    verts = K.hull_verts(p.bm, pts)
    p._tag(verts, M["crust"], smooth=True)
    p.soft(verts)
    crust_line(
        p,
        a + out * width * 0.35 + Vector((0, 0, height * 0.45)),
        b + out * width * 0.35 + Vector((0, 0, height * 0.45)),
        max(2, n - 1),
        min(width, height) * 0.8,
        rnd,
        0.55,
    )


def mound(p: K.Piece, c, r: float, height: float, rnd: random.Random, lumps: int = 6, top: float = 0.45) -> None:
    """A crust collar round a foot at c: a low mound (r m out, `height` up, its top ring at r * top) with lumps."""
    c = Vector(c)
    pts = []
    for i in range(12):
        a = (i + rnd.uniform(-0.3, 0.3)) / 12 * math.tau
        k = rnd.uniform(0.8, 1.15)
        pts.append(c + Vector((math.cos(a) * r * k, math.sin(a) * r * k, -0.12)))
        pts.append(c + Vector((math.cos(a) * r * top * k, math.sin(a) * r * top * k, height * rnd.uniform(0.7, 1.2))))
    verts = K.hull_verts(p.bm, pts)
    p._tag(verts, M["crust"], smooth=True)
    p.soft(verts)
    for i in range(lumps):
        a = (i + rnd.uniform(-0.3, 0.3)) / lumps * math.tau
        rr = r * rnd.uniform(0.45, 0.7)
        s = r * rnd.uniform(0.35, 0.5)
        p.blob(
            c + Vector((math.cos(a) * rr, math.sin(a) * rr, height * 0.45)),
            (s * 1.4, s, s * 0.55),
            rnd,
            M["crust"],
            rot=rz(math.degrees(a) + 90),
        )


def drips(p: K.Piece, c, n: int, rnd: random.Random, length: float = 0.25) -> None:
    """Salt stalactites hanging under a leak (a flange, a nozzle)."""
    c = Vector(c)
    for _ in range(n):
        q = c + Vector((rnd.uniform(-0.1, 0.1), rnd.uniform(-0.1, 0.1), 0))
        ln = length * rnd.uniform(0.6, 1.2)
        p.blob(q - Vector((0, 0, ln / 2)), (0.09, 0.08, ln), rnd, M["crust"], count=10)


def house() -> None:
    """The pump house: a steel skid, prefab wall panels with ribs, gunmetal corner posts and roof, a motor housing
    and a mushroom vent on the roof, the hatch in a hazard-striped frame with a red status light above it, a louvered
    vent, three pipe stubs (to the wellhead, the tank and the ground run), salt crust grown along the foot, on the
    skid's ledge, the corners and under the stubs."""
    p = K.Piece("Pump_house", LOOKS, bevel=(0.035, 1))
    rnd = random.Random(31)
    p.box((0, 0, -0.05), (4.3, 3.3, 0.6), mi=M["gun"])
    p.box((0, 0, 1.525), (4.0, 3.0, 2.55), mi=M["bone"])
    for x in (-1.98, 1.98):
        for y in (-1.48, 1.48):
            p.box((x, y, 1.55), (0.2, 0.2, 2.6), mi=M["gun"])
    for x in (-0.95, 0.95):
        p.box((x, 1.52, 1.5), (0.08, 0.06, 2.45), mi=M["bone"])
    p.box((0.95, -1.52, 1.5), (0.08, 0.06, 2.45), mi=M["bone"])
    for y in (-0.5, 0.5):
        for x in (-2.02, 2.02):
            p.box((x, y, 1.5), (0.06, 0.08, 2.45), mi=M["bone"])
    p.box((0, 0, 2.89), (4.3, 3.3, 0.18), mi=M["gun"])
    p.box((0.55, 0.35, 3.22), (1.5, 1.05, 0.5), mi=M["olive"])
    p.box((0.55, 0.35, 3.49), (1.6, 1.15, 0.06), mi=M["gun"])
    p.cyl((-1.15, 0.55, 3.2), 0.18, 0.45, 12, mi=M["gun"])
    p.cyl((-1.15, 0.55, 3.45), 0.32, 0.1, 12, mi=M["steel"])
    # Hatch, status light, sill, louvered vent.
    p.box((-0.6, -1.53, 1.33), (1.35, 0.08, 2.15), mi=M["hazard"])
    p.box((-0.6, -1.57, 1.27), (1.05, 0.08, 1.9), mi=M["gun"])
    p.box((-0.98, -1.63, 1.2), (0.06, 0.05, 0.3), mi=M["steel"])
    for z in (0.6, 1.95):
        p.box((-0.2, -1.62, z), (0.1, 0.06, 0.18), mi=M["steel"])  # hinges
    p.box((-0.6, -1.58, 2.58), (0.16, 0.06, 0.1), mi=M["lamp"])
    p.box((-0.6, -1.55, 2.58), (0.24, 0.06, 0.18), mi=M["gun"])
    p.box((-0.6, -1.8, 0.3), (1.5, 0.45, 0.14), mi=M["gun"])
    p.box((1.15, -1.52, 1.95), (1.0, 0.06, 0.8), mi=M["gun"])
    for i in range(4):
        p.box((1.15, -1.56, 1.67 + i * 0.18), (0.88, 0.04, 0.1), rx(35), M["steel"])
    # Pipe stubs with flanges (Pump_pipes continues from their tips).
    for tip, d in STUBS:
        tip, d = Vector(tip), Vector(d)
        p.rod(tip - d * 0.35, tip, PIPE_R, 12, M["steel"])
        p.cyl(tip - d * 0.03, 0.2, 0.06, 12, C_basis(d), M["gun"])
        p.cyl(tip - d * 0.3, 0.22, 0.08, 12, C_basis(d), M["gun"])
        drips(p, tip - d * 0.03 - Vector((0, 0, 0.2)), 2, rnd, 0.22)
    # Salt crust: berms along the foot all round (thicker on the -X side and the back), lumps on the skid's ledge
    # and at the corners, a crust line under the roof's lip.
    for a, b, out, w, h in (
        ((-2.15, -1.65), (-2.15, 1.65), (-1, 0), 0.75, 0.75),
        ((-2.15, 1.65), (2.15, 1.65), (0, 1), 0.6, 0.6),
        ((2.15, 1.65), (2.15, -1.65), (1, 0), 0.42, 0.42),
        ((2.15, -1.65), (0.3, -1.65), (0, -1), 0.32, 0.35),
        ((-1.45, -1.65), (-2.15, -1.65), (0, -1), 0.4, 0.45),
    ):
        berm(p, (*a, 0.0), (*b, 0.0), (*out, 0.0), w, h, rnd, 5)
    for x, y in ((-1.98, -1.48), (-1.98, 1.48), (1.98, 1.48)):
        p.blob((x * 1.04, y * 1.04, 0.75), (0.36, 0.36, 0.6), rnd, M["crust"])
    crust_line(p, (-2.13, -1.3, 2.8), (-2.13, 1.3, 2.8), 6, 0.16, rnd, 0.6)
    p.finish()


def C_basis(d: Vector) -> Matrix:
    """Rotation turning a cylinder's axis (Z) along d."""
    return K.C.basis(d, Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0)))


# Pipe stubs of the house (house frame: tip, direction).
STUBS = [((2.35, -0.6, 0.9), (1, 0, 0)), ((0.6, 1.85, 1.0), (0, 1, 0)), ((-2.35, 0.5, 1.2), (-1, 0, 0))]
TANK_NOZZLE = ((-0.8, 1.25, 1.0), (0, 1, 0))  # tank frame
WELL_INLET = ((0.62, 0.0, 0.9), (1, 0, 0))  # wellhead frame


def tank() -> None:
    """The brine tank: a horizontal olive tank with dished heads, gunmetal bands, a faded hazard band, a manway and a
    vent on top, a side nozzle (to the house) and a drain nozzle, two saddles; salt crust on the saddles' feet,
    along the belly, salt drips under the nozzles."""
    p = K.Piece("Pump_tank", LOOKS, bevel=(0.03, 1))
    rnd = random.Random(41)
    zc, r = 1.35, 0.95
    p.cyl((0, 0, zc), r, 4.0, 28, ry(90), M["olive"])
    for side in (-1, 1):
        p.cyl((side * 2.15, 0, zc), r, 0.3, 28, ry(90 * side), M["olive"], r2=0.55)
        p.cyl((side * 1.85, 0, zc), r + 0.025, 0.1, 28, ry(90), M["gun"])
    p.cyl((1.15, 0, zc), r + 0.015, 0.36, 28, ry(90), M["hazard"])
    p.cyl((-0.3, 0, zc), r + 0.02, 0.08, 28, ry(90), M["gun"])
    for side in (-1, 1):
        x = side * 1.3
        p.box((x, 0, 0.0), (0.32, 1.75, 0.7), mi=M["gun"])
        p.prism(
            [(-0.8, 0.3), (0.8, 0.3), (0.8, 0.95), (0.45, 0.62), (-0.45, 0.62), (-0.8, 0.95)],
            x - 0.12,
            x + 0.12,
            Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0))).to_4x4(),
            M["gun"],
        )
        berm(p, (x - 0.16, -0.95, 0.0), (x - 0.16, 0.95, 0.0), (-1, 0, 0), 0.4, 0.38, rnd, 4)
        berm(p, (x + 0.16, 0.95, 0.0), (x + 0.16, -0.95, 0.0), (1, 0, 0), 0.32, 0.3, rnd, 4)
    p.cyl((0.6, 0, zc + r + 0.05), 0.32, 0.25, 16, mi=M["olive"])
    p.cyl((0.6, 0, zc + r + 0.2), 0.38, 0.07, 16, mi=M["gun"])
    p.rod((-1.4, 0, zc + r - 0.1), (-1.4, 0, zc + r + 0.45), 0.08, 10, M["steel"])
    p.cyl((-1.4, 0, zc + r + 0.48), 0.16, 0.08, 10, mi=M["gun"])
    tip, d = Vector(TANK_NOZZLE[0]), Vector(TANK_NOZZLE[1])
    p.rod(tip - d * 0.6, tip, PIPE_R, 12, M["steel"])
    p.cyl(tip - d * 0.03, 0.2, 0.06, 12, C_basis(d), M["gun"])
    drips(p, tip - d * 0.05 - Vector((0, 0, 0.2)), 3, rnd, 0.3)
    p.rod((1.6, 0, 0.55), (1.6, 0, 0.25), 0.07, 8, M["steel"])  # drain
    p.cyl((1.6, 0, 0.27), 0.12, 0.05, 10, mi=M["gun"])
    drips(p, (1.6, 0, 0.12), 2, rnd, 0.18)
    p.blob((1.6, 0, 0.0), (0.7, 0.55, 0.3), rnd, M["crust"])
    for y in (-0.55, 0.55):  # crust grown along the belly
        crust_line(p, (-1.0, y, zc - 0.78), (0.95, y, zc - 0.78), 5, 0.24, rnd, 0.55)
    p.finish()


def wellhead() -> None:
    """The wellhead where the brine line goes into the ground: casing, a heavy base flange, a spool and a valve
    block with a handwheel on top, the inlet stub towards the house (+X), a capped stub with a gauge on the other side;
    a thick salt crust collar round its foot."""
    p = K.Piece("Pump_wellhead", LOOKS, bevel=(0.025, 1))
    rnd = random.Random(51)
    p.cyl((0, 0, 0.0), 0.32, 1.0, 16, mi=M["steel"])
    p.cyl((0, 0, 0.5), 0.55, 0.1, 16, mi=M["gun"])
    p.cyl((0, 0, 0.66), 0.3, 0.24, 16, mi=M["gun"])
    p.box((0, 0, 0.95), (0.5, 0.5, 0.42), mi=M["olive"])
    p.cyl((0, 0, 1.2), 0.36, 0.08, 16, mi=M["gun"])
    p.cyl((0, 0, 1.32), 0.2, 0.16, 12, mi=M["gun"])
    p.rod((0, 0, 1.38), (0, 0, 1.62), 0.04, 6, M["steel"])
    wheel(p, (0, 0, 1.6), 0.24)
    tip, d = Vector(WELL_INLET[0]), Vector(WELL_INLET[1])
    p.rod((0.2, 0, 0.9), tip, PIPE_R, 12, M["steel"])
    p.cyl(tip - d * 0.03, 0.2, 0.06, 12, C_basis(d), M["gun"])
    p.rod((-0.2, 0, 0.95), (-0.45, 0, 0.95), 0.09, 10, M["steel"])
    p.cyl((-0.47, 0, 0.95), 0.15, 0.06, 12, ry(90), M["gun"])
    p.cyl((-0.3, 0, 1.12), 0.07, 0.04, 10, rx(90), M["gun"])
    mound(p, (0, 0, 0), 0.95, 0.42, rnd, 7)
    for i in range(6):
        a = i / 6 * math.tau + rnd.uniform(-0.3, 0.3)
        p.blob((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.58), (0.22, 0.18, 0.14), rnd, M["crust"])
    drips(p, (0.45, 0, 0.75), 2, rnd, 0.2)
    p.finish()


def wheel(p: K.Piece, c, r: float) -> None:
    """A horizontal valve handwheel (rim and three spokes) centered at c."""
    c = Vector(c)
    pts = [c + Vector((math.cos(a / 16 * math.tau) * r, math.sin(a / 16 * math.tau) * r, 0)) for a in range(16)]
    p.tube(pts, 0.03, 6, M["amber"], closed=True)
    for k in range(3):
        a = k / 3 * math.tau
        p.rod(c, c + Vector((math.cos(a) * r, math.sin(a) * r, 0)), 0.02, 4, M["amber"])
    p.cyl(c, 0.05, 0.06, 8, mi=M["gun"])


def run(p: K.Piece, pts: list, rnd: random.Random, crust: bool = True) -> None:
    """A pipe run through `pts` (straight legs), a joint and flanges at each bend, salt along its underside."""
    pts = [Vector(q) for q in pts]
    for a, b in itertools.pairwise(pts):
        p.rod(a, b, PIPE_R, 12, M["steel"])
        d = (b - a).normalized()
        ln = (b - a).length
        if crust and abs(d.z) < 0.5 and ln > 0.8:
            crust_line(
                p,
                a + d * 0.3 - Vector((0, 0, 0.11)),
                b - d * 0.3 - Vector((0, 0, 0.11)),
                max(1, int(ln / 0.7)),
                0.13,
                rnd,
                0.7,
            )
    for i in range(1, len(pts) - 1):
        q = pts[i]
        p.sphere(q, PIPE_R * 1.25, 12, 6, mi=M["steel"])
        for other in (pts[i - 1], pts[i + 1]):
            d = (other - q).normalized()
            p.cyl(q + d * 0.28, 0.2, 0.06, 12, C_basis(d), M["gun"])
        if crust:
            drips(p, q - Vector((0, 0, 0.18)), 2, rnd, 0.2)


def support(p: K.Piece, c, along, rnd: random.Random) -> None:
    """An H-frame pipe support under a pipe at c (pipe center), crusted at its feet."""
    c = Vector(c)
    side = Vector(along).cross(Vector((0, 0, 1))).normalized()
    for s in (-1, 1):
        f = c + side * s * 0.28
        p.box((f.x, f.y, (c.z - PIPE_R - 0.3) / 2), (0.09, 0.09, c.z - PIPE_R + 0.3), mi=M["gun"])
        mound(p, (f.x, f.y, 0.0), 0.28, 0.2, rnd, 2)
    q = c - Vector((0, 0, PIPE_R + 0.04))
    p.beam(q - side * 0.33, q + side * 0.33, 0.1, 0.08, Vector((0, 0, 1)), M["gun"])


def valve(p: K.Piece, c, along, rnd: random.Random) -> None:
    """A gate valve in a pipe at c: body, flanges, a stem and a handwheel on top."""
    c, d = Vector(c), Vector(along).normalized()
    p.box(c, (0.36, 0.36, 0.34), C_basis(d) if abs(d.z) > 0.9 else rz(math.degrees(math.atan2(d.y, d.x))), M["olive"])
    for s in (-1, 1):
        p.cyl(c + d * s * 0.22, 0.21, 0.07, 12, C_basis(d), M["gun"])
    p.cyl(c + Vector((0, 0, 0.32)), 0.11, 0.3, 10, mi=M["olive"])
    p.rod(c + Vector((0, 0, 0.45)), c + Vector((0, 0, 0.7)), 0.035, 6, M["steel"])
    wheel(p, c + Vector((0, 0, 0.68)), 0.27)
    p.blob(c - Vector((0, 0, 0.24)), (0.42, 0.36, 0.2), rnd, M["crust"])


def pipes() -> None:
    """The pipe runs around the house (part frame): house to wellhead (with a valve and a support), house to tank
    (a valve), and the east line along the tank down into the ground (a support, a ground collar of crust)."""
    p = K.Piece("Pump_pipes", LOOKS, bevel=(0.025, 1))
    rnd = random.Random(61)
    stubs = [(place(t, HOUSE), rz(HOUSE[1]) @ Vector(d)) for t, d in STUBS]
    nozzle = place(TANK_NOZZLE[0], TANK)
    inlet = place(WELL_INLET[0], WELL)
    # A: house -> wellhead.
    a0 = stubs[0][0]
    xa = -3.3
    run(p, [a0, (xa, a0.y, a0.z), (xa, inlet.y, a0.z), (inlet.x, inlet.y, inlet.z)], rnd)
    valve(p, (a0.x - 0.6, a0.y, a0.z), (1, 0, 0), rnd)
    support(p, (xa, (a0.y + inlet.y) / 2, a0.z), (0, 1, 0), rnd)
    # B: house -> tank.
    b0 = stubs[1][0]
    run(p, [b0, (b0.x, (b0.y + nozzle.y) / 2, b0.z), nozzle], rnd, crust=False)
    valve(p, (b0.x, (b0.y + nozzle.y) / 2, b0.z), (0, 1, 0), rnd)
    # C: house -> east, along the tank's end, down into the ground.
    c0 = stubs[2][0]
    xc, yc = 3.4, -2.6
    run(p, [c0, (xc, c0.y, c0.z), (xc, yc, c0.z), (xc, yc, -0.4)], rnd)
    support(p, (xc, (c0.y + yc) / 2, c0.z), (0, 1, 0), rnd)
    p.cyl((xc, yc, 0.1), 0.24, 0.1, 12, mi=M["gun"])
    mound(p, (xc, yc, 0.0), 0.8, 0.32, rnd, 5)
    p.finish()


PIECES = {"Pump_house": house, "Pump_tank": tank, "Pump_pipes": pipes, "Pump_wellhead": wellhead}

LAYOUT = [
    ("Pump_house", HOUSE[0], (0.0, 0.0, HOUSE[1]), 1.0),
    ("Pump_tank", TANK[0], (0.0, 0.0, TANK[1]), 1.0),
    ("Pump_wellhead", WELL[0], (0.0, 0.0, WELL[1]), 1.0),
    ("Pump_pipes", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), 1.0),
]

KIT = K.Kit(
    name="pump_station",
    weather="salt",
    pieces=PIECES,
    layout=LAYOUT,
    prop_radius=8.0,
    footprint=12.0,
    crate=((2.9, 3.5), -15.0),
    ores=[(6.0, 1.0), (-5.4, -2.9), (-1.6, 6.0)],
    emission=True,
)

if __name__ == "__main__":
    K.main(KIT)
