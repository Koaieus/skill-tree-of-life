shader_type canvas_item;

// Arcane Terminal fused panel: dark fill with optional gradient, animated
// scanlines, per-edge glow, hairline border, and sharp corner AA.
// Combines the best of GlassPanel (dark readability, gradient, border) and
// HoloPanel (scanlines, glow edge, CRT aesthetic). Size is pushed from
// FusedPanel.gd on _ready/resize since canvas_item shaders don't know
// Control rect size.

uniform vec2 size = vec2(300.0, 120.0);

// --- Fill ---
// Dark base color. Alpha 0.85–0.95 for readability over live game world.
uniform vec4 fill_color : source_color = vec4(0.086, 0.098, 0.149, 0.90);
// Optional gradient second color. gradient_mix = 0 → flat fill, 1 → full gradient.
uniform vec4 gradient_color_b : source_color = vec4(0.039, 0.043, 0.075, 0.95);
uniform float gradient_angle_deg = 158.0;
uniform float gradient_mix : hint_range(0.0, 1.0, 0.01) = 0.0;

// --- Scanlines ---
uniform float scanline_count = 60.0;
uniform float scanline_speed = 0.35;
uniform float scanline_intensity = 0.18;

// --- Edge glow ---
uniform vec4 glow_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float glow : hint_range(0.0, 1.0, 0.01) = 0.0;
// Bit flags: 1=top, 2=right, 4=bottom, 8=left (15 = all).
uniform int glow_edges = 15;
// Width of the edge glow stroke in pixels.
uniform float glow_width : hint_range(1.0, 12.0, 0.5) = 2.0;

// --- Border ---
uniform vec4 border_color : source_color = vec4(0.47, 0.55, 0.75, 0.16);
uniform float border_width : hint_range(0.0, 8.0, 0.1) = 1.0;

// --- Corner ---
uniform float corner_radius : hint_range(0.0, 40.0, 0.5) = 13.0;
// How wide the glow hands over between two edges meeting at a corner, in
// boundary-normal space. 0 = hard switch at the 45-degree bisector.
uniform float glow_corner_softness : hint_range(0.0, 1.0, 0.01) = 0.35;

#include "res://ui/theme/round_rect.gdshaderinc"

void fragment() {
	vec2 half_size = size * 0.5;
	vec2 centered = UV * size - half_size;
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	float d = rr_distance(centered, half_size, radius);

	// Fill: flat or gradient, controlled by gradient_mix knob.
	float rad = radians(gradient_angle_deg);
	vec2 dir = vec2(cos(rad), sin(rad));
	float t = clamp(dot(UV - 0.5, dir) + 0.5, 0.0, 1.0);
	vec4 grad = mix(fill_color, gradient_color_b, t);
	vec4 col = mix(fill_color, grad, gradient_mix);

	// Animated horizontal scanlines, drifting downward over time.
	float scan = sin(UV.y * scanline_count * TAU - TIME * scanline_speed * TAU);
	float scan_mask = smoothstep(0.7, 1.0, scan);
	col.rgb += scan_mask * scanline_intensity;

	// Hairline border stroke along the inner rounded edge.
	float border_mask = smoothstep(0.0, 1.0, -d) - smoothstep(0.0, 1.0, -d - border_width);
	col = mix(col, border_color, border_mask * border_color.a);

	// Edge glow. The stroke follows the SDF inward from the boundary; the
	// per-side selection runs off the BOUNDARY NORMAL, so both stay in the same
	// rounded geometry all the way around a corner.
	float stroke = 1.0 - smoothstep(0.0, glow_width, -d);
	vec2 n = rr_normal(centered, half_size, radius);
	float sel = rr_edge_select(n, glow_edges, glow_corner_softness);
	float g = stroke * sel * glow;
	col.rgb = mix(col.rgb, glow_color.rgb, g);
	col.a += g * glow_color.a;

	COLOR = vec4(col.rgb, col.a * rr_coverage(d));
}
