"""Dead heat tap (Ash fields point of interest): a colony geothermal heat tap over a dead vent: a squat armored
housing with heat-exchanger fin banks, its top grate over a well where a dull ember glow is left, the riser that
stood on it collapsed and lying broken beside it, a loose fin rack on the ground. Scorched, heat-blued paint.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/heat_tap/source/heat_tap_build.py wip h1 layout,pieces,sheet
    tools/blender.sh assets/parts/heat_tap/source/heat_tap_build.py wip h1 Tap_housing
    tools/blender.sh assets/parts/heat_tap/source/heat_tap_build.py final

Everything it writes goes to tmp/assets/parts/heat_tap/ (see crawler_build.py for the modes and views); "final"
saves heat_tap_procedural.blend for heat_tap_bake.py.

Game contract: one mesh object per piece at the kit's root, all sharing one baked material (with an emission map:
the ember glow in the housing's well); origin at the bottom center on z = 0, front towards -Y.
"""

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
    "ash",
    {
        "olive": ("paint", K.OLIVE, {"wear": 0.55, "rust": 0.55, "heat_z": (1.6, 3.2)}),
        "gun": ("paint", K.GUNMETAL, {"wear": 0.6, "rust": 0.55, "rough": 0.55, "heat_z": (1.6, 3.2)}),
        "hazard": ("paint", K.AMBER, {"hazard": True, "wear": 0.6}),
        "steel": ("steel", K.STEEL, {"rust": 0.45, "heat": 0.1}),
        "scorch": ("paint", (0.11, 0.1, 0.095), {"wear": 0.3, "rust": 0.3, "rough": 0.8, "heat": 0.15, "grime": 0.8}),
        "ember": ("ember", K.EMBER, {"strength": 2.6, "cells": 3.5}),
    },
)
M = LOOKS
YZ = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0))).to_4x4()  # prism profile in (y, z), extruded along X

R_OUT, CHAMFER = 1.75, 0.55  # the housing's octagon (half width, corner chamfer)
WELL = 0.75  # half width of the open well under the grate
TOP = 3.1
SOCKET = (1.25, 0.0)  # where the riser stood, on the +X side of the top


def octagon(r: float, c: float) -> list:
    return [
        (r, -(r - c)),
        (r, r - c),
        (r - c, r),
        (-(r - c), r),
        (-r, r - c),
        (-r, -(r - c)),
        (-(r - c), -r),
        (r - c, -r),
    ]


def housing() -> None:
    """The heat tap housing: a heavy octagonal plinth, the octagonal body (olive) with gunmetal armor plates front
    and back and fin banks on both sides, a front access hatch, a hazard strip on the plinth; on top an open square
    well under a heat-tinted grate, its walls sooted, dull embers glowing at its bottom; on the +X side of the top
    the riser's socket with the torn stub of the riser."""
    p = K.Piece("Tap_housing", LOOKS, bevel=(0.04, 1))
    rnd = random.Random(71)
    p.prism(octagon(2.0, 0.65), -0.4, 0.35, mi=M["gun"])
    p.prism(octagon(R_OUT, CHAMFER), 0.35, 1.95, mi=M["olive"])
    rm = R_OUT - CHAMFER / 2
    sector = [(WELL, -WELL), (rm, -rm), (R_OUT, -(R_OUT - CHAMFER)), (R_OUT, R_OUT - CHAMFER), (rm, rm), (WELL, WELL)]
    for k in range(4):
        m = rz(90 * k).to_4x4()
        p.prism(sector, 1.95, TOP, m, M["olive"])
        p.prism(
            [(WELL, -WELL), (WELL + 0.12, -WELL - 0.12), (WELL + 0.12, WELL + 0.12), (WELL, WELL)],
            1.7,
            TOP - 0.05,
            m,
            M["scorch"],
        )  # sooted well wall
    rim = (
        [(WELL - 0.04, -WELL + 0.04)] + [(x * 1.035, y * 1.035) for x, y in sector[1:-1]] + [(WELL - 0.04, WELL - 0.04)]
    )
    for k in range(4):
        p.prism(rim, TOP - 0.02, TOP + 0.08, rz(90 * k).to_4x4(), M["gun"])  # top rim
    p.box((0, 0, 1.75), (2 * WELL + 0.2, 2 * WELL + 0.2, 0.3), mi=M["scorch"])
    p.box((0, 0, 1.93), (2 * WELL, 2 * WELL, 0.06), mi=M["ember"])
    for i in range(6):  # grate
        y = -WELL + (i + 0.5) * 2 * WELL / 6
        p.box((0, y, TOP + 0.02), (2 * WELL + 0.2, 0.07, 0.14), mi=M["steel"])
    for x in (-0.3, 0.3):
        p.box((x, 0, TOP + 0.1), (0.07, 2 * WELL + 0.2, 0.08), mi=M["steel"])
    # Armor plates front and back, the hatch, the hazard strip on the plinth.
    for side in (-1, 1):
        p.box((0, side * (R_OUT + 0.04), 1.2), (2.0, 0.1, 1.45), mi=M["gun"])
        for x in (-0.85, 0.85):
            p.box((x, side * (R_OUT + 0.1), 1.2), (0.12, 0.06, 1.3), mi=M["gun"])
    p.box((0.35, -(R_OUT + 0.11), 1.05), (0.8, 0.06, 0.95), mi=M["olive"])
    p.box((-0.1, -(R_OUT + 0.15), 1.05), (0.08, 0.05, 0.25), mi=M["steel"])
    p.box((0, -1.98, 0.22), (1.3, 0.06, 0.16), mi=M["hazard"])
    # Fin banks on both sides, with headers.
    for side in (-1, 1):
        x0 = side * R_OUT
        for i in range(9):
            y = -0.96 + i * 0.24
            p.box((x0 + side * 0.17, y, 1.25), (0.34, 0.045, 1.35), mi=M["steel"])
        for z in (0.52, 1.98):
            p.box((x0 + side * 0.19, 0, z), (0.36, 2.16, 0.12), mi=M["gun"])
    # Riser socket and the torn stub of the riser.
    sx, sy = SOCKET
    p.cyl((sx, sy, TOP + 0.14), 0.5, 0.12, 16, mi=M["gun"])
    for i in range(8):
        a = i / 8 * math.tau
        p.cyl((sx + math.cos(a) * 0.43, sy + math.sin(a) * 0.43, TOP + 0.24), 0.035, 0.1, 6, mi=M["steel"])
    p.pipe((sx, sy, TOP + 0.18), (sx, sy, TOP + 0.75), 0.36, 0.04, M["gun"], M["scorch"], 16, jag1=0.4, rnd=rnd)
    p.finish()


def riser() -> None:
    """The collapsed riser, about 6.4 m: the long lower run lying on the ground with the base flange it tore off
    the socket, cladding bands, broken in two, the short top run lying at an angle beyond the break with the top
    flange; torn, sooted ends."""
    p = K.Piece("Tap_riser", LOOKS, bevel=(0.03, 1))
    rnd = random.Random(81)
    r = 0.36
    a0, a1 = Vector((-3.6, 0.0, r - 0.04)), Vector((0.2, 0.0, r - 0.04))
    p.pipe(a0, a1, r, 0.04, M["gun"], M["scorch"], 16, jag1=0.45, rnd=rnd)
    p.cyl(a0 + Vector((0.05, 0, 0)), 0.52, 0.12, 16, ry(90), M["gun"])
    for i in range(8):
        a = i / 8 * math.tau
        q = a0 + Vector((-0.02, math.cos(a) * 0.44, math.sin(a) * 0.44))
        p.rod(q, q + Vector((-0.12, 0, 0)), 0.03, 6, M["steel"])
    for x in (-2.7, -1.6, -0.5):
        p.cyl((x, 0, r - 0.04), r + 0.035, 0.1, 16, ry(90), M["steel"])
    d = Vector((math.cos(math.radians(24)), math.sin(math.radians(24)), 0.0))
    b0 = Vector((0.55, 0.3, r - 0.06))
    b1 = b0 + d * 2.5
    p.pipe(b0, b1, r, 0.04, M["gun"], M["scorch"], 16, jag0=0.4, rnd=rnd)
    p.cyl(b1 - d * 0.05, 0.5, 0.12, 16, K.C.basis(d, Vector((0, 0, 1))), M["gun"])
    p.cyl(b0 + d * 1.2, r + 0.035, 0.1, 16, K.C.basis(d, Vector((0, 0, 1))), M["steel"])
    # A cladding sheet peeled off the break, lying beside it.
    p.box((0.0, -0.8, 0.04), (0.9, 0.55, 0.03), rz(-20) @ rx(6), M["steel"])
    p.finish(center=True)


def fins() -> None:
    """A loose heat-exchanger fin rack lying on the ground: two header pipes, a frame, a row of fins, the ones at
    one end bent over."""
    p = K.Piece("Tap_fins", LOOKS, bevel=(0.015, 1))
    for y in (-0.6, 0.6):
        p.rod((-1.2, y, 0.11), (1.2, y, 0.11), 0.09, 10, M["steel"])
    for x in (-1.22, 1.22):
        p.box((x, 0, 0.13), (0.08, 1.4, 0.3), mi=M["gun"])
    for i in range(12):
        x = -1.05 + i * 0.19
        tilt = 0.0 if i < 9 else 18.0 + (i - 9) * 10.0
        p.box((x + (0.03 * (i - 8) if i > 8 else 0), 0, 0.16), (0.035, 1.12, 0.3), ry(tilt), M["steel"])
    p.box((0, 0.66, 0.26), (2.4, 0.06, 0.06), mi=M["gun"])
    p.finish()


PIECES = {"Tap_housing": housing, "Tap_riser": riser, "Tap_fins": fins}

# Layout (Blender axes, the part's way in towards +Y): the housing turned so its hatch faces the way in (its socket
# then on the -X side), the riser fallen from it towards the back left, the fin rack off the back right.
LAYOUT = [
    ("Tap_housing", (0.0, 0.0, 0.0), (0.0, 0.0, 180.0), 1.0),
    ("Tap_riser", (-3.9, -2.34, 0.0), (0.0, 0.0, 243.0), 1.0),
    ("Tap_fins", (3.0, -3.5, 0.0), (5.0, -3.0, 28.0), 1.0),
]

KIT = K.Kit(
    name="heat_tap",
    weather="ash",
    pieces=PIECES,
    layout=LAYOUT,
    prop_radius=8.0,
    footprint=12.0,
    crate=((3.3, 3.0), -20.0),
    ores=[(5.8, -0.2), (-3.6, 4.9), (0.2, -5.9)],
    emission=True,
)

if __name__ == "__main__":
    K.main(KIT)
