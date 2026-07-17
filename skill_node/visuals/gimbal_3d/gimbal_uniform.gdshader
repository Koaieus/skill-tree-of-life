shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_disabled;
// Uniform-glow gimbal ring: evenly emissive, the 3D echo of the 2D CoreHalos
// halo. The glow Environment turns the >1.0 emission into neon bloom.

instance uniform vec3 tint : source_color = vec3(0.36, 0.9, 0.585);

void fragment() {
	// Evenly emissive, but with a mild view-facing falloff so the tube keeps its
	// roundness and the nested rings stay legible instead of blooming into one
	// blob — "uniform glow" with form, not a flat flat-shaded washer.
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	ALBEDO = vec3(0.0);
	EMISSION = tint * (0.7 + rim * 1.2);
}
