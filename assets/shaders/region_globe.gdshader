// A planet or moon in the navigator's hologram: a faint globe with its regions as bordered areas
// on the surface. Each surface point belongs to the nearest region center (up to `max_angle`
// away); borders run where two regions meet and along each region's outer edge. Regions keep
// their danger color; the selected one is filled brighter with a wide white border, the hovered
// one a little brighter.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

const int MAX_REGIONS = 8;

uniform vec4 globe_color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
// Region centers (unit directions in the globe's space) and colors (danger; alpha: locked dim).
uniform vec3 region_dirs[MAX_REGIONS];
uniform vec4 region_colors[MAX_REGIONS] : source_color;
uniform int region_count = 0;
uniform int selected = -1;
uniform int hovered = -1;
// How far a region reaches from its center, and how wide its borders are (radians).
uniform float max_angle = 0.6;
uniform float border = 0.025;
// Fades the whole globe in and out (zooming).
uniform float fade = 1.0;
uniform float energy = 0.9;

varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	vec3 dir = normalize(local_dir);
	float nearest = 10.0;
	float second = 10.0;
	int index = -1;
	for (int i = 0; i < MAX_REGIONS; i++) {
		if (i >= region_count) {
			break;
		}
		float angle = acos(clamp(dot(dir, region_dirs[i]), -1.0, 1.0));
		if (angle < nearest) {
			second = nearest;
			nearest = angle;
			index = i;
		} else if (angle < second) {
			second = angle;
		}
	}
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	vec3 color = globe_color.rgb;
	float alpha = 0.08 + 0.35 * rim * rim;
	if (index >= 0 && nearest < max_angle) {
		vec4 region = region_colors[index];
		bool picked = index == selected;
		float width = picked ? border * 2.0 : border;
		bool edge = (second - nearest) < width * 2.0 || (max_angle - nearest) < width;
		float fill = picked ? 0.55 : (index == hovered ? 0.38 : 0.22);
		color = picked ? mix(region.rgb, vec3(1.0), edge ? 0.8 : 0.25) : region.rgb;
		alpha = edge ? 0.95 * region.a : fill * region.a + 0.2 * rim;
	}
	ALBEDO = color;
	ALPHA = clamp(alpha * energy * fade, 0.0, 1.0);
}
