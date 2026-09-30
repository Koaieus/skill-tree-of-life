// A Gate's flip rope — closed-form, no baking. See graph/gate_rope.gd.
//
// The strip is two ropes of SEGMENTS quads each, laid out in the rope's local
// frame: origin at the thrower's rim, +x toward the far node, `span_px` long.
// UV.x in [0,1] is rope 0 (anchored at the thrower, x = 0), UV.x in [2,3] is
// rope 1 (anchored at the far node, x = span); UV.y is the side (0 / 1). Each
// rope samples the shared centreline y(u), u in [0,1] along the span, so the
// two always meet on one curve. Mode: 0 single throw, 1 handshake, 2 snap.
shader_type canvas_item;

uniform int mode = 0;
uniform float t = 0.0;
uniform float span_px = 100.0;
uniform float width : hint_range(0.0, 32.0) = 3.0;
uniform float throw_duration = 0.22;
uniform float sag = 0.25;
uniform float thwang_amplitude = 0.08;
uniform float decay_tau = 0.35;
uniform float omega = 56.5;
uniform float harmonic2_mix = 0.2;
uniform float snap_duration = 0.18;
uniform float snap_whip = 0.15;
uniform float fade = 1.0;
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
// Same screen-constant width as graph/edge_mesh.gdshader, so the rope matches
// the edge it crossfades into.
global uniform float edge_camera_zoom;

varying float v_side;
varying float v_u;
varying float v_alpha;

const float AA_PAD = 1.5;

float ease_out(float x) {
	float k = 1.0 - clamp(x, 0.0, 1.0);
	return 1.0 - k * k * k;
}

// Perpendicular displacement (px) of the centreline at span parameter u.
// `arch` is the rope's own arch parameter — equal to u once the rope is whole.
float centre_y(float u, float arch) {
	if (mode == 2) {
		return 0.0;
	}
	float L = span_px;
	if (t < throw_duration) {
		float p = ease_out(t / throw_duration);
		// Trailing sag hands over to the thwang's opening displacement at the
		// latch, so the pull-tight starts where the throw left off.
		return L * (sag * (1.0 - p) + thwang_amplitude * p) * sin(PI * arch);
	}
	float t2 = t - throw_duration;
	float env = L * thwang_amplitude * exp(-t2 / max(decay_tau, 0.0001));
	return env * (sin(PI * u) * cos(omega * t2)
		+ harmonic2_mix * sin(TAU * u) * sin(2.0 * omega * t2));
}

// Centreline point of rope `k` at its own parameter s in [0,1] (0 = anchor).
// `alive` goes to 0 on a rope that does not draw in this mode.
vec2 rope_point(int k, float s, out float alive) {
	float L = span_px;
	alive = 1.0;
	float p_throw = ease_out(t / max(throw_duration, 0.0001));
	if (mode == 2) {
		float p = ease_out(t / max(snap_duration, 0.0001));
		float len = 0.5 * (1.0 - p);
		float u = k == 0 ? s * len : 1.0 - s * len;
		// Each half whips back: the free end flails, most at mid-snap.
		float whip = L * snap_whip * s * s * sin(PI * p) * (k == 0 ? 1.0 : -1.0);
		return vec2(u * L, whip);
	}
	float u;
	float arch;
	if (mode == 1) {
		float reach = 0.5 * p_throw;
		u = k == 0 ? s * reach : 1.0 - s * reach;
		arch = k == 0 ? s * 0.5 : 1.0 - s * 0.5;
	} else {
		if (k == 1) {
			alive = 0.0;
			return vec2(0.0);
		}
		u = s * p_throw;
		arch = s;
	}
	return vec2(u * L, centre_y(u, arch));
}

void vertex() {
	int k = UV.x > 1.5 ? 1 : 0;
	float s = UV.x - float(k) * 2.0;
	float side = UV.y * 2.0 - 1.0;
	float alive;
	vec2 p0 = rope_point(k, s, alive);
	float s1 = s < 0.99 ? s + 0.01 : s - 0.01;
	float dummy;
	vec2 p1 = rope_point(k, s1, dummy);
	vec2 dir = (s < 0.99 ? p1 - p0 : p0 - p1);
	if (k == 1) {
		dir = -dir;
	}
	dir = length(dir) > 0.0001 ? normalize(dir) : vec2(1.0, 0.0);
	vec2 n = vec2(-dir.y, dir.x);
	float half_w = (width * 0.5 + AA_PAD) / max(edge_camera_zoom, 0.0001);
	VERTEX = p0 + n * side * half_w * alive;
	v_side = side;
	v_u = clamp(p0.x / max(span_px, 0.0001), 0.0, 1.0);
	float snap_fade = mode == 2 ? 1.0 - clamp(t / max(snap_duration, 0.0001), 0.0, 1.0) : 1.0;
	v_alpha = alive * fade * snap_fade;
}

void fragment() {
	float half_w = width * 0.5;
	float d = abs(v_side) * (half_w + AA_PAD) - half_w;
	float aa = max(fwidth(d), 0.0001);
	float shape_alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);
	vec4 c = mix(color_a, color_b, v_u);
	COLOR = vec4(c.rgb, c.a * v_alpha * shape_alpha);
}
