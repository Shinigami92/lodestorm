// A cool glow along a body's outline, independent of the scene lights, so players, aliens and
// machines stay readable on dark ground from the isometric distance (see docs/design/art.md,
// Art direction). Used as a material overlay: it adds light on top of whatever material the mesh has.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float strength : hint_range(0.0, 4.0) = 0.8;
// Higher values keep the glow closer to the outline.
uniform float sharpness : hint_range(0.5, 8.0) = 3.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), sharpness);
	ALBEDO = color.rgb * rim * strength;
}
