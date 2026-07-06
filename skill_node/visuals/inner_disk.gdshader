shader_type canvas_item;

// #123 — semi-sphere shading for the SkillNode inner disk: an offset radial
// highlight fakes a lit hemisphere. Player-tinted when allocated,
// neutral-dark otherwise. See skill_node/visuals/inner_disk.gd for the
// exported knobs this is driven by (resource_local_to_scene — one material
// instance per node, uniforms never bleed across nodes).

uniform float hue = 220.0;
uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;
uniform bool allocated = false;
uniform vec2 highlight_position = vec2(-0.35, -0.35);
uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.85;

const vec3 NEUTRAL_DARK = vec3(0.16, 0.17, 0.20);
const vec3 NEUTRAL_LIGHT = vec3(0.38, 0.40, 0.45);

vec3 hue_to_rgb(float h, float s, float v) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(vec3(h) + k.xyz) * 6.0 - k.www);
	return v * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), s);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	float z = sqrt(max(0.0, 1.0 - min(r2, 1.0)));
	vec3 normal = normalize(vec3(p, z));
	vec3 light_dir = normalize(vec3(highlight_position, 0.65));
	float diffuse = max(dot(normal, light_dir), 0.0);
	float spec = pow(diffuse, 24.0) * highlight_intensity;

	vec3 tinted = hue_to_rgb(hue / 360.0, 0.55 * tint_mix, 0.85);
	vec3 base_dark = mix(NEUTRAL_DARK, NEUTRAL_LIGHT, 0.35 + 0.5 * diffuse);
	vec3 base_tint = tinted * (0.45 + 0.65 * diffuse);
	vec3 base = allocated ? base_tint : base_dark;
	vec3 final_color = base + vec3(spec);

	float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
	COLOR = vec4(final_color, edge_alpha);
}
