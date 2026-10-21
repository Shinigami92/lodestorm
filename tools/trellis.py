"""Image to 3D with TRELLIS.2 on a local ComfyUI (its native nodes, ComfyUI 0.34 or newer).

Usage: python tools/trellis.py <image> <out.glb> [--seed N] [--faces N] [--texture N] [--unet NAME] [--url URL]

Removes the background (BiRefNet), generates the shape and its texture, remeshes it, decimates it to --faces and
bakes base color, metallic/roughness, normal and AO (from the remeshed shape) into one --texture set, then saves the
textured .glb to <out.glb>. The graph follows ComfyUI's template "3d_pixal3d_trellis2_image_to_model" (its TRELLIS
path). Needs in ComfyUI's models folder: diffusion_models/trellis_2_bf16.safetensors (or the int8 one, --unet),
vae/trellis_2_shape_vae_bf16.safetensors and trellis_2_texture_vae_bf16.safetensors,
clip_vision/dino_v3_vit_l.safetensors, background_removal/birefnet.safetensors. About 4 minutes on a 16 GB GPU,
which it uses fully: run one at a time. Record what made an asset next to its source (e.g.
assets/player/source/trellis/trellis.json).
"""

import argparse
import json
import pathlib
import time
import urllib.parse
import urllib.request
import uuid

Ref = list  # [node id, output index]


def post(url: str, path: str, data: bytes, content_type: str) -> dict:
    req = urllib.request.Request(url + path, data=data, headers={"Content-Type": content_type})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def get(url: str, path: str) -> bytes:
    with urllib.request.urlopen(url + path) as r:
        return r.read()


def upload(url: str, image: pathlib.Path) -> str:
    boundary = uuid.uuid4().hex
    head = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{image.name}"\r\n'
        "Content-Type: image/png\r\n\r\n"
    )
    tail = f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n--{boundary}--\r\n'
    body = head.encode() + image.read_bytes() + tail.encode()
    return post(url, "/upload/image", body, f"multipart/form-data; boundary={boundary}")["name"]


def graph(image: str, seed: int, faces: int, texture: int, unet: str) -> dict:
    g: dict = {}

    def node(key: str, cls: str, **inputs) -> Ref:
        g[key] = {"class_type": cls, "inputs": inputs}
        return [key, 0]

    def out(key: str, index: int) -> Ref:
        return [key, index]

    img = node("image", "LoadImage", image=image)
    bg = node("bg_model", "LoadBackgroundRemovalModel", bg_removal_name="birefnet.safetensors")
    mask = node("mask", "RemoveBackground", bg_removal_model=bg, image=img)
    crop = node(
        "crop",
        "ImageCropToMask",
        images=img,
        masks=mask,
        width=1024,
        height=1024,
        pad_factor=1.1,
        grow_mask=0,
        background="#000000",
    )
    clip = node("clip", "CLIPVisionLoader", clip_name="dino_v3_vit_l.safetensors")
    node("cond", "Trellis2Conditioning", clip_vision_model=clip, image=crop)
    model = node("unet", "UNETLoader", unet_name=unet, weight_dtype="default")
    vae_shape = node("vae_shape", "VAELoader", vae_name="trellis_2_shape_vae_bf16.safetensors")
    vae_tex = node("vae_tex", "VAELoader", vae_name="trellis_2_texture_vae_bf16.safetensors")
    sampler = {"sampler_name": "euler", "denoise": 1.0, "seed": seed}

    # Structure, then shape (with the template's CFG override and rescale), upsampled to 1536.
    m1 = node("cfg1", "CFGOverride", model=model, cfg=1.0, start_percent=0.667, end_percent=1.0)
    m1 = node("rescale1", "RescaleCFG", model=m1, multiplier=0.7)
    m1 = node("shift", "ModelSamplingSD3", model=m1, shift=5.0)
    empty = node("empty", "EmptyTrellis2LatentStructure", batch_size=1)
    s = node(
        "ks_structure",
        "KSampler",
        model=m1,
        positive=out("cond", 0),
        negative=out("cond", 1),
        latent_image=empty,
        steps=12,
        cfg=7.5,
        scheduler="normal",
        **sampler,
    )
    voxel = node("voxel", "VaeDecodeStructureTrellis2", samples=s, vae=vae_shape, resolution="32")
    node("shape", "Trellis2ShapeStage", positive=out("cond", 0), negative=out("cond", 1), voxel=voxel)
    m2 = node("cfg2", "CFGOverride", model=model, cfg=1.0, start_percent=0.769, end_percent=1.0)
    m2 = node("rescale2", "RescaleCFG", model=m2, multiplier=0.5)
    s = node(
        "ks_shape",
        "KSampler",
        model=m2,
        positive=out("shape", 0),
        negative=out("shape", 1),
        latent_image=out("shape", 2),
        steps=20,
        cfg=7.5,
        scheduler="normal",
        **sampler,
    )
    node(
        "up",
        "Trellis2UpsampleStage",
        positive=out("shape", 0),
        negative=out("shape", 1),
        shape_latent=s,
        vae=vae_shape,
        target_resolution=1536,
    )
    s_up = node(
        "ks_up",
        "KSampler",
        model=m2,
        positive=out("up", 0),
        negative=out("up", 1),
        latent_image=out("up", 2),
        steps=12,
        cfg=7.5,
        scheduler="simple",
        **sampler,
    )
    node("decode_shape", "VaeDecodeShapeTrellis", samples=s_up, vae=vae_shape)
    mesh = out("decode_shape", 0)

    # Texture voxels.
    node("tex", "Trellis2TextureStage", positive=out("up", 0), negative=out("up", 1), shape_latent=s_up)
    s = node(
        "ks_tex",
        "KSampler",
        model=model,
        positive=out("tex", 0),
        negative=out("tex", 1),
        latent_image=out("tex", 2),
        steps=12,
        cfg=1.0,
        scheduler="normal",
        **(sampler | {"seed": seed + 1}),
    )
    colors = node(
        "decode_tex", "VaeDecodeTextureTrellis", samples=s, vae=vae_tex, shape_subdivides=out("decode_shape", 1)
    )

    # Remesh (closed, smoothed), decimate, unwrap, bake.
    remesh = node(
        "remesh",
        "RemeshMesh",
        mesh=mesh,
        resolution=768,
        sign_mode="solid",
        **{"sign_mode.fill": 20.0, "sign_mode.qef": False},
        band=1.0,
        project_back=0.0,
        fix_poles=False,
        smooth_iters=20,
        drop_small_components=0.01,
        precluster_max_verts=20000000,
    )
    low = node("decimate", "DecimateMesh", mesh=remesh, target_face_count=faces, placement_mode="midpoint")
    low = node("smooth", "MeshSmoothNormals", mesh=low, crease_angle=180.0)
    low = node("unwrap", "UnwrapMesh", mesh=low, segmenter="pec", resolution=texture, padding=1, weld_distance=0.0002)
    node("bake", "BakeTextureFromVoxel", mesh=low, voxel_colors=colors, texture_size=texture, reference_mesh=mesh)
    normal = node(
        "normal",
        "BakeNormalMapFromMesh",
        low_poly=low,
        high_poly=remesh,
        resolution=texture,
        cage_distance=0.05,
        ignore_backfaces=True,
    )
    ao = node(
        "ao",
        "BakeAmbientOcclusion",
        low_poly=low,
        high_poly=remesh,
        resolution=min(texture, 1024),
        samples=64,
        max_distance=0.71,
        strength=1.0,
        bias=0.01,
    )
    textured = node(
        "apply",
        "ApplyTextureToMesh",
        mesh=low,
        base_color=out("bake", 0),
        metallic=out("bake", 1),
        roughness=out("bake", 2),
        occlusion=ao,
        normal_map=normal,
    )
    textured = node("smooth2", "MeshSmoothNormals", mesh=textured, crease_angle=180.0)
    node("save", "SaveGLB", mesh=node("file", "MeshToFile3D", mesh=textured), filename_prefix="3d/trellis")
    return g


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("image", type=pathlib.Path)
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--faces", type=int, default=20000)
    ap.add_argument("--texture", type=int, default=2048)
    ap.add_argument("--unet", default="trellis_2_bf16.safetensors")
    ap.add_argument("--url", default="http://127.0.0.1:8188")
    a = ap.parse_args()
    prompt = graph(upload(a.url, a.image), a.seed, a.faces, a.texture, a.unet)
    pid = post(a.url, "/prompt", json.dumps({"prompt": prompt}).encode(), "application/json")["prompt_id"]
    t0 = time.time()
    while True:
        time.sleep(5)
        history = json.loads(get(a.url, f"/history/{pid}"))
        if pid in history:
            break
    entry = history[pid]
    if entry["status"]["status_str"] != "success":
        raise SystemExit(json.dumps(entry["status"], indent=1))
    glb = entry["outputs"]["save"]["3d"][0]
    query = urllib.parse.urlencode({k: glb[k] for k in ("filename", "subfolder", "type")})
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_bytes(get(a.url, f"/view?{query}"))
    print(f"{a.out} ({time.time() - t0:.0f} s)")


if __name__ == "__main__":
    main()
