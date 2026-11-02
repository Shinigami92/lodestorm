// The Ash fields' lava (LocationBiome.gap_fill): a flat surface in the lava channels, drawn without
// textures. Dark plates of cooling crust drift slowly on it, the glowing melt shows in the cracks
// between them and along their edges; the crust's middle stays warm in places, and the whole field
// breathes slowly. World space, so neighboring channels match.
shader_type spatial;
render_mode cull_back;

// Size of the crust plates, in m.
uniform float plate_size = 2.4;
// Width of the glowing cracks between the plates, in plate sizes.
uniform float crack_width : hint_range(0.0, 0.5) = 0.07;
// How far the crust drifts per s, in m (direction in the XZ plane).
uniform vec2 drift = vec2(0.05, 0.02);
uniform vec3 melt_color : source_color = vec3(1.0, 0.42, 0.08);
uniform vec3 hot_color : source_color = vec3(1.0, 0.78, 0.35);
uniform vec3 crust_color : source_color = vec3(0.06, 0.045, 0.04);
// Emission of the melt (the crust's warm glow is a share of it).
uniform float melt_energy = 1.6;
uniform float crust_glow : hint_range(0.0, 1.0) = 0.12;
// How much of the surface is open melt instead of crust, 0..1.
uniform float open_melt : hint_range(0.0, 1.0) = 0.1;

varying vec3 world_pos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Distance to the nearest cell border (F2 - F1, about) and the nearest cell's id.
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d2 - d1, id);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz - drift * TIME;
	vec2 warp = vec2(value_noise(p * 0.35), value_noise(p * 0.35 + 17.3)) - 0.5;
	vec3 c = cells((p + warp * 2.0) / plate_size);
	float plate_rand = hash2(c.yz + 3.1).x;
	// Open melt: some plates melted away, the cracks wider where the field is hotter.
	float heat = value_noise(p * 0.12 + vec2(TIME * 0.03, 0.0));
	float open = step(plate_rand, open_melt * (0.5 + heat));
	float width = crack_width * (0.6 + heat);
	float crack = 1.0 - smoothstep(width * 0.4, width, c.x);
	float edge = 1.0 - smoothstep(width, width * 3.0, c.x);
	float melt = max(open, crack);
	float breathe = 0.85 + 0.15 * sin(TIME * 0.7 + heat * 6.0);
	vec3 glow = mix(melt_color, hot_color, crack * heat) * breathe;
	float crust_heat = crust_glow * (edge * 0.6 + heat * 0.4) * (0.6 + 0.4 * value_noise(p * 2.3));
	ALBEDO = mix(crust_color * (0.8 + 0.4 * plate_rand), melt_color * 0.3, melt);
	ROUGHNESS = mix(0.92, 0.55, melt);
	EMISSION = glow * melt_energy * max(melt, crust_heat);
}
