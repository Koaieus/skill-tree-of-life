// Shared helpers for the world-space circle-field overlays (fog.gdshader,
// aura.gdshader).
//
// Parameter names are deliberately underscore-prefixed: Godot's shader codegen
// rewrites *uniform tokens* even inside included function bodies, so a param
// named `falloff` or `intensity` would be silently substituted at the call
// site's uniform. See .claude/rules/godot-workflow.md.

// Polynomial smooth-minimum. Unions two distance fields without the C1 crease
// that plain min() leaves along the seam between two circles — that crease is
// what reads as a Mach band inside the fade ring.
//
// `_k` is the blend width in normalized-distance units; 0 degrades to min().
float field_smin(float _a, float _b, float _k) {
	if (_k <= 0.0) {
		return min(_a, _b);
	}
	float _h = clamp(0.5 + 0.5 * (_b - _a) / _k, 0.0, 1.0);
	return mix(_b, _a, _h) - _k * _h * (1.0 - _h);
}

// ---------------------------------------------------------------------------
// Rounded-cone primitive (#897). GLSL twin of ui/overlay_field_cone.gd — the
// derivation, the nested-cone counterexample and the NaN guard are all
// documented there, and test_overlay_field_cone.gd pins the CPU side against a
// brute-force sample of the definition. Keep the two line-for-line equivalent.
// ---------------------------------------------------------------------------

// Normalized distance to the cone (_a, _ra) -> (_b, _rb):
//   d(p) = min over t in [0,1] of |p - lerp(_a,_b,t)| / lerp(_ra,_rb,t)
// so d == 1 is the hull of the two discs, and d reduces to |p-_a|/_ra at the
// ends — the same units field_smin and the falloff fade already consume.
//
// A degenerate cone (_a == _b, _ra == _rb) is exactly the disc field, which is
// how isolated owned nodes ship: one primitive type, one shader path.
float field_cone_distance(vec2 _p, vec2 _a, float _ra, vec2 _b, float _rb) {
    vec2 _pa = _p - _a;
    vec2 _ba = _b - _a;
    float _rd = _rb - _ra;
    float _l2 = dot(_ba, _ba);
    float _pp = dot(_pa, _ba);
    float _den = _l2 * _ra + _rd * _pp;
    // Guard before dividing: a disc gives 0.0/0.0, and clamp(NaN) is undefined.
    float _t = 0.0;
    if (_l2 > 0.0 && abs(_den) > 1e-8) {
        _t = clamp((_rd * dot(_pa, _pa) + _ra * _pp) / _den, 0.0, 1.0);
    }
    // The end discs are not a fallback: the stationary point _t can lie past
    // the pole of the ratio (one disc nested in the other), where clamping it
    // into [0,1] lands on the wrong endpoint.
    float _d = min(length(_pa) / _ra, length(_p - _b) / _rb);
    return min(_d, length(_pa - _ba * _t) / (_ra + _rd * _t));
}

// Clamped orthogonal projection of _p onto the segment _a -> _b. This is the
// point the tile index buckets for the projection-dedupe rule (a primitive
// contributes only from the tile whose cell contains it) — NOT the argmin of
// field_cone_distance above. See OverlayFieldTileIndex.
vec2 field_cone_project(vec2 _p, vec2 _a, vec2 _b) {
    vec2 _ba = _b - _a;
    float _l2 = dot(_ba, _ba);
    if (_l2 <= 0.0) {
        return _a;
    }
    return _a + _ba * clamp(dot(_p - _a, _ba) / _l2, 0.0, 1.0);
}

// Cheap per-pixel hash in [0,1). Used to dither the final alpha by ±half a
// quantization step, which breaks up the 8-bit stair-stepping a wide, shallow
// distance fade would otherwise show as evenly-spaced bands.
float field_dither(vec2 _p) {
	return fract(sin(dot(_p, vec2(12.9898, 78.233))) * 43758.5453);
}
