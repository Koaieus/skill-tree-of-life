shader_type canvas_item;
render_mode blend_add;

// Fault Line's crack: a jagged, glowing fissure laid ALONG a real edge as an
// overlay quad. Same paint-on-top contract as `edge_energize.gdshader` (never
// the edge MultiMesh — see docs/domain/spell-vfx-kit.md).
//
// ONE MATERIAL FOR EVERY CRACK. Every uniform here is shared and static. The
// per-instance channels are the node transform and `modulate` only:
//   bar x-scale  = the opening front (0..1 of the edge length)
//   bar y-scale  = the crack's width factor (the landed Sunder) — VERTEX.y is
//                  written in local space below, so the model matrix's y-scale
//                  multiplies the zoom-derived half-width per instance
//   modulate     = caster tint lifted by a named Emissive tier, and the fade
// The fracture pattern is seeded from the bar's world origin and measured in
// world pixels along the edge, so it holds still while the front grows.

uniform float edge_width : hint_range(0.0, 32.0) = 4.0;
// Quad half-height over the edge's half-width at width factor 1: room for the
// jag to wander without leaving the quad.
uniform float width_scale : hint_range(0.5, 16.0) = 8.0;
global uniform float edge_camera_zoom;
// Jag amplitude as a fraction of the quad's half-height.
uniform float jag_amplitude : hint_range(0.0, 0.9) = 0.45;
// World pixels per jag segment (the coarse octave; a finer one rides at /3).
uniform float jag_period_px : hint_range(2.0, 200.0) = 26.0;
// Half-thickness of the hot seam, as a fraction of the quad's half-height.
uniform float seam_half : hint_range(0.01, 0.5) = 0.14;
// Brightness of the glow bleeding out of the seam, relative to the seam.
uniform float halo_level : hint_range(0.0, 1.0) = 0.45;
// Hairline side fissures branching off the seam: how much of the length grows
// one (0 = none, 1 = everywhere).
uniform float branch_density : hint_range(0.0, 1.0) = 0.35;
// EV stops the opening tip sits above the seam body (named-tier steps, as in
// `edge_energize.gdshader`'s `front_gain_stops`).
uniform float front_gain_stops : hint_range(0.0, 3.0) = 1.0;
// Fraction of the quad's length the hot opening tip occupies.
uniform float front_width : hint_range(0.02, 1.0) = 0.2;

varying float along_px;
varying float crack_seed;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)),
			step(vec3(0.04045), c));
}

vec3 linear_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055),
			step(vec3(0.0031308), c));
}

float hash11(float p) {
	return fract(sin(p * 127.1 + 311.7) * 43758.5453);
}

// Piecewise-linear value noise in -1..1: straight segments between random
// knots, which reads as a fracture (sharp corners) rather than a wave.
float jag(float x) {
	float i = floor(x);
	return mix(hash11(i), hash11(i + 1.0), fract(x)) * 2.0 - 1.0;
}

void vertex() {
	float zoom = max(edge_camera_zoom, 0.0001);
	VERTEX.y = sign(VERTEX.y) * (edge_width * 0.5 * width_scale) / zoom;
	along_px = VERTEX.x * length(MODEL_MATRIX[0].xy);
	vec2 o = MODEL_MATRIX[3].xy;
	crack_seed = fract(sin(dot(o, vec2(12.9898, 78.233))) * 43758.5453) * 97.0;
}

void fragment() {
	// -1..1 across the quad, 0 on the edge's own line.
	float y = (UV.y - 0.5) * 2.0;
	float s = along_px / jag_period_px;
	// Pinned to the line at the origin end so the crack leaves the node.
	float pin = smoothstep(0.0, 1.2, s);
	float centre = (jag(s + crack_seed) * 0.7 + jag(s * 3.0 + crack_seed * 1.7) * 0.3)
			* jag_amplitude * pin;
	float d = abs(y - centre);
	float aa = max(fwidth(y) * 1.5, 0.001);
	float seam = 1.0 - smoothstep(seam_half - aa, seam_half + aa, d);
	float halo = halo_level * exp(-d / max(seam_half * 2.5, 0.001));

	// A hairline branch: a thin spur leaving the seam on one side, alive only
	// where its own noise clears the density bar.
	float bs = s * 0.5 + crack_seed * 3.1;
	float alive = step(1.0 - branch_density, hash11(floor(bs) + 7.0));
	float side = hash11(floor(bs) + 13.0) < 0.5 ? -1.0 : 1.0;
	float reach = fract(bs);
	float spur_y = centre + side * reach * (1.0 - jag_amplitude * 0.5) * 0.9;
	float spur = alive * (1.0 - reach) * (1.0 - smoothstep(seam_half * 0.35 - aa,
			seam_half * 0.35 + aa, abs(y - spur_y)));

	float body = max(max(seam, spur * 0.6), halo);
	float front = smoothstep(1.0 - front_width, 1.0, UV.x);
	vec3 lin = srgb_to_linear(COLOR.rgb) * exp2(front_gain_stops * front * seam);
	COLOR.rgb = linear_to_srgb(lin);
	COLOR.a *= clamp(body, 0.0, 1.0);
}
