shader_type canvas_item;

// The reference shard look (#835): a flat disc in the shard's tint, cut into
// Voronoi cells with a small gap at the seams so the cracks read at spawn.
// Consumers do not use this — #787 draws a blade wedge's fill + rim and #257
// re-runs the InnerDisk dome inside the cell — but every one of them is this
// file with a different body: `SHATTER_VERTEX` in vertex(), then in
// fragment() unspin -> cell test -> your look -> `shatter_fade()`.
#include "res://ui/vfx/shatter/shatter_motion.gdshaderinc"

// Gap between shards at the seams, in disc-radius units.
uniform float seam_gap : hint_range(0.0, 0.2) = 0.03;

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
	c.a *= shape;
	COLOR = shatter_fade(c, prog);
}
