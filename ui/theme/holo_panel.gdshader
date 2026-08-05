shader_type canvas_item;

// Arcane Terminal hologram panel: rounded rect, translucent cyan tint,
// animated horizontal scanlines, and a rim glow driven by `glow` intensity +
// a per-edge `glow_edges` selector (see HoloPanel.gd). Size is pushed from
// HoloPanel.gd on _ready/resize since canvas_item shaders don't know Control
// rect size.
uniform vec2 size = vec2(300.0, 100.0);
uniform vec4 tint_color : source_color = vec4(0.35, 0.85, 0.95, 0.12);
uniform float corner_radius = 13.0;
// Scanlines in DEVICE PIXEL space (#345) — see fused_panel.gdshader for the
// full rationale; kept in sync so the shared round_rect family stays
// consistent (the fan-trace sandbox still renders this skin directly).
// `scanline_pitch` is radians per device pixel = TAU / N_px.
uniform float scanline_pitch : hint_range(0.5, 6.0, 0.05) = 3.14159;
uniform float scanline_speed = 0.35;
uniform float scanline_intensity : hint_range(0.0, 1.0, 0.01) = 0.09;
uniform vec4 glow_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// Which borders the glow lights, as bit flags: 1=top, 2=right, 4=bottom,
// 8=left (15 = all). Driven by HoloPanel.gd's @export_flags.
uniform int glow_edges = 15;
// How wide the glow hands over between two edges meeting at a corner, in
// boundary-normal space. 0 = hard switch at the 45-degree bisector.
uniform float glow_corner_softness : hint_range(0.0, 1.0, 0.01) = 0.35;

#include "res://ui/theme/round_rect.gdshaderinc"

void fragment() {
	vec2 half_size = size * 0.5;
	vec2 centered = UV * size - half_size;
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	float d = rr_distance(centered, half_size, radius);

	vec4 col = tint_color;

	// Animated horizontal scanlines, drifting downward over time — sampled in
	// device pixels so the pitch never aliases against the pixel grid (#345).
	float scan = sin(FRAGCOORD.y * scanline_pitch - TIME * scanline_speed * TAU);
	float scan_mask = smoothstep(0.7, 1.0, scan);
	col.rgb += scan_mask * scanline_intensity;

	// Sharp edge highlight — a thin, crisp border stroke hugging the inner
	// rounded edge (clean "card" look), NOT a soft bloom. `edge_width` px
	// thick with a hard falloff; `glow` is the intensity, `glow_edges` picks
	// which borders light. The per-side selection runs off the BOUNDARY NORMAL,
	// so it follows the corner arc: a lit edge stays lit around the arc it
	// shares with another lit edge, and fades out over an arc it doesn't.
	float edge_width = 2.0;
	float stroke = 1.0 - smoothstep(0.0, edge_width, -d);
	vec2 n = rr_normal(centered, half_size, radius);
	float sel = rr_edge_select(n, glow_edges, glow_corner_softness);
	float g = stroke * sel * glow;
	col.rgb = mix(col.rgb, glow_color.rgb, g);
	col.a += g * glow_color.a;

	COLOR = vec4(col.rgb, col.a * rr_coverage(d));
}
