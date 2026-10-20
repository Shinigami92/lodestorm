// Mantle's field (ShieldField): a curved pane of warm light in front of its holder. UV.x runs across
// the arc, UV.y from the ground up. Faint in the middle, brighter at its edges and top, with bands
// drifting up; dimmer as its charge runs down; a ring spreads from each of the latest hits.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.86, 0.66, 1.0);
// Its charge's share: the field dims as it runs down.
uniform float strength = 1.0;
// A block's flash over the whole pane, fading.
uniform float flare = 0.0;
// The pane's size in m: across the arc, and its height.
uniform vec2 size = vec2(2.3, 2.2);
// The latest hits: where on the pane (m), seconds since, and how hard (0 to 1). Unused: z < 0.
uniform vec4 hits[4];
// Seconds a hit's ring spreads, and how fast (m/s).
const float RING_TIME = 0.6;
const float RING_SPEED = 3.0;

void fragment() {
	vec2 p = UV * size;
	float edge = max(smoothstep(0.05, 0.0, UV.x), smoothstep(0.95, 1.0, UV.x));
	float top = smoothstep(0.93, 1.0, UV.y);
	float bands = 0.5 + 0.5 * sin((p.y - TIME * 0.5) * 8.0);
	float glow = 0.012 + 0.45 * edge + 0.4 * top + 0.02 * bands * bands;
	for (int i = 0; i < 4; i++) {
		vec4 hit = hits[i];
		if (hit.z < 0.0 || hit.z > RING_TIME) {
			continue;
		}
		float fade = 1.0 - hit.z / RING_TIME;
		float d = distance(p, hit.xy);
		float ring = smoothstep(0.14, 0.0, abs(d - hit.z * RING_SPEED));
		float core = smoothstep(0.5, 0.0, d);
		glow += (ring * 1.2 + core * 0.8) * fade * hit.w;
	}
	float ground = smoothstep(0.0, 0.12, UV.y);
	ALBEDO = color.rgb;
	ALPHA = clamp(glow * mix(0.3, 1.0, strength) + flare * 0.15, 0.0, 1.0) * ground;
}
