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

// Cheap per-pixel hash in [0,1). Used to dither the final alpha by ±half a
// quantization step, which breaks up the 8-bit stair-stepping a wide, shallow
// distance fade would otherwise show as evenly-spaced bands.
float field_dither(vec2 _p) {
	return fract(sin(dot(_p, vec2(12.9898, 78.233))) * 43758.5453);
}
