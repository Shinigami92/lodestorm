"""Sealed case: a quest item, the ruggedized hard case of a lost expedition. A quest step asks the player to recover
it at a site (an abandoned camp, a wreck): it lies on the ground there, the player picks it up and carries it
strapped across the bottom of the backpack until back aboard. Dark olive-grey composite shell with a protruding
seam flange, steel corner guards, two heavy latches and a carry handle on the front, strap loops on the back, a
sealed-status panel with an amber light strip on the lid's front edge; scuffed, dusty, no markings.

Run from the repo root (see docs/technical/assets.md):
    tools/blender.sh assets/quests/sealed_case/source/sealed_case_build.py wip r1 [iso,hero,back,top,close,scale,game]
    tools/blender.sh assets/quests/sealed_case/source/sealed_case_build.py final

Everything it writes goes to tmp/assets/sealed_case/: "wip <tag> [views]" renders quick previews into
wip/<tag>_*.png ("game" is the game's orthographic camera at its pixel density, "scale" the iso view with the
1.8 m figure); "final" renders the preview set, a contact sheet (sheet.png) and saves the procedural
sealed_case_procedural.blend that sealed_case_bake.py turns into the game asset.

Game contract: Blender Z-up meters (glTF turns them into Godot's Y-up), the origin at the bottom center, the case
lying flat, its front (latches, handle, status panel) towards -Y. Under the root empty "SealedCase": "Case" (the
body with all hardware, one object, gets the baked atlas, material "SealedCase") and "Glow" (the amber seal light
strip, own constant emissive material; the game may override it). About 0.55 m long (X), 0.36 m deep (Y), 0.21 m
tall. Triangle budget under ~3000, one 1024 texture set, TBD (playtest).
"""

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = ROOT / "tmp" / "assets" / "sealed_case"
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import bmesh
import bpy
from mathutils import Vector

import common as C
from common import T, rx, ry

ARGV = C.args()
MODE = ARGV[0] if ARGV else "wip"
TAG = ARGV[1] if len(ARGV) > 1 else "r0"
VIEWS = ARGV[2].split(",") if len(ARGV) > 2 else ["iso", "hero"]

ASSET = "SealedCase"
AMBER = (1.0, 0.522, 0.073)  # linear for the seal light's sRGB Color(1.0, 0.75, 0.3)

# --- layout (meters, Z-up, front = -Y, origin = bottom center) ---------------------------------------

HX, HY, R = 0.262, 0.167, 0.036  # half extents and corner radius of the shell
FLANGE = 0.008  # how far the seam flange and the corner guards stand out of the shell
BODY_Z = (0.012, 0.112)  # lower shell
CORE_Z = (0.106, 0.134)  # gasket band in the seam
FLANGE_LO = (0.098, 0.1185)  # seam flange, lower half
FLANGE_HI = (0.1215, 0.142)  # seam flange, lid half
LID_Z = (0.128, 0.188)
PLATEAU = (0.236, 0.141, 0.03, 0.188, 0.2)  # raised top of the lid: half extents, corner radius, z0, z1
GUARD_LO = (0.0, 0.058)  # corner guards: the bottom ones are the feet
GUARD_HI = (0.142, 0.207)
LATCH_X = 0.165
HANDLE_X = 0.075
LOOP_X = 0.14
PANEL_Y = -0.1  # seal panel on the plateau, along the front edge
STRIP = (0.27, 0.036)  # glowing strip: length, width
FRONT_STRIP = (0.17, 0.015)  # its front half on the lid's front face: length, height
FRONT_Z = 0.165


# --- mesh builder -----------------------------------------------------------------------------------


class Part(C.Part):
    """common.Part with weighted bevels: only the hard edges (> 35 degrees) get a bevel, small parts (detail = True)
    keep sharp edges instead (saves triangles)."""

    def __init__(self, name: str, mats: list, bevel: tuple[float, int] | None = (0.003, 1)):
        super().__init__(name, mats, bevel)
        self.weight = self.bm.edges.layers.float.new("bevel_weight_edge")
        self.detail = False

    def _tag(self, verts, mi: int, smooth: bool = True):
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = mi
            f.smooth = smooth
        for e in {e for f in faces for e in f.edges}:
            hard = e.is_manifold and e.calc_face_angle(0.0) > math.radians(35)
            e[self.weight] = 1.0 if hard and not self.detail else 0.0
            e.smooth = not (hard and self.detail)
        return verts

    def xcyl(self, loc, r, length, seg=8, mi=0, scale=(1, 1, 1)):
        """Cylinder along X (hinge pins, the handle's grip)."""
        return self.cyl(loc, r, length, seg, rot=ry(90), mi=mi, scale=scale)

    def _bevel(self, obj: bpy.types.Object) -> None:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = self.bev[0]
        mod.segments = self.bev[1]
        mod.limit_method = "WEIGHT"
        mod.harden_normals = True
        obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL").keep_sharp = True

    def finish(self, parent) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        return super().finish(parent)


def corner_centers(hx: float, hy: float, r: float) -> list:
    """Centers of the four corner arcs, counter-clockwise from the +X/+Y corner."""
    return [(hx - r, hy - r), (-(hx - r), hy - r), (-(hx - r), -(hy - r)), (hx - r, -(hy - r))]


def rrect(hx: float, hy: float, r: float, seg: int = 3) -> list:
    """Rounded rectangle (counter-clockwise points)."""
    pts = []
    for q, (cx, cy) in enumerate(corner_centers(hx, hy, r)):
        for k in range(seg + 1):
            a = math.radians(q * 90 + k * 90 / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def guard_profile(q: int, out: float, inner: float, leg: float, seg: int = 4) -> list:
    """L-shaped outline of a corner guard around corner q: the shell's corner arc grown by `out`, legs running
    `leg` along both faces, its inner edge `inner` inside the shell (buried)."""
    cx, cy = corner_centers(HX, HY, R)[q]
    ro, ri = R + out, max(R - inner, 0.004)
    base = math.radians(q * 90)
    cb, sb = math.cos(base), math.sin(base)

    def local(dx: float, dy: float) -> tuple[float, float]:
        return (cx + dx * cb - dy * sb, cy + dx * sb + dy * cb)

    pts = [local(ro, -leg)]
    pts += [
        local(ro * math.cos(math.radians(k * 90 / seg)), ro * math.sin(math.radians(k * 90 / seg)))
        for k in range(seg + 1)
    ]
    pts.append(local(-leg, ro))
    pts.append(local(-leg, ri))
    pts += [
        local(ri * math.cos(math.radians(90 - k * 90 / seg)), ri * math.sin(math.radians(90 - k * 90 / seg)))
        for k in range(seg + 1)
    ]
    pts.append(local(ri, -leg))
    return pts


def inset_top(part: Part, verts, z: float, thickness: float, depth: float) -> None:
    """Inset the up-facing face(s) of a fresh primitive at height z (a recessed panel)."""
    faces = [
        f
        for f in {f for v in verts for f in v.link_faces}
        if f.normal.z > 0.9 and abs(f.calc_center_median().z - z) < 1e-4
    ]
    bmesh.ops.inset_individual(part.bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)


# --- materials --------------------------------------------------------------------------------------


def _src(sock: bpy.types.NodeSocket):
    """What drives a BSDF input: its link's socket or its constant."""
    if sock.is_linked:
        return sock.links[0].from_socket
    v = sock.default_value
    return tuple(v)[:3] if hasattr(v, "__len__") else v


def rescale(mat: bpy.types.Material, noise_factor: float, ao_distance: float) -> None:
    """common's materials are tuned for a 3.6 m machine: shrink their noise and cavity sizes to a 0.55 m case."""
    for n in mat.node_tree.nodes:
        if n.bl_idname == "ShaderNodeTexNoise":
            n.inputs["Scale"].default_value *= noise_factor
        elif n.bl_idname == "ShaderNodeAmbientOcclusion":
            n.inputs["Distance"].default_value = ao_distance
        elif n.bl_idname == "ShaderNodeBump":
            n.inputs["Distance"].default_value *= 0.4


def add_dust(mat: bpy.types.Material, amount: float = 0.6, color=(0.115, 0.1, 0.08)) -> None:
    """Dust on the up-facing surfaces and in the cavities, dirt along the bottom (it lay on the ground for years)."""
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nrm = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Normal"], nrm.inputs["Vector"])
    pos = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], pos.inputs["Vector"])
    blot = C._ramp(nt, 0.48, 0.72, C._noise(nt, 9.0, 6.0, 0.62).outputs["Fac"])
    speck = C._ramp(nt, 0.35, 0.7, C._noise(nt, 140.0, 4.0, 0.6).outputs["Fac"])
    up = C._math(nt, "MULTIPLY", C._ramp(nt, 0.4, 0.95, nrm.outputs["Z"]), blot)
    up = C._math(nt, "MULTIPLY", up, speck)
    low = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.004, 0.05, pos.outputs["Z"]))
    low = C._math(nt, "MULTIPLY", low, C._ramp(nt, 0.3, 0.6, C._noise(nt, 30.0, 5.0, 0.6).outputs["Fac"]))
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.02
    crevice = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.5, 0.95, ao.outputs["AO"]))
    total = C._math(nt, "ADD", up, C._math(nt, "MULTIPLY", low, 0.9), clamp=True)
    total = C._math(nt, "ADD", total, C._math(nt, "MULTIPLY", crevice, 0.45), clamp=True)
    mask = C._math(nt, "MULTIPLY", total, amount, clamp=True)
    nt.links.new(C._mix_color(nt, mask, _src(bsdf.inputs["Base Color"]), color), bsdf.inputs["Base Color"])
    nt.links.new(C._mix_float(nt, mask, _src(bsdf.inputs["Roughness"]), 0.93), bsdf.inputs["Roughness"])
    nt.links.new(C._mix_float(nt, mask, _src(bsdf.inputs["Metallic"]), 0.0), bsdf.inputs["Metallic"])


def mat_composite(name: str, color, roughness: float = 0.7) -> bpy.types.Material:
    """Molded composite shell: slightly blotchy color, lighter scuffs on the worn edges and squiggly scratches on
    the faces (scratched composite turns pale, it shows no metal), grime in the cavities, a fine molded stipple."""
    mat, nt, bsdf = C._new_material(name)
    breakup = C._noise(nt, 26.0, 6.0, 0.6)
    tone = C._noise(nt, 3.5, 3.0, 0.5)
    paint = C._mix_color(nt, breakup.outputs["Fac"], tuple(c * 0.82 for c in color), tuple(c * 1.15 for c in color))
    paint = C._mix_color(nt, C._ramp(nt, 0.35, 0.7, tone.outputs["Fac"]), tuple(c * 0.85 for c in color), paint)
    # Scuffs: convex edges broken up by noise.
    edge = C._ramp(nt, 0.02, 0.1, C._bevel_edge(nt, 0.005))
    scuff = C._math(nt, "MULTIPLY", edge, C._ramp(nt, 0.4, 0.62, C._noise(nt, 55.0, 8.0, 0.7).outputs["Fac"]))
    # Scratches: thin contour lines of a noise, only in sparse patches.
    line = C._noise(nt, 7.0, 3.0, 0.5, distortion=0.4)
    dist = C._math(nt, "ABSOLUTE", C._math(nt, "SUBTRACT", line.outputs["Fac"], 0.5))
    lines = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.0, 0.006, dist))
    patches = C._ramp(nt, 0.55, 0.68, C._noise(nt, 5.0, 2.0, 0.5).outputs["Fac"])
    scratch = C._math(nt, "MULTIPLY", lines, patches)
    worn = C._math(nt, "MAXIMUM", scuff, C._math(nt, "MULTIPLY", scratch, 0.8))
    # Grime in the cavities.
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.03
    grime = C._math(nt, "SUBTRACT", 1.0, C._ramp(nt, 0.35, 0.95, ao.outputs["AO"]))
    base = C._mix_color(nt, worn, paint, (0.2, 0.2, 0.185))
    base = C._mix_color(nt, C._math(nt, "MULTIPLY", grime, 0.7), base, (0.02, 0.019, 0.016))
    nt.links.new(base, bsdf.inputs["Base Color"])
    rough = C._mix_float(nt, breakup.outputs["Fac"], roughness - 0.08, roughness + 0.08)
    rough = C._mix_float(nt, worn, rough, 0.78)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    stipple = C._noise(nt, 420.0, 2.0, 0.5).outputs["Fac"]
    height = C._math(nt, "SUBTRACT", stipple, C._math(nt, "MULTIPLY", scratch, 0.6))
    C._bump(nt, bsdf, height, 0.15, 0.0008)
    return mat


def mat_panel(name: str = "SealPanel", color=(0.018, 0.019, 0.021)) -> bpy.types.Material:
    """Dark graphite plastic of the seal panel and the gasket."""
    mat, nt, bsdf = C._new_material(name)
    noise = C._noise(nt, 60.0, 4.0, 0.55)
    nt.links.new(
        C._mix_color(nt, noise.outputs["Fac"], tuple(c * 0.8 for c in color), tuple(c * 1.4 for c in color)),
        bsdf.inputs["Base Color"],
    )
    nt.links.new(C._mix_float(nt, noise.outputs["Fac"], 0.38, 0.55), bsdf.inputs["Roughness"])
    return mat


def make_materials() -> None:
    global SHELL, GUARD, STEEL, RUBBER, PANEL, CASE_MATS, GLOW
    SHELL = mat_composite("Shell", (0.05, 0.057, 0.034))  # sRGB about (0.25, 0.26, 0.2): dark olive grey
    GUARD = C.mat_painted_metal("Guard", (0.03, 0.031, 0.033), wear=0.8, grime=0.4, roughness=0.42)
    rescale(GUARD, 4.0, 0.025)
    C.bevel_wear(GUARD, lo=0.015, hi=0.06, radius=0.004)
    STEEL = C.mat_bare_metal("Steel", (0.36, 0.36, 0.37), 0.36)
    rescale(STEEL, 4.0, 0.025)
    RUBBER = C.mat_rubber("Rubber", (0.022, 0.021, 0.02))
    PANEL = mat_panel()
    add_dust(SHELL, 0.4)
    add_dust(GUARD, 0.55)
    add_dust(STEEL, 0.35)
    add_dust(RUBBER, 0.6)
    add_dust(PANEL, 0.3)
    CASE_MATS = [SHELL, GUARD, STEEL, RUBBER, PANEL]
    GLOW = C.mat_emissive("SealedCase_Glow", AMBER, 1.5)


M_SHELL, M_GUARD, M_STEEL, M_RUBBER, M_PANEL = 0, 1, 2, 3, 4


# --- parts ------------------------------------------------------------------------------------------


def build_shell(case: Part) -> None:
    case.prism(rrect(HX, HY, R), *BODY_Z, mi=M_SHELL)
    case.prism(rrect(HX - 0.004, HY - 0.004, R - 0.004), *CORE_Z, mi=M_RUBBER)
    case.prism(rrect(HX, HY, R), *LID_Z, mi=M_SHELL)
    hx, hy, r, z0, z1 = PLATEAU
    inset_top(case, case.prism(rrect(hx, hy, r), z0, z1, mi=M_SHELL), z1, 0.022, -0.005)
    fl = rrect(HX + FLANGE, HY + FLANGE, R + FLANGE)
    case.prism(fl, *FLANGE_LO, mi=M_SHELL)
    case.prism(fl, *FLANGE_HI, mi=M_SHELL)
    # Two low ribs across the lid behind the seal panel (they catch the light from the high camera).
    for y in (0.0, 0.07):
        case.box((0, y, z1 - 0.003), (0.36, 0.016, 0.01), mi=M_SHELL)
    # Molded ribs down the short sides (stiffeners), between the guards.
    case.detail = True
    for sx in (-1, 1):
        for y in (-0.045, 0.045):
            case.box((sx * (HX + 0.003), y, (BODY_Z[0] + FLANGE_LO[0]) / 2 + 0.006), (0.008, 0.016, 0.07), mi=M_SHELL)
    case.detail = False


def build_guards(case: Part) -> None:
    for q in range(4):
        for z0, z1 in (GUARD_LO, GUARD_HI):
            case.prism(guard_profile(q, FLANGE + 0.002, 0.022, 0.05, seg=3), z0, z1, mi=M_GUARD)


def build_latch(case: Part, x: float) -> None:
    y = -HY
    case.box((x, y - 0.004, 0.074), (0.078, 0.012, 0.032), mi=M_GUARD)  # hinge base on the shell
    case.detail = True
    case.xcyl((x, y - 0.013, 0.076), 0.0075, 0.082, seg=8, mi=M_STEEL)  # hinge pin
    case.detail = False
    lever = T((x, y - 0.0165, 0.117), rx(-3))
    case.box(lever @ Vector((0, 0, 0)), (0.064, 0.012, 0.09), rot=rx(-3), mi=M_GUARD)  # the lever over the seam
    case.box(lever @ Vector((0, -0.0075, -0.004)), (0.036, 0.004, 0.05), rot=rx(-3), mi=M_STEEL)  # thumb pad
    case.box((x, y - 0.011, 0.159), (0.056, 0.016, 0.012), mi=M_GUARD)  # hook over the keeper
    case.box((x, y - 0.004, 0.167), (0.078, 0.012, 0.03), mi=M_GUARD)  # keeper on the lid


def build_handle(case: Part) -> None:
    y = -HY
    for sx in (-1, 1):
        case.box((sx * HANDLE_X, y - 0.008, 0.068), (0.03, 0.018, 0.044), mi=M_GUARD)  # mounts
    case.box((0, y - 0.001, 0.066), (0.13, 0.004, 0.05), mi=M_PANEL)  # dark recess behind the grip
    case.xcyl((0, y - 0.013, 0.058), 0.011, 2 * HANDLE_X + 0.01, seg=8, mi=M_RUBBER, scale=(0.75, 1, 1))  # grip


def build_loops(case: Part) -> None:
    """Strap loops on the back: staples standing off the shell, the strap runs through them along X."""
    y = HY
    for sx in (-1, 1):
        x = sx * LOOP_X
        case.box((x, y + 0.003, 0.062), (0.05, 0.008, 0.064), mi=M_GUARD)  # riveted plate
        case.detail = True
        for dz in (-0.022, 0.022):
            case.beam((x, y + 0.006, 0.062 + dz), (x, y + 0.026, 0.062 + dz), 0.034, 0.009, (1, 0, 0), mi=M_STEEL)
        case.beam((x, y + 0.026, 0.035), (x, y + 0.026, 0.089), 0.034, 0.009, (1, 0, 0), mi=M_STEEL)
        case.detail = False


def build_panel(case: Part) -> None:
    """Seal panel on the plateau along the front edge: a dark plate with a bezel around the strip, a purge valve."""
    z = PLATEAU[4]
    length, width = STRIP
    case.box((0, PANEL_Y, z + 0.0035), (length + 0.05, width + 0.03, 0.007), mi=M_PANEL)
    case.detail = True
    for sy in (-1, 1):
        case.box((0, PANEL_Y + sy * (width / 2 + 0.005), z + 0.0085), (length + 0.03, 0.01, 0.004), mi=M_GUARD)
    for sx in (-1, 1):
        case.box((sx * (length / 2 + 0.01), PANEL_Y, z + 0.0085), (0.02, width, 0.004), mi=M_GUARD)
    case.cyl((0.195, PANEL_Y, z + 0.006), 0.016, 0.012, seg=12, mi=M_GUARD)  # purge valve
    case.cyl((0.195, PANEL_Y, z + 0.013), 0.009, 0.004, seg=12, mi=M_STEEL)
    case.detail = False
    # Its front half on the lid's front face, between the latches: the seal light wraps over the front edge.
    case.box((0, -HY - 0.003, FRONT_Z), (FRONT_STRIP[0] + 0.03, 0.006, FRONT_STRIP[1] + 0.02), mi=M_PANEL)


def build_glow(root) -> None:
    glow = Part("Glow", [GLOW], bevel=None)
    length, width = STRIP
    glow.box((0, PANEL_Y, PLATEAU[4] + 0.008), (length, width, 0.003))
    glow.box((0, -HY - 0.0065, FRONT_Z), (FRONT_STRIP[0], 0.003, FRONT_STRIP[1]))
    glow.finish(root)


def build() -> bpy.types.Object:
    root = C.asset_root(ASSET)
    case = Part("Case", CASE_MATS)
    build_shell(case)
    build_guards(case)
    for sx in (-1, 1):
        build_latch(case, sx * LATCH_X)
    build_handle(case)
    build_loops(case)
    build_panel(case)
    case.finish(root)
    build_glow(root)
    return root


# --- previews ---------------------------------------------------------------------------------------

CENTER = (0.0, 0.0, 0.1)
GAME_PX_PER_M = 1080 / 20.0  # the game's orthographic camera shows 20 m of height on a 1080 p screen
CUSTOM_VIEWS = {  # location relative to CENTER, lens
    "top": ((0.05, -0.05, 1.6), 50),
    "close": ((0.35, -0.42, 0.22), 40),
    "right": ((0.9, -0.1, 0.25), 50),
}


def set_figure(visible: bool) -> None:
    for child in bpy.data.objects["PreviewFigure"].children:
        child.hide_render = not visible


def render_game_view(path: pathlib.Path, samples: int, size: int) -> None:
    """The game's camera: orthographic along the +X/-Y diagonal, 35.26 degrees down, at the game's pixel density
    on a 1080 p screen (the crop is size px wide)."""
    C._render_settings(samples, size)
    cam = C._camera("custom")
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size / GAME_PX_PER_M
    down = math.radians(35.264)
    target = Vector((0.25, 0.25, 0.4))
    cam.location = target + Vector((math.cos(down) / math.sqrt(2), -math.cos(down) / math.sqrt(2), math.sin(down))) * 40
    cam.data.clip_end = 100
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    C._write_render(path)


def render_view(path: pathlib.Path, view: str, samples: int, size: int) -> None:
    set_figure(view in ("scale", "game"))
    if view == "iso":
        C.render(path, view="iso", samples=samples, size=size, target=CENTER, zoom=0.1)
    elif view in ("hero", "back"):
        C.render(path, view=view, samples=samples, size=size, target=CENTER, zoom=0.13)
    elif view == "scale":
        C.render(path, view="iso", samples=samples, size=size, target=(0.3, 0.25, 0.6), zoom=0.3)
    elif view == "game":
        render_game_view(path, samples, size)
    else:
        offset, lens = CUSTOM_VIEWS[view]
        C.render_from(path, Vector(CENTER) + Vector(offset), CENTER, lens, samples, size)


FINAL_VIEWS = ["iso", "hero", "back", "top", "close", "scale", "game"]


def main() -> None:
    C.reset(ASSET)
    make_materials()
    build()
    print("STATS per object", C.tris_per_object())
    print("STATS", C.stats())
    C.preview_scene(crystals=False, figure_location=(0.75, 0.6, 0.0))
    if MODE == "final":
        paths = []
        for view in FINAL_VIEWS:
            p = OUT / f"render_{view}.png"
            render_view(p, view, samples=96, size=1024 if view != "game" else 512)
            paths.append(p)
        C.contact_sheet(paths, OUT / "sheet.png", cols=4, tile=512)
        C.save_blend(OUT / "sealed_case_procedural.blend")
    else:
        for view in VIEWS:
            if view != "none":
                render_view(OUT / "wip" / f"{TAG}_{view}.png", view, samples=32, size=512 if view == "game" else 640)


main()
