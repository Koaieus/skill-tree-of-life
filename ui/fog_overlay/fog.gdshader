shader_type canvas_item;

#include "res://ui/overlay_field.gdshaderinc"

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

// World-space tile binning (#177): circles and the tile→(offset,count) lookup
// live in data textures instead of a fixed-size uniform array, so the
// per-pixel loop only visits its own 3x3 tile neighbourhood — local circle
// DENSITY, not total circle count. See OverlayFieldTileIndex and
// docs/domain/overlay-field-rendering.md.
uniform sampler2D circles_tex : filter_nearest, repeat_disable;
uniform sampler2D tile_index_tex : filter_nearest, repeat_disable;
uniform sampler2D tile_indices_tex : filter_nearest, repeat_disable;
uniform vec2 grid_origin = vec2(0.0);
uniform float cell_size = 0.0;
uniform int grid_cols = 0;
uniform int grid_rows = 0;
uniform int circle_count = 0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// Fraction of radius the gradient extends BEYOND the edge. 0 = hard cut,
// 0.5 = fade zone equal to half the radius, etc.
uniform float falloff : hint_range(0.0, 1.0) = 0.25;
// Half-width of the frontier halo, in normalized distance units. The halo
// is a band centered on the circle's edge (d == 1.0). 0 disables it.
uniform float glow_band : hint_range(0.0, 0.5) = 0.08;
uniform vec3 glow_color : source_color = vec3(1.0, 0.9, 0.6);
uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;
// Blend width of the smooth union between overlapping vision circles, in
// normalized-distance units. 0 = plain min() (creased seams, visible as bands).
uniform float union_smoothness : hint_range(0.0, 0.5) = 0.12;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// `min_d` is the SMOOTH union of the circle fields — plain min() leaves a
	// derivative crease along each pair's seam, which the eye reads as a band.
	// `hard_min` keeps the true nearest circle, only to pick its motion value.
	float min_d = 1e9;
	float hard_min = 1e9;
	float closest_motion = 0.0;
	if (circle_count > 0 && cell_size > 0.0) {
		ivec2 centre_tile = ivec2(floor((world_pos - grid_origin) / cell_size));
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
					int idx = int(texelFetch(tile_indices_tex, ivec2(offset + j, 0), 0).r);
					vec4 c = texelFetch(circles_tex, ivec2(idx, 0), 0);
					float d = distance(world_pos, c.xy) / max(c.z, 1.0);
					min_d = field_smin(min_d, d, union_smoothness);
					if (d < hard_min) {
						hard_min = d;
						closest_motion = c.w;
					}
				}
			}
		}
	}
	// Darkness: 0 inside the clear zone, smooth 0→1 ramp across the fade zone
	// (between (1-falloff) and 1), pinned at 1 beyond the radius. `falloff` is
	// still a pure width knob; smoothstep only reshapes the ramp so its slope
	// is continuous at both ends — a linear ramp's slope discontinuity there
	// is what produced the Mach bands.
	float fade_start = 1.0 - max(falloff, 1e-4);
	float dark = smoothstep(fade_start, 1.0, min_d);
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
