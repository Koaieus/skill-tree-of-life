shader_type canvas_item;

// ModSlabRow's visual (#343): dark fill, bright saturated stat-tint border
// reading as glowing — the PoE prefix/suffix-row reading surface, in dark
// mode. Size is pushed from SlabPanel.gd on _ready/resize since canvas_item
// shaders don't know Control rect size.
//
// The border stroke is painted INWARD only (d < 0), mirroring
// fused_panel.gdshader's proven #391 pattern — never the shape's own halo:
// this shader has no way to paint anything past d == 0, because a
// canvas_item shader only ever runs within its Control's own rect, which has
// zero margin around the visible shape. An outward "halo" term (d > 0) tried
// here once; it only had room to exist in the sliver between a rounded
// corner's arc and the Control's own square corner, so at any real
// glow_strength it read as a glow confined to (and clipped hard at) the
// bounding box's corners — not rounded, not bleeding past the edge. The
// actual outward bleed a bloom-lit border reads as comes from the engine's
// bloom pass — a screen-space post-process over the whole composited frame,
// unconstrained by any one node's clip rect — not from this shader painting
// extra geometry. See docs/domain/hdr-color.md.
uniform vec2 size = vec2(160.0, 22.0);

// The stat's tint. Everything else derives from this one colour.
uniform vec4 tint_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
// 0 = fill is the raw tint, 1 = fill is near-black with only a hint of hue.
uniform float fill_darkness : hint_range(0.0, 1.0, 0.01) = 0.88;
// 0 = stroke invisible; 1 = fully blended in. Shape/opacity knob only — see
// glow_energy for whether the stroke is hot enough to actually bloom.
uniform float glow_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
// EV stops (see Emissive, docs/domain/hdr-color.md) the stroke is lifted by
// before bloom sees it. Fill stays SDR so the dark background never blooms.
// Defaults to Emissive.VALUE (1.0); the mix below reproduces Emissive.tint()
// by hand (source_color already decoded tint_color to linear, so a Rec.709
// luminance divide + pow(2, stops) is the whole conversion — same trick as
// rim_ring.gdshader's #389 fix, extended 2026-08-08 with the luminance
// normalization: a raw pow(2, stops) lift on tint_color made equal stops
// bloom by very different amounts across archetype hues (a blue-dominant
// tint like INT's reads far dimmer than its max channel suggests — Rec.709
// discounts blue 10x against green), so the hue is rescaled to unit
// luminance before the stop lift, same as Emissive.tint().
uniform float glow_energy : hint_range(0.0, 3.0, 0.05) = 1.0;

// Rec.709 luma weights — must match ui/theme/emissive.gd's Emissive.tint().
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
// How deep the bright stroke fades into the interior, in pixels. Judge this
// against the *rendered* pixel footprint at the row's actual on-screen
// size, not a number that merely looks right zoomed in — bloom's wider mips
// need real screen-pixel coverage to accumulate on (docs/domain/hdr-color.md).
uniform float glow_width : hint_range(0.5, 8.0, 0.1) = 2.5;
uniform float corner_radius : hint_range(0.0, 12.0, 0.5) = 4.0;

#include "res://ui/theme/round_rect.gdshaderinc"

void fragment() {
	vec2 half_size = size * 0.5;
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	float d = rr_distance(UV * size - half_size, half_size, radius);

	// Fill: tint darkened toward a near-black neutral — the "very dark
	// desaturated version of the stat tint" (#343). Faint hue survives at
	// fill_darkness 0.85+ so rows still whisper their stat's colour. Stays
	// SDR — only the stroke below carries the HDR lift.
	vec3 fill = mix(tint_color.rgb, vec3(0.03, 0.04, 0.05), fill_darkness);
	// Luminance-normalized before the lift (Emissive.tint(), not .at()) so
	// equal glow_energy reads as equal glow regardless of the stat tint's hue
	// — see the uniform's comment above.
	float luminance = max(dot(tint_color.rgb, LUMA), 0.0001);
	vec3 hot_tint = (tint_color.rgb / luminance) * pow(2.0, glow_energy);

	// Inward stroke hugging the edge, HDR-lifted so it actually clears bloom
	// threshold. `-d` keeps this entirely inside the shape (d < 0 only) —
	// see the file header for why an outward term can't work here.
	float stroke = 1.0 - smoothstep(0.0, glow_width, -d);
	vec3 col = mix(fill, hot_tint, stroke * glow_strength);

	COLOR = vec4(col, rr_coverage(d));
}
