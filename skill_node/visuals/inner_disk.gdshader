shader_type canvas_item;

// #123 — semi-sphere shading for the SkillNode inner disk: an offset radial
// highlight fakes a lit hemisphere. Player-tinted when allocated,
// neutral-dark otherwise. `instance uniform`s mean every inner_disk shares
// ONE ShaderMaterial (batches into one draw call) while still varying
// per-node via CanvasItem.set_instance_shader_parameter() — see
// skill_node/visuals/inner_disk.gd.
//
// The lighting math lives in lighting.gdshaderinc (shared with rim_ring.gdshader)
// so the disk and its rim read as lit from one source and neither re-derives it.

#include "res://skill_node/visuals/lighting.gdshaderinc"

instance uniform vec4 tint_color : source_color = vec4(0.291, 0.5892, 1.0, 1.0);
instance uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;
instance uniform bool allocated = false;
instance uniform vec2 highlight_position = vec2(-0.35, -0.35);
instance uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec3 normal = sn_dome_normal(p);
	vec3 light_dir = sn_light_dir(highlight_position);
	vec3 final_color = sn_disk_color(normal, light_dir, tint_color.rgb, tint_mix, allocated, highlight_intensity);

	float r2 = dot(p, p);
	float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
	COLOR = vec4(final_color, edge_alpha);
}
