shader_type canvas_item;

// ModSlabRow's visual (#343): dark fill, bright saturated stat-tint border
// reading as glowing, and a soft tint halo — the PoE prefix/suffix-row
// reading surface, in dark mode. Size is pushed from SlabPanel.gd on
// _ready/resize since canvas_item shaders don't know Control rect size.

uniform vec2 size = vec2(160.0, 22.0);

// The stat's tint. Everything else derives from this one colour.
uniform vec4 tint_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
// 0 = fill is the raw tint, 1 = fill is near-black with only a hint of hue.
uniform float fill_darkness : hint_range(0.0, 1.0, 0.01) = 0.88;
// 0 = hairline border, no halo; 1 = strong glow.
uniform float glow_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
// Width of the bright inner border band, in pixels.
uniform float border_width : hint_range(0.5, 4.0, 0.1) = 1.5;
// How far the halo bleeds outward past the edge, in pixels.
uniform float glow_width : hint_range(1.0, 10.0, 0.5) = 5.0;
uniform float corner_radius : hint_range(0.0, 12.0, 0.5) = 4.0;

#include "res://ui/theme/round_rect.gdshaderinc"

void fragment() {
	vec2 half_size = size * 0.5;
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	float d = rr_distance(UV * size - half_size, half_size, radius);

	// Fill: tint darkened toward a near-black neutral — the "very dark
	// desaturated version of the stat tint" (#343). Faint hue survives at
	// fill_darkness 0.85+ so rows still whisper their stat's colour.
	vec3 fill = mix(tint_color.rgb, vec3(0.03, 0.04, 0.05), fill_darkness);

	// Border: bright full-strength tint hugging the inner edge.
	float border = 1.0 - smoothstep(0.0, border_width, -d);
	vec3 col = mix(fill, tint_color.rgb, border);

	// Glow: tint halo bleeding outward past the edge.
	float halo = 1.0 - smoothstep(0.0, glow_width, d);
	col += tint_color.rgb * halo * glow_strength;

	float a = rr_coverage(d) + halo * glow_strength;
	COLOR = vec4(col, min(a, 1.0));
}
