"""Recipes of the weapons' sounds: shots, Dray's swings, Riven's slashes and lunge, Auger's thrust
and drill, Jag's saw, Grindle's spin, Quill's charge, Pinner's battery, Tremor's and Wick's blasts
and charges, Scald's flame, Kith's and Zenith's beams, overheating and venting, Fulgen's lightning,
Nadir's wells, reloads and the timing window."""

import random

from synth import (
    Signal,
    bandpass,
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
    saturate,
    shape,
    slide,
    sound,
    thump,
    tone,
    tremolo,
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


@sound("weapons/pinner_shot", variants=4)
def pinner_shot(rng: random.Random, take: str, variant: int) -> Signal:
    """Pinner, the rivet pistol: a light pneumatic snap with a metal tick, no boom."""
    j = 0.08
    snap = burst(rng, 0.03, 0.0002, jitter(rng, 0.012, j), "highpass", jitter(rng, 3200, j))
    puff = burst(rng, 0.08, 0.001, jitter(rng, 0.04, j), "bandpass", jitter(rng, 1400, j), 1.2)
    body = thump(jitter(rng, 330, j), jitter(rng, 180, j), 0.008, jitter(rng, 0.035, j), 0.06)
    tick = modes(rng, [(jitter(rng, 4200, 0.04), 0.025, 1.0), (jitter(rng, 6900, 0.04), 0.015, 0.5)], 0.04)
    return saturate(mix((snap, 0.7), (puff, 0.6), (body, 0.7), (tick, 0.15, 0.004)), 1.3)


@sound("weapons/pinner_charged")
def pinner_charged(rng: random.Random, take: str, variant: int) -> Signal:
    """Pinner's battery full again after running dry: a soft rising two-tone chirp."""

    def note(freq: float, seconds: float) -> Signal:
        return shape(
            mix((tone(freq, seconds), 1.0), (tone(freq * 2.0, seconds), 0.2)), env(seconds, 0.004, seconds * 0.8)
        )

    return mix((note(1180, 0.09), 0.6), (note(1770, 0.14), 0.7, 0.07))


@sound("weapons/grindle_shot", variants=4)
def grindle_shot(rng: random.Random, take: str, variant: int) -> Signal:
    """Grindle, the rotary gun (14 shots a second): a short, dry punch that blurs into a roar."""
    j = 0.08
    crack = burst(rng, 0.025, 0.0002, jitter(rng, 0.008, j), "highpass", jitter(rng, 2200, j))
    body = thump(jitter(rng, 150, j), jitter(rng, 60, j), 0.01, jitter(rng, 0.05, j), 0.08)
    bark = burst(rng, 0.06, 0.0008, jitter(rng, 0.035, j), "bandpass", jitter(rng, 700, j), 0.9)
    return saturate(mix((crack, 0.6), (body, 1.0), (bark, 0.6)), 1.8)


@sound("weapons/grindle_spin", loop=True)
def grindle_spin(rng: random.Random, take: str, variant: int) -> Signal:
    """Grindle's barrels spinning (a loop, 1 s, its pitch following the spin): a motor whine over
    the rattle of the barrels going round."""
    seconds = loop_seconds(1.0)
    whine = lowpass(mix((tone(220, seconds, "saw"), 1.0), (tone(440, seconds), 0.4)), 1600)
    rattle = tremolo(bandpass(noise(rng, seconds), 2400, 2.0), 30.0, 0.7)
    hum = lowpass(tone(55, seconds, "square"), 300)
    return saturate(mix((whine, 0.35), (rattle, 0.5), (hum, 0.4)), 1.2)


@sound("weapons/quill_shot", variants=3)
def quill_shot(rng: random.Random, take: str, variant: int) -> Signal:
    """Quill, the rail rifle: an electric snap, a hard crack and a falling zing down the rails."""
    j = 0.06
    snap = burst(rng, 0.02, 0.0001, jitter(rng, 0.006, j), "highpass", jitter(rng, 4000, j))
    crack = burst(rng, 0.12, 0.0005, jitter(rng, 0.07, j), "bandpass", jitter(rng, 1800, j), 0.8)
    body = thump(jitter(rng, 140, j), jitter(rng, 45, j), 0.02, jitter(rng, 0.18, j), 0.25)
    zing = shape(tone(glide(jitter(rng, 3600, j), 900, 0.25), 0.35, "saw"), env(0.35, 0.002, 0.25))
    tail = burst(rng, 0.5, 0.004, jitter(rng, 0.35, j), "lowpass", glide(2500, 400, 0.2))
    return saturate(mix((snap, 0.7), (crack, 0.8), (body, 0.9), (lowpass(zing, 5000), 0.2), (tail, 0.35)), 1.6)


@sound("weapons/quill_charge", loop=True)
def quill_charge(rng: random.Random, take: str, variant: int) -> Signal:
    """Quill charging (a loop, 1 s, its pitch rising with the charge): a capacitor hum with a fast
    electric flutter."""
    seconds = loop_seconds(1.0)
    hum = mix((tone(330, seconds), 1.0), (tone(660, seconds), 0.35), (tone(990, seconds, "square"), 0.08))
    flutter = tremolo(highpass(noise(rng, seconds), 5000), 24.0, 0.8)
    return mix((tremolo(hum, 12.0, 0.25), 0.6), (flutter, 0.08))


@sound("weapons/quill_full")
def quill_full(rng: random.Random, take: str, variant: int) -> Signal:
    """Quill's charge full: a bright, short ping that cuts through the hum."""
    ping = modes(rng, [(2640, 0.25, 1.0), (5280, 0.12, 0.3), (7920, 0.06, 0.1)], 0.3)
    return mix((ping, 1.0), (click(rng, 6000, 3, 0.004), 0.3))


@sound("weapons/tremor_shot", variants=3)
def tremor_shot(rng: random.Random, take: str, variant: int) -> Signal:
    """Tremor, the seismic launcher: a hollow, deep thunk out of the tube, then a short hiss."""
    j = 0.07
    thunk = thump(jitter(rng, 120, j), jitter(rng, 55, j), 0.02, jitter(rng, 0.12, j), 0.2)
    pop = burst(rng, 0.1, 0.0005, jitter(rng, 0.05, j), "bandpass", jitter(rng, 500, j), 1.4)
    hollow = shape(bandpass(noise(rng, 0.18), jitter(rng, 260, j), 6.0), env(0.18, 0.002, 0.12))
    hiss = burst(rng, 0.35, 0.01, jitter(rng, 0.25, j), "highpass", glide(3000, 1800, 0.3))
    return saturate(mix((thunk, 1.0), (pop, 0.7), (hollow, 0.5), (hiss, 0.2, 0.02)), 1.5)


@sound("weapons/blast", variants=3)
def blast(rng: random.Random, take: str, variant: int) -> Signal:
    """A blast (Tremor's shells, Wick's charges): a hard crack, a deep boom, and rock and grit
    raining down."""
    j = 0.08
    crack = burst(rng, 0.06, 0.0002, jitter(rng, 0.03, j), "highpass", jitter(rng, 1800, j))
    boom = thump(jitter(rng, 75, j), 28, 0.04, jitter(rng, 0.55, j), 0.9)
    roar = burst(rng, 0.9, 0.003, jitter(rng, 0.6, j), "lowpass", glide(2600, 300, 0.7))
    grit = shape(highpass(crackle(rng, 0.9, 500), 1800), env(0.9, 0.08, 0.7))
    return saturate(mix((crack, 0.7), (boom, 1.0), (roar, 0.8), (grit, 0.25, 0.08)), 2.2)


@sound("weapons/wick_toss", variants=2)
def wick_toss(rng: random.Random, take: str, variant: int) -> Signal:
    """Wick tossing a charge: a spring's soft clack and a short swish."""
    j = 0.08
    clack = modes(rng, [(jitter(rng, 1900, j), 0.03, 1.0), (jitter(rng, 3100, j), 0.02, 0.5)], 0.05)
    spring = shape(tone(glide(jitter(rng, 700, j), 400, 0.06), 0.08, "triangle"), env(0.08, 0.002, 0.06))
    swish = whoosh(rng, 0.22, glide(1500, 2600, 0.2), 1.2)
    return mix((clack, 0.8), (spring, 0.3), (swish, 0.5, 0.02), (click(rng, 2500, 3, 0.01), 0.4))


@sound("weapons/wick_armed")
def wick_armed(rng: random.Random, take: str, variant: int) -> Signal:
    """A charge armed: two short, low beeps."""

    def beep(freq: float) -> Signal:
        return shape(mix((tone(freq, 0.06, "square"), 0.5), (tone(freq, 0.06), 1.0)), env(0.06, 0.002, 0.05))

    return lowpass(mix((beep(880), 0.6), (beep(880), 0.6, 0.1)), 3500)


@sound("weapons/wick_tripped")
def wick_tripped(rng: random.Random, take: str, variant: int) -> Signal:
    """A charge tripped (0.35 s until it blasts): fast rising beeps."""

    def beep(freq: float) -> Signal:
        return shape(mix((tone(freq, 0.04, "square"), 0.5), (tone(freq, 0.04), 1.0)), env(0.04, 0.001, 0.035))

    return lowpass(mix(*((beep(1000 + 220 * i), 0.6, 0.065 * i) for i in range(5))), 4500)


@sound("weapons/scald_flame", loop=True)
def scald_flame(rng: random.Random, take: str, variant: int) -> Signal:
    """Scald's flame (a loop, 1 s, while it fires): a roaring hiss of burning gas with a low,
    fluttering rumble and the odd crackle."""
    seconds = loop_seconds(1.0)
    roar = lowpass(bandpass(noise(rng, seconds), 900, 0.6), 2400)
    hiss = highpass(noise(rng, seconds), 3500)
    rumble = tremolo(lowpass(noise(rng, seconds), 180), 9.0, 0.5)
    crack = highpass(crackle(rng, seconds, 30), 1500)
    return saturate(mix((roar, 0.8), (hiss, 0.15), (rumble, 0.9), (crack, 0.2)), 1.3)


@sound("weapons/kith_beam", loop=True)
def kith_beam(rng: random.Random, take: str, variant: int) -> Signal:
    """Kith's beam (a loop, 1 s, while it fires): a soft, warm chord that slowly breathes, with a
    faint shimmer on top."""
    seconds = loop_seconds(1.0)
    chord = mix(
        (tone(392, seconds), 1.0), (tone(494, seconds), 0.6), (tone(587, seconds), 0.45), (tone(784, seconds), 0.2)
    )
    shimmer = tremolo(bandpass(noise(rng, seconds), 6000, 2.0), 8.0, 0.6)
    return mix((tremolo(chord, 2.0, 0.25), 0.6), (shimmer, 0.05))


@sound("weapons/zenith_beam", loop=True)
def zenith_beam(rng: random.Random, take: str, variant: int) -> Signal:
    """Zenith's beam (a loop, 1 s, while it fires): a deep, searing drone with a hard electric
    buzz and a crackling edge."""
    seconds = loop_seconds(1.0)
    drone = lowpass(mix((tone(82, seconds, "saw"), 1.0), (tone(164, seconds, "square"), 0.35)), 900)
    buzz = bandpass(tone(330, seconds, "saw"), 1800, 1.5)
    sear = tremolo(highpass(noise(rng, seconds), 4000), 30.0, 0.7)
    crack = highpass(crackle(rng, seconds, 60), 2500)
    return saturate(mix((drone, 0.8), (buzz, 0.3), (sear, 0.12), (crack, 0.15)), 1.8)


@sound("weapons/overheat")
def overheat(rng: random.Random, take: str, variant: int) -> Signal:
    """A heat-fed weapon overheating: a sharp metallic ping and two short, falling alarm tones."""

    def falling(start: float) -> Signal:
        return shape(tone(glide(start, start * 0.7, 0.12), 0.14, "square"), env(0.14, 0.003, 0.11))

    ping = modes(rng, [(3300, 0.12, 1.0), (5100, 0.06, 0.4)], 0.15)
    return lowpass(mix((ping, 0.6), (falling(1400), 0.4, 0.05), (falling(1400), 0.4, 0.22)), 5000)


@sound("weapons/heat_vent", variants=2)
def heat_vent(rng: random.Random, take: str, variant: int) -> Signal:
    """A heat-fed weapon venting: a valve's clack and a long, falling hiss of hot gas."""
    j = 0.06
    clack = mix((click(rng, jitter(rng, 2600, j), 5, 0.015), 1.0), (thump(320, 200, 0.005, 0.05, 0.06), 0.6))
    hiss = burst(rng, 1.3, 0.02, jitter(rng, 0.9, j), "bandpass", glide(jitter(rng, 5200, j), 1800, 1.1), 0.8)
    return mix((clack, 0.8), (hiss, 0.7, 0.03))


@sound("weapons/cell_in", variants=2)
def cell_in(rng: random.Random, take: str, variant: int) -> Signal:
    """A fuel cell seated: a heavy slide, a clunk, and a short pressurising hiss."""
    j = 0.06
    slide_in = shape(bandpass(noise(rng, 0.07), 1300, 1.5), env(0.07, 0.03, 0.03))
    clunk = mix((thump(jitter(rng, 200, j), 110, 0.006, 0.08, 0.1), 1.0), (click(rng, 1500, 2.5, 0.02), 0.6))
    hiss = burst(rng, 0.25, 0.01, 0.18, "highpass", 4200)
    return mix((slide_in, 0.35), (clunk, 1.0, 0.05), (hiss, 0.2, 0.1))


@sound("weapons/fulgen_arc", variants=4)
def fulgen_arc(rng: random.Random, take: str, variant: int) -> Signal:
    """Fulgen's lightning (4 a second): a sharp electric crack, a short buzzing snarl and a
    crackling tail."""
    j = 0.08
    crack = burst(rng, 0.05, 0.0002, jitter(rng, 0.02, j), "highpass", jitter(rng, 2500, j))
    snarl = shape(bandpass(tone(glide(jitter(rng, 180, j), 90, 0.12), 0.16, "saw"), 1400, 1.2), env(0.16, 0.002, 0.12))
    tail = shape(highpass(crackle(rng, 0.22, 400), 2200), env(0.22, 0.004, 0.18))
    return saturate(mix((crack, 0.8), (snarl, 0.6), (tail, 0.35, 0.01)), 1.6)


@sound("weapons/nadir_shot", variants=2)
def nadir_shot(rng: random.Random, take: str, variant: int) -> Signal:
    """Nadir firing its orb: a deep, soft whomp and a low hum sliding down."""
    j = 0.06
    whomp = thump(jitter(rng, 110, j), 38, 0.12, 0.35, 0.45)
    hum = shape(tone(glide(jitter(rng, 220, j), 70, 0.35), 0.45, "triangle"), env(0.45, 0.01, 0.3))
    air = whoosh(rng, 0.3, glide(900, 300, 0.3), 0.8, 0.2)
    return mix((whomp, 1.0), (hum, 0.4), (air, 0.25))


@sound("weapons/well_hum", loop=True)
def well_hum(rng: random.Random, take: str, variant: int) -> Signal:
    """A gravity well open (a loop, 1 s): a deep throbbing drone with air rushing in."""
    seconds = loop_seconds(1.0)
    drone = mix((tone(55, seconds), 1.0), (tone(83, seconds, "triangle"), 0.4), (tone(110, seconds), 0.2))
    rush = bandpass(noise(rng, seconds), 500, 0.9)
    return mix((tremolo(drone, 6.0, 0.45), 0.8), (tremolo(rush, 3.0, 0.5), 0.2))


@sound("weapons/well_burst", variants=2)
def well_burst(rng: random.Random, take: str, variant: int) -> Signal:
    """A gravity well bursting: a short sucking rise, then a deep, hollow boom."""
    j = 0.08
    suck = shape(bandpass(noise(rng, 0.16), glide(300, 2600, 0.16), 2.0), env(0.16, 0.14, 0.02))
    boom = thump(jitter(rng, 70, j), 30, 0.06, jitter(rng, 0.6, j), 0.8)
    body = burst(rng, 0.6, 0.004, 0.45, "lowpass", glide(1600, 200, 0.5))
    return saturate(mix((suck, 0.45), (boom, 1.0, 0.15), (body, 0.6, 0.15)), 1.8)


@sound("weapons/nadir_charged")
def nadir_charged(rng: random.Random, take: str, variant: int) -> Signal:
    """Nadir's battery holding one more well: a soft, low two-tone chime."""

    def note(freq: float, seconds: float) -> Signal:
        return shape(
            mix((tone(freq, seconds), 1.0), (tone(freq * 2.0, seconds), 0.15)), env(seconds, 0.006, seconds * 0.8)
        )

    return mix((note(523, 0.12), 0.6), (note(784, 0.2), 0.7, 0.09))


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


@sound("weapons/riven_swing", variants=3)
def riven_swing(rng: random.Random, take: str, variant: int) -> Signal:
    """Riven, the blade, cutting the air (3 a second): a short, thin swish with a faint metallic
    whistle."""
    seconds = jitter(rng, 0.16, 0.1)

    def sweep(t: float) -> float:
        x = t / seconds
        return 900 + 2600 * (4.0 * x * (1.0 - x)) ** 1.2

    swish = whoosh(rng, seconds, sweep, 2.2)
    whistle = shape(tone(glide(jitter(rng, 2400, 0.05), 3100, seconds), seconds), env(seconds, 0.03, 0.08))
    return mix((swish, 1.0), (whistle, 0.08))


@sound("weapons/riven_lunge", variants=2)
def riven_lunge(rng: random.Random, take: str, variant: int) -> Signal:
    """Riven's lunge: a quick rush of air rising into a sharp, ringing stab."""
    j = 0.06
    rush = whoosh(rng, 0.22, glide(500, 2600, 0.22), 1.6, 0.3)
    stab = burst(rng, 0.06, 0.0003, jitter(rng, 0.03, j), "highpass", jitter(rng, 3000, j))
    steel = [(1850, 0.2, 1.0), (3920, 0.12, 0.5), (5600, 0.08, 0.3)]
    ring = modes(rng, [(jitter(rng, f, 0.03), d, level) for f, d, level in steel], 0.25)
    return saturate(mix((rush, 0.8), (stab, 0.7, 0.16), (ring, 0.1, 0.16)), 1.3)


@sound("weapons/riven_hit", variants=3)
def riven_hit(rng: random.Random, take: str, variant: int) -> Signal:
    """Riven slicing into something: a sharp scrape of steel and a short, wet cut."""
    j = 0.08
    scrape = shape(bandpass(noise(rng, 0.09), glide(jitter(rng, 4200, j), 2200, 0.09), 2.5), env(0.09, 0.001, 0.06))
    cut = burst(rng, 0.07, 0.0005, jitter(rng, 0.04, j), "bandpass", jitter(rng, 1100, j), 0.8)
    tick = click(rng, jitter(rng, 2800, j), 8, 0.01)
    return saturate(mix((scrape, 0.7), (cut, 0.9), (tick, 0.4)), 1.4)


@sound("weapons/auger_thrust", variants=3)
def auger_thrust(rng: random.Random, take: str, variant: int) -> Signal:
    """Auger, the drill lance, thrusting: a pneumatic hiss and a hard, low punch."""
    j = 0.06
    hiss = shape(highpass(noise(rng, 0.14), jitter(rng, 2800, j)), env(0.14, 0.002, 0.1))
    punch = thump(jitter(rng, 120, j), 55, 0.015, jitter(rng, 0.12, j), 0.3)
    clank = modes(rng, [(jitter(rng, 640, 0.04), 0.12, 1.0), (jitter(rng, 1530, 0.04), 0.08, 0.5)], 0.15)
    return saturate(mix((hiss, 0.5), (punch, 1.0, 0.02), (clank, 0.2, 0.02)), 1.4)


@sound("weapons/auger_hit", variants=2)
def auger_hit(rng: random.Random, take: str, variant: int) -> Signal:
    """Auger's point piercing: a crunch through chitin with a dull, wet thud."""
    j = 0.08
    crunch = burst(rng, 0.1, 0.0005, jitter(rng, 0.06, j), "bandpass", jitter(rng, 1700, j), 0.9)
    thud = thump(jitter(rng, 85, j), 45, 0.01, jitter(rng, 0.14, j), 0.2)
    grit = shape(highpass(crackle(rng, 0.12, 300), 2000), env(0.12, 0.001, 0.08))
    return saturate(mix((crunch, 0.9), (thud, 0.9), (grit, 0.3)), 1.5)


@sound("weapons/auger_drill", loop=True)
def auger_drill(rng: random.Random, take: str, variant: int) -> Signal:
    """Auger drilling (a loop, 1 s, its pitch rising with the drill): a high motor whine over a
    gritty, chattering grind."""
    seconds = loop_seconds(1.0)
    whine = lowpass(mix((tone(330, seconds, "saw"), 1.0), (tone(660, seconds), 0.3)), 2400)
    grind = tremolo(bandpass(noise(rng, seconds), 1800, 1.4), 24.0, 0.6)
    grit = highpass(crackle(rng, seconds, 80), 2500)
    return saturate(mix((whine, 0.3), (grind, 0.7), (grit, 0.25)), 1.4)


@sound("weapons/jag_saw", loop=True)
def jag_saw(rng: random.Random, take: str, variant: int) -> Signal:
    """Jag, the rock saw, running (a loop, 1 s, its pitch following the blade): a raw two-stroke
    motor and the blade's teeth buzzing round."""
    seconds = loop_seconds(1.0)
    motor = lowpass(tremolo(tone(70, seconds, "square"), 35.0, 0.5), 900)
    teeth = tremolo(bandpass(tone(180, seconds, "saw"), 1300, 1.0), 60.0, 0.4)
    air = bandpass(noise(rng, seconds), 2600, 1.2)
    return saturate(mix((motor, 0.6), (teeth, 0.5), (air, 0.15)), 1.5)


@sound("weapons/jag_bite", variants=3)
def jag_bite(rng: random.Random, take: str, variant: int) -> Signal:
    """Jag's blade biting into something (up to 10 a second): a short, harsh rasp."""
    j = 0.1
    rasp = shape(
        tremolo(bandpass(noise(rng, 0.09), jitter(rng, 2000, j), 1.6), jitter(rng, 120, j), 0.7),
        env(0.09, 0.002, 0.06),
    )
    crunch = burst(rng, 0.05, 0.0005, 0.03, "bandpass", jitter(rng, 900, j), 0.7)
    return saturate(mix((rasp, 0.9), (crunch, 0.5)), 1.6)


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
