// A staking channel's live lasso — closed-form, animated by TIME only. See
// ui/vfx/channel_lasso/channel_lasso.gd.
//
// One rope of RopeStrip quads: UV.x = u in [0,1] from the core end (0) to the
// channelling node (1), UV.y the side. The baked vertices are ignored; every
// vertex is rebuilt from the endpoint uniforms, in the lasso's local frame.
shader_type canvas_item;

#include "res://ui/vision_field.gdshaderinc"

uniform vec2 from_pos = vec2(0.0);
uniform vec2 to_pos = vec2(100.0, 0.0);
// 0 slack (core close) → 1 taut (core at the leash).
uniform float tension : hint_range(0.0, 1.0) = 0.0;
uniform float width : hint_range(0.0, 32.0) = 2.5;
uniform float segments = 24.0;
uniform float slack_amplitude = 0.12;
uniform float taut_amplitude = 0.02;
uniform float wave_hz = 1.2;
uniform float crackle_slack = 0.1;
uniform float crackle_taut = 0.8;
// +1 pulses run core → node, −1 node → core, 0 none.
uniform float direction = 1.0;
uniform float pulse_speed = 0.6;
uniform float pulse_spacing = 0.25;
uniform float pulse_strength = 0.5;
uniform vec4 color : source_color = vec4(1.0);
uniform vec4 pulse_color : source_color = vec4(1.0);
// Same screen-constant width as graph/edge_mesh.gdshader.
global uniform float edge_camera_zoom;

varying float v_side;
varying float v_u;
varying vec2 world_pos;

const float AA_PAD = 1.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453) * 2.0 - 1.0;
}

void vertex() {
	float u = clamp(UV.x, 0.0, 1.0);
	float side = UV.y * 2.0 - 1.0;
	vec2 span = to_pos - from_pos;
	float L = length(span);
	vec2 dir = L > 0.0001 ? span / L : vec2(1.0, 0.0);
	vec2 n = vec2(-dir.y, dir.x);
	float amp = L * mix(slack_amplitude, taut_amplitude, tension);
	float w = TAU * wave_hz * TIME;
	// A whip travelling along the rope, plus a slower second harmonic so the
	// slack never reads as a metronome.
	float wave = sin(w - u * PI * 1.5) + 0.35 * sin(TAU * u) * sin(0.5 * w + 1.3);
	// Per-vertex jitter re-rolled ~24×/s: the crackle that grows with tension.
	float jitter = hash(vec2(floor(u * segments + 0.5), floor(TIME * 24.0)));
	float crackle = mix(crackle_slack, crackle_taut, tension);
	float disp = amp * sin(PI * u) * mix(wave, jitter, crackle);
	float half_w = (width * 0.5 + AA_PAD) / max(edge_camera_zoom, 0.0001);
	VERTEX = from_pos + span * u + n * (disp + side * half_w);
	v_side = side;
	v_u = u;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float half_w = width * 0.5;
	float d = abs(v_side) * (half_w + AA_PAD) - half_w;
	float aa = max(fwidth(d), 0.0001);
	float shape_alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);
	// Pulses travel in the action's direction: a sharp head, a fading tail.
	float coord = direction < 0.0 ? 1.0 - v_u : v_u;
	float phase = fract((coord - TIME * pulse_speed) / max(pulse_spacing, 0.001));
	float pulse = abs(direction) > 0.5 ? pow(phase, 6.0) : 0.0;
	vec4 c = mix(color, pulse_color, pulse * pulse_strength);
	COLOR = vec4(c.rgb, c.a * shape_alpha * vision_field_dim(world_pos));
}
