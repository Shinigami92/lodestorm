// A body's silhouette where something stands between it and the camera (a cliff, a tree, a wall):
// only drawn where the depth test fails, as a flat, see-through color with brighter edges.
// Skips pixels where the body itself is visible (its material writes stencil 1, see
// Player._ready), so parts of the body hidden behind its other parts don't show.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_inverted, cull_back, shadows_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(0.95, 0.55, 0.15, 0.7);

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.6 + 0.4 * rim);
}
