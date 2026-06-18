shader_type canvas_item;

// World-space radial-gradient darkness mask. One uniform array of vision
// circles (xy = world pos, z = radius). Per-fragment finds the closest
// circle and lights/darkens accordingly. Cap of 64 is comfortable for any
// realistic skill-tree size; bump MAX_CIRCLES if a level ever needs more.

const int MAX_CIRCLES = 64;

uniform int circle_count : hint_range(0, 64) = 0;
uniform vec3 circles[MAX_CIRCLES];
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// Gradient softness as a fraction of each circle's radius. 0 = hard edge,
// 1 = gradient starts at the center. 0.25 looks like classic FoW falloff.
uniform float falloff : hint_range(0.0, 1.0) = 0.25;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float min_d = 1e9;
	for (int i = 0; i < MAX_CIRCLES; i++) {
		if (i >= circle_count) break;
		vec3 c = circles[i];
		// Normalized distance: 0 = center, 1 = edge, >1 = outside.
		float d = distance(world_pos, c.xy) / max(c.z, 1.0);
		min_d = min(min_d, d);
	}
	float alpha = smoothstep(1.0 - falloff, 1.0, min_d);
	COLOR = vec4(0.0, 0.0, 0.0, alpha * intensity);
}
