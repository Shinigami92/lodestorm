// A miner being projected onto its node (see MinerHologram), as an overlay on its parts: above
// `build_line` (world Y, per instance) a see-through hologram in the miners' bay's ghost color,
// brighter at the edges, with scan lines drifting upwards and a bright line along the build line;
// below it nothing (the real miner shows there). `energy` (per instance) dims it while the build
// waits for its player.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

instance uniform float build_line = -100000.0;
instance uniform float energy = 1.0;

uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
// Distance between scan lines in m.
uniform float line_spacing = 0.06;
uniform float scroll_speed = 0.15;
// Height of the bright line on top of what's built, in m.
uniform float edge_height = 0.04;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float above = world_y - build_line;
	if (above < 0.0) {
		discard;
	}
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float scan = step(0.5, fract((world_y - TIME * scroll_speed) / line_spacing));
	float flicker = 0.95 + 0.05 * sin(TIME * 23.0);
	float alpha = energy * flicker * (0.2 + 0.6 * rim * rim) * (0.6 + 0.4 * scan);
	float edge = 1.0 - smoothstep(0.0, edge_height, above);
	ALBEDO = color.rgb;
	ALPHA = clamp(max(alpha, edge * max(energy, 0.5)), 0.0, 1.0);
}
