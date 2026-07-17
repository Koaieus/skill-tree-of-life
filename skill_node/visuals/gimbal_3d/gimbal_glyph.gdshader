shader_type spatial;
render_mode cull_disabled;
// Solid-glyph gimbal ring: an opaque metal hoop inscribed with glowing runes on
// its inward-facing surface. A TorusMesh has real UVs (u around the major ring,
// v around the tube), so the inner face is a v band we sample a scrolling glyph
// strip into and drive as EMISSION — the inner-surface inscription the 2D path
// flagged as un-fakeable.

instance uniform vec3 tint : source_color = vec3(0.36, 0.9, 0.585);
uniform sampler2D glyphs : source_color, filter_linear, repeat_enable;
// How many glyph cells wrap around the ring — few enough that each rune reads.
uniform float glyph_tiles = 6.0;
// v-band of the tube the inscription sits on. A TorusMesh's v runs around the
// tube; this centered band lands the runes on the camera-facing wall.
uniform float inner_lo = 0.3;
uniform float inner_hi = 0.7;

void fragment() {
	// Dark brushed-metal hoop base — kept dim so the runes out-glow it.
	ALBEDO = tint * 0.22;
	METALLIC = 0.85;
	ROUGHNESS = 0.34;

	float tube = UV.y;
	float band = smoothstep(inner_lo, inner_lo + 0.05, tube)
			* (1.0 - smoothstep(inner_hi - 0.05, inner_hi, tube));
	float vv = clamp((tube - inner_lo) / max(inner_hi - inner_lo, 0.0001), 0.0, 1.0);
	vec2 guv = vec2(UV.x * glyph_tiles + TIME * 0.04, vv);
	float g = texture(glyphs, guv).r;
	EMISSION = tint * g * band * 7.0;
}
