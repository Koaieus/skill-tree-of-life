shader_type spatial;
render_mode cull_back;
// Solid-glyph gimbal ring: an opaque metal hoop inscribed with glowing runes on
// its inward-facing surface. The band mesh (gimbal_3d.gd::_build_band_mesh) hands
// the INNER wall clean UVs — u around the ring, v in [0,1] across the wall — while
// the outer wall and both rims are parked at v = OUTER_V (>1), where the band mask
// below is 0. So the runes inscribe only the inner face (centered down it) and the
// rims stay bare — the "rim thickness awareness" the thin single-wall lacked.
// cull_back drops the near inner wall (occluded by the near outer wall anyway), so
// you read the FAR inner face lit through the ring's near gap.

instance uniform vec3 tint : source_color = vec3(0.36, 0.9, 0.585);
uniform sampler2D glyphs : source_color, filter_linear, repeat_enable;
// How many glyph cells wrap around the ring — few enough that each rune reads.
uniform float glyph_tiles = 7.0;
// Edge feather: the runes span the inner wall's full height (v in [0,1]) minus a
// small margin at each rim, so they run centered down the band.
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
