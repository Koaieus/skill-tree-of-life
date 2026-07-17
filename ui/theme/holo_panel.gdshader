shader_type canvas_item;

// Arcane Terminal hologram panel: rounded rect, translucent cyan tint,
// animated horizontal scanlines, and a rim glow driven by ONE exported
// `glow` control (see HoloPanel.gd). Size is pushed from HoloPanel.gd on
// _ready/resize since canvas_item shaders don't know Control rect size.
uniform vec2 size = vec2(300.0, 100.0);
uniform vec4 tint_color : source_color = vec4(0.35, 0.85, 0.95, 0.12);
uniform float corner_radius = 13.0;
uniform float scanline_count = 60.0;
uniform float scanline_speed = 0.35;
uniform float scanline_intensity = 0.18;
uniform vec4 glow_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;

float sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * size;
	vec2 centered = px - size * 0.5;
	float d = sd_round_rect(centered, size * 0.5, corner_radius);

	vec4 col = tint_color;

	// Animated horizontal scanlines, drifting downward over time.
	float scan = sin(UV.y * scanline_count * TAU - TIME * scanline_speed * TAU);
	float scan_mask = smoothstep(0.7, 1.0, scan);
	col.rgb += scan_mask * scanline_intensity;

	// Rim glow along the panel edge, strength controlled by `glow`.
	float rim = 1.0 - smoothstep(-8.0, 0.0, d);
	col.rgb = mix(col.rgb, glow_color.rgb, rim * glow);
	col.a += rim * glow * glow_color.a;

	float shape_alpha = 1.0 - smoothstep(-1.0, 1.0, d);
	COLOR = vec4(col.rgb, col.a * shape_alpha);
}
