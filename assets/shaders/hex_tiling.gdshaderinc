// Hex tiling, shared by the ground and ship shell shaders (textures without visible repeats).

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
