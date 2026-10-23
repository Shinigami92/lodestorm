"""Text to image with Z-Image Turbo on a local ComfyUI.

Usage: python tools/concepts/gen.py <out.png> <seed> <prompt...>   (env: SIZE, default 1024; COMFYUI_URL)

Needs in ComfyUI's models folder: diffusion_models/z_image_turbo_bf16.safetensors, text_encoders/qwen_3_4b.safetensors
and vae/ae.safetensors. The first image after a model swap takes about a minute, the rest 10-25 s on a 16 GB GPU.
"""

import json
import os
import sys
import time
import urllib.request

URL = os.environ.get("COMFYUI_URL", "http://127.0.0.1:8188")
MODEL = "z_image_turbo_bf16"


def post(path: str, data: dict) -> dict:
    req = urllib.request.Request(URL + path, json.dumps(data).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def get(path: str) -> bytes:
    with urllib.request.urlopen(URL + path) as r:
        return r.read()


def graph(prompt: str, seed: int, size: int) -> dict:
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": f"{MODEL}.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "lumina2"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 3.0}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "6": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["5", 0]}},
        "7": {"class_type": "EmptySD3LatentImage", "inputs": {"width": size, "height": size, "batch_size": 1}},
        "8": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["4", 0],
                "positive": ["5", 0],
                "negative": ["6", 0],
                "latent_image": ["7", 0],
                "seed": seed,
                "steps": 8,
                "cfg": 1.0,
                "sampler_name": "res_multistep",
                "scheduler": "simple",
                "denoise": 1.0,
            },
        },
        "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": "lodestorm"}},
    }


def generate(out: str, seed: int, prompt: str, size: int = 1024) -> float:
    """Render one image to out and return the seconds it took."""
    pid = post("/prompt", {"prompt": graph(prompt, seed, size)})["prompt_id"]
    t0 = time.time()
    while True:
        hist = json.loads(get(f"/history/{pid}"))
        if pid in hist:
            entry = hist[pid]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError(json.dumps(entry["status"], indent=1))
            img = entry["outputs"]["10"]["images"][0]
            data = get(f"/view?filename={img['filename']}&subfolder={img['subfolder']}&type={img['type']}")
            with open(out, "wb") as f:
                f.write(data)
            return time.time() - t0
        time.sleep(1)


if __name__ == "__main__":
    out, seed, text = sys.argv[1], int(sys.argv[2]), " ".join(sys.argv[3:])
    print(f"{out} ({generate(out, seed, text, int(os.environ.get('SIZE', '1024'))):.1f}s)")
