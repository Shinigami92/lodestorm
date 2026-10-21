"""Recipes of the refinery's sounds: a furnace igniting, roaring while it runs and going out, and a
bar landing on the ingot rack."""

import math
import random

from synth import (
    Signal,
    bandpass,
    bell,
    burst,
    click,
    crackle,
    env,
    glide,
    highpass,
    jitter,
    loop_seconds,
    lowpass,
    mix,
    modes,
    noise,
    reverb,
    shape,
    slide,
    sound,
    thump,
    tone,
)


def _flutter(seconds: float, rates: list[tuple[float, float]]) -> Signal:
    """A slow level between 0 and 1 from sines of (rate in Hz, weight): flames licking. The rates
    are multiples of 0.5 Hz, so a 2 s loop joins without a jump."""
    total = sum(weight for _, weight in rates)
    out = []
    for i in range(round(seconds * 44100)):
        t = i / 44100
        value = sum(weight * math.sin(2.0 * math.pi * rate * t + k) for k, (rate, weight) in enumerate(rates))
        out.append(0.5 + 0.5 * value / total)
    return out


@sound("refinery/furnace_ignite")
def furnace_ignite(rng: random.Random, take: str, variant: int) -> Signal:
    """A furnace starting a batch: the igniter ticking twice, the gas catching with a soft whump
    and the burners swelling into a roar."""
    seconds = 1.6
    ticks = mix((click(rng, 2400, 5, 0.02), 1.0), (click(rng, 2600, 5, 0.02), 0.8, 0.12))
    whump = mix(
        (thump(120, 45, 0.08, 0.4, 0.5), 1.0),
        (burst(rng, 0.5, 0.01, 0.35, "lowpass", 500), 0.8),
    )
    swell = shape(lowpass(noise(rng, seconds), slide(250, 900, 1.0)), bell(seconds, 0.55, 1.5))
    rumble = shape(lowpass(noise(rng, seconds), 110), env(seconds, 0.3, 1.0, 0.2))
    return reverb(mix((ticks, 0.35), (whump, 1.0, 0.2), (swell, 0.45, 0.25), (rumble, 0.6, 0.25)), 0.4, 0.5, 0.12)


@sound("refinery/furnace_roar", loop=True)
def furnace_roar(rng: random.Random, take: str, variant: int) -> Signal:
    """A furnace running (a loop, 2 s, quiet in the room's background): a low roar of the burners,
    flames licking, now and then a crackle, and the hum of its blower."""
    seconds = loop_seconds(2.0)
    roar = lowpass(noise(rng, seconds), 260)
    roar = shape(roar, [0.65 + 0.35 * p for p in _flutter(seconds, [(1.5, 1.0), (2.5, 0.6), (4.0, 0.4)])])
    lick = shape(bandpass(noise(rng, seconds), 700, 0.8), _flutter(seconds, [(3.0, 1.0), (5.5, 0.5)]))
    crack = highpass(crackle(rng, seconds, 9), 1500)
    hum = lowpass(mix((tone(50.0, seconds, "saw"), 1.0), (tone(100.0, seconds), 0.4)), 300)
    return mix((roar, 1.0), (lick, 0.25), (crack, 0.3), (hum, 0.12))


@sound("refinery/furnace_stop")
def furnace_stop(rng: random.Random, take: str, variant: int) -> Signal:
    """A batch stopped: the burners choking off with a falling rush, a valve clunking shut and a
    short hiss of the gas line."""
    seconds = 1.4
    falloff = shape(lowpass(noise(rng, seconds), glide(900, 120, 0.8)), env(seconds, 0.01, 1.0))
    clunk = mix((thump(160, 60, 0.02, 0.25, 0.3), 1.0), (click(rng, 1300, 3, 0.04), 0.6))
    hiss = shape(highpass(noise(rng, 0.6), 3500), env(0.6, 0.01, 0.45))
    return reverb(mix((falloff, 0.8), (clunk, 0.9, 0.35), (hiss, 0.15, 0.4)), 0.4, 0.5, 0.12)


@sound("refinery/bar_clink", variants=3)
def bar_clink(rng: random.Random, take: str, variant: int) -> Signal:
    """A finished bar landing on the rack: a heavy little ingot clinking onto steel and the ones
    under it, a dull knock of its weight."""
    j = 0.04
    seconds = 0.6
    ingot = [(jitter(rng, 1250, j), 0.35, 1.0), (jitter(rng, 2900, j), 0.2, 0.5), (jitter(rng, 4700, j), 0.1, 0.25)]
    shelf = [(jitter(rng, 520, j), 0.3, 0.6), (jitter(rng, 1370, j), 0.18, 0.3)]
    knock = thump(jitter(rng, 220, j), 110, 0.02, 0.12, 0.15)
    bounce = modes(rng, [(p[0] * 1.01, p[1] * 0.5, p[2] * 0.4) for p in ingot], 0.3)
    return mix(
        (modes(rng, ingot, seconds), 0.6),
        (modes(rng, shelf, seconds), 0.4),
        (knock, 0.7),
        (bounce, 1.0, jitter(rng, 0.09, 0.2)),
    )
