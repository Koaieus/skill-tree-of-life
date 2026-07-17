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
uniform float glyph_tiles = 7.0;
// Edge feather: the runes span the band's full height (the cylinder wall's v)
// minus a small margin at each rim.
uniform float margin = 0.12;

void fragment() {
	// Dark brushed-metal band base — kept dim so the runes out-glow it.
	ALBEDO = tint * 0.22;
	METALLIC = 0.85;
	ROUGHNESS = 0.34;

	float v = UV.y;
	float band = smoothstep(margin, margin + 0.05, v)
			* (1.0 - smoothstep(1.0 - margin - 0.05, 1.0 - margin, v));
	float vv = clamp((v - margin) / max(1.0 - 2.0 * margin, 0.0001), 0.0, 1.0);
	vec2 guv = vec2(UV.x * glyph_tiles + TIME * 0.04, vv);
	float g = texture(glyphs, guv).r;
	EMISSION = tint * g * band * 7.0;
}
