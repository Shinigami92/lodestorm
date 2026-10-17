// The ground of a generated location: three tileable texture sets (made by
// assets/terrain/source/terrain_textures.py), projected in world space and blended per pixel.
// - Ground: flat and gently sloped ground, projected from above.
// - Rock: steep slopes and cliffs, projected from the sides (image up = world up, so strata run
//   horizontally); takes over by the slope.
// - Scree: loose stones at the foot of cliffs and in patches, projected from above; its share
//   comes from the vertex color's alpha (painted by GeneratedLocation).
// Hex tiling hides the tiling: each pixel mixes three samples from randomly shifted copies of the
// texture on a grid of hexagons (ground and scree also turned; rock only shifted sideways, so its
// strata stay level), the higher parts of each sample winning at the seams. A large noise varies
// the brightness on top.
// Where layers meet, the higher parts of each texture (albedo alpha = height) win, so stones and
// rock ledges poke through instead of fading. The vertex color's RGB tints everything (high ground,
// large-scale variation).
// Textures: *_albedo (RGB base color, A height) and *_nra (RG normal X/Y with image up = +Y, B
// roughness, A ambient occlusion).
// Cut-away: ground between the camera and the player it follows (a cliff on the camera's side of a
// narrow pass) is pressed down to just above the player's feet, so the player and what's around
// them stay visible (cutting a hole would show the void under the heightfield). The camera rig sets
// the globals every frame (`IsoCameraRig`); shadows keep the whole cliff.
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
// Hex cells per texture tile: more cells break the tiling up more, but also the texture's larger
// features.
uniform float hex_cells = 1.5;
// How much the textures' heights decide between the three hex samples (0: smooth mix).
uniform float hex_contrast : hint_range(0.0, 1.0) = 0.6;
// Brightness variation over large areas (0.1: by +-10%) and the size of its noise, in m.
uniform float macro_strength : hint_range(0.0, 0.3) = 0.08;
uniform float macro_size = 24.0;

// The followed player (xyz: where the cut-away aims, w: its radius in m; 0 turns it off) and the
// camera that looks at them (other views, like a light's shadow pass, don't cut).
global uniform vec4 cutaway_target;
global uniform vec3 cutaway_camera;

// Where the pressed-down ground ends, below where the cut-away aims (just above the target's
// feet), and how far above that the ground is pressed down fully (gentle swells of the open ground
// below it stay, so nothing standing on them floats). Same as `IsoCameraRig.cutaway_press`.
const float CUTAWAY_FLOOR_BELOW = 0.8;
const float CUTAWAY_FULL_ABOVE = 2.0;

varying vec3 world_position;
varying vec3 world_normal;

// How much of the ground at `p` is cut away for the camera at `eye` (0: none, 1: all): within the
// cut-away's radius of the line from the camera to the target and on the camera's side of it,
// fading out towards the radius. Built-ins are passed in (helpers can't see them).
float cutaway(vec3 p, vec3 eye) {
	float radius = cutaway_target.w;
	if (radius <= 0.0 || distance(eye, cutaway_camera) > 0.5) {
		return 0.0;
	}
	vec3 target = cutaway_target.xyz;
	vec3 to_eye = eye - target;
	float along = dot(p - target, to_eye) / dot(to_eye, to_eye);
	if (along <= 0.0) {
		return 0.0;
	}
	float off_line = distance(p, target + to_eye * min(along, 1.0));
	float inside = 1.0 - smoothstep(radius * 0.6, radius, off_line);
	return inside;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float floor_level = cutaway_target.y - CUTAWAY_FLOOR_BELOW;
	float cut = cutaway(world_position, CAMERA_POSITION_WORLD);
	cut *= smoothstep(floor_level + 0.5, floor_level + CUTAWAY_FULL_ABOVE, world_position.y);
	if (cut > 0.0) {
		world_position.y = mix(world_position.y, floor_level, cut);
		world_normal = normalize(mix(world_normal, vec3(0.0, 1.0, 0.0), cut));
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world_position, 1.0)).xyz;
		NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(world_normal, 0.0)).xyz);
	}
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

vec2 hash2(vec2 p) {
	vec2 r = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(r) * 43758.5453);
}

// The triangle of a hex grid (corners = hexagon centers) that `st` lies in: its corners and the
// barycentric weights (Mikkelsen, "Practical Real-Time Hex-Tiling", 2022).
void triangle_grid(vec2 st, out vec3 weights, out vec2 v1, out vec2 v2, out vec2 v3) {
	st *= 3.46410162; // 2 * sqrt(3)
	vec2 skewed = vec2(st.x, -0.57735027 * st.x + 1.15470054 * st.y);
	vec2 base = floor(skewed);
	vec3 temp = vec3(fract(skewed), 0.0);
	temp.z = 1.0 - temp.x - temp.y;
	float s = step(0.0, -temp.z);
	float s2 = 2.0 * s - 1.0;
	weights = vec3(-temp.z * s2, s - temp.y * s2, s - temp.x * s2);
	v1 = base + vec2(s);
	v2 = base + vec2(s, 1.0 - s);
	v3 = base + vec2(1.0 - s, s);
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

// A texture set sampled with hex tiling at `uv`; its tilt is in uv space (along u, v and the
// projection's normal). `turn`: the copies are turned too, otherwise only shifted along u.
Layer hex_sample(sampler2D albedo_map, sampler2D nra_map, vec2 uv, bool turn) {
	vec3 weights;
	vec2 corners[3];
	triangle_grid(uv * hex_cells, weights, corners[0], corners[1], corners[2]);
	// Derivatives of the unbroken uv, so the mip level doesn't jump at the cell borders.
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec4 albedo[3];
	vec4 nra[3];
	vec3 tilt[3];
	vec3 mix_weights;
	for (int i = 0; i < 3; i++) {
		vec2 random = hash2(corners[i]);
		float angle = turn ? random.x * TAU : 0.0;
		mat2 rotation = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
		vec2 shift = turn ? random : vec2(random.y, 0.0);
		vec2 at = rotation * uv + shift;
		albedo[i] = textureGrad(albedo_map, at, rotation * dx, rotation * dy);
		nra[i] = textureGrad(nra_map, at, rotation * dx, rotation * dy);
		vec3 t = tangent_normal(nra[i]);
		// Image up is -v: the tilt in the copy's uv space, turned back.
		tilt[i] = vec3(transpose(rotation) * vec2(t.x, -t.y), t.z - 1.0);
		mix_weights[i] = mix(1.0, albedo[i].a, hex_contrast) * pow(weights[i], 7.0);
	}
	mix_weights /= mix_weights.x + mix_weights.y + mix_weights.z;
	Layer layer;
	layer.albedo = albedo[0] * mix_weights.x + albedo[1] * mix_weights.y + albedo[2] * mix_weights.z;
	layer.tilt = tilt[0] * mix_weights.x + tilt[1] * mix_weights.y + tilt[2] * mix_weights.z;
	vec4 mixed_nra = nra[0] * mix_weights.x + nra[1] * mix_weights.y + nra[2] * mix_weights.z;
	layer.roughness = mixed_nra.b;
	layer.ao = mixed_nra.a;
	return layer;
}

// Projected from above: u = +X, v = +Z.
Layer top_layer(sampler2D albedo_map, sampler2D nra_map, vec2 xz, float tile) {
	Layer layer = hex_sample(albedo_map, nra_map, xz / tile, true);
	layer.tilt = vec3(layer.tilt.x, layer.tilt.z, layer.tilt.y);
	return layer;
}

// Projected from the sides (along X and Z), image up = world up.
Layer rock_layer(vec3 position, vec3 normal) {
	vec2 weights = pow(abs(normal.xz), vec2(4.0));
	weights /= max(weights.x + weights.y, 1e-4);
	// Along X: u runs along -Z on the +X side (+Z on the -X side), so it isn't mirrored; v is down.
	float side_x = normal.x >= 0.0 ? 1.0 : -1.0;
	float side_z = normal.z >= 0.0 ? 1.0 : -1.0;
	vec2 uv_x = vec2(-position.z * side_x, -position.y) / rock_tile;
	vec2 uv_z = vec2(position.x * side_z, -position.y) / rock_tile + 0.5;
	Layer x = hex_sample(rock_albedo, rock_nra, uv_x, false);
	Layer z = hex_sample(rock_albedo, rock_nra, uv_z, false);
	vec3 tilt_x = vec3(x.tilt.z * side_x, -x.tilt.y, -x.tilt.x * side_x);
	vec3 tilt_z = vec3(z.tilt.x * side_z, -z.tilt.y, z.tilt.z * side_z);
	Layer layer;
	layer.albedo = x.albedo * weights.x + z.albedo * weights.y;
	layer.tilt = tilt_x * weights.x + tilt_z * weights.y;
	layer.roughness = x.roughness * weights.x + z.roughness * weights.y;
	layer.ao = x.ao * weights.x + z.ao * weights.y;
	return layer;
}

Layer no_layer() {
	return Layer(vec4(0.0), vec3(0.0), 1.0, 1.0);
}

void fragment() {
	vec3 up = normalize(world_normal);
	float rock = smoothstep(rock_from_up, rock_to_up, up.y);
	float scree = COLOR.a * (1.0 - rock);
	float ground = 1.0 - rock - scree;

	// Layers without weight aren't sampled (most of the ground is only ground).
	vec2 xz = world_position.xz;
	Layer g = no_layer();
	Layer s = no_layer();
	Layer r = no_layer();
	if (ground > 0.001) {
		g = top_layer(ground_albedo, ground_nra, xz, ground_tile);
	}
	if (scree > 0.001) {
		s = top_layer(scree_albedo, scree_nra, xz, scree_tile);
	}
	if (rock > 0.001) {
		r = rock_layer(world_position, up);
	}
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

	float macro = value_noise(xz / macro_size) * 0.6 + value_noise(xz / (macro_size * 0.31) + 17.0) * 0.4;
	vec3 albedo = g.albedo.rgb * blend.x + s.albedo.rgb * blend.y + r.albedo.rgb * blend.z;
	ALBEDO = albedo * COLOR.rgb * (1.0 + (macro - 0.5) * 2.0 * macro_strength);
	ROUGHNESS = g.roughness * blend.x + s.roughness * blend.y + r.roughness * blend.z;
	AO = g.ao * blend.x + s.ao * blend.y + r.ao * blend.z;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
}
