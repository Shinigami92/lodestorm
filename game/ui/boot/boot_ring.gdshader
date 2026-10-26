// The boot screen's ring around the emblem: a faint track and an arc filling clockwise from the
// top with `progress`. Radii are shares of the quad's half size.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 color : source_color = vec4(0.45, 1.0, 1.0, 1.0);
// Above 1, so the glow picks it up.
uniform float energy = 1.6;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float inner = 0.93;
uniform float outer = 0.97;
uniform float track_alpha = 0.07;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r);
	float band = smoothstep(inner - aa, inner, r) * (1.0 - smoothstep(outer, outer + aa, r));
	// 0 at the top, growing clockwise (UV's y points down).
	float turn = fract(atan(p.x, -p.y) / TAU);
	ALBEDO = color.rgb * energy;
	ALPHA = band * (turn <= progress ? 1.0 : track_alpha);
}
