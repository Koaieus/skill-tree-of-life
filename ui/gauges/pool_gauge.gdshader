shader_type canvas_item;

// Arcane Terminal pool gauge — one shader covers both the smooth vitals
// bars (Health/Mana/XP) and the skewed "battery" cells (AP/DP/Move) via
// cell_count: 0 = smooth continuous bar, N = N skewed parallelogram cells.
// drain_from renders a fading ghost trail between the new (lower) value
// and the previous one, so a stat/HP drop reads as felt power loss.
uniform vec2 size = vec2(120.0, 20.0);
uniform float current = 1.0;
uniform float min_value = 0.0;
uniform float max_value = 2.0;
uniform float drain_from = 1.0;
uniform vec4 fill_color : source_color = vec4(0.7, 0.75, 0.95, 1.0);
uniform vec4 empty_color : source_color = vec4(1.0, 1.0, 1.0, 0.08);
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.6);
// EV stops the shine trace is lifted by (see docs/domain/hdr-color.md). The
// sweep was authored as a fake additive highlight before the project had a
// real bloom pass; it now lands as a genuine >1.0 HDR crest the
// WorldEnvironment glow pass picks up, so `glow_color` is the HUE and this is
// the ENERGY. glow_color.a stays the strength of the trace over the fill.
uniform float glow_stops : hint_range(0.0, 3.0, 0.05) = 2.5;
uniform vec4 drain_color : source_color = vec4(0.9, 0.3, 0.3, 0.5);
uniform float preview_gain = 0.0;
uniform vec4 preview_color : source_color = vec4(1.0, 1.0, 1.0, 0.25);
// Transient budget bin sitting OUTSIDE the cap (#152 / SurplusPoolStat). Drawn
// as `surplus` extra battery cells appended past the cap-count cells, in
// surplus_color. 0 = disabled (resting state), so plain PoolGauges are
// unaffected. Cell branch only — surplus is a battery concept (DP/MP).
uniform float surplus = 0.0;
uniform vec4 surplus_color : source_color = vec4(0.91, 0.67, 0.30, 0.85);
// Force the battery (cell) branch even when cell_count is 0. A SurplusPoolStat
// pool whose cap is SET to 0 (Pacifist) still wants cells — its whole budget is
// the out-of-cap surplus. Without this, cell_count == 0 routes to the smooth
// branch, which never reads `surplus`, so the boost renders as an empty bar.
// Plain smooth bars (Health/Mana/XP) leave this 0.
uniform float force_cells = 0.0;
uniform float shine_speed = 0.6;
uniform float cell_count = 0.0;
uniform float skew_degrees = 0.0;
uniform float corner_radius = 4.0;
uniform float cell_gap = 3.0;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// `glow_color` lifted to `glow_stops`, normalized by its PEAK channel —
// Emissive.tint_peak(), not .tint(). Luminance normalization would drag a red
// vitals bar's green/blue to ~1.0 and the streak would read white with a red
// halo; peak normalization keeps the dominant channel on the tier and the
// trace the colour it was authored. `source_color` already decoded the uniform
// to linear, so the divide + pow is the whole conversion (same shader-side
// copy of the formula as slab_panel.gdshader).
vec3 shine_tint() {
	vec3 c = max(glow_color.rgb, vec3(0.0));
	float peak = max(c.r, max(c.g, c.b));
	if (peak < 0.0001) {
		return vec3(0.0);
	}
	return (c / peak) * pow(2.0, glow_stops);
}

void fragment() {
	float value_range = max(0.0001, max_value - min_value);
	float fill_frac = clamp((current - min_value) / value_range, 0.0, 1.0);
	float drain_frac = clamp((drain_from - min_value) / value_range, 0.0, 1.0);
	float preview_frac = clamp((current + preview_gain - min_value) / value_range, 0.0, 1.0);
	vec2 px = UV * size;

	// Battery mode when we have real cells, a nonzero surplus to append, or a
	// pool that always wants cells (force_cells). Otherwise a smooth bar.
	float surp = max(0.0, floor(surplus + 0.5));
	bool cell_mode = cell_count >= 0.5 || surp >= 0.5 || force_cells >= 0.5;

	if (!cell_mode) {
		vec2 centered = px - size * 0.5;
		float d = sd_round_rect(centered, size * 0.5, corner_radius);
		float shape_alpha = 1.0 - smoothstep(-1.0, 1.0, d);

		bool filled = UV.x <= fill_frac;
		bool draining = UV.x > fill_frac && UV.x <= drain_frac;
		bool previewing = !draining && UV.x > fill_frac && UV.x <= preview_frac;

		vec4 col = filled ? fill_color : empty_color;
		if (draining) {
			float trail_t = (UV.x - fill_frac) / max(0.001, drain_frac - fill_frac);
			col = mix(drain_color, empty_color, trail_t);
		} else if (previewing) {
			col = preview_color;
		}
		if (filled) {
			float shine = sin((UV.x - TIME * shine_speed) * 18.0) * 0.5 + 0.5;
			col.rgb = mix(col.rgb, shine_tint(), glow_color.a * pow(shine, 6.0));
		}
		COLOR = vec4(col.rgb, col.a * shape_alpha);
	} else {
		// base_n = the cap's cells (fill math anchors here); the surplus bin
		// appends `surp` more cells past the cap. Geometry (cell width, index,
		// discard) uses the total so every cell fits the fixed widget width and
		// the strip re-widens once surplus clears. base_n may be 0 (a cap-0
		// Pacifist pool draws only its surplus cells, no phantom empty cell);
		// n is floored at 1 so a resting 0/0+0 pool still shows one empty slot.
		float base_n = max(0.0, floor(cell_count + 0.5));
		float n = max(1.0, base_n + surp);
		// Shearing the whole cell strip by skew_degrees would push the
		// top or bottom edge of the outermost cells past the texture
		// bounds (clipped off) for any nonzero skew. Instead of shearing
		// the full-width strip, shrink the strip to `usable_width` (the
		// width still shared by every horizontal slice after shearing)
		// and slide it within [0, size.x] as `t` sweeps top->bottom, so
		// both slanted side edges stay on-canvas for the whole -45..45
		// range without a second uniform — size + skew_degrees already
		// carry what's needed.
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

		// Fill fractions are relative to the cap, so multiply by base_n.
		float filled_upto = fill_frac * base_n;
		float drain_upto = drain_frac * base_n;
		float preview_upto = preview_frac * base_n;
		// Surplus cells are the band [base_n, base_n + surp); past that (the
		// n>=1 placeholder slot at rest) is an ordinary empty cell, not gold.
		bool is_surplus = idx >= base_n - 0.001 && idx < base_n + surp - 0.001;
		bool filled = !is_surplus && idx < filled_upto - 0.001;
		bool draining = !is_surplus && !filled && idx < drain_upto - 0.001;
		bool previewing = !is_surplus && !filled && !draining && idx < preview_upto - 0.001;

		vec4 col = filled ? fill_color : empty_color;
		if (is_surplus) {
			col = surplus_color;  // trailing surplus cell — available, spent first
		} else if (draining) {
			col = drain_color;
		} else if (previewing) {
			col = preview_color;
		}
		if (filled || is_surplus) {
			float shine = sin((UV.x - TIME * shine_speed) * 10.0) * 0.5 + 0.5;
			col.rgb = mix(col.rgb, shine_tint(), glow_color.a * pow(shine, 6.0));
		}
		COLOR = vec4(col.rgb, col.a * gap_mask);
	}
}
