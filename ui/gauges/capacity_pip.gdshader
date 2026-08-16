shader_type canvas_item;

// A single "capacity blip" — the rotated-diamond pip used for blade-size
// pips and the spell degree icon. One pip, driven per-instance by
// CapacityBlips; filled/empty + optional selection highlight + glow, plus an
// optional addon-outline band (melee blade blips, #406 follow-up) drawn just
// outside the diamond edge. With one addon color the band is solid; with two
// it's angularly split and slowly rotates (TIME-driven, no CPU cost) so both
// colors stay visible rather than picking a static split that hides one.
uniform vec2 size = vec2(14.0, 14.0);
uniform vec4 fill_color : source_color = vec4(0.62, 0.21, 0.21, 1.0);
uniform vec4 empty_color : source_color = vec4(1.0, 1.0, 1.0, 0.08);
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform float filled = 0.0;
uniform float highlight = 0.0;
uniform float glow_strength = 6.0;
uniform vec4 outline_color_a : source_color = vec4(0.0);
uniform vec4 outline_color_b : source_color = vec4(0.0);
uniform float has_outline_a = 0.0;
uniform float has_outline_b = 0.0;

const float OUTLINE_WIDTH = 0.22;
const float OUTLINE_ROTATION_SPEED = 0.6; // rad/sec — slow, legible split

void fragment() {
	vec2 half_size = size * 0.5;
	vec2 px = UV * size - half_size;
	float d = abs(px.x) / half_size.x + abs(px.y) / half_size.y - 1.0;
	float aa = 2.0 / max(1.0, min(size.x, size.y));
	float shape_alpha = 1.0 - smoothstep(-aa, aa, d);

	vec4 col = mix(empty_color, fill_color, filled);
	col.rgb += highlight_color.rgb * highlight * 0.6;
	if (filled > 0.5 && glow_strength > 0.0) {
		float glow = 1.0 - smoothstep(-glow_strength / min(size.x, size.y), 0.0, d);
		col.rgb += fill_color.rgb * glow * 0.3;
	}
	vec4 out_col = vec4(col.rgb, col.a * shape_alpha);

	if (has_outline_a > 0.5 || has_outline_b > 0.5) {
		float band = smoothstep(-aa, aa, d) - smoothstep(OUTLINE_WIDTH - aa, OUTLINE_WIDTH + aa, d);
		if (band > 0.0) {
			vec4 outline_col = outline_color_a;
			if (has_outline_a > 0.5 && has_outline_b > 0.5) {
				float angle = atan(px.y, px.x) - TIME * OUTLINE_ROTATION_SPEED;
				float half_side = step(0.0, sin(angle));
				outline_col = mix(outline_color_b, outline_color_a, half_side);
			} else if (has_outline_b > 0.5) {
				outline_col = outline_color_b;
			}
			out_col = vec4(mix(out_col.rgb, outline_col.rgb, band), max(out_col.a, band * outline_col.a));
		}
	}

	COLOR = out_col;
}
