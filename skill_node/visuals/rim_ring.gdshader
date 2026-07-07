shader_type canvas_item;

// #125 — the ring is drawn continuously from inner_r (pit/disc edge) to
// outer_r (rim): flat floor from inner_r up to crest_r, then a REAL
// height(radius) bumpmap bevel from crest_r to outer_r, lit the same way as
// inner_disk.gdshader (shared LIGHT_DIR) so the disk and its rim read as
// lit from one source. crest_r is an *interior* control point, not a draw
// boundary — RimRing knows nothing about the disk underneath it, just its
// own inner/outer band and where the bevel starts inside that band.
//
// The 4 locked presets (level/terrace/smooth/sharpen) are closed-form
// functions of the normalized bevel domain, selected by `height_preset` —
// that keeps them out of a Curve resource entirely, so every rim_ring on a
// built-in preset shares ONE ShaderMaterial via `instance uniform`s
// (batches into one draw call).
//
// A genuinely custom (5th/6th profile) Curve can't ride an instance
// uniform — samplers aren't allowed there — so rim_ring.gd falls back to a
// per-instance material + a small baked LUT texture for that case
// (height_preset == 4), an intentional, documented, opt-in cost. See
// skill_node/visuals/rim_ring.gd.
//
// Light math (sn_light_dir / sn_diffuse) is shared with inner_disk.gdshader via
// lighting.gdshaderinc so the disk and its rim can never drift onto two lights.

#include "res://skill_node/visuals/lighting.gdshaderinc"

instance uniform float inner_r = 24.0;
instance uniform float crest_r = 28.0;
instance uniform float outer_r = 32.0;
instance uniform vec4 ring_tint : source_color = vec4(0.65, 0.67, 0.72, 1.0);
instance uniform int height_preset = 0; // 0 level, 1 terrace, 2 smooth, 3 sharpen, 4 custom (height_lut)

// Only bound (and only sampled) for height_preset == 4, on that instance's
// own per-instance material — see rim_ring.gd::_sync_material.
uniform sampler2D height_lut;

// #130 — matches inner_disk.gdshader's highlight_position instance uniform
// (same xy, same fixed z=0.65) instead of a private hardcoded constant, so
// the composite can drive both from the ONE InnerDisk value and the disk +
// rim never drift onto two different light sources.
instance uniform vec2 light_dir_xy = vec2(-0.35, -0.35);

float height_level(float t) {
	return t;
}

float height_terrace(float t) {
	return clamp((floor(t * 3.0) + 1.0) / 3.0, 0.0, 1.0);
}

float height_smooth(float t) {
	return smoothstep(0.0, 1.0, t);
}

float height_sharpen(float t) {
	return t * t * t;
}

float sample_bevel(float local_t) {
	local_t = clamp(local_t, 0.0, 1.0);
	float h = height_level(local_t);
	h = mix(h, height_terrace(local_t), float(height_preset == 1));
	h = mix(h, height_smooth(local_t), float(height_preset == 2));
	h = mix(h, height_sharpen(local_t), float(height_preset == 3));
	h = mix(h, texture(height_lut, vec2(local_t, 0.5)).r, float(height_preset == 4));
	return h;
}

// Height across the WHOLE inner_r..outer_r band: flat floor up to the
// crest, then the bevel preset from crest to outer_r.
float sample_height(float t, float tc) {
	float span_after_crest = max(1.0 - tc, 0.0001);
	float local_t = (t - tc) / span_after_crest;
	return mix(0.0, sample_bevel(local_t), step(tc, t));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * outer_r;
	float r = length(p);
	float span = max(outer_r - inner_r, 0.0001);
	float t = clamp((r - inner_r) / span, 0.0, 1.0);
	float tc = clamp((crest_r - inner_r) / span, 0.0, 1.0);

	float eps = 0.015;
	float h0 = sample_height(t - eps, tc);
	float h1 = sample_height(t + eps, tc);
	float slope = (h1 - h0) / (2.0 * eps);

	vec2 radial_dir = r > 0.0001 ? p / r : vec2(0.0, 1.0);
	vec3 normal = normalize(vec3(-radial_dir * slope, 1.0));
	vec3 light_dir = sn_light_dir(light_dir_xy);
	float diffuse = sn_diffuse(normal, light_dir);
	vec3 shaded = ring_tint.rgb * (0.35 + 0.65 * diffuse);

	float inside = step(inner_r, r) * step(r, outer_r);
	float edge_soft = smoothstep(inner_r - 0.75, inner_r + 0.75, r) * (1.0 - smoothstep(outer_r - 0.75, outer_r + 0.75, r));
	COLOR = vec4(shaded, ring_tint.a * edge_soft * inside);
}
