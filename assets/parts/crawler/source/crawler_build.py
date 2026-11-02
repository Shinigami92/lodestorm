"""Buried crawler (Dust flats point of interest): a colony survey crawler abandoned in a dust storm, half buried in
a drift, its sampling crane folded, a thrown track run and a sample case that fell off lying beside it.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/parts/crawler/source/crawler_build.py wip c1 layout,pieces,sheet
    tools/blender.sh assets/parts/crawler/source/crawler_build.py wip c1 Crawler
    tools/blender.sh assets/parts/crawler/source/crawler_build.py final

Everything it writes goes to tmp/assets/parts/crawler/: "wip <tag> [views]" renders previews into wip/<tag>_*.png
(views: layout, pieces, a piece name, sheet), "final" renders the layout and every piece, writes the contact sheet
sheet.png and saves the procedural crawler_procedural.blend that crawler_bake.py turns into the game asset.

Game contract: one mesh object per piece at the kit's root, all sharing one baked material; origin at the bottom
center on z = 0 (the ground contact), front towards -Y. The crawler is modeled whole (the game sinks and tilts it
into the drift, see LAYOUT); Crawler_drift is the drift itself, a low sand mound to set against its buried side.
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
    "dust",
    {
        "bone": ("paint", K.BONE, {"wear": 0.55, "rust": 0.45, "dust_band": 1.9}),
        "olive": ("paint", K.OLIVE, {"wear": 0.5, "rust": 0.5, "dust_band": 1.0}),
        "gun": ("paint", K.GUNMETAL, {"wear": 0.6, "rust": 0.6, "rough": 0.55, "dust_band": 1.9}),
        "hazard": ("paint", K.AMBER, {"hazard": True, "wear": 0.6, "period": 0.32, "dust_band": 1.7}),
        "steel": ("steel", K.STEEL, {}),
        "track": ("paint", K.TRACK, {"wear": 0.9, "rust": 0.8, "rough": 0.7, "dust_band": 2.0}),
        "glass": ("glass", (0.03, 0.035, 0.04), {"weather": 0.5}),
        "lamp": ("lamp", K.LAMP_RED, {"strength": 6.0}),
        "core": ("paint", (0.27, 0.24, 0.205), {"wear": 0.0, "rust": 0.0, "rough": 0.85, "grime": 0.3}),
        "sand": ("sand", None, {}),
    },
)
M = LOOKS
YZ = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0))).to_4x4()  # prism profile in (y, z), extruded along X


def hull2d(pts: list) -> list:
    """Convex hull of 2D points, counter-clockwise (monotone chain)."""
    pts = sorted(set(pts))

    def half(seq):
        out = []
        for p in seq:
            while (
                len(out) >= 2
                and (out[-1][0] - out[-2][0]) * (p[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0])
                <= 0
            ):
                out.pop()
            out.append(p)
        return out

    lower, upper = half(pts), half(reversed(pts))
    return lower[:-1] + upper[:-1]


def resample(poly: list, step: float) -> list:
    """Points every `step` m along a closed polygon, with the outward normal at each (CCW polygon)."""
    segs = []
    for i, a in enumerate(poly):
        b = poly[(i + 1) % len(poly)]
        segs.append((Vector(a), Vector(b)))
    total = sum((b - a).length for a, b in segs)
    n = max(8, round(total / step))
    out, s, k, acc = [], 0.0, 0, 0.0
    for i in range(n):
        s = i * total / n
        while acc + (segs[k][1] - segs[k][0]).length < s:
            acc += (segs[k][1] - segs[k][0]).length
            k += 1
        a, b = segs[k]
        d = (b - a).normalized()
        out.append((a + d * (s - acc), Vector((d.y, -d.x))))
    return out


# --- pieces -----------------------------------------------------------------------------------------------

TRACK_X = 1.35  # track centers
TRACK_W = 0.85
IDLER = (-3.2, 0.72, 0.55)  # front idler (y, z, r) of the belt's outside
SPROCKET = (3.15, 0.64, 0.62)  # rear sprocket
WHEELS_Y = (-2.2, -1.1, 0.0, 1.1, 2.2)


def track_unit(p: K.Piece, x: float) -> None:
    """One track: a belt loop with grouser teeth (unbevelled), the frame inside it, road wheels, the front idler
    and the rear sprocket."""
    pts = []
    for cy, cz, r in (IDLER, SPROCKET):
        pts += [(cy + math.cos(a / 24 * math.tau) * r, cz + math.sin(a / 24 * math.tau) * r) for a in range(24)]
    pts += [(-2.5, 0.0), (2.4, 0.0)]
    outline = hull2d([(round(a, 4), round(b, 4)) for a, b in pts])
    samples = resample(outline, 0.2)
    thick = 0.14
    x0, x1 = x - TRACK_W / 2, x + TRACK_W / 2
    rings = []
    for i, (q, n) in enumerate(samples):
        tooth = 0.055 if i % 2 == 0 else 0.0
        o = q + n * tooth
        inn = q - n * thick
        rings.append(
            [p.bm.verts.new(v) for v in ((x0, o.x, o.y), (x1, o.x, o.y), (x1, inn.x, inn.y), (x0, inn.x, inn.y))]
        )
    faces = []
    for a, b in zip(rings, rings[1:] + rings[:1]):
        for k in range(4):
            faces.append(p.bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k])))
    for f in faces:
        f.material_index = M["track"]
        f.smooth = True
    p.soft([v for r in rings for v in r])
    # Frame inside the loop, road wheels, idler, sprocket.
    p.box((x, 0.0, 0.78), (TRACK_W - 0.2, 5.8, 0.62), mi=M["gun"])
    for y in WHEELS_Y:
        p.cyl((x, y, 0.41), 0.27, TRACK_W - 0.08, 12, ry(90), M["gun"])
        p.cyl((x, y, 0.41), 0.11, TRACK_W + 0.02, 8, ry(90), M["steel"])
    p.cyl((x, IDLER[0], IDLER[1]), IDLER[2] - thick, TRACK_W - 0.06, 14, ry(90), M["gun"])
    p.cyl((x, SPROCKET[0], SPROCKET[1]), SPROCKET[2] - thick, TRACK_W - 0.06, 14, ry(90), M["gun"])
    p.cyl((x, SPROCKET[0], SPROCKET[1]), 0.2, TRACK_W + 0.04, 10, ry(90), M["steel"])


def crawler() -> None:
    """The survey crawler: two tracks under a full-width deck, the hull between them, a boxy cab at the front with
    dark windows, a light bar, a survey dome and a red beacon on the roof, an equipment block behind the cab with
    the sampling crane's turret, the crane folded back over the cargo bed (boom, folded jib, core drill head), the
    cargo bed with low sides, sample cases and a drum, hazard stripes on the bumper, the bed's rim and the jib."""
    p = K.Piece("Crawler", LOOKS, bevel=(0.04, 1))
    for side in (-1, 1):
        track_unit(p, side * TRACK_X)
    # Hull between the tracks, the deck over them (fenders), the nose and the front bumper.
    p.box((0, 0.1, 0.87), (1.8, 7.0, 0.98), mi=M["gun"])
    p.box((0, 0.0, 1.43), (3.64, 7.9, 0.15), mi=M["gun"])
    p.prism([(-3.4, 0.5), (-3.4, 1.36), (-4.0, 1.36), (-4.0, 0.95)], -0.9, 0.9, YZ, M["gun"])
    p.box((0, -4.0, 0.92), (3.7, 0.2, 0.32), mi=M["hazard"])
    for side in (-1, 1):
        p.box((side * 0.6, -4.12, 0.72), (0.14, 0.18, 0.2), mi=M["steel"])  # tow hooks
        p.box((side * 1.79, 0.0, 1.32), (0.06, 7.7, 0.12), mi=M["bone"])  # fender lip
    # Cab: slanted front, dark windows, roof lip, light bar with dark lenses, survey dome, beacon, exhaust.
    p.prism([(-3.85, 1.5), (-1.45, 1.5), (-1.45, 3.25), (-3.05, 3.25), (-3.85, 2.35)], -1.55, 1.55, YZ, M["bone"])
    p.box((0, -2.25, 3.29), (3.2, 1.75, 0.08), mi=M["bone"])
    a = math.degrees(math.atan2(-0.9, -0.8))  # the slanted front's direction in (y, z)
    mid = Vector((0, (-3.05 - 3.85) / 2, (3.25 + 2.35) / 2))
    n = Vector((0, -0.9, 0.8)).normalized()
    p.box(mid + n * 0.015, (2.7, 0.92, 0.04), rx(a), M["glass"])
    p.box(mid + n * 0.01 + Vector((0, 0.55, -0.62)), (3.0, 0.1, 0.08), rx(a), M["gun"])  # wiper sill
    for side in (-1, 1):
        p.box((side * 1.56, -2.35, 2.72), (0.04, 1.25, 0.62), mi=M["glass"])
        p.box((side * 1.57, -2.35, 2.33), (0.05, 1.4, 0.07), mi=M["gun"])
        p.box((side * 1.57, -1.6, 2.0), (0.05, 0.05, 0.5), mi=M["steel"])  # grab handle
    p.box((0, -3.0, 3.42), (2.4, 0.18, 0.18), mi=M["gun"])
    for x in (-0.85, -0.3, 0.3, 0.85):
        p.box((x, -3.1, 3.42), (0.26, 0.04, 0.11), mi=M["glass"])
    p.sphere((-0.75, -2.0, 3.33), 0.3, 12, 6, scale=(1, 1, 0.8), mi=M["bone"])
    p.cyl((-0.75, -2.0, 3.36), 0.32, 0.06, 12, mi=M["gun"])
    p.cyl((0.95, -1.75, 3.39), 0.1, 0.1, 10, mi=M["gun"])
    p.cyl((0.95, -1.75, 3.5), 0.085, 0.13, 10, mi=M["lamp"])
    p.rod((1.42, -1.3, 1.5), (1.42, -1.3, 3.35), 0.075, 10, M["gun"])
    p.cyl((1.42, -1.3, 3.38), 0.1, 0.06, 10, mi=M["steel"])
    # Equipment block behind the cab with a vent grille, the crane turret on it.
    p.box((0, -0.92, 1.92), (3.0, 1.05, 0.84), mi=M["gun"])
    for i in range(4):
        p.box((-0.75, -0.6 + i * 0.0, 1.7 + i * 0.13), (1.0, 0.06, 0.06), rx(-30), M["steel"])
    p.cyl((0.85, -0.9, 2.5), 0.48, 0.32, 16, mi=M["bone"])
    p.cyl((0.85, -0.9, 2.72), 0.32, 0.14, 12, mi=M["gun"])
    # Crane: boom back to a rest post at the rear, the jib folded forward on top of it, the core drill head.
    p.box((0.85, -0.55, 2.82), (0.5, 0.5, 0.36), mi=M["gun"])
    p.beam((0.85, -0.5, 2.82), (0.85, 3.45, 2.42), 0.34, 0.34, (1, 0, 0), M["bone"])
    p.rod((0.85, -0.4, 2.55), (0.85, 1.6, 2.5), 0.07, 8, M["steel"])  # hydraulic ram
    p.rod((0.85, -0.4, 2.55), (0.85, 0.5, 2.53), 0.11, 8, M["gun"])
    p.cyl((0.85, 3.45, 2.52), 0.24, 0.5, 14, ry(90), M["gun"])  # elbow
    p.beam((0.85, 3.4, 2.75), (0.85, 0.55, 2.78), 0.26, 0.26, (1, 0, 0), M["bone"])
    p.box((0.85, 0.85, 2.78), (0.3, 0.6, 0.3), mi=M["hazard"])
    p.cyl((0.85, 0.45, 2.52), 0.2, 0.42, 12, mi=M["gun"])  # drill head housing
    p.cyl((0.85, 0.45, 2.04), 0.11, 0.56, 10, mi=M["steel"])  # core barrel
    for x in (0.6, 1.1):
        p.box((x, 3.55, 1.9), (0.12, 0.12, 0.8), mi=M["gun"])  # rest post
    p.box((0.85, 3.55, 2.27), (0.7, 0.16, 0.1), mi=M["gun"])
    # Cargo bed: low sides and corner posts, hazard rim at the tail, red marker lights, cases, a drum.
    for side in (-1, 1):
        p.box((side * 1.76, 1.75, 1.75), (0.1, 4.2, 0.5), mi=M["olive"])
        p.box((side * 1.74, 3.86, 1.8), (0.16, 0.16, 0.62), mi=M["gun"])
        p.box((side * 1.74, -0.35, 1.8), (0.16, 0.16, 0.62), mi=M["gun"])
        p.box((side * 1.5, 3.95, 1.68), (0.22, 0.04, 0.1), mi=M["lamp"])
    p.box((0, 3.86, 1.7), (3.4, 0.1, 0.4), mi=M["olive"])
    p.box((0, 3.88, 2.0), (3.6, 0.14, 0.12), mi=M["hazard"])
    p.box((-0.95, 0.75, 1.73), (0.95, 0.62, 0.46), rz(4), M["olive"])
    p.box((-0.95, 0.75, 1.97), (0.97, 0.64, 0.04), rz(4), M["gun"])
    p.box((-1.0, 1.7, 1.73), (0.95, 0.62, 0.46), rz(-3), M["olive"])
    p.box((0.0, 1.3, 1.65), (0.62, 0.95, 0.3), rz(80), M["gun"])
    p.cyl((-0.95, 2.95, 1.92), 0.3, 0.85, 14, mi=M["olive"])
    p.cyl((-0.95, 2.95, 2.36), 0.31, 0.04, 14, mi=M["gun"])
    # Tail: hitch and steps.
    p.box((0, 4.02, 0.85), (0.5, 0.25, 0.3), mi=M["gun"])
    p.finish()


def track_run() -> None:
    """A thrown track run: about 5.5 m of track links lying in a curve, its end curled up over itself."""
    p = K.Piece("Crawler_track", LOOKS, bevel=(0.015, 1))
    rnd = random.Random(21)
    pitch = 0.27
    # Ground run: a gentle curve in XY, then the end curled up and back over in a vertical loop.
    path = []
    for i in range(19):
        t = i / 18
        x = -2.6 + 4.6 * t
        y = 0.55 * math.sin(t * math.pi * 0.9) - 0.25
        path.append((Vector((x, y, 0.035)), None))
    end, prev = path[-1][0], path[-2][0]
    d = (end - prev).normalized()
    for k in range(1, 8):
        ang = k / 8 * math.pi * 0.95
        q = end + d * math.sin(ang) * 0.42 + Vector((0, 0, (1 - math.cos(ang)) * 0.42))
        path.append((q, ang))
    for i, (q, ang) in enumerate(path):
        nxt = path[min(i + 1, len(path) - 1)][0]
        prv = path[max(i - 1, 0)][0]
        tan = (nxt - prv).normalized()
        up = Vector((0, 0, 1)) if ang is None else Vector((-d.x * math.sin(ang), -d.y * math.sin(ang), math.cos(ang)))
        side = up.cross(tan).normalized()
        up = tan.cross(side).normalized()
        rot = Matrix((side, tan, up)).transposed() @ rz(rnd.uniform(-2, 2)) @ rx(rnd.uniform(-3, 3))
        p.soft(p.box(q, (TRACK_W, pitch - 0.035, 0.06), rot, M["track"]))
        p.box(q + up * 0.05, (TRACK_W - 0.04, 0.06, 0.05), rot, M["track"])
    p.finish()


def sample_case() -> None:
    """A survey sample case that fell off the bed: a ribbed hard case with latches and a handle, three rock cores
    spilled beside it."""
    p = K.Piece("Crawler_crate", LOOKS, bevel=(0.02, 1))
    p.box((0, 0, 0.21), (0.95, 0.6, 0.42), mi=M["olive"])
    p.box((0, 0, 0.32), (0.97, 0.62, 0.04), mi=M["gun"])
    for x in (-0.3, 0.3):
        p.box((x, -0.31, 0.3), (0.08, 0.03, 0.12), mi=M["steel"])
        p.box((x, 0, 0.21), (0.05, 0.63, 0.43), mi=M["olive"])
    p.rod((-0.18, 0, 0.47), (0.18, 0, 0.47), 0.025, 6, M["gun"])
    for x in (-0.2, 0.2):
        p.box((x, 0, 0.44), (0.04, 0.05, 0.06), mi=M["gun"])
    for (x, y), yaw, ln in (((0.85, -0.25), 15, 0.55), ((0.72, 0.2), -20, 0.42), ((-0.75, 0.45), 70, 0.5)):
        dvec = Vector((math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0)) * ln / 2
        c = Vector((x, y, 0.045))
        p.rod(c - dvec, c + dvec, 0.048, 8, M["core"])
    p.finish()


def drift() -> None:
    """The dust drift the crawler sank into: a low sand mound (8.6 x 3.6 m, 1.1 m high), its crest towards +X
    (the vehicle's buried side, which it runs into), a smooth fall to -X, a skirt below the ground."""
    p = K.Piece("Crawler_drift", LOOKS, bevel=(0.01, 1))
    rnd = random.Random(5)
    nx, ny = 14, 24
    x0, x1, y0, y1 = -2.4, 1.2, -4.3, 4.3
    phase = rnd.uniform(0, 6)

    def h(x: float, y: float) -> float:
        u = (y - y0) / (y1 - y0)
        fy = math.sin(math.pi * u) ** 0.6
        crest = 0.45 + 0.15 * math.sin(u * 5 + phase)
        fx = (x - x0) / (crest - x0) if x < crest else 1 - (x - crest) / (x1 - crest) * 0.35
        fx = max(0.0, min(1.0, fx))
        fx = fx * fx * (3 - 2 * fx)
        return 1.1 * fx * fy * (0.85 + 0.15 * math.sin(u * 11 + phase * 2))

    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            y = y0 + (y1 - y0) * j / ny
            edge = i in (0, nx) or j in (0, ny)
            row.append(p.bm.verts.new((x, y, -0.3 if edge else h(x, y))))
        grid.append(row)
    faces = []
    for j in range(ny):
        for i in range(nx):
            faces.append(p.bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])))
    for f in faces:
        f.material_index = M["sand"]
        f.smooth = True
    p.soft([v for r in grid for v in r])
    p.finish()


PIECES = {"Crawler": crawler, "Crawler_track": track_run, "Crawler_crate": sample_case, "Crawler_drift": drift}

# The part (Blender axes, way in towards +Y): the crawler sunk 0.8 m, nose down and rolled onto its left side
# (left track buried), the drift along that side, the thrown track behind on the right, the case off the tail.
YAW = 28.0


def _at(local, yaw: float = YAW, origin=(0.3, -0.6)) -> tuple[float, float]:
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return (origin[0] + local[0] * c - local[1] * s, origin[1] + local[0] * s + local[1] * c)


LAYOUT = [
    ("Crawler", (0.3, -0.6, -0.8), (3.0, -6.0, YAW), 1.0),
    ("Crawler_drift", (*_at((-1.75, 0.0)), 0.0), (0.0, 0.0, YAW), 1.0),
    ("Crawler_track", (*_at((3.5, 1.0)), 0.0), (0.0, 0.0, YAW + 18), 1.0),
    ("Crawler_crate", (*_at((1.2, 5.6)), 0.0), (0.0, 0.0, YAW + 64), 1.0),
]

KIT = K.Kit(
    name="crawler",
    weather="dust",
    pieces=PIECES,
    layout=LAYOUT,
    prop_radius=8.0,
    footprint=12.0,
    crate=((3.7, -3.6), 20.0),
    ores=[(-5.6, -1.6), (6.0, -0.9), (2.2, 6.0)],
    emission=True,
)

if __name__ == "__main__":
    K.main(KIT)
