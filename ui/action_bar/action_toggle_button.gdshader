shader_type canvas_item;

uniform vec2 mouse_uv;
uniform vec3 tint : source_color;
uniform float glow_radius : hint_range(0.0, 1.0) = 0.3;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float active_strength : hint_range(0.0, 1.0) = 0.0;

const vec4 GLOW_COLOR = vec4(1.0);

void fragment() {
	float d = distance(UV, mouse_uv);
	float falloff = 1.0 - smoothstep(0.0, glow_radius, d);
	float glow = falloff * max(glow_strength, active_strength);
	vec3 base = tint * 0.5 + vec3(active_strength) * 0.3;
	COLOR = mix(vec4(base, 1.0), GLOW_COLOR, glow);
}
