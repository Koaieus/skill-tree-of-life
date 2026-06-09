shader_type canvas_item;

uniform vec2 mouse_uv;
uniform ivec2 texture_size = ivec2(1);
uniform vec3 tint : source_color;
uniform float glow_radius : hint_range(0.0, 1.0) = 0.3;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float active_strength : hint_range(0.0, 1.0) = 0.0;
uniform float disabled_strength : hint_range(0.0, 1.0) = 0.0;



const vec4 GLOW_COLOR = vec4(1.0);
const float DISABLED_DARKENING = 0.8;

void fragment() {
	float aspect = float(texture_size.x) / float(texture_size.y);
	vec2 corrected_uv = vec2(UV.x * aspect, UV.y);
	vec2 corrected_mouse = vec2(mouse_uv.x * aspect, mouse_uv.y);
	
	float d = distance(corrected_uv, corrected_mouse);
	float falloff = 1.0 - smoothstep(0.0, glow_radius, d);
	float glow = falloff * max(glow_strength, active_strength) * mix(0.2, 1.0, 1. - disabled_strength);
	vec3 base = tint * 0.5 + vec3(active_strength) * 0.3;
	base *= 1. - disabled_strength * DISABLED_DARKENING;
	COLOR = mix(vec4(base, 1.0), GLOW_COLOR, glow);
}
