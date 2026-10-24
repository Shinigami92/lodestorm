"""Speech from VoxCPM2, run by the VoxCPM Python environment (not the system Python).

Usage: <venv python> tools/voice/voxcpm_run.py <jobs.json>   (env: VOXCPM_MODEL, default openbmb/VoxCPM2)

jobs.json is a list of {"out": "<file.flac>", "text": str, "seed": int} with optionally "reference": "<clip>"
(clone that voice) and "prompt_wav" + "prompt_text" (continue from that clip). Voice design puts the description
in parentheses in front of the text: "(A calm older man)Hello there.". The model loads once for all jobs;
existing outputs are skipped. Prints one line per take: "<out> (<seconds>s)".
"""

import json
import os
import random
import sys
import time

import numpy as np
import soundfile
import torch
from voxcpm import VoxCPM

MODEL = os.environ.get("VOXCPM_MODEL", "openbmb/VoxCPM2")


def main(jobs_file: str) -> None:
    with open(jobs_file, encoding="utf-8") as f:
        jobs = [j for j in json.load(f) if not os.path.exists(j["out"])]
    if not jobs:
        return
    model = VoxCPM.from_pretrained(MODEL, load_denoiser=False)
    rate = model.tts_model.sample_rate
    for job in jobs:
        # VoxCPM has no seed argument: seed every generator it might draw from
        random.seed(job["seed"])
        np.random.seed(job["seed"])
        torch.manual_seed(job["seed"])
        t0 = time.time()
        wav = model.generate(
            text=job["text"],
            reference_wav_path=job.get("reference"),
            prompt_wav_path=job.get("prompt_wav"),
            prompt_text=job.get("prompt_text"),
        )
        os.makedirs(os.path.dirname(job["out"]) or ".", exist_ok=True)
        soundfile.write(job["out"], wav, rate)
        print(f"{job['out']} ({time.time() - t0:.1f}s)", flush=True)


if __name__ == "__main__":
    main(sys.argv[1])
