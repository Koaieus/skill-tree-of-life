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
// Deliberately SDR: `palette()`'s a+b never exceeds ~0.95 per channel, so this
// layer does not clear glow_hdr_threshold and will not bloom. See
// .claude/rules/hdr-color.md — a background that blooms has to be a named,
// deliberate tier, not a drifting shader output, and this one deliberately
// stays under.

uniform float shader_time : hint_range(0.0, 1000000.0) = 0.0;
// Noise feature count across the tile. Higher = smaller, busier waves.
uniform float scale : hint_range(0.5, 8.0) = 1.6;
// How hard the sample point folds back on itself before the final fbm read —
// this is what turns flat marble bands into swirls.
uniform float warp_strength : hint_range(0.0, 2.0) = 0.8;
// Radians of palette cycled per second of (unfrozen) shader_time.
uniform float speed : hint_range(0.0, 1.0) = 0.045;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
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
	vec3 a = vec3(0.42, 0.38, 0.48);
	vec3 b = vec3(0.38, 0.34, 0.38);
	vec3 c = vec3(1.0, 1.0, 1.2);
	vec3 d = vec3(0.1, 0.35, 0.6);
	return a + b * cos(6.28318 * (c * t + d));
}

void fragment() {
	vec2 uv = UV * scale;
	float t = shader_time * speed;

	// Domain warp: offset the sample point by a second, slower fbm field so
	// bands fold into swirls rather than sitting as flat marble stripes.
	vec2 warp = vec2(fbm(uv + t * 0.3), fbm(uv + 5.2 - t * 0.2)) * warp_strength;
	float n = fbm(uv + warp + t);

	COLOR = vec4(clamp(palette(n), 0.0, 0.95), 1.0);
}
