// The land beyond a generated location's rim (`LocationFarRing`): the biome's ground and rock
// textures, one sample each (ground from above, rock from the side), blended by the slope and the
// vertex color's height (R, rock lighter like the map's); no close-up blending, it's only seen far
// off and through the haze.
shader_type spatial;
render_mode cull_back;

uniform sampler2D ground_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float ground_tile = 6.0;
uniform float rock_tile = 8.0;
uniform vec3 ground_tint : source_color = vec3(1.0);
uniform vec3 rock_tint : source_color = vec3(1.0);
// The map's tint on its low ground (`LocationBiome.low_ground_tint`), lighter higher up.
uniform vec3 low_tint : source_color = vec3(0.9);
// Far off the textures are drawn larger, so their tiling doesn't show.
uniform float far_scale = 4.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 ground = texture(ground_albedo, world_position.xz / (ground_tile * far_scale)).rgb;
	vec2 side_uv = abs(world_normal.x) > abs(world_normal.z) ? world_position.zy : world_position.xy;
	vec3 rock = texture(rock_albedo, side_uv / (rock_tile * far_scale) * vec2(1.0, -1.0)).rgb;
	float steep = smoothstep(0.85, 0.6, world_normal.y);
	vec3 color = mix(ground * ground_tint, rock * rock_tint, steep);
	ALBEDO = color * mix(low_tint, vec3(1.0), COLOR.r);
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
