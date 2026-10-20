"""Recipes of the mission's sounds: the ship's ramp, the countdown's beeps, the storm's warning,
its building and its hit, and the biomes' hazards (the vents)."""

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
    noise,
    reverb,
    saturate,
    shape,
    slide,
    sound,
    thump,
    tone,
)


def _wobble(seconds: float, rates: list[tuple[float, float]]) -> Signal:
    """A slow level between 0 and 1 from sines of (rate in Hz, weight): gusts."""
    total = sum(weight for _, weight in rates)
    out = []
    for i in range(round(seconds * 44100)):
        t = i / 44100
        value = sum(weight * math.sin(2.0 * math.pi * rate * t + k) for k, (rate, weight) in enumerate(rates))
        out.append(0.5 + 0.5 * value / total)
    return out


@sound("mission/ramp")
def ramp(rng: random.Random, take: str, variant: int) -> Signal:
    """The ship's ramp moving (2 s, up or down): the latches letting go, a hydraulic whine with a
    hiss, and the ramp settling with a heavy clunk."""
    seconds = 2.0
    latch = mix((click(rng, 1600, 3, 0.03), 1.0), (thump(220, 120, 0.005, 0.08, 0.1), 0.8))
    whine = lowpass(
        mix((tone(slide(95, 130, seconds), seconds, "saw"), 1.0), (tone(slide(190, 260, seconds), seconds), 0.3)), 900
    )
    whine = shape(whine, env(seconds, 0.15, 0.3, seconds - 0.4))
    hiss = shape(highpass(noise(rng, seconds), 3000), env(seconds, 0.2, 0.4, seconds - 0.5))
    clunk = mix((thump(85, 40, 0.02, 0.35, 0.4), 1.0), (burst(rng, 0.15, 0.001, 0.1, "bandpass", 700, 0.8), 0.6))
    rattle = bandpass(crackle(rng, seconds, 60), 1400, 2.0)
    return reverb(
        mix((latch, 0.6), (whine, 0.35, 0.05), (hiss, 0.08, 0.05), (rattle, 0.2), (clunk, 1.0, seconds)), 0.5, 0.6, 0.15
    )


@sound("mission/countdown_beep")
def countdown_beep(rng: random.Random, take: str, variant: int) -> Signal:
    """The suit counting down the last minute (every 10 s, then every s of the last 10): one terse
    beep."""
    beep = mix((tone(1180, 0.09), 1.0), (tone(2360, 0.09), 0.1))
    return shape(beep, env(0.09, 0.002, 0.06, 0.03))


@sound("mission/storm_warning")
def storm_warning(rng: random.Random, take: str, variant: int) -> Signal:
    """The storm's warning (a critical cue: the last minute starts, the hive frenzies): a deep
    two-tone horn, three times, with a distant rumble."""
    layers = []
    for index in range(3):
        for freq, start in ((330, 0.0), (247, 0.22)):
            horn = lowpass(mix((tone(freq, 0.22, "square"), 1.0), (tone(freq * 1.005, 0.22, "saw"), 0.6)), 1400)
            layers.append((shape(horn, env(0.22, 0.01, 0.2, 0.12)), 0.35, index * 0.55 + start))
    rumble = shape(lowpass(noise(rng, 1.8), 120), bell(1.8, 0.4, 1.0))
    return mix(*layers, (rumble, 0.5))


@sound("mission/storm", loop=True)
def storm(rng: random.Random, take: str, variant: int) -> Signal:
    """The storm building (a loop, 4 s, on the Ambience bus: louder as it comes, muffled aboard):
    a howling wind gusting with grit and a deep roar."""
    seconds = loop_seconds(4.0)
    gusts = _wobble(seconds, [(0.25, 1.0), (0.5, 0.6), (1.25, 0.3)])
    howl_hz = 520

    def sweep(t: float) -> float:
        return howl_hz * (1.0 + 0.35 * math.sin(2.0 * math.pi * 0.25 * t) + 0.15 * math.sin(2.0 * math.pi * 0.75 * t))

    howl = shape(bandpass(noise(rng, seconds), sweep, 6.0), gusts)
    wind = shape(bandpass(noise(rng, seconds), 900, 0.6), [0.4 + 0.6 * g for g in gusts])
    roar = lowpass(noise(rng, seconds), 140)
    grit = shape(highpass(crackle(rng, seconds, 1800), 2500), gusts)
    return mix((howl, 0.7), (wind, 0.5), (roar, 0.8), (grit, 0.25))


@sound("mission/storm_hit")
def storm_hit(rng: random.Random, take: str, variant: int) -> Signal:
    """The storm hitting (the time is up): a crack like thunder, a blast of wind and a long roar."""
    crack = burst(rng, 0.3, 0.001, 0.25, "highpass", 1200)
    boom = thump(70, 28, 0.05, 1.2, 1.4)
    blast = shape(bandpass(noise(rng, 3.0), glide(2500, 500, 1.0), 0.7), env(3.0, 0.05, 2.5, 0.3))
    roar = shape(lowpass(noise(rng, 3.5), 180), env(3.5, 0.3, 2.5, 0.5))
    return saturate(mix((crack, 0.5), (boom, 1.0), (blast, 0.6, 0.05), (roar, 1.0, 0.1)), 1.5)


@sound("biomes/vent_rumble", variants=2)
def vent_rumble(rng: random.Random, take: str, variant: int) -> Signal:
    """A vent about to burst (its warning, 1.5 s, the Ash fields): a rumble rising under the
    ground, bubbling."""
    seconds = 1.5
    rise = [(i / round(seconds * 44100)) ** 1.5 for i in range(round(seconds * 44100))]
    rumble = shape(lowpass(noise(rng, seconds), slide(60, jitter(rng, 320, 0.1), seconds)), rise)
    boil = shape(bandpass(crackle(rng, seconds, 300), 500, 1.0), rise)
    hiss = shape(highpass(noise(rng, seconds), 2500), [r**2 for r in rise])
    return mix((rumble, 1.0), (boil, 0.6), (hiss, 0.15))


@sound("biomes/vent_burst", variants=2)
def vent_burst(rng: random.Random, take: str, variant: int) -> Signal:
    """A vent bursting (the Ash fields): a deep thump and a roaring blast of hot gas hissing
    out."""
    j = 0.08
    boom = thump(jitter(rng, 80, j), 32, 0.03, 0.5, 0.6)
    blast = burst(rng, 1.3, 0.01, jitter(rng, 1.0, j), "bandpass", glide(1800, 700, 0.6), 0.6)
    hiss = burst(rng, 1.2, 0.02, jitter(rng, 0.9, j), "highpass", 3500)
    grit = shape(highpass(crackle(rng, 0.8, 900), 2000), env(0.8, 0.005, 0.7))
    return saturate(mix((boom, 1.0), (blast, 0.8), (hiss, 0.3), (grit, 0.3)), 1.6)
