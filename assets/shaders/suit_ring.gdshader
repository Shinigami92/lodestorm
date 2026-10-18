// The suit ring on the ground around the player (on a PlaneMesh, see SuitRing): the health arc on
// the screen's left, the ammo arc on its right (both filling from the bottom up), the spare
// magazine ticks inside the ammo arc, the dash's thin inner ring, the green outer band while
// handing over ammo, short red marks on the outer edge where hits came from, and the pointers'
// arrows beyond them. A dimmed arc shows as a faint outline. A teammate's ring shows only the
// health arc inside an outline in their color. Lines keep `min_line` pixels on screen. Pulled
// `depth_bias` m towards the camera, so the ground, grass and low plants don't hide it, but
// cliffs and props do.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, skip_vertex_transform;

#include "res://assets/shaders/ground_marking.gdshaderinc"

// Half the plane's size, in m.
uniform float radius = 1.62;
uniform float depth_bias = 1.0;
uniform float min_line = 2.0;
// Shares of the circle left open at the top (where the body stands from the camera's view) and at
// the bottom, between the two arcs.
uniform float top_gap = 0.045;
uniform float bottom_gap = 0.02;
// Inner and outer radius of each band, in m.
uniform vec2 arc_band = vec2(1.16, 1.36);
uniform vec2 spare_band = vec2(1.03, 1.11);
uniform vec2 dash_band = vec2(0.92, 0.96);
uniform vec2 give_band = vec2(1.42, 1.5);
uniform vec2 hit_band = vec2(1.42, 1.6);
uniform vec2 team_band = vec2(1.39, 1.43);
// Dark, so the ring reads on light ground too.
uniform vec4 track_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
// How much of a dimmed arc's outline shows (0 aboard, where the ring stays quiet).
uniform float outline_alpha = 1.0;

uniform float health_fill = 1.0;
uniform vec4 health_color : source_color = vec4(0.3, 1.0, 0.45, 0.9);
// 0: dimmed to the outline, 1: lit.
uniform float health_glow = 1.0;

uniform float ammo_alpha = 0.0;
uniform float ammo_fill = 1.0;
uniform vec4 ammo_color : source_color = vec4(0.02, 0.7, 1.0, 0.9);
uniform float ammo_glow = 1.0;
// Rounds as segments (0: one continuous bar).
uniform int ammo_segments = 0;
// The reload's timing window along the arc (x > y: none).
uniform vec2 ammo_window = vec2(1.0, 0.0);
uniform vec4 window_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 window_ahead_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
// The segment of the round being loaded (-1: none), in its own color.
uniform int loading_segment = -1;
uniform vec4 loading_color : source_color = vec4(1.0);

uniform float spare_alpha = 0.0;
uniform int spare_slots = 0;
// Spare magazines left (a fraction: a partly used one).
uniform float spare_fill = 0.0;
uniform vec4 spare_color : source_color = vec4(0.02, 0.7, 1.0, 0.9);

uniform float dash_alpha = 0.0;
uniform float dash_fill = 1.0;
uniform vec4 dash_color : source_color = vec4(1.0, 0.93, 0.8, 0.9);

uniform float give_alpha = 0.0;
uniform float give_fill = 0.0;
uniform vec4 give_color : source_color = vec4(0.35, 1.0, 0.45, 0.9);

uniform vec4 hit_color : source_color = vec4(1.0, 0.12, 0.08, 1.0);
// Share of the circle (where the hit came from) and strength of each mark.
uniform vec2 hits[4];

// Where the pointers' arrows start (m from the center).
uniform float pointer_base = 1.68;
// Per pointer: share of the circle it points to, alpha (0: none), its tip's radius and half its
// width at the base (m).
uniform vec4 pointers[3];
uniform vec4 pointer_colors[3] : source_color;
// Dark rim around the arrows, so they read on light ground (m).
uniform float pointer_rim = 0.05;

// A teammate's outline in their player color (0: the local player's ring, none).
uniform float team_alpha = 0.0;
uniform vec4 team_color : source_color = vec4(1.0);

void vertex() {
	VERTEX = ground_marking_view(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, depth_bias);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Coverage of the band `b` at radius `r`, at least `min_line` pixels wide; `edge` is 1 on its
// outline.
float band(float r, vec2 b, float fw, out float edge) {
	float center = (b.x + b.y) * 0.5;
	float half_width = max((b.y - b.x) * 0.5, min_line * fw * 0.5);
	float d = abs(r - center);
	edge = smoothstep(half_width - 2.5 * fw, half_width - fw, d);
	return 1.0 - smoothstep(half_width - fw, half_width, d);
}

// Coverage of a share range [from, to] of the circle at radius `r` (anti-aliased in m).
float span(float s, float from, float to, float r, float fw) {
	float d = max(from - s, s - to) * TAU * r;
	return clamp(0.5 - d / fw, 0.0, 1.0);
}

// Signed distance (m, negative inside) from `p` to an arrow pointing to `share` from `base` to
// `tip`, `half_width` wide at its notched back.
float arrow_distance(vec2 p, float share, float base, float tip, float half_width) {
	float angle = share * TAU;
	vec2 dir = vec2(sin(angle), -cos(angle));
	float along = dot(p, dir);
	float across = abs(dot(p, vec2(-dir.y, dir.x)));
	float length_m = tip - base;
	float slope = half_width / length_m;
	float to_side = (across - (tip - along) * slope) / sqrt(1.0 + slope * slope);
	float to_back = base + 0.3 * length_m * (1.0 - across / half_width) - along;
	return max(to_side, to_back);
}

vec4 over(vec4 below, vec4 above) {
	float a = above.a + below.a * (1.0 - above.a);
	vec3 rgb = (above.rgb * above.a + below.rgb * below.a * (1.0 - above.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

// An arc's color at `t` (0 at its bottom, 1 at its top): `fill` lit, the rest dark, all of it
// dimmed to the outline by `glow`.
vec4 arc_color(float t, float fill, vec4 color, float glow, float edge, float along_m, float fw) {
	float filled = clamp(0.5 - (t - fill) * along_m / fw, 0.0, 1.0);
	vec4 lit = mix(track_color, color, filled);
	// The filled share stays readable when dimmed.
	vec4 dim = vec4(color.rgb, mix(mix(0.04, 0.3, edge), mix(0.22, 0.5, edge), filled) * outline_alpha);
	return mix(dim, lit, glow);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * radius;
	float r = length(p);
	float fw = max(fwidth(r), 0.0001);
	// 0 at the top (UV.y = 0 is -Z, away from the camera), growing clockwise seen from above.
	float s = fract(atan(p.x, -p.y) / TAU + 1.0);
	float arc_span = 0.5 - top_gap - bottom_gap;
	float right_t = (0.5 - bottom_gap - s) / arc_span;
	float left_t = (s - 0.5 - bottom_gap) / arc_span;
	vec4 color = vec4(0.0);
	float edge;

	float in_arc = band(r, arc_band, fw, edge);
	if (in_arc > 0.0) {
		float along_m = arc_span * TAU * r;
		float in_left = span(s, 0.5 + bottom_gap, 1.0 - top_gap, r, fw);
		if (in_left > 0.0) {
			vec4 c = arc_color(left_t, health_fill, health_color, health_glow, edge, along_m, fw);
			c.a *= in_arc * in_left;
			color = over(color, c);
		}
		float in_right = span(s, top_gap, 0.5 - bottom_gap, r, fw) * ammo_alpha;
		if (in_right > 0.0) {
			vec4 fill = ammo_color;
			// -1: the bar up to `ammo_fill`, 0: dark here, 1: lit here.
			float forced = -1.0;
			if (ammo_segments > 0) {
				float n = float(ammo_segments);
				float index = floor(right_t * n);
				// Gaps between the rounds.
				float to_gap = abs(fract(right_t * n + 0.5) - 0.5) / n * along_m;
				in_right *= smoothstep(0.02, 0.02 + fw, to_gap);
				forced = (index + 0.5) / n <= ammo_fill ? 1.0 : 0.0;
				if (int(index) == loading_segment) {
					fill = loading_color;
					forced = 1.0;
				}
			} else if (right_t >= ammo_window.x && right_t <= ammo_window.y) {
				fill = right_t <= ammo_fill ? window_color : window_ahead_color;
				forced = 1.0;
			}
			float t = forced < 0.0 ? right_t : 1.0 - forced;
			float bar = forced < 0.0 ? ammo_fill : forced;
			vec4 c = arc_color(t, bar, fill, ammo_glow, edge, along_m, fw);
			c.a *= in_arc * in_right;
			color = over(color, c);
		}
	}

	float in_spares = band(r, spare_band, fw, edge) * spare_alpha;
	if (in_spares > 0.0 && spare_slots > 0) {
		float step_share = min(0.034, arc_span / float(spare_slots));
		float from_bottom = (0.5 - bottom_gap - s) / step_share;
		float index = floor(from_bottom);
		if (index >= 0.0 && index < float(spare_slots)) {
			float to_gap = abs(fract(from_bottom) - 0.5) * step_share * TAU * r;
			float tick = 1.0 - smoothstep(step_share * 0.36 * TAU * r - fw, step_share * 0.36 * TAU * r, to_gap);
			float fill = clamp(spare_fill - index, 0.0, 1.0);
			vec4 c = mix(vec4(spare_color.rgb, mix(0.15, 0.5, edge)), spare_color, fill);
			c.a *= in_spares * tick;
			color = over(color, c);
		}
	}

	float in_dash = band(r, dash_band, fw, edge) * dash_alpha;
	if (in_dash > 0.0) {
		vec4 c = s <= dash_fill ? dash_color : track_color;
		c.a *= in_dash;
		color = over(color, c);
	}

	float in_give = band(r, give_band, fw, edge) * give_alpha;
	if (in_give > 0.0) {
		vec4 c = s <= give_fill ? give_color : track_color;
		c.a *= in_give;
		color = over(color, c);
	}

	float in_hits = band(r, hit_band, fw, edge);
	if (in_hits > 0.0) {
		// Narrower outwards, so a mark reads as pointing out.
		float outward = clamp((r - hit_band.x) / (hit_band.y - hit_band.x), 0.0, 1.0);
		float width = mix(0.04, 0.015, outward);
		for (int i = 0; i < 4; i++) {
			float strength = hits[i].y;
			if (strength <= 0.0) {
				continue;
			}
			float d = abs(fract(s - hits[i].x + 0.5) - 0.5);
			float mark = clamp(0.5 - (d - width) * TAU * r / fw, 0.0, 1.0);
			vec4 c = hit_color;
			c.a *= in_hits * mark * strength;
			color = over(color, c);
		}
	}

	float in_team = band(r, team_band, fw, edge) * team_alpha;
	if (in_team > 0.0) {
		vec4 c = team_color;
		c.a *= in_team;
		color = over(color, c);
	}

	if (r > pointer_base - pointer_rim - fw) {
		for (int i = 0; i < 3; i++) {
			vec4 pointer = pointers[i];
			if (pointer.y <= 0.0) {
				continue;
			}
			float d = arrow_distance(p, pointer.x, pointer_base, pointer.z, pointer.w);
			// At least `min_line` pixels of rim too.
			float rim = max(pointer_rim, min_line * fw);
			float dark = clamp(0.5 - (d - rim) / fw, 0.0, 1.0);
			float lit = clamp(0.5 - d / fw, 0.0, 1.0);
			vec4 c = pointer_colors[i];
			vec4 shade = vec4(track_color.rgb, track_color.a * c.a * dark);
			color = over(color, shade);
			c.a *= lit * pointer.y;
			color = over(color, c);
		}
	}

	if (color.a <= 0.002) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
