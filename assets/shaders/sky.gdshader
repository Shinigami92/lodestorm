shader_type sky;
// The one sky outside and in space (`WeatherSky` sets it), in layers, cheap enough for VR:
// - the body's sky: a gradient from the zenith to the horizon, where it meets the biome's haze
//   (below the horizon only haze, the far land fades into it);
// - the star Kesh: a disc with a glow, small and pale far out, big and harsh inwards with flares
//   (rays and a wide glare);
// - on a moon its planet, large and lit from the star's side; the other planets as bright points;
// - the biome's weather overhead (a cloud, ash or snow layer);
// - the storm: a towering wall of cloud on its side during the warning, closing over the sky when
//   it hits;
// - space (blended in by `space`): black with stars in every direction and the planet's glow far
//   below.
// Only uniforms set from the script, no TIME: the radiance map only updates when they change.

uniform vec3 zenith_color : source_color = vec3(0.05, 0.05, 0.07);
uniform vec3 horizon_color : source_color = vec3(0.16, 0.15, 0.16);
// The haze at and below the horizon (the fog's color) and how far up it reaches.
uniform vec3 haze_color : source_color = vec3(0.3, 0.27, 0.25);
uniform float haze_reach : hint_range(0.0, 1.0) = 0.2;

// Towards the star (unit vector), its disc's radius in radians, its color and its flares.
uniform vec3 sun_direction = vec3(0.3, 0.7, 0.5);
uniform float sun_radius = 0.01;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_energy = 4.0;
uniform float glare : hint_range(0.0, 1.0) = 0.0;

// A moon's planet: its direction, its radius in radians (0: none) and its color.
uniform vec3 planet_direction = vec3(0.0, 0.5, -0.8);
uniform float planet_radius = 0.0;
uniform vec3 planet_disc_color : source_color = vec3(0.6, 0.5, 0.4);
// The other planets as points: xyz their direction, w their brightness (0: none).
uniform vec4 points[8];

// The weather overhead.
uniform vec3 cloud_color : source_color = vec3(0.2, 0.19, 0.18);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.0;
// Where the clouds' pattern stands (drifts with the wind, moved by the script).
uniform vec2 cloud_offset = vec2(0.0);

// The storm: its side (a horizontal unit vector), how high its wall towers (0–1) and how much it
// covers the whole sky (0–1).
uniform vec3 storm_direction = vec3(1.0, 0.0, 0.0);
uniform vec3 storm_color : source_color = vec3(0.42, 0.27, 0.2);
uniform float storm_wall : hint_range(0.0, 1.0) = 0.0;
uniform float storm_cover : hint_range(0.0, 1.0) = 0.0;

// Space.
uniform float space : hint_range(0.0, 1.0) = 0.0;
uniform vec3 space_color : source_color = vec3(0.003, 0.004, 0.008);
uniform vec3 planet_color : source_color = vec3(0.3, 0.17, 0.1);
// Possible stars per side of each face of the cube around the viewer.
uniform float star_cells = 220.0;
// Share of the cells that hold a star.
uniform float star_chance : hint_range(0.0, 1.0) = 0.07;
uniform float star_energy = 5.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Gradient noise (smooth, round shapes at any threshold), about 0–1.
float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(vec2(cos(hash2(i) * 6.2832), sin(hash2(i) * 6.2832)), f);
	vec2 i_b = i + vec2(1.0, 0.0);
	float b = dot(vec2(cos(hash2(i_b) * 6.2832), sin(hash2(i_b) * 6.2832)), f - vec2(1.0, 0.0));
	vec2 i_c = i + vec2(0.0, 1.0);
	float c = dot(vec2(cos(hash2(i_c) * 6.2832), sin(hash2(i_c) * 6.2832)), f - vec2(0.0, 1.0));
	vec2 i_d = i + vec2(1.0, 1.0);
	float d = dot(vec2(cos(hash2(i_d) * 6.2832), sin(hash2(i_d) * 6.2832)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

float fbm(vec2 p) {
	// Each octave turned against the last, so the noise's grid doesn't show.
	const mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += gradient_noise(p) * amplitude;
		p = turn * p * 2.03 + vec2(1.7, 9.2);
		amplitude *= 0.5;
	}
	return sum / 0.9375;
}

// Brightness of the star (if any) seen in direction `dir`.
float stars(vec3 dir) {
	vec3 a = abs(dir);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) {
		uv = dir.yz / a.x;
		face = sign(dir.x);
	} else if (a.y >= a.z) {
		uv = dir.xz / a.y;
		face = 2.0 * sign(dir.y);
	} else {
		uv = dir.xy / a.z;
		face = 3.0 * sign(dir.z);
	}
	vec2 grid = uv * star_cells;
	vec2 cell = floor(grid);
	float chance = hash(vec3(cell, face));
	if (chance > star_chance) {
		return 0.0;
	}
	vec2 jitter = vec2(hash(vec3(cell, face + 7.0)), hash(vec3(cell, face + 13.0))) - 0.5;
	float distance_to_star = length(grid - (cell + 0.5 + jitter * 0.5));
	float size = mix(0.12, 0.32, chance / star_chance);
	return smoothstep(size, 0.0, distance_to_star) * mix(0.25, 1.0, hash(vec3(cell, face + 3.0)));
}

// The moon's planet over `color`: a lit sphere with faint bands.
vec3 planet_disc(vec3 dir, vec3 color) {
	float angle = acos(clamp(dot(dir, planet_direction), -1.0, 1.0));
	if (planet_radius <= 0.0 || angle > planet_radius * 1.15) {
		return color;
	}
	vec3 forward = planet_direction;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
	vec3 up = cross(forward, right);
	vec2 local = vec2(dot(dir, right), dot(dir, up)) / sin(planet_radius);
	float r2 = dot(local, local);
	float r = sqrt(r2);
	vec3 normal = normalize(local.x * right + local.y * up - sqrt(max(1.0 - r2, 0.0)) * forward);
	float lit = smoothstep(-0.15, 0.6, dot(normal, sun_direction));
	// A faint glow of atmosphere around the limb.
	float rim = (1.0 - smoothstep(0.97, 1.15, r)) * smoothstep(0.85, 1.0, r);
	if (r2 > 1.0) {
		return color + planet_disc_color * rim * lit * 0.12;
	}
	float bands = 0.85 + 0.15 * sin(local.y * 14.0 + fbm(local * 3.0) * 4.0);
	vec3 surface = planet_disc_color * bands * mix(0.03, 0.75, lit) + planet_disc_color * rim * lit * 0.12;
	float edge = 1.0 - smoothstep(0.985, 1.0, r);
	return mix(color, surface, edge);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	// The body's sky, its haze at the horizon.
	vec3 color = mix(horizon_color, zenith_color, smoothstep(0.0, 0.7, up));
	// The star's glow and disc.
	float to_sun = acos(clamp(dot(dir, sun_direction), -1.0, 1.0));
	float glow = exp(-to_sun / max(sun_radius * 6.0, 0.001)) * 0.35;
	glow += glare * exp(-to_sun * 5.0) * 0.06;
	if (!AT_CUBEMAP_PASS && glare > 0.0) {
		// Flares: a few uneven rays around the disc.
		vec3 side = normalize(cross(sun_direction, vec3(0.0, 1.0, 0.0)));
		vec3 above = cross(side, sun_direction);
		float around = atan(dot(dir, above), dot(dir, side));
		float rays = pow(abs(sin(around * 3.0 + 0.4)) * abs(sin(around * 5.0 + 1.3)), 6.0);
		glow += glare * rays * exp(-to_sun / max(sun_radius * 3.0, 0.001)) * 0.5;
	}
	float disc = smoothstep(sun_radius, sun_radius * 0.8, to_sun);
	vec3 sun = sun_color * (glow + disc) * sun_energy;
	color = planet_disc(dir, color);
	// The other planets.
	if (!AT_CUBEMAP_PASS) {
		for (int i = 0; i < 8; i++) {
			if (points[i].w > 0.0) {
				float d = 1.0 - dot(dir, normalize(points[i].xyz));
				color += vec3(0.9, 0.92, 1.0) * points[i].w * smoothstep(0.000004, 0.0, d);
			}
		}
	}
	// The weather overhead, drawn on a flat layer high up (it thins towards the horizon).
	float clouds = 0.0;
	if (cloud_cover > 0.0 && up > 0.0) {
		vec2 layer = dir.xz / (up + 0.3) * 2.2 + cloud_offset;
		float n = fbm(layer);
		clouds = smoothstep(0.85 - cloud_cover * 0.6, 1.15 - cloud_cover * 0.6, n);
		clouds = min(clouds + cloud_cover * 0.3, 1.0) * smoothstep(0.0, 0.3, up);
	}
	color = mix(color + sun * (1.0 - clouds * 0.9), cloud_color * (1.0 + glow * 2.0), clouds);
	// The haze over the horizon and below it.
	float haze = smoothstep(haze_reach, 0.0, up);
	color = mix(color, haze_color, haze);
	// The storm's wall on its side, rising with the warning; then it closes over everything. Its
	// billows: along the horizon for the wall, on a layer overhead for the cover.
	vec2 bearing = normalize(dir.xz + vec2(0.0001));
	float facing = dot(bearing, normalize(storm_direction.xz));
	float billow = fbm(bearing * 3.0 + vec2(0.0, max(up, 0.0) * 9.0) + cloud_offset * 0.3);
	float top = storm_wall * (0.12 + 0.6 * smoothstep(-0.2, 1.0, facing)) * (0.7 + billow * 0.6);
	float wall = smoothstep(top, top - 0.1, up) * smoothstep(-0.7, -0.1, facing);
	float overhead = fbm(dir.xz / (abs(up) + 0.3) * 1.6 + cloud_offset);
	float cover = smoothstep(0.0, 0.5, storm_cover * 1.4 + overhead * 0.6 - 0.5) * storm_cover;
	float storm = max(wall * min(storm_wall * 3.0, 1.0), cover);
	float shade = mix(billow, overhead, smoothstep(0.05, 0.4, up));
	// At the horizon the storm's color is the haze's (the far land fades into it), darker above.
	vec3 storm_shade = storm_color * mix(1.0, mix(0.5, 0.95, shade), smoothstep(0.0, 0.25, up));
	color = mix(color, storm_shade, storm);
	// Space.
	vec3 dark = space_color;
	// The planet below: its lit limb glows faintly towards straight down.
	dark += planet_color * 0.2 * smoothstep(-0.1, 1.0, -up);
	if (!AT_CUBEMAP_PASS && space > 0.0) {
		dark += vec3(0.8, 0.9, 1.0) * star_energy * stars(dir);
	}
	COLOR = mix(color, dark, space);
}
