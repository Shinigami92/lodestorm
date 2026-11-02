// The biome's loose cover (snow, salt, ash, dust) settled on a map part's props: an overlay
// drawn over their own material, taking the biome's ground texture (projected from above, in
// world space like the ground's) where faces point up and around their foot, broken up by the
// texture's height so it lies in drifts, not as an even coat. See `SettledCover`.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// The biome's ground set (`<biome>_ground_albedo`: RGB color, A height; `_nra`: B roughness, A AO).
uniform sampler2D cover_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cover_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cover_tile = 6.0;
uniform vec3 cover_tint : source_color = vec3(1.0);
// How much settles, 0 (nothing) to 1 (every up face and the foot covered).
uniform float amount : hint_range(0.0, 1.0) = 0.5;
// Faces count as up from this normal's y, fully from the second.
uniform float up_from : hint_range(0.0, 1.0) = 0.45;
uniform float up_to : hint_range(0.0, 1.0) = 0.85;
// How high the cover heaps up around a piece's foot (its origin), in m.
uniform float skirt = 0.5;
// Width of the drifts' edge (in the mask's units): small is crisp, big is soft.
uniform float edge : hint_range(0.01, 0.5) = 0.12;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec2 uv = world_position.xz / cover_tile;
	vec4 albedo = texture(cover_albedo, uv);
	vec4 nra = texture(cover_nra, uv);
	float up = smoothstep(up_from, up_to, normalize(world_normal).y);
	float foot = 1.0 - smoothstep(0.0, skirt, world_position.y - NODE_POSITION_WORLD.y);
	// Height breaks it up: `amount` covers about that share of an up face, its texture's high
	// spots first, so it lies in drifts.
	float mask = max(up, foot) * albedo.a;
	float threshold = 1.0 - amount;
	ALPHA = smoothstep(threshold, threshold + edge, mask) * step(0.001, amount);
	ALBEDO = albedo.rgb * cover_tint;
	ROUGHNESS = nra.b;
	AO = nra.a;
}
