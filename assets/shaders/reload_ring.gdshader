// A ring on the ground (on a PlaneMesh) that fills clockwise from the top of the screen: a reload's
// progress with its timing window (see ReloadRing). Drawn on top, like the arrow to the ship.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

// Shares of the circle.
uniform float progress = 0.0;
uniform float window_start = -1.0;
uniform float window_end = -1.0;
uniform vec4 fill_color : source_color = vec4(0.02, 0.7, 1.0, 0.9);
uniform vec4 window_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Dark, so the ring reads on light ground too.
uniform vec4 track_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
// The window before the bar reaches it.
uniform vec4 window_ahead_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
// Inner edge, as a share of the outer radius.
uniform float inner_radius = 0.86;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = fwidth(r);
	float band = smoothstep(inner_radius - edge, inner_radius, r) * (1.0 - smoothstep(1.0 - edge, 1.0, r));
	if (band <= 0.0) {
		discard;
	}
	// 0 at the top (UV.y = 0 is -Z, away from the camera), growing clockwise seen from above.
	float share = fract(atan(p.x, -p.y) / TAU + 1.0);
	bool in_window = share >= window_start && share <= window_end;
	vec4 color = in_window ? window_ahead_color : track_color;
	if (share <= progress) {
		color = in_window ? window_color : fill_color;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * band;
}
