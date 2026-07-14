shader_type canvas_item;

// Soft cloudy nebula tint for the deep-space backdrop. Like starfield.gdshader
// it draws in local UV so a Parallax2D can repeat + scroll it; kept as its own
// (non-additive) layer so it reads as diffuse colour behind the stars. Output
// is transparent where the cloud mask is thin, letting the flat base show.

uniform vec4 color_a : source_color = vec4(0.13, 0.05, 0.30, 1.0);
uniform vec4 color_b : source_color = vec4(0.02, 0.11, 0.22, 1.0);
uniform float strength : hint_range(0.0, 1.5) = 0.5;
uniform float scale : hint_range(0.5, 8.0) = 2.5;
// Below this the cloud fades to transparent; above, it saturates.
uniform float threshold : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * scale;
	float mask = smoothstep(threshold, threshold + 0.28, fbm(p));
	vec3 tint = mix(color_a.rgb, color_b.rgb, fbm(p * 2.0 + 11.0));
	float a = clamp(mask * strength, 0.0, 1.0);
	COLOR = vec4(tint, a);
}
