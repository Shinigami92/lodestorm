// The ship's shell (assets/ship/source/ship_shell_build.py): a tileable texture set (assets/ship/textures, made
// by assets/ship/source/ship_textures.py) projected in the model's space, which is the ship's: floors from
// above (the image's up towards -z), walls from the side they face (the image's up as up), each face by its
// main axis. Hex tiling hides the tiling (as the terrain's: three randomly shifted copies on a grid of
// hexagons, floors' copies turned too, walls' only shifted so their streaks keep running down), and a large
// noise varies the brightness. Tinted, darker low on the walls (grime), optionally striped (hazard markings)
// and tinted per room (floors: `room_tint`, set by ShipShell from the room's RoomLook). The albedo's alpha is
// the metalness (bare metal).
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nra_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Meters per texture tile.
uniform float tile = 3.0;
uniform vec3 tint : source_color = vec3(1.0);
// Metalness where the texture says bare metal (its albedo's alpha), else `metallic`.
uniform float metallic = 0.0;
uniform bool metal_from_texture = true;
uniform float normal_strength = 1.0;
// Hex tiling (off for regular patterns like the grating), hex cells per texture tile, and how far the large noise moves the brightness (over `macro_size` m).
uniform bool hex_tiling = true;
uniform float hex_cells = 1.3;
uniform float macro_strength : hint_range(0.0, 0.5) = 0.15;
uniform float macro_size = 7.0;
// How much darker the walls get towards the floor, and up to which height over it.
uniform float grime : hint_range(0.0, 1.0) = 0.35;
uniform float grime_height = 1.4;
// The decks' floors in the ship (hull_layout.LOW, UP): grime counts from the deck a point is on.
uniform vec2 decks = vec2(2.5, 7.0);
// Diagonal stripes of `stripe_color` over the tinted texture (hazard markings), `stripe_width` m wide.
uniform bool stripes = false;
uniform vec3 stripe_color : source_color = vec3(0.02);
uniform float stripe_width = 0.15;
uniform bool room_tinted = false;
instance uniform vec4 room_tint : source_color = vec4(1.0);

varying vec3 v_pos;
varying vec3 v_normal;

void vertex() {
	v_pos = VERTEX;
	v_normal = NORMAL;
}

#include "res://assets/shaders/noise.gdshaderinc"
#include "res://assets/shaders/hex_tiling.gdshaderinc"

// The texture set at `uv` with hex tiling: albedo (RGB, A metalness), nra, and the normal's tilt in the
// image's axes (x right, y up). `turn`: the copies are turned too, otherwise only shifted.
void hex_sample(vec2 uv, bool turn, out vec4 albedo, out vec4 nra, out vec2 tilt) {
	vec3 weights;
	vec2 corners[3];
	triangle_grid(uv * hex_cells, weights, corners[0], corners[1], corners[2]);
	// Derivatives of the unbroken uv, so the mip level doesn't jump at the cell borders.
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	albedo = vec4(0.0);
	nra = vec4(0.0);
	tilt = vec2(0.0);
	float total = 0.0;
	for (int i = 0; i < 3; i++) {
		vec2 random = hash2(corners[i]);
		float angle = turn ? random.x * TAU : 0.0;
		mat2 rotation = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
		vec2 at = rotation * uv + random;
		float w = pow(weights[i], 7.0);
		vec4 n = textureGrad(nra_tex, at, rotation * dx, rotation * dy);
		albedo += textureGrad(albedo_tex, at, rotation * dx, rotation * dy) * w;
		nra += n * w;
		// The copy's tilt in uv space (image up is -v), turned back, then in the image's axes again.
		vec2 t = (n.rg * 2.0 - 1.0) * vec2(1.0, -1.0);
		tilt += (transpose(rotation) * t) * vec2(1.0, -1.0) * w;
		total += w;
	}
	albedo /= total;
	nra /= total;
	tilt /= total;
}

void fragment() {
	vec3 a = abs(v_normal);
	vec2 uv;
	vec3 image_right;
	vec3 image_up;
	bool floor_face = a.y >= a.x && a.y >= a.z;
	if (floor_face) {
		uv = v_pos.xz;
		image_right = vec3(1.0, 0.0, 0.0);
		image_up = vec3(0.0, 0.0, -1.0);
	} else if (a.x > a.z) {
		float s = sign(v_normal.x);
		uv = vec2(-v_pos.z * s, -v_pos.y);
		image_right = vec3(0.0, 0.0, -s);
		image_up = vec3(0.0, 1.0, 0.0);
	} else {
		float s = sign(v_normal.z);
		uv = vec2(v_pos.x * s, -v_pos.y);
		image_right = vec3(s, 0.0, 0.0);
		image_up = vec3(0.0, 1.0, 0.0);
	}
	vec4 color;
	vec4 nra;
	vec2 tilt;
	if (hex_tiling) {
		hex_sample(uv / tile, floor_face, color, nra, tilt);
	} else {
		color = texture(albedo_tex, uv / tile);
		nra = texture(nra_tex, uv / tile);
		tilt = nra.rg * 2.0 - 1.0;
	}
	vec2 big = floor_face ? v_pos.xz : vec2(v_pos.x + v_pos.z, v_pos.y);
	float macro = value_noise(big / macro_size) * 0.6 + value_noise(big / (macro_size * 0.31) + 17.0) * 0.4;
	vec3 albedo = color.rgb * tint * (1.0 + (macro - 0.5) * 2.0 * macro_strength);
	if (room_tinted) {
		albedo *= room_tint.rgb;
	}
	if (stripes) {
		float band = step(0.5, fract((v_pos.x + v_pos.z) / (2.0 * stripe_width)));
		albedo = mix(albedo, stripe_color * color.rgb / max(0.05, dot(color.rgb, vec3(0.333))), band);
	}
	float deck = v_pos.y >= decks.y - 0.3 ? decks.y : decks.x;
	float over = v_pos.y - deck;
	float low = 1.0 - smoothstep(0.0, grime_height, over);
	albedo *= 1.0 - grime * low * (1.0 - a.y) * (0.7 + 0.3 * (1.0 - nra.a));
	ALBEDO = albedo;
	ROUGHNESS = nra.b;
	METALLIC = metal_from_texture ? max(metallic, color.a) : metallic;
	AO = nra.a;
	AO_LIGHT_AFFECT = 0.4;
	vec2 t = tilt * normal_strength;
	vec3 model_normal = normalize(v_normal * sqrt(max(0.0, 1.0 - dot(t, t))) + image_right * t.x + image_up * t.y);
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(model_normal, 0.0))).xyz);
}
