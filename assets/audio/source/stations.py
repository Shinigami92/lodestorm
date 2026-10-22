"""Recipes of the ship's stations' sounds: an upgrade level or a skill rank done."""

import random

from synth import Signal, env, mix, modes, reverb, shape, sound, tone


@sound("stations/job_done")
def job_done(rng: random.Random, take: str, variant: int) -> Signal:
    """An upgrade level or a skill rank done (at its station, while aboard): a soft rising pair of
    glassy chimes, a fifth apart, over a faint warm hum, ringing out in the room."""
    first = modes(rng, [(880.0, 1.1, 1.0), (2420.0, 0.5, 0.25), (4180.0, 0.25, 0.08)], 1.4)
    second = modes(rng, [(1320.0, 1.3, 1.0), (3630.0, 0.6, 0.22), (6270.0, 0.3, 0.06)], 1.6)
    hum = shape(mix((tone(220.0, 1.2), 1.0), (tone(440.0, 1.2), 0.3)), env(1.2, 0.15, 0.9, 0.1))
    return reverb(mix((first, 0.5), (second, 0.55, 0.16), (hum, 0.08)), 0.5, 1.2, 0.25)
