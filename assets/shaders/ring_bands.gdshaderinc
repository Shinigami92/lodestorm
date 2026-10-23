// Shared by the rings on the ground (the suit ring, the miners' rings): bands, their shares of the
// circle, and blending.

// Coverage of the band `b` at radius `r`, at least `min_line` pixels wide; `edge` is 1 on its
// outline.
float band(float r, vec2 b, float fw, float min_line, out float edge) {
	float center = (b.x + b.y) * 0.5;
	float half_width = max((b.y - b.x) * 0.5, min_line * fw * 0.5);
	float d = abs(r - center);
	edge = smoothstep(half_width - 2.5 * fw, half_width - fw, d);
	return 1.0 - smoothstep(half_width - fw, half_width, d);
}

// Coverage of a share range [from, to] of the circle at radius `r` (anti-aliased in m).
float span(float s, float from, float to, float r, float fw) {
	float d = max(from - s, s - to) * TAU * r;
	return clamp(0.5 - d / fw, 0.0, 1.0);
}

vec4 over(vec4 below, vec4 above) {
	float a = above.a + below.a * (1.0 - above.a);
	vec3 rgb = (above.rgb * above.a + below.rgb * below.a * (1.0 - above.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}
