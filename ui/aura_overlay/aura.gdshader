shader_type canvas_item;

#include "res://ui/overlay_field.gdshaderinc"

// World-space "owned territory" wash. One circle per owned SkillNode, tagged
// with its owning entity's index; one colour per entity.
//
// Same-entity overlap does NOT stack: circles belonging to one entity are
// unioned via nearest-distance (mirrors fog.gdshader's closest-circle read),
// so a cluster of adjacent owned nodes reads as one smooth blob instead of
// getting brighter where they overlap.
//
// Cross-entity overlap is a HARD CUT, not a blend: at each pixel the entity
// with the strongest (closest) claim wins outright — a Voronoi-style
// territory line rather than two auras mixing into a muddy colour. This
// matches the issue's lean toward cuts over blends for enemy-vs-owned
// boundaries (#74).

const int MAX_CIRCLES = 512;
const int MAX_ENTITIES = 8;

uniform int circle_count : hint_range(0, 512) = 0;
// vec4(world_x, world_y, radius, entity_index)
uniform vec4 circles[MAX_CIRCLES];
uniform int entity_count : hint_range(0, 8) = 0;
uniform vec4 entity_colors[MAX_ENTITIES] : source_color;
uniform float intensity : hint_range(0.0, 1.0) = 0.6;
// Fraction of radius the alpha fades over, INSIDE the edge: full strength
// out to (1-falloff)*r, linear fade to 0 between that and r, nothing beyond.
uniform float falloff : hint_range(0.01, 1.0) = 0.6;
// Blend width of the same-entity smooth union, in normalized-distance units.
// Cross-entity boundaries are unaffected — those stay a hard argmax cut.
uniform float union_smoothness : hint_range(0.0, 0.5) = 0.12;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float min_d[MAX_ENTITIES];
	for (int e = 0; e < MAX_ENTITIES; e++) {
		min_d[e] = 1e9;
	}
	for (int i = 0; i < MAX_CIRCLES; i++) {
		if (i >= circle_count) break;
		vec4 c = circles[i];
		int e = int(c.w);
		float d = distance(world_pos, c.xy) / max(c.z, 1.0);
		// Same-entity union is smoothed: plain min() creases along the seam
		// between two of this entity's circles, reading as a Mach band.
		min_d[e] = field_smin(min_d[e], d, union_smoothness);
	}

	// Smoothstep (not a linear ramp) so the alpha slope is continuous at both
	// ends of the fade — a slope discontinuity there is a Mach band.
	float fade_start = 1.0 - max(falloff, 1e-4);
	float best_alpha = 0.0;
	int best_entity = -1;
	for (int e = 0; e < MAX_ENTITIES; e++) {
		if (e >= entity_count) break;
		float d = min_d[e];
		if (d > 1.0) continue;
		float a = 1.0 - smoothstep(fade_start, 1.0, d);
		// Strongest claim wins outright — a hard Voronoi territory line, not
		// a blend. Deliberate (#74); do NOT smooth across entities.
		if (a > best_alpha) {
			best_alpha = a;
			best_entity = e;
		}
	}

	if (best_entity < 0) {
		COLOR = vec4(0.0);
	} else {
		vec4 tint = entity_colors[best_entity];
		float alpha = best_alpha * tint.a * intensity;
		// Dither by ±half an 8-bit step to break up quantization banding in
		// the long shallow tail of the fade.
		alpha += (field_dither(FRAGCOORD.xy) - 0.5) / 255.0;
		COLOR = vec4(tint.rgb, clamp(alpha, 0.0, 1.0));
	}
}
