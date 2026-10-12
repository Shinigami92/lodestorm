// The ground of a generated location: three tileable texture sets (made by
// assets/terrain/source/terrain_textures.py), projected in world space and blended per pixel.
// - Ground: flat and gently sloped ground, projected from above; sampled twice (the second time
//   turned and scaled) and mixed by a large noise, so its tiling doesn't show.
// - Rock: steep slopes and cliffs, projected from the sides (image up = world up, so strata run
//   horizontally); takes over by the slope.
// - Scree: loose stones at the foot of cliffs and in patches, projected from above; its share
//   comes from the vertex color's alpha (painted by GeneratedLocation).
// Where layers meet, the higher parts of each texture (albedo alpha = height) win, so stones and
// rock ledges poke through instead of fading. The vertex color's RGB tints everything (high ground,
// large-scale variation).
// Textures: *_albedo (RGB base color, A height) and *_nra (RG normal X/Y with image up = +Y, B
// roughness, A ambient occlusion).
shader_type spatial;
render_mode cull_back;

uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Edge length of one texture tile, in m.
uniform float ground_tile = 6.0;
uniform vec3 ground_tint : source_color = vec3(1.0);
uniform sampler2D scree_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scree_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scree_tile = 4.0;
uniform vec3 scree_tint : source_color = vec3(1.0);
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_tile = 8.0;
uniform vec3 rock_tint : source_color = vec3(1.0);
// Rock takes over between these slopes (the normal's up component: 1 flat, 0 vertical).
uniform float rock_from_up = 0.82;
uniform float rock_to_up = 0.68;
// How much the textures' heights push one layer through another where they meet.
uniform float height_blend : hint_range(0.0, 2.0) = 0.6;
// Width of the transition after the height decided, smaller is crisper.
uniform float blend_softness : hint_range(0.01, 1.0) = 0.12;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// Size of the noise mixing the two ground samples, in m.
uniform float variation_size = 11.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Tangent-space normal (image X right, Y up) from an nra sample.
vec3 tangent_normal(vec4 nra) {
	vec2 xy = (nra.rg * 2.0 - 1.0) * normal_strength;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

struct Layer {
	vec4 albedo; // RGB color, A height
	vec3 tilt; // world space: the texture's normal minus the projection's flat normal
	float roughness;
	float ao;
};

// Projected from above: image right = +X, image up = -Z.
Layer top_layer(sampler2D albedo_map, sampler2D nra_map, vec2 uv) {
	Layer layer;
	layer.albedo = texture(albedo_map, uv);
	vec4 nra = texture(nra_map, uv);
	vec3 t = tangent_normal(nra);
	layer.tilt = vec3(t.x, t.z - 1.0, -t.y);
	layer.roughness = nra.b;
	layer.ao = nra.a;
	return layer;
}

// The ground, sampled twice (the second sample turned by `turn` and scaled) and mixed.
Layer ground_layer(vec2 xz) {
	Layer a = top_layer(ground_albedo, ground_nra, xz / ground_tile);
	const float turn = 2.1;
	mat2 rotation = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn)));
	Layer b = top_layer(ground_albedo, ground_nra, rotation * (xz / (ground_tile * 1.37)) + 0.31);
	// Turn the second sample's tilt back into world space (uv space has v = +Z).
	vec2 back = transpose(rotation) * vec2(b.tilt.x, b.tilt.z);
	b.tilt = vec3(back.x, b.tilt.y, back.y);
	float noise = value_noise(xz / variation_size) * 0.65 + value_noise(xz / (variation_size * 0.37)) * 0.35;
	float t = smoothstep(0.4, 0.6, noise + (b.albedo.a - a.albedo.a) * 0.25);
	Layer mixed;
	mixed.albedo = mix(a.albedo, b.albedo, t);
	mixed.tilt = mix(a.tilt, b.tilt, t);
	mixed.roughness = mix(a.roughness, b.roughness, t);
	mixed.ao = mix(a.ao, b.ao, t);
	return mixed;
}

// Projected from the sides (along X and Z), image up = world up.
Layer rock_layer(vec3 position, vec3 normal) {
	vec2 weights = pow(abs(normal.xz), vec2(4.0));
	weights /= max(weights.x + weights.y, 1e-4);
	// Along X: image right runs along -Z on the +X side (+Z on the -X side), so it isn't mirrored.
	float side_x = normal.x >= 0.0 ? 1.0 : -1.0;
	float side_z = normal.z >= 0.0 ? 1.0 : -1.0;
	vec2 uv_x = vec2(-position.z * side_x, -position.y) / rock_tile;
	vec2 uv_z = vec2(position.x * side_z, -position.y) / rock_tile + 0.5;
	vec4 albedo_x = texture(rock_albedo, uv_x);
	vec4 albedo_z = texture(rock_albedo, uv_z);
	vec4 nra_x = texture(rock_nra, uv_x);
	vec4 nra_z = texture(rock_nra, uv_z);
	vec3 t_x = tangent_normal(nra_x);
	vec3 t_z = tangent_normal(nra_z);
	vec3 tilt_x = vec3((t_x.z - 1.0) * side_x, t_x.y, -t_x.x * side_x);
	vec3 tilt_z = vec3(t_z.x * side_z, t_z.y, (t_z.z - 1.0) * side_z);
	Layer layer;
	layer.albedo = albedo_x * weights.x + albedo_z * weights.y;
	layer.tilt = tilt_x * weights.x + tilt_z * weights.y;
	layer.roughness = nra_x.b * weights.x + nra_z.b * weights.y;
	layer.ao = nra_x.a * weights.x + nra_z.a * weights.y;
	return layer;
}

void fragment() {
	vec3 up = normalize(world_normal);
	float rock = smoothstep(rock_from_up, rock_to_up, up.y);
	float scree = COLOR.a * (1.0 - rock);
	float ground = 1.0 - rock - scree;

	Layer g = ground_layer(world_position.xz);
	Layer s = top_layer(scree_albedo, scree_nra, world_position.xz / scree_tile);
	Layer r = rock_layer(world_position, up);
	g.albedo.rgb *= ground_tint;
	s.albedo.rgb *= scree_tint;
	r.albedo.rgb *= rock_tint;

	// Height blend: each layer's weight plus its texture height; the highest wins, and whatever
	// comes within `blend_softness` of it mixes in. Layers without weight stay out.
	vec3 weights = vec3(ground, scree, rock);
	vec3 heights = vec3(g.albedo.a, s.albedo.a, r.albedo.a);
	vec3 score = weights + heights * height_blend - step(weights, vec3(0.001)) * 10.0;
	float top = max(score.x, max(score.y, score.z));
	vec3 blend = max(score - top + blend_softness, vec3(0.0));
	blend /= blend.x + blend.y + blend.z;

	// The textures' normals tilt the surface's (UDN-style: add the tilt to the actual normal).
	vec3 normal = normalize(up + g.tilt * blend.x + s.tilt * blend.y + r.tilt * blend.z);

	ALBEDO = (g.albedo.rgb * blend.x + s.albedo.rgb * blend.y + r.albedo.rgb * blend.z) * COLOR.rgb;
	ROUGHNESS = g.roughness * blend.x + s.roughness * blend.y + r.roughness * blend.z;
	AO = g.ao * blend.x + s.ao * blend.y + r.ao * blend.z;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
}
