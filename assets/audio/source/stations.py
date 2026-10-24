"""Recipes of the stations' sounds: an upgrade level or a skill rank done, and the ore exchange's
trade."""

import random

from synth import Signal, bandpass, click, env, jitter, lowpass, mix, modes, noise, reverb, shape, sound, thump, tone


@sound("stations/job_done")
def job_done(rng: random.Random, take: str, variant: int) -> Signal:
    """An upgrade level or a skill rank done (at its station, while aboard): a soft rising pair of
    glassy chimes, a fifth apart, over a faint warm hum, ringing out in the room."""
    first = modes(rng, [(880.0, 1.1, 1.0), (2420.0, 0.5, 0.25), (4180.0, 0.25, 0.08)], 1.4)
    second = modes(rng, [(1320.0, 1.3, 1.0), (3630.0, 0.6, 0.22), (6270.0, 0.3, 0.06)], 1.6)
    hum = shape(mix((tone(220.0, 1.2), 1.0), (tone(440.0, 1.2), 0.3)), env(1.2, 0.15, 0.9, 0.1))
    return reverb(mix((first, 0.5), (second, 0.55, 0.16), (hum, 0.08)), 0.5, 1.2, 0.25)


@sound("stations/exchange")
def exchange(rng: random.Random, take: str, variant: int) -> Signal:
    """A trade at the ore exchange: a hopper's flap clunking open, a rattle of ore chunks sliding
    down its steel funnel and a dull thud as they land in the bin below."""
    seconds = 1.3
    flap = mix((thump(180, 70, 0.02, 0.18, 0.25), 1.0), (click(rng, 1600, 3, 0.03), 0.5))
    chunks = []
    for _ in range(26):
        start = 0.08 + rng.random() ** 1.4 * 0.75
        pitch = jitter(rng, 2200, 0.35)
        chunks.append((click(rng, pitch, 5, jitter(rng, 0.03, 0.4)), jitter(rng, 0.5, 0.5), start))
    rattle = mix(*chunks)
    slide = shape(bandpass(noise(rng, seconds), 900, 0.7), env(seconds, 0.12, 0.7))
    thud = mix((thump(110, 50, 0.03, 0.3, 0.4), 1.0), (lowpass(noise(rng, 0.25), 300), 0.3))
    return reverb(mix((flap, 0.7), (rattle, 0.8), (slide, 0.25, 0.05), (thud, 0.8, 0.85)), 0.35, 0.4, 0.12)
