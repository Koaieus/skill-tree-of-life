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
uniform vec4 drain_color : source_color = vec4(0.9, 0.3, 0.3, 0.5);
uniform float preview_gain = 0.0;
uniform vec4 preview_color : source_color = vec4(1.0, 1.0, 1.0, 0.25);
uniform float shine_speed = 0.6;
uniform float cell_count = 0.0;
uniform float skew_degrees = 0.0;
uniform float corner_radius = 4.0;
uniform float cell_gap = 3.0;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float value_range = max(0.0001, max_value - min_value);
	float fill_frac = clamp((current - min_value) / value_range, 0.0, 1.0);
	float drain_frac = clamp((drain_from - min_value) / value_range, 0.0, 1.0);
	float preview_frac = clamp((current + preview_gain - min_value) / value_range, 0.0, 1.0);
	vec2 px = UV * size;

	if (cell_count < 0.5) {
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
			col.rgb += glow_color.rgb * glow_color.a * pow(shine, 6.0) * 0.5;
		}
		COLOR = vec4(col.rgb, col.a * shape_alpha);
	} else {
		float n = max(1.0, floor(cell_count + 0.5));
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

		float filled_upto = fill_frac * n;
		float drain_upto = drain_frac * n;
		float preview_upto = preview_frac * n;
		bool filled = idx < filled_upto - 0.001;
		bool draining = !filled && idx < drain_upto - 0.001;
		bool previewing = !filled && !draining && idx < preview_upto - 0.001;

		vec4 col = filled ? fill_color : empty_color;
		if (draining) {
			col = drain_color;
		} else if (previewing) {
			col = preview_color;
		}
		if (filled) {
			float shine = sin((UV.x - TIME * shine_speed) * 10.0) * 0.5 + 0.5;
			col.rgb += glow_color.rgb * glow_color.a * pow(shine, 6.0) * 0.4;
		}
		COLOR = vec4(col.rgb, col.a * gap_mask);
	}
}
