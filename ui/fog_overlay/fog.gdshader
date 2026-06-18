shader_type canvas_item;

// World-space radial-cutout darkness mask.
//
// Each circle is packed as vec4(world_x, world_y, radius, motion). `motion`
// is 0 for static circles and ramps up as the radius lerps toward its
// target — used to paint a warm halo at the moving frontier.
//
// Visibility model (`range` = the circle's radius stat = the outer edge
// of any vision):
//   [center] -- 100% clear -- fade zone (clear→dark) -- HALO at d=1.0 -- pure black
//
// `falloff` is the fade-zone width as a fraction of the radius. The fade
// lives INSIDE the radius (between (1-falloff)·r and r); beyond r is pure
// black. Halo rides the outer edge — its inner side dips into the fade
// zone, its outer side dips into the dark zone, brightening both.

const int MAX_CIRCLES = 256;

uniform int circle_count : hint_range(0, 256) = 0;
uniform vec4 circles[MAX_CIRCLES];
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// Fraction of radius the gradient extends BEYOND the edge. 0 = hard cut,
// 0.5 = fade zone equal to half the radius, etc.
uniform float falloff : hint_range(0.0, 1.0) = 0.25;
// Half-width of the frontier halo, in normalized distance units. The halo
// is a band centered on the circle's edge (d == 1.0). 0 disables it.
uniform float glow_band : hint_range(0.0, 0.5) = 0.08;
uniform vec3 glow_color : source_color = vec3(1.0, 0.9, 0.6);
uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float min_d = 1e9;
	float closest_motion = 0.0;
	for (int i = 0; i < MAX_CIRCLES; i++) {
		if (i >= circle_count) break;
		vec4 c = circles[i];
		float d = distance(world_pos, c.xy) / max(c.z, 1.0);
		if (d < min_d) {
			min_d = d;
			closest_motion = c.w;
		}
	}
	// Darkness: 0 inside the clear zone, linear ramp 0→1 across the fade
	// zone (between (1-falloff) and 1), and pinned at 1 beyond the radius.
	// Linear keeps `falloff` a pure width knob.
	float fade_start = 1.0 - falloff;
	float dark = clamp((min_d - fade_start) / max(falloff, 1e-4), 0.0, 1.0);
	// Frontier halo: bell centered on d=1.0 (the outer edge of vision),
	// symmetric ±glow_band. Inner side dips into the fade zone; outer
	// side dips into the dark zone. The clear interior (d < 1 - falloff)
	// stays untouched.
	float halo = (1.0 - smoothstep(0.0, 1.0,
		min(1.0, abs(min_d - 1.0) / max(glow_band, 1e-5))
	)) * closest_motion * glow_strength;
	// Composite: the halo LIFTS the darkness (its emissive presence pushes
	// the fog alpha down) and contributes its own colored alpha. Linear
	// dark + smooth halo decay → continuous handoff at the band edge.
	float lifted_dark = clamp(dark - halo, 0.0, 1.0);
	float halo_alpha = halo * 0.6;
	float alpha = max(lifted_dark, halo_alpha) * intensity;
	vec3 color = glow_color * halo;
	COLOR = vec4(color, alpha);
}
