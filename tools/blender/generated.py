"""Shared helpers for generated models (image to 3D, tools/trellis.py; see docs/technical/assets.md, Generated models): load
the raw mesh, weight it to a skeleton by the nearest bone, cut the faces between parts that move apart, and read and
repaint its texture.

    import generated as G
    obj = G.load(path, root, "Creature")              # welded, world transform applied
    score, along = G.capsules(co, names, seg, radius)  # per vertex and bone: distance to the bone minus its radius
    owner, w = G.weights(score, along, names, seg, band, parent)
    G.cut_bridges(obj.data, owner, names, (group_a, group_b))
    G.set_weights(obj, names, w)
"""

import bmesh
import bpy
import numpy as np
from mathutils import Matrix

import common as C


def load(path, root: bpy.types.Object, name: str) -> bpy.types.Object:
    """The generated .glb's mesh, welded (it comes split along its UV seams), its world transform applied, linked
    under root and named `name`."""
    bpy.ops.import_scene.gltf(filepath=str(path))
    obj = next(o for o in bpy.context.selected_objects if o.type == "MESH")
    for o in [o for o in bpy.context.selected_objects if o is not obj]:
        bpy.data.objects.remove(o)
    obj.parent = None
    me = obj.data
    me.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    C.link(obj, root)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    obj.name = me.name = name
    return obj


def vertices(me: bpy.types.Mesh) -> np.ndarray:
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def set_vertices(me: bpy.types.Mesh, co: np.ndarray) -> None:
    me.vertices.foreach_set("co", co.ravel())
    me.update()


def smooth_shading(obj: bpy.types.Object) -> None:
    """Drop the generator's custom normals (they don't fit moved vertices) and shade smooth."""
    if obj.data.has_custom_normals:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in obj.data.polygons:
        p.use_smooth = True


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def capsules(co: np.ndarray, names: list, seg: dict, radius: dict) -> tuple:
    """Per vertex and bone (columns in `names` order): the distance to the bone's segment (seg: name -> (head, end))
    minus the bone's radius, and how far along the bone the vertex lies (from its head, m). Set a score to inf to keep
    a bone from owning a vertex."""
    score, along = np.empty((len(co), len(names))), np.empty((len(co), len(names)))
    for i, name in enumerate(names):
        h, e = (np.asarray(p, dtype=float) for p in seg[name])
        length = np.linalg.norm(e - h)
        u = (e - h) / length
        t = (co - h) @ u
        nearest = h + np.clip(t, 0, length)[:, None] * u
        score[:, i] = np.linalg.norm(co - nearest, axis=1) - radius[name]
        along[:, i] = t
    return score, along


def weights(
    score, along, names: list, seg: dict, band: dict, parent: dict, end_blend: dict | None = None, co=None
) -> tuple:
    """The owning bone per vertex (the lowest score) and the weights (vertices x names): a vertex weighs 100 % to its
    owner, except within `band[child]` (m) on either side of a child's head, where it blends from the parent to the
    child. The parent's side is measured from its end (the child's head is there, as in a limb), or, with `co` (the
    vertices) given, along the child's axis around the child's head (for children starting elsewhere on the parent,
    e.g. a tail at the far end of the hips or two bones from the same point). end_blend (parent name -> vertex mask)
    limits which of the parent's vertices blend."""
    n = len(score)
    owner = score.argmin(1)
    w = np.zeros((n, len(names)))
    w[np.arange(n), owner] = 1.0
    index = {b: i for i, b in enumerate(names)}
    for child, width in band.items():
        c, p = index[child], index[parent[child]]
        lp = np.linalg.norm(np.asarray(seg[parent[child]][1]) - np.asarray(seg[parent[child]][0]))
        near_child = (owner == c) & (along[:, c] < width)
        if co is None:
            near_parent = (owner == p) & (along[:, p] > lp - width)
            t_parent = along[:, p] - lp
        else:
            head = np.asarray(seg[child][0], dtype=float)
            near_parent = (owner == p) & (along[:, c] > -width) & (np.linalg.norm(co - head, axis=1) < 4 * width)
            t_parent = along[:, c]
        if end_blend and parent[child] in end_blend:
            near_parent &= end_blend[parent[child]]
        for m, t in ((near_child, along[:, c]), (near_parent, t_parent)):
            f = smoothstep(-width, width, t[m])
            w[m] = 0.0
            w[m, c] = f
            w[m, p] = 1.0 - f
    return owner, w


def cut_bridges(me: bpy.types.Mesh, owner: np.ndarray, names: list, groups: tuple, where=None) -> int:
    """Cut the faces joining a vertex owned by a bone of one group to one owned by a bone of the other (they would
    stretch) and fill the holes left behind; with `where` (a vertex mask), only faces with all their vertices in it.
    Returns how many faces were cut."""
    a, b = ({names.index(n) for n in group} for group in groups)
    bm = bmesh.new()
    bm.from_mesh(me)
    cut = []
    for f in bm.faces:
        owners = {int(owner[v.index]) for v in f.verts}
        if owners & a and owners & b and (where is None or all(where[v.index] for v in f.verts)):
            cut.append(f)
    bmesh.ops.delete(bm, geom=cut, context="FACES_ONLY")
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=64)
    bm.to_mesh(me)
    bm.free()
    return len(cut)


def set_weights(obj: bpy.types.Object, names: list, w: np.ndarray) -> None:
    """Vertex groups in `names` order (the weights' columns)."""
    for b in names:
        obj.vertex_groups.new(name=b)
    for vi, row in enumerate(w):
        for bi in np.nonzero(row > 1e-4)[0]:
            obj.vertex_groups[names[bi]].add([vi], float(row[bi]), "REPLACE")


def base_color_image(mat: bpy.types.Material) -> bpy.types.Image:
    return mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].links[0].from_node.image


def image_pixels(img: bpy.types.Image) -> np.ndarray:
    """RGBA rows (bottom up, as the UVs), as stored (sRGB for color images)."""
    w, h = img.size
    return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)


def packed_image(name: str, rgba: np.ndarray) -> bpy.types.Image:
    """A new image from RGBA rows, packed so the .blend keeps it."""
    img = bpy.data.images.new(name, rgba.shape[1], rgba.shape[0])
    px = rgba.copy()
    px[..., 3] = 1.0
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def face_values(me: bpy.types.Mesh, texture: np.ndarray) -> np.ndarray:
    """A per-pixel map (rows x columns) sampled at each face's UV center."""
    h, w = texture.shape[:2]
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    out = np.empty(len(me.polygons))
    for p in me.polygons:
        u, v = uv[p.loop_start : p.loop_start + p.loop_total].mean(0)
        out[p.index] = texture[min(int(v * h), h - 1), min(int(u * w), w - 1)]
    return out


def uv_cover(me: bpy.types.Mesh, faces: list, size: int, grow: int = 3) -> np.ndarray:
    """Pixels the faces cover in the texture (rasterized UV triangles, grown by a few pixels)."""
    cover = np.zeros((size, size), dtype=bool)
    uv = me.uv_layers.active.data
    for p in faces:
        pts = np.array([uv[i].uv[:] for i in p.loop_indices]) * size
        for k in range(1, len(pts) - 1):
            tri = pts[[0, k, k + 1]]
            x0, y0 = np.floor(tri.min(0)).astype(int)
            x1, y1 = np.ceil(tri.max(0)).astype(int)
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = tri
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) < 1e-12:
                continue
            l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
            l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
            inside = (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
            yy, xx = ys[inside].astype(int), xs[inside].astype(int)
            ok = (yy >= 0) & (yy < size) & (xx >= 0) & (xx < size)
            cover[yy[ok], xx[ok]] = True
    for _ in range(grow):
        cover[1:] |= cover[:-1].copy()
        cover[:-1] |= cover[1:].copy()
        cover[:, 1:] |= cover[:, :-1].copy()
        cover[:, :-1] |= cover[:, 1:].copy()
    return cover


def nearest_weights(co: np.ndarray, points, w: np.ndarray) -> np.ndarray:
    """The weights of the mesh vertex nearest to each point (for parts added on top of the mesh)."""
    return w[np.array([np.argmin(np.linalg.norm(co - np.asarray(p), axis=1)) for p in points])]
