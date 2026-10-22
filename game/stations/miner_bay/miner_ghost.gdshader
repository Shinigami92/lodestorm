// A crafted miner's outline in its cradle: see-through, filling from the bottom while it's built
// (below `fill_top`, in world Y, it's denser, with a bright line at the top of the fill), faint
// when the cradle is empty.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float empty_alpha = 0.04;
uniform float filled_alpha = 0.6;
// World Y up to which it's built (far below: nothing yet).
uniform float fill_top = -1000.0;
uniform float line_width = 0.015;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// Edges facing away from the camera read stronger, like an outline.
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float alpha = world_y <= fill_top ? filled_alpha : empty_alpha;
	ALBEDO = color.rgb;
	ALPHA = clamp(alpha * (0.6 + rim), 0.0, 1.0);
	if (abs(world_y - fill_top) < line_width) {
		ALPHA = 0.9;
	}
}
