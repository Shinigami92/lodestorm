// A tender's link (MendLinks): a glowing strand with pulses running from the tender to the alien it
// mends. UV.y runs along the strand, `strand_length` (m) sets how many pulses fit.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.9, 1.0, 0.2, 1.0);
// Pulses per m and how fast they run (m/s).
uniform float pulses_per_meter = 0.8;
uniform float pulse_speed = 3.0;
instance uniform float strand_length = 1.0;
// 0 while the tender is staggered: the strand dims.
instance uniform float strength = 1.0;

void fragment() {
	float along = UV.y * strand_length;
	float wave = 0.5 + 0.5 * sin((along + TIME * pulse_speed) * pulses_per_meter * 6.2831853);
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.25 + 0.75 * wave * wave) * mix(0.25, 1.0, strength);
}
