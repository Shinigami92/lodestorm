// The ores' glow patterns (see OreType.Glow), shared by the crystal, fill and badge shaders. The
// rhythms match `OreGlow.intensity` in scripts/mining/ore_glow.gd: change both together. Nothing
// flashes faster than 3 times a second (photosensitivity). The rates and depths are TBD
// (playtest).

#define GLOW_STEADY 0
#define GLOW_SLOW_PULSE 1
#define GLOW_FAST_PULSE 2
#define GLOW_FLICKER 3
#define GLOW_WAVE 4
#define GLOW_SPARKLE 5
#define GLOW_BREATHING 6
#define GLOW_HEARTBEAT 7
#define GLOW_SHIFTING 8

// How many bright bands of a wave pass a point per second, and their spacing (in meters, or in
// the badge's height).
const float WAVE_RATE = 0.6;
const float WAVE_LENGTH = 0.6;
// Full hue turns per second of a shifting glow.
const float SHIFT_RATE = 0.1;

float ore_hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float ore_hash31(vec3 p) {
	vec3 q = fract(p * 0.1031);
	q += dot(q, q.zyx + 31.32);
	return fract((q.x + q.y) * q.z);
}

vec3 ore_hash33(vec3 p) {
	vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yxx) * q.zyx);
}

// Smooth value noise over time, 0..1, changing direction at most once per unit.
float ore_value_noise(float x) {
	float i = floor(x);
	float f = x - i;
	float u = f * f * (3.0 - 2.0 * f);
	return mix(ore_hash11(i), ore_hash11(i + 1.0), u);
}

// Bright bands, 0..1, passing a point `height` up at `t`.
float ore_wave(float t, float height) {
	float w = 0.5 + 0.5 * sin(TAU * (WAVE_RATE * t - height / WAVE_LENGTH));
	return w * w * w;
}

// Brightness of `glow` at time `t` (seconds, phase included), 1.0 being the ore's full glow; for a
// wave at `height` (0 at the bottom).
float ore_intensity(int glow, float t, float height) {
	if (glow == GLOW_SLOW_PULSE) {
		return 0.775 + 0.225 * sin(TAU * 0.4 * t);
	} else if (glow == GLOW_FAST_PULSE) {
		return 0.88 + 0.12 * sin(TAU * 2.5 * t);
	} else if (glow == GLOW_FLICKER) {
		float flicker = ore_value_noise(t * 3.5);
		float dip = smoothstep(0.65, 0.9, ore_value_noise(t * 0.6 + 31.7));
		return (0.8 + 0.25 * flicker) * (1.0 - 0.4 * dip);
	} else if (glow == GLOW_WAVE) {
		return 0.6 + 0.55 * ore_wave(t, height);
	} else if (glow == GLOW_SPARKLE) {
		return 0.85 + 0.08 * sin(TAU * 1.3 * t) + 0.07 * sin(TAU * 1.9 * t + 1.0);
	} else if (glow == GLOW_BREATHING) {
		return 0.5 + 0.55 * (0.5 - 0.5 * cos(TAU * 0.25 * t));
	} else if (glow == GLOW_HEARTBEAT) {
		float x = fract(t * 1.1) / 1.1;
		float a = (x - 0.15) / 0.06;
		float b = (x - 0.38) / 0.07;
		float lub = exp(-a * a);
		float dub = 0.65 * exp(-b * b);
		return 0.55 + 0.5 * (lub + dub);
	}
	return 1.0;
}

// How far a breathing glow has inhaled, 0..1 (its core grows brighter with it).
float ore_breath(float t) {
	return 0.5 - 0.5 * cos(TAU * 0.25 * t);
}

// One facet's twinkle, 0..1: a short glint at a random time, every 2 to 4 seconds.
float ore_twinkle(float t, float facet) {
	float rate = 0.25 + 0.2 * ore_hash11(facet * 7.13 + 3.1);
	float s = max(sin(TAU * (rate * t + ore_hash11(facet))), 0.0);
	return pow(s, 24.0);
}

// `color` with its hue turned by `angle` (radians) around the grey axis.
vec3 ore_hue_rotate(vec3 color, float angle) {
	const vec3 k = vec3(0.57735);
	float c = cos(angle);
	return color * c + cross(k, color) * sin(angle) + k * dot(k, color) * (1.0 - c);
}

// Hue turn of a shifting glow at `t` (radians).
float ore_hue_angle(float t) {
	return TAU * SHIFT_RATE * t;
}

// Distance to the nearest edge between 3D cells (roughly; 0 on an edge), in cell units: the veins
// of a dark-bodied ore.
float ore_cell_edge(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = p - cell;
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 r = offset + ore_hash33(cell + offset) - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}
