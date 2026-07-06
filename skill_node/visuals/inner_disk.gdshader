shader_type canvas_item;

// #123 — semi-sphere shading for the SkillNode inner disk: an offset radial
// highlight fakes a lit hemisphere. Player-tinted when allocated,
// neutral-dark otherwise. `instance uniform`s mean every inner_disk shares
// ONE ShaderMaterial (batches into one draw call) while still varying
// per-node via CanvasItem.set_instance_shader_parameter() — see
// skill_node/visuals/inner_disk.gd. Light direction matches
// rim_ring.gdshader so the disk and its rim read as lit from one source.

instance uniform vec4 tint_color : source_color = vec4(0.291, 0.5892, 1.0, 1.0);
instance uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;
instance uniform bool allocated = false;
instance uniform vec2 highlight_position = vec2(-0.35, -0.35);
instance uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.85;

const vec3 NEUTRAL_DARK = vec3(0.16, 0.17, 0.20);
const vec3 NEUTRAL_LIGHT = vec3(0.38, 0.40, 0.45);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	float z = sqrt(max(0.0, 1.0 - min(r2, 1.0)));
	vec3 normal = normalize(vec3(p, z));
	vec3 light_dir = normalize(vec3(highlight_position, 0.65));
	float diffuse = max(dot(normal, light_dir), 0.0);
	float spec = pow(diffuse, 24.0) * highlight_intensity;

	vec3 tinted = mix(vec3(0.5), tint_color.rgb, tint_mix);
	vec3 base_dark = mix(NEUTRAL_DARK, NEUTRAL_LIGHT, 0.35 + 0.5 * diffuse);
	vec3 base_tint = tinted * (0.45 + 0.65 * diffuse);
	vec3 base = allocated ? base_tint : base_dark;
	vec3 final_color = base + vec3(spec);

	float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
	COLOR = vec4(final_color, edge_alpha);
}
