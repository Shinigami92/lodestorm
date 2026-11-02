"""Node-tree helpers of the asset scripts' procedural materials, one base per family of kits that grew from the same
copy: `MatNodes` (a material of its own: frost, lairs, meteor, vein, the colony part kits), `ShaderNodes` (a node tree
handed in: salt, field, wreck, structures, the colony kits) and `TreeNodes` (overgrowth, plants). A kit's class
inherits its family's base and overrides what it does its own way (a kit's `ramp` may mean something else than
another's), so its materials stay exactly what they were.
"""

import bpy

import common as C


class MatNodes:
    """The frost, lairs, meteor, vein, cpart kits' node helper (see the module)."""

    def __init__(self, name: str):
        self.mat, self.nt, self.bsdf = C._new_material(name)
        self.geo = self.nt.nodes.new("ShaderNodeNewGeometry")
        self.obj = self.nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]

    def math(self, op, a, b=None, c=None, clamp=False):
        return C._math(self.nt, op, a, b, c, clamp)

    def noise(self, scale, detail=4.0, rough=0.6, vector=None):
        return C._noise(self.nt, scale, detail, rough, vector=vector or self.obj).outputs["Fac"]

    def ramp(self, a, b, src):
        return C._ramp(self.nt, a, b, src)

    def mix(self, fac, a, b):
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b):
        return C._mix_float(self.nt, fac, a, b)

    def scale(self, col, fac):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = "SCALE"
        self.nt.links.new(col, n.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, n.inputs["Scale"])
        else:
            n.inputs["Scale"].default_value = fac
        return n.outputs[0]

    def facet(self):
        n = self.nt.nodes.new("ShaderNodeAttribute")
        n.attribute_type = "GEOMETRY"
        n.attribute_name = "facet"
        return n.outputs["Fac"]

    def up(self):
        """World Z of the shading normal (1 on faces looking up)."""
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.geo.outputs["Normal"], sep.inputs["Vector"])
        return sep.outputs["Z"]

    def cavity(self, distance: float):
        ao = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = distance
        ao.samples = 16
        return ao.outputs["AO"]

    def warped(self, scale: float, amount: float):
        warp = C._noise(self.nt, scale, 3.0, 0.5, vector=self.obj)
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = "MULTIPLY_ADD"
        self.nt.links.new(warp.outputs["Color"], n.inputs[0])
        n.inputs[1].default_value = (amount, amount, amount)
        self.nt.links.new(self.obj, n.inputs[2])
        return n.outputs[0]

    def out(self, color, rough, height, strength: float, distance: float) -> bpy.types.Material:
        self.nt.links.new(color, self.bsdf.inputs["Base Color"])
        if isinstance(rough, bpy.types.NodeSocket):
            self.nt.links.new(rough, self.bsdf.inputs["Roughness"])
        else:
            self.bsdf.inputs["Roughness"].default_value = rough
        self.bsdf.inputs["Metallic"].default_value = 0.0
        C._bump(self.nt, self.bsdf, height, strength, distance)
        return self.mat


class ShaderNodes:
    """The salt, field, wreck, colony, struct kits' node helper (see the module)."""

    def __init__(self, nt: bpy.types.NodeTree):
        self.nt = nt
        self.obj = nt.nodes.new("ShaderNodeTexCoord").outputs["Object"]
        self.geo = nt.nodes.new("ShaderNodeNewGeometry")

    def m(self, op: str, a, b=None, c=None, clamp: bool = False) -> bpy.types.NodeSocket:
        return C._math(self.nt, op, a, b, c, clamp)

    def mix(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b) -> bpy.types.NodeSocket:
        return C._mix_float(self.nt, fac, a, b)

    def ramp(self, a: float, b: float, src) -> bpy.types.NodeSocket:
        return C._ramp(self.nt, a, b, src)

    def noise(self, scale: float, detail: float = 4.0, rough: float = 0.6, vector=None) -> bpy.types.NodeSocket:
        """Noise Fac (about 0.5 +- 0.09)."""
        return C._noise(self.nt, scale, detail, rough, vector if vector is not None else self.obj).outputs["Fac"]

    def attr(self, name: str) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeAttribute")
        node.attribute_type = "GEOMETRY"
        node.attribute_name = name
        return node.outputs["Fac"]

    def xyz(self, vector) -> bpy.types.Node:
        node = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(vector, node.inputs["Vector"])
        return node

    def vec(self, op: str, a, b=None) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = op
        for sock, val in ((node.inputs[0], a), (node.inputs[1], b)):
            if val is None:
                continue
            if isinstance(val, bpy.types.NodeSocket):
                self.nt.links.new(val, sock)
            else:
                sock.default_value = val
        return node.outputs[0]

    def scale_color(self, col, fac) -> bpy.types.NodeSocket:
        node = self.nt.nodes.new("ShaderNodeVectorMath")
        node.operation = "SCALE"
        self.nt.links.new(col, node.inputs[0])
        if isinstance(fac, bpy.types.NodeSocket):
            self.nt.links.new(fac, node.inputs["Scale"])
        else:
            node.inputs["Scale"].default_value = fac
        return node.outputs[0]

    def spread(self, fac, k: float) -> bpy.types.NodeSocket:
        """Noise Fac stretched around 0.5 by `k`, clamped to 0..1."""
        return self.m("MULTIPLY_ADD", self.m("SUBTRACT", fac, 0.5), k, clamp=True, c=0.5)


class TreeNodes:
    """The ogrowth, plants kits' node helper (see the module)."""

    def __init__(self, nt):
        self.nt = nt

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, val in props.items():
            setattr(n, k, val)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def ramp(self, src, stops):
        """stops: [(pos, value-or-rgb)]; returns the Color output."""
        n = self.node("ShaderNodeValToRGB")
        els = n.color_ramp.elements
        while len(els) < len(stops):
            els.new(0.5)
        for el, (pos, val) in zip(els, stops):
            el.position = pos
            el.color = (*val, 1.0) if isinstance(val, tuple) else (val, val, val, 1.0)
        self.link(src, n.inputs["Fac"])
        return n.outputs["Color"]

    def coords(self, scale=(1, 1, 1)):
        coord = self.node("ShaderNodeTexCoord")
        if scale == (1, 1, 1):
            return coord.outputs["Object"]
        mp = self.node("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = scale
        self.link(coord.outputs["Object"], mp.inputs["Vector"])
        return mp.outputs["Vector"]

    def noise(self, scale, detail=4.0, rough=0.55, vec_scale=(1, 1, 1)):
        n = self.node("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        self.link(self.coords(vec_scale), n.inputs["Vector"])
        return n.outputs["Fac"]

    def voronoi(self, scale, feature="F1"):
        n = self.node("ShaderNodeTexVoronoi", feature=feature)
        n.inputs["Scale"].default_value = scale
        self.link(self.coords(), n.inputs["Vector"])
        return n

    def mix(self, fac, a, b):
        return C._mix_color(self.nt, fac, a, b)

    def mixf(self, fac, a, b):
        return C._mix_float(self.nt, fac, a, b)
