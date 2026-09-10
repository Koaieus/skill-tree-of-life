shader_type canvas_item;

// Blade-pop shard look (#787): reproduces `blade_circle.gd`'s fill disc + rim
// band inside each Voronoi wedge #835's ShatterField cuts the dying vertex
// into, so a wedge reads as "a slice of the vertex that died" rather than the
// generic flat-tint reference shard. Copied from
// `ui/vfx/shatter/shatter_shard.gdshader`; the only difference is the two-band
// fragment below in place of one flat colour.
#include "res://ui/vfx/shatter/shatter_motion.gdshaderinc"

// Gap between shards at the seams, in disc-radius units — same knob as the
// reference shard.
uniform float seam_gap : hint_range(0.0, 0.2) = 0.03;
// BladeNode's inner_radius / radius ratio (0.75 = the 24/32 default). A
// MATERIAL uniform, not per-shard: most blade vertices share one ratio, and
// there is no spare INSTANCE_CUSTOM channel to carry a per-shard one (see
// ShatterField's class docs on the half-float packing budget) — a vertex
// whose source SkillNode allocated a different radius/inner_radius pair reads
// slightly off until a per-shard channel exists. Not gated by any test; the
// look is judged in the sandbox.
uniform float inner_frac : hint_range(0.0, 1.0) = 0.75;
// EV stops the rim sits above the fill, mirroring BladeStyle's
// `rim_tier - fill_tier` (VALUE - LABEL = 0.5 by default).
uniform float rim_lift_stops : hint_range(0.0, 4.0) = 0.5;
// Alpha the FILL band draws at, mirroring `BladeStyle.fill_alpha`. The rim
// band stays fully opaque, same as BladeCircle.
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.7;

void vertex() {
	SHATTER_VERTEX;
}

void fragment() {
	ShatterShard s = shatter_shard();
	float prog = shatter_progress(s);
	vec2 p = shatter_unspin(shatter_disc_point(), s, prog);
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float margin = shatter_cell_margin(p, s);
	if (margin < 0.0) {
		discard;
	}
	float seam_aa = max(fwidth(margin), 0.0001);
	float rim_aa = max(fwidth(r), 0.0001);
	float shape = smoothstep(seam_gap, seam_gap + seam_aa, margin)
			* (1.0 - smoothstep(1.0 - rim_aa, 1.0, r));

	vec4 c = COLOR;
	float band_aa = max(fwidth(r), 0.0001);
	float is_rim = smoothstep(inner_frac - band_aa, inner_frac + band_aa, r);
	c.rgb *= mix(1.0, exp2(rim_lift_stops), is_rim);
	c.a *= mix(fill_alpha, 1.0, is_rim);
	c.a *= shape;
	COLOR = shatter_fade(c, prog);
}
