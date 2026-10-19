// A stalker's see-through body (AlienCloaking): what's behind it, bent along its surface, with a
// faint edge in the hive's yellow-green. `shimmer` fades the bending in (0: not there at all),
// `shown` fades its own colors in (1: as if it had no cloak). It marks where it's visible in the
// stencil buffer like the other bodies (see OccludedSilhouette), so only cliffs and props in front
// of it show its silhouette.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
stencil_mode write, compare_always, 1;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec3 edge_color : source_color = vec3(0.9, 1.0, 0.2);
// How far the shimmer bends what's behind it (a share of the screen).
uniform float bend = 0.035;
uniform float edge_strength = 0.15;
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float shown : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec2 bent = SCREEN_UV + NORMAL.xy * bend * (0.4 + edge);
	vec3 behind = textureLod(screen_texture, bent, 0.0).rgb;
	ALBEDO = texture(albedo_texture, UV).rgb * shown;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5 * shown;
	EMISSION = (behind + edge_color * edge * edge_strength) * (1.0 - shown);
	ALPHA = max(shimmer, shown);
}
