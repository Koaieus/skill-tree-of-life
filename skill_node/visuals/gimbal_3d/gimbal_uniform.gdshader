shader_type spatial;
render_mode cull_back, shadows_disabled, specular_disabled;
// Uniform-glow gimbal ring: evenly emissive, the 3D echo of the 2D CoreHalos
// halo. The glow Environment turns the >1.0 emission into neon bloom.

instance uniform vec3 tint : source_color = vec3(0.36, 0.9, 0.585);
#include "res://skill_node/visuals/gimbal_3d/gimbal_chain.gdshaderinc"

void vertex() {
	gimbal_vertex(VERTEX, NORMAL, TIME);
}

void fragment() {
	// Evenly emissive, but with a mild view-facing falloff so the tube keeps its
	// roundness and the nested rings stay legible instead of blooming into one
	// blob — "uniform glow" with form, not a flat flat-shaded washer.
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	ALBEDO = vec3(0.0);
	// Shape only (peak 1.0); the level is the tier Gimbal3D lifts `tint` by.
	EMISSION = tint * mix(0.37, 1.0, rim);
}
