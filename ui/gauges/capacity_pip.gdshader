shader_type canvas_item;

// A single "capacity blip" — the rotated-diamond pip used for blade-size
// pips and the spell degree icon. One pip, driven per-instance by
// CapacityBlips; filled/empty + optional selection highlight + glow.
uniform vec2 size = vec2(14.0, 14.0);
uniform vec4 fill_color : source_color = vec4(0.62, 0.21, 0.21, 1.0);
uniform vec4 empty_color : source_color = vec4(1.0, 1.0, 1.0, 0.08);
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform float filled = 0.0;
uniform float highlight = 0.0;
uniform float glow_strength = 6.0;

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
	COLOR = vec4(col.rgb, col.a * shape_alpha);
}
