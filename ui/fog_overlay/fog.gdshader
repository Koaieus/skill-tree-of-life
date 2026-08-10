shader_type canvas_item;

#include "res://ui/overlay_field.gdshaderinc"
#include "res://ui/vision_field.gdshaderinc"

// World-space radial-cutout darkness mask.
//
// The circle-union darkness field itself (grid textures, falloff,
// union_smoothness) now lives in `vision_field.gdshaderinc` as GLOBAL
// uniforms — shared with any other self-shading consumer (e.g. `Edge`'s
// MultiMesh, see #413) instead of being local to this material. This shader
// keeps only what's actually its own: the frontier halo glow and the final
// opaque-darkness composite for whatever still relies on z-order to escape
// it (SkillNodes, pending their own #413-style follow-up).
//
// Visibility model (`range` = the circle's radius stat = the outer edge
// of any vision):
//   [center] -- 100% clear -- fade zone (clear→dark) -- HALO at d=1.0 -- pure black
//
// `falloff` is the fade-zone width as a fraction of the radius. The fade
// lives INSIDE the radius (between (1-falloff)·r and r); beyond r is pure
// black. Halo rides the outer edge — its inner side dips into the fade
// zone, its outer side dips into the dark zone, brightening both.

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
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
	// Re-walk the same tile neighbourhood `vision_field_darkness` does, only
	// to pick up `closest_motion` for the halo — the shared function doesn't
	// expose it since no other consumer needs the halo term.
	float min_d = 1e9;
	float closest_motion = 0.0;
	if (vision_circle_count > 0 && vision_cell_size > 0.0) {
		ivec2 centre_tile = ivec2(floor((world_pos - vision_grid_origin) / vision_cell_size));
		for (int dx = -1; dx <= 1; dx++) {
			for (int dy = -1; dy <= 1; dy++) {
				ivec2 tile = centre_tile + ivec2(dx, dy);
				if (tile.x < 0 || tile.x >= vision_grid_cols || tile.y < 0 || tile.y >= vision_grid_rows) {
					continue;
				}
				vec2 oc = texelFetch(vision_tile_index_tex, tile, 0).rg;
				int offset = int(oc.x);
				int count = int(oc.y);
				for (int j = 0; j < count; j++) {
					int idx = int(texelFetch(vision_tile_indices_tex, ivec2(offset + j, 0), 0).r);
					vec4 c = texelFetch(vision_circles_tex, ivec2(idx, 0), 0);
					float d = distance(world_pos, c.xy) / max(c.z, 1.0);
					min_d = field_smin(min_d, d, vision_union_smoothness);
					if (d < min_d + 1e-4) {
						closest_motion = c.w;
					}
				}
			}
		}
	}
	float dark = vision_field_darkness(world_pos);
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
	// Dither by ±half an 8-bit step: a fade this wide and this shallow would
	// otherwise quantize into evenly-spaced bands that smoothstep can't fix.
	alpha += (field_dither(FRAGCOORD.xy) - 0.5) / 255.0;
	vec3 color = glow_color * halo;
	COLOR = vec4(color, clamp(alpha, 0.0, 1.0));
}
