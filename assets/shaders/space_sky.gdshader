shader_type sky;
// The sky around the ship: a planet's (a flat color, set by the weather) or space, blended by
// `space`. Space is black with stars in every direction and the planet's glow far below.

uniform vec3 atmosphere_color : source_color = vec3(0.1, 0.095, 0.1);
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

void sky() {
	vec3 color = space_color;
	// The planet below: its lit limb glows faintly towards straight down.
	color += planet_color * 0.2 * smoothstep(-0.1, 1.0, -EYEDIR.y);
	if (!AT_CUBEMAP_PASS && space > 0.0) {
		color += vec3(0.8, 0.9, 1.0) * star_energy * stars(EYEDIR);
	}
	COLOR = mix(atmosphere_color, color, space);
}
