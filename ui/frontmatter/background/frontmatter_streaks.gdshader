shader_type canvas_item;
render_mode blend_add;

// Additive "lines" accent layer for the frontmatter background (#602) —
// composited over frontmatter_plasma_base.gdshader by two Parallax2D copies
// of this same shader at different depths/uniforms (mirrors how
// ui/space_background/starfield.gdshader is reused three times for
// far/mid/near). Traces thin flowing contour ridges of a warped noise field
// and tints them, additively, so the mid/near layers read as light streaking
// through the base layer's colour waves rather than a second opaque cloud.
//
// `shader_time` is a plain uniform the host script drives every frame instead
// of the builtin TIME, so GameSettings.reduce_motion freezes the streak
// animation without touching the Parallax2D's camera-driven scroll — same
// contract as frontmatter_plasma_base.gdshader.
//
// Deliberately SDR: `tint * line` is clamped well under 1.0 by
// `line_strength`'s 0..1 range at the authored default, so stacking two
// copies over the base layer still does not clear glow_hdr_threshold. If a
// future pass wants this to bloom, that has to be a raised `line_strength`
// past 1.0 chosen on purpose, not a default drifting there — see
// .claude/rules/hdr-color.md.

uniform float shader_time : hint_range(0.0, 1000000.0) = 0.0;
uniform float scale : hint_range(0.5, 12.0) = 3.0;
uniform float warp_strength : hint_range(0.0, 2.0) = 0.5;
uniform float speed : hint_range(0.0, 1.0) = 0.08;
// Ridges traced per unit of the warped field — higher reads as finer lines.
uniform float line_freq : hint_range(1.0, 60.0) = 14.0;
// How tightly the ridge is drawn; higher = thinner, crisper lines.
uniform float line_sharpness : hint_range(1.0, 64.0) = 24.0;
uniform vec4 tint : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float line_strength : hint_range(0.0, 1.0) = 0.5;
// Decorrelates the noise field from the base layer / the other streak copy.
uniform float seed = 0.0;

// Sampled noise, not procedural (#605, same fix as frontmatter_plasma_base's
// seam trap): TEXTURE is the sprite's own NoiseTexture2D (seamless = true).
// TEXTURE is only a valid identifier inside fragment(), so it is threaded
// through as a parameter. `seed` still decorrelates this layer from the base
// layer / the other streak copy, now as a constant phase offset folded in
// before the wrap — fract(p + seed) stays periodic in p with period 1
// exactly like fract(p) does, so it does not reopen the seam. Every read,
// including the warped coordinate, goes through this same
// fract()-before-texture() path.
float noise(sampler2D tex, vec2 p) {
	return texture(tex, fract(p + seed)).r;
}

float fbm(sampler2D tex, vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * noise(tex, p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * scale;
	float t = shader_time * speed;

	vec2 warp = vec2(fbm(TEXTURE, uv - t * 0.25), fbm(TEXTURE, uv + 7.1 + t * 0.15)) * warp_strength;
	float n = fbm(TEXTURE, uv + warp);

	// A ridge lights up wherever the warped field crosses a periodic band —
	// sin() zero-crossings sharpened by a power curve into thin lines rather
	// than soft sine bands.
	float ridge = 1.0 - abs(sin((n + t) * line_freq));
	float line = pow(clamp(ridge, 0.0, 1.0), line_sharpness) * line_strength;

	COLOR = vec4(tint.rgb * line, line);
}
