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

#include "res://ui/theme/round_rect.gdshaderinc"

void fragment() {
	vec2 half_size = size * 0.5;
	vec2 centered = UV * size - half_size;
	float d = rr_distance(centered, half_size, min(corner_radius, min(half_size.x, half_size.y)));

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

	COLOR = vec4(col.rgb, col.a * rr_coverage(d));
}
