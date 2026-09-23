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
//
// #608 — figure/ground inversion: this layer used to paint `palette(n)`
// across the whole tile at alpha 1.0, so colour was the ground. The owner
// wants colour as the *figure* instead — most of the field near-black, with
// colour only in filaments — while keeping the palette and the opaque alpha
// (the Fallback ColorRect + this layer are still what stops the panels
// behind from showing through). `coverage_mask()` reuses the same ridge
// technique frontmatter_streaks.gdshader traces lines with (a periodic
// sin() zero-crossing sharpened by a pow()), but as a multiplier on the
// palette colour rather than as this layer's own alpha, so the RGB folds
// to near-black outside the filaments while alpha stays 1.0 opaque.

uniform float shader_time : hint_range(0.0, 1000000.0) = 0.0;
// Noise feature count across the tile. Higher = smaller, busier waves.
uniform float scale : hint_range(0.5, 8.0) = 1.6;
// How hard the sample point folds back on itself before the final fbm read —
// this is what turns flat marble bands into swirls.
uniform float warp_strength : hint_range(0.0, 2.0) = 0.8;
// Radians of palette cycled per second of (unfrozen) shader_time.
uniform float speed : hint_range(0.0, 1.0) = 0.045;
// Filament bands traced per unit of the warped field — higher reads as more,
// narrower slivers of colour.
uniform float coverage_freq : hint_range(1.0, 40.0) = 6.0;
// How tightly each filament is drawn before it folds to black; higher =
// thinner slivers, less screen area carrying colour.
uniform float coverage_sharpness : hint_range(1.0, 32.0) = 10.0;

// Noise sampling (fnoise/fbm) lives in frontmatter_noise.gdshaderinc (#908) —
// TEXTURE must never be forwarded into a user function as a sampler2D
// argument; see that file's header for why and the seam-trap contract.
#include "res://ui/frontmatter/background/frontmatter_noise.gdshaderinc"

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
	vec2 warp = vec2(fbm(uv + t * 0.3, 4, 0.0), fbm(uv + 5.2 - t * 0.2, 4, 0.0)) * warp_strength;
	float n = fbm(uv + warp + t, 4, 0.0);

	// Same ridge-then-pow shape frontmatter_streaks.gdshader uses to draw
	// thin lines, reused here as a coverage mask on the base layer's own
	// colour instead of on its alpha — this is the #608 inversion. Away from
	// a ridge the mask goes to 0 and the pixel folds to black; the tile
	// stays opaque (alpha 1.0) throughout.
	float ridge = 1.0 - abs(sin((n + t) * coverage_freq));
	float coverage = pow(clamp(ridge, 0.0, 1.0), coverage_sharpness);

	COLOR = vec4(clamp(palette(n), 0.0, 0.40) * coverage, 1.0);
}
