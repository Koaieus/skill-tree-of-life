shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
// Holo-glass gimbal ring: semitransparent body, edges lit by a fresnel rim so
// the silhouette reads as a glowing glass hoop. The Environment glow blooms the
// bright rim.

instance uniform vec3 tint : source_color = vec3(0.36, 0.9, 0.585);

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - abs(dot(n, v)), 2.5);
	ALBEDO = tint;
	ALPHA = 0.07 + fres * 0.9;
	METALLIC = 0.0;
	ROUGHNESS = 0.12;
	EMISSION = tint * (0.25 + fres * 3.5);
}
