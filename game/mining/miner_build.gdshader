// A miner's own look while it's projected onto its node (see MinerHologram): the material of one of
// its parts, copied from its StandardMaterial3D (albedo, normal map, roughness, metallic and
// ambient occlusion from their texture channels, emission), up to `build_line` (world Y, per
// instance); above it nothing, the hologram shows there.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform float build_line = 100000.0;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float roughness = 1.0;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic = 0.0;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float specular = 0.5;
uniform bool use_normal_map = false;
uniform sampler2D normal_texture : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
uniform bool use_ao = false;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (world_y > build_line) {
		discard;
	}
	vec4 color = albedo * texture(albedo_texture, UV);
	ALBEDO = color.rgb;
	ROUGHNESS = dot(texture(roughness_texture, UV), roughness_channel) * roughness;
	METALLIC = dot(texture(metallic_texture, UV), metallic_channel) * metallic;
	SPECULAR = specular;
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (use_ao) {
		AO = dot(texture(ao_texture, UV), ao_channel);
		AO_LIGHT_AFFECT = ao_light_affect;
	}
	EMISSION = emission.rgb * emission_energy;
}
