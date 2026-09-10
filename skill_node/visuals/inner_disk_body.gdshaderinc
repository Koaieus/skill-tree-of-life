// The InnerDisk dome BODY (#257) — extracted from `inner_disk.gdshader`'s
// fragment() verbatim, so the live node (per-instance-uniform driven) and
// #257's shatter shard (plain-uniform driven, re-running this same dome
// inside its own Voronoi cell) can never drift apart. One implementation,
// two callers — same reasoning as `lighting.gdshaderinc` being shared
// between `inner_disk.gdshader` and `rim_ring.gdshader`.
//
// `sn_inner_disk_shade()` returns the dome's lit RGB at a normalized (-1..1)
// disk-space position. It does NOT touch alpha/edge falloff/vision fog — those
// are per-CALLER (the live node fades at the vision field per fragment; a
// shatter shard fades on the flight clock instead), so each `#include`r
// composes COLOR itself.
//
// GOTCHA (see lighting.gdshaderinc's own header): every parameter below is
// `p_`-prefixed ON PURPOSE. Godot's shader code-generator rewrites a
// uniform's name-token wherever it textually appears, including inside an
// included function body — so a parameter sharing a caller's uniform name
// (`tint_color`, `carve_kind`, ...) would get silently swapped for that
// uniform inside this function, and the two callers declare DIFFERENT
// uniform storage for the same names (`instance uniform` vs plain `uniform`).
// Prefixing keeps this function genuinely parameterized.

#include "res://skill_node/visuals/lighting.gdshaderinc"

// Full A-to-B-and-back period for the two-carve crossfade, seconds. Moved
// here from `inner_disk.gdshader` verbatim — the only place that read it.
const float SN_INNER_DISK_CARVE_ALTERNATE_PERIOD = 4.0;

vec3 sn_inner_disk_shade(
		vec2 p_pos,
		vec4 p_tint_color,
		float p_tint_mix,
		bool p_allocated,
		vec2 p_highlight_position,
		float p_highlight_intensity,
		int p_carve_kind,
		float p_carve_sides,
		float p_carve_squish,
		float p_carve_radius,
		float p_well_depth,
		int p_carve_slice,
		int p_carve_slice_b,
		sampler2D p_gem_lut,
		sampler2DArray p_carve_atlas) {
	vec3 normal = sn_dome_normal(p_pos);

	// Crossfade weight between slot A and slot B — identical to
	// inner_disk.gdshader's original.
	float mix_a = 1.0;
	float mix_b = 0.0;
	if (p_carve_slice_b >= 0) {
		float phase = fract(TIME / SN_INNER_DISK_CARVE_ALTERNATE_PERIOD) * TAU;
		mix_a = 0.5 + 0.5 * cos(phase);
		mix_b = 1.0 - mix_a;
	}

	// Both callers' `p` spans the same -1..1 disk space `UV` used to, so the
	// LUT/atlas lookups use the same remap the live node's `UV` gave for free.
	vec2 uv = p_pos * 0.5 + 0.5;

	vec2 bump_sum = vec2(0.0);
	bool carved = false;

	if (p_carve_kind == 2 && mix_a > 0.0) {
		vec4 lut = texture(p_gem_lut, uv);
		if (lut.a > 0.0) {
			vec3 bump = sn_gem_bump(lut);
			bump_sum += bump.yz * lut.a * mix_a;
			carved = true;
		}
	} else if (p_carve_kind == 3 && p_carve_slice >= 0 && mix_a > 0.0) {
		vec4 lut = texture(p_carve_atlas, vec3(uv, float(p_carve_slice)));
		if (lut.a > 0.0) {
			vec3 bump = sn_texture_bump(lut);
			bump_sum += bump.yz * lut.a * mix_a;
			carved = true;
		}
	} else if (p_carve_kind == 1 && mix_a > 0.0) {
		vec2 wp = vec2(p_pos.x / p_carve_squish, p_pos.y);
		vec3 bowl = sn_bowl_drop(wp, p_carve_sides, p_carve_radius, p_well_depth * mix_a);
		if (bowl.x > 0.0) {
			bump_sum += vec2(bowl.y / p_carve_squish, bowl.z);
			carved = true;
		}
	}

	if (p_carve_slice_b >= 0 && mix_b > 0.0) {
		vec4 lut = texture(p_carve_atlas, vec3(uv, float(p_carve_slice_b)));
		if (lut.a > 0.0) {
			vec3 bump = sn_texture_bump(lut);
			bump_sum += bump.yz * lut.a * mix_b;
			carved = true;
		}
	}

	if (carved) {
		float z_dome = sqrt(max(0.0001, 1.0 - dot(p_pos, p_pos)));
		vec2 grad_dome = -p_pos / z_dome;
		vec2 grad_total = grad_dome - bump_sum;
		normal = normalize(vec3(-grad_total, 1.0));
	}

	vec3 light_dir = sn_light_dir(p_highlight_position);
	return sn_disk_color(normal, light_dir, p_tint_color.rgb, p_tint_mix, p_allocated, p_highlight_intensity);
}
