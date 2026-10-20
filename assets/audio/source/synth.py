"""Synthesis kit for the game's sound effects, standard library only.

A signal is a list of floats (mono, RATE samples per second, about -1..1). The building blocks
(oscillators, noise, envelopes, filters, a small reverb) return new lists; a recipe layers them
into one sound. Deterministic: every random source is a `random.Random` the build seeds per sound,
take and variant, so a rerun writes the same files.

A recipe is a function `(rng, take, variant) -> signal`, registered with `@sound(...)` in one of
the group modules (`weapons.py`, ...); `build.py` runs them.
"""

import math
import random
from collections.abc import Callable
from dataclasses import dataclass, field

RATE = 44100

Signal = list[float]
# A frequency in Hz: fixed, or a function of the time in s (a sweep)
Freq = float | Callable[[float], float]


@dataclass
class Recipe:
    """A sound: `name` is "<group>/<name>" (its folder and file name under assets/audio/sfx/)."""

    name: str
    make: Callable[[random.Random, str, int], Signal]
    # Files built per take (the game picks one at random each time it plays)
    variants: int
    # The takes the recipe knows (letters) and the one the game uses
    takes: str
    take: str
    # Recorded raw files it uses (paths under recordings/, each in manifest.json)
    recordings: tuple[str, ...] = field(default_factory=tuple)
    # Peak level of the built files in dBFS
    peak_db: float = -1.0

    @property
    def description(self) -> str:
        return (self.make.__doc__ or "").strip()


RECIPES: dict[str, Recipe] = {}


def sound(name: str, variants: int = 1, takes: str = "a", take: str = "a", **options) -> Callable:
    """Registers the decorated function as the recipe of `name` (see `Recipe`)."""

    def register(make: Callable[[random.Random, str, int], Signal]) -> Callable:
        assert name not in RECIPES, f"{name} registered twice"
        assert take in takes, f"{name}: take {take} not in {takes}"
        RECIPES[name] = Recipe(name, make, variants, takes, take, **options)
        return make

    return register


def count(seconds: float) -> int:
    return max(1, round(seconds * RATE))


def at(signal: Signal, index: int) -> float:
    return signal[index] if 0 <= index < len(signal) else 0.0


def jitter(rng: random.Random, value: float, amount: float) -> float:
    """`value` changed by up to +-`amount` (a share): each variant comes out a little different."""
    return value * (1.0 + rng.uniform(-amount, amount))


def _hz(freq: Freq, t: float) -> float:
    return freq(t) if callable(freq) else freq


# Sweeps


def glide(start: float, end: float, time: float) -> Callable[[float], float]:
    """Starts at `start` and settles exponentially on `end` (most of the way within `time`)."""
    return lambda t: end + (start - end) * math.exp(-4.6 * t / time)


def slide(start: float, end: float, time: float) -> Callable[[float], float]:
    """Moves from `start` to `end` evenly in pitch over `time`, then stays at `end`."""
    ratio = end / start
    return lambda t: start * ratio ** min(t / time, 1.0)


# Sources


def silence(seconds: float) -> Signal:
    return [0.0] * count(seconds)


def noise(rng: random.Random, seconds: float) -> Signal:
    return [rng.uniform(-1.0, 1.0) for _ in range(count(seconds))]


def crackle(rng: random.Random, seconds: float, density: float) -> Signal:
    """Sparse random impulses (`density` per s): sparks, grit."""
    chance = density / RATE
    return [rng.uniform(-1.0, 1.0) if rng.random() < chance else 0.0 for _ in range(count(seconds))]


def _blep(phase: float, step: float) -> float:
    # Smooths an oscillator's jump so it doesn't alias
    if phase < step:
        phase /= step
        return phase + phase - phase * phase - 1.0
    if phase > 1.0 - step:
        phase = (phase - 1.0) / step
        return phase * phase + phase + phase + 1.0
    return 0.0


def tone(freq: Freq, seconds: float, shape: str = "sine", phase: float = 0.0) -> Signal:
    """An oscillator: "sine", "saw", "square" or "triangle", its frequency fixed or swept."""
    out = []
    for i in range(count(seconds)):
        step = _hz(freq, i / RATE) / RATE
        if shape == "sine":
            value = math.sin(2.0 * math.pi * phase)
        elif shape == "saw":
            value = 2.0 * phase - 1.0 - _blep(phase, step)
        elif shape == "square":
            value = (1.0 if phase < 0.5 else -1.0) + _blep(phase, step) - _blep((phase + 0.5) % 1.0, step)
        elif shape == "triangle":
            value = 1.0 - 4.0 * abs(phase - 0.5)
        else:
            raise ValueError(shape)
        out.append(value)
        phase = (phase + step) % 1.0
    return out


def modes(rng: random.Random, partials: list[tuple[float, float, float]], seconds: float) -> Signal:
    """A struck solid (metal, a plate): partials of (frequency, decay to -60 dB in s, level)."""
    out = [0.0] * count(seconds)
    for freq, decay, level in partials:
        phase = rng.uniform(0.0, 2.0 * math.pi)
        rate = 6.9 / decay
        for i in range(len(out)):
            t = i / RATE
            out[i] += level * math.sin(2.0 * math.pi * freq * t + phase) * math.exp(-rate * t)
    return out


# Envelopes


def env(seconds: float, attack: float, decay: float, hold: float = 0.0) -> Signal:
    """Rises over `attack`, holds `hold`, then falls 60 dB over `decay` (all in s)."""
    rate = 6.9 / decay
    out = []
    for i in range(count(seconds)):
        t = i / RATE
        if t < attack:
            out.append(math.sin(0.5 * math.pi * t / attack))
        elif t < attack + hold:
            out.append(1.0)
        else:
            out.append(math.exp(-rate * (t - attack - hold)))
    return out


def bell(seconds: float, peak: float, sharpness: float = 2.0) -> Signal:
    """Swells to 1 at `peak` (a share of the length) and back to 0: a whoosh's shape."""
    n = count(seconds)
    out = []
    for i in range(n):
        x = i / n
        side = x / peak if x < peak else (1.0 - x) / (1.0 - peak)
        out.append(max(side, 0.0) ** sharpness)
    return out


def tremolo(signal: Signal, rate: float, depth: float) -> Signal:
    """Wobbles the level `rate` times a s, by up to `depth` (0..1)."""
    return [s * (1.0 - depth * 0.5 * (1.0 + math.sin(2.0 * math.pi * rate * i / RATE))) for i, s in enumerate(signal)]


# Filters


def _biquad(kind: str, freq: float, q: float) -> tuple[float, float, float, float, float]:
    freq = min(max(freq, 20.0), 0.45 * RATE)
    w = 2.0 * math.pi * freq / RATE
    alpha = math.sin(w) / (2.0 * q)
    cos = math.cos(w)
    if kind == "lowpass":
        b = ((1.0 - cos) / 2.0, 1.0 - cos, (1.0 - cos) / 2.0)
    elif kind == "highpass":
        b = ((1.0 + cos) / 2.0, -(1.0 + cos), (1.0 + cos) / 2.0)
    elif kind == "bandpass":
        b = (alpha, 0.0, -alpha)
    else:
        raise ValueError(kind)
    a0 = 1.0 + alpha
    return b[0] / a0, b[1] / a0, b[2] / a0, -2.0 * cos / a0, (1.0 - alpha) / a0


def biquad(signal: Signal, kind: str, freq: Freq, q: float = 0.707) -> Signal:
    """A 12 dB/octave "lowpass", "highpass" or "bandpass" (peak at 0 dB), its frequency fixed
    or swept."""
    out = []
    x1 = x2 = y1 = y2 = 0.0
    coefficients = _biquad(kind, _hz(freq, 0.0), q)
    for i, x in enumerate(signal):
        if callable(freq) and i % 16 == 0:
            coefficients = _biquad(kind, freq(i / RATE), q)
        b0, b1, b2, a1, a2 = coefficients
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def lowpass(signal: Signal, freq: Freq, q: float = 0.707) -> Signal:
    return biquad(signal, "lowpass", freq, q)


def highpass(signal: Signal, freq: Freq, q: float = 0.707) -> Signal:
    return biquad(signal, "highpass", freq, q)


def bandpass(signal: Signal, freq: Freq, q: float = 1.0) -> Signal:
    return biquad(signal, "bandpass", freq, q)


# Combining


def gain(signal: Signal, level: float) -> Signal:
    return [s * level for s in signal]


def shape(signal: Signal, envelope: Signal) -> Signal:
    """`signal` times `envelope` (as long as the shorter one)."""
    return [s * e for s, e in zip(signal, envelope)]


def mix(*layers: tuple[Signal, float] | tuple[Signal, float, float]) -> Signal:
    """Adds layers of (signal, level) or (signal, level, start in s)."""
    starts = [count(layer[2]) if len(layer) > 2 else 0 for layer in layers]
    out = [0.0] * max(start + len(layer[0]) for layer, start in zip(layers, starts))
    for layer, start in zip(layers, starts):
        signal, level = layer[0], layer[1]
        for i, s in enumerate(signal):
            out[start + i] += s * level
    return out


def saturate(signal: Signal, drive: float) -> Signal:
    """Soft clipping: rounds off the peaks, thickens a blast."""
    norm = math.tanh(drive)
    return [math.tanh(s * drive) / norm for s in signal]


def echo(signal: Signal, delay: float, level: float, cutoff: float = 2000.0, repeats: int = 2) -> Signal:
    """A few duller copies `delay` s apart: a slap off nearby rock."""
    out = list(signal) + [0.0] * count(delay * repeats)
    copy = signal
    for repeat in range(1, repeats + 1):
        copy = lowpass(copy, cutoff)
        start = count(delay * repeat)
        for i, s in enumerate(copy):
            out[start + i] += s * level**repeat
    return out


def reverb(signal: Signal, size: float, decay: float, wet: float, damp: float = 3000.0) -> Signal:
    """A small Schroeder reverb: `size` scales the room (1: a hall), `decay` in s to -60 dB."""
    tail = count(decay)
    dry = list(signal) + [0.0] * tail
    wet_sum = [0.0] * len(dry)
    for delay_ms in (29.7, 37.1, 41.1, 43.7):
        delay = max(1, round(delay_ms * size * RATE / 1000.0))
        feedback = 10.0 ** (-3.0 * delay / RATE / decay)
        buffer = [0.0] * delay
        damping = math.exp(-2.0 * math.pi * damp / RATE)
        low = 0.0
        for i, x in enumerate(dry):
            y = buffer[i % delay]
            low = y * (1.0 - damping) + low * damping
            buffer[i % delay] = x + low * feedback
            wet_sum[i] += y * 0.25
    for delay_ms, g in ((5.0, 0.7), (1.7, 0.7)):
        delay = max(1, round(delay_ms * size * RATE / 1000.0))
        buffer = [0.0] * delay
        for i, x in enumerate(wet_sum):
            y = buffer[i % delay]
            v = x + g * y
            buffer[i % delay] = v
            wet_sum[i] = y - g * v
    return [d + w * wet for d, w in zip(dry, wet_sum)]


def concat(*signals: Signal) -> Signal:
    out: Signal = []
    for signal in signals:
        out.extend(signal)
    return out


# Common layers


def thump(start: float, end: float, sweep: float, decay: float, seconds: float | None = None) -> Signal:
    """A body: a sine dropping from `start` to `end` Hz, falling 60 dB over `decay` s."""
    seconds = seconds or decay
    return shape(tone(glide(start, end, sweep), seconds), env(seconds, 0.001, decay))


def burst(rng: random.Random, seconds: float, attack: float, decay: float, kind: str, freq: Freq, q: float = 0.707):
    """Filtered noise with an envelope: a crack, a hiss, a blast."""
    return shape(biquad(noise(rng, seconds), kind, freq, q), env(seconds, attack, decay))


def click(rng: random.Random, freq: float = 3000.0, q: float = 4.0, decay: float = 0.012) -> Signal:
    """A small mechanical click: a ringing noise impulse."""
    seconds = decay * 1.2
    return shape(bandpass(noise(rng, seconds), freq, q), env(seconds, 0.0003, decay))


def whoosh(rng: random.Random, seconds: float, freq: Freq, q: float, peak: float = 0.45) -> Signal:
    """Air rushing past: band-passed noise swelling and fading."""
    return shape(bandpass(noise(rng, seconds), freq, q), bell(seconds, peak))


# Finishing


def finish(signal: Signal, peak_db: float) -> Signal:
    """Removes DC rumble, trims the silent tail, fades the ends and scales the peak to `peak_db`."""
    signal = highpass(signal, 25.0)
    peak = max((abs(s) for s in signal), default=0.0)
    if peak <= 0.0:
        return signal
    floor = peak * 10.0 ** (-60.0 / 20.0)
    end = len(signal)
    while end > 1 and abs(signal[end - 1]) < floor:
        end -= 1
    signal = signal[: min(len(signal), end + count(0.01))]
    fade_in, fade_out = count(0.0003), min(count(0.005), len(signal))
    for i in range(min(fade_in, len(signal))):
        signal[i] *= i / fade_in
    for i in range(fade_out):
        signal[-1 - i] *= i / fade_out
    scale = 10.0 ** (peak_db / 20.0) / peak
    return [s * scale for s in signal]
