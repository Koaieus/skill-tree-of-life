shader_type canvas_item;

// Arcane Terminal fused panel: dark fill with optional gradient, animated
// scanlines, per-edge glow, hairline border, and sharp corner AA.
// Combines the best of GlassPanel (dark readability, gradient, border) and
// HoloPanel (scanlines, glow edge, CRT aesthetic). Size is pushed from
// FusedPanel.gd on _ready/resize since canvas_item shaders don't know
// Control rect size.

// Per-panel — see FusedPanel.gd (#391): rides set_instance_shader_parameter
// on ONE shared ShaderMaterial rather than a separate material per panel, so
// batching survives. Genuinely varies per instance: panel footprint, the
// glow selection/intensity, which edges glow, and the glow's HDR energy.
instance uniform vec2 size = vec2(300.0, 120.0);

// --- Fill ---
// Dark base color. Alpha 0.85–0.95 for readability over live game world.
// 0.06,0.13,0.17 is the #345 dial: a hint of hue (cyan-leaning teal) so the
// world bleeds back through JUST enough that scanlines read as phosphor over
// a faint world, not wallpaper over a wall.
uniform vec4 fill_color : source_color = vec4(0.06, 0.13, 0.17, 0.85);
// Optional gradient second color. gradient_mix = 0 → flat fill, 1 → full gradient.
uniform vec4 gradient_color_b : source_color = vec4(0.039, 0.043, 0.075, 0.95);
uniform float gradient_angle_deg = 158.0;
uniform float gradient_mix : hint_range(0.0, 1.0, 0.01) = 0.0;

// --- Scanlines ---
// Scanlines run in DEVICE PIXEL space, not UV space (#345): the old UV-domain
// count (60 cycles per panel, whatever its pixel height) beat against the
// device pixel grid and produced a moire whose apparent motion changed with
// editor zoom / DPI / resolution. In pixel space one scanline is always the
// same number of device pixels, so the pattern is stable across zooms; the
// drift term is unchanged wall-clock TIME, so the roll still reads as a CRT.
// `scanline_pitch` is radians per device pixel = TAU / N_px (e.g. 3.1416 =
// one scanline every 2 device pixels).
uniform float scanline_pitch : hint_range(0.5, 6.0, 0.05) = 3.14159;
uniform float scanline_speed = 0.35;
uniform float scanline_intensity : hint_range(0.0, 1.0, 0.01) = 0.09;

// --- Edge glow ---
// Constant across every panel — the identity hue before HDR tiering.
uniform vec4 glow_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
// Per-panel: how much of the stroke shows (0 = off). Animated at runtime by
// FanPanel's idle pulse, so this MUST stay an instance uniform, not baked
// into the shared material.
instance uniform float glow : hint_range(0.0, 1.0, 0.01) = 0.0;
// Per-panel: bit flags, 1=top, 2=right, 4=bottom, 8=left (15 = all).
instance uniform int glow_edges = 15;
// Per-panel EV stops (see ui/theme/emissive.gd) that glow_color is raised by
// before it's mixed into the border (#391) — this is what lets a panel's
// glow actually clear the bloom pass's linear threshold instead of just
// looking like an SDR highlight. Default ≈ Emissive.VALUE.
instance uniform float glow_energy : hint_range(0.0, 3.0, 0.05) = 1.0;
// Width of the edge glow stroke in pixels. Constant across every panel.
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

// Raises an sRGB-encoded colour by `stops` EV and returns the sRGB-encoded
// result — the exact piecewise conversion `Emissive.at()` (ui/theme/emissive.gd)
// runs on the CPU, reimplemented here because GLSL can't call into GDScript.
// Keeping the two in lockstep is why this stays piecewise instead of a `pow(2.2)`
// shortcut: a shader-side approximation would drift from the tier vocabulary
// every other emissive surface in the project is authored against.
float _srgb_to_linear1(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float _linear_to_srgb1(float l) {
	return l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1.0 / 2.4) - 0.055;
}
vec3 emissive_at(vec3 base, float stops) {
	vec3 lin = vec3(_srgb_to_linear1(base.r), _srgb_to_linear1(base.g), _srgb_to_linear1(base.b));
	lin *= pow(2.0, stops);
	return vec3(_linear_to_srgb1(lin.r), _linear_to_srgb1(lin.g), _linear_to_srgb1(lin.b));
}

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

	// Animated horizontal scanlines, drifting downward over time — sampled in
	// device pixels so the pitch never aliases against the pixel grid (#345).
	float scan = sin(FRAGCOORD.y * scanline_pitch - TIME * scanline_speed * TAU);
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
	vec3 hot_glow = emissive_at(glow_color.rgb, glow_energy);
	col.rgb = mix(col.rgb, hot_glow, g);
	col.a += g * glow_color.a;

	COLOR = vec4(col.rgb, col.a * rr_coverage(d));
}
