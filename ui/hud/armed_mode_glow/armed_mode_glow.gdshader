shader_type canvas_item;
render_mode blend_add, unshaded;

// Inward border glow for the armed-mode viewport tint (#412).
//
// Carries NO colour uniform. The tint arrives through the ColorRect's own
// `color`, which reaches `fragment()` as `COLOR` — per
// `.claude/rules/rendering-performance.md`, per-instance variation belongs in
// modulate/vertex colour, not in a uniform, because a differing uniform value
// breaks batching even when the shader is identical. Here it also keeps the
// HDR discipline honest: the caller hands us an `Emissive.tint(...)` colour
// with channels above 1.0 and the shader never invents a float of its own.
//
// Additive, because this reads as light spilling in from the frame — not as a
// vignette darkening the board (which could not bloom, and would stack with
// FogOverlay's own edge falloff).

// How far in from the edge the glow reaches, in pixels.
uniform float band_px : hint_range(8.0, 512.0) = 40.0;

// Falloff curve. >1 concentrates the light at the very edge; 1.0 is linear.
uniform float falloff : hint_range(0.5, 6.0) = 2.4;

void fragment() {
	// Rect size in pixels, needed because UV is normalised — without it the
	// band would be thinner on the long axis and the corners would read as
	// ovals. Derived from SCREEN_PIXEL_SIZE (= 1 / viewport size) rather than
	// pushed as a uniform from GDScript, which means it is never stale: no
	// first-frame default to render wrong before a `resized` signal arrives,
	// and no resize plumbing at all. Valid only because this rect is anchored
	// to the full viewport (preset 15) — if it is ever inset, this has to
	// become a uniform again.
	vec2 rect_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = UV * rect_size;
	// Distance to the nearest edge on each axis, then the nearer of the two.
	vec2 to_edge = min(px, rect_size - px);
	float edge = min(to_edge.x, to_edge.y);
	float mask = 1.0 - clamp(edge / max(band_px, 1.0), 0.0, 1.0);
	COLOR.a *= pow(mask, falloff);
}
