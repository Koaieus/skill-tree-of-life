shader_type canvas_item;

// Proportional multi-bucket bar (Skill Points: to-spend/allocated/wounded/
// staked). Stacking order (left->right) is to-spend, allocated (rendered as
// plain background — it's headroom already invested, not a "problem"
// bucket), wounded, staked — wounds/staked trail at the end per design so
// the "available to spend" segment reads first and glows.
// fractions are normalized 0..1 shares against the pool's max; `allocated`
// is derived as the remainder (1 - to_spend - wounded - staked), not passed
// explicitly. Bucket 1 in draw order ("wounded") pulses per the design's
// woundPulse keyframe.
//
// cell_count == 0 renders the original smooth rounded-rect bar; N > 0
// renders N skewed parallelogram "battery" cells, mirroring PoolGauge's
// shine/cell/skew uniform-naming convention (same clip-safe skew math —
// see pool_gauge.gdshader's comment for why the window slides).
uniform vec2 size = vec2(200.0, 14.0);
uniform vec3 fractions = vec3(0.1, 0.2, 0.1);
uniform vec4 color_0 : source_color = vec4(0.26, 0.64, 0.99, 1.0);
uniform vec4 color_1 : source_color = vec4(0.87, 0.23, 0.24, 1.0);
uniform vec4 color_2 : source_color = vec4(0.91, 0.67, 0.30, 1.0);
uniform vec4 color_background : source_color = vec4(0.59, 0.65, 0.78, 0.30);
uniform vec4 glow_color : source_color = vec4(0.26, 0.64, 0.99, 0.6);
uniform float corner_radius = 5.0;
uniform float pulse_speed = 2.4;
uniform float shine_speed = 0.6;
uniform float cell_count = 0.0;
uniform float skew_degrees = -15.0;
uniform float cell_gap = 3.0;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Shared bucket lookup: `u` is the 0..1 position along the bar to classify.
// Returns the bucket color and, via `out_pulse`/`out_glow`, whether the
// wound-pulse or to-spend-glow should apply at that position.
vec4 bucket_color(float u, float b0, float b1, float b2, float b3, out float out_pulse, out bool out_glow) {
	out_pulse = 1.0;
	out_glow = false;
	if (u < b0) {
		out_glow = true;
		return color_0;
	} else if (u < b1) {
		return color_background;
	} else if (u < b2) {
		out_pulse = 0.72 + 0.28 * (sin(TIME * pulse_speed) * 0.5 + 0.5);
		return color_1;
	} else if (u < b3) {
		return color_2;
	}
	return color_background;
}

void fragment() {
	vec2 px = UV * size;

	float to_spend_f = fractions.x;
	float wounded_f = fractions.y;
	float staked_f = fractions.z;
	float allocated_f = max(0.0, 1.0 - to_spend_f - wounded_f - staked_f);
	float b0 = to_spend_f;
	float b1 = b0 + allocated_f;
	float b2 = b1 + wounded_f;
	float b3 = b2 + staked_f;

	float pulse;
	bool glow;

	if (cell_count < 0.5) {
		float d = sd_round_rect(px - size * 0.5, size * 0.5, corner_radius);
		float shape_alpha = 1.0 - smoothstep(-1.0, 1.0, d);

		vec4 col = bucket_color(UV.x, b0, b1, b2, b3, pulse, glow);
		if (glow) {
			float shine = sin((UV.x - TIME * shine_speed) * 18.0) * 0.5 + 0.5;
			col.rgb += glow_color.rgb * glow_color.a * pow(shine, 6.0) * 0.6;
		}
		COLOR = vec4(col.rgb, col.a * pulse * shape_alpha);
	} else {
		float n = max(1.0, floor(cell_count + 0.5));
		float skew_px = size.y * tan(radians(skew_degrees));
		float abs_skew = abs(skew_px);
		float usable_width = max(1.0, size.x - abs_skew);
		float t = clamp(px.y / max(size.y, 0.001), 0.0, 1.0);
		float window_min = skew_px >= 0.0 ? t * skew_px : (1.0 - t) * abs_skew;
		float sheared_x = px.x - window_min;
		float cell_w = usable_width / n;
		float idx = floor(sheared_x / max(cell_w, 0.001));

		if (sheared_x < 0.0 || sheared_x > usable_width || idx >= n) {
			discard;
		}

		float local_x = mod(sheared_x, cell_w);
		float gap_mask = step(cell_gap * 0.5, local_x) * step(local_x, cell_w - cell_gap * 0.5);

		float cell_u = (idx + 0.5) / n;
		vec4 col = bucket_color(cell_u, b0, b1, b2, b3, pulse, glow);
		if (glow) {
			float shine = sin((UV.x - TIME * shine_speed) * 10.0) * 0.5 + 0.5;
			col.rgb += glow_color.rgb * glow_color.a * pow(shine, 6.0) * 0.5;
		}
		COLOR = vec4(col.rgb, col.a * pulse * gap_mask);
	}
}
