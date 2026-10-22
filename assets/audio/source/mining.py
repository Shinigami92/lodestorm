"""Recipes of the mining sounds: placing a miner, its drill, the full chime, the hose, the
breakdown, the repair, the servos folding and unfolding it and the latch when it's folded."""

import math
import random

from synth import (
    Signal,
    bandpass,
    burst,
    click,
    crackle,
    env,
    gain,
    highpass,
    jitter,
    loop_seconds,
    lowpass,
    mix,
    modes,
    noise,
    saturate,
    shape,
    slide,
    sound,
    thump,
    tone,
    tremolo,
)


def _pulses(seconds: float, rate: float, width: float, sharpness: float = 2.0) -> Signal:
    """A level pulsing `rate` times a s, each pulse `width` (a share of its period) long."""
    out = []
    for i in range(round(seconds * 44100)):
        x = (i / 44100 * rate) % 1.0
        out.append(math.sin(math.pi * x / width) ** sharpness if x < width else 0.0)
    return out


@sound("mining/miner_place", variants=2)
def miner_place(rng: random.Random, take: str, variant: int) -> Signal:
    """A miner set down: a heavy metal thud, the legs' clamps locking and a hiss of its
    hydraulics."""
    j = 0.06
    thud = thump(jitter(rng, 90, j), jitter(rng, 45, j), 0.025, jitter(rng, 0.25, j), 0.3)
    body = modes(rng, [(jitter(rng, 180, j), 0.3, 1.0), (jitter(rng, 410, j), 0.2, 0.6), (870, 0.1, 0.3)], 0.35)
    clamp = mix((click(rng, jitter(rng, 2200, j), 5, 0.02), 1.0), (thump(320, 200, 0.004, 0.04, 0.05), 0.6))
    hiss = burst(rng, 0.4, 0.02, jitter(rng, 0.25, j), "highpass", 3500)
    return saturate(mix((thud, 1.0), (body, 0.15), (clamp, 0.6, 0.18), (clamp, 0.5, 0.26), (hiss, 0.12, 0.3)), 1.3)


@sound("mining/drill", loop=True)
def drill(rng: random.Random, take: str, variant: int) -> Signal:
    """A miner drilling (a loop, 2 s): a deep motor humming, the bit grinding rock slowly in time
    with its turn and grit crackling."""
    seconds = loop_seconds(2.0)
    hum_hz, turn_hz = 48.0, 6.0
    motor = lowpass(mix((tone(hum_hz, seconds, "saw"), 1.0), (tone(hum_hz * 2, seconds, "square"), 0.3)), 420)
    motor = tremolo(motor, turn_hz, 0.25)
    grind = bandpass(noise(rng, seconds), 900, 1.2)
    grind = shape(grind, [0.35 + 0.65 * p for p in _pulses(seconds, turn_hz, 0.6, 1.5)])
    grit = highpass(crackle(rng, seconds, 600), 1800)
    rumble = lowpass(noise(rng, seconds), 120)
    return saturate(mix((motor, 0.5), (grind, 0.55), (grit, 0.35), (rumble, 0.6)), 1.4)


@sound("mining/miner_full")
def miner_full(rng: random.Random, take: str, variant: int) -> Signal:
    """A miner's tank full: two soft, low panel tones (falling), like a machine done with its
    work."""

    def note(freq: float, seconds: float) -> Signal:
        body = mix((tone(freq, seconds), 1.0), (tone(freq * 2.01, seconds), 0.25), (tone(freq * 3.0, seconds), 0.08))
        return shape(body, env(seconds, 0.006, seconds * 0.9))

    return lowpass(mix((note(660, 0.5), 0.8), (note(495, 0.8), 0.9, 0.22)), 3000)


@sound("mining/hose", loop=True)
def hose(rng: random.Random, take: str, variant: int) -> Signal:
    """The hose carrying ore (a loop, 2 s): a dull flow rushing through the pipe, a pump
    pulsing twice a s and grains rattling against the walls."""
    seconds = loop_seconds(2.0)
    flow = lowpass(noise(rng, seconds), 320)
    flow = shape(flow, [0.6 + 0.4 * p for p in _pulses(seconds, 2.0, 0.5)])
    pump = lowpass(shape(tone(55.0, seconds, "triangle"), _pulses(seconds, 2.0, 0.35)), 200)
    rattle = bandpass(crackle(rng, seconds, 1400), 2200, 1.5)
    return mix((flow, 1.0), (pump, 0.5), (rattle, 0.4))


@sound("mining/breakdown")
def breakdown(rng: random.Random, take: str, variant: int) -> Signal:
    """A miner breaking down: its motor grinding to a halt with a bang and sparks, then a
    two-tone warning buzz, three times."""
    stall = shape(lowpass(tone(slide(48, 18, 0.7), 0.8, "saw"), 400), env(0.8, 0.005, 0.7))
    bang = mix((thump(130, 45, 0.02, 0.3, 0.35), 1.0), (burst(rng, 0.2, 0.0005, 0.12, "bandpass", 1200, 0.8), 0.7))
    sparks = shape(highpass(crackle(rng, 0.6, 700), 2500), env(0.6, 0.001, 0.5))
    beeps = []
    for index in range(3):
        for freq, start in ((520, 0.0), (390, 0.16)):
            beep = lowpass(tone(freq, 0.15, "square"), 1800)
            beeps.append((shape(beep, env(0.15, 0.004, 0.25, 0.1)), 0.22, 0.75 + index * 0.4 + start))
    return mix((stall, 0.5), (bang, 1.0, 0.05), (sparks, 0.4, 0.05), *beeps)


@sound("mining/repair", loop=True)
def repair(rng: random.Random, take: str, variant: int) -> Signal:
    """Repairing a miner (a loop, 2 s): a wrench ratcheting and clanking on steel, with a short
    hiss of a welding torch."""
    seconds = loop_seconds(2.0)
    layers: list = [(gain(burst(rng, seconds, 0.05, 1.0, "highpass", 4000), 0.0), 1.0)]
    # A ratchet: quick clicks in two runs
    for start in (0.1, 1.1):
        for k in range(6):
            layers.append((click(rng, jitter(rng, 2600, 0.08), 5, 0.01), 0.5, start + k * 0.055))
    # The wrench clanking on the frame
    for start in (0.55, 1.6):
        steel = [(jitter(rng, 820, 0.05), 0.25, 1.0), (jitter(rng, 1930, 0.05), 0.15, 0.6), (3150, 0.08, 0.3)]
        layers.append((modes(rng, steel, 0.3), 0.25, start))
        layers.append((thump(260, 160, 0.004, 0.05, 0.06), 0.5, start))
    # The torch
    torch = shape(highpass(noise(rng, 0.5), 2500), env(0.5, 0.05, 0.4, 0.15))
    layers.append((mix((torch, 1.0), (highpass(crackle(rng, 0.5, 400), 3000), 0.6)), 0.25, 0.75))
    signal = mix(*layers)
    return signal + [0.0] * max(0, round(seconds * 44100) - len(signal))


@sound("mining/miner_servo", loop=True, takes="abc")
def miner_servo(rng: random.Random, take: str, variant: int) -> Signal:
    """A miner's servos folding or unfolding its legs (a loop, 1 s; the game raises its pitch
    while it unfolds and lowers it while it folds): a whining motor, its gears whirring and a soft
    hydraulic hiss. a: a thin, high whine; b: a lower, heavier drive; c: a geared whir with a
    stepping ratchet."""
    seconds = loop_seconds(1.0)
    hz = {"a": 520.0, "b": 260.0, "c": 380.0}[take]
    whine = mix((tone(hz, seconds, "saw"), 1.0), (tone(hz * 1.5, seconds), 0.35), (tone(hz * 2.0, seconds), 0.2))
    whine = tremolo(bandpass(whine, hz * 2.2, 0.9), 9.0, 0.15)
    gears = bandpass(noise(rng, seconds), hz * 4.0, 2.5)
    hiss = highpass(noise(rng, seconds), 5000)
    layers: list = [(whine, 0.55), (gears, 0.3 if take != "b" else 0.15), (hiss, 0.06)]
    if take == "b":
        layers.append((lowpass(tone(hz * 0.5, seconds, "square"), 300), 0.35))
    if take == "c":
        for k in range(12):
            layers.append((click(rng, jitter(rng, 3400, 0.05), 6, 0.008), 0.3, k / 12.0))
    return saturate(mix(*layers), 1.2)


@sound("mining/miner_latch", takes="abc")
def miner_latch(rng: random.Random, take: str, variant: int) -> Signal:
    """A miner folded up on the back: its legs' latches snapping shut, a short clack of steel and
    a sigh of the hydraulics settling. a: one firm clack; b: two quick latches; c: a heavy clunk
    with a ring."""
    j = 0.05
    clack = mix((click(rng, jitter(rng, 2600, j), 4, 0.02), 1.0), (thump(420, 240, 0.004, 0.05, 0.06), 0.7))
    steel = modes(rng, [(jitter(rng, 1250, j), 0.12, 1.0), (jitter(rng, 2900, j), 0.08, 0.5)], 0.15)
    sigh = burst(rng, 0.3, 0.02, 0.18, "highpass", 3000)
    layers: list = [(clack, 1.0), (steel, 0.25), (sigh, 0.1, 0.05)]
    if take == "b":
        layers.append((clack, 0.8, 0.09))
    if take == "c":
        layers.append((thump(150, 70, 0.01, 0.15, 0.2), 0.9))
        layers.append((modes(rng, [(jitter(rng, 640, j), 0.5, 1.0), (1530, 0.3, 0.4)], 0.5), 0.15))
    return saturate(mix(*layers), 1.2)
