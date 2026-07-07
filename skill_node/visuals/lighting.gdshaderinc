// Shared shading model for the SkillNode-visuals family (milestone #16).
//
// ONE source of truth for the "height-field + one light" model: rim, disk (and
// later weld) stop each re-deriving the same `normalize(vec3(dir, LIGHT_Z))`
// light + Lambert/specular math and #include these helpers instead. Keep the
// numbers here identical to the CPU twin in weld_symbol.gd::_disk_shade() until
// that component is reworked into a real height feature (then it drops its copy
// and the duplication is fully gone).
//
// LIGHT_Z is the fixed height of the faked light above the node plane. A later
// global-uniform light framework can replace the per-shader `*_dir_xy` inputs
// with global data without touching these helpers.
//
// GOTCHA: every parameter below is `p_`-prefixed ON PURPOSE. Godot's shader
// code-generator rewrites uniform-name *tokens* wherever they appear — including
// inside a function body — into the uniform's storage accessor. A parameter
// sharing a uniform's name (e.g. a `vec3 tint_color` param vs the shader's
// `instance uniform vec4 tint_color`) gets its in-body uses silently swapped for
// the uniform, producing invalid generated GLSL (`mix(vec3, vec4, float)`) that
// fails at driver compile — passing Godot's own parser, so nothing catches it
// until the GPU rejects it. Prefixing keeps these functions genuinely
// parameterized and collision-proof against any consumer's uniform names.

const float SN_LIGHT_Z = 0.65;
const vec3 SN_NEUTRAL_DARK = vec3(0.16, 0.17, 0.20);
const vec3 SN_NEUTRAL_LIGHT = vec3(0.38, 0.40, 0.45);

// The faked main-light direction from its xy component (z fixed above plane).
vec3 sn_light_dir(vec2 p_dir_xy) {
	return normalize(vec3(p_dir_xy, SN_LIGHT_Z));
}

float sn_diffuse(vec3 p_normal, vec3 p_light_dir) {
	return max(dot(p_normal, p_light_dir), 0.0);
}

float sn_specular(float p_diffuse, float p_intensity) {
	return pow(p_diffuse, 24.0) * p_intensity;
}

// Hemisphere-dome surface normal at a normalized (-1..1) disk-space position.
vec3 sn_dome_normal(vec2 p_pos) {
	float r2 = dot(p_pos, p_pos);
	float z = sqrt(max(0.0, 1.0 - min(r2, 1.0)));
	return normalize(vec3(p_pos, z));
}

// Full inner-disk shaded color: tinted-lit when allocated, neutral-dark when
// not, plus the specular term. Matches the pre-include inner_disk fragment.
vec3 sn_disk_color(vec3 p_normal, vec3 p_light_dir, vec3 p_tint, float p_tint_mix,
		bool p_allocated, float p_highlight_intensity) {
	float diffuse = sn_diffuse(p_normal, p_light_dir);
	float spec = sn_specular(diffuse, p_highlight_intensity);
	vec3 tinted = mix(vec3(0.5), p_tint, p_tint_mix);
	vec3 base_dark = mix(SN_NEUTRAL_DARK, SN_NEUTRAL_LIGHT, 0.35 + 0.5 * diffuse);
	vec3 base_tint = tinted * (0.45 + 0.65 * diffuse);
	vec3 base = p_allocated ? base_tint : base_dark;
	return base + vec3(spec);
}
