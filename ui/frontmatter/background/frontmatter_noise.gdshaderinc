// Shared noise sampling for the frontmatter background's shader layers
// (#602, #908) — frontmatter_plasma_base.gdshader and
// frontmatter_streaks.gdshader both include this instead of each carrying
// its own copy of `noise()` / `fbm()`.
//
// #908: the two shaders used to thread TEXTURE (the built-in sampler) through
// a user function as a `sampler2D` parameter — `fbm(TEXTURE, ...)` — which
// the shader compiler cannot map to a custom sampler slot when a *built-in*
// sampler is forwarded through a user function; it logs a "Continuing"
// condition on every load (test/unit/test_sandbox_host_tabs.gd reds on it)
// even though the visual output is unaffected. The fix: a real uniform,
// declared once here, so TEXTURE is never forwarded anywhere.
//
// The sprite owns the texture: FrontmatterBackground._ready() pushes each
// layer sprite's own `texture` into this uniform on its ShaderMaterial (see
// frontmatter_background.gd). Nobody authors `shader_parameter/noise_tex` by
// hand in the .tscn — the runtime push is the source of truth; the @tool
// script may serialize the pushed value back on a later editor save, which
// is expected and harmless.
uniform sampler2D noise_tex : filter_linear, repeat_enable;

// Sampled noise, not procedural (#605): noise_tex is the sprite's own
// NoiseTexture2D (seamless = true), so every read is a hardware texture
// fetch instead of a hash. The one rule that keeps this seamless: NEVER pass
// an unwrapped coordinate into texture() — always fract() first, at every
// octave and for the warped coordinate too, because a NoiseTexture2D only
// tiles across its own [0,1) UV period. A sample that drifts outside that
// wrapped domain reintroduces the seam this shader exists to remove.
//
// `phase` folds in a constant offset before the wrap (frontmatter_streaks'
// old `seed`, decorrelating one layer's field from another's) —
// fract(p + phase) stays periodic in p with period 1 exactly like fract(p)
// does, so it does not reopen the seam.
float fnoise(vec2 p, float phase) {
	return texture(noise_tex, fract(p + phase)).r;
}

float fbm(vec2 p, int octaves, float phase) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += amp * fnoise(p, phase);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}
