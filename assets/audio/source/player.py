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


@sound("player/dash", variants=3)
def dash(rng: random.Random, take: str, variant: int) -> Signal:
    """The suit's thrusters bursting: a rising whoosh."""
    return whoosh(rng, jitter(rng, 0.35, 0.08), slide(400, 1600, 0.3), 1.2, 0.35)
