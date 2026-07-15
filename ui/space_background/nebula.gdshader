shader_type canvas_item;

// Soft cloudy nebula tint for the deep-space backdrop. Like starfield.gdshader
// it draws in local UV (0..1 across the host tile) so a Parallax2D can repeat +
// scroll it; output is transparent where the cloud mask is thin, letting the
// flat base show. The noise is *domain-tiling*: the value-noise lattice wraps on
// an integer period so the fbm is seamless across the Parallax2D tile boundary
// (a plain fbm leaves a hard rectangular seam once the UVs are correct — #157).
//
// NOTE: the host Sprite2D must use a REAL texture (GradientTexture2D), not a
// PlaceholderTexture2D — a placeholder collapses the sprite's UVs to a constant
// and the cloud degenerates to a flat tint (#157).

uniform vec4 color_a : source_color = vec4(0.13, 0.05, 0.30, 1.0);
uniform vec4 color_b : source_color = vec4(0.02, 0.11, 0.22, 1.0);
uniform float strength : hint_range(0.0, 1.5) = 0.5;
// Cloud feature count across the tile. Rounded to an integer internally so the
// lattice wraps exactly at the tile edge — keep it whole for a clean look.
// Higher = more / smaller features across the tile (visual zoom).
uniform float scale : hint_range(1.0, 16.0) = 3.0;
// Below this the cloud fades to transparent; above, it saturates.
uniform float threshold : hint_range(0.0, 1.0) = 0.35;
// Feathers alpha to zero near tile edges so adjacent tile copies blend
// seamlessly. 0 = no fade (sharp seam possible), 0.15 = ~300 px zone on a 2048
// tile. Increase if the seam is still visible.
uniform float edge_fade : hint_range(0.0, 0.5) = 0.06;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise whose integer lattice wraps every `period` cells, so sampling
// p in [0, period] is seamless when p returns to 0 at the next tile.
float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(mod(i, period));
	float b = hash21(mod(i + vec2(1.0, 0.0), period));
	float c = hash21(mod(i + vec2(0.0, 1.0), period));
	float d = hash21(mod(i + vec2(1.0, 1.0), period));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, float period) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p, period);
		p *= 2.0;
		period *= 2.0; // each octave doubles frequency AND its wrap period
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float period = max(1.0, floor(scale + 0.5));
	vec2 p = UV * period;
	float mask = smoothstep(threshold, threshold + 0.28, fbm(p, period));
	vec3 tint = mix(color_a.rgb, color_b.rgb, fbm(p * 2.0, period * 2.0));
	float a = clamp(mask * strength, 0.0, 1.0);

	if (edge_fade > 0.0) {
		float ef = edge_fade;
		float edge = smoothstep(0.0, ef, UV.x) * smoothstep(0.0, ef, UV.y) * smoothstep(0.0, ef, 1.0 - UV.x) * smoothstep(0.0, ef, 1.0 - UV.y);
		a *= edge;
	}

	COLOR = vec4(tint, a);
}
