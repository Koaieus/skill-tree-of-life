shader_type canvas_item;

// Arcane Terminal hologram panel: rounded rect, translucent cyan tint,
// animated horizontal scanlines, and a rim glow driven by `glow` intensity +
// a per-edge `glow_edges` selector (see HoloPanel.gd). Size is pushed from
// HoloPanel.gd on _ready/resize since canvas_item shaders don't know Control
// rect size.
uniform vec2 size = vec2(300.0, 100.0);
uniform vec4 tint_color : source_color = vec4(0.35, 0.85, 0.95, 0.12);
uniform float corner_radius = 13.0;
uniform float scanline_count = 60.0;
uniform float scanline_speed = 0.35;
uniform float scanline_intensity = 0.18;
uniform vec4 glow_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// Which borders the glow lights, as bit flags: 1=top, 2=right, 4=bottom,
// 8=left (15 = all). Driven by HoloPanel.gd's @export_flags.
uniform int glow_edges = 15;

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

	// Sharp edge highlight — a thin, crisp border stroke hugging the inner
	// rounded edge (clean "card" look), NOT a soft bloom. `edge_width` px
	// thick with a hard falloff; `glow` is the intensity, `glow_edges` picks
	// which borders light. The per-side selection is measured at the border
	// so a selected edge lights uniformly and fades into an L-bracket at a
	// corner when only one of the two meeting edges is on.
	float edge_width = 2.0;
	float stroke = 1.0 - smoothstep(0.0, edge_width, -d);
	float sel = 0.0;
	if ((glow_edges & 1) != 0) sel = max(sel, 1.0 - smoothstep(0.0, edge_width, px.y));           // top
	if ((glow_edges & 2) != 0) sel = max(sel, 1.0 - smoothstep(0.0, edge_width, size.x - px.x));  // right
	if ((glow_edges & 4) != 0) sel = max(sel, 1.0 - smoothstep(0.0, edge_width, size.y - px.y));  // bottom
	if ((glow_edges & 8) != 0) sel = max(sel, 1.0 - smoothstep(0.0, edge_width, px.x));           // left
	float g = stroke * sel * glow;
	col.rgb = mix(col.rgb, glow_color.rgb, g);
	col.a += g * glow_color.a;

	float shape_alpha = 1.0 - smoothstep(-1.0, 1.0, d);
	COLOR = vec4(col.rgb, col.a * shape_alpha);
}
