shader_type canvas_item;

// Opaque base layer for the frontmatter background (#602) — domain-warped
// fbm noise mapped through an Inigo Quilez cosine palette instead of a
// two-colour mix (ui/space_background/nebula.gdshader's technique), which is
// what turns plain noise into rolling "colour waves" rather than a single
// tinted cloud. Same value-noise lattice as nebula.gdshader; this layer
// covers the whole tile at alpha 1.0 so it reads as the backdrop, not a mask.
//
// `shader_time` is a plain uniform the host script (frontmatter_background.gd)
// drives every frame — never the builtin TIME — so GameSettings.reduce_motion
// can freeze the colour animation without touching the Parallax2D's
// positional scroll, which rides the camera's own navigation travel instead
// (#602's brief: parallax needs no clock of its own).
//
// Deliberately SDR: `palette()`'s a+b never exceeds ~0.40 per channel (#605
// dark-mode pass — offset and amplitude scaled by the same factor so
// saturation is preserved), so this layer does not clear glow_hdr_threshold
// and will not bloom, and leaves headroom for the two additive streak layers
// on top (base 0.40 + mid 0.30 + near 0.25 = 0.95 worst case, still under
// 1.0). See .claude/rules/hdr-color.md — a background that blooms has to be
// a named, deliberate tier, not a drifting shader output, and this one
// deliberately stays under.

uniform float shader_time : hint_range(0.0, 1000000.0) = 0.0;
// Noise feature count across the tile. Higher = smaller, busier waves.
uniform float scale : hint_range(0.5, 8.0) = 1.6;
// How hard the sample point folds back on itself before the final fbm read —
// this is what turns flat marble bands into swirls.
uniform float warp_strength : hint_range(0.0, 2.0) = 0.8;
// Radians of palette cycled per second of (unfrozen) shader_time.
uniform float speed : hint_range(0.0, 1.0) = 0.045;

// Sampled noise, not procedural (#605): TEXTURE is the sprite's own
// NoiseTexture2D (seamless = true), so every read is a hardware texture
// fetch instead of a hash. TEXTURE is only a valid identifier inside
// fragment(), so it is threaded through as a parameter rather than read
// globally. The one rule that keeps this seamless: NEVER pass an unwrapped
// coordinate into texture() — always fract() first, at every octave and for
// the warped coordinate too, because a NoiseTexture2D only tiles across its
// own [0,1) UV period. A sample that drifts outside that wrapped domain
// reintroduces the seam this shader exists to remove.
float noise(sampler2D tex, vec2 p) {
	return texture(tex, fract(p)).r;
}

float fbm(sampler2D tex, vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise(tex, p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

// Classic iq cosine palette (a + b*cos(2pi*(c*t+d))) — cheap, and it is what
// makes the noise field read as travelling rainbow bands instead of a tinted
// grayscale cloud. Coefficients hand-picked for a violet/teal/amber cycle
// that stays clear of a flat gray midpoint at any t.
vec3 palette(float t) {
	// #605 — dark mode: offset and amplitude scaled by the same ~0.3 factor,
	// which darkens the field while leaving saturation mathematically
	// unchanged (the owner explicitly liked the saturation). c and d (the
	// hue cycle) are kept exactly as authored.
	vec3 a = vec3(0.126, 0.114, 0.144);
	vec3 b = vec3(0.114, 0.102, 0.114);
	vec3 c = vec3(1.0, 1.0, 1.2);
	vec3 d = vec3(0.1, 0.35, 0.6);
	return a + b * cos(6.28318 * (c * t + d));
}

void fragment() {
	vec2 uv = UV * scale;
	float t = shader_time * speed;

	// Domain warp: offset the sample point by a second, slower fbm field so
	// bands fold into swirls rather than sitting as flat marble stripes.
	vec2 warp = vec2(fbm(TEXTURE, uv + t * 0.3), fbm(TEXTURE, uv + 5.2 - t * 0.2)) * warp_strength;
	float n = fbm(TEXTURE, uv + warp + t);

	COLOR = vec4(clamp(palette(n), 0.0, 0.40), 1.0);
}
