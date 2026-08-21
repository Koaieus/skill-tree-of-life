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

// Ordered-noise amplitude, in 1/255 units, breaking up quantisation banding in
// the long shallow part of the ramp. ~1 LSB is enough; above ~2 it reads as
// visible grain. Set 0 to disable and confirm what it was actually hiding.
uniform float dither_lsb : hint_range(0.0, 3.0) = 1.0;

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
	// Distance to the nearest edge on each axis, normalised to the band depth:
	// 0 hard against an edge, 1 at full depth and beyond.
	vec2 to_edge = min(px, rect_size - px);
	vec2 t = clamp(to_edge / max(band_px, 1.0), 0.0, 1.0);

	// Per-axis ramp, then a SMOOTH UNION — deliberately not `min(t.x, t.y)`.
	// Taking the nearer edge is a Chebyshev distance, whose iso-contours are
	// nested rectangles with a derivative discontinuity along every 45-degree
	// corner diagonal. The two ramps meet at a crease there and the eye reads
	// it as a hard seam (mach banding latches onto exactly that kind of slope
	// break). The screen/probabilistic union `a + b - ab` is C1-continuous
	// across the whole rect: identical to the old ramp along an edge midpoint,
	// where the other axis contributes ~0, and smoothly brighter into the
	// corners instead of creased.
	vec2 ramp = pow(1.0 - t, vec2(falloff));
	float mask = ramp.x + ramp.y - ramp.x * ramp.y;

	// Static screen-space hash. The gradient is shallow over most of its run,
	// so without this the ramp quantises into visible steps once it is
	// composited to 8-bit. Keyed on FRAGCOORD, not TIME — it must not shimmer.
	if (dither_lsb > 0.0) {
		float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		mask += (n - 0.5) * dither_lsb / 255.0;
	}

	COLOR.a *= clamp(mask, 0.0, 1.0);
}
