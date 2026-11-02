// Heat shimmer (the Glass plains' weather, `WeatherEffects`): a soft patch facing the camera
// that bends the view behind it a little, wavering upwards. Drawn by particles, wrapped into a
// box around the viewer like the others (`weather_particle.gdshader`); their color's alpha sets
// how strongly.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 field_center = vec3(0.0);
uniform vec3 field_size = vec3(48.0, 2.0, 48.0);
// Unused (shared with the other particles' material parameters).
uniform float tint = 1.0;
uniform float glow = 0.0;
// How far the view bends at most, in screen units.
uniform float strength = 0.004;
uniform float wave_size = 9.0;
uniform float wave_speed = 2.5;

varying float edge_fade;

void vertex() {
	vec3 rel = MODEL_MATRIX[3].xyz - field_center;
	rel = mod(rel + field_size * 0.5, field_size) - field_size * 0.5;
	vec3 center = field_center + rel;
	vec3 edge = abs(rel) / (field_size * 0.5);
	edge_fade = 1.0 - smoothstep(0.75, 1.0, max(edge.x, edge.z));
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * width;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float fade = (1.0 - smoothstep(0.2, 1.0, length(centered))) * COLOR.a * edge_fade;
	float wave = sin(UV.y * wave_size + TIME * wave_speed + UV.x * 3.0);
	float wave2 = sin(UV.y * wave_size * 1.7 - TIME * wave_speed * 1.3);
	vec2 offset = vec2(wave * 0.7 + wave2 * 0.3, 0.0) * strength * fade;
	ALBEDO = textureLod(screen, SCREEN_UV + offset, 0.0).rgb;
	ALPHA = fade;
}
