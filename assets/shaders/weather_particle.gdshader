// The weather's particles (`WeatherEffects`): a soft quad per particle, unlit. Every particle is
// wrapped into a box around the viewer (`field_center`, `field_size`), so the field stays full
// wherever the viewer walks or jumps to (the particles move in world space and would otherwise
// only fill a new spot over their life); near the box's sides they fade out, so the wrap doesn't
// pop. Shapes: a dot facing the camera (flakes, spores, embers, glints), a streak stretched along
// the particle's velocity (its Y axis, the particles align it: drifting sand, the storm) and a flat
// sheet lying on the ground, fading where it meets it (mist). `tint` dims it with the outside
// light; `glow` above 0 makes it add light instead of covering (embers, glints).
shader_type spatial;
// No fog: with premultiplied alpha the fog would be added over the whole quad, its transparent
// corners too (rectangles in the mist's height fog); the particles stay within the clear range
// around the viewer anyway.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_premul_alpha, fog_disabled;

uniform int shape : hint_range(0, 2) = 0;
uniform vec3 field_center = vec3(0.0);
uniform vec3 field_size = vec3(48.0, 16.0, 48.0);
uniform float tint = 1.0;
// How much of the field shows (0–1): the ones still alive fade out with it too (going aboard).
uniform float presence = 1.0;
uniform float glow = 0.0;
// How far above the ground a sheet fades in, in m (0: no fading, shape 2 only).
uniform float ground_fade = 0.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying float edge_fade;

void vertex() {
	vec3 rel = MODEL_MATRIX[3].xyz - field_center;
	rel = mod(rel + field_size * 0.5, field_size) - field_size * 0.5;
	vec3 center = field_center + rel;
	vec3 edge = abs(rel) / (field_size * 0.5);
	edge_fade = 1.0 - smoothstep(0.75, 1.0, max(edge.x, edge.z));
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 world;
	if (shape == 1) {
		vec3 along = MODEL_MATRIX[1].xyz / max(height, 0.0001);
		vec3 side = cross(along, normalize(INV_VIEW_MATRIX[3].xyz - center));
		float side_length = length(side);
		side = side_length > 0.001 ? side / side_length : normalize(INV_VIEW_MATRIX[0].xyz);
		world = center + side * VERTEX.x * width + along * VERTEX.y * height;
	} else if (shape == 2) {
		world = center + vec3(VERTEX.x, 0.0, VERTEX.y) * width;
	} else {
		world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * width;
	}
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float soft = 1.0 - smoothstep(shape == 2 ? 0.0 : 0.2, 1.0, length(centered));
	float alpha = COLOR.a * soft * edge_fade * presence;
	if (ground_fade > 0.0) {
		float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float behind = -scene.z / scene.w + VERTEX.z;
		alpha *= clamp(behind / ground_fade, 0.0, 1.0);
	}
	// Glowing ones keep their light: emissives never dim.
	vec3 color = COLOR.rgb * (glow > 0.0 ? 1.0 : tint);
	if (glow > 0.0) {
		ALBEDO = color * glow * alpha;
		ALPHA = 0.0;
	} else {
		ALBEDO = color * alpha;
		ALPHA = alpha;
	}
}
