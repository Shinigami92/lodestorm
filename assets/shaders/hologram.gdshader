// Glowing, see-through hologram: brighter at the edges, with scan lines drifting upwards.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float energy = 0.9;
// Distance between scan lines in m (world space, so they stay even at any scale).
uniform float line_spacing = 0.03;
uniform float scroll_speed = 0.02;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float line = step(0.5, fract((world_y - TIME * scroll_speed) / line_spacing));
	float flicker = 0.95 + 0.05 * sin(TIME * 23.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(energy * flicker * (0.3 + 0.7 * rim * rim) * (0.6 + 0.4 * line), 0.0, 1.0);
}
