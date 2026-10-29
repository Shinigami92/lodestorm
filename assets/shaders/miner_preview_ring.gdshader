// The ring under a miner a player is about to place (on a PlaneMesh, see MinerPreview): a thin
// circle in the preview's color, lit clockwise from the top (the screen's) up to a tick at `share`
// (how long it would take to fill, the full circle `MinerPreview.DIAL_TIME`), dim beyond it. Lines
// keep `min_line` pixels on screen; pulled `depth_bias` m towards the camera like the miners' rings.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, skip_vertex_transform;

#include "res://assets/shaders/ground_marking.gdshaderinc"
#include "res://assets/shaders/ring_bands.gdshaderinc"

// Half the plane's size, in m.
uniform float radius = 2.2;
uniform float depth_bias = 1.0;
uniform float min_line = 2.0;
// Inner and outer radius of the circle, and how far the tick reaches, in m.
uniform vec2 circle_band = vec2(1.8, 1.86);
uniform vec2 tick_band = vec2(1.68, 2.0);
// The tick's width, in m.
uniform float tick_width = 0.06;
// Brightness of the circle beyond the tick.
uniform float dim = 0.2;

uniform float share = 0.5;
uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 0.8);
uniform float fade = 1.0;

void vertex() {
	VERTEX = ground_marking_view(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, depth_bias);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * radius;
	float r = length(p);
	float fw = max(fwidth(r), 0.0001);
	// 0 at the top (UV.y = 0 is -Z, away from the camera), growing clockwise seen from above.
	float s = fract(atan(p.x, -p.y) / TAU + 1.0);
	float edge;

	float in_circle = band(r, circle_band, fw, min_line, edge);
	float lit = span(s, 0.0, share, r, fw);
	vec4 c = vec4(color.rgb, color.a * in_circle * mix(dim, 1.0, lit));

	// The tick: a short line across the circle, pointing out from its middle at `share`.
	float angle = share * TAU;
	vec2 towards = vec2(sin(angle), -cos(angle));
	float across = abs(towards.x * p.y - towards.y * p.x);
	float half_width = max(tick_width * 0.5, min_line * fw * 0.5);
	float in_tick = (1.0 - smoothstep(half_width - fw, half_width, across))
			* step(0.0, dot(p, towards)) * band(r, tick_band, fw, min_line, edge);
	c = over(c, vec4(color.rgb, color.a * in_tick));

	c.a *= fade;
	if (c.a <= 0.002) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
