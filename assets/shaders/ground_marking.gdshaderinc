// Shared by the markings the suit projects on the ground (the suit ring, the target lock's
// brackets): pulled `depth_bias` m towards the camera, so the ground, grass and low plants don't
// hide them, but cliffs and props do. Use with `skip_vertex_transform`.

// The view-space position of `vertex` (model space), pulled towards the camera.
vec3 ground_marking_view(vec3 vertex, mat4 modelview, mat4 projection, float depth_bias) {
	vec3 view = (modelview * vec4(vertex, 1.0)).xyz;
	if (projection[3][3] > 0.5) {
		// Orthographic: the camera looks along -Z.
		view.z += depth_bias;
	} else {
		// Along the ray to the camera, so it stays in the same spot on screen.
		view *= max(1.0 - depth_bias / length(view), 0.05);
	}
	return view;
}
