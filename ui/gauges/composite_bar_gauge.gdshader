shader_type canvas_item;

// Proportional multi-bucket bar (Skill Points: to-spend/wounded/staked/
// allocated). fractions are normalized 0..1 shares in stacking order;
// bucket index 1 ("wounded") pulses per the design's woundPulse keyframe.
uniform vec2 size = vec2(200.0, 14.0);
uniform vec4 fractions = vec4(0.1, 0.2, 0.1, 0.6);
uniform vec4 color_0 : source_color = vec4(0.26, 0.64, 0.99, 1.0);
uniform vec4 color_1 : source_color = vec4(0.87, 0.23, 0.24, 1.0);
uniform vec4 color_2 : source_color = vec4(0.91, 0.67, 0.30, 1.0);
uniform vec4 color_3 : source_color = vec4(0.59, 0.65, 0.78, 0.30);
uniform float corner_radius = 5.0;
uniform float pulse_speed = 2.4;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * size;
	vec2 centered = px - size * 0.5;
	float d = sd_round_rect(centered, size * 0.5, corner_radius);
	float shape_alpha = 1.0 - smoothstep(-1.0, 1.0, d);

	float b0 = fractions.x;
	float b1 = b0 + fractions.y;
	float b2 = b1 + fractions.z;

	vec4 col;
	float pulse = 1.0;
	if (UV.x < b0) {
		col = color_0;
	} else if (UV.x < b1) {
		col = color_1;
		pulse = 0.72 + 0.28 * (sin(TIME * pulse_speed) * 0.5 + 0.5);
	} else if (UV.x < b2) {
		col = color_2;
	} else {
		col = color_3;
	}

	COLOR = vec4(col.rgb, col.a * pulse * shape_alpha);
}
