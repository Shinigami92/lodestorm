// A miner's ring on the ground around it (on a PlaneMesh, see MinerRing): the health arc on the
// screen's left and the tank's fill arc on its right (both filling from the bottom up, the empty
// part dark with an outline in the arc's color), a thin band inside them going around clockwise
// from the top with the progress of placing or picking it up, and a thin dashed circle at its hose
// range (`range_solid` fills the gaps). Lines keep `min_line` pixels on screen. Pulled
// `depth_bias` m towards the camera, so the ground, grass and low plants don't hide it, but cliffs
// and props do.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, skip_vertex_transform;

#include "res://assets/shaders/ground_marking.gdshaderinc"
#include "res://assets/shaders/ring_bands.gdshaderinc"

// Half the plane's size, in m.
uniform float radius = 5.2;
uniform float depth_bias = 1.0;
uniform float min_line = 2.0;
// Shares of the circle left open at the top (where the miner stands from the camera's view) and
// at the bottom, between the two arcs.
uniform float top_gap = 0.09;
uniform float bottom_gap = 0.02;
// Inner and outer radius of each band, in m.
uniform vec2 arc_band = vec2(1.75, 1.95);
uniform vec2 progress_band = vec2(1.6, 1.67);
// Dark, so the ring reads on light ground too.
uniform vec4 track_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);

uniform float health_fill = 1.0;
uniform vec4 health_color : source_color = vec4(0.3, 1.0, 0.45, 0.9);
uniform float tank_fill = 0.0;
uniform vec4 tank_color : source_color = vec4(0.3, 0.85, 1.0, 0.9);

uniform float progress_alpha = 0.0;
uniform float progress = 0.0;
uniform vec4 progress_color : source_color = vec4(0.3, 0.85, 1.0, 0.9);

uniform float range_radius = 5.0;
uniform float range_width = 0.05;
uniform int range_dashes = 48;
// 0: dashed, 1: solid.
uniform float range_solid = 0.0;
uniform vec4 range_color : source_color = vec4(0.6, 0.85, 1.0, 0.5);

void vertex() {
	VERTEX = ground_marking_view(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, depth_bias);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// An arc's color at `t` (0 at its bottom, 1 at its top): `fill` lit, the rest dark with an outline.
vec4 arc_color(float t, float fill, vec4 color, float edge, float along_m, float fw) {
	float filled = clamp(0.5 - (t - fill) * along_m / fw, 0.0, 1.0);
	vec4 c = mix(track_color, color, filled);
	return over(c, vec4(color.rgb, color.a * 0.6 * edge * (1.0 - filled)));
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * radius;
	float r = length(p);
	float fw = max(fwidth(r), 0.0001);
	// 0 at the top (UV.y = 0 is -Z, away from the camera), growing clockwise seen from above.
	float s = fract(atan(p.x, -p.y) / TAU + 1.0);
	float arc_span = 0.5 - top_gap - bottom_gap;
	vec4 color = vec4(0.0);
	float edge;

	float in_arc = band(r, arc_band, fw, min_line, edge);
	if (in_arc > 0.0) {
		float along_m = arc_span * TAU * r;
		float in_left = span(s, 0.5 + bottom_gap, 1.0 - top_gap, r, fw);
		if (in_left > 0.0) {
			float t = (s - 0.5 - bottom_gap) / arc_span;
			vec4 c = arc_color(t, health_fill, health_color, edge, along_m, fw);
			c.a *= in_arc * in_left;
			color = over(color, c);
		}
		float in_right = span(s, top_gap, 0.5 - bottom_gap, r, fw);
		if (in_right > 0.0) {
			float t = (0.5 - bottom_gap - s) / arc_span;
			vec4 c = arc_color(t, tank_fill, tank_color, edge, along_m, fw);
			c.a *= in_arc * in_right;
			color = over(color, c);
		}
	}

	float in_progress = band(r, progress_band, fw, min_line, edge) * progress_alpha;
	if (in_progress > 0.0) {
		float done = clamp(0.5 - (s - progress) * TAU * r / fw, 0.0, 1.0);
		vec4 c = mix(track_color, progress_color, done);
		c.a *= in_progress;
		color = over(color, c);
	}

	float in_range = band(r, vec2(range_radius - range_width, range_radius), fw, min_line, edge);
	if (in_range > 0.0) {
		float n = float(range_dashes);
		// Half of each dash's share lit (around its middle), the gaps filled by `range_solid`.
		float half_dash = 0.25 / n * TAU * r;
		float to_middle = abs(fract(s * n) - 0.5) / n * TAU * r;
		float dash = 1.0 - smoothstep(half_dash - fw, half_dash, to_middle);
		vec4 c = range_color;
		c.a *= in_range * max(dash, range_solid);
		color = over(color, c);
	}

	if (color.a <= 0.002) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
