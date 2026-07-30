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

// Which CARVE shape family the dome etches — one selector rather than the
// retired pair of mutually-exclusive "show this glyph" bools
// (0 = NONE, 1 = POLYGON, 2 = GEM; see InnerDisk.CarveKind). All scalar so
// the shared ShaderMaterial keeps batching every InnerDisk into one draw call.
instance uniform int carve_kind = 0;

// Polygon carve (#124 rework) — a regular-polygon "gem facet" bowl dent folded
// into this same dome height field. See sn_polygon_facet/sn_bowl_drop in
// lighting.gdshaderinc for the math and skill-node-visuals.md for the design
// intent. Every default here MUST match the matching InnerDisk export's.
instance uniform float carve_sides : hint_range(3.0, 16.0, 1.0) = 3.0;
// Anisotropic X-squish (1.0 = regular; < 1.0 narrows the shape, e.g. DEX's
// diamond read) — applied as a warp of the sampled position before the facet
// math, so the analytic gradient just needs a chain-rule rescale back.
instance uniform float carve_squish : hint_range(0.3, 1.0, 0.01) = 1.0;
instance uniform float carve_radius : hint_range(0.4, 1.15, 0.01) = 0.75;
instance uniform float well_depth : hint_range(0.0, 1.0, 0.01) = 0.35;

// Loot relic gem cut (#168), viewed from the side — see sn_gem_bump in
// lighting.gdshaderinc. `gem_lut` is deliberately a PLAIN uniform (not
// `instance uniform`): the shape is fixed and identical for every relic, so
// one shared texture on the shared ShaderMaterial costs nothing against the
// family's batching, unlike a per-instance-varying sampler would.
// filter_linear_mipmap (trilinear), not plain filter_linear: the 128px LUT
// is higher-res than the disk's on-screen footprint, so sampling it is a
// MINIFICATION — mip-aware filtering is what actually antialiases the
// facet creases instead of aliasing them (see _build_gem_lut in
// inner_disk.gd, which bakes the matching mip chain).
uniform sampler2D gem_lut : filter_linear_mipmap, hint_default_black;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec3 normal = sn_dome_normal(p);

	if (carve_kind == 2) {
		vec4 lut = texture(gem_lut, UV);
		// lut.a is antialiased COVERAGE (see InnerDisk._gem_coverage), so it
		// scales the perturbation instead of gating it. A `> 0.5` branch here
		// snapped every partially-covered pixel fully in or fully out and
		// stair-stepped the gem's outline — the soft bake was being discarded.
		if (lut.a > 0.0) {
			vec3 bump = sn_gem_bump(lut);
			float z_dome = sqrt(max(0.0001, 1.0 - dot(p, p)));
			vec2 grad_dome = -p / z_dome;
			vec2 grad_total = grad_dome - bump.yz * lut.a;
			normal = normalize(vec3(-grad_total, 1.0));
		}
	} else if (carve_kind == 1) {
		vec2 wp = vec2(p.x / carve_squish, p.y);
		vec3 bowl = sn_bowl_drop(wp, carve_sides, carve_radius, well_depth);
		if (bowl.x > 0.0) {
			// Chain rule: q.x = p.x / carve_squish, so d/d(p.x) = d/d(q.x) / carve_squish.
			bowl.y /= carve_squish;
			float z_dome = sqrt(max(0.0001, 1.0 - dot(p, p)));
			vec2 grad_dome = -p / z_dome;
			vec2 grad_total = grad_dome - bowl.yz;
			normal = normalize(vec3(-grad_total, 1.0));
		}
	}

	vec3 light_dir = sn_light_dir(highlight_position);
	vec3 final_color = sn_disk_color(normal, light_dir, tint_color.rgb, tint_mix, allocated, highlight_intensity);

	float r2 = dot(p, p);
	float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
	COLOR = vec4(final_color, edge_alpha);
}
