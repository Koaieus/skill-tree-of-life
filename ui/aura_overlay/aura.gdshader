shader_type canvas_item;

#include "res://ui/overlay_field.gdshaderinc"

// World-space "owned territory" wash over the owned induced subgraph (#898):
// one rounded cone per owned SkillNode (degenerate — a disc) and one per edge
// whose endpoints share an owner (a rectangle, tapering to a trapezoid when
// the stake radii differ), tagged with the owning entity's index; one colour
// per entity. One primitive type, one path — see field_cone_distance.
//
// Same-entity overlap does NOT stack: primitives belonging to one entity are
// unioned via nearest-distance (mirrors fog.gdshader's closest-circle read),
// so an owned path reads as one smooth band instead of getting brighter
// where disc and cone overlap.
//
// Cross-entity overlap is a HARD CUT, not a blend: at each pixel the entity
// with the strongest (closest) claim wins outright — a Voronoi-style
// territory line rather than two auras mixing into a muddy colour. This
// matches the issue's lean toward cuts over blends for enemy-vs-owned
// boundaries (#74).

const int MAX_ENTITIES = 32;

// World-space tile binning (#177): circles and the tile→(offset,count) lookup
// live in data textures instead of a fixed-size uniform array, so the
// per-pixel loop only visits its own 3x3 tile neighbourhood — local circle
// DENSITY, not total circle count. See OverlayFieldTileIndex and
// docs/domain/overlay-field-rendering.md.
// TWO RGBAF texels per primitive: (ax, ay, ra, entity_index) then
// (bx, by, rb, unused) — OverlayFieldTileIndex.build_cones' layout. The name
// predates cones (#898) and is pinned by test_overlay_uniform_caps.gd.
uniform sampler2D circles_tex : filter_nearest, repeat_disable;
uniform sampler2D tile_index_tex : filter_nearest, repeat_disable;
// Flat bucket buffer wrapped to rows of textureSize(...).x texels (#898): a
// cone is bucketed into every cell its segment's AABB touches, so occupancy
// outgrows a single 16384-texel row at late-game scale.
uniform sampler2D tile_indices_tex : filter_nearest, repeat_disable;
uniform vec2 grid_origin = vec2(0.0);
uniform float cell_size = 0.0;
uniform int grid_cols = 0;
uniform int grid_rows = 0;
uniform int circle_count : hint_range(0, 100000) = 0;
uniform int entity_count : hint_range(0, 32) = 0;
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
	if (circle_count > 0 && cell_size > 0.0) {
		ivec2 centre_tile = ivec2(floor((world_pos - grid_origin) / cell_size));
		int indices_cols = textureSize(tile_indices_tex, 0).x;
		for (int dx = -1; dx <= 1; dx++) {
			for (int dy = -1; dy <= 1; dy++) {
				ivec2 tile = centre_tile + ivec2(dx, dy);
				if (tile.x < 0 || tile.x >= grid_cols || tile.y < 0 || tile.y >= grid_rows) {
					continue;
				}
				vec2 oc = texelFetch(tile_index_tex, tile, 0).rg;
				int offset = int(oc.x);
				int count = int(oc.y);
				for (int j = 0; j < count; j++) {
					int entry = offset + j;
					int idx = int(texelFetch(tile_indices_tex, ivec2(entry % indices_cols, entry / indices_cols), 0).r);
					vec4 ca = texelFetch(circles_tex, ivec2(idx * 2, 0), 0);
					vec4 cb = texelFetch(circles_tex, ivec2(idx * 2 + 1, 0), 0);
					// Projection dedupe (#897): a cone sits in every cell its
					// segment crosses, and field_smin is not idempotent, so it
					// contributes only from the tile owning the clamped
					// projection of this pixel onto its segment.
					vec2 q = field_cone_project(world_pos, ca.xy, cb.xy);
					if (ivec2(floor((q - grid_origin) / cell_size)) != tile) {
						continue;
					}
					int e = int(ca.w);
					float d = field_cone_distance(world_pos, ca.xy, max(ca.z, 1.0), cb.xy, max(cb.z, 1.0));
					// Same-entity union is smoothed: plain min() creases along
					// the seam between two of this entity's primitives,
					// reading as a Mach band.
					min_d[e] = field_smin(min_d[e], d, union_smoothness);
				}
			}
		}
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
