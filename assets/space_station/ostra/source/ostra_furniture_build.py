"""Waypost Ostra's furniture, one model each: the supply depot's counter and pallet racking, the council's table and
chairs, the bar (counter, back bar, wall rack of bottles, booths, stools), the concourse's market stalls (parts,
barter, Dace's), Dace's workbench, the suit technician's bench and gantry, the gallery's bench and the hub's
information kiosk. Worn, heavy industrial pieces; detail is geometry (bevels, panels, ribs, bolts, cables).

The materials are placeholders named for the game (Ostra*, see the table below); OstraLook
(game/space_station/ostra_look.gd) swaps in the station's materials by name.

Run from the repo root:
    tools/blender.sh assets/space_station/ostra/source/ostra_furniture_build.py              all models
    tools/blender.sh assets/space_station/ostra/source/ostra_furniture_build.py booth kiosk  only these

Writes assets/space_station/ostra/props/<name>.glb (an asset root empty per model, named in PascalCase after it);
previews (iso, about 35 degrees down, and eye level) and a contact sheet of all of them go to tmp/ostra_furniture/.

Coordinates here are Godot's (x right, y up, z front = towards the camera, meters); g() turns them into Blender's
(x, -z, y). Each model's front, where people stand to use it, faces +z; its origin is the floor at the footprint's
center (the wall rack's is the floor below the middle of its back edge). Sizes are the game's collision boxes.
"""

import itertools
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
PROPS = ROOT / "assets" / "space_station" / "ostra" / "props"
TMP = ROOT / "tmp" / "ostra_furniture"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C

# name: (base color, roughness, metallic, transmission, emission strength); the emission takes the base color
MATERIALS = {
    "OstraPaint": ((0.40, 0.38, 0.34), 0.6, 0.0, 0.0, 0.0),
    "OstraPaintDark": ((0.10, 0.10, 0.10), 0.55, 0.0, 0.0, 0.0),
    "OstraMetal": ((0.5, 0.5, 0.5), 0.4, 1.0, 0.0, 0.0),
    "OstraFloor": ((0.22, 0.22, 0.22), 0.5, 0.0, 0.0, 0.0),
    "OstraGrating": ((0.3, 0.3, 0.3), 0.45, 1.0, 0.0, 0.0),
    "OstraHazard": ((0.8, 0.6, 0.1), 0.6, 0.0, 0.0, 0.0),
    "OstraRubber": ((0.03, 0.03, 0.03), 0.8, 0.0, 0.0, 0.0),
    "OstraFabric": ((0.2, 0.12, 0.08), 0.75, 0.0, 0.0, 0.0),
    "OstraWood": ((0.3, 0.18, 0.1), 0.45, 0.0, 0.0, 0.0),
    "OstraCanvas": ((0.33, 0.29, 0.21), 0.9, 0.0, 0.0, 0.0),
    "OstraGlass": ((0.6, 0.7, 0.75), 0.05, 0.0, 1.0, 0.0),
    "OstraBottle": ((0.25, 0.12, 0.04), 0.15, 0.0, 0.5, 0.0),
    "OstraScreen": ((0.2, 0.9, 0.85), 0.3, 0.0, 0.0, 3.0),
    "OstraLamp": ((1.0, 0.8, 0.55), 0.3, 0.0, 0.0, 6.0),
    "OstraAmber": ((1.0, 0.55, 0.12), 0.3, 0.0, 0.0, 4.0),
    "OstraRed": ((1.0, 0.1, 0.05), 0.3, 0.0, 0.0, 4.0),
    "OstraPlant": ((0.12, 0.3, 0.08), 0.7, 0.0, 0.0, 0.0),
    "OstraOrange": ((0.75, 0.3, 0.05), 0.5, 0.0, 0.0, 0.0),
    "OstraContainerRed": ((0.35, 0.1, 0.07), 0.6, 0.0, 0.0, 0.0),
    "OstraContainerBlue": ((0.12, 0.2, 0.3), 0.6, 0.0, 0.0, 0.0),
    "OstraContainerOlive": ((0.25, 0.27, 0.15), 0.6, 0.0, 0.0, 0.0),
}
CRATES = ("OstraContainerOlive", "OstraContainerRed", "OstraContainerBlue", "OstraPaint")


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    color, roughness, metallic, transmission, emission = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Transmission Weight"].default_value = transmission
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


# --- Godot-axes mesh kit ----------------------------------------------------------------------------


def g(p) -> Vector:
    """Godot point or direction -> Blender."""
    return Vector((p[0], -p[2], p[1]))


def gs(s) -> tuple:
    """Godot size (x, y, z) -> Blender size."""
    return (s[0], s[2], s[1])


AXIS = {"y": None, "x": C.ry(90), "z": C.rx(90)}  # local +Z of a cylinder -> Godot +y / +x / +z
X_PROFILE = Matrix(((0, 0, 1, 0), (-1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # local (z, y, x) -> Blender
Z_PROFILE = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # local (x, y, z) -> Blender


class Kit:
    """Two C.Part meshes per model: "Body" with bevelled edges (the chunky shapes) and "Detail" without (small
    parts, glass, lamps). All coordinates and sizes in Godot axes; materials by name."""

    def __init__(self, name: str, bevel: float = 0.012):
        self.parts = {True: C.Part(name + "Body", [], (bevel, 2)), False: C.Part(name + "Detail", [], None)}

    def _part(self, mat: str, bev: bool):
        part = self.parts[bev]
        m = material(mat)
        if m not in part.mats:
            part.mats.append(m)
        return part, part.mats.index(m)

    def box(self, c, s, mat, bev=True, rot=None, off=(0, 0, 0)):
        """Box of size s at c; with rot (a Blender 3x3), off is a Godot-axes offset in the rotated frame."""
        part, mi = self._part(mat, bev)
        loc = g(c) if rot is None else g(c) + rot @ g(off)
        return part.box(loc, gs(s), rot, mi)

    def cyl(self, c, r, length, mat, axis="y", seg=16, r2=None, bev=False, rot=None):
        part, mi = self._part(mat, bev)
        return part.cyl(g(c), r, length, seg, rot=rot if rot is not None else AXIS[axis], mi=mi, r2=r2)

    def rod(self, p0, p1, r, mat, seg=8, r2=None, bev=False):
        part, mi = self._part(mat, bev)
        return part.rod(g(p0), g(p1), r, seg, mi, r2)

    def path(self, pts, r, mat, seg=6):
        for a, b in itertools.pairwise(pts):
            self.rod(a, b, r, mat, seg)

    def beam(self, p0, p1, w, h, side, mat, bev=False):
        part, mi = self._part(mat, bev)
        return part.beam(g(p0), g(p1), w, h, g(side), mi)

    def sphere(self, c, r, mat, scale=(1, 1, 1), seg=12, rings=6, rot=None, bev=False):
        part, mi = self._part(mat, bev)
        return part.sphere(g(c), r, seg, rings, gs(scale), rot, mi)

    def lump(self, base, size, mat, rnd, seg=10, turn=0.0):
        """A sack, rag or bundle: a jittered round pillow of `size` resting on `base` with a flat bottom."""
        part, mi = self._part(mat, False)
        center = g((base[0], base[1] + size[1] * 0.42, base[2]))
        verts = part.sphere(center, 0.5, seg, max(4, seg // 2 + 1), gs(size), C.rz(turn), mi)
        floor = base[1]
        for v in verts:
            v.co += (v.co - center) * rnd.uniform(-0.06, 0.08)
            v.co.z = max(v.co.z, floor)
        return part._tag(verts, mi, smooth=True)

    def torus(self, c, big, small, mat, axis="y", seg=24, tseg=6, rot=None):
        part, mi = self._part(mat, False)
        m = C.T(g(c), rot if rot is not None else AXIS[axis])
        bm = part.bm
        rings = []
        for i in range(seg):
            a = math.tau * i / seg
            ring = []
            for j in range(tseg):
                b = math.tau * j / tseg
                rr = big + small * math.cos(b)
                ring.append(bm.verts.new(m @ Vector((rr * math.cos(a), rr * math.sin(a), small * math.sin(b)))))
            rings.append(ring)
        for i in range(seg):
            r0, r1 = rings[i], rings[(i + 1) % seg]
            for j in range(tseg):
                bm.faces.new((r0[j], r1[j], r1[(j + 1) % tseg], r0[(j + 1) % tseg])).normal_update()
        return part._tag([v for r in rings for v in r], mi)

    def lathe(self, c, profile, mat, seg=12, bev=False, rot=None):
        """Round shape turned about the vertical axis (or rot's): profile (radius, height) pairs, bottom to top,
        closed at both ends."""
        part, mi = self._part(mat, bev)
        m = C.T(g(c), rot)
        bm = part.bm
        angles = [math.tau * i / seg for i in range(seg)]
        rings = [[bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), y))) for a in angles] for r, y in profile]
        faces = []
        for lo, hi in itertools.pairwise(rings):
            for i in range(seg):
                faces.append(bm.faces.new((lo[i], lo[(i + 1) % seg], hi[(i + 1) % seg], hi[i])))
        faces.append(bm.faces.new(list(reversed(rings[0]))))
        faces.append(bm.faces.new(rings[-1]))
        for f in faces:
            f.normal_update()
        return part._tag([v for r in rings for v in r], mi)

    def _prism(self, pts, w0, w1, m4, mat, bev):
        part, mi = self._part(mat, bev)
        area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
        if (area < 0) != (m4.to_3x3().determinant() < 0):
            pts = pts[::-1]
        return part.prism(pts, w0, w1, m4, mi)

    def prism_y(self, pts_xz, y0, y1, mat, bev=True):
        """Polygon in the floor plane (x, z), extruded upwards from y0 to y1."""
        return self._prism([(x, -z) for x, z in pts_xz], y0, y1, Matrix.Identity(4), mat, bev)

    def prism_x(self, pts_zy, x0, x1, mat, bev=True):
        """Profile in the (z, y) plane, extruded along x."""
        return self._prism(list(pts_zy), x0, x1, X_PROFILE, mat, bev)

    def prism_z(self, pts_xy, z0, z1, mat, bev=True):
        """Profile in the (x, y) plane, extruded along z."""
        return self._prism(list(pts_xy), z0, z1, Z_PROFILE, mat, bev)

    def sheet(self, fn, nu, nv, mat, thickness=0.015):
        """A thin solid sheet (canvas) through the points fn(u, v), u and v in [0, 1]."""
        part, mi = self._part(mat, False)
        bm = part.bm
        grid = [[bm.verts.new(g(fn(i / nu, j / nv))) for i in range(nu + 1)] for j in range(nv + 1)]
        faces = [
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for j in range(nv)
            for i in range(nu)
        ]
        for f in faces:
            f.normal_update()
        geom = bmesh.ops.solidify(bm, geom=faces, thickness=thickness)["geom"]
        verts = {v for f in faces for v in f.verts} | {e for e in geom if isinstance(e, bmesh.types.BMVert)}
        bmesh.ops.recalc_face_normals(bm, faces=list({f for v in verts for f in v.link_faces}))
        return part._tag(list(verts), mi)

    def finish(self, root) -> None:
        for bev, part in self.parts.items():
            if not part.bm.verts:
                part.bm.free()
                continue
            part.bm.normal_update()
            if not bev:  # flat-looking hard edges on the unbevelled parts
                for e in part.bm.edges:
                    if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(40):
                        e.smooth = False
            part.finish(root)


# --- shared small things -----------------------------------------------------------------------------


def rrect(w, d, r, seg=4):
    """Rounded rectangle in the floor plane: (x, z) points around the origin."""
    pts = []
    corners = (
        (w / 2 - r, d / 2 - r, 0),
        (r - w / 2, d / 2 - r, 90),
        (r - w / 2, r - d / 2, 180),
        (w / 2 - r, r - d / 2, 270),
    )
    for cx, cz, a0 in corners:
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


BOTTLE_SHAPES = {  # shoulder start, neck start (fractions of the height), neck radius (fraction of the radius)
    "wine": (0.6, 0.78, 0.34),
    "liquor": (0.68, 0.8, 0.42),
    "squat": (0.5, 0.68, 0.32),
    "flask": (0.76, 0.86, 0.45),
}


def bottle(k, x, y, z, h, r, mat="OstraBottle", shape="wine", seg=8):
    sh, nk, nr = BOTTLE_SHAPES[shape]
    k.lathe((x, y, z), [(r, 0), (r, h * sh), (r * nr, h * nk), (r * nr, h)], mat, seg)


def glass(k, x, y, z, r=0.034, h=0.11):
    k.lathe((x, y, z), [(r * 0.8, 0), (r, h)], "OstraGlass", 8)


def bolts(k, pts, size=0.025, depth=0.012, mat="OstraMetal"):
    """Bolt heads on a face looking +z."""
    for p in pts:
        k.box(p, (size, size, depth), mat, bev=False)


def gear(k, c, r, t, mat="OstraMetal", axis="y", teeth=10):
    """A spur gear lying flat (axis y) or standing with its face to the front (axis z)."""
    k.cyl(c, r, t, mat, axis=axis, seg=16)
    k.cyl(c, r * 0.35, t * 1.5, "OstraPaintDark", axis=axis, seg=8)
    tl, tw = r * 0.22, r * 2.6 / teeth
    for i in range(teeth):
        a = 360 * i / teeth
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        if axis == "y":
            k.box((c[0] + ca * r, c[1], c[2] + sa * r), (tl, t, tw), mat, bev=False, rot=C.rz(-a))
        else:
            k.box((c[0] + ca * r, c[1] + sa * r, c[2]), (tl, tw, t), mat, bev=False, rot=C.ry(-a))


def valve(k, c, r=0.08, mat="OstraContainerRed"):
    """A pipe valve standing on c: flanged body, stem and a handwheel facing up."""
    x, y, z = c
    k.cyl((x, y + 0.05, z), 0.045, 0.22, "OstraMetal", axis="x", seg=10)
    for dx in (-0.1, 0.1):
        k.cyl((x + dx, y + 0.05, z), 0.06, 0.02, "OstraMetal", axis="x", seg=10)
    k.cyl((x, y + 0.08, z), 0.05, 0.08, "OstraPaintDark", seg=10)
    k.cyl((x, y + 0.16, z), 0.012, 0.1, "OstraMetal", seg=6)
    k.torus((x, y + 0.2, z), r, 0.01, mat, seg=14, tseg=4)
    for a in (0, 120, 240):
        p = (x + math.cos(math.radians(a)) * r, y + 0.2, z + math.sin(math.radians(a)) * r)
        k.rod((x, y + 0.2, z), p, 0.007, mat, seg=4)


def wrench(k, c, length, mat="OstraMetal", hanging=True, turn=0.0):
    """A flat open-ended wrench: hanging on a board (in the x-y plane) or lying on a top (turned about y)."""
    x, y, z = c
    if hanging:
        k.box((x, y, z), (0.025, length, 0.008), mat, bev=False)
        k.box((x, y - length / 2, z), (0.055, 0.045, 0.01), mat, bev=False)
        k.box((x, y + length / 2, z), (0.05, 0.035, 0.01), mat, bev=False)
    else:
        rot = C.rz(turn)
        k.box((x, y + 0.004, z), (length, 0.008, 0.025), mat, bev=False, rot=rot)
        k.box((x, y + 0.005, z), (0.045, 0.01, 0.055), mat, bev=False, rot=rot, off=(length / 2, 0, 0))
        k.box((x, y + 0.005, z), (0.035, 0.01, 0.05), mat, bev=False, rot=rot, off=(-length / 2, 0, 0))


def hammer(k, c, hanging=True, turn=0.0):
    x, y, z = c
    if hanging:
        k.box((x, y, z), (0.03, 0.3, 0.02), "OstraWood", bev=False)
        k.box((x, y + 0.16, z), (0.12, 0.04, 0.035), "OstraPaintDark", bev=False)
    else:
        rot = C.rz(turn)
        k.box((x, y + 0.015, z), (0.3, 0.025, 0.03), "OstraWood", bev=False, rot=rot)
        k.box((x, y + 0.02, z), (0.04, 0.04, 0.12), "OstraPaintDark", bev=False, rot=rot, off=(0.16, 0, 0))


def screwdriver(k, p0, p1, handle="OstraOrange"):
    p0, p1 = Vector(p0), Vector(p1)
    mid = p0.lerp(p1, 0.45)
    k.rod(p0, mid, 0.014, handle, seg=6)
    k.rod(mid, p1, 0.004, "OstraMetal", seg=4)


def screen_unit(k, c, size, mat_case="OstraPaintDark", tilt=20.0, turn=0.0):
    """A monitor housing tilted back by `tilt` degrees, turned about y, its teal screen to the front."""
    rot = C.rz(turn) @ C.rx(-tilt)
    w, h, d = size
    k.box(c, (w, h, d), mat_case, rot=rot)
    k.box(c, (w - 0.06, h - 0.06, 0.01), "OstraScreen", bev=False, rot=rot, off=(0, 0, d / 2 + 0.002))


# --- supply depot ------------------------------------------------------------------------------------


def depot_counter(k: Kit) -> None:
    """Heavy steel service counter, 6.0 x 1.1 x 0.9; the top's middle 3.4 m stays clear for the ore hoppers."""
    k.box((0, 0.06, -0.02), (5.86, 0.12, 0.76), "OstraPaintDark")  # plinth, toe recess at the front
    k.box((0, 0.065, 0.366), (5.76, 0.09, 0.012), "OstraRubber", bev=False)  # kick plate
    k.box((0, 0.57, 0), (5.8, 0.9, 0.84), "OstraPaint")  # body
    for s in (-1, 1):  # heavy end caps with a steel corner guard and a vent
        k.box((s * 2.95, 0.55, 0), (0.1, 1.0, 0.88), "OstraPaintDark")
        k.box((s * 2.975, 0.55, 0.42), (0.06, 0.96, 0.05), "OstraMetal")
        k.box((s * 3.0, 0.55, -0.05), (0.012, 0.36, 0.5), "OstraGrating", bev=False)
    for x in (-1.475, 0.0, 1.475):  # pilasters
        k.box((x, 0.57, 0.43), (0.1, 0.9, 0.04), "OstraPaintDark")
    for cx in (-2.2125, -0.7375, 0.7375, 2.2125):  # raised front panels, plain for the game's text plates
        k.box((cx, 0.56, 0.425), (1.24, 0.6, 0.02), "OstraPaint")
        bolts(k, [(cx + dx * 0.58, 0.56 + dy * 0.26, 0.438) for dx in (-1, 1) for dy in (-1, 1)])
    k.box((0, 0.19, 0.426), (5.8, 0.05, 0.014), "OstraHazard", bev=False)
    k.box((0, 0.985, 0.43), (5.8, 0.05, 0.04), "OstraPaintDark")  # lip under the top
    # The top: dark steel slab, flat at 1.1, with a worn bare-steel nose bar along the front.
    k.box((0, 1.06, -0.03), (6.0, 0.08, 0.84), "OstraPaintDark")
    k.box((0, 1.06, 0.42), (6.0, 0.08, 0.06), "OstraMetal")
    for s in (-1, 1):  # bare wear plates at the ends where crates get dragged
        k.box((s * 2.55, 1.102, 0.05), (0.7, 0.006, 0.6), "OstraMetal", bev=False)
    # Terminal at the +x end: a small tilted housing with a teal screen, facing the customer.
    k.box((2.55, 1.125, -0.15), (0.32, 0.05, 0.24), "OstraPaintDark")
    k.box((2.55, 1.2, -0.17), (0.07, 0.12, 0.06), "OstraMetal", bev=False)
    screen_unit(k, (2.55, 1.34, -0.15), (0.44, 0.28, 0.07), tilt=18)
    k.box((2.55, 1.13, 0.16), (0.24, 0.04, 0.14), "OstraPaint", rot=C.rx(-8))  # keypad
    k.box((2.47, 1.155, 0.16), (0.03, 0.01, 0.03), "OstraAmber", bev=False)
    # Weighing plate at the -x end with its readout.
    k.box((-2.45, 1.105, 0.06), (0.56, 0.012, 0.46), "OstraRubber", bev=False)
    k.box((-2.45, 1.125, 0.06), (0.6, 0.03, 0.5), "OstraMetal")
    k.rod((-2.45, 1.1, -0.33), (-2.45, 1.3, -0.33), 0.018, "OstraMetal")
    k.box((-2.45, 1.34, -0.33), (0.24, 0.12, 0.07), "OstraPaintDark", rot=C.rx(-10))
    k.box((-2.45, 1.34, -0.33), (0.16, 0.04, 0.01), "OstraAmber", bev=False, rot=C.rx(-10), off=(0, 0.01, 0.037))
    # Clerk's side: drawers, cabinet doors, a cable conduit.
    for cx in (-2.2, -0.74, 0.74, 2.2):
        k.box((cx, 0.78, -0.425), (1.2, 0.3, 0.02), "OstraPaint")
        k.box((cx, 0.8, -0.44), (0.3, 0.03, 0.02), "OstraMetal", bev=False)
        k.box((cx, 0.38, -0.425), (1.2, 0.42, 0.02), "OstraPaint")
        k.box((cx + 0.52, 0.42, -0.44), (0.03, 0.18, 0.02), "OstraMetal", bev=False)
    k.rod((-2.88, 0.2, -0.44), (2.88, 0.2, -0.44), 0.025, "OstraRubber")
    k.path([(2.55, 1.1, -0.3), (2.55, 1.06, -0.46), (2.7, 0.3, -0.46), (2.88, 0.2, -0.44)], 0.012, "OstraRubber")


def _crate(k, rnd, cx, y, w, hmax, cz=0.0, d=None, stack=True):
    h = rnd.uniform(0.38, min(0.78, hmax))
    d = d or rnd.uniform(0.7, 0.95)
    mat = rnd.choice(CRATES)
    k.box((cx, y + h / 2, cz), (w - 0.04, h, d), mat)
    k.box((cx, y + h - 0.025, cz), (w, 0.05, d + 0.02), "OstraPaintDark", bev=False)  # lid rim
    for sx in (-1, 1):  # straps on the front
        k.box((cx + sx * w * 0.3, y + h / 2, cz + d / 2 + 0.002), (0.04, h - 0.06, 0.012), "OstraPaintDark", bev=False)
    if stack and h + 0.3 < hmax and rnd.random() < 0.6:
        w2 = w * rnd.uniform(0.55, 0.8)
        _crate(k, rnd, cx + rnd.uniform(-0.05, 0.05), y + h, w2, hmax - h, cz, d * 0.8, stack=False)


def _canisters(k, rnd, cx, y, w, hmax):
    n = max(1, int(w / 0.3))
    r = w / n / 2 - 0.02
    h = rnd.uniform(0.42, min(0.72, hmax))
    mat = rnd.choice(("OstraContainerBlue", "OstraHazard", "OstraOrange", "OstraPaint"))
    for i in range(n):
        x = cx - w / 2 + (i + 0.5) * w / n
        for z in (-0.23, 0.23):
            k.cyl((x, y + h / 2, z), r, h, mat, seg=12)
            k.cyl((x, y + h + 0.01, z), r * 0.75, 0.02, "OstraPaintDark", seg=12)
            k.cyl((x + r * 0.4, y + h + 0.03, z), r * 0.18, 0.04, "OstraPaintDark", seg=6)


def _sacks(k, rnd, cx, y, w, hmax):
    n = max(1, round(w / 0.4))
    for i in range(n):
        x = cx - w / 2 + (i + 0.5) * w / n
        for z in (-0.22, 0.22):
            k.lump((x, y, z), (w / n * 0.98, 0.24, 0.5), "OstraCanvas", rnd, turn=rnd.uniform(-10, 10))
    if hmax > 0.6:
        for i in range(max(1, n - 1)):
            x = cx + (i - (n - 2) / 2) * w / n
            k.lump(
                (x, y + 0.2, rnd.uniform(-0.1, 0.1)), (w / n, 0.24, 0.6), "OstraCanvas", rnd, turn=rnd.uniform(-20, 20)
            )


def _boxes(k, rnd, cx, y, w, hmax):
    k.box((cx, y + 0.06, 0), (w, 0.12, 0.92), "OstraWood")  # pallet
    for x in (cx - w / 2 + 0.08, cx, cx + w / 2 - 0.08):
        k.box((x, y + 0.06, 0.462), (0.1, 0.12, 0.01), "OstraPaintDark", bev=False)  # pallet's runner ends
    layers = rnd.randint(1, max(1, int((hmax - 0.15) / 0.3)))
    for layer in range(layers):
        for sx in (-1, 1):
            for sz in (-1, 1):
                if layer == layers - 1 and rnd.random() < 0.3:
                    continue
                bh = rnd.uniform(0.24, 0.3)
                k.box(
                    (cx + sx * w / 4, y + 0.12 + layer * 0.3 + bh / 2, sz * 0.22),
                    (w / 2 - 0.03, bh, 0.42),
                    "OstraCanvas",
                )


def depot_shelf(k: Kit) -> None:
    """Pallet racking, 5.0 x 3.5 x 1.2: three levels of crates, canisters, sacks and boxes, open front and back."""
    rnd = random.Random(11)
    for x in (-2.42, 0.0, 2.42):  # end frames: posts, rungs and zig-zag bracing
        for z in (-0.53, 0.53):
            k.box((x, 1.75, z), (0.09, 3.5, 0.08), "OstraPaintDark")
            k.box((x, 0.01, z), (0.16, 0.02, 0.16), "OstraMetal", bev=False)
        for y in (0.06, 3.44):
            k.box((x, y, 0), (0.06, 0.05, 1.0), "OstraPaintDark", bev=False)
        ys = (0.1, 0.95, 1.8, 2.65, 3.4)
        for i in range(len(ys) - 1):
            za, zb = (-0.5, 0.5) if i % 2 == 0 else (0.5, -0.5)
            k.beam((x, ys[i], za), (x, ys[i + 1], zb), 0.04, 0.035, (1, 0, 0), "OstraPaintDark")
    for x0, x1 in ((-2.37, -0.05), (0.05, 2.37)):
        cx = (x0 + x1) / 2
        for y in (0.14, 1.24, 2.34):
            for z in (-0.53, 0.53):
                k.box((cx, y - 0.07, z), (x1 - x0, 0.12, 0.06), "OstraOrange")
            k.box((cx, y - 0.01, 0), (x1 - x0, 0.02, 1.0), "OstraGrating", bev=False)
            x = x0 + rnd.uniform(0.02, 0.1)
            while x < x1 - 0.3:
                kind = rnd.choice(("crate", "crate", "canisters", "sacks", "boxes", "gap"))
                lo, hi = {"canisters": (0.5, 0.8), "sacks": (0.6, 0.9), "boxes": (0.7, 1.0), "gap": (0.15, 0.35)}.get(
                    kind, (0.5, 0.85)
                )
                w = min(rnd.uniform(lo, hi), x1 - 0.03 - x)
                if w < 0.3:
                    break
                if kind != "gap":
                    {"crate": _crate, "canisters": _canisters, "sacks": _sacks, "boxes": _boxes}[kind](
                        k, rnd, x + w / 2, y, w, 0.95
                    )
                x += w + rnd.uniform(0.03, 0.12)


# --- council ---------------------------------------------------------------------------------------


def council_table(k: Kit) -> None:
    """The council's long table, 2.4 x 0.8 x 5.5 (long along z): worn top, teal map strip, heavy pedestal."""
    k.prism_y(rrect(2.4, 5.5, 0.5, 5), 0.725, 0.785, "OstraMetal")  # rim
    k.prism_y(rrect(2.3, 5.4, 0.45, 5), 0.74, 0.8, "OstraPaint")  # top
    k.box((0, 0.803, 0), (0.68, 0.008, 4.2), "OstraPaintDark", bev=False)  # the strip's bezel
    for z in (-1.38, 0.0, 1.38):
        k.box((0, 0.807, z), (0.56, 0.006, 1.28), "OstraScreen", bev=False)
    for s in (-1, 1):  # a pad at each seat, half of them lit
        for i, z in enumerate((-1.8, -0.6, 0.6, 1.8)):
            k.box((s * 0.86, 0.803, z), (0.22, 0.008, 0.15), "OstraPaintDark", bev=False)
            if (i + (s > 0)) % 2 == 0:
                k.box((s * 0.86, 0.806, z), (0.15, 0.004, 0.09), "OstraScreen", bev=False)
    for z in (-2.75, 2.75):
        k.box((0, 0.803, z * 0.86), (0.3, 0.008, 0.18), "OstraPaintDark", bev=False)
    k.prism_y(rrect(1.7, 4.7, 0.3, 3), 0.62, 0.725, "OstraPaintDark")  # skirt
    k.box((0, 0.36, 0), (0.62, 0.52, 3.8), "OstraPaintDark")  # pedestal spine
    for s in (-1, 1):
        for i in range(7):
            k.box((s * 0.315, 0.36, -1.65 + i * 0.55), (0.03, 0.44, 0.07), "OstraPaint", bev=False)
        k.box((s * 0.315, 0.55, 0), (0.02, 0.03, 3.6), "OstraAmber", bev=False)
    k.box((0, 0.05, 0), (0.95, 0.1, 4.1), "OstraPaintDark")  # plinth
    k.box((0, 0.012, 0), (0.98, 0.024, 4.13), "OstraRubber", bev=False)
    for x in (-0.12, 0.12):  # cables into the floor
        k.path([(x, 0.3, 1.9), (x, 0.14, 2.2), (x, 0.03, 2.45), (x, 0.03, 2.7)], 0.025, "OstraRubber", seg=8)


def council_chair(k: Kit) -> None:
    """Command chair, 0.6 x 0.9 x 0.6, seat at 0.45, backrest at -z."""
    for i in range(5):  # five-star base on casters
        a = math.radians(90 + 72 * i)
        tip = (math.cos(a) * 0.26, 0.07, math.sin(a) * 0.26)
        k.beam((0, 0.09, 0), tip, 0.05, 0.035, (0, 1, 0), "OstraPaintDark")
        k.cyl((tip[0], 0.03, tip[2]), 0.03, 0.035, "OstraRubber", axis="x", seg=8)
    k.cyl((0, 0.1, 0), 0.05, 0.06, "OstraPaintDark", seg=12)
    k.cyl((0, 0.2, 0), 0.04, 0.16, "OstraPaintDark", seg=12)
    k.cyl((0, 0.31, 0), 0.025, 0.1, "OstraMetal", seg=10)
    k.box((0, 0.35, 0), (0.46, 0.04, 0.44), "OstraPaintDark")  # seat pan
    k.box((0, 0.41, 0.01), (0.52, 0.08, 0.5), "OstraFabric")  # cushion, top at 0.45
    k.rod((-0.25, 0.44, 0.26), (0.25, 0.44, 0.26), 0.01, "OstraRubber", seg=6)
    tilt = C.rx(-10)
    k.box((0, 0.69, -0.24), (0.48, 0.4, 0.05), "OstraPaintDark", rot=tilt)  # backrest shell
    k.box((0, 0.69, -0.24), (0.42, 0.34, 0.05), "OstraFabric", rot=tilt, off=(0, 0, 0.035))
    k.box((0, 0.69, -0.24), (0.44, 0.02, 0.02), "OstraRubber", bev=False, rot=tilt, off=(0, 0.19, 0.04))
    k.box((0, 0.46, -0.245), (0.07, 0.24, 0.04), "OstraPaintDark")  # spine
    for s in (-1, 1):  # armrests
        k.box((s * 0.27, 0.51, -0.02), (0.035, 0.2, 0.05), "OstraPaintDark")
        k.box((s * 0.27, 0.62, -0.02), (0.06, 0.035, 0.3), "OstraRubber")


# --- bar -------------------------------------------------------------------------------------------------


def bar_counter(k: Kit) -> None:
    """The bar's counter, 9.0 x 1.1 x 0.9: guests at +z (foot rail, top flat at 1.1), the bartender at -z (a
    lower work shelf with a sink, glasses below, kegs under the taps)."""
    n = 9.0
    sink = -0.74  # middle of the third bay
    k.box((0, 1.07, 0.145), (n, 0.06, 0.53), "OstraWood")  # guests' top, z -0.12..0.41
    k.cyl((0, 1.06, 0.41), 0.04, n, "OstraMetal", axis="x", seg=12)  # steel nose
    k.box((0, 1.012, 0.37), (n - 0.2, 0.01, 0.025), "OstraAmber", bev=False)  # glow under the overhang
    k.box((0, 0.57, 0.17), (n - 0.1, 0.94, 0.3), "OstraPaint")  # front wall, z 0.02..0.32
    k.box((0, 0.05, 0.15), (n - 0.1, 0.1, 0.24), "OstraPaintDark")  # plinth
    k.box((0, 0.05, 0.275), (n - 0.2, 0.08, 0.01), "OstraRubber", bev=False)
    xs = [-4.45 + i * 8.9 / 6 for i in range(7)]
    for x in xs:
        k.box((x, 0.57, 0.335), (0.08, 0.92, 0.03), "OstraPaintDark")
    for a, b in itertools.pairwise(xs):
        cx = (a + b) / 2
        k.box((cx, 0.6, 0.328), (1.3, 0.62, 0.02), "OstraPaint")
        bolts(k, [(cx + dx * 0.6, 0.6 + dy * 0.27, 0.34) for dx in (-1, 1) for dy in (-1, 1)])
    k.cyl((0, 0.2, 0.42), 0.025, n - 0.2, "OstraMetal", axis="x", seg=10)  # foot rail
    for x in [*xs[1:-1], -4.3, 4.3]:
        k.rod((x, 0.2, 0.42), (x, 0.26, 0.32), 0.014, "OstraMetal", seg=6)
    # Bartender's side.
    k.box((0, 0.98, -0.1), (n - 0.1, 0.12, 0.04), "OstraPaintDark")  # riser under the top's back edge
    for x0, x1 in ((-4.45, -1.07), (-0.43, 4.45)):  # stainless work shelf at 0.92, cut for the sink
        k.box(((x0 + x1) / 2, 0.905, -0.225), (x1 - x0, 0.03, 0.45), "OstraMetal")
    k.box((sink, 0.905, -0.075), (0.64, 0.03, 0.15), "OstraMetal")
    k.box((0, 0.05, -0.2), (n - 0.1, 0.1, 0.4), "OstraPaintDark")  # back plinth
    for x in xs:
        k.box((x, 0.5, -0.22), (0.04, 0.78, 0.44), "OstraPaintDark", bev=False)
    k.box((-0.75, 0.44, -0.22), (7.4, 0.03, 0.42), "OstraMetal", bev=False)  # glass shelf (not under the kegs)
    rnd = random.Random(5)
    for bay in range(5):
        a, b = xs[bay] + 0.1, xs[bay + 1] - 0.1
        if bay == 2:  # under the sink: a bin and a crate of bottles
            k.box((sink, 0.3, -0.22), (0.4, 0.4, 0.36), "OstraContainerBlue")
            continue
        x = a
        while x < b:
            if rnd.random() < 0.8:
                glass(k, x, 0.455, -0.3 + rnd.uniform(-0.03, 0.03), 0.034, rnd.choice((0.1, 0.12, 0.14)))
            x += 0.1
        k.box(((a + b) / 2, 0.2, -0.2), (0.5, 0.2, 0.34), "OstraContainerRed")  # bottle crate
        for i in range(8):
            k.cyl(
                ((a + b) / 2 - 0.18 + (i % 4) * 0.12, 0.33, -0.28 + (i // 4) * 0.16), 0.012, 0.06, "OstraBottle", seg=6
            )
    for x in (3.35, 3.95):  # kegs under the taps
        k.cyl((x, 0.375, -0.22), 0.19, 0.55, "OstraMetal", seg=16)
        for y in (0.16, 0.59):
            k.cyl((x, y, -0.22), 0.197, 0.03, "OstraPaintDark", seg=16)
        k.cyl((x, 0.665, -0.22), 0.04, 0.03, "OstraPaintDark", seg=8)
        k.path([(x, 0.68, -0.22), (x, 0.8, -0.1), (3.6, 0.86, -0.03)], 0.012, "OstraRubber")
    # Sink: an open steel basin behind the riser, with a faucet.
    k.box((sink, 0.71, -0.29), (0.6, 0.02, 0.3), "OstraMetal", bev=False)
    for z in (-0.44, -0.14):
        k.box((sink, 0.81, z), (0.64, 0.2, 0.02), "OstraMetal", bev=False)
    for x in (sink - 0.31, sink + 0.31):
        k.box((x, 0.81, -0.29), (0.02, 0.2, 0.32), "OstraMetal", bev=False)
    k.cyl((sink, 0.725, -0.29), 0.03, 0.01, "OstraPaintDark", seg=8)
    k.path([(sink, 0.96, -0.125), (sink, 1.01, -0.16), (sink, 1.0, -0.25), (sink, 0.95, -0.27)], 0.012, "OstraMetal")
    for x in (-2.6, -2.45, -2.3, -2.15):  # glasses drying upside down
        glass(k, x, 0.92, -0.3, 0.032, 0.11)
    # Beer taps at +3.6 (handles towards the bartender), drip tray; a few glasses at the far end.
    k.box((3.6, 1.105, 0.03), (0.62, 0.012, 0.16), "OstraGrating", bev=False)
    k.cyl((3.6, 1.115, 0.12), 0.07, 0.03, "OstraMetal", seg=12)
    k.cyl((3.6, 1.28, 0.12), 0.035, 0.32, "OstraMetal", seg=12)
    k.cyl((3.6, 1.45, 0.12), 0.042, 0.58, "OstraMetal", axis="x", seg=12)
    for i, x in enumerate((3.39, 3.53, 3.67, 3.81)):
        k.rod((x, 1.45, 0.12), (x, 1.45, 0.05), 0.012, "OstraMetal", seg=6)
        k.rod((x, 1.45, 0.05), (x, 1.38, 0.05), 0.01, "OstraMetal", seg=6)
        k.rod(
            (x, 1.46, 0.06),
            (x, 1.62, 0.02),
            0.014,
            ("OstraOrange", "OstraHazard", "OstraContainerRed", "OstraWood")[i],
            seg=6,
        )
    k.box((-4.0, 1.104, 0.16), (0.5, 0.01, 0.3), "OstraRubber", bev=False)
    for x, z, h in ((-4.15, 0.1, 0.12), (-4.0, 0.22, 0.14), (-3.84, 0.09, 0.11)):
        glass(k, x, 1.109, z, 0.034, h)


def back_bar(k: Kit) -> None:
    """Low narrow shelf behind the bartender, 1.3 x 1.38 x 0.3: four bottles on its top (1.13 + 0.25), bottles
    and glasses on the open shelf below, a closed cabinet at the bottom."""
    for s in (-1, 1):
        k.box((s * 0.635, 0.565, 0), (0.03, 1.13, 0.3), "OstraPaintDark")
    k.box((0, 1.115, 0), (1.3, 0.03, 0.3), "OstraWood")  # top, at 1.13
    k.box((0, 1.13, 0.148), (1.3, 0.012, 0.012), "OstraMetal", bev=False)
    k.box((0, 0.77, -0.14), (1.24, 0.72, 0.02), "OstraPaintDark")  # back of the open shelf
    k.box((0, 0.61, 0), (1.24, 0.03, 0.28), "OstraWood")  # open shelf, top at 0.625
    k.box((0, 0.04, -0.01), (1.24, 0.08, 0.26), "OstraPaintDark")  # plinth
    k.box((0, 0.335, 0), (1.24, 0.51, 0.28), "OstraPaint")  # cabinet
    for s in (-1, 1):
        k.box((s * 0.305, 0.335, 0.145), (0.58, 0.44, 0.015), "OstraPaint")
        k.box((s * 0.05, 0.4, 0.157), (0.02, 0.14, 0.015), "OstraMetal", bev=False)
    k.box((0, 0.59, 0.145), (1.24, 0.014, 0.012), "OstraLamp", bev=False)  # small warm strip under the shelf
    for x, shape in ((-0.45, "wine"), (-0.2, "liquor"), (0.15, "wine"), (0.45, "flask")):
        bottle(k, x, 1.13, 0.0, 0.25, 0.035, "OstraBottle", shape, seg=10)
    for x, h, r, mat, shape in (
        (-0.52, 0.3, 0.036, "OstraBottle", "wine"),
        (-0.42, 0.24, 0.04, "OstraGlass", "squat"),
        (-0.31, 0.28, 0.034, "OstraBottle", "liquor"),
        (0.28, 0.27, 0.035, "OstraGlass", "liquor"),
        (0.4, 0.3, 0.033, "OstraBottle", "wine"),
        (0.52, 0.22, 0.042, "OstraBottle", "squat"),
    ):
        bottle(k, x, 0.625, 0.02, h, r, mat, shape)
    for x in (-0.12, -0.03, 0.06, 0.15):
        glass(k, x, 0.625, 0.04, 0.033, 0.11)
    for x in (-0.08, 0.02, 0.11):
        glass(k, x, 0.735, 0.04, 0.03, 0.1)  # stacked


def bar_wall_shelf(k: Kit) -> None:
    """Wall rack of bottles, 4.0 x 2.4 x 0.35, hanging from 1.2 to 2.4; origin below the middle of its back edge."""
    rnd = random.Random(9)
    k.box((0, 1.8, 0.015), (4.0, 1.2, 0.03), "OstraPaintDark")  # back plate
    k.box((0, 1.82, 0.034), (3.9, 1.0, 0.008), "OstraGlass", bev=False)  # old mirror behind the bottles
    for x in (-1.975, 1.975):
        k.box((x, 1.8, 0.175), (0.05, 1.2, 0.35), "OstraPaintDark")
    for x in (-1.0, 0.0, 1.0):
        k.box((x, 1.79, 0.17), (0.03, 1.12, 0.3), "OstraPaintDark", bev=False)
    k.box((0, 2.375, 0.175), (4.0, 0.05, 0.35), "OstraPaintDark")  # top cap
    k.box((0, 2.346, 0.31), (3.8, 0.012, 0.025), "OstraLamp", bev=False)  # warm strip under the cap
    for y in (1.215, 1.595, 1.975):  # planks with a steel lip
        k.box((0, y, 0.18), (3.9, 0.03, 0.31), "OstraWood")
        k.box((0, y + 0.035, 0.338), (3.9, 0.04, 0.012), "OstraMetal", bev=False)
    for s in (-1, 1):  # wall brackets
        k.box((s * 1.5, 1.17, 0.12), (0.04, 0.06, 0.22), "OstraMetal", bev=False)
    for i, y in enumerate((1.23, 1.61, 1.99)):
        x = -1.92
        while x < 1.92:
            if any(abs(x - u) < 0.06 for u in (-1.0, 0.0, 1.0)):
                x += 0.07
                continue
            shape = rnd.choice(("wine", "wine", "liquor", "squat", "flask"))
            r = {"squat": 0.045, "flask": 0.03}.get(shape, rnd.uniform(0.032, 0.038))
            h = {"squat": 0.2, "flask": 0.22}.get(shape, rnd.uniform(0.26, 0.32))
            mat = "OstraGlass" if rnd.random() < 0.35 else "OstraBottle"
            if i == 0 and rnd.random() < 0.25:  # a few glasses on the bottom shelf
                glass(k, x, y, 0.22, 0.034, 0.11)
                x += 0.08
                continue
            if rnd.random() < 0.08:
                x += 0.1
                continue
            bottle(k, x, y, 0.2 + rnd.uniform(-0.03, 0.03), h, r, mat, shape)
            x += 2 * r + rnd.uniform(0.012, 0.04)


def booth(k: Kit) -> None:
    """Diner booth, 1.8 x 1.1 x 3.7: a 1.6 x 1.0 table (top 0.75) between two upholstered benches (seat 0.45)."""
    for s in (-1, 1):
        k.box((0, 0.165, s * 1.325), (1.8, 0.33, 0.75), "OstraPaintDark")  # bench base
        k.box((0, 0.05, s * 0.955), (1.76, 0.09, 0.012), "OstraRubber", bev=False)
        k.box((0, 0.39, s * 1.3), (1.78, 0.12, 0.8), "OstraFabric")  # seat cushion, top at 0.45
        k.rod((-0.88, 0.44, s * 0.905), (0.88, 0.44, s * 0.905), 0.012, "OstraRubber", seg=6)
        k.box((0, 0.55, s * 1.815), (1.8, 1.1, 0.07), "OstraPaintDark")  # backrest shell
        for y in (0.56, 0.75, 0.94):  # channelled back cushion
            k.box((0, y, s * 1.74), (1.7, 0.18, 0.08), "OstraFabric")
        k.rod((-0.9, 1.09, s * 1.79), (0.9, 1.09, s * 1.79), 0.016, "OstraRubber", seg=6)
        for x in (-0.9, 0.9):  # steel end trims
            k.box((x, 0.55, s * 1.775), (0.02, 1.1, 0.15), "OstraMetal", bev=False)
        k.box((0, 0.06, s * 1.846), (1.76, 0.1, 0.012), "OstraRubber", bev=False)  # outer kick strip
        k.box((0, 0.62, s * 1.846), (1.76, 0.03, 0.012), "OstraMetal", bev=False)  # outer rail
    k.box((0, 0.73, 0), (1.6, 0.04, 1.0), "OstraWood")  # table top, top at 0.75
    k.box((0, 0.705, 0), (1.62, 0.025, 1.02), "OstraMetal")
    k.box((0, 0.68, 0), (0.6, 0.03, 0.5), "OstraPaintDark", bev=False)
    k.cyl((0, 0.37, 0), 0.06, 0.66, "OstraMetal", seg=12)
    k.cyl((0, 0.025, 0), 0.32, 0.05, "OstraPaintDark", seg=20, bev=True)
    # Napkin holder and a small lamp at the +x end.
    k.box((0.6, 0.79, -0.12), (0.12, 0.08, 0.05), "OstraMetal", bev=False)
    k.box((0.6, 0.8, -0.12), (0.1, 0.07, 0.03), "OstraCanvas", bev=False)
    k.cyl((0.6, 0.76, 0.15), 0.045, 0.02, "OstraPaintDark", seg=10)
    k.rod((0.6, 0.77, 0.15), (0.6, 0.98, 0.15), 0.008, "OstraMetal", seg=6)
    k.cyl((0.6, 0.99, 0.15), 0.08, 0.08, "OstraPaintDark", r2=0.035, seg=12)
    k.sphere((0.6, 0.965, 0.15), 0.028, "OstraLamp", seg=8, rings=4)
    bottle(k, 0.45, 0.75, -0.18, 0.15, 0.022, "OstraBottle", "liquor")


def bar_stool(k: Kit) -> None:
    """Round bar stool, 0.45 x 0.75 x 0.45, seat at 0.75, footrest ring."""
    k.lathe((0, 0, 0), [(0.2, 0.0), (0.2, 0.015), (0.16, 0.035), (0.05, 0.05)], "OstraPaintDark", seg=20, bev=True)
    k.torus((0, 0.008, 0), 0.2, 0.012, "OstraRubber", seg=20, tseg=4)
    k.cyl((0, 0.33, 0), 0.035, 0.6, "OstraMetal", seg=12)
    k.torus((0, 0.28, 0), 0.17, 0.013, "OstraMetal", seg=20, tseg=6)
    for a in (90, 210, 330):
        p = (math.cos(math.radians(a)) * 0.17, 0.28, math.sin(math.radians(a)) * 0.17)
        k.rod((0, 0.31, 0), p, 0.01, "OstraMetal", seg=6)
    k.cyl((0, 0.645, 0), 0.12, 0.04, "OstraPaintDark", seg=16)
    k.lathe(
        (0, 0, 0),
        [(0.17, 0.665), (0.2, 0.68), (0.205, 0.715), (0.19, 0.74), (0.12, 0.75)],
        "OstraFabric",
        seg=20,
    )
    k.torus((0, 0.7, 0), 0.204, 0.009, "OstraRubber", seg=20, tseg=4)
    k.torus((0, 0.668, 0), 0.172, 0.01, "OstraMetal", seg=20, tseg=4)


# --- concourse market ---------------------------------------------------------------------------------


def stall_counter(k: Kit) -> None:
    """The stall's counter, 3.0 x 1.0 x 1.2 around the origin; its front face stays at z <= 0.6."""
    k.box((0, 0.04, -0.02), (2.9, 0.08, 1.0), "OstraPaintDark")
    k.box((0, 0.515, 0.555), (2.9, 0.87, 0.05), "OstraPaint")  # front wall
    for x in (-1.425, 1.425):
        k.box((x, 0.515, 0.0), (0.05, 0.87, 1.16), "OstraPaint")
    for y in (0.1, 0.5):
        k.box((0, y, -0.02), (2.8, 0.03, 1.08), "OstraPaintDark", bev=False)
    k.box((0, 0.975, -0.01), (3.0, 0.05, 1.18), "OstraWood")  # top, z -0.6..0.58
    k.box((0, 0.955, 0.585), (3.0, 0.04, 0.03), "OstraMetal")
    for x in (-1.0, 0.0, 1.0):
        k.box((x, 0.52, 0.588), (0.06, 0.8, 0.016), "OstraPaintDark", bev=False)
    k.box((0, 0.13, 0.588), (2.8, 0.06, 0.016), "OstraHazard", bev=False)
    for cx in (-1.25, -0.5, 0.5, 1.25):  # patched plates
        bolts(k, [(cx + dx * 0.15, 0.85, 0.586) for dx in (-1, 1)], depth=0.01)
    # Vendor's side: crates and a cash box on the shelves.
    k.box((-0.9, 0.24, -0.1), (0.6, 0.25, 0.5), "OstraContainerOlive")
    k.box((0.8, 0.62, -0.2), (0.3, 0.14, 0.24), "OstraPaintDark")


def stall_rack(k: Kit) -> None:
    """Goods rack behind the vendor, 3.0 x 2.2 x 0.4 at z = -2.8."""
    for x in (-1.47, 1.47):
        for z in (-2.97, -2.63):
            k.box((x, 1.1, z), (0.05, 2.2, 0.05), "OstraPaintDark")
        k.beam((x, 0.15, -2.97), (x, 1.1, -2.63), 0.03, 0.025, (1, 0, 0), "OstraPaintDark")
    for y in (0.12, 0.62, 1.12):
        k.box((0, y, -2.8), (2.9, 0.03, 0.38), "OstraWood")
        k.box((0, y + 0.03, -2.615), (2.9, 0.04, 0.012), "OstraMetal", bev=False)
    k.box((0, 1.67, -2.975), (2.9, 1.06, 0.015), "OstraGrating", bev=False)  # pegboard
    k.box((0, 2.18, -2.8), (3.0, 0.04, 0.4), "OstraPaintDark")


# The awning's front edge: behind the one standing at the counter (at z -1.6), so the camera, looking down from the
# front at 35°, sees them under it.
AWNING_FRONT = -2.1


def canopy(k: Kit, back_z: float, back_post_z: float) -> None:
    """Posts, a slanted canvas awning over the back of the stall from 3.0 m at back_z to 2.7 m at its front edge
    (AWNING_FRONT), a scalloped valance and a string of bulbs along the front."""
    front_z, front_y, back_y = AWNING_FRONT, 2.7, 3.0

    def height(z):
        return front_y + (back_y - front_y) * (front_z - z) / (front_z - back_z)

    for z in (front_z - 0.05, back_post_z):
        top = height(z) - 0.04
        for x in (-1.55, 1.55):
            k.box((x, 0.01, z), (0.14, 0.02, 0.14), "OstraMetal", bev=False)
            k.cyl((x, top / 2, z), 0.035, top, "OstraPaintDark", seg=8)
    k.cyl((0, front_y - 0.035, front_z - 0.03), 0.025, 3.2, "OstraMetal", axis="x", seg=8)
    bz = back_z + 0.05
    k.cyl((0, height(bz) - 0.035, bz), 0.025, 3.2, "OstraMetal", axis="x", seg=8)
    for x in (-1.55, 0.0, 1.55):
        k.rod((x, front_y - 0.035, front_z - 0.03), (x, height(bz) - 0.035, bz), 0.02, "OstraMetal", seg=6)

    def canvas(u, v):
        x = -1.6 + 3.2 * u
        z = front_z + (back_z - front_z) * v
        sag = 0.05 * abs(math.sin(math.pi * x / 1.55)) * math.sin(math.pi * v) ** 0.5
        return (x, height(z) - sag, z)

    k.sheet(canvas, 24, 8, "OstraCanvas")
    pts = [(-1.6, front_y + 0.005), (1.6, front_y + 0.005)]
    n = 40
    for i in range(n + 1):
        x = 1.6 - 3.2 * i / n
        pts.append((x, front_y - 0.17 - 0.05 * abs(math.sin(math.pi * i / 5))))
    k.prism_z(pts, front_z - 0.006, front_z + 0.006, "OstraCanvas", bev=False)
    # String of bulbs: hooks at the posts and the middle, the cable sagging in between.
    cable = []
    for a, b in ((-1.55, 0.0), (0.0, 1.55)):
        for i in range(5):
            t = i / 5
            cable.append((a + (b - a) * t, front_y - 0.2 - 0.12 * math.sin(math.pi * t), front_z + 0.04))
    cable.append((1.55, front_y - 0.2, front_z + 0.04))
    k.path(cable, 0.006, "OstraRubber", seg=4)
    for p in cable[1:-1]:
        if abs(p[0]) < 0.01:
            continue
        k.cyl((p[0], p[1] - 0.025, p[2]), 0.014, 0.04, "OstraPaintDark", seg=6)
        k.sphere((p[0], p[1] - 0.07, p[2]), 0.03, "OstraLamp", seg=8, rings=4)


def stall_parts(k: Kit) -> None:
    """Market stall for machine parts and tools: counter, rack, canopy; gears, pipes, valves, a toolbox."""
    rnd = random.Random(21)
    stall_counter(k)
    stall_rack(k)
    canopy(k, -3.1, -3.05)
    # Bottom shelf: pipe stock and a toolbox.
    for i, (x0, y, r) in enumerate(((-1.2, 0.18, 0.05), (-1.2, 0.18, 0.05), (-1.25, 0.26, 0.04), (-1.2, 0.18, 0.05))):
        z = -2.9 + i * 0.09 if i != 2 else -2.83
        mat = ("OstraMetal", "OstraPaintDark", "OstraContainerOlive", "OstraMetal")[i]
        k.cyl((x0 + 0.5, y if i != 2 else 0.24, z), r, 1.0, mat, axis="x", seg=10)
    k.box((0.75, 0.25, -2.8), (0.5, 0.22, 0.26), "OstraContainerRed")
    k.box((0.75, 0.37, -2.8), (0.52, 0.03, 0.28), "OstraPaintDark", bev=False)
    k.rod((0.6, 0.41, -2.8), (0.9, 0.41, -2.8), 0.012, "OstraMetal", seg=6)
    gear(k, (0.0, 0.2, -2.8), 0.12, 0.05, "OstraPaintDark", axis="y")
    # Middle shelf: gears, valves, parts bins.
    gear(k, (-1.1, 0.66, -2.8), 0.14, 0.04, "OstraMetal")
    gear(k, (-1.1, 0.7, -2.8), 0.09, 0.04, "OstraMetal")
    gear(k, (-0.65, 0.81, -2.75), 0.16, 0.04, "OstraMetal", axis="z")
    valve(k, (-0.15, 0.635, -2.8))
    valve(k, (0.25, 0.635, -2.75), 0.06, "OstraContainerBlue")
    for x in (0.65, 0.95, 1.25):
        k.box((x, 0.7, -2.8), (0.26, 0.13, 0.32), "OstraContainerBlue")
        for _ in range(3):
            k.cyl((x + rnd.uniform(-0.08, 0.08), 0.765, -2.8 + rnd.uniform(-0.1, 0.1)), 0.02, 0.02, "OstraMetal", seg=6)
    # Top shelf: a hose coil, standing gears, a gauge.
    k.torus((-0.9, 1.18, -2.8), 0.15, 0.03, "OstraRubber", seg=16, tseg=6)
    k.torus((-0.9, 1.24, -2.8), 0.15, 0.03, "OstraRubber", seg=16, tseg=6)
    gear(k, (-0.25, 1.33, -2.85), 0.18, 0.05, "OstraPaintDark", axis="z", teeth=12)
    gear(k, (0.2, 1.27, -2.82), 0.12, 0.04, "OstraMetal", axis="z")
    k.cyl((0.75, 1.26, -2.8), 0.08, 0.06, "OstraMetal", axis="z", seg=12)
    k.cyl((0.75, 1.26, -2.765), 0.065, 0.01, "OstraCanvas", axis="z", seg=12)
    k.box((1.2, 1.25, -2.8), (0.3, 0.2, 0.3), "OstraContainerOlive")
    # Pegboard: wrenches, a hammer, a coil, a handwheel.
    for i in range(6):
        wrench(k, (-1.3 + i * 0.07, 1.85 - i * 0.02, -2.96), 0.32 - i * 0.03)
    hammer(k, (-0.75, 1.8, -2.96))
    k.torus((-0.3, 1.75, -2.955), 0.2, 0.025, "OstraOrange", axis="z", seg=16, tseg=4)
    k.torus((0.35, 1.85, -2.955), 0.12, 0.014, "OstraContainerRed", axis="z", seg=14, tseg=4)
    gear(k, (0.85, 1.8, -2.95), 0.15, 0.03, "OstraPaintDark", axis="z")
    for i in range(4):
        screwdriver(
            k,
            (1.2 + i * 0.06, 1.95, -2.955),
            (1.2 + i * 0.06, 1.7, -2.955),
            ("OstraOrange", "OstraContainerRed")[i % 2],
        )
    # On the counter, clear in the middle: a toolbox, gears, a tray of bolts, a valve.
    k.box((-1.05, 1.1, -0.15), (0.45, 0.2, 0.24), "OstraOrange")
    k.box((-1.05, 1.21, -0.15), (0.47, 0.03, 0.26), "OstraPaintDark", bev=False)
    k.rod((-1.2, 1.25, -0.15), (-0.9, 1.25, -0.15), 0.012, "OstraMetal", seg=6)
    gear(k, (-1.1, 1.02, 0.25), 0.11, 0.03, "OstraMetal")
    gear(k, (-0.82, 1.02, 0.3), 0.07, 0.03, "OstraMetal")
    k.box((0.95, 1.02, 0.2), (0.4, 0.04, 0.28), "OstraPaintDark")
    for _ in range(9):
        k.cyl((0.95 + rnd.uniform(-0.15, 0.15), 1.05, 0.2 + rnd.uniform(-0.1, 0.1)), 0.015, 0.025, "OstraMetal", seg=6)
    valve(k, (1.15, 1.0, -0.2), 0.06)


def stall_trade(k: Kit) -> None:
    """Barter stall: counter, rack, canopy; jars, bundles, crates, sacks, a small scale."""
    rnd = random.Random(33)
    stall_counter(k)
    stall_rack(k)
    canopy(k, -3.1, -3.05)
    # Bottom shelf: sacks and a crate.
    for x in (-1.15, -0.75, -0.35):
        k.lump((x, 0.135, -2.8), (0.36, 0.3, 0.32), "OstraCanvas", rnd, seg=12, turn=rnd.uniform(-20, 20))
    k.box((0.35, 0.3, -2.8), (0.6, 0.33, 0.34), "OstraWood")
    k.box((0.35, 0.44, -2.62), (0.6, 0.05, 0.012), "OstraPaintDark", bev=False)
    k.box((1.1, 0.27, -2.8), (0.5, 0.27, 0.34), "OstraContainerOlive")
    # Middle shelf: rows of jars with metal lids.
    for i in range(14):
        x = -1.3 + i * 0.19
        if 0.25 < x < 0.65:
            continue
        fill = ("OstraPlant", "OstraOrange", "OstraContainerRed", "OstraCanvas")[i % 4]
        for z in (-2.88, -2.72) if i % 2 else (-2.72,):
            h = 0.16 + 0.03 * ((i + int(z * 10)) % 3)
            k.lathe((x, 0.635, z), [(0.06, 0), (0.065, 0.02), (0.065, h), (0.05, h + 0.01)], "OstraGlass", 8)
            k.cyl((x, 0.635 + h * 0.4, z), 0.055, h * 0.75, fill, seg=8)
            k.cyl((x, 0.65 + h, z), 0.052, 0.025, "OstraMetal", seg=10)
    k.box((0.45, 0.72, -2.8), (0.32, 0.17, 0.3), "OstraWood")
    # Top shelf: bundles of rods and cloth rolls tied up.
    for j, x in enumerate((-1.0, -0.2, 0.6)):
        for i in range(5):
            z = -2.88 + (i % 3) * 0.08
            y = 1.17 + (i // 3) * 0.07
            k.cyl((x, y, z), 0.04, 0.6, ("OstraCanvas", "OstraWood", "OstraPlant")[j], axis="x", seg=8)
        for dx in (-0.2, 0.2):
            k.cyl((x + dx, 1.2, -2.84), 0.11, 0.03, "OstraRubber", axis="x", seg=8)
    k.box((1.25, 1.24, -2.8), (0.3, 0.2, 0.3), "OstraContainerBlue")
    # Pegboard: herbs and bundles hanging on strings.
    for i in range(7):
        x = -1.3 + i * 0.4
        k.rod((x, 2.12, -2.95), (x, 1.88, -2.93), 0.004, "OstraCanvas", seg=4)
        k.lump(
            (x, 1.62, -2.92), (0.14, 0.28, 0.1), ("OstraPlant", "OstraCanvas")[i % 2], rnd, turn=rnd.uniform(-30, 30)
        )
    # Counter: jars, a crate of produce, a sack, a small balance scale.
    for x, z in ((-1.2, 0.2), (-1.05, 0.28), (-1.12, 0.05)):
        k.lathe((x, 1.0, z), [(0.06, 0), (0.065, 0.02), (0.065, 0.17), (0.05, 0.18)], "OstraGlass", 8)
        k.cyl((x, 1.07, z), 0.055, 0.12, "OstraOrange", seg=8)
        k.cyl((x, 1.19, z), 0.052, 0.025, "OstraMetal", seg=10)
    k.box((-0.95, 1.08, -0.25), (0.5, 0.16, 0.36), "OstraWood")
    for _ in range(10):
        k.sphere(
            (-0.95 + rnd.uniform(-0.18, 0.18), 1.17, -0.25 + rnd.uniform(-0.12, 0.12)),
            0.045,
            "OstraOrange",
            seg=6,
            rings=4,
        )
    k.lump((1.2, 1.0, -0.25), (0.34, 0.4, 0.3), "OstraCanvas", rnd, seg=12)
    k.cyl((1.2, 1.38, -0.25), 0.04, 0.05, "OstraRubber", seg=8)
    sx, sz = 0.95, 0.2  # balance scale
    k.box((sx, 1.015, sz), (0.3, 0.03, 0.14), "OstraPaintDark")
    k.rod((sx, 1.03, sz), (sx, 1.3, sz), 0.012, "OstraMetal", seg=6)
    k.rod((sx - 0.16, 1.3, sz), (sx + 0.16, 1.3, sz), 0.008, "OstraMetal", seg=6)
    for dx in (-0.15, 0.15):
        for dz in (-0.04, 0.04):
            k.rod((sx + dx, 1.3, sz), (sx + dx, 1.12, sz + dz), 0.002, "OstraMetal", seg=3)
        k.cyl((sx + dx, 1.115, sz), 0.07, 0.012, "OstraMetal", seg=12)


def stall_dace(k: Kit) -> None:
    """Dace's machinist stall: the counter and a canopy over his workbench behind (which stands separately, its
    back at z -3.4), no rack, no goods (the game's shutter closes at z +0.7)."""
    stall_counter(k)
    canopy(k, -3.6, -3.55)


# --- workshops -----------------------------------------------------------------------------------------


def dace_bench(k: Kit) -> None:
    """Machinist's workbench, 3.0 x 0.95 x 0.8: vise, drill press, tools, a pegboard rising to 2.2."""
    rnd = random.Random(4)
    k.box((0, 0.92, 0), (3.0, 0.06, 0.8), "OstraWood")  # thick top, at 0.95
    k.box((0, 0.92, 0.405), (3.0, 0.06, 0.012), "OstraMetal", bev=False)
    for x in (-1.42, 1.42):
        for z in (-0.34, 0.34):
            k.box((x, 0.445, z), (0.07, 0.89, 0.07), "OstraPaintDark")
            k.box((x, 0.01, z), (0.12, 0.02, 0.12), "OstraMetal", bev=False)
        k.box((x, 0.2, 0), (0.05, 0.05, 0.62), "OstraPaintDark", bev=False)
    for z in (-0.34, 0.34):
        k.box((0, 0.84, z), (2.8, 0.08, 0.05), "OstraPaintDark")
    k.box((-0.55, 0.2, 0), (1.78, 0.03, 0.66), "OstraGrating", bev=False)  # lower shelf
    k.box((-0.55, 0.2, 0.33), (1.78, 0.05, 0.03), "OstraPaintDark", bev=False)
    k.box((-1.0, 0.36, -0.05), (0.5, 0.3, 0.4), "OstraContainerOlive")
    k.cyl((-0.4, 0.36, 0.05), 0.12, 0.3, "OstraHazard", seg=12)
    k.cyl((-0.4, 0.52, 0.05), 0.04, 0.03, "OstraPaintDark", seg=8)
    # Tool chest under the right end: four drawers.
    k.box((0.85, 0.47, 0), (1.0, 0.8, 0.66), "OstraContainerRed")
    for i, y in enumerate((0.17, 0.37, 0.57, 0.76)):
        hgt = 0.18 if i else 0.2
        k.box((0.85, y, 0.335), (0.94, hgt - 0.02, 0.015), "OstraContainerRed")
        k.box((0.85, y + 0.03, 0.35), (0.5, 0.02, 0.02), "OstraMetal", bev=False)
    # Vise at x -1.0 on the front edge.
    vx, vy, vz = -1.0, 0.95, 0.2
    k.box((vx, vy + 0.02, vz), (0.2, 0.04, 0.24), "OstraPaintDark")
    k.box((vx, vy + 0.1, vz), (0.12, 0.12, 0.26), "OstraContainerBlue")
    for dz, mat in ((-0.09, "OstraContainerBlue"), (0.1, "OstraContainerBlue")):
        k.box((vx, vy + 0.17, vz + dz), (0.26, 0.1, 0.06), mat)
        k.box((vx, vy + 0.2, vz + dz - 0.033 * (1 if dz > 0 else -1)), (0.24, 0.05, 0.008), "OstraMetal", bev=False)
    k.rod((vx, vy + 0.1, vz + 0.13), (vx, vy + 0.1, vz + 0.21), 0.012, "OstraMetal", seg=6)
    k.rod((vx - 0.12, vy + 0.1, vz + 0.21), (vx + 0.12, vy + 0.1, vz + 0.21), 0.009, "OstraMetal", seg=6)
    for dx in (-0.12, 0.12):
        k.sphere((vx + dx, vy + 0.1, vz + 0.21), 0.018, "OstraMetal", seg=6, rings=4)
    # Drill press over the chest.
    dx, dz = 1.0, -0.12
    k.box((dx, 0.97, dz), (0.26, 0.04, 0.3), "OstraPaintDark")
    k.cyl((dx, 1.37, dz - 0.1), 0.03, 0.8, "OstraMetal", seg=10)
    k.box((dx, 1.2, dz + 0.02), (0.18, 0.025, 0.18), "OstraMetal")
    k.box((dx, 1.64, dz - 0.03), (0.17, 0.2, 0.32), "OstraContainerOlive")
    k.box((dx, 1.78, dz - 0.05), (0.2, 0.07, 0.38), "OstraContainerOlive")
    k.cyl((dx, 1.66, dz - 0.25), 0.07, 0.2, "OstraPaintDark", seg=12)
    k.cyl((dx, 1.5, dz + 0.06), 0.025, 0.1, "OstraMetal", seg=8)
    k.cyl((dx, 1.42, dz + 0.06), 0.015, 0.07, "OstraMetal", r2=0.004, seg=6)
    for a in (0, 120, 240):
        p = (dx + 0.1, 1.6 + math.sin(math.radians(a)) * 0.14, dz + math.cos(math.radians(a)) * 0.14)
        k.rod((dx + 0.1, 1.6, dz), p, 0.007, "OstraMetal", seg=4)
        k.sphere(p, 0.016, "OstraRubber", seg=6, rings=3)
    k.box((dx + 0.09, 1.66, dz + 0.13), (0.03, 0.03, 0.01), "OstraRed", bev=False)
    # Tools on the top.
    hammer(k, (-0.45, 0.95, 0.15), hanging=False, turn=20)
    wrench(k, (-0.1, 0.95, 0.22), 0.3, hanging=False, turn=-15)
    wrench(k, (0.05, 0.95, 0.12), 0.22, hanging=False, turn=30)
    k.box((0.3, 0.98, -0.15), (0.3, 0.06, 0.2), "OstraPaintDark")  # parts tray
    for _ in range(6):
        k.cyl((0.3 + rnd.uniform(-0.1, 0.1), 1.01, -0.15 + rnd.uniform(-0.06, 0.06)), 0.014, 0.02, "OstraMetal", seg=6)
    gear(k, (-0.3, 0.965, -0.2), 0.08, 0.025, "OstraMetal")
    k.lump((-0.65, 0.95, -0.15), (0.2, 0.05, 0.15), "OstraCanvas", rnd)
    # Pegboard on two uprights, a lamp hood at its top.
    for x in (-1.42, 1.42):
        k.box((x, 1.575, -0.44), (0.06, 1.25, 0.05), "OstraPaintDark")
    k.box((0, 1.56, -0.455), (2.84, 1.2, 0.02), "OstraPaint")
    k.box((0, 1.56, -0.444), (2.7, 1.08, 0.004), "OstraGrating", bev=False)
    k.box((0, 2.17, -0.37), (2.9, 0.06, 0.16), "OstraPaintDark")
    k.box((0, 2.136, -0.33), (2.7, 0.01, 0.05), "OstraLamp", bev=False)
    for i in range(7):
        wrench(k, (-1.25 + i * 0.075, 1.6 - i * 0.015, -0.438), 0.34 - i * 0.03)
    hammer(k, (-0.6, 1.55, -0.438))
    hammer(k, (-0.45, 1.5, -0.438))
    for i in range(5):
        screwdriver(
            k,
            (-0.25 + i * 0.06, 1.75, -0.435),
            (-0.25 + i * 0.06, 1.45, -0.435),
            ("OstraOrange", "OstraContainerRed")[i % 2],
        )
    k.torus((0.35, 1.55, -0.43), 0.17, 0.025, "OstraRubber", axis="z", seg=16, tseg=4)
    k.prism_z([(0.65, 1.35), (1.1, 1.35), (1.1, 1.45), (0.75, 1.47)], -0.44, -0.432, "OstraMetal", bev=False)  # saw
    k.box((1.15, 1.42, -0.436), (0.12, 0.1, 0.02), "OstraWood", bev=False)
    k.box((0.9, 1.8, -0.36), (0.8, 0.025, 0.16), "OstraPaintDark")  # small shelf with jars and cans
    for i, x in enumerate((0.6, 0.72, 0.84, 0.98, 1.12, 1.22)):
        if i % 3 == 2:
            k.cyl((x, 1.87, -0.36), 0.045, 0.12, "OstraContainerBlue", seg=10)
        else:
            k.lathe((x, 1.81, -0.36), [(0.04, 0), (0.04, 0.12), (0.032, 0.13)], "OstraGlass", 8)
            k.cyl((x, 1.945, -0.36), 0.033, 0.02, "OstraMetal", seg=8)


def suit_bench(k: Kit) -> None:
    """Suit technician's bench, 2.2 x 0.95 x 0.9: an armored helmet, tools, a cable reel, a teal diagnostic screen."""
    rnd = random.Random(8)
    k.box((0, 0.925, 0), (2.2, 0.05, 0.9), "OstraMetal")  # steel top, at 0.95
    k.box((0, 0.88, 0), (2.1, 0.06, 0.82), "OstraPaintDark")
    for x in (-1.04, 1.04):
        k.box((x, 0.43, 0), (0.08, 0.86, 0.84), "OstraPaintDark")  # side frames
    k.box((-0.55, 0.45, -0.02), (1.0, 0.8, 0.76), "OstraPaint")  # cabinet, left
    for i, y in enumerate((0.2, 0.45, 0.7)):
        k.box((-0.55, y, 0.365), (0.92, 0.22, 0.015), "OstraPaint")
        k.box((-0.55, y + 0.05, 0.38), (0.4, 0.02, 0.02), "OstraMetal", bev=False)
    k.box((-0.55, 0.82, 0.366), (0.04, 0.02, 0.01), "OstraAmber", bev=False)
    k.box((0.5, 0.06, 0), (1.0, 0.03, 0.8), "OstraGrating", bev=False)  # open right side: spare plates
    k.box((0.5, 0.45, 0), (1.0, 0.03, 0.8), "OstraPaintDark", bev=False)
    k.box((0.35, 0.15, 0.0), (0.4, 0.14, 0.5), "OstraContainerOlive")
    for i in range(3):
        k.box((0.75, 0.5 + i * 0.035, 0.05 - i * 0.03), (0.35, 0.03, 0.42), "OstraPaint", rot=C.rz(8 * i))
    k.cyl((0.75, 0.25, 0.1), 0.1, 0.36, "OstraHazard", seg=12)
    # Helmet on a ring stand, turned a little towards the screen.
    hx, hz = -0.3, 0.05
    turn = C.rz(15)
    k.cyl((hx, 0.97, hz), 0.11, 0.04, "OstraMetal", seg=16)
    k.cyl((hx, 1.0, hz), 0.12, 0.03, "OstraPaintDark", seg=16)
    k.sphere((hx, 1.16, hz), 0.15, "OstraPaint", scale=(0.95, 1.0, 1.05), seg=16, rings=10, rot=turn)
    k.box((hx, 1.16, hz), (0.2, 0.09, 0.08), "OstraGlass", bev=False, rot=turn, off=(0, 0.01, 0.12))
    k.box((hx, 1.16, hz), (0.23, 0.035, 0.05), "OstraPaintDark", bev=False, rot=turn, off=(0, 0.07, 0.125))  # brow
    k.box((hx, 1.16, hz), (0.15, 0.05, 0.05), "OstraPaintDark", bev=False, rot=turn, off=(0, -0.07, 0.125))  # chin
    k.box((hx, 1.16, hz), (0.05, 0.03, 0.26), "OstraPaintDark", bev=False, rot=turn, off=(0, 0.15, -0.01))  # crest
    for s in (-1, 1):
        k.cyl((hx, 1.16, hz), 0.05, 0.04, "OstraPaintDark", rot=turn @ C.ry(90), seg=12)
        k.box((hx, 1.16, hz), (0.03, 0.02, 0.02), "OstraAmber", bev=False, rot=turn, off=(s * 0.165, 0.0, 0.0))
    # Cable reel at the +x end, its cable to the helmet.
    rx_, rz_ = 0.75, 0.2
    for dx in (-0.1, 0.1):
        k.cyl((rx_ + dx, 1.12, rz_), 0.15, 0.02, "OstraOrange", axis="x", seg=16)
        k.box((rx_ + dx * 1.25, 1.03, rz_), (0.025, 0.16, 0.05), "OstraPaintDark", bev=False)
    k.cyl((rx_, 1.12, rz_), 0.115, 0.18, "OstraRubber", axis="x", seg=16)
    k.box((rx_, 0.96, rz_), (0.3, 0.02, 0.2), "OstraPaintDark", bev=False)
    k.path(
        [(rx_ - 0.05, 1.03, rz_ + 0.08), (0.3, 0.96, 0.3), (-0.1, 0.96, 0.25), (hx + 0.1, 1.03, hz + 0.05)],
        0.012,
        "OstraRubber",
    )
    # Diagnostic screen at the back.
    k.box((0.3, 0.97, -0.3), (0.2, 0.04, 0.15), "OstraPaintDark")
    k.box((0.3, 1.06, -0.32), (0.05, 0.16, 0.04), "OstraMetal", bev=False)
    screen_unit(k, (0.3, 1.24, -0.3), (0.46, 0.3, 0.06), tilt=12, turn=-12)
    k.path([(0.3, 1.1, -0.35), (0.25, 0.96, -0.42), (-0.1, 0.96, -0.4), (hx, 1.0, hz - 0.08)], 0.008, "OstraRubber")
    # Tools.
    wrench(k, (-0.75, 0.95, 0.25), 0.28, hanging=False, turn=10)
    screwdriver(k, (-0.85, 0.96, 0.05), (-0.6, 0.96, 0.02), "OstraContainerRed")
    k.box((-0.85, 0.99, -0.25), (0.3, 0.08, 0.22), "OstraContainerBlue")
    k.cyl((0.0, 1.02, -0.3), 0.04, 0.14, "OstraHazard", seg=8)
    for _ in range(4):
        k.cyl(
            (-0.05 + rnd.uniform(-0.15, 0.1), 0.955, 0.3 + rnd.uniform(-0.05, 0.05)), 0.012, 0.01, "OstraMetal", seg=6
        )


def suit_frame(k: Kit) -> None:
    """Maintenance gantry holding an empty armored suit upright (no helmet), 0.7 x 1.9 x 0.5, front +z."""
    k.box((0, 0.025, 0), (0.7, 0.05, 0.5), "OstraPaintDark")  # base plate
    k.box((0, 0.052, 0.22), (0.66, 0.006, 0.05), "OstraHazard", bev=False)
    for x in (-0.3, 0.3):
        k.box((x, 0.95, -0.21), (0.06, 1.85, 0.06), "OstraPaintDark")
        k.box((x, 0.08, -0.15), (0.08, 0.06, 0.16), "OstraPaintDark", bev=False)
    k.box((0, 1.85, -0.21), (0.66, 0.07, 0.07), "OstraPaintDark")
    k.box((0, 1.2, -0.21), (0.6, 0.05, 0.05), "OstraPaintDark", bev=False)
    k.box((0, 1.85, -0.17), (0.3, 0.03, 0.01), "OstraAmber", bev=False)
    for x in (-0.11, 0.11):  # clamp arms into the backpack
        k.box((x, 1.42, -0.17), (0.04, 0.05, 0.1), "OstraMetal", bev=False)
    k.path([(-0.2, 1.82, -0.21), (-0.2, 1.7, -0.19), (-0.08, 1.55, -0.15)], 0.018, "OstraRubber")
    k.path([(0.2, 1.82, -0.21), (0.22, 1.6, -0.2), (0.1, 1.5, -0.15)], 0.014, "OstraRubber")
    # The suit: backpack, tapered chest plate, abdomen, belt, collar.
    k.box((0, 1.3, -0.12), (0.34, 0.42, 0.14), "OstraPaintDark")
    k.box((0, 1.3, -0.12), (0.3, 0.06, 0.15), "OstraPaint", bev=False)
    k.prism_z(
        [(-0.15, 1.1), (0.15, 1.1), (0.21, 1.4), (0.16, 1.5), (-0.16, 1.5), (-0.21, 1.4)], -0.08, 0.12, "OstraPaint"
    )
    for s in (-1, 1):
        k.box((s * 0.085, 1.37, 0.13), (0.16, 0.2, 0.05), "OstraPaint", rot=C.rz(s * 4) @ C.ry(s * 14))
        k.box((s * 0.13, 1.5, 0.0), (0.08, 0.03, 0.26), "OstraPaintDark")
    k.box((0, 1.24, 0.125), (0.16, 0.08, 0.03), "OstraPaintDark")
    k.box((0, 1.26, 0.13), (0.04, 0.02, 0.01), "OstraAmber", bev=False)
    for y in (1.03, 1.08):
        k.box((0, y, 0.01), (0.27, 0.045, 0.19), "OstraPaintDark")
    k.box((0, 0.97, 0.01), (0.33, 0.07, 0.23), "OstraPaintDark")
    for x in (-0.12, 0.12):
        k.box((x, 0.97, 0.12), (0.07, 0.06, 0.04), "OstraPaintDark", bev=False)
    k.cyl((0, 1.53, 0.01), 0.1, 0.06, "OstraMetal", seg=16)
    k.cyl((0, 1.56, 0.01), 0.08, 0.02, "OstraPaintDark", seg=16)
    # Arms hanging.
    for s in (-1, 1):
        x = s * 0.25
        k.sphere((s * 0.23, 1.45, 0.0), 0.1, "OstraPaint", scale=(1.05, 0.75, 1.0), seg=12, rings=6)
        k.cyl((x, 1.27, 0.0), 0.05, 0.3, "OstraPaintDark", seg=10)
        k.cyl((x, 1.27, 0.0), 0.062, 0.18, "OstraPaint", seg=10)
        k.sphere((x, 1.1, 0.01), 0.05, "OstraMetal", seg=8, rings=4)
        k.cyl((x + s * 0.01, 0.96, 0.03), 0.058, 0.24, "OstraPaint", seg=10, r2=0.064)
        k.box((x + s * 0.012, 0.79, 0.035), (0.07, 0.13, 0.09), "OstraPaintDark")
    # Hips and legs.
    k.box((0, 0.87, 0.0), (0.32, 0.12, 0.22), "OstraPaint")
    for s in (-1, 1):
        k.box((s * 0.09, 0.79, 0.11), (0.12, 0.12, 0.02), "OstraPaint", rot=C.rx(10))
        x = s * 0.1
        k.cyl((x, 0.66, 0.0), 0.075, 0.38, "OstraPaintDark", seg=10)
        k.box((x, 0.68, 0.07), (0.13, 0.24, 0.04), "OstraPaint")
        k.box((x, 0.49, 0.07), (0.1, 0.09, 0.05), "OstraPaintDark")
        k.cyl((x, 0.31, 0.0), 0.07, 0.3, "OstraPaint", seg=10, r2=0.078)
        k.box((x, 0.115, 0.03), (0.12, 0.12, 0.25), "OstraPaintDark")
        k.box((x, 0.065, 0.035), (0.125, 0.03, 0.26), "OstraRubber", bev=False)


# --- gallery and hub -----------------------------------------------------------------------------------


def gallery_bench(k: Kit) -> None:
    """Long backless bench, 5.0 x 0.45 x 0.8, padded top sat on from both sides, sturdy metal legs."""
    for x in (-1.64, 0.0, 1.64):  # three pads with seams between them
        k.box((x, 0.405, 0), (1.62, 0.09, 0.76), "OstraFabric")
    for z in (-0.385, 0.385):
        k.rod((-2.46, 0.405, z), (2.46, 0.405, z), 0.012, "OstraRubber", seg=6)
    k.box((0, 0.335, 0), (4.96, 0.05, 0.72), "OstraPaintDark")  # seat pan
    k.box((0, 0.34, 0.37), (4.96, 0.04, 0.02), "OstraMetal", bev=False)
    k.box((0, 0.34, -0.37), (4.96, 0.04, 0.02), "OstraMetal", bev=False)
    for x in (-2.15, 0.0, 2.15):  # trapezoid leg frames
        k.prism_x([(-0.34, 0.0), (0.34, 0.0), (0.26, 0.31), (-0.26, 0.31)], x - 0.04, x + 0.04, "OstraPaintDark")
        k.box((x, 0.012, 0), (0.12, 0.024, 0.72), "OstraRubber", bev=False)
        k.box((x, 0.16, 0), (0.09, 0.1, 0.3), "OstraPaint")
    k.box((0, 0.15, 0), (4.3, 0.06, 0.08), "OstraPaintDark")  # stretcher
    k.box((0, 0.185, 0), (4.0, 0.012, 0.04), "OstraMetal", bev=False)


def kiosk(k: Kit) -> None:
    """Information pillar of the concourse hub, round, diameter 3.0, 3.2 high: heavy base, four teal screens at
    eye level, a ring of warm light at its crown, cables running up."""
    k.lathe((0, 0, 0), [(1.5, 0.0), (1.5, 0.14), (1.44, 0.2), (1.2, 0.22)], "OstraPaintDark", seg=40, bev=True)
    k.lathe((0, 0, 0), [(1.505, 0.06), (1.505, 0.09)], "OstraHazard", seg=40)
    k.torus((0, 0.225, 0), 1.25, 0.022, "OstraAmber", seg=40, tseg=4)
    k.lathe((0, 0, 0), [(1.05, 0.2), (1.05, 0.55), (0.95, 0.65), (0.6, 0.7)], "OstraPaint", seg=32, bev=True)
    for i in range(8):  # vents around the second tier
        a = 22.5 + 45 * i
        k.box((0, 0.4, 0), (0.3, 0.2, 0.03), "OstraGrating", bev=False, rot=C.rz(a), off=(0, 0, 1.055))
    k.cyl((0, 1.72, 0), 0.5, 2.06, "OstraPaint", seg=24)
    for i in range(4):  # ribs between the screens
        a = 45 + 90 * i
        k.box((0, 1.72, 0), (0.08, 2.06, 0.1), "OstraPaintDark", rot=C.rz(a), off=(0, 0, 0.52))
    for i in range(4):  # screen housings facing +z, +x, -z, -x
        rot = C.rz(90 * i)
        k.box((0, 1.7, 0), (0.78, 0.96, 0.18), "OstraPaintDark", rot=rot, off=(0, 0, 0.53))
        k.box((0, 1.7, 0), (0.66, 0.8, 0.01), "OstraScreen", bev=False, rot=rot, off=(0, 0, 0.623))
        k.box((0, 1.7, 0), (0.84, 0.04, 0.14), "OstraPaintDark", bev=False, rot=rot, off=(0, 0.5, 0.6))
        k.box((0, 1.7, 0), (0.1, 0.03, 0.01), "OstraAmber", bev=False, rot=rot, off=(0.3, -0.45, 0.625))
    for y in (1.12, 2.3):  # dark bands round the column
        k.cyl((0, y, 0), 0.515, 0.05, "OstraPaintDark", seg=24)
    for a in (38, 52, 128, 142, 218, 232, 308, 322):  # cables up the column, clamped
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        pts = [(ca * r, y, sa * r) for r, y in ((0.64, 0.69), (0.56, 0.8), (0.56, 2.7), (0.8, 2.9))]
        k.path(pts, 0.022, "OstraRubber", seg=6)
        for y in (1.0, 2.4):
            k.box((ca * 0.56, y, sa * 0.56), (0.07, 0.04, 0.06), "OstraMetal", bev=False, rot=C.rz(-a))
    k.lathe(
        (0, 0, 0),
        [(0.5, 2.72), (0.9, 2.92), (0.92, 3.04), (0.75, 3.12), (0.3, 3.2)],
        "OstraPaintDark",
        seg=32,
        bev=True,
    )
    k.lathe((0, 0, 0), [(0.925, 2.95), (0.925, 3.0)], "OstraLamp", seg=32)  # the crown's ring of light
    k.torus((0, 2.86, 0), 0.72, 0.025, "OstraLamp", seg=32, tseg=4)
    k.cyl((0, 3.19, 0), 0.32, 0.03, "OstraMetal", seg=20)
    for i in range(8):  # vents on the crown, readable from above
        a = 45 * i
        k.box((0, 3.165, 0), (0.12, 0.02, 0.22), "OstraGrating", bev=False, rot=C.rz(a), off=(0, 0, 0.55))


# --- build, preview, export ------------------------------------------------------------------------------

# name: (builder, Godot bounds (min, max) the mesh must stay within, bevel width)
MODELS = {
    "depot_counter": (depot_counter, ((-3.0, 0.0, -0.45), (3.0, 1.55, 0.45)), 0.012),
    "depot_shelf": (depot_shelf, ((-2.5, 0.0, -0.6), (2.5, 3.5, 0.6)), 0.012),
    "council_table": (council_table, ((-1.2, 0.0, -2.75), (1.2, 0.8, 2.75)), 0.012),
    "council_chair": (council_chair, ((-0.3, 0.0, -0.3), (0.3, 0.9, 0.3)), 0.015),
    "bar_counter": (bar_counter, ((-4.5, 0.0, -0.45), (4.5, 1.65, 0.45)), 0.012),
    "back_bar": (back_bar, ((-0.65, 0.0, -0.15), (0.65, 1.38, 0.15)), 0.01),
    "bar_wall_shelf": (bar_wall_shelf, ((-2.0, 1.15, 0.0), (2.0, 2.4, 0.35)), 0.01),
    "booth": (booth, ((-0.9, 0.0, -1.85), (0.9, 1.1, 1.85)), 0.02),
    "bar_stool": (bar_stool, ((-0.225, 0.0, -0.225), (0.225, 0.75, 0.225)), 0.01),
    "stall_parts": (stall_parts, ((-1.6, 0.0, -3.1), (1.6, 3.0, 0.9)), 0.012),
    "stall_trade": (stall_trade, ((-1.6, 0.0, -3.1), (1.6, 3.0, 0.9)), 0.012),
    "stall_dace": (stall_dace, ((-1.6, 0.0, -3.6), (1.6, 3.0, 0.9)), 0.012),
    "dace_bench": (dace_bench, ((-1.5, 0.0, -0.5), (1.5, 2.2, 0.4)), 0.012),
    "suit_bench": (suit_bench, ((-1.1, 0.0, -0.45), (1.1, 1.45, 0.45)), 0.012),
    "suit_frame": (suit_frame, ((-0.35, 0.0, -0.25), (0.35, 1.9, 0.25)), 0.012),
    "gallery_bench": (gallery_bench, ((-2.5, 0.0, -0.4), (2.5, 0.45, 0.4)), 0.015),
    "kiosk": (kiosk, ((-1.5, 0.0, -1.5), (1.5, 3.2, 1.5)), 0.015),
}


def pascal(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_"))


def check_bounds(name: str, st: dict) -> None:
    lo, hi = st["min"], st["max"]
    got_lo = (lo[0], lo[2], -hi[1])  # Blender -> Godot
    got_hi = (hi[0], hi[2], -lo[1])
    want_lo, want_hi = MODELS[name][1]
    bad = [
        f"{axis}: {got_lo[i]:+.2f}..{got_hi[i]:+.2f} (want {want_lo[i]:+.2f}..{want_hi[i]:+.2f})"
        for i, axis in enumerate("xyz")
        if got_lo[i] < want_lo[i] - 0.05 or got_hi[i] > want_hi[i] + 0.05
    ]
    print("BOUNDS", name, "ok" if not bad else "OUTSIDE " + "; ".join(bad))


def previews(name: str, st: dict) -> None:
    lo, hi = Vector(st["min"]), Vector(st["max"])
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 0.6)
    C.preview_scene(crystals=False, figure_location=(lo.x - 0.9, center.y + 0.4, 0.0))
    dist = radius * 2.9
    el, az = math.radians(35), math.radians(30)
    iso = center + Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * dist
    C.render_from(TMP / f"{name}_iso.png", iso, center, 50, 32, 640)
    az = math.radians(-25)
    eye = center + Vector((math.sin(az), -math.cos(az), 0.0)) * dist
    eye.z = 1.6
    C.render_from(TMP / f"{name}_eye.png", eye, center, 50, 32, 640)
    az = math.radians(200)
    back = center + Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * dist
    C.render_from(TMP / f"{name}_back.png", back, center, 50, 32, 640)


def build(name: str) -> dict:
    builder, _bounds, bevel = MODELS[name]
    C.reset(pascal(name))
    root = C.asset_root(pascal(name))
    kit = Kit(pascal(name), bevel)
    builder(kit)
    kit.finish(root)
    st = C.stats()
    print("MODEL", name, st["triangles"], "tris", C.tris_per_object())
    check_bounds(name, st)
    C.export_glb(PROPS / f"{name}.glb")
    previews(name, st)
    return st


def main() -> None:
    names = C.args() or list(MODELS)
    unknown = [n for n in names if n not in MODELS]
    if unknown:
        raise SystemExit(f"unknown models: {unknown}; known: {list(MODELS)}")
    for name in names:
        build(name)
    shots = [TMP / f"{n}_{view}.png" for n in MODELS for view in ("iso", "eye", "back")]
    C.contact_sheet(shots, TMP / "sheet.png", cols=9, tile=256)


main()
