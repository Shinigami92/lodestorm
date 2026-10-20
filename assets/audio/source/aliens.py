"""Recipes of the hive's sounds (wet, clicking, chittering): the aliens' chitter, strike, hits and
death, the telegraphs of their heavy attacks, the shrieker's scream, and the nests' pulse, hatching,
burst warning and collapse. The game plays them lower for bigger strains (`AlienStrain.voice_pitch`).
"""

import math
import random

from synth import (
    RATE,
    Signal,
    bandpass,
    bell,
    burst,
    click,
    count,
    crackle,
    echo,
    env,
    glide,
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
    tremolo,
)


def chatter(rng: random.Random, seconds: float, rate: float, freq: float, spread: float = 0.25) -> Signal:
    """A train of chitin clicks, `rate` a s (each gap jittered), ringing around `freq`."""
    out = [0.0] * count(seconds + 0.03)
    t = rng.uniform(0.0, 0.5 / rate)
    while t < seconds:
        tick = click(rng, jitter(rng, freq, spread), rng.uniform(4.0, 9.0), rng.uniform(0.004, 0.009))
        level = rng.uniform(0.5, 1.0)
        start = count(t)
        for i, s in enumerate(tick):
            if start + i < len(out):
                out[start + i] += s * level
        t += jitter(rng, 1.0 / rate, 0.45)
    return out


def bubbles(rng: random.Random, seconds: float, density: float, low: float, high: float) -> Signal:
    """Wet bubbles popping (`density` a s): short sine chirps rising, each between `low` and
    `high` Hz."""
    out = [0.0] * count(seconds + 0.06)
    for _ in range(max(1, round(seconds * density))):
        start = count(rng.uniform(0.0, seconds))
        freq = rng.uniform(low, high)
        length = rng.uniform(0.015, 0.05)
        chirp = shape(tone(slide(freq, freq * 1.8, length), length), env(length, 0.001, length * 0.8))
        level = rng.uniform(0.3, 1.0)
        for i, s in enumerate(chirp):
            if start + i < len(out):
                out[start + i] += s * level
    return out


def rasp(rng: random.Random, seconds: float, freq, formants: list[tuple[float, float]], rough: float) -> Signal:
    """A creature's voice: a saw wavering around `freq` (fixed or swept), through `formants`
    (frequency, level), roughened by `rough` (0..1) of fast flutter."""
    drift = [0.0]
    for _ in range(count(seconds) // 64 + 2):
        drift.append(drift[-1] * 0.97 + rng.uniform(-0.02, 0.02))

    def wavering(t: float) -> float:
        base = freq(t) if callable(freq) else freq
        return base * (1.0 + drift[int(t * RATE) // 64])

    source = tone(wavering, seconds, "saw")
    voiced = mix(*[(bandpass(source, f, 4.0), level) for f, level in formants])
    flutter = [
        1.0 - rough * 0.5 * (1.0 + math.sin(2.0 * math.pi * 31.0 * i / RATE + rng.random())) for i in range(len(voiced))
    ]
    return shape(voiced, flutter)


def squelch(rng: random.Random, seconds: float, start: float, end: float, q: float = 3.0) -> Signal:
    """Wet flesh: noise through a resonance sliding from `start` to `end` Hz."""
    return shape(bandpass(noise(rng, seconds), slide(start, end, seconds), q), env(seconds, 0.003, seconds * 0.8))


def swell(seconds: float, power: float = 2.0) -> Signal:
    """Rises from silence to full over `seconds`: a telegraph builds to its strike."""
    n = count(seconds)
    return [(i / n) ** power for i in range(n)]


# The aliens


@sound("aliens/chitter", variants=4)
def chitter(rng: random.Random, take: str, variant: int) -> Signal:
    """An alien noticing a player, and now and then while it chases: wet chittering, chitin clicks
    in quick runs with a hiss."""
    seconds = jitter(rng, 0.6, 0.2)
    runs = [chatter(rng, jitter(rng, 0.18, 0.3), jitter(rng, 34, 0.2), jitter(rng, 3400, 0.1)) for _ in range(3)]
    layers = [(run, 1.0, i * jitter(rng, 0.2, 0.2)) for i, run in enumerate(runs)]
    hiss = shape(bandpass(noise(rng, seconds), jitter(rng, 2600, 0.1), 2.0), bell(seconds, 0.3))
    return mix(*layers, (hiss, 0.25), (bubbles(rng, seconds, 18, 500, 1100), 0.2))


@sound("aliens/strike", variants=3)
def strike(rng: random.Random, take: str, variant: int) -> Signal:
    """An alien's bite or slash landing: a hiss, the jaws clacking shut and a wet tear."""
    j = 0.08
    hiss = shape(bandpass(noise(rng, 0.12), jitter(rng, 3200, j), 1.5), swell(0.12, 1.5))
    clack = mix(
        (click(rng, jitter(rng, 1700, j), 3, 0.02), 1.0), (click(rng, jitter(rng, 2600, j), 4, 0.015), 0.7, 0.012)
    )
    tear = squelch(rng, 0.14, jitter(rng, 1400, j), jitter(rng, 500, j), 2.0)
    return mix((hiss, 0.35), (clack, 1.0, 0.11), (tear, 0.7, 0.12), (thump(180, 90, 0.01, 0.05, 0.07), 0.5, 0.11))


@sound("aliens/hit", variants=4)
def hit(rng: random.Random, take: str, variant: int) -> Signal:
    """A hit in an alien's (or a nest's) flesh: a wet thwack and a squish."""
    j = 0.1
    thwack = mix(
        (thump(jitter(rng, 170, j), 80, 0.01, jitter(rng, 0.07, j), 0.09), 1.0),
        (burst(rng, 0.05, 0.0005, 0.025, "bandpass", jitter(rng, 700, j), 1.0), 0.8),
    )
    squish = squelch(rng, jitter(rng, 0.12, j), jitter(rng, 1600, j), jitter(rng, 420, j), 3.5)
    return mix((thwack, 1.0), (squish, 0.6, 0.01), (bubbles(rng, 0.1, 30, 600, 1400), 0.15, 0.02))


@sound("aliens/hit_armor", variants=3)
def hit_armor(rng: random.Random, take: str, variant: int) -> Signal:
    """A hit on an alien's armor plates: a hard, hollow chitin knock."""
    j = 0.08
    plate = [(jitter(rng, 950, j), 0.05, 1.0), (jitter(rng, 2150, j), 0.035, 0.7), (jitter(rng, 3600, j), 0.02, 0.4)]
    return mix(
        (modes(rng, plate, 0.08), 0.5),
        (click(rng, jitter(rng, 1800, j), 2, 0.012), 0.8),
        (thump(260, 150, 0.004, 0.04, 0.05), 0.6),
    )


@sound("aliens/death", variants=3)
def death(rng: random.Random, take: str, variant: int) -> Signal:
    """An alien dying: a screech falling away into a wet gurgle."""
    j = 0.08
    seconds = jitter(rng, 0.7, j)
    screech = rasp(rng, seconds, slide(jitter(rng, 820, j), 220, seconds), [(1100, 1.0), (2300, 0.6), (650, 0.5)], 0.6)
    screech = shape(saturate(screech, 2.0), env(seconds, 0.01, seconds * 0.9))
    gurgle = shape(bubbles(rng, 0.5, 40, 250, 700), env(0.5, 0.05, 0.45))
    return mix((screech, 0.8), (gurgle, 0.4, seconds * 0.5), (squelch(rng, 0.3, 900, 250, 2.5), 0.4, seconds * 0.6))


# The telegraphs of the heavy attacks (a wind-up, 0.3-1.2 s): each swells into its strike


@sound("aliens/windup_pounce", variants=2)
def windup_pounce(rng: random.Random, take: str, variant: int) -> Signal:
    """A pounce winding up (swarmer, stalker, 0.4 s): a hissing rattle rising quickly."""
    seconds = 0.4
    hiss = shape(bandpass(noise(rng, seconds), slide(1800, 4200, seconds), 2.0), swell(seconds))
    rattle = shape(chatter(rng, seconds, 45, 3200), swell(seconds, 1.5))
    return mix((hiss, 0.6), (rattle, 0.8))


@sound("aliens/windup_charge", variants=2)
def windup_charge(rng: random.Random, take: str, variant: int) -> Signal:
    """A charge winding up (brute, Ravager, 1 s): a snort, then a growl rising to a roar."""
    j = 0.06
    snort = burst(rng, 0.18, 0.02, 0.15, "lowpass", 700)
    growl = rasp(
        rng, 0.9, slide(jitter(rng, 70, j), jitter(rng, 125, j), 0.9), [(480, 1.0), (1100, 0.5), (250, 0.6)], 0.7
    )
    growl = shape(saturate(growl, 2.5), swell(0.9, 1.5))
    return mix((snort, 0.7), (growl, 0.9, 0.15), (lowpass(noise(rng, 1.05), 160), 0.25))


@sound("aliens/windup_slam", variants=2)
def windup_slam(rng: random.Random, take: str, variant: int) -> Signal:
    """A slam winding up (Ravager, warden, 1 s): a deep groan rising with the plates creaking."""
    groan = rasp(rng, 1.0, slide(48, 85, 1.0), [(300, 1.0), (700, 0.5)], 0.5)
    creak = bandpass(chatter(rng, 1.0, 22, 900, 0.4), 1100, 1.5)
    return mix((shape(saturate(groan, 2.0), swell(1.0, 1.4)), 1.0), (shape(creak, swell(1.0, 0.8)), 0.6))


@sound("aliens/windup_spit", variants=2)
def windup_spit(rng: random.Random, take: str, variant: int) -> Signal:
    """A spit winding up (spitter, skimmer, 0.3-0.6 s): acid gurgling in the throat, rising."""
    seconds = 0.6
    gurgle = shape(bubbles(rng, seconds, 70, 300, 900), swell(seconds, 1.2))
    throat = shape(bandpass(noise(rng, seconds), slide(600, 1600, seconds), 3.0), swell(seconds, 2.0))
    return mix((gurgle, 0.8), (throat, 0.5))


@sound("aliens/windup_burst")
def windup_burst(rng: random.Random, take: str, variant: int) -> Signal:
    """A bloater swelling to burst (0.5 s): a stretching, wet groan with a whine of tension."""
    seconds = 0.5
    groan = shape(rasp(rng, seconds, slide(90, 140, seconds), [(400, 1.0), (900, 0.4)], 0.4), swell(seconds, 1.2))
    whine = shape(tone(slide(350, 1100, seconds), seconds), swell(seconds, 3.0))
    return mix((groan, 0.7), (whine, 0.15), (shape(bubbles(rng, seconds, 60, 200, 600), swell(seconds)), 0.6))


@sound("aliens/windup_scream")
def windup_scream(rng: random.Random, take: str, variant: int) -> Signal:
    """A shrieker drawing breath for its scream (1 s): a long rasping inhale with clicks."""
    seconds = 1.0
    breath = shape(bandpass(noise(rng, seconds), slide(3200, 1100, seconds), 1.5), swell(seconds, 1.3))
    return mix((breath, 0.8), (shape(chatter(rng, seconds, 14, 2600), swell(seconds, 0.7)), 0.5))


@sound("aliens/scream")
def scream(rng: random.Random, take: str, variant: int) -> Signal:
    """A shrieker's scream (it calls the hive): a harsh, wavering shriek with an echo."""
    seconds = 1.2

    def voice(freq: float) -> Signal:
        def vibrato(t: float) -> float:
            return freq * (1.0 + 0.04 * math.sin(2.0 * math.pi * 7.0 * t)) * (1.0 - 0.15 * t)

        return rasp(rng, seconds, vibrato, [(1400, 1.0), (2900, 0.7), (800, 0.4)], 0.5)

    shriek = mix((voice(760), 1.0), (voice(810), 0.8), (voice(1130), 0.4))
    shriek = shape(saturate(shriek, 3.0), env(seconds, 0.05, 0.6, 0.55))
    return echo(shriek, 0.18, 0.35, 1600, 3)


@sound("aliens/windup_hook")
def windup_hook(rng: random.Random, take: str, variant: int) -> Signal:
    """A stalker drawing its flesh hook back (0.5 s): a wet creak tightening."""
    seconds = 0.5
    out = [0.0] * count(seconds + 0.02)
    t = 0.0
    while t < seconds:
        tick = click(rng, jitter(rng, 1300, 0.1), 3, 0.01)
        start = count(t)
        for i, s in enumerate(tick):
            if start + i < len(out):
                out[start + i] += s
        t += 1.0 / (30.0 + 120.0 * t / seconds)
    wet = shape(bandpass(noise(rng, seconds), 700, 2.5), swell(seconds))
    return mix((shape(out, swell(seconds, 0.8)), 0.8), (wet, 0.4))


@sound("aliens/windup_dive")
def windup_dive(rng: random.Random, take: str, variant: int) -> Signal:
    """A darter winding up its dive (0.6 s): its wings' buzz rising."""
    seconds = 0.6
    buzz = tremolo(tone(slide(130, 260, seconds), seconds, "saw"), 55, 0.8)
    buzz = bandpass(buzz, slide(700, 1600, seconds), 1.2)
    return shape(saturate(buzz, 1.5), swell(seconds, 1.2))


@sound("aliens/windup_eruption")
def windup_eruption(rng: random.Random, take: str, variant: int) -> Signal:
    """A burrower about to come up under its target (0.7 s): a rumble under the ground rising,
    with gravel trickling."""
    seconds = 0.7
    rumble = shape(lowpass(noise(rng, seconds), slide(70, 260, seconds)), swell(seconds, 1.2))
    gravel = shape(bandpass(crackle(rng, seconds, 500), 1800, 1.0), swell(seconds, 1.8))
    return mix((rumble, 1.0), (gravel, 0.6))


@sound("aliens/windup_shed")
def windup_shed(rng: random.Random, take: str, variant: int) -> Signal:
    """The Ravager shedding swarmers (1 s): its hide crackling and tearing open, a low groan."""
    seconds = 1.0
    tearing = shape(bandpass(crackle(rng, seconds, 1600), 1500, 1.0), swell(seconds, 1.5))
    groan = shape(rasp(rng, seconds, slide(55, 75, seconds), [(260, 1.0), (600, 0.4)], 0.6), bell(seconds, 0.6, 1.0))
    return mix((tearing, 0.8), (groan, 0.6), (shape(bubbles(rng, seconds, 40, 300, 800), swell(seconds)), 0.4))


# The nests


@sound("aliens/nest_pulse", variants=2)
def nest_pulse(rng: random.Random, take: str, variant: int) -> Signal:
    """One beat of a nest's pulse (faster and louder as the hive escalates): a deep, wet throb."""
    j = 0.06
    throb = thump(jitter(rng, 58, j), 36, 0.04, jitter(rng, 0.3, j), 0.35)
    wet = lowpass(squelch(rng, 0.25, 500, 180, 2.0), 900)
    return mix((throb, 1.0), (wet, 0.35, 0.02), (bubbles(rng, 0.3, 20, 150, 400), 0.15, 0.05))


@sound("aliens/nest_hatch", variants=3)
def nest_hatch(rng: random.Random, take: str, variant: int) -> Signal:
    """An alien hatching from a nest: the membrane tearing with a wet pop, slime dripping."""
    j = 0.1
    tear = squelch(rng, jitter(rng, 0.25, j), jitter(rng, 600, j), jitter(rng, 1800, j), 3.0)
    pop = mix((thump(jitter(rng, 140, j), 70, 0.015, 0.08, 0.1), 1.0), (click(rng, 1100, 2, 0.015), 0.4))
    drips = bubbles(rng, 0.4, 20, 400, 900)
    return mix((tear, 0.7), (pop, 0.9, jitter(rng, 0.18, j)), (drips, 0.3, 0.2))


@sound("aliens/nest_swell")
def nest_swell(rng: random.Random, take: str, variant: int) -> Signal:
    """A nest swelling to burst (its warning, 1 s): a groaning, bubbling rise."""
    seconds = 1.0
    groan = shape(rasp(rng, seconds, slide(45, 70, seconds), [(220, 1.0), (520, 0.5)], 0.4), swell(seconds, 1.3))
    boil = shape(bubbles(rng, seconds, 90, 150, 600), swell(seconds, 1.5))
    return mix((groan, 0.8), (boil, 0.6), (shape(lowpass(noise(rng, seconds), 200), swell(seconds)), 0.5))


@sound("aliens/nest_destroyed")
def nest_destroyed(rng: random.Random, take: str, variant: int) -> Signal:
    """A nest destroyed and collapsing (1.5 s): a wet crunch, the mound caving in with a rumble,
    gas hissing out and its glow's hum dying."""
    crunch = mix((thump(90, 40, 0.03, 0.4, 0.45), 1.0), (burst(rng, 0.3, 0.001, 0.2, "bandpass", 900, 0.8), 0.8))
    cave = shape(lowpass(noise(rng, 1.5), glide(400, 90, 0.8)), env(1.5, 0.1, 1.2, 0.2))
    hiss = shape(bandpass(noise(rng, 1.2), glide(3000, 900, 1.0), 1.0), env(1.2, 0.05, 1.0))
    hum = shape(tone(slide(110, 40, 1.4), 1.4, "triangle"), env(1.4, 0.05, 1.3))
    return mix(
        (crunch, 1.0), (cave, 0.7, 0.05), (hiss, 0.25, 0.1), (hum, 0.2), (bubbles(rng, 1.2, 25, 200, 600), 0.3, 0.1)
    )
