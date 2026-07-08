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

// Weld glyph (#124 rework) — a regular-polygon "gem facet" bowl dent folded
// into this same dome height field. See sn_polygon_facet/sn_bowl_drop in
// lighting.gdshaderinc for the math and skill-node-visuals.md for the design
// intent. All scalar so the shared ShaderMaterial keeps batching every
// InnerDisk into one draw call.
instance uniform bool show_weld = false;
instance uniform float weld_sides : hint_range(3.0, 16.0, 1.0) = 6.0;
instance uniform float weld_k : hint_range(0.4, 1.15, 0.01) = 0.75;
instance uniform float well_depth : hint_range(0.0, 1.0, 0.01) = 0.35;
instance uniform float hairline_width : hint_range(0.0, 0.05, 0.001) = 0.015;
instance uniform float hairline_opacity : hint_range(0.0, 1.0, 0.01) = 0.35;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec3 normal = sn_dome_normal(p);

	if (show_weld) {
		vec3 bowl = sn_bowl_drop(p, weld_sides, weld_k, well_depth);
		if (bowl.x > 0.0) {
			float z_dome = sqrt(max(0.0001, 1.0 - dot(p, p)));
			vec2 grad_dome = -p / z_dome;
			vec2 grad_total = grad_dome - bowl.yz;
			normal = normalize(vec3(-grad_total, 1.0));
		}
	}

	vec3 light_dir = sn_light_dir(highlight_position);
	vec3 final_color = sn_disk_color(normal, light_dir, tint_color.rgb, tint_mix, allocated, highlight_intensity);

	if (show_weld && hairline_opacity > 0.0) {
		float edge_dist = sn_polygon_facet(p, weld_sides, weld_k).w;
		float hairline = 1.0 - smoothstep(0.0, max(hairline_width, 0.0001), abs(edge_dist));
		final_color += vec3(hairline * hairline_opacity);
	}

	float r2 = dot(p, p);
	float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
	COLOR = vec4(final_color, edge_alpha);
}
