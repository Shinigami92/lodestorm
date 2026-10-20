"""Recipes of the player's sounds: hits taken, low health, the dash and its steps."""

import random

from synth import (
    Signal,
    bandpass,
    burst,
    click,
    crackle,
    env,
    highpass,
    jitter,
    lowpass,
    mix,
    modes,
    noise,
    shape,
    slide,
    sound,
    thump,
    whoosh,
)


@sound("player/hit_taken", variants=3)
def hit_taken(rng: random.Random, take: str, variant: int) -> Signal:
    """A hit on the suit: a thud, the armor plate clanking and sparks crackling."""
    j = 0.08
    thud = thump(jitter(rng, 140, j), jitter(rng, 70, j), 0.015, jitter(rng, 0.1, j), 0.12)
    plate = modes(rng, [(jitter(rng, 650, j), 0.1, 1.0), (jitter(rng, 1500, j), 0.07, 0.6), (2700, 0.04, 0.4)], 0.12)
    sparks = shape(highpass(crackle(rng, 0.12, 900), 2000), env(0.12, 0.001, 0.1))
    return mix((thud, 1.0), (plate, 0.2), (sparks, 0.6, 0.005))


@sound("player/low_health")
def low_health(rng: random.Random, take: str, variant: int) -> Signal:
    """One beat of the slow pulse below a quarter of the health: a low double thump like a
    heartbeat."""
    beat = mix((thump(62, 45, 0.02, 0.12, 0.14), 1.0), (thump(58, 42, 0.02, 0.1, 0.12), 0.6, 0.17))
    return lowpass(beat, 400)


@sound("player/step_ground", variants=6)
def step_ground(rng: random.Random, take: str, variant: int) -> Signal:
    """A boot on the ground outside (subtle, every 2 m): a soft heel thud with gravel crunching."""
    j = 0.1
    heel = thump(jitter(rng, 110, j), jitter(rng, 70, j), 0.01, jitter(rng, 0.06, j), 0.08)
    grit = shape(
        bandpass(mix((noise(rng, 0.1), 0.5), (crackle(rng, 0.1, 2500), 1.0)), jitter(rng, 2800, j), 0.9),
        env(0.1, 0.004, 0.08),
    )
    scuff = burst(rng, 0.09, 0.006, jitter(rng, 0.07, j), "bandpass", jitter(rng, 900, j), 0.8)
    return mix((heel, 0.8), (grit, 0.5, 0.004), (scuff, 0.3))


@sound("player/step_deck", variants=6)
def step_deck(rng: random.Random, take: str, variant: int) -> Signal:
    """A boot on the ship's metal deck (subtle, every 2 m): a hollow plate ringing softly."""
    j = 0.08
    heel = thump(jitter(rng, 140, j), jitter(rng, 95, j), 0.008, jitter(rng, 0.06, j), 0.08)
    tap = click(rng, jitter(rng, 1800, j), 2.5, 0.012)
    plate = [(jitter(rng, 230, j), 0.14, 1.0), (jitter(rng, 560, j), 0.1, 0.6), (jitter(rng, 1150, j), 0.06, 0.35)]
    return mix((heel, 0.9), (tap, 0.3), (modes(rng, plate, 0.16), 0.12))


@sound("player/step_shards", variants=6)
def step_shards(rng: random.Random, take: str, variant: int) -> Signal:
    """A boot on glass shards (the Glass plains' hazard, every 2 m): a heel thud with glass
    crunching and tinkling."""
    j = 0.1
    heel = thump(jitter(rng, 110, j), jitter(rng, 70, j), 0.01, jitter(rng, 0.06, j), 0.08)
    crunch = shape(bandpass(crackle(rng, 0.12, 6000), jitter(rng, 4200, j), 1.0), env(0.12, 0.002, 0.09))
    shards = [(jitter(rng, f, 0.15), rng.uniform(0.03, 0.08), rng.uniform(0.3, 1.0)) for f in (3100, 4300, 5600, 7200)]
    tinkle = modes(rng, shards, 0.12)
    return mix((heel, 0.7), (crunch, 0.7, 0.003), (tinkle, 0.12, rng.uniform(0.005, 0.03)))


@sound("player/step_mud", variants=6)
def step_mud(rng: random.Random, take: str, variant: int) -> Signal:
    """A boot in mud (the Overgrowth's hazard, every 2 m): a soft, wet squelch and the suck of
    the boot pulling out."""
    j = 0.1
    heel = thump(jitter(rng, 90, j), jitter(rng, 55, j), 0.015, jitter(rng, 0.08, j), 0.1)
    squelch = shape(bandpass(noise(rng, 0.14), slide(jitter(rng, 1300, j), 350, 0.12), 3.0), env(0.14, 0.004, 0.11))
    suck = shape(bandpass(noise(rng, 0.12), slide(300, jitter(rng, 900, j), 0.1), 4.0), env(0.12, 0.03, 0.08))
    return lowpass(mix((heel, 0.8), (squelch, 0.6, 0.005), (suck, 0.35, jitter(rng, 0.13, j))), 3500)


@sound("player/dash", variants=3)
def dash(rng: random.Random, take: str, variant: int) -> Signal:
    """The suit's thrusters bursting: a rising whoosh."""
    return whoosh(rng, jitter(rng, 0.35, 0.08), slide(400, 1600, 0.3), 1.2, 0.35)
