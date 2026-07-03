shader_type canvas_item;

// Arcane Terminal glass panel: rounded rect, diagonal gradient fill,
// hairline border, optional inner glow. Size is pushed from GlassPanel.gd
// on _ready/resize since canvas_item shaders don't know Control rect size.
uniform vec2 size = vec2(300.0, 100.0);
uniform vec4 gradient_color_a : source_color = vec4(0.086, 0.098, 0.149, 0.94);
uniform vec4 gradient_color_b : source_color = vec4(0.039, 0.043, 0.075, 0.95);
uniform float gradient_angle_deg = 158.0;
uniform vec4 border_color : source_color = vec4(0.47, 0.55, 0.75, 0.16);
uniform float border_width = 1.0;
uniform float corner_radius = 13.0;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float glow_strength = 0.0;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * size;
	vec2 centered = px - size * 0.5;
	float d = sd_round_rect(centered, size * 0.5, corner_radius);

	float rad = radians(gradient_angle_deg);
	vec2 dir = vec2(cos(rad), sin(rad));
	float t = clamp(dot(UV - 0.5, dir) + 0.5, 0.0, 1.0);
	vec4 fill = mix(gradient_color_a, gradient_color_b, t);

	if (glow_strength > 0.0) {
		float inner_glow = 1.0 - smoothstep(-glow_strength, 0.0, d);
		fill.rgb = mix(fill.rgb, glow_color.rgb, inner_glow * glow_color.a);
	}

	float border_mask = smoothstep(0.0, 1.0, -d) - smoothstep(0.0, 1.0, -d - border_width);
	vec4 col = mix(fill, border_color, border_mask * border_color.a);

	float shape_alpha = 1.0 - smoothstep(-1.0, 1.0, d);
	COLOR = vec4(col.rgb, col.a * shape_alpha);
}
