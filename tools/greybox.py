"""Shared helpers for the greybox interiors built from data: the ship's hull (game/ship/hull_build.py)
and the stations' maps (game/space_station/*/*_build.py). Each builder lists its walls, boxes and
outer walls with windows on a `Greybox`, adds what's its own (floors, lights, props) and writes one
.tscn with `write`, which keeps the scene's and its resources' UIDs (tools/uids.sh adds them to a
new file) and fails with --check when the file differs.

Walls are boxes along x or z; a wall in front of what the camera must see goes into a group that
only casts shadows while the viewer is inside (see CutAway in game/camera/cut_away.gd), leaving a
low stub in a group that always shows. Groups map to parent nodes (`groups`: group -> node path).
"""

import pathlib
import re
import sys

NL = "\n"
# Window panes: hidden with their wall (see CutAway.HIDE_GROUP in game/camera/cut_away.gd).
HIDE_GROUP = "cutaway_hide"


def g(c):
    c = round(c, 4)
    if c == 0:
        c = 0.0
    return f"{c:g}"


def vec(v):
    return f"Vector3({', '.join(g(c) for c in v)})"


def xform(origin, basis="1, 0, 0, 0, 1, 0, 0, 0, 1"):
    return f"Transform3D({basis}, {', '.join(g(c) for c in origin)})"


def scaled(size, origin):
    x, y, z = (g(c) for c in size)
    return xform(origin, f"{x}, 0, 0, 0, {y}, 0, 0, 0, {z}")


def sid(s):
    return "x".join(g(c) for c in s).replace(".", "_").replace("-", "m")


def unique(sizes):
    """Sizes in order, one per id (sizes a rounding error apart share one)."""
    seen = {}
    for s in sorted(sizes):
        seen.setdefault(sid(s), s)
    return list(seen.values())


def windows_for(x0, x1, spacing=9, width=4.0, margin=1.5):
    """Evenly spaced windows along a room's outer wall, one per ~`spacing` m, at most `width` wide
    and `margin` narrower than their share of the wall."""
    w = x1 - x0
    n = max(1, int(w // spacing))
    return [(x0 + w * (i + 0.5) / n, min(width, w / n - margin)) for i in range(n)]


class Greybox:
    """Wall pieces (name, size, center, group, stub_group or None, kind: "both", "shape" or "mesh")
    and window panes (name, size, center, group, sill), turned into sub-resources and nodes."""

    def __init__(self, groups, material_id, material_lines, stub=1.0, door=3.0, sill=1.0, window_height=2.0):
        self.groups = groups
        self.material_id = material_id
        self.material_lines = material_lines
        self.stub = stub
        self.door = door
        self.sill = sill
        self.window_height = window_height
        self.walls = []
        self.glass = []

    def wall(
        self, name, axis, fixed, a0, a1, y0, y1, doors=(), group=None, stub_group=None, front=None, door_height=None
    ):
        """Wall along `axis` at `fixed`, from a0 to a1 and y0 to y1, doors as (center, width) from
        y0 up to y0 + door_height (a zero-width door just splits the wall). `front` = (group,
        stub_group) for the pieces of a z wall at z >= 1 (in front of a corridor along z = 0), which
        would hide players from the camera."""
        group = group or self.default_group()
        door_height = self.door if door_height is None else door_height

        def piece(pname, b0, b1, c0, c1, sg):
            if b1 - b0 <= 0.001 or c1 - c0 <= 0.001:
                return
            mid = (b0 + b1) / 2
            gr = group
            if axis == "x":
                size, center = (b1 - b0, c1 - c0, 0.5), (mid, (c0 + c1) / 2, fixed)
            else:
                size, center = (0.5, c1 - c0, b1 - b0), (fixed, (c0 + c1) / 2, mid)
                if front and b0 >= 1.0:
                    gr, sg = front
            self.walls.append((pname, size, center, gr, sg, "both"))

        edges = [a0]
        for c, w in sorted(doors):
            edges += [c - w / 2, c + w / 2]
        edges.append(a1)
        for i in range(0, len(edges), 2):
            suffix = "" if len(edges) == 2 else str(i // 2 + 1)
            piece(name + suffix, edges[i], edges[i + 1], y0, y1, stub_group)
        for i, (c, w) in enumerate(sorted(doors)):
            suffix = "" if len(doors) == 1 else str(i + 1)
            piece(name + "Lintel" + suffix, c - w / 2, c + w / 2, y0 + door_height, y1, None)

    def box(self, name, size, center, group=None, kind="both"):
        self.walls.append((name, size, center, group or self.default_group(), None, kind))

    def outer_wall(self, name, axis, fixed, a0, a1, y0, y1, wins, group=None, stub_group=None, sill=None, height=None):
        """One collision shape for the whole wall; its mesh goes around the windows (sill below,
        header above), with glass in them."""
        group = group or self.default_group()
        sill = self.sill if sill is None else sill
        height = self.window_height if height is None else height
        if axis == "x":
            size, center = (a1 - a0, y1 - y0, 0.5), ((a0 + a1) / 2, (y0 + y1) / 2, fixed)
        else:
            size, center = (0.5, y1 - y0, a1 - a0), (fixed, (y0 + y1) / 2, (a0 + a1) / 2)
        self.walls.append((name, size, center, group, stub_group, "shape"))

        def piece(pname, b0, b1, c0, c1):
            if b1 - b0 <= 0.001 or c1 - c0 <= 0.001:
                return
            mid = (b0 + b1) / 2
            if axis == "x":
                s, c = (b1 - b0, c1 - c0, 0.5), (mid, (c0 + c1) / 2, fixed)
            else:
                s, c = (0.5, c1 - c0, b1 - b0), (fixed, (c0 + c1) / 2, mid)
            self.walls.append((pname, s, c, group, None, "mesh"))

        edges = [a0]
        for c, w in sorted(wins):
            edges += [c - w / 2, c + w / 2]
        edges.append(a1)
        for i in range(0, len(edges), 2):
            piece(f"{name}Part{i // 2 + 1}", edges[i], edges[i + 1], y0, y1)
        for i, (c, w) in enumerate(sorted(wins)):
            piece(f"{name}Sill{i + 1}", c - w / 2, c + w / 2, y0, y0 + sill)
            piece(f"{name}Header{i + 1}", c - w / 2, c + w / 2, y0 + sill + height, y1)
            wy = y0 + sill + height / 2
            if axis == "x":
                self.glass.append((f"{name}Glass{i + 1}", (w, height, 0.06), (c, wy, fixed), group))
            else:
                self.glass.append((f"{name}Glass{i + 1}", (0.06, height, w), (fixed, wy, c), group))

    def default_group(self):
        return next(iter(self.groups))

    def subresources(self):
        """The wall material, the walls' shapes and meshes, the glass and the stubs."""
        mid = self.material_id
        subs = [f'[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_{mid}"]'] + self.material_lines + [""]
        for s in unique({w[1] for w in self.walls if w[5] != "mesh"}):
            subs += [f'[sub_resource type="BoxShape3D" id="BoxShape3D_{sid(s)}"]', f"size = {vec(s)}", ""]
        for s in unique({w[1] for w in self.walls if w[5] != "shape"}):
            subs += [
                f'[sub_resource type="BoxMesh" id="BoxMesh_{sid(s)}"]',
                f'material = SubResource("StandardMaterial3D_{mid}")',
                f"size = {vec(s)}",
                "",
            ]
        subs += ['[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_glass"]', "transparency = 1"]
        subs += ["albedo_color = Color(0.6, 0.8, 0.95, 0.2)", "metallic = 0.4", "roughness = 0.05", ""]
        for s in unique({gl[1] for gl in self.glass}):
            subs += [
                f'[sub_resource type="BoxMesh" id="BoxMesh_glass_{sid(s)}"]',
                'material = SubResource("StandardMaterial3D_glass")',
                f"size = {vec(s)}",
                "",
            ]
        for s in unique({(w[1][0], self.stub, w[1][2] - 0.02) for w in self.walls if w[4]}):
            subs += [
                f'[sub_resource type="BoxMesh" id="BoxMesh_stub_{sid(s)}"]',
                f'material = SubResource("StandardMaterial3D_{mid}")',
                f"size = {vec(s)}",
                "",
            ]
        return subs

    def nodes(self, body="."):
        """The walls' collision shapes (under `body`) and meshes (under their group's node), their
        stubs and the glass."""
        nodes = []
        for name, size, center, group, stub_group, kind in self.walls:
            if kind != "mesh":
                nodes += [
                    f'[node name="{name}Shape" type="CollisionShape3D" parent="{body}"]',
                    f"transform = {xform(center)}",
                    f'shape = SubResource("BoxShape3D_{sid(size)}")',
                    "",
                ]
            if kind != "shape":
                nodes += [
                    f'[node name="{name}" type="MeshInstance3D" parent="{self.groups[group]}"]',
                    f"transform = {xform(center)}",
                    f'mesh = SubResource("BoxMesh_{sid(size)}")',
                    "",
                ]
            if stub_group:
                s = (size[0], self.stub, size[2] - 0.02)
                y0 = center[1] - size[1] / 2
                nodes += [
                    f'[node name="{name}Stub" type="MeshInstance3D" parent="{self.groups[stub_group]}"]',
                    f"transform = {xform((center[0], y0 + self.stub / 2, center[2]))}",
                    f'mesh = SubResource("BoxMesh_stub_{sid(s)}")',
                    "",
                ]
        # Glass lets light in and doesn't cast shadows; it's shown or hidden with its wall.
        for name, size, center, group in self.glass:
            nodes += [
                f'[node name="{name}" type="MeshInstance3D" parent="{self.groups[group]}" groups=["{HIDE_GROUP}"]]',
                f"transform = {xform(center)}",
                "cast_shadow = 0",
                f'mesh = SubResource("BoxMesh_glass_{sid(size)}")',
                "",
            ]
        return nodes


def write(out, root, ext_resources, subs, nodes, script_name):
    """Writes the scene to `out` (a path under the repo `root`), keeping the UIDs of the scene and
    of its `ext_resources` ((type, path, id) each); with --check on the command line, only fails
    if the file differs."""
    old = out.read_text(encoding="utf-8") if out.exists() else ""
    scene_uid = re.search(r'^\[gd_scene [^\]]*?( uid="[^"]+")', old)
    header = ["[gd_scene format=3%s]" % (scene_uid.group(1) if scene_uid else ""), ""]
    for kind, path, rid in ext_resources:
        uid = re.search(rf'\[ext_resource [^\]]*?( uid="[^"]+") path="{re.escape(path)}"', old)
        header += [f'[ext_resource type="{kind}"{uid.group(1) if uid else ""} path="{path}" id="{rid}"]']
    header += [""]
    text = NL.join(header + subs + nodes).rstrip(NL) + NL
    text = re.sub(r"\n{3,}", NL + NL, text)
    if "--check" in sys.argv:
        if text != old:
            sys.exit(f"{out.relative_to(root)} differs from what {script_name} builds: run it, don't edit the file")
        return None
    out.write_text(text, encoding="utf-8", newline=NL)
    return text


def repo_root(script):
    """The repo root, from a builder at game/<area>/.../<script>."""
    path = pathlib.Path(script).resolve()
    for parent in path.parents:
        if (parent / "project.godot").exists():
            return parent
    raise SystemExit("project.godot not found above " + str(path))
