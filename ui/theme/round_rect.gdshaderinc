// Shared rounded-rect helpers for the Arcane Terminal panel skins
// (fused_panel.gdshader, holo_panel.gdshader, glass_panel.gdshader).
//
// Parameter names are deliberately underscore-prefixed: Godot's shader codegen
// rewrites *uniform tokens* even inside included function bodies, so a param
// named `size` or `corner_radius` would be silently substituted at the call
// site's uniform. See .claude/rules/godot-workflow.md.

// Signed distance to a rounded rect centred on the origin. Negative inside.
float rr_distance(vec2 _p, vec2 _half_size, float _radius) {
	vec2 _q = abs(_p) - _half_size + _radius;
	return length(max(_q, 0.0)) + min(max(_q.x, _q.y), 0.0) - _radius;
}

// Outward unit normal of the nearest point on the rounded-rect boundary.
//
// Along a flat side this is the axis normal; across a corner it sweeps
// smoothly through 90 degrees. That sweep is the whole point: it is what lets
// per-edge selection follow the ARC rather than the rectangle the arc was cut
// from. Everything inside the corner-centre rect (only reachable at radius ~0)
// falls back to the dominant-axis face normal, which is the true SDF gradient
// there.
vec2 rr_normal(vec2 _p, vec2 _half_size, float _radius) {
	vec2 _core = max(_half_size - vec2(_radius), vec2(0.0));
	vec2 _v = _p - clamp(_p, -_core, _core);
	float _len = length(_v);
	if (_len > 0.0001) {
		return _v / _len;
	}
	vec2 _q = abs(_p) - _half_size;
	if (_q.x > _q.y) {
		return vec2(_p.x >= 0.0 ? 1.0 : -1.0, 0.0);
	}
	return vec2(0.0, _p.y >= 0.0 ? 1.0 : -1.0);
}

// Per-edge glow selection, as a partition of unity over the boundary normal.
// `_edges` is the bit mask 1=top, 2=right, 4=bottom, 8=left.
//
// Each edge owns the normals nearest its own axis, and the two edges meeting
// at a corner hand over across the 45-degree bisector. Consequences that the
// old "distance from each rectangular edge" selector got wrong:
//
//   * all four edges lit -> the terms sum to exactly 1 everywhere on the
//     boundary, INCLUDING the corner arcs (no dim, semi-transparent corners);
//   * one edge lit -> the glow fades out smoothly along the corner arc instead
//     of capping the corner with a rectangular L-bracket.
//
// `_softness` is the hand-over width in normal-space (the terms range over
// [-1, 1]); ~0.35 blends across roughly the middle third of the arc.
float rr_edge_select(vec2 _n, int _edges, float _softness) {
	float _sel = 0.0;
	if ((_edges & 1) != 0) _sel += smoothstep(-_softness, _softness, -_n.y - abs(_n.x));
	if ((_edges & 2) != 0) _sel += smoothstep(-_softness, _softness, _n.x - abs(_n.y));
	if ((_edges & 4) != 0) _sel += smoothstep(-_softness, _softness, _n.y - abs(_n.x));
	if ((_edges & 8) != 0) _sel += smoothstep(-_softness, _softness, -_n.x - abs(_n.y));
	return clamp(_sel, 0.0, 1.0);
}

// Coverage of the rounded rect at this fragment, anti-aliased over one screen
// pixel. Uses fwidth rather than a fixed distance so the edge stays exactly as
// crisp when the panel is scaled — the fan tweens panels from 0.82 to 1.0 on
// reveal, where a fixed-width AA band visibly thickens.
float rr_coverage(float _d) {
	float _aa = max(fwidth(_d) * 0.5, 0.0001);
	return 1.0 - smoothstep(-_aa, _aa, _d);
}
