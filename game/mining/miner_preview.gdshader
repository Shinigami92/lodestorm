// A miner a player is about to place (see MinerPreview), on every part: fainter than the hologram
// of one being placed (miner_hologram.gdshader), slowly breathing, without scan lines, in `tint`
// (per instance: how its drill fits the ore); `fade` (per instance) fades it in and out.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(0.3, 0.85, 1.0, 1.0);
instance uniform float fade = 1.0;

// Seconds of one breath, and how far it dims.
uniform float breath_time = 2.6;
uniform float breath_depth = 0.35;

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float breath = 1.0 - breath_depth * (0.5 + 0.5 * sin(TIME * TAU / breath_time));
	ALBEDO = tint.rgb;
	ALPHA = clamp(fade * breath * (0.06 + 0.4 * rim * rim), 0.0, 1.0);
}
