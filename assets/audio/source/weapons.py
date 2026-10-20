"""Recipes of the weapons' sounds: shots, Dray's swings, reloads and the timing window."""

import random

from synth import (
    Signal,
    bandpass,
    burst,
    click,
    env,
    glide,
    highpass,
    jitter,
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
    whoosh,
)


@sound("weapons/harl_shot", variants=4, seed="weapons/blaster_shot")
def harl_shot(rng: random.Random, take: str, variant: int) -> Signal:
    """Harl, the assault rifle (8 shots a second): a tight punch with a crack."""
    j = 0.08
    crack = burst(rng, 0.03, 0.0002, jitter(rng, 0.012, j), "highpass", jitter(rng, 2500, j))
    body = thump(jitter(rng, 190, j), jitter(rng, 65, j), 0.015, jitter(rng, 0.09, j), 0.12)
    bark = burst(rng, 0.09, 0.001, jitter(rng, 0.06, j), "bandpass", jitter(rng, 950, j), 0.9)
    tail = burst(rng, 0.3, 0.004, jitter(rng, 0.22, j), "lowpass", glide(1800, 500, 0.1))
    return saturate(mix((crack, 0.7), (body, 0.9), (bark, 0.7), (tail, 0.3)), 1.6)


@sound("weapons/brask_shot", variants=4, seed="weapons/shotgun_shot")
def brask_shot(rng: random.Random, take: str, variant: int) -> Signal:
    """Brask, the shotgun: a deep boom with a rumbling tail."""
    j = 0.07
    crack = burst(rng, 0.04, 0.0002, jitter(rng, 0.02, j), "highpass", jitter(rng, 1800, j))
    body = thump(jitter(rng, 120, j), jitter(rng, 38, j), 0.03, jitter(rng, 0.25, j), 0.3)
    blast = burst(rng, 0.35, 0.001, jitter(rng, 0.25, j), "lowpass", glide(4000, 380, 0.08))
    rumble = burst(rng, 0.9, 0.01, jitter(rng, 0.8, j), "lowpass", 260)
    return saturate(mix((crack, 0.6), (body, 1.0), (blast, 0.8), (rumble, 0.55)), 2.5)


@sound("weapons/dray_swing", variants=3, seed="weapons/hammer_swing")
def dray_swing(rng: random.Random, take: str, variant: int) -> Signal:
    """Dray, the hammer, cutting the air: one heavy whoosh."""
    seconds = jitter(rng, 0.3, 0.1)

    def sweep(t: float) -> float:
        x = t / seconds
        return 260 + 900 * (4.0 * x * (1.0 - x)) ** 1.5

    return whoosh(rng, seconds, sweep, 1.4)


@sound("weapons/dray_hit", variants=3, seed="weapons/hammer_hit")
def dray_hit(rng: random.Random, take: str, variant: int) -> Signal:
    """Dray striking: a thud with a crunch and the steel head ringing."""
    j = 0.08
    thud = thump(jitter(rng, 95, j), jitter(rng, 50, j), 0.02, jitter(rng, 0.16, j), 0.2)
    crunch = burst(rng, 0.08, 0.0005, jitter(rng, 0.05, j), "bandpass", jitter(rng, 1500, j), 0.7)
    grit = shape(highpass(noise(rng, 0.12), 2500), env(0.12, 0.0005, 0.04))
    steel = [(420, 0.25, 1.0), (1130, 0.16, 0.6), (2210, 0.1, 0.4), (3480, 0.06, 0.25)]
    partials = [(jitter(rng, f, 0.03), d, level) for f, d, level in steel]
    ring = modes(rng, partials, 0.3)
    return saturate(mix((thud, 1.0), (crunch, 0.7), (grit, 0.25), (ring, 0.1)), 1.5)


@sound("weapons/empty_click", variants=2)
def empty_click(rng: random.Random, take: str, variant: int) -> Signal:
    """The trigger on an empty weapon that can't reload: two dry clicks (trigger, then the
    striker)."""
    return mix((click(rng, jitter(rng, 3200, 0.05), 8, 0.014), 1.0), (click(rng, 2400, 6, 0.012), 0.6, 0.035))


@sound("weapons/reload_start", variants=2)
def reload_start(rng: random.Random, take: str, variant: int) -> Signal:
    """A reload starting: the latch, the magazine sliding out and dropping."""
    j = 0.06
    latch = click(rng, jitter(rng, 2800, j), 6, 0.015)
    slide_out = shape(bandpass(noise(rng, 0.13), jitter(rng, 1600, j), 1.5), env(0.13, 0.03, 0.09))
    drop = mix((thump(300, 180, 0.005, 0.05, 0.06), 0.8), (burst(rng, 0.03, 0.0005, 0.02, "bandpass", 900, 1), 0.5))
    return mix((latch, 1.0), (slide_out, 0.35, 0.015), (drop, 0.8, 0.15))


@sound("weapons/shell_in", variants=3)
def shell_in(rng: random.Random, take: str, variant: int) -> Signal:
    """A shell pushed into Brask: a thunk with a brass ring."""
    j = 0.06
    ring = modes(rng, [(jitter(rng, 3100, j), 0.03, 1.0), (jitter(rng, 5200, j), 0.02, 0.5)], 0.05)
    body = thump(jitter(rng, 420, j), 260, 0.006, 0.04, 0.07)
    return mix((body, 1.0), (click(rng, jitter(rng, 2200, j), 4, 0.015), 0.6), (ring, 0.2, 0.003))


@sound("weapons/magazine_in", variants=2)
def magazine_in(rng: random.Random, take: str, variant: int) -> Signal:
    """A magazine seated: a short slide, the clack and the latch."""
    j = 0.06
    slide_in = shape(bandpass(noise(rng, 0.05), 1800, 1.5), env(0.05, 0.03, 0.02))
    clack = mix((thump(jitter(rng, 260, j), 150, 0.005, 0.06, 0.07), 1.0), (click(rng, 1800, 2.5, 0.02), 0.8))
    latch = click(rng, jitter(rng, 3500, j), 8, 0.012)
    return mix((slide_in, 0.35), (clack, 1.0, 0.04), (latch, 0.6, 0.065))


@sound("weapons/window_tick")
def window_tick(rng: random.Random, take: str, variant: int) -> Signal:
    """The timing window opening (a cue that must cut through): a bright, short sine tick."""
    body = mix((tone(2400, 0.07), 1.0), (tone(4800, 0.07), 0.15))
    return mix((shape(body, env(0.07, 0.0008, 0.045)), 1.0), (click(rng, 5000, 2, 0.003), 0.3))


@sound("weapons/timed_hit")
def timed_hit(rng: random.Random, take: str, variant: int) -> Signal:
    """A timing press within the window: a snap and two rising notes."""
    snap = click(rng, 4000, 3, 0.01)

    def note(freq: float) -> Signal:
        return shape(mix((tone(freq, 0.18), 1.0), (tone(freq * 2, 0.18), 0.12)), env(0.18, 0.002, 0.15))

    return mix((snap, 0.6), (note(1320), 0.5, 0.005), (note(1760), 0.6, 0.06))


@sound("weapons/timed_miss")
def timed_miss(rng: random.Random, take: str, variant: int) -> Signal:
    """A timing press outside the window (the reload takes longer): a dull clunk and a falling
    buzz."""
    clunk = mix((thump(160, 110, 0.01, 0.07, 0.09), 1.0), (click(rng, 900, 2, 0.02), 0.5))
    buzz = shape(lowpass(tone(slide(220, 150, 0.12), 0.14, "square"), 1100), env(0.14, 0.005, 0.12))
    return mix((clunk, 1.0), (buzz, 0.35, 0.02))
