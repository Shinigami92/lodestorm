// The Salt pans' brine (LocationBiome.gap_fill) at the bottom of the sinkholes and beside the
// causeways: a flat surface drawn without textures. Dark, still and glossy, with slow ripples
// breaking up the reflections and pale rafts of salt crust floating on it. World space.
shader_type spatial;
render_mode cull_back;

uniform vec3 brine_color : source_color = vec3(0.05, 0.085, 0.09);
uniform vec3 crust_color : source_color = vec3(0.55, 0.56, 0.54);
// Size of the ripples, in m, and how fast they move, in m per s.
uniform float ripple_size = 2.5;
uniform float ripple_speed = 0.08;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.25;
// Share of the surface under floating salt rafts, and their size in m.
uniform float crust_share : hint_range(0.0, 1.0) = 0.12;
uniform float crust_size = 3.0;

varying vec3 world_pos;

#include "res://assets/shaders/noise.gdshaderinc"

float ripples(vec2 p) {
	float t = TIME * ripple_speed;
	return value_noise(p / ripple_size + vec2(t, t * 0.6))
		+ 0.5 * value_noise(p / (ripple_size * 0.43) - vec2(t * 0.8, -t));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float e = 0.05;
	float h = ripples(p);
	vec2 slope = vec2(ripples(p + vec2(e, 0.0)) - h, ripples(p + vec2(0.0, e)) - h) / e;
	float raft_field = value_noise(p / crust_size) * 0.7 + value_noise(p / (crust_size * 0.3)) * 0.3;
	float raft = smoothstep(1.0 - crust_share - 0.03, 1.0 - crust_share + 0.03, raft_field);
	ALBEDO = mix(brine_color, crust_color, raft);
	ROUGHNESS = mix(0.06, 0.85, raft);
	SPECULAR = 0.5;
	vec3 n = normalize(vec3(-slope.x * ripple_strength * (1.0 - raft), 1.0, -slope.y * ripple_strength * (1.0 - raft)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
