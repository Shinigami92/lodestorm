// The target lock (TargetMarker): four corner brackets on the ground around the locked-on alien,
// in the player's color with a dark rim, on a PlaneMesh. Lines keep `min_line` pixels on screen.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, skip_vertex_transform;

#include "res://assets/shaders/ground_marking.gdshaderinc"

// Half the plane's size, in m.
uniform float extent = 1.2;
// Half the square the brackets frame, each bracket's arm length and line width (m).
uniform float half_size = 0.9;
uniform float arm = 0.32;
uniform float line_width = 0.08;
uniform float min_line = 2.0;
uniform float depth_bias = 1.0;
uniform float rim = 0.04;
uniform vec4 color : source_color = vec4(0.95, 0.55, 0.15, 0.95);
uniform vec4 rim_color : source_color = vec4(0.0, 0.0, 0.0, 0.45);

void vertex() {
	VERTEX = ground_marking_view(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, depth_bias);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float box_distance(vec2 p, vec2 center, vec2 half_extent) {
	vec2 d = abs(p - center) - half_extent;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * extent;
	float fw = max(fwidth(p.x), 0.0001);
	float w = max(line_width, min_line * fw) * 0.5;
	// All four corners are the same, mirrored.
	vec2 q = abs(p);
	float d = min(
		box_distance(q, vec2(half_size - arm * 0.5 + w, half_size), vec2(arm * 0.5, w)),
		box_distance(q, vec2(half_size, half_size - arm * 0.5 + w), vec2(w, arm * 0.5))
	);
	float lit = clamp(0.5 - d / fw, 0.0, 1.0);
	float dark = clamp(0.5 - (d - max(rim, min_line * fw)) / fw, 0.0, 1.0);
	float a = color.a * lit + rim_color.a * dark * (1.0 - lit);
	if (a <= 0.002) {
		discard;
	}
	ALBEDO = mix(rim_color.rgb, color.rgb, color.a * lit / max(a, 0.0001));
	ALPHA = a;
}
